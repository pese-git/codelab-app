import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'acp_client_env.dart';
import 'config_options.dart';
import 'connection/acp_error.dart';
import 'connection/client_requests.dart';
import 'event_projection.dart';
import 'replay.dart';

/// Куда мост ставит уведомления сессии: очередь соединения-владельца.
typedef SessionUpdateSink = void Function(acp.SessionNotification update);

/// Сессия ACP поверх `AgentSession` (§13.7).
///
/// Почему отдельный объект: у сессии ACP есть состояние, которого нет в
/// ядре, — соединение-владелец, идущий `session/prompt`, флаг отмены,
/// подписка проекции, отсоединение. Сервер хранит мосты по `sessionId`,
/// чтобы новое соединение нашло сессию и продолжило её (§13.5, шаг 3).
///
/// Для чего: проецирует каждое событие сессии в [sink] в порядке событий
/// ядра; [prompt] запускает ход в фоне и завершается ответом по
/// `TurnEnded` — после всех уведомлений хода (ACP-3); [cancel] отменяет ход
/// и ожидания клиента; [detach], [reattach] и [resume] — отсоединение и
/// переподключение по D7.
///
/// Как использовать: соединение создаёт мост до сессии, передаёт
/// [markInProgress] в хуки сессии, затем вызывает [attach] с созданной или
/// загруженной сессией. Ход, опции и отмена идут через мост; [close]
/// закрывает сессию.
final class SessionBridge {
  SessionBridge({
    required this.owner,
    required this.sink,
    required ClientLink link,
    required ModelCatalog catalog,
    required Clock clock,
    required Logger logger,
    AcpClientExecutionEnv? clientEnv,
  }) : _link = link,
       _catalog = catalog,
       _clock = clock,
       _logger = logger,
       _clientEnv = clientEnv;

  /// Соединение-владелец: его запросы и его очередь получают кадры сессии.
  Object owner;

  /// Очередь соединения-владельца; меняется при переподключении.
  SessionUpdateSink sink;
  final ClientLink _link;
  final ModelCatalog _catalog;
  final Clock _clock;
  final Logger _logger;

  /// Env через клиента: его `fs/*` прекращаются при отмене хода.
  final AcpClientExecutionEnv? _clientEnv;

  late final AgentSession session;
  late final acp.SessionId _id;
  StreamSubscription<AgentEvent>? _events;

  /// Идущий ход: завершается по `TurnEnded`.
  Completer<TurnEnded>? _turn;
  AgentError? _failure;
  var _cancelRequested = false;

  /// Токен идущего хода: `session/cancel`, пришедший до старта цикла, не
  /// теряется (ход стартует уже отменённым).
  CancelTokenSource? _turnCancel;

  /// Соединение закрыто, сессия ждёт переподключения (D7).
  var _detached = false;
  ClockTimer? _grace;

  /// Ожидающие разрешения ждут переподключения; [resume] их отпускает.
  Completer<void>? _reconnected;

  /// Ход пережил переподключение: его итог уходит новому соединению
  /// `session_info_update` (§13.5, шаг 9).
  var _turnMoved = false;

  /// Смена режима по запросу клиента: `config_option_update` не
  /// дублирует ответ (ACP-11); завершается, когда `current_mode_update`
  /// поставлен в очередь.
  Completer<void>? _clientModeChange;

  /// Заметка о смене на модель без рассуждения: первым
  /// `agent_message_chunk` следующего хода (§2.12.3).
  String? _effortNote;

  /// Вызовы, о которых клиент уже знает (`tool_call` ушёл).
  final _announced = <String>{};

  /// `markInProgress` сработал раньше, чем `tool_call` дошёл до проекции.
  final _earlyInProgress = <String>{};

  /// Ожидающие проекции `tool_call` своего вызова (запрос разрешения).
  final _awaitingAnnounce = <String, Completer<void>>{};

