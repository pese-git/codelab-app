import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

/// Агент на `FakeAcpTransport`, которого играет модульный тест CLI.
///
/// Почему: раннеры CLI работают поверх настоящего `ClientWorkspace`, а не
/// фейка kit — так модульные тесты проверяют то же, что увидит процесс; кадры
/// агента тест отправляет сам (design.md change `add-codelab-cli`, D2).
///
/// Как использовать: `FakeAgent()`, затем раннер с [workspace] и
/// [profile]; [next] ждёт запрос клиента, [respond], [update] и [fail]
/// отвечают от имени агента. [openError] — агент не запускается: резолвер
/// бросает эту ошибку вместо транспорта.
final class FakeAgent {
  FakeAgent({this.openError}) {
    transport.initializeAgentCapabilities = const AgentCapabilities();
  }

  final Object? openError;

  final transport = FakeAcpTransport();
  final application = AcpClientApplication(transport: FakeAcpTransport());
  late final ClientWorkspace workspace = ClientWorkspace(
    backend: AcpClientBackend(application),
    resolvers: [
      ConfigTransportResolver(
        stdio: (_) => switch (openError) {
          final error? => throw error,
          null => transport,
        },
      ),
    ],
  );

  static const profile = StdioProfile(
    id: 'agent',
    label: 'Agent',
    command: 'agent',
  );

  Future<JsonRpcRequest> next(String method) async =>
      await transport.sent.firstWhere(
            (message) => message is JsonRpcRequest && message.method == method,
          )
          as JsonRpcRequest;

  void respond(JsonRpcRequest request, Object? result) => transport.emitInbound(
    JsonRpcMessage.response(id: request.id, result: result),
  );

  void fail(
    JsonRpcRequest request,
    String message, {
    Map<String, Object?>? data,
  }) => transport.emitInbound(
    JsonRpcMessage.response(
      id: request.id,
      error: JsonRpcError(code: -32603, message: message, data: data),
    ),
  );

  void update(String sessionId, Map<String, Object?> update) =>
      transport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: {'sessionId': sessionId, 'update': update},
        ),
      );

  void chunk(String sessionId, String text) => update(sessionId, {
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  });

  /// Отвечает на `session/new` сессией [sessionId].
  Future<void> acceptNewSession(String sessionId) async =>
      respond(await next(sessionNewMethod), {'sessionId': sessionId});

  Future<void> dispose() async {
    await workspace.dispose();
    await application.dispose();
  }
}
