import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript_item.freezed.dart';

/// Элемент транскрипта сессии для отображения.
///
/// Почему: UI и CLI показывают один и тот же транскрипт, а сырые
/// `session/update` и read-модель ядра клиента — протокольные данные, не
/// представление (`AGENTS.md` §7). Проекция в элементы — логика kit
/// (spec acp-client-kit «Инкрементальная проекция транскрипта»).
///
/// Для чего: `SessionView.transcript`. Порядок — порядок ходов сессии; в
/// ходе — промпт, затем элементы по порядку обновлений агента, затем
/// одобрения вызовов, о которых агент не объявлял, и итоговое уведомление.
///
/// Как использовать: хост отображает элементы через `switch`; [id]
/// стабилен, пока элемент живёт (растущий текст сохраняет id), и подходит
/// как ключ виджета.
@freezed
sealed class TranscriptItem with _$TranscriptItem {
  const TranscriptItem._();

  /// Текст промпта пользователя.
  const factory TranscriptItem.user({
    required String id,
    required String text,
  }) = UserItem;

  /// Сплошной отрезок `agent_message_chunk` подряд.
  const factory TranscriptItem.agentText({
    required String id,
    required String text,
  }) = AgentTextItem;

  /// Сплошной отрезок `agent_thought_chunk` подряд.
  const factory TranscriptItem.thought({
    required String id,
    required String text,
  }) = ThoughtItem;

  /// Вызов инструмента; [details] — `null`, если ядро не знает записи вызова.
  const factory TranscriptItem.toolCall({
    required String id,
    required ToolCallId toolCallId,
    required String title,
    ToolCallView? details,
    ApprovalStateView? approval,
  }) = ToolCallItem;

  /// Операция со списком задач: тихая строка вместо вызова `think`
  /// (design.md change `add-subagents-and-tasks`, D27).
  ///
  /// Поля — id пунктов (`_meta.codelab.task.id`): [added] — добавленные,
  /// [completed] — ставшие `completed`, [removed] — удалённые, [updated] —
  /// прочие изменённые. Подряд идущие операции сливаются в один элемент
  /// (поля объединяются); [id] — id первого. Текст — [TaskOpsItemText.text].
  const factory TranscriptItem.taskOps({
    required String id,
    @Default(<String>[]) List<String> added,
    @Default(<String>[]) List<String> completed,
    @Default(<String>[]) List<String> removed,
    @Default(<String>[]) List<String> updated,
  }) = TaskOpsItem;

  /// Итог хода, который не виден из обновлений агента.
  ///
  /// [failure] заполнен только у [NoticeKind.error]: по нему хост строит
  /// заголовок заметки, а [text] остаётся нейтральной строкой для CLI
  /// (design D3 change `add-connection-and-error-states`).
  const factory TranscriptItem.notice({
    required String id,
    required NoticeKind kind,
    required String text,
    PromptFailure? failure,
  }) = NoticeItem;
}

/// Текст тихой строки операций со списком задач (D27).
///
/// Почему: текст один для app, REPL и TUI, поэтому строится в kit, а не в
/// хостах. Для чего: «Task #3 added to the plan», «Tasks #1–#4 added to the
/// plan» (подряд идущие id — диапазоном, иначе списком `#1, #3`), «Task #2
/// done», «Task #2 removed», «Task #2 updated»; части идут в этом порядке и
/// объединяются через `; `.
extension TaskOpsItemText on TaskOpsItem {
  String get text => [
    if (added.isNotEmpty) '${_tasks(added)} added to the plan',
    if (completed.isNotEmpty) '${_tasks(completed)} done',
    if (removed.isNotEmpty) '${_tasks(removed)} removed',
    if (updated.isNotEmpty) '${_tasks(updated)} updated',
  ].join('; ');
}

String _tasks(List<String> ids) =>
    '${ids.length == 1 ? 'Task' : 'Tasks'} ${_idList(ids)}';

String _idList(List<String> ids) {
  final numbers = [for (final id in ids) int.tryParse(id)];
  final consecutive =
      ids.length > 1 &&
      !numbers.contains(null) &&
      [
        for (var i = 1; i < numbers.length; i++) numbers[i]! - numbers[i - 1]!,
      ].every((step) => step == 1);
  return consecutive
      ? '#${ids.first}–#${ids.last}'
      : ids.map((id) => '#$id').join(', ');
}

