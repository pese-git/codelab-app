import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

AcpFixture _fixture(
  List<Map<String, Object?>> frames, {
  List<String>? roles,
  Map<String, Object?> setup = const {'cwd': '/work/demo'},
  Map<String, Object?>? after,
}) => AcpFixture.fromJson({
  'id': 'acp/driver-test',
  'spec': ['05-Prompt Turn.md#1-user-message'],
  'description': 'Фикстура теста клиентского драйвера.',
  'roles': ?roles,
  'setup': setup,
  'frames': frames,
  'after': ?after,
}, fileName: 'driver-test.json');

Map<String, Object?> _prompt(String text) => {
  'dir': 'c2a',
  'frame': {
    'jsonrpc': '2.0',
    'id': {r'$capture': 'promptId'},
    'method': 'session/prompt',
    'params': {
      'sessionId': r'${sessionId}',
      'prompt': [
        {'type': 'text', 'text': text},
      ],
    },
  },
};

Map<String, Object?> _a2c(Map<String, Object?> frame, {bool repeat = false}) =>
    {'dir': 'a2c', 'frame': frame, if (repeat) 'repeat': '+'};

Map<String, Object?> _c2a(Map<String, Object?> frame) => {
  'dir': 'c2a',
  'frame': frame,
};

Map<String, Object?> _endTurn() => _a2c({
  'jsonrpc': '2.0',
  'id': r'${promptId}',
  'result': {'stopReason': 'end_turn'},
});

final _promptTextEndTurn = [
  _prompt('Привет'),
  {
    'dir': 'a2c',
    'repeat': '+',
    'frame': {
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': r'${sessionId}',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {
            'type': 'text',
            'text': {r'$any': true},
          },
        },
      },
    },
    'match': {r'$text': 'Здравствуйте!'},
  },
  _endTurn(),
];

/// Drives [AcpClientApplication] the way a user would: connect, open a
/// session, send the prompt of the expected `session/prompt` frame.
final class _AppHooks {
  _AppHooks(this.env)
    : app = AcpClientApplication(
        transport: FakeAcpTransport(),
        textFileReader: env.fileSystem,
        textFileWriter: env.fileSystem,
        terminalProcessRunner: env.terminal,
      );

  final ClientFixtureEnvironment env;
  final AcpClientApplication app;

  void onBeforeExpect(ClientFixtureStep<AcpClientApplication> step) {
    switch (step.expected['method']) {
      case 'initialize':
        step.track(app.connect(env.transport));
      case 'session/new':
        step.track(app.createSession(CreateSessionCommand(cwd: env.cwd)));
      case 'session/prompt':
        final params = step.expected['params']! as Map<String, Object?>;
        final prompt = (params['prompt']! as List).cast<Map<String, Object?>>();
        step.track(
          app.sendPrompt(
            SendPromptCommand(
              sessionId: SessionId(params['sessionId']! as String),
              prompt: [
                for (final block in prompt)
                  ContentBlock.text(text: block['text']! as String),
              ],
            ),
          ),
        );
    }
  }
}

Future<ClientFixtureResult<AcpClientApplication>> _run(
  AcpFixture fixture, {
  Duration frameTimeout = const Duration(seconds: 5),
}) async {
  late _AppHooks hooks;
  final result = await runClientFixture<AcpClientApplication>(
    fixture,
    (env) {
      hooks = _AppHooks(env);
      return hooks.app;
    },
    onBeforeExpect: (step) => hooks.onBeforeExpect(step),
    frameTimeout: frameTimeout,
  );
  addTearDown(hooks.app.dispose);
  return result;
}

Matcher _failure({required int frame, String? mismatch}) =>
    isA<ClientFixtureFailure>()
        .having((f) => f.fixtureId, 'fixtureId', 'acp/driver-test')
        .having((f) => f.frameIndex, 'frameIndex', frame)
        .having(
          (f) => f.toString(),
          'toString',
          mismatch == null ? anything : contains(mismatch),
        );

