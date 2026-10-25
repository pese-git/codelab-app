import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'acp_client_env.dart';
import 'config_options.dart';
import 'event_projection.dart';

/// Куда мост ставит уведомления сессии: очередь соединения-владельца.
typedef SessionUpdateSink = void Function(acp.SessionNotification update);

/// Сессия ACP поверх `AgentSession` (§13.7).
///
/// Почему отдельный объект: у сессии ACP есть состояние, которого нет в
/// ядре, — соединение-владелец, идущий `session/prompt`, флаг отмены,
/// подписка проекции. Сервер хранит мосты по `sessionId`, чтобы
/// переподключение нашло сессию из другого соединения (§13.5, шаг 3b).
///
/// Для чего: проецирует каждое событие сессии в [sink] в порядке событий
/// ядра; [prompt] запускает ход в фоне и завершается ответом по
/// `TurnEnded` — после всех уведомлений хода (ACP-3); [cancel] отменяет ход
/// и ожидания клиента.
///
/// Как использовать: соединение создаёт мост до сессии, передаёт
/// [markInProgress] в `SessionSpec.extraBeforeToolCall`, затем вызывает
/// [attach] с созданной сессией. Ход и отмена идут через мост; [close]
/// закрывает сессию.
final class SessionBridge {
  SessionBridge({
    required this.sink,
    required Logger logger,
    AcpClientExecutionEnv? clientEnv,
  }) : _logger = logger,
       _clientEnv = clientEnv;

  /// Очередь соединения-владельца; меняется при переподключении.
  SessionUpdateSink sink;
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

  /// Вызовы, о которых клиент уже знает (`tool_call` ушёл).
  final _announced = <String>{};

  /// `markInProgress` сработал раньше, чем `tool_call` дошёл до проекции.
  final _earlyInProgress = <String>{};

  bool get turnActive => _turn != null;

  /// Подключает созданную или загруженную сессию и начинает проекцию.
  void attach(AgentSession session) {
    this.session = session;
    _id = acp.SessionId(session.id.value);
    _events = session.events.listen(_onEvent);
  }

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
    _cancelRequested = false;
    // Ход идёт в фоне: обработчик ждёт TurnEnded, а не возврата prompt, —
    // ответ должен встать в очередь после последнего уведомления хода.
    unawaited(
      session
          .prompt(content)
          .then<void>(
            (_) {},
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

  /// `session/cancel` (§13.7): токен хода, ожидающие разрешения (через
  /// токен), `fs/*` и терминалы. `false` — хода нет.
  bool cancel() {
    if (_turn == null) {
      return false;
    }
    _cancelRequested = true;
    unawaited(session.cancel());
    _clientEnv?.abortPending();
    return true;
  }

  Future<void> close() async {
    await session.close();
    await _events?.cancel();
  }

  void _onEvent(AgentEvent event) {
    switch (event) {
      case AgentError(retrying: false):
        _failure = event;
      case ToolCallStarted(:final toolCallId):
        _announced.add(toolCallId);
      case _:
    }
    for (final update in projectEvent(
      event,
      configOptions: () => sessionConfigOptions(session),
    )) {
      _send(update);
    }
    switch (event) {
      case ToolCallStarted(:final toolCallId)
          when _earlyInProgress.remove(toolCallId):
        _send(inProgressUpdate(toolCallId));
      case ToolCallFinished(:final toolCallId):
        _announced.remove(toolCallId);
      case TurnEnded():
        _announced.clear();
        _earlyInProgress.clear();
        final turn = _turn;
        if (turn != null && !turn.isCompleted) {
          turn.complete(event);
        }
      case _:
    }
  }

  void _send(acp.SessionUpdate update) =>
      sink(acp.SessionNotification(sessionId: _id, update: update));
}
