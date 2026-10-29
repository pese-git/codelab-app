// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';

/// Gate, который записывает вопросы и в момент вопроса фиксирует, сколько
/// вызовов `tools/call` уже получил MCP-сервер.
final class RecordingGate implements PermissionGate {
  RecordingGate(this._server, this._decide);

  final FakeMcpServer _server;
  final PermissionDecision Function(PermissionRequest request) _decide;
  final requests = <PermissionRequest>[];

  /// `server.calls.length` в момент каждого вопроса.
  final callsAtAsk = <int>[];

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async {
    requests.add(req);
    callsAtAsk.add(_server.calls.length);
    return _decide(req);
  }
}

final _model = ModelRef(
  provider: 'test',
  id: 'model-1',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 32000,
  maxOutputTokens: 4096,
);

/// Ядро, собранное `buildAgentCore` с настоящим `McpClientConnector` над
/// `FakeMcpServer` (design.md change `add-agent-mcp-client`, D15): так
/// проверяется весь путь «модель → политика → MCP-сервер».
final class CoreStack {
  CoreStack._(this.core, this.logger, this.model, this.store);

  static CoreStack build({
    required FakeMcpServer server,
    required List<Map<String, Object?>> steps,
    required PermissionGate? Function(FakeMcpServer server) gate,
    McpTransports? transports,
    List<McpServerConfig>? servers,
  }) {
    final store = MemorySessionStore();
    _servers =
        servers ?? const [McpStdioServerConfig(name: 'fake', command: 'fake')];
    final clock = FakeClock();
    final logger = RecordingLogger();
    final model = ScriptedStreamFunction.fromJson({
      'steps': steps,
    }, clock: clock);
    final core = buildAgentCore(
      profile: HostProfile.of('agent-serve').narrowed({
        HostCapability.shellExec: const CapabilityOff('тест без shell'),
        // Фабрика http в тесте не нужна: профиль сужается до stdio (HOST-3).
        HostCapability.mcp: CapabilityTransport({
          if (transports == null || transports.stdio != null) 'stdio',
          if (transports?.http != null) 'http',
        }, 'тест'),
        HostCapability.sessionPersistence: const CapabilityOff(
          'журнал в памяти',
        ),
      }),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        gate: gate(server),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
        mcp: McpClientConnector(
          transports:
              transports ??
              McpTransports(stdio: FakeMcpTransportFactory({'fake': server})),
          clock: clock,
        ),
      ),
      config: CoreConfig(defaultModel: _model),
      streamFunction: model.call,
    );
    return CoreStack._(core, logger, model, store);
  }

  static var _servers = <McpServerConfig>[];

  final BuiltAgentCore core;
  final RecordingLogger logger;
  final ScriptedStreamFunction model;
  final MemorySessionStore store;

  Future<AgentSession> session({ModeId? mode}) => core.runtime.createSession(
    SessionSpec(cwd: '/proj', mode: mode, mcpServers: _servers),
  );
}

Map<String, Object?> toolCallStep(
  String id,
  String name,
  Map<String, Object?> arguments,
) => {
  'reply': [
    {
      'toolCall': {'id': id, 'name': name, 'arguments': arguments},
    },
  ],
};

Map<String, Object?> endStep() => {
  'reply': [
    {'text': 'done'},
  ],
};
