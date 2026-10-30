import '../commands/expand_command.dart' show CommandRef;
import '../llm/messages.dart';
import '../loop/agent_events.dart';
import '../tools/agent_tool.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import '../util/logger.dart';
import 'ids.dart';
import 'records.dart';
import 'session_store.dart';
import 'tree.dart';
import 'user_words.dart';

/// Собирает запись по выданным писателем id, родителю и времени.
typedef RecordBuilder<R extends SessionRecord> =
    R Function(String id, String? parentId, DateTime timestamp);

/// Писатель журнала одной сессии (`agent-core-architecture` §8.3).
///
/// Почему подписчик, а не вызовы из цикла: цикл только эмитит события и не
/// знает о хранилище (LOOP-6, «хост сохраняет, цикл эмитит»). Писатель
/// стоит первым подписчиком `Agent`, а цикл ждёт каждого `emit` (LOOP-2),
/// поэтому сообщение записано до следующего действия цикла (SES-8).
///
/// Для чего: держит текущий лист и снимок журнала в памяти, выдаёт id
/// записей, проставляет `parentId` и время и пишет записи по таблице §8.3.
/// Результат инструмента пишется с `durable` (SES-9), конец хода — сброс.
///
/// Как использовать: сессия создаёт писателя над снимком (новым или
/// открытым), вызывает [handle] для каждого события и [append] — для своих
/// записей (`model_change`, синтетические результаты). Ошибка записи не
/// бросается наружу: писатель логирует `session.append.failed`, зовёт
/// [onFailure] и до конца хода больше ничего не пишет.
final class SessionWriter {
  SessionWriter({
    required SessionStore store,
    required SessionSnapshot snapshot,
    required IdGenerator ids,
    required Clock clock,
    required Logger logger,
    required void Function(Object error) onFailure,
  }) : _store = store,
       _snapshot = snapshot,
       _ids = ids,
       _clock = clock,
       _logger = logger,
       _onFailure = onFailure;

  final SessionStore _store;
  final IdGenerator _ids;
  final Clock _clock;
  final Logger _logger;
  final void Function(Object error) _onFailure;
  SessionSnapshot _snapshot;

  /// Служебные сообщения: `origin` приходит в `MessageStarted`, а запись
  /// пишется на `MessageEnded` того же сообщения.
  final _origins = Expando<MessageOrigin>();

  /// Исходные команды развёрнутых сообщений: сессия помечает сообщение до
  /// хода, запись пишется на `MessageEnded` того же объекта (design.md change
  /// `add-agent-project-files`, D8).
  final _commands = Expando<CommandRef>();
  final _meta = <String, ToolMeta>{};
  final _finished = <String, ToolCallFinished>{};

  /// Ход, запись которого не удалась: до следующего `TurnStarted` писатель
  /// молчит, иначе в журнале появились бы записи с пропуском посередине.
  var _failed = false;

  SessionId get _id => _snapshot.header.id;

  /// Запоминает, что [message] получено разворачиванием [command]: его запись
  /// получит поле `command`. Вызывается до `Agent.prompt`.
  void noteCommand(Message message, CommandRef command) =>
      _commands[message] = command;

  /// Журнал в памяти после последней успешной записи.
  SessionSnapshot get snapshot => _snapshot;

  Future<void> handle(AgentEvent event) async {
    if (event is TurnStarted) {
      _failed = false;
    }
    if (_failed) {
      return;
    }
    switch (event) {
      case MessageStarted(:final message, origin: final origin?):
        _origins[message] = origin;
      case MessageEnded(message: final ToolResultMessage result):
        final finished = _finished.remove(result.toolCallId);
        final diffs = finished?.diffs ?? const <FileDiff>[];
        await _write(
          (id, parent, at) => MessageRecord(
            id: id,
            parentId: parent,
            timestamp: at,
            message: result,
            outcome: finished?.outcome.name,
            diff: diffs.length == 1 ? diffs.single : null,
            toolMeta: _meta.remove(result.toolCallId),
          ),
          durable: true,
        );
      case MessageEnded(:final message):
        final origin = _origins[message];
        final fields = origin == null ? null : originFieldsOf(origin);
        await _write(
          (id, parent, at) => MessageRecord(
            id: id,
            parentId: parent,
            timestamp: at,
            message: message,
            origin: fields?.origin,
            nudge: fields?.nudge,
            attempt: fields?.attempt,
            command: _commands[message],
          ),
        );
      case ToolCallStarted(
        :final toolCallId,
        :final title,
        :final kind,
        :final locations,
      ):
        _meta[toolCallId] = ToolMeta(
          title: title,
          kind: kind,
          locations: locations,
        );
      case ToolCallFinished(:final toolCallId):
        _finished[toolCallId] = event;
      case ModeChanged(:final mode):
        await _write(
          (id, parent, at) => ModeChangeRecord(
            id: id,
            parentId: parent,
            timestamp: at,
            modeId: mode.value,
          ),
        );
      case PlanUpdated(:final entries):
        await _write(
          (id, parent, at) => PlanRecord(
            id: id,
            parentId: parent,
            timestamp: at,
            entries: entries,
          ),
        );
      case SessionTitleChanged(:final title):
        await _write(
          (id, parent, at) => SessionInfoRecord(
            id: id,
            parentId: parent,
            timestamp: at,
            title: title,
            source: 'auto',
          ),
        );
      case TurnEnded():
        await _guard(() => _store.flush(_id));
      default:
        break;
    }
  }

  /// Пишет запись сессии; ошибка хранилища уходит вызывающему, снимок при
  /// этом не меняется.
  Future<R> append<R extends SessionRecord>(
    RecordBuilder<R> build, {
    bool durable = false,
  }) async {
    final record = build(
      newRecordId(_ids, _snapshot.byId.containsKey),
      _snapshot.leafId,
      _clock.now(),
    );
    await appendBuilt(record, durable: durable);
    return record;
  }

  /// Пишет уже собранную запись (синтетические результаты §8.8).
  Future<void> appendBuilt(SessionRecord record, {bool durable = false}) async {
    await _store.append(_id, record, durable: durable);
    // Порядок «файл → индекс»: снимок меняется только после записи (§8.5).
    _snapshot = _snapshot.withRecord(record, leafAfter(record));
  }

  Future<void> _write(RecordBuilder build, {bool durable = false}) =>
      _guard(() => append(build, durable: durable));

  Future<void> _guard(Future<void> Function() write) async {
    try {
      await write();
    } on Object catch (error, stack) {
      _failed = true;
      _logger.log(
        LogLevel.error,
        'session.append.failed',
        fields: {'session_id': _id.value},
        error: error,
        stack: stack,
      );
      _onFailure(error);
    }
  }
}