  /// Терминалы, встроенные в вызов, и ожидающие этого `exec`.
  final _shownTerminals = <String>{};
  final _awaitingTerminal = <String, Completer<void>>{};

  /// Для `AcpClientExecutionEnv`: завершается, когда `tool_call_update` с
  /// терминалом уже в очереди — `terminal/wait_for_exit` идёт после него.
  Future<void> terminalShown(String terminalId) {
    if (_shownTerminals.remove(terminalId)) {
      return Future.value();
    }
    return (_awaitingTerminal[terminalId] ??= Completer<void>()).future;
  }

  bool get turnActive => _turn != null;

  /// `TurnEnded` идущего хода; ответ строится по нему, когда `prompt`
  /// вернулся.
  TurnEnded? _ended;

  void _finishTurn(Completer<TurnEnded> turn) {
    final ended = _ended;
    _ended = null;
    if (turn.isCompleted) {
      return;
    }
    if (ended == null) {
      turn.completeError(StateError('the turn ended without TurnEnded'));
      return;
    }
    if (_turnMoved) {
      _turnMoved = false;
      _send(_turnEndedInfo(ended));
    }
    turn.complete(ended);
  }

  /// Соединение-владелец закрыто, а сессия ещё не переподключена.
  bool get detached => _detached;

  /// Подключает созданную или загруженную сессию и начинает проекцию.
  void attach(AgentSession session) {
    this.session = session;
    _id = acp.SessionId(session.id.value);
    _events = session.events.listen(_onEvent);
  }

  /// Текущий снимок `configOptions` (§13.6).
  List<acp.SessionConfigOption> get configOptions =>
      sessionConfigOptions(session, _catalog);

  /// Хук `beforeToolCall` последним в цепочке (§10.7): вызов прошёл
  /// разрешения и хуки — клиент получает `in_progress` (§13.7).
  ///
  /// События сессии приходят подписчику асинхронно, а хук вызывается в
  /// цикле синхронно, поэтому `in_progress` может опередить `tool_call`
  /// своего вызова; тогда он откладывается до проекции `tool_call`.
  Future<Block?> markInProgress(
    ToolCall call,
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    if (_announced.contains(call.id)) {
      _send(inProgressUpdate(call.id));
    } else {
      _earlyInProgress.add(call.id);
    }
    return null;
  }

  /// Запускает ход и ждёт его итога; ответ — по §13.8, сбой хода —
  /// `AcpRequestError` `-32603`.
  Future<acp.PromptResponse> prompt(List<ContentBlock> content) async {
    final turn = _turn = Completer<TurnEnded>();
    _failure = null;
    _ended = null;
    _cancelRequested = false;
    _turnMoved = false;
    if (_effortNote case final note?) {
      _effortNote = null;
      _send(
        acp.SessionUpdate.agentMessageChunk(
          content: acp.ContentBlock.text(text: note),
        ),
      );
    }
    // Ход идёт в фоне: обработчик ждёт возврата prompt, а не TurnEnded, —
    // после TurnEnded сессия ещё пишет автозаголовок, и его
    // session_info_update идёт до ответа, как в фикстурах этапа 0 (D15).
    // События сессии доставлены подписчику раньше: их микрозадачи
    // поставлены до завершения prompt.
    unawaited(
      session
          .prompt(content, cancel: (_turnCancel = CancelTokenSource()).token)
          .then<void>(
            (_) => _finishTurn(turn),
            onError: (Object error, StackTrace stack) {
              _logger.log(
                LogLevel.error,
                'acp.turn.failed',
                fields: {'session_id': _id.value},
                error: error,
                stack: stack,
              );
              if (!turn.isCompleted) {
                turn.completeError(error, stack);
              }
            },
          ),
    );
    try {
      final ended = await turn.future;
      return turnResponse(
        ended,
        failure: _failure,
        cancelRequested: _cancelRequested,
      );
    } finally {
      _turn = null;
    }
  }

