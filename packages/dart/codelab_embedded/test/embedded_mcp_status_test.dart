import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/src/assemble.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/acp_client.dart';
import 'support/memory_host.dart';

/// Состояние MCP-серверов для хоста (embedded-agent «Состояние MCP-серверов
/// для хоста»; design.md change `add-provider-setup-ui`, D12, решение Q18):
/// `EmbeddedAgent.mcpStatus(sessionId)` — структурный статус без промпта и
/// без разбора `/mcp list` (SETUP-11). Серверы — `FakeMcpServer`, модель —
/// сценарий без шагов: любой запрос к ней видно в `requests`.
void main() {
  late RecordingLogger logger;
  late FakeClock clock;
  late Map<String, FakeMcpServer> servers;
  late ScriptedStreamFunction model;
  EmbeddedAgent? agent;
  TestAcpClient? client;

  setUp(() {
    logger = RecordingLogger();
    clock = FakeClock();
    servers = {
      'github': FakeMcpServer(
        era: FakeMcpEra.modern,
        tools: [FakeMcpTool('search'), FakeMcpTool('issue')],
      ),
    };
    model = ScriptedStreamFunction.fromJson({'steps': const []}, clock: clock);
  });

  tearDown(() async {
    await client?.close();
    await agent?.dispose();
    agent = client = null;
  });

  Future<String> open({bool withServer = true}) async {
    // Профиль требует оба транспорта (`stdio` и `http`), как у настоящего
    // хоста: фабрика в памяти обслуживает оба.
    final factory = FakeMcpTransportFactory(servers);
    final connector = McpClientConnector(
      transports: McpTransports(stdio: factory, http: factory),
      clock: clock,
    );
    final services = memoryServices(
      logger,
      MockClient((_) async => throw StateError('no network')),
      mcp: connector,
    );
    agent = await assembleEmbeddedAgent(
      config: memoryConfig(),
      services: services,
      models: FixedModelCatalog([memoryConfig().core.defaultModel]),
      streamFunction: model.call,
    );
    client = TestAcpClient(agent!.clientTransport);
    await client!.start();
    await client!.initialize();
    final created = await client!.call('session/new', {
      'cwd': '/t',
      'mcpServers': [
        if (withServer)
          {
            'name': 'github',
            'command': '/usr/bin/github',
            'args': <Object?>[],
            'env': <Object?>[],
          },
      ],
    });
    return created['sessionId']! as String;
  }

  test('статус без промпта: github в connected с числом инструментов; '
      'к модели не было ни одного запроса (сценарий «Статус без '
      'промпта»)', () async {
    final id = await open();

    final port = agent!.mcpStatus(id);

    expect(port, isNotNull);
    final github = port!.servers.single;
    expect(github.name, 'github');
    expect(github.state, McpServerState.connected);
    expect(github.toolCount, 2);
    expect(model.requests, isEmpty, reason: 'промпт ради статуса не нужен');
    expect(client!.agentText, isEmpty);
  });

  test('сбой сервера приходит в changes, а reconnect(name) порта '
      'переподключает его', () async {
    final id = await open();
    final port = agent!.mcpStatus(id)!;
    final failed = port.changes
        .firstWhere((l) => l.any((s) => s.state == McpServerState.failed))
        .timeout(const Duration(seconds: 5));

    servers['github']!.crash();

    expect((await failed).single.name, 'github');
    final connected = port.changes
        .firstWhere((l) => l.single.state == McpServerState.connected)
        .timeout(const Duration(seconds: 5));
    await port.reconnect('github');
    expect((await connected).single.state, McpServerState.connected);
  });

  test('сессия без MCP-серверов: порт есть, снимок пуст (Q18)', () async {
    final id = await open(withServer: false);

    final port = agent!.mcpStatus(id);

    expect(port, isNotNull);
    expect(port!.servers, isEmpty);
  });

  test('неизвестная сессия — null', () async {
    await open();

    expect(agent!.mcpStatus('no-such-session'), isNull);
  });

  test(
    'закрытый агент: поток порта завершён (сценарий «Закрытие агента»)',
    () async {
      final id = await open();
      final port = agent!.mcpStatus(id)!;
      final done = Completer<void>();
      port.changes.listen((_) {}, onDone: done.complete);

      await agent!.dispose();

      await done.future.timeout(const Duration(seconds: 5));
    },
  );
}
