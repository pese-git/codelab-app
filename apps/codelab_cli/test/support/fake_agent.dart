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
/// бросает эту ошибку вместо транспорта. [capabilities] — что агент
/// объявит в `initialize`; [sessions] — ответ на `session/list`, который kit
/// отправляет сразу после `initialize` агенту со списком сессий.
final class FakeAgent {
  FakeAgent({
    this.openError,
    AgentCapabilities capabilities = const AgentCapabilities(),
    ListSessionsResponse? sessions,
  }) {
    transport.initializeAgentCapabilities = capabilities;
    if (sessions != null) {
      unawaited(
        next(sessionListMethod).then((r) => respond(r, sessions.toJson())),
      );
    }
  }

  final Object? openError;

  /// Транспорт текущего «процесса» агента; [restartAgent] заменяет его.
  var transport = FakeAcpTransport();
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

  /// Новый «процесс» агента: следующий `connect` получит свежий транспорт
  /// с возможностями [capabilities] (`/profile`, `/reconnect`); [sessions] —
  /// ответ на его `session/list`.
  void restartAgent({
    AgentCapabilities capabilities = const AgentCapabilities(),
    ListSessionsResponse? sessions,
  }) {
    transport = FakeAcpTransport()..initializeAgentCapabilities = capabilities;
    if (sessions != null) {
      unawaited(
        next(sessionListMethod).then((r) => respond(r, sessions.toJson())),
      );
    }
  }

  /// Запросы клиента, которые тест уже получил через [next].
  final _consumed = <JsonRpcMessage>{};

  /// Следующий ещё не полученный запрос [method]: сначала среди уже
  /// отправленных — раннер может отправить его раньше, чем тест начнёт
  /// ждать, — затем из потока.
  Future<JsonRpcRequest> next(String method) async {
    bool matches(JsonRpcMessage message) =>
        message is JsonRpcRequest &&
        message.method == method &&
        !_consumed.contains(message);
    final sent = transport.sentMessages.where(matches).firstOrNull;
    final request = sent ?? await transport.sent.firstWhere(matches);
    _consumed.add(request);
    // Поток `sent` синхронный: без паузы тест продолжился бы внутри его
    // рассылки, и кадр, который тест вызовет следующим (например,
    // `session/cancel`), не дошёл бы до подписчиков.
    await Future<void>.delayed(Duration.zero);
    return request as JsonRpcRequest;
  }

  /// Ждёт уведомление клиента [method] (например, `session/cancel`).
  Future<void> nextNotification(String method) async {
    bool matches(JsonRpcMessage message) =>
        message is JsonRpcNotification && message.method == method;
    if (!transport.sentMessages.any(matches)) {
      await transport.sent.firstWhere(matches);
    }
  }

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

  /// Отвечает на `session/new` сессией [sessionId] с опциями
  /// [configOptions] (JSON `configOptions` ответа).
  Future<void> acceptNewSession(
    String sessionId, {
    List<Map<String, Object?>>? configOptions,
  }) async => respond(await next(sessionNewMethod), {
    'sessionId': sessionId,
    'configOptions': ?configOptions,
  });

  /// Варианты одобрения по умолчанию: `allow_once` и `reject_once`.
  static const defaultOptions = [
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
  ];

  /// Запрос одобрения вызова [toolCallId] вида [kind] с вариантами
  /// [options]; [critical] — `_meta.codelab.critical`.
  void requestPermission({
    required int id,
    required String sessionId,
    required String toolCallId,
    ToolKind kind = ToolKind.execute,
    bool critical = false,
    List<PermissionOption> options = defaultOptions,
  }) => transport.emitInbound(
    JsonRpcMessage.request(
      id: JsonRpcId.integer(id),
      method: sessionRequestPermissionMethod,
      params: RequestPermissionRequest(
        sessionId: SessionId(sessionId),
        toolCall: ToolCallUpdate(
          toolCallId: ToolCallId(toolCallId),
          title: 'Run $toolCallId',
          kind: kind,
          status: ToolCallStatus.pending,
          rawInput: const {'command': 'dart test'},
          meta: critical
              ? const {
                  'codelab': {'critical': true},
                }
              : null,
        ),
        options: options,
      ).toJson(),
    ),
  );

  /// Ответ клиента на запрос агента с [id].
  Future<JsonRpcResponse> responseTo(int id) async {
    bool matches(JsonRpcMessage message) =>
        message is JsonRpcResponse && message.id == JsonRpcId.integer(id);
    return (transport.sentMessages.where(matches).firstOrNull ??
            await transport.sent.firstWhere(matches))
        as JsonRpcResponse;
  }

  Future<void> dispose() async {
    await workspace.dispose();
    await application.dispose();
  }
}
