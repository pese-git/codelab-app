// `/sessions` и `/resume` (tasks 7.5; spec codelab-cli «Сессии в REPL»;
// design.md change `add-codelab-cli`, D7).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:test/test.dart';

import '../../support/fake_agent.dart';
import '../../support/repl_harness.dart';

const _withLoad = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

const _listed = ListSessionsResponse(
  sessions: [
    SessionInfo(
      sessionId: SessionId('old-1'),
      cwd: '/work',
      title: 'Fix the login bug',
      updatedAt: '2026-10-01T10:00:00Z',
    ),
    SessionInfo(
      sessionId: SessionId('old-2'),
      cwd: '/work',
      title: 'Write docs',
      updatedAt: '2026-10-02T10:00:00Z',
    ),
  ],
);

void main() {
  late ReplHarness repl;

  tearDown(() => repl.dispose());

  Future<void> start(FakeAgent agent) async {
    repl = ReplHarness(agent: agent);
    await repl.start();
  }

  test('/sessions numbers the sessions of the folder with titles', () async {
    await start(FakeAgent(capabilities: _withLoad, sessions: _listed));

    repl.line('/sessions');

    await repl.waitText('Write docs');
    expect(repl.lastOutput, contains('Fix the login bug'));
    expect(RegExp(r'\b1\. ').hasMatch(repl.lastOutput), isTrue);
    expect(RegExp(r'\b2\. ').hasMatch(repl.lastOutput), isTrue);
  });

  test('/resume <n> loads the listed session and prints its '
      'history', () async {
    await start(FakeAgent(capabilities: _withLoad, sessions: _listed));
    repl.line('/sessions');
    await repl.waitText('Write docs');
    final number = RegExp(
      r'(\d+)\. Write docs',
    ).firstMatch(repl.lastOutput)!.group(1)!;

    repl.line('/resume $number');

    final load = await repl.agent.next(sessionLoadMethod);
    expect((load.params! as Map<String, Object?>)['sessionId'], 'old-2');
    repl.agent
      ..chunk('old-2', 'earlier answer')
      ..respond(load, const <String, Object?>{});
    await repl.waitText('earlier answer');

    repl.line('more');
    final prompt = await repl.agent.next(sessionPromptMethod);
    expect((prompt.params! as Map<String, Object?>)['sessionId'], 'old-2');
  });

  test('/resume <id> loads by id', () async {
    await start(FakeAgent(capabilities: _withLoad, sessions: _listed));

    repl.line('/resume old-1');

    final load = await repl.agent.next(sessionLoadMethod);
    expect((load.params! as Map<String, Object?>)['sessionId'], 'old-1');
  });

  test('/resume without loadSession says so without a request', () async {
    await start(FakeAgent());

    repl.line('/resume old-1');

    await repl.waitText('cannot load sessions');
    expect(repl.sentMethods, isNot(contains(sessionLoadMethod)));
  });

  test('/resume without an argument prints the usage', () async {
    await start(FakeAgent());

    repl.line('/resume');

    await repl.waitText('/resume <n|id>');
  });
}
