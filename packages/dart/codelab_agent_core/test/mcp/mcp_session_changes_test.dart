import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../mcp/fake_mcp_connector.dart';
import '../permissions/fake_gate.dart';

McpStdioServerConfig _stdio(String name) => McpStdioServerConfig(
  name: name,
  command: '/usr/bin/$name',
  origin: McpServerOrigin.session,
);

McpServerSummary _summary(
  String name,
  McpServerState state, {
  int tools = 0,
  String? lastError,
  Duration? retryIn,
}) => McpServerSummary(
  name: name,
  toolCount: tools,
  state: state,
  lastError: lastError,
  retryIn: retryIn,
);

String _line(List<McpServerSummary> list) =>
    list.map((s) => '${s.name}:${s.state.name}:${s.toolCount}').join(',');

/// Поток состояний серверов сессии на уровне ядра (agent-mcp-client «Поток
/// состояний серверов сессии»; `17-5-agent-setup.md`, OQ4; design.md change
/// `add-provider-setup-ui`, D12, Q18): `McpSessionTools.changes` коннектора
/// доходит до хоста через `AgentRuntime.mcpStatus(SessionId)`. Настоящий
/// коннектор проверяет `codelab_agent_mcp/test/connector_changes_test.dart`.
void main() {
  late FakeMcpConnector mcp;
  late CoreHarness h;

  Future<AgentSession> open({List<McpServerConfig> servers = const []}) {
    mcp = FakeMcpConnector();
    h = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      steps: const [],
      mcp: mcp,
    );
    return h.core.runtime.createSession(
      SessionSpec(cwd: '/proj', mcpServers: servers),
    );
  }

  test('сбой и восстановление сервера приходят подписчику по порядку '
      '(сценарий «Сбой и восстановление сервера»)', () async {
    final session = await open(servers: [_stdio('docs')]);
    final port = h.core.runtime.mcpStatus(session.id)!;
    final seen = <String>[];
    port.changes.listen((list) => seen.add(_line(list)));
    final tools = mcp.sessions.single;

    tools.emit([
      _summary(
        'docs',
        McpServerState.failed,
        lastError: 'process exited',
        retryIn: const Duration(seconds: 1),
      ),
    ]);
    tools.emit([_summary('docs', McpServerState.connecting)]);
    tools.emit([_summary('docs', McpServerState.connected, tools: 2)]);

    expect(seen, ['docs:failed:0', 'docs:connecting:0', 'docs:connected:2']);
    expect(_line(port.servers), 'docs:connected:2');
  });

  test('поток не повторяет последнее значение новому подписчику; снимок — '
      'servers', () async {
    final session = await open(servers: [_stdio('docs')]);
    final port = h.core.runtime.mcpStatus(session.id)!;
    mcp.sessions.single.emit([
      _summary('docs', McpServerState.connected, tools: 1),
    ]);
    final late = <String>[];

    port.changes.listen((list) => late.add(_line(list)));
    await pumpEventQueue();

    expect(late, isEmpty);
    expect(_line(port.servers), 'docs:connected:1');
  });

  test(
    'поток широковещательный: два подписчика получают одно и то же',
    () async {
      final session = await open(servers: [_stdio('docs')]);
      final port = h.core.runtime.mcpStatus(session.id)!;
      final a = <String>[];
      final b = <String>[];
      port.changes.listen((l) => a.add(_line(l)));
      port.changes.listen((l) => b.add(_line(l)));

      mcp.sessions.single.emit([_summary('docs', McpServerState.connecting)]);

      expect(a, ['docs:connecting:0']);
      expect(b, a);
    },
  );

  test('reconnect(name) порта доходит до McpSessionTools.reconnect', () async {
    final session = await open(servers: [_stdio('docs')]);
    final port = h.core.runtime.mcpStatus(session.id)!;

    await port.reconnect('docs');

    expect(mcp.sessions.single.reconnected, ['docs']);
  });

  test('поток закрывается вместе с сессией (сценарий «Поток закрывается с '
      'сессией»)', () async {
    final session = await open(servers: [_stdio('docs')]);
    final port = h.core.runtime.mcpStatus(session.id)!;
    final done = Completer<void>();
    port.changes.listen((_) {}, onDone: done.complete);

    await session.close();

    await done.future.timeout(const Duration(seconds: 1));
    expect(mcp.sessions.single.closed, 1);
  });

  test('dispose() рантайма закрывает потоки открытых сессий', () async {
    final session = await open(servers: [_stdio('docs')]);
    final port = h.core.runtime.mcpStatus(session.id)!;
    final done = Completer<void>();
    port.changes.listen((_) {}, onDone: done.complete);

    await h.core.runtime.dispose();

    await done.future.timeout(const Duration(seconds: 1));
  });

  test('после закрытия сессии события коннектора до подписчика не '
      'доходят', () async {
    final session = await open(servers: [_stdio('docs')]);
    final port = h.core.runtime.mcpStatus(session.id)!;
    final seen = <String>[];
    port.changes.listen((l) => seen.add(_line(l)));
    await session.close();

    mcp.sessions.single.emit([_summary('docs', McpServerState.failed)]);
    await pumpEventQueue();

    expect(seen, isEmpty);
  });
}
