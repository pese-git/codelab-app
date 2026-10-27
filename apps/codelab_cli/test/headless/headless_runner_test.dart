// Headless-раннер поверх `ClientWorkspace` (tasks 3.3; spec cli-headless
// «Вывод headless», «Коды выхода headless»; design.md change
// `add-codelab-cli`, D9).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';

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

  HeadlessRunner runner({bool verbose = false}) => HeadlessRunner(
    workspace: agent.workspace,
    stdout: stdout,
    stderr: stderr,
    verbose: verbose,
  );

  Future<HeadlessOutcome> start(HeadlessRunner runner) =>
      runner.run(profile: FakeAgent.profile, cwd: '/work', prompt: 'hello');

  test('prints the answer deltas byte for byte and ends with a '
      'newline', () async {
    final outcome = start(runner());
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);
    expect((prompt.params! as Map<String, Object?>)['prompt'], [
      {'type': 'text', 'text': 'hello'},
    ]);

    agent
      ..chunk('s1', '# Title\n')
      ..chunk('s1', '**bold** é');
    expect(stdout.toString(), '# Title\n**bold** é');
    agent.respond(prompt, {'stopReason': 'end_turn'});

    final result = await outcome;
    expect(result, isA<TurnCompleted>());
    expect(exitCodeOf(result), 0);
    expect(stdout.toString(), '# Title\n**bold** é\n');
  });

  test('an answer ending with a newline gets no extra one', () async {
    final outcome = start(runner());
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);
    agent
      ..chunk('s1', 'done\n')
      ..respond(prompt, {'stopReason': 'end_turn'});

    await outcome;
    expect(stdout.toString(), 'done\n');
  });

  test('thoughts stay out of stdout and tool rows go to stderr', () async {
    final outcome = start(runner());
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);
    agent
      ..update('s1', {
        'sessionUpdate': 'agent_thought_chunk',
        'content': {'type': 'text', 'text': 'secret plan'},
      })
      ..update('s1', {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call_1',
        'title': 'Read lib/main.dart',
        'kind': 'read',
        'status': 'pending',
        'rawInput': {'path': 'lib/main.dart'},
      })
      ..update('s1', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1',
        'status': 'completed',
      })
      ..chunk('s1', 'done')
      ..respond(prompt, {'stopReason': 'end_turn'});

    await outcome;
    expect(stdout.toString(), 'done\n');
    expect(stderr.toString(), contains('Read lib/main.dart'));
    expect(stderr.toString(), isNot(contains('secret plan')));
    expect(stderr.toString(), isNot(contains('"path"')));
  });

  test('end_turn without an answer is an empty response', () async {
    final outcome = start(runner());
    await agent.acceptNewSession('s1');
    agent.respond(await agent.next(sessionPromptMethod), {
      'stopReason': 'end_turn',
    });

    final result = await outcome;
    expect(exitCodeOf(result), 1);
    expect(stdout.toString(), isEmpty);
    expect(stderr.toString(), isNotEmpty);
  });

  test('a JSON-RPC error on session/prompt fails the turn with the '
      'agent message', () async {
    final outcome = start(runner());
    await agent.acceptNewSession('s1');
    agent.fail(
      await agent.next(sessionPromptMethod),
      'Turn failed',
      data: {
        'codelab': {
          'errorClass': 'provider',
          'message': 'Provider is down',
          'retryable': false,
        },
      },
    );

    final result = await outcome;
    expect(result, isA<TurnFailed>());
    expect(exitCodeOf(result), 1);
    expect(stdout.toString(), isEmpty);
    expect(stderr.toString(), contains('Provider is down'));
  });

  test('a failed connection is ConnectFailed with the reason in '
      'stderr', () async {
    await agent.dispose();
    agent = FakeAgent(openError: StateError('agent not found'));

    final result = await start(runner());

    expect(result, isA<ConnectFailed>());
    expect(exitCodeOf(result), 1);
    expect(stderr.toString(), contains('agent not found'));
    expect(stderr.toString(), contains('"agent"'));
  });

  test('--verbose adds the connection diagnostics to stderr', () async {
    final outcome = start(runner(verbose: true));
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);
    agent
      ..chunk('s1', 'ok')
      ..respond(prompt, {'stopReason': 'end_turn'});

    await outcome;
    expect(stderr.toString(), isNotEmpty);
    expect(stdout.toString(), 'ok\n');
  });
}
