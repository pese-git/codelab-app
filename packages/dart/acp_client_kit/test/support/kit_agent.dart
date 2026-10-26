// Общая обвязка тестов kit: рабочее пространство на `FakeAcpTransport`, в
// котором тест играет агента.

import 'dart:async';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_client_kit/acp_client_kit.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';

/// Рабочее пространство, подключённое к агенту на [transport]; собирает
/// диагностику kit в [diagnostics].
final class KitAgent {
  final transport = FakeAcpTransport();
  final application = AcpClientApplication(transport: FakeAcpTransport());
  late final ClientWorkspace workspace = ClientWorkspace(
    backend: AcpClientBackend(application),
    resolvers: [ConfigTransportResolver(stdio: (_) => transport)],
  );
  final diagnostics = <WorkspaceDiagnostic>[];
  StreamSubscription<WorkspaceDiagnostic>? _subscription;

  Future<void> start() async {
    _subscription = workspace.diagnostics.listen(diagnostics.add);
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
