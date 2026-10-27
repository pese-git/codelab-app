/// Общая обвязка характеризационных тестов `CodeLabShellCubit` (задача 5.0).
///
/// Почему: change `extract-acp-client-kit` переносит логику Cubit в
/// `codelab_client_core` серией итераций, и каждая должна сохранить поведение app.
/// Тесты фиксируют это поведение до первого переноса и не меняются до конца
/// change (spec `testing-quality`, «Характеризационные тесты фасада
/// приложения»).
///
/// Для чего: один способ поднять Cubit через настоящий граф cherrypick
/// (`CodeLabTestBinding`) с `FakeAcpTransport` и короткие шаги протокола
/// (сессия, ход, обновление, запрос разрешения), чтобы тексты тестов
/// говорили о поведении, а не о кадрах JSON-RPC.
///
/// Как использовать: `final h = ShellHarness();` в начале теста; закрытие
/// графа выполняет teardown `CodeLabTestBinding`. Тест обращается только к
/// публичной поверхности `CodeLabShellCubit` и `CodeLabShellState` и
/// проверяет конечные состояния, а не число `emit` (design D1). Каждый
/// начатый ход тест завершает сам, иначе закрытие графа оборвёт запрос.
library;

import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../../support/test_app_scope.dart';
import '../../../../support/transcript_rows.dart';

/// Готовит среду для `ShellHarness`; вызывается в `setUp` каждого файла.
///
/// `selectProject` пишет недавние проекты в `shared_preferences`, которому
/// нужен тестовый биндинг и подменное хранилище.
void setUpCharacterization() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
}

/// Начатый ход: запрос `session/prompt` и future `submitPrompt`.
typedef StartedTurn = ({JsonRpcRequest request, Future<void> done});

/// Cubit из графа app и транспорт агента, через который тест играет агента.
final class ShellHarness {
  ShellHarness({
    FakeAcpTransport? agent,
    CodeLabStdioTransportFactory? stdioTransportFactory,
    CodeLabWebSocketTransportFactory? webSocketTransportFactory,
  }) : agent = agent ?? FakeAcpTransport() {
    binding = CodeLabTestBinding(
      stdioTransportFactory:
          stdioTransportFactory ??
          (_) {
            stdioStarts++;
            return this.agent;
          },
      webSocketTransportFactory: webSocketTransportFactory,
    );
  }

  /// Транспорт, который получает Cubit при `connect()` по stdio.
  final FakeAcpTransport agent;

  late final CodeLabTestBinding binding;

  /// Сколько раз Cubit запросил stdio-транспорт у фабрики по умолчанию.
  var stdioStarts = 0;

  CodeLabShellCubit get cubit => binding.scope.resolve<CodeLabShellCubit>();

  AcpClientApplication get application =>
      binding.scope.resolve<AcpClientApplication>();

  /// Тексты всех записей структурного лога app в порядке записи.
  List<String> get logEvents => [
    for (final entry in binding.scope.resolve<LogBuffer>().entries.value)
      '${entry['event']}',
  ];

  /// Ждёт следующий исходящий кадр с методом [method].
  ///
  /// Подписка открывается сразу, поэтому future берут до действия, которое
  /// кадр отправит.
  Future<JsonRpcMessage> nextSent(String method, {FakeAcpTransport? via}) =>
      (via ?? agent).sent.firstWhere(
        (message) => switch (message) {
          JsonRpcRequest(method: final sent) ||
          JsonRpcNotification(method: final sent) => sent == method,
          JsonRpcResponse() => false,
        },
      );

  /// Ждёт следующий исходящий ответ клиента агенту (на запрос агента).
  Future<JsonRpcResponse> nextResponse() async =>
      await agent.sent.firstWhere((message) => message is JsonRpcResponse)
          as JsonRpcResponse;

  /// Исходящие кадры агенту, кроме `initialize`.
  List<JsonRpcMessage> sentAfterInitialize() => [
    for (final message in agent.sentMessages)
      if (message is! JsonRpcRequest || message.method != initializeMethod)
        message,
  ];

