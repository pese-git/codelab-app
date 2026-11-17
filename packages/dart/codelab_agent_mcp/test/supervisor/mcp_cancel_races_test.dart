import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/supervisor_rig.dart';

/// Отмена и гонки сессии коннектора (ревью итерации 6; design.md change
/// `add-config-writer-and-reload`, D11): отмена токена во время раскрытия
/// секретов, `setEnabled`/`reconnect` во время `replaceServers`.
void main() {
  McpStdioServerConfig secretServer(String name) => McpStdioServerConfig(
    name: name,
    command: '/usr/bin/$name',
    origin: McpServerOrigin.config,
    secretValues: {
      'env.T': SecretTemplate([const SecretReference('codelab/mcp/x/t')]),
    },
  );

  test('cancel during the expansion of the first attempt: connect returns, '
      'a server that connected before the cancel is closed, the late value '
      'is dropped, no process starts for it', () async {
    final rig = SupervisorRig({
      'gh': fakeServer(['t']),
      'b': fakeServer(['t']),
    });
    final gate = Completer<McpServerConfig>();
    final gh = secretServer('gh');
    var returned = false;
    final connecting = rig
        .connect([gh, stdio('b')], expandSecrets: (_) => gate.future)
        .whenComplete(() => returned = true);
    await rig.settle();

    rig.cancelSession();
    await rig.settle();

    expect(returned, isTrue, reason: 'the gate is still closed');
    final session = await connecting;
    expect(rig.fakes['b']!.closedTransports, 1, reason: 'b is not leaked');
    expect(rig.spy.opened, ['b']);

    gate.complete(gh.withSecrets({'env.T': 'v'}));
    await rig.settle();

    expect(rig.spy.opened, ['b'], reason: 'the late value starts nothing');
    expect(rig.log.eventsOf('mcp.server.failed'), isEmpty);
    expect(rig.clock.pendingTimers, 0);
    expect(
      session.servers.map((s) => s.state),
      isNot(contains(McpServerState.connecting)),
    );
  });

  test('close during a replaceServers whose expansion hangs: replace '
      'returns, nothing is started', () async {
    final rig = SupervisorRig({
      'b': fakeServer(['t']),
      'gh': fakeServer(['t']),
    });
    final gate = Completer<McpServerConfig>();
    final gh = secretServer('gh');
    final session = await rig.connect([
      stdio('b'),
    ], expandSecrets: (_) => gate.future);
    var done = false;
    final replacing = session
        .replaceServers([stdio('b'), gh])
        .whenComplete(() => done = true);
    await rig.settle();

    await session.close();
    await rig.settle();

    expect(done, isTrue);
    await replacing;
    gate.complete(gh.withSecrets({'env.T': 'v'}));
    await rig.settle();
    expect(rig.spy.opened, ['b']);
  });

  test('setEnabled(true) of a server that a concurrent replaceServers '
      'removes does not leave a process', () async {
    final rig = SupervisorRig({
      'a': fakeServer(['t']),
      'b': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('a', enabled: false), stdio('b')]);

    final replacing = session.replaceServers([stdio('b')]);
    await session.setEnabled('a', true);
    await replacing;
    await session.close();
    await rig.settle();

    expect(rig.spy.opened, isNot(contains('a')));
    expect(rig.fakes['a']!.closedTransports, 0);
    expect(rig.fakes['b']!.closedTransports, 1);
  });

  test('reconnect of a server that a concurrent replaceServers removes '
      'does not resurrect it', () async {
    final rig = SupervisorRig({
      'a': fakeServer(['t']),
      'b': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('a'), stdio('b')]);

    final replacing = session.replaceServers([stdio('b')]);
    await session.reconnect('a');
    await replacing;
    await rig.settle();

    expect(session.servers.map((s) => s.name), ['b']);
    expect(rig.spy.opened, ['a', 'b'], reason: 'a is not opened again');
    expect(rig.fakes['a']!.closedTransports, 1);
  });
}
