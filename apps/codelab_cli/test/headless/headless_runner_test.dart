// Headless-раннер поверх `ClientWorkspace` (tasks 3.3; spec cli-headless
// «Вывод headless», «Коды выхода headless»; design.md change
// `add-codelab-cli`, D9).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
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
    tokenSource: fakeTokenSource,
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

  // Spec cli-headless / codelab-cli: операции со списком задач — одна строка
  // в stderr на элемент, когда он перестал расти (D27).
  test('merged list operations are written to stderr once, stdout stays the '
      'answer', () async {
    final outcome = start(runner());
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);
    final entries = <Map<String, Object?>>[];
    for (var i = 1; i <= 4; i++) {
      entries.add({
        'content': 'Task $i',
        'status': 'pending',
        'priority': 'medium',
        '_meta': {
          'codelab': {
            'task': {'id': '$i'},
          },
        },
      });
      agent
        ..update('s1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-$i',
          'title': 'Update the list',
          'kind': 'think',
          'status': 'in_progress',
        })
        ..update('s1', {
          'sessionUpdate': 'plan',
          'entries': List.of(entries),
          '_meta': {
            'codelab': {
              'taskChange': {
                'op': 'create',
                'actor': 'main',
                'toolCallId': 'call-$i',
                'changed': ['$i'],
                'deleted': <String>[],
              },
            },
          },
        })
        ..update('s1', {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-$i',
          'status': 'completed',
        });
    }
    agent
      ..chunk('s1', 'done')
      ..respond(prompt, {'stopReason': 'end_turn'});

    await outcome;
    expect(stdout.toString(), 'done\n');
    expect(
      'Tasks #1–#4 added to the plan'.allMatches(stderr.toString()),
      hasLength(1),
    );
    for (final partial in [
      'Task #1 added to the plan',
      'Tasks #1–#2 added to the plan',
      'Tasks #1–#3 added to the plan',
    ]) {
      expect(stderr.toString(), isNot(contains(partial)));
    }
  });

  test(
    'operations split by a read call: both lines in order, once each',
    () async {
      final outcome = start(runner());
      await agent.acceptNewSession('s1');
      final prompt = await agent.next(sessionPromptMethod);
      Map<String, Object?> create(String id) => {
        'sessionUpdate': 'plan',
        'entries': [
          for (var i = 1; i <= int.parse(id); i++)
            {
              'content': 'Task $i',
              'status': 'pending',
              'priority': 'medium',
              '_meta': {
                'codelab': {
                  'task': {'id': '$i'},
                },
              },
            },
        ],
        '_meta': {
          'codelab': {
            'taskChange': {
              'op': 'create',
              'actor': 'main',
              'toolCallId': 'c$id',
              'changed': [id],
              'deleted': <String>[],
            },
          },
        },
      };
      Map<String, Object?> think(String id) => {
        'sessionUpdate': 'tool_call',
        'toolCallId': id,
        'title': 'Update the list',
        'kind': 'think',
        'status': 'in_progress',
      };
      Map<String, Object?> done(String id) => {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': id,
        'status': 'completed',
      };
      agent
        ..update('s1', think('c1'))
        ..update('s1', create('1'))
        ..update('s1', done('c1'))
        ..update('s1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'r1',
          'title': 'Read lib/a.dart',
          'kind': 'read',
          'status': 'pending',
        })
        ..update('s1', done('r1'))
        ..update('s1', think('c2'))
        ..update('s1', create('2'))
        ..update('s1', done('c2'))
        ..respond(prompt, {'stopReason': 'end_turn'});

      await outcome;
      final err = stderr.toString();
      expect(err, contains('Task #1 added to the plan'));
      expect(err, contains('Task #2 added to the plan'));
      expect(
        err.indexOf('Task #1 added'),
        lessThan(err.indexOf('Read lib/a.dart')),
      );
      expect(
        err.indexOf('Read lib/a.dart'),
        lessThan(err.indexOf('Task #2 added')),
      );
      for (final line in [
        'Task #1 added',
        'Task #2 added',
        'Read lib/a.dart',
      ]) {
        expect(line.allMatches(err), hasLength(1), reason: line);
      }
    },
  );

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

  // Заметка исхода хода (design D27, Q33; spec acp-client-kit «Инкрементальная
  // проекция транскрипта»): headless печатает заметку kit-а в stderr, а код
  // выхода остаётся прежним (ход завершён ответом агента, `exitCodeOf`).
  test('max_tokens after thoughts prints the stop notice to stderr and '
      'keeps exit code 1', () async {
    final outcome = start(runner());
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);
    agent
      ..update('s1', {
        'sessionUpdate': 'agent_thought_chunk',
        'content': {'type': 'text', 'text': 'thinking'},
      })
      ..respond(prompt, {'stopReason': 'max_tokens'});

    final result = await outcome;
    expect(result, isA<TurnCompleted>());
    expect(exitCodeOf(result), 1);
    expect(stdout.toString(), isEmpty);
    expect(
      stderr.toString(),
      contains(
        'codelab: The model reached its token limit, so the turn ended.',
      ),
    );
    expect(stderr.toString(), isNot(contains('empty response')));
  });

  test('refusal after text keeps the answer on stdout and prints the notice '
      'to stderr', () async {
    final outcome = start(runner());
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);
    agent
      ..chunk('s1', 'I cannot do that')
      ..respond(prompt, {'stopReason': 'refusal'});

    final result = await outcome;
    expect(exitCodeOf(result), 1);
    expect(stdout.toString(), 'I cannot do that\n');
    expect(
      stderr.toString(),
      contains('codelab: The agent refused to continue.'),
    );
  });

  test('end_turn with an answer prints no stop notice', () async {
    final outcome = start(runner());
    await agent.acceptNewSession('s1');
    final prompt = await agent.next(sessionPromptMethod);
    agent
      ..chunk('s1', 'done')
      ..respond(prompt, {'stopReason': 'end_turn'});

    expect(exitCodeOf(await outcome), 0);
    expect(stderr.toString(), isEmpty);
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

  group('a handshake rejected because of the token', () {
    Future<HeadlessOutcome> startWith(
      int status,
      WebSocketProfile profile,
    ) async {
      await agent.dispose();
      agent = FakeAgent(openError: handshakeRejected(status));
      return runner().run(profile: profile, cwd: '/work', prompt: 'hello');
    }

    test('with a token the message says the agent rejected it', () async {
      final result = await startWith(401, wsProfile());

      expect(result, isA<ConnectFailed>());
      expect(exitCodeOf(result), 1);
      expect(
        stderr.toString(),
        'codelab: cannot start the agent ws://127.0.0.1:9: '
        'the agent rejected the token (HTTP 401).\n',
      );
      expect(stderr.toString(), isNot(contains(fakeTokenMarker)));
      for (final leak in fakeUrlLeaks) {
        expect(stderr.toString(), isNot(contains(leak)));
      }
    });

    test('without a token the message says the agent requires one', () async {
      await startWith(403, wsProfile(withToken: false));

      expect(
        stderr.toString(),
        'codelab: cannot start the agent ws://127.0.0.1:9: '
        'the agent requires a token (HTTP 403).\n',
      );
    });

    test('a reference that gives no value counts as no token', () async {
      await startWith(
        401,
        WebSocketProfile(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('ws://127.0.0.1:9/acp'),
          tokenRef: 'env:UNSET',
        ),
      );

      expect(stderr.toString(), contains('the agent requires a token'));
    });

    test('other handshake statuses keep the previous text', () async {
      await startWith(404, wsProfile());

      expect(stderr.toString(), contains('Failed to connect ACP transport.'));
      expect(stderr.toString(), isNot(contains('token')));
    });
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