/// Состояние вызова инструмента в элементе транскрипта.
@freezed
abstract class ToolCallView with _$ToolCallView {
  const factory ToolCallView({
    required ToolKind kind,
    required ToolCallStatusView status,

    /// Команда из `rawInput.command`, если агент её прислал.
    String? command,

    /// `rawInput` вызова как пришёл от агента; источник детали строки
    /// инструмента (`ToolRowFormatter`, `dart-agent-and-clients` §12.1.6).
    /// Клиенты не показывают его как есть.
    Map<String, Object?>? rawInput,

    /// Пути из `locations` вызова в порядке прихода.
    @Default(<String>[]) List<String> paths,

    /// Тексты элементов `content` с текстовым блоком в порядке прихода:
    /// вывод вызова, причина отказа или ошибки.
    @Default(<String>[]) List<String> textOutput,
  }) = _ToolCallView;
}

/// Статус вызова для отображения.
///
/// [cancelled] — вызов не закончился к `session/cancel` клиента: в ACP такого
/// статуса нет, ядро хранит его как `failed` с флагом `cancelledByClient`
/// (fix-prompt-cancel-tool-calls/design.md, D3).
enum ToolCallStatusView { queued, running, succeeded, failed, cancelled }

/// Одобрение вызова инструмента, встроенное в его элемент.
@freezed
sealed class ApprovalStateView with _$ApprovalStateView {
  const ApprovalStateView._();

  /// Ждёт ответа пользователя. [focused] — самое раннее ожидающее одобрение
  /// хода: только оно отвечает на клавиши одобрения
  /// (embed-approval-in-thread/design.md, Decision 6). [critical] — агент
  /// пометил запрос `_meta.codelab.critical: true`; headless-политика
  /// `allow-all` такой запрос отклоняет (design.md change `add-codelab-cli`,
  /// D9, D14).
  const factory ApprovalStateView.pending({
    required ApprovalRequestId approvalId,
    required SessionId sessionId,
    required ApprovalRiskLevel risk,
    String? command,
    Map<String, Object?>? rawInput,
    required List<PermissionOption> options,
    required bool focused,
    @Default(false) bool critical,
  }) = PendingApprovalView;

  /// Решено; [label] — имя выбранного варианта, `Cancelled` или `Resolved`,
  /// [outcome] — исход, по которому клиент выбирает отметку (галочка только у
  /// разрешённого вызова).
  const factory ApprovalStateView.resolved({
    required String label,
    required ApprovalOutcomeView outcome,
  }) = ResolvedApprovalView;
}

/// Исход решённого одобрения для отображения.
///
/// Почему: одной метки мало — клиент рисовал зелёную галочку и у отменённого,
/// и у отклонённого запроса, потому что не знал, чем он закончился.
///
/// Для чего: проекция [TranscriptProjector] выводит исход из статуса запроса
/// и вида выбранного варианта ACP (`allow_*` / `reject_*`), а клиент по нему
/// выбирает иконку и тон.
///
/// Как использовать: читать из [ResolvedApprovalView.outcome]; [unknown] —
/// вариант без известного вида (агент прислал неизвестный `optionId` или
/// ответ без варианта), клиент показывает его нейтрально.
enum ApprovalOutcomeView { allowed, rejected, cancelled, unknown }

/// Вид уведомления в транскрипте.
enum NoticeKind {
  /// Ход сорвался; текст — `Failed to send prompt: <причина>`.
  error,

  /// Ход завершился без вывода агента; текст — `Completed with stopReason …`.
  emptyTurn,

  /// Ход остановлен агентом по причине, которую пользователь иначе не
  /// увидит: `max_tokens`, `max_turn_requests`, `refusal` (design D27,
  /// решение Q33). Добавляется всегда, даже если агент что-то вывел; id
  /// `<turnId>/stopped`. Ходу с такой заметкой `emptyTurn` не добавляется.
  turnStopped,

  /// Связь сессии с агентом потеряна после переподключения: агент не умеет
  /// загружать сессии или `session/load` не удался (design D5 change
  /// `add-session-list-and-reload`). Добавляет рабочее пространство, а не
  /// проекция хода.
  detached,

  /// Сессию не удалось восстановить после перезапуска хоста, и вместо неё
  /// создана новая (design D6).
  reconnected,
}
