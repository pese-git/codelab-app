import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import '../support/supervisor_rig.dart';

/// Отмена настоящего ядра во время раскрытия секретов MCP-сервера (ревью
/// итерации 6; agent-runtime «Закрытие во время раскрытия секретов»):
/// `dispose()` и `close()` не ждут хранилище, не оставляют процессов, таймеров
/// и записей `mcp.server.failed`.
///
/// Ядро собрано `buildAgentCore` с настоящим `McpClientConnector` над
/// `FakeMcpServer`; хранилище секретов зависает и не отпускается никогда.
void main() {
  const secretName = 'codelab/mcp/gh/authorization';

  late FakeClock clock;
  late RecordingLogger logger;
  late Map<String, FakeMcpServer> fakes;
  late FakeMcpTransportFactory factory;
  final hanging = <String>{};
  late BuiltAgentCore core;
  late SecretResolver resolver;

  McpStdioServerConfig gh() => McpStdioServerConfig(
    name: 'gh',
    command: '/usr/bin/gh',
    origin: McpServerOrigin.config,
    secretValues: {
      'env.TOKEN': SecretTemplate([const SecretReference(secretName)]),
    },
  );

  const docs = McpStdioServerConfig(
    name: 'docs',
    command: '/usr/bin/docs',
    origin: McpServerOrigin.config,
  );

  setUp(() {
    clock = FakeClock();
    logger = RecordingLogger();
    hanging.clear();
    fakes = {
      'gh': fakeServer(['t']),
      'docs': fakeServer(['d']),
    };
    factory = FakeMcpTransportFactory(fakes);
    final model = ScriptedStreamFunction.fromJson({
      'steps': const <Object?>[],
    }, clock: clock);
    resolver = SecretResolver(
      store: _HangingStore(hanging),
      environment: const {},
      logger: logger,
    );
    core = buildAgentCore(
      profile: HostProfile.of('agent-serve').narrowed({
        HostCapability.shellExec: const CapabilityOff('тест без shell'),
        HostCapability.sessionPersistence: const CapabilityOff('в памяти'),
      }),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
        secrets: resolver,
        mcp: McpClientConnector(
          transports: McpTransports(stdio: factory, http: factory),
          clock: clock,
        ),
      ),
      config: CoreConfig(
        defaultModel: ModelRef(
          provider: 'test',
          id: 'm',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://localhost/v1'),
          contextWindow: 32000,
          maxOutputTokens: 4096,
        ),
        mcpServers: [gh(), docs],
      ),
      streamFunction: model.call,
    );
  });

  Future<void> settle() => clock.elapse(Duration.zero);

  test('dispose() during createSession: CancelledException, transports of '
      'both servers closed, no session, no failed record, no timers', () async {
    hanging.add(secretName);
    Object? outcome;
    final creating = core.runtime
        .createSession(SessionSpec(cwd: '/proj'))
        .then<void>(
          (_) => outcome = 'session',
          onError: (Object e) => outcome = e,
        );
    await settle();

    await core.runtime.dispose();
    await settle();
    await creating;

    expect(outcome, isA<CancelledException>());
    expect(fakes['docs']!.closedTransports, 1);
    expect(factory.opened, ['docs'], reason: 'gh never started');
    expect(logger.eventsOf('mcp.server.failed'), isEmpty);
    expect(clock.pendingTimers, 0);
  });

  test('session.close() during setMcpServers finishes: the server of the '
      'config comes back after the client stops shadowing it, and its secret '
      'hangs', () async {
    final session = await core.runtime.createSession(SessionSpec(cwd: '/proj'));
    // Клиент затеняет `gh`; затем перестаёт: `gh` конфига подключается заново,
    // а его секрет не читается никогда.
    await session.setMcpServers([
      const McpStdioServerConfig(name: 'gh', command: '/usr/bin/other'),
    ]);
    resolver.invalidate();
    hanging.add(secretName);
    final changing = session.setMcpServers(const []);
    await settle();

    await session.close();
    await settle();
    await changing.timeout(const Duration(seconds: 5));

    expect(logger.eventsOf('mcp.server.failed'), isEmpty);
    expect(clock.pendingTimers, 0);
  });
}

final class _HangingStore implements DescribedSecretStore {
  _HangingStore(this._hanging);

  /// Имена, чтение которых не завершается никогда.
  final Set<String> _hanging;

  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'hang', writable: false);

  @override
  Future<String?> read(String name) async {
    if (_hanging.contains(name)) {
      await Completer<void>().future;
    }
    return 'tok';
  }

  @override
  Future<void> write(String name, String value) async {}

  @override
  Future<void> delete(String name) async {}

  @override
  Future<List<String>> names() async => const [];
}