  Future<void> connect() async {
    await cubit.connect();
    expect(cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
  }

  /// Создаёт сессию [sessionId]; агент отвечает с [configOptions].
  Future<JsonRpcRequest> createSession(
    String sessionId, {
    List<Map<String, Object?>>? configOptions,
  }) async {
    final requestFuture = nextSent(sessionNewMethod);
    final createFuture = cubit.createSession();
    final request = await requestFuture as JsonRpcRequest;
    agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: {'sessionId': sessionId, 'configOptions': ?configOptions},
      ),
    );
    await createFuture;
    return request;
  }

  /// Отправляет промпт в активную сессию и ждёт кадр `session/prompt`.
  Future<StartedTurn> startTurn(String text) async {
    final requestFuture = nextSent(sessionPromptMethod);
    final done = cubit.submitPrompt(text);
    final request = await requestFuture as JsonRpcRequest;
    return (request: request, done: done);
  }

  /// Агент завершает ход ответом на `session/prompt`.
  void endTurn(JsonRpcRequest prompt, {String stopReason = 'end_turn'}) {
    agent.emitInbound(
      JsonRpcMessage.response(
        id: prompt.id,
        result: {'stopReason': stopReason},
      ),
    );
  }

  /// Агент присылает `session/update` для [sessionId].
  void sessionUpdate(
    String sessionId,
    Map<String, Object?> update, {
    FakeAcpTransport? via,
  }) {
    (via ?? agent).emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: {'sessionId': sessionId, 'update': update},
      ),
    );
  }

  /// Агент присылает фрагмент ответа `agent_message_chunk`.
  void agentText(String sessionId, String text, {FakeAcpTransport? via}) =>
      sessionUpdate(sessionId, {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': text},
      }, via: via);

  /// Агент запрашивает разрешение на вызов [toolCallId] запросом с [id].
  void requestPermission({
    required int id,
    required String sessionId,
    required String toolCallId,
    required String title,
    String command = 'echo hi',
  }) {
    agent.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: SessionId(sessionId),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(toolCallId),
            title: title,
            kind: ToolKind.execute,
            status: ToolCallStatus.inProgress,
            rawInput: {'command': command},
          ),
          options: const [
            PermissionOption(
              optionId: PermissionOptionId('allow-once'),
              name: 'Allow once',
              kind: PermissionOptionKind.allowOnce,
            ),
            PermissionOption(
              optionId: PermissionOptionId('reject-once'),
              name: 'Reject',
              kind: PermissionOptionKind.rejectOnce,
            ),
          ],
        ).toJson(),
      ),
    );
  }

  /// Строки вызовов активной сессии с ожидающим одобрением — «метка деталь»,
  /// например `Run echo hi`.
  List<String> pendingApprovalTexts() => [
    for (final entry in cubit.state.transcriptRows)
      if (entry.approval is CodeLabTranscriptApprovalPending) entry.text,
  ];

  /// Даёт доставить состояния, уже выпущенные Cubit: поток `BlocBase`
  /// отдаёт их подписчикам асинхронно.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Собирает состояния Cubit, пока тест не вызовет `cancel` у подписки.
  (List<CodeLabShellState>, StreamSubscription<CodeLabShellState>)
  recordStates() {
    final states = <CodeLabShellState>[];
    final subscription = cubit.stream.listen(states.add);
    addTearDown(subscription.cancel);
    return (states, subscription);
  }
}

/// Транспорт, `start()` которого падает с [error].
///
/// Моделирует агента, который не запустился или отверг рукопожатие
/// WebSocket.
final class ThrowingStartTransport implements AcpTransport {
  ThrowingStartTransport(this.error);

  final Object error;

  final _inbound = StreamController<JsonRpcMessage>.broadcast();
  final _events = StreamController<AcpTransportEvent>.broadcast();

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => AcpTransportState.idle;

  @override
  Future<void> start() async => throw error;

  @override
  Future<void> send(JsonRpcMessage message) async =>
      throw StateError('not started');

  @override
  Future<void> close({Duration? timeout}) async {
    await _inbound.close();
    await _events.close();
  }
}

/// Транспорт, который после `close()` продолжает доставлять кадры.
///
/// Моделирует старое соединение, чьи кадры приходят уже после
/// переподключения: настоящий транспорт может закрываться медленно, и
/// поздний `session/update` старого поколения не должен менять состояние
/// (`AGENTS.md` §9).
final class LingeringTransport implements AcpTransport {
  LingeringTransport(this.inner);

  final FakeAcpTransport inner;

  var closeRequested = false;

  @override
  Stream<JsonRpcMessage> get inbound => inner.inbound;

  @override
  Stream<AcpTransportEvent> get events => inner.events;

  @override
  AcpTransportState get state => inner.state;

  @override
  Future<void> start() => inner.start();

  @override
  Future<void> send(JsonRpcMessage message) => inner.send(message);

  @override
  Future<void> close({Duration? timeout}) async => closeRequested = true;
}
