// Headless-раннер: одобрения, таймаут, загрузка сессии, опции и прерывание
// (tasks 4.3, 4.7; spec cli-headless «Политика одобрений headless»,
// «Источники промпта headless», «Коды выхода headless»; design.md change
// `add-codelab-cli`, D9).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';

const _withLoad = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

const _models = [
  {
    'type': 'select',
    'id': 'model',
    'name': 'Model',
    'category': 'model',
    'currentValue': 'gpt-5',
    'options': [
      {'value': 'gpt-5', 'name': 'GPT-5'},
      {'value': 'gpt-4', 'name': 'GPT-4'},
    ],
  },
];

void main() {
  late FakeAgent agent;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() {
    agent = FakeAgent();
    stdout = StringBuffer();
    stderr = StringBuffer();
  });
  tearDown(() => agent.dispose());

  HeadlessRunner runner({
    ApprovePolicy approve = ApprovePolicy.reject,
    Duration? timeout,
  }) => HeadlessRunner(
    workspace: agent.workspace,
    stdout: stdout,
    stderr: stderr,
    approve: approve,
    timeout: timeout,
    cancelGrace: const Duration(milliseconds: 200),
  );

  Future<Map<String, Object?>> outcomeOf(int requestId) async {
    final response = await agent.responseTo(requestId);
    final result = response.result! as Map<String, Object?>;
    return result['outcome']! as Map<String, Object?>;
  }

  group('approvals', () {
    Future<(Future<HeadlessOutcome>, JsonRpcRequest)> started(
      HeadlessRunner runner,
    ) async {
      final outcome = runner.run(
        profile: FakeAgent.profile,
        cwd: '/work',
        prompt: 'go',
      );
      await agent.acceptNewSession('s1');
      return (outcome, await agent.next(sessionPromptMethod));
    }

    test('the default policy rejects once and says so in stderr', () async {
      final (outcome, prompt) = await started(runner());

      agent.requestPermission(id: 7, sessionId: 's1', toolCallId: 'call_1');
      expect(await outcomeOf(7), {
        'outcome': 'selected',
        'optionId': 'reject-once',
      });
      agent
        ..chunk('s1', 'ok')
        ..respond(prompt, {'stopReason': 'end_turn'});

      await outcome;
      expect(
        stderr.toString(),
        contains('codelab: permission "Run call_1": reject_once (policy)'),
      );
    });

    test('allow-all warns once, allows a request and rejects a critical '
        'one', () async {
      final (outcome, prompt) = await started(
        runner(approve: ApprovePolicy.allowAll),
      );

      agent.requestPermission(id: 7, sessionId: 's1', toolCallId: 'call_1');
      expect((await outcomeOf(7))['optionId'], 'allow-once');
      agent.requestPermission(
        id: 8,
        sessionId: 's1',
        toolCallId: 'call_2',
        critical: true,
      );
      expect((await outcomeOf(8))['optionId'], 'reject-once');
      agent
        ..chunk('s1', 'ok')
        ..respond(prompt, {'stopReason': 'end_turn'});

      await outcome;
      final text = stderr.toString();
      expect(
        'allow-all'.allMatches(text.split('\n').first).length,
        1,
        reason: text,
      );
      expect(text, contains('"Run call_2": reject_once (critical)'));
    });

    test('read-only allows a read request', () async {
      final (outcome, prompt) = await started(
        runner(approve: ApprovePolicy.readOnly),
      );

      agent.requestPermission(
        id: 7,
        sessionId: 's1',
        toolCallId: 'call_1',
        kind: ToolKind.read,
      );
      expect((await outcomeOf(7))['optionId'], 'allow-once');
      agent
        ..chunk('s1', 'ok')
        ..respond(prompt, {'stopReason': 'end_turn'});
      await outcome;
    });
  });

  test('--timeout cancels the turn and gives TimedOut', () async {
    final outcome = runner(
      timeout: const Duration(milliseconds: 50),
    ).run(profile: FakeAgent.profile, cwd: '/work', prompt: 'slow');
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);

    await agent.nextNotification(sessionCancelMethod);
    agent.respond(prompt, {'stopReason': 'cancelled'});

    final result = await outcome;
    expect(result, isA<TimedOut>());
    expect(exitCodeOf(result), 130);
    expect(stderr.toString(), contains('timeout'));
  });

  test('interrupt() cancels the turn and gives the signal code', () async {
    final headless = runner();
    final outcome = headless.run(
      profile: FakeAgent.profile,
      cwd: '/work',
      prompt: 'slow',
    );
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);

    final cancel = agent.nextNotification(sessionCancelMethod);
    unawaited(headless.interrupt(143));
    await cancel;
    agent.respond(prompt, {'stopReason': 'cancelled'});

    expect(exitCodeOf(await outcome), 143);
  });

  test('interrupt() does not wait forever for an agent that never '
      'answers', () async {
    final headless = runner();
    final outcome = headless.run(
      profile: FakeAgent.profile,
      cwd: '/work',
      prompt: 'slow',
    );
    await agent.acceptNewSession('s1');
    await agent.next(sessionPromptMethod);

    unawaited(headless.interrupt(130));

    expect(exitCodeOf(await outcome.timeout(const Duration(seconds: 2))), 130);
  });

  group('sessions', () {
    test('--resume loads the session and prints only the new '
        'answer', () async {
      await agent.dispose();
      agent = FakeAgent(
        capabilities: _withLoad,
        sessions: const ListSessionsResponse(sessions: []),
      );

      final outcome = runner().run(
        profile: FakeAgent.profile,
        cwd: '/work',
        prompt: 'more',
        resume: 'old',
      );
      final load = await agent.next(sessionLoadMethod);
      expect((load.params! as Map<String, Object?>)['sessionId'], 'old');
      agent
        ..chunk('old', 'replayed answer')
        ..respond(load, const <String, Object?>{});
      final prompt = await agent.next(sessionPromptMethod);
      agent
        ..chunk('old', 'new answer')
        ..respond(prompt, {'stopReason': 'end_turn'});

      expect(exitCodeOf(await outcome), 0);
      expect(stdout.toString(), 'new answer\n');
    });

    test('--resume without loadSession is 1 with the reason', () async {
      final result = await runner().run(
        profile: FakeAgent.profile,
        cwd: '/work',
        prompt: 'more',
        resume: 'old',
      );

      expect(exitCodeOf(result), 1);
      expect(stderr.toString(), contains('cannot load sessions'));
    });

    test('--continue loads the latest session of the folder', () async {
      await agent.dispose();
      agent = FakeAgent(
        capabilities: _withLoad,
        sessions: const ListSessionsResponse(
          sessions: [
            SessionInfo(
              sessionId: SessionId('older'),
              cwd: '/work',
              updatedAt: '2026-10-01T10:00:00Z',
            ),
            SessionInfo(
              sessionId: SessionId('newer'),
              cwd: '/work',
              updatedAt: '2026-10-02T10:00:00Z',
            ),
          ],
        ),
      );

      final outcome = runner().run(
        profile: FakeAgent.profile,
        cwd: '/work',
        prompt: 'more',
        continueLast: true,
      );
      final load = await agent.next(sessionLoadMethod);
      expect((load.params! as Map<String, Object?>)['sessionId'], 'newer');
      agent.respond(load, const <String, Object?>{});
      final prompt = await agent.next(sessionPromptMethod);
      agent
        ..chunk('newer', 'ok')
        ..respond(prompt, {'stopReason': 'end_turn'});

      expect(exitCodeOf(await outcome), 0);
    });

    test('--continue without sessions is 1', () async {
      await agent.dispose();
      agent = FakeAgent(
        capabilities: _withLoad,
        sessions: const ListSessionsResponse(sessions: []),
      );

      final result = await runner().run(
        profile: FakeAgent.profile,
        cwd: '/work',
        prompt: 'more',
        continueLast: true,
      );

      expect(exitCodeOf(result), 1);
      expect(stderr.toString(), contains('No session to continue'));
    });
  });

  group('config options', () {
    test('--model is set before the prompt', () async {
      final outcome = runner().run(
        profile: FakeAgent.profile,
        cwd: '/work',
        prompt: 'go',
        model: 'gpt-4',
      );
      await agent.acceptNewSession('s1', configOptions: _models);
      final set = await agent.next(sessionSetConfigOptionMethod);
      expect(set.params, containsPair('configId', 'model'));
      expect(set.params, containsPair('value', 'gpt-4'));
      agent.respond(set, {'configOptions': _models});
      final prompt = await agent.next(sessionPromptMethod);
      agent
        ..chunk('s1', 'ok')
        ..respond(prompt, {'stopReason': 'end_turn'});

      expect(exitCodeOf(await outcome), 0);
    });

    test('an unknown --model value is 1 and no prompt is sent', () async {
      final outcome = runner().run(
        profile: FakeAgent.profile,
        cwd: '/work',
        prompt: 'go',
        model: 'zzz',
      );
      await agent.acceptNewSession('s1', configOptions: _models);

      expect(exitCodeOf(await outcome), 1);
      expect(stderr.toString(), contains('gpt-5, gpt-4'));
      expect(
        agent.transport.sentMessages.whereType<JsonRpcRequest>().map(
          (r) => r.method,
        ),
        isNot(contains(sessionPromptMethod)),
      );
    });

    test('--mode without a mode option is 1', () async {
      final outcome = runner().run(
        profile: FakeAgent.profile,
        cwd: '/work',
        prompt: 'go',
        mode: 'ask',
      );
      await agent.acceptNewSession('s1', configOptions: _models);

      expect(exitCodeOf(await outcome), 1);
      expect(stderr.toString(), contains('"mode"'));
    });
  });
}