void main() {
  test('a fixture without the client role is skipped with a reason', () async {
    var factoryCalled = false;
    final result = await runClientFixture<Object>(
      _fixture(_promptTextEndTurn, roles: ['agent']),
      (env) {
        factoryCalled = true;
        return Object();
      },
    );

    expect(result.skipped, isTrue);
    expect(result.skipReason, contains('client'));
    expect(factoryCalled, isFalse);
  });

  test('prompt → text → end_turn passes on AcpClientApplication', () async {
    final result = await _run(_fixture(_promptTextEndTurn));

    expect(result.skipped, isFalse);
    final session = result.client!.sessions.single;
    expect(session.id, const SessionId(standardFixtureSessionId));
    expect(session.turns.single.status, PromptTurnStatus.completed);
  });

  test('a c2a mismatch fails with the frame index and the JSON path', () async {
    final fixture = _fixture(
      [
        _prompt('Прочитай README'),
        _a2c({
          'jsonrpc': '2.0',
          'id': {r'$capture': 'read1'},
          'method': 'fs/read_text_file',
          'params': {'sessionId': r'${sessionId}', 'path': r'${cwd}/README.md'},
        }),
        _c2a({
          'jsonrpc': '2.0',
          'id': r'${read1}',
          'result': {'content': 'bar\n'},
        }),
        _endTurn(),
      ],
      setup: {
        'cwd': '/work/demo',
        'files': {'README.md': 'foo\n'},
      },
    );

    await expectLater(
      _run(fixture),
      throwsA(
        _failure(
          frame: 2,
          mismatch: r'$.result.content: expected "bar\n", got "foo\n"',
        ),
      ),
    );
  });

  test('a missing c2a frame times out with the frame index', () async {
    final frames = [
      ..._promptTextEndTurn,
      _c2a({'jsonrpc': '2.0', 'method': 'session/cancel'}),
    ];

    await expectLater(
      _run(_fixture(frames), frameTimeout: const Duration(milliseconds: 200)),
      throwsA(_failure(frame: 3, mismatch: 'timed out')),
    );
  });

  test('fs/* is served from setup.files and after.files is checked', () async {
    final fixture = _fixture(
      [
        _prompt('Почини README'),
        _a2c({
          'jsonrpc': '2.0',
          'id': {r'$capture': 'read1'},
          'method': 'fs/read_text_file',
          'params': {
            'sessionId': r'${sessionId}',
            'path': r'${cwd}/README.md',
            'line': 2,
            'limit': 1,
          },
        }),
        _c2a({
          'jsonrpc': '2.0',
          'id': r'${read1}',
          'result': {'content': 'foo'},
        }),
        _a2c({
          'jsonrpc': '2.0',
          'id': {r'$capture': 'write1'},
          'method': 'fs/write_text_file',
          'params': {
            'sessionId': r'${sessionId}',
            'path': r'${cwd}/README.md',
            'content': '# title\nbar\n',
          },
        }),
        // 09-File System.md shows `"result": null`, 17-Schema.md types
        // WriteTextFileResponse as an object; both readings are accepted.
        _c2a({
          'jsonrpc': '2.0',
          'id': r'${write1}',
          'result': {
            r'$oneOf': [null, <String, Object?>{}],
          },
        }),
        _endTurn(),
      ],
      setup: {
        'cwd': '/work/demo',
        'files': {'README.md': '# title\nfoo\n'},
      },
      after: {
        'files': {'README.md': '# title\nbar\n'},
      },
    );

    final result = await _run(fixture);

    expect(result.environment!.fileSystem.files, {
      'README.md': '# title\nbar\n',
    });
  });

  test('after.files mismatch fails the fixture', () async {
    final fixture = _fixture(
      _promptTextEndTurn,
      setup: {
        'cwd': '/work/demo',
        'files': {'README.md': 'old\n'},
      },
      after: {
        'files': {'README.md': 'new\n'},
      },
    );

    await expectLater(
      _run(fixture),
      throwsA(
        isA<ClientFixtureFailure>().having(
          (f) => f.toString(),
          'toString',
          contains('README.md'),
        ),
      ),
    );
  });

  test('terminal/* is served from setup.terminal', () async {
    final fixture = _fixture(
      [
        _prompt('Покажи файлы'),
        _a2c({
          'jsonrpc': '2.0',
          'id': {r'$capture': 'create1'},
          'method': 'terminal/create',
          'params': {
            'sessionId': r'${sessionId}',
            'command': 'ls',
            'args': ['-la'],
            'cwd': r'${cwd}',
          },
        }),
        _c2a({
          'jsonrpc': '2.0',
          'id': r'${create1}',
          'result': {
            'terminalId': {r'$capture': 'terminalId'},
          },
        }),
        _a2c({
          'jsonrpc': '2.0',
          'id': {r'$capture': 'wait1'},
          'method': 'terminal/wait_for_exit',
          'params': {
            'sessionId': r'${sessionId}',
            'terminalId': r'${terminalId}',
          },
        }),
        _c2a({
          'jsonrpc': '2.0',
          'id': r'${wait1}',
          'result': {
            r'$partial': {'exitCode': 0},
          },
        }),
        _a2c({
          'jsonrpc': '2.0',
          'id': {r'$capture': 'output1'},
          'method': 'terminal/output',
          'params': {
            'sessionId': r'${sessionId}',
            'terminalId': r'${terminalId}',
          },
        }),
        _c2a({
          'jsonrpc': '2.0',
          'id': r'${output1}',
          'result': {
            r'$partial': {'output': 'README.md\n', 'truncated': false},
          },
        }),
        _endTurn(),
      ],
      setup: {
        'cwd': '/work/demo',
        'terminal': {
          'ls -la': {'output': 'README.md\n', 'exitCode': 0},
        },
      },
    );

    final result = await _run(fixture);

    expect(result.environment!.terminal.started.single.command, 'ls');
  });

  test('an extra frame from the client fails the fixture', () async {
    final fixture = _fixture(
      [
        _prompt('Прочитай README'),
        _a2c({
          'jsonrpc': '2.0',
          'id': 'read-unanswered',
          'method': 'fs/read_text_file',
          'params': {'sessionId': r'${sessionId}', 'path': r'${cwd}/README.md'},
        }),
        _endTurn(),
      ],
      setup: {
        'cwd': '/work/demo',
        'files': {'README.md': 'x\n'},
      },
    );

    await expectLater(
      _run(fixture),
      throwsA(
        isA<ClientFixtureFailure>().having(
          (f) => f.toString(),
          'toString',
          allOf(contains('unexpected'), contains('read-unanswered')),
        ),
      ),
    );
  });

  test('an error of a user action surfaces instead of a timeout', () async {
    final fixture = _fixture(_promptTextEndTurn);

    await expectLater(
      runClientFixture<Object>(
        fixture,
        (env) => Object(),
        onBeforeExpect: (step) =>
            step.track(Future<void>.error(StateError('action failed'))),
      ),
      throwsA(
        isA<ClientFixtureFailure>().having(
          (f) => f.toString(),
          'toString',
          contains('action failed'),
        ),
      ),
    );
  });

  test('the standard handshake is replaced by fixture frames on '
      'skipInitialize', () async {
    final fixture = _fixture(
      [
        _c2a({
          'jsonrpc': '2.0',
          'id': {r'$capture': 'initId'},
          'method': 'initialize',
          'params': {
            r'$partial': {'protocolVersion': 1},
          },
        }),
        _a2c({
          'jsonrpc': '2.0',
          'id': r'${initId}',
          'result': {'protocolVersion': 1, 'agentCapabilities': {}},
        }),
      ],
      setup: {'cwd': '/work/demo', 'skipInitialize': true},
    );

    final result = await _run(fixture);

    expect(result.client!.connectionState, isA<ClientConnectionReady>());
    expect(result.client!.sessions, isEmpty);
  });

  group('FixtureTerminalProcessRunner', () {
    test('a script with exitCode exits at once with its output', () async {
      final runner = FixtureTerminalProcessRunner({
        '/bin/sh -c echo hi': const FixtureTerminalCommand(
          output: 'hi\n',
          exitCode: 0,
        ),
      });
      final handle = await runner.start(
        command: '/bin/sh',
        args: ['-c', 'echo hi'],
        env: const {},
        cwd: '/work/demo',
      );

      expect(handle.output, 'hi\n');
      expect(await handle.waitForExit(), isA<TerminalProcessExited>());
    });

    test('a script without exitCode runs until killed', () async {
      final runner = FixtureTerminalProcessRunner({
        'dart test': const FixtureTerminalCommand(output: 'Running...\n'),
      });
      final handle = await runner.start(
        command: 'dart',
        args: ['test'],
        env: const {},
        cwd: '/work/demo',
      );

      expect(handle.state, isA<TerminalProcessRunning>());
      await handle.kill();
      expect(
        await handle.waitForExit(),
        isA<TerminalProcessExited>().having(
          (s) => s.signal,
          'signal',
          'SIGTERM',
        ),
      );
    });
  });
}