  /// Завершается вместе с идущим ходом; без хода — сразу.
  Future<void> get idle async {
    final turn = _turn;
    if (turn != null) {
      await turn.future.then<void>((_) {}, onError: (Object _) {});
    }
  }

  /// `session/cancel` (§13.7): токен хода, ожидающие разрешения (через
  /// токен), `fs/*` и терминалы. `false` — хода нет.
  bool cancel() {
    if (_turn == null) {
      return false;
    }
    _cancelRequested = true;
    _turnCancel?.cancel();
    unawaited(session.cancel());
    _clientEnv?.abortPending();
    return true;
  }

  /// Режим по запросу клиента: `current_mode_update` без дублирующего
  /// `config_option_update` (§13.6, шаг 4); возвращается, когда уведомление
  /// уже в очереди — ответ встанет после него.
  Future<void> setMode(ModeId mode) async {
    final echoed = _clientModeChange = Completer<void>();
    await session.setMode(mode);
    await echoed.future;
  }

  /// Модель по запросу клиента; смена на модель без рассуждения оставляет
  /// заметку для следующего хода (§2.12.3).
  Future<void> setModel(ModelId id) async {
    final before = session.model;
    await session.setModel(id);
    final after = session.model;
    if (before.supportsReasoning && !after.supportsReasoning) {
      _effortNote =
          'Reasoning effort is not supported by '
          '${after.provider}/${after.id}; the setting is kept and applies '
          'again after switching to a model with reasoning.';
    } else if (after.supportsReasoning) {
      _effortNote = null;
    }
  }

  /// Кадры `session/load` до ответа: история и хвост (§13.5, шаги 5–6).
  List<acp.SessionUpdate> replay() {
    final events = session.replay().toList();
    final plan = events.whereType<PlanUpdated>().lastOrNull;
    final title = events.whereType<SessionTitleChanged>().lastOrNull;
    return [
      ...replayUpdates(events),
      if (plan != null)
        ...projectEvent(plan, configOptions: () => configOptions),
      acp.SessionUpdate.currentModeUpdate(
        currentModeId: acp.SessionModeId(session.mode.value),
      ),
      acp.SessionUpdate.configOptionUpdate(configOptions: configOptions),
      // Встроенных slash-команд на этапе 4 нет (§13.4, шаг 6).
      const acp.SessionUpdate.availableCommandsUpdate(availableCommands: []),
      if (title != null)
        acp.SessionUpdate.sessionInfoUpdate(
          title: title.title,
          updatedAt: formatJournalTime(title.updatedAt),
        ),
    ];
  }

  /// Соединение-владелец закрыто (§13.10, «Отсоединение»): кадры больше
  /// некуда отправлять, ход ждёт переподключения [grace], затем
  /// отменяется. Без хода сессия просто ждёт следующего `session/load`.
  void detach(Duration grace) {
    _detached = true;
    // События остаются в журнале, реплей отдаст их новому соединению.
    sink = (_) {};
    if (_turn == null) {
      return;
    }
    _logger.log(
      LogLevel.info,
      'acp.session.detached',
      fields: {'session_id': _id.value, 'grace_ms': grace.inMilliseconds},
    );
    if (grace == Duration.zero) {
      _expire();
      return;
    }
    _grace = _clock.timer(grace, _expire);
  }

  /// Новое соединение загружает сессию (§13.5, шаг 3): запросы, очередь и
  /// возможности клиента — его. Возвращает `true`, если это
  /// переподключение идущего хода.
  bool reattach({
    required Object owner,
    required ClientRequests requests,
    required acp.ClientCapabilities capabilities,
    required SessionUpdateSink sink,
  }) {
    final moved = _detached && _turn != null;
    _grace?.cancel();
    _grace = null;
    _detached = false;
    this.owner = owner;
    this.sink = sink;
    _link
      ..requests = requests
      ..capabilities = capabilities;
    if (moved) {
      _turnMoved = true;
      _logger.log(
        LogLevel.info,
        'acp.session.reconnected',
        fields: {'session_id': _id.value},
      );
    }
    return moved;
  }

