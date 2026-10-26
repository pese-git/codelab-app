// Общая обвязка тестов kit: рабочее пространство на `FakeAcpTransport`, в
// котором тест играет агента.

import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';

/// Рабочее пространство, подключённое к агенту на [transport]; собирает
/// диагностику kit в [diagnostics].
final class KitAgent {
  /// [capabilities] — что агент объявит в ответе `initialize`.
  /// [snapshots] — хранилище снимка рабочего пространства; без него
  /// восстановление выключено.
  KitAgent({
    AgentCapabilities capabilities = const AgentCapabilities(),
    this.snapshots,
  }) {
    transport.initializeAgentCapabilities = capabilities;
  }

  final WorkspaceSnapshotStore? snapshots;

  /// Транспорт текущего процесса агента; резолвер читает его при каждом
  /// открытии, поэтому [restartAgent] подменяет агента для `reconnect`.
  var transport = FakeAcpTransport();

  /// Новый «процесс» агента для следующего `reconnect()`: прежний транспорт
  /// ядро клиента закрывает при замене и повторно не открывает.
  void restartAgent({
    AgentCapabilities capabilities = const AgentCapabilities(),
  }) =>
      transport = FakeAcpTransport()
        ..initializeAgentCapabilities = capabilities;
  final application = AcpClientApplication(transport: FakeAcpTransport());
  late final ClientWorkspace workspace = ClientWorkspace(
    backend: AcpClientBackend(application),
    resolvers: [ConfigTransportResolver(stdio: (_) => transport)],
    snapshots: snapshots,
  );
  final diagnostics = <WorkspaceDiagnostic>[];
  StreamSubscription<WorkspaceDiagnostic>? _subscription;

  /// Подключается к агенту; [sessions] — ответ на `session/list`, который
  /// kit отправляет сразу после `initialize` агенту со списком сессий.
  Future<void> start({ListSessionsResponse? sessions}) async {
    _subscription = workspace.diagnostics.listen(diagnostics.add);
    if (sessions != null) {
      unawaited(
        next(
          sessionListMethod,
        ).then((request) => respond(request, sessions.toJson())),
      );
    }
    await workspace.connect(
      const StdioProfile(id: 'agent', label: 'Agent', command: 'agent'),
      projectDirectory: '/work',
    );
  }

  Future<SessionHandle> newSession(
    String id, {
    List<Map<String, Object?>>? configOptions,
  }) async {
    final request = next(sessionNewMethod);
    final handle = workspace.newSession();
    respond(await request, {'sessionId': id, 'configOptions': ?configOptions});
    return handle;
  }

  /// Отправляет промпт [text] в [session] и ждёт кадр `session/prompt`.
  Future<({JsonRpcRequest request, Future<PromptOutcome> done})> prompt(
    SessionHandle session,
    String text,
  ) async {
    final request = next(sessionPromptMethod);
    final done = session.send(text);
    return (request: await request, done: done);
  }

  Future<JsonRpcRequest> next(String method) async =>
      await transport.sent.firstWhere(
            (message) => message is JsonRpcRequest && message.method == method,
          )
          as JsonRpcRequest;

  Future<JsonRpcResponse> nextResponse() async =>
      await transport.sent.firstWhere((message) => message is JsonRpcResponse)
          as JsonRpcResponse;

  void respond(JsonRpcRequest request, Object? result) => transport.emitInbound(
    JsonRpcMessage.response(id: request.id, result: result),
  );

  void fail(JsonRpcRequest request, String message) => transport.emitInbound(
    JsonRpcMessage.response(
      id: request.id,
      error: JsonRpcError(code: -32603, message: message),
    ),
  );

  void update(String sessionId, Map<String, Object?> update) =>
      transport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: {'sessionId': sessionId, 'update': update},
        ),
      );

  void requestPermission({
    required int id,
    required String sessionId,
    required String toolCallId,
    Map<String, Object?> rawInput = const {'command': 'dart test'},
  }) {
    transport.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: SessionId(sessionId),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(toolCallId),
            title: 'Run $toolCallId',
            kind: ToolKind.execute,
            status: ToolCallStatus.inProgress,
            rawInput: rawInput,
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

  Future<void> dispose() async {
    await _subscription?.cancel();
    await workspace.dispose();
    await application.dispose();
  }
}