  /// Для `AcpPermissionGate`: завершается, когда `tool_call` вызова уже в
  /// очереди. События сессии приходят подписчику асинхронно, а вопрос
  /// политики может быть готов раньше (§13.7, «Статусы вызова»).
  Future<void> announced(String toolCallId) {
    if (_announced.contains(toolCallId)) {
      return Future.value();
    }
    return (_awaitingAnnounce[toolCallId] ??= Completer<void>()).future;
  }

  /// После ответа `session/load`: ожидающие разрешения уходят новому
  /// соединению с новым id и тем же `toolCallId` (§13.5, шаг 8; PERM-4).
  void resume() {
    final reconnected = _reconnected;
    _reconnected = null;
    reconnected?.complete();
  }

  /// Для `AcpPermissionGate`: соединение пропало во время вопроса. `true` —
  /// сессию переподключили, вопрос задаётся заново; `false` — ход
  /// отменён (grace истёк) или ждать нечего.
  Future<bool> waitForReconnect(CancelToken cancel) async {
    if (!_detached || cancel.isCancelled) {
      return false;
    }
    final reconnected = _reconnected ??= Completer<void>();
    return Future.any([
      reconnected.future.then((_) => true),
      cancel.onCancel.then((_) => false),
    ]);
  }

  Future<void> close() async {
    _grace?.cancel();
    await session.close();
    await _events?.cancel();
  }

  void _expire() {
    if (!_detached) {
      return;
    }
    _logger.log(
      LogLevel.info,
      'acp.session.grace_expired',
      fields: {'session_id': _id.value},
    );
    cancel();
  }

  void _onEvent(AgentEvent event) {
    switch (event) {
      case AgentError(retrying: false):
        _failure = event;
      case ToolCallStarted(:final toolCallId):
        _announced.add(toolCallId);
      case _:
    }
    final echo = _clientModeChange;
    for (final update in projectEvent(
      event,
      configOptions: () => configOptions,
    )) {
      if (event is ModeChanged &&
          echo != null &&
          update is acp.ConfigOptionUpdate) {
        continue;
      }
      _send(update);
    }
    switch (event) {
      case ModeChanged() when echo != null:
        _clientModeChange = null;
        echo.complete();
      case ToolCallStarted(:final toolCallId):
        _awaitingAnnounce.remove(toolCallId)?.complete();
        if (_earlyInProgress.remove(toolCallId)) {
          _send(inProgressUpdate(toolCallId));
        }
      case ToolCallProgress(:final content):
        for (final item in content.whereType<ToolCallTerminal>()) {
          final waiting = _awaitingTerminal.remove(item.terminalId);
          if (waiting == null) {
            _shownTerminals.add(item.terminalId);
          } else {
            waiting.complete();
          }
        }
      case ToolCallFinished(:final toolCallId):
        _announced.remove(toolCallId);
      case TurnEnded():
        _announced.clear();
        _earlyInProgress.clear();
        _ended = event;
      case _:
    }
  }

  /// Итог хода, чей `session/prompt` остался у закрытого соединения
  /// (§13.5, шаг 9; расширение `_meta.codelab.turnEnded`, D10).
  acp.SessionUpdate _turnEndedInfo(TurnEnded event) {
    Map<String, Object?> ended;
    try {
      final response = turnResponse(
        event,
        failure: _failure,
        cancelRequested: _cancelRequested,
      );
      ended = {'stopReason': response.stopReason.wireName};
    } on AcpRequestError catch (error) {
      ended = {'error': (error.data! as Map<String, Object?>)['codelab']};
    }
    return acp.SessionUpdate.sessionInfoUpdate(
      meta: {
        'codelab': {'turnEnded': ended},
      },
    );
  }

  void _send(acp.SessionUpdate update) =>
      sink(acp.SessionNotification(sessionId: _id, update: update));
}
