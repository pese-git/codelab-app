import 'dart:async';
import 'dart:io';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

/// Агентский драйвер фикстур (задача 9.1; acp-golden-fixtures «Агентский
/// драйвер фикстур»; §14.9) на заглушке агента: драйвер не зависит от
/// пакетов агента и проверяется сам по себе.
void main() {
  AcpFixture fixture(
    List<Map<String, Object?>> frames, {
    List<String>? roles,
    Map<String, Object?> setup = const {
      'cwd': '/work/demo',
      'files': {'README.md': '# foo\n'},
    },
    Map<String, Object?>? after,
  }) => AcpFixture.fromJson({
    'id': 'acp/agent-driver-test',
    'spec': ['05-Prompt Turn.md#1-user-message'],
    'description': 'Фикстура теста агентского драйвера.',
    'roles': ?roles,
    'setup': setup,
    'frames': frames,
    'after': ?after,
  }, fileName: 'agent-driver-test.json');

  final promptFrames = [
    {
      'dir': 'c2a',
      'frame': {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'session/prompt',
        'params': {
          'sessionId': r'${sessionId}',
          'prompt': [
            {'type': 'text', 'text': 'Hi'},
          ],
        },
      },
    },
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
      'match': {r'$text': 'Hello there'},
    },
    {
      'dir': 'a2c',
      'frame': {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'stopReason': 'end_turn'},
      },
    },
  ];

  test('matching frames pass; the setup reaches the agent', () async {
    late _StubAgent agent;
    late AgentFixtureSetup seen;
    late String readme;

    final result = await runAgentFixture(fixture(promptFrames), (
      transport,
      setup,
    ) async {
      seen = setup;
      readme = File('${setup.cwd}/README.md').readAsStringSync();
      return agent = _StubAgent(transport, chunks: ['Hello ', 'there']);
    });

    expect(result.skipped, isFalse);
    expect(result.variables['sessionId'], 'stub-session');
    expect(seen.profile, 'agent-serve');
    // Файлы setup лежат во временном cwd для локального листинга (§14.9).
    expect(readme, '# foo\n');
    expect(agent.stopped, isTrue);
  });

  test('a frame after the silence fails the run', () async {
    expect(
      () => runAgentFixture(
        fixture(promptFrames),
        (transport, setup) async =>
            _StubAgent(transport, chunks: ['Hello there'], extraUpdate: true),
      ),
      throwsA(
        isA<AgentFixtureFailure>().having(
          (f) => f.message,
          'message',
          contains('unexpected frames'),
        ),
      ),
    );
  });

  test('an extra fs request fails the run', () async {
    expect(
      () => runAgentFixture(
        fixture(promptFrames),
        (transport, setup) async =>
            _StubAgent(transport, chunks: ['Hello there'], extraRead: true),
      ),
      throwsA(
        isA<AgentFixtureFailure>().having(
          (f) => f.message,
          'message',
          contains('fs/read_text_file'),
        ),
      ),
    );
  });

  test('a different frame fails with the index and both frames', () async {
    expect(
      () => runAgentFixture(
        fixture(promptFrames),
        (transport, setup) async => _StubAgent(transport, chunks: ['Goodbye']),
      ),
      throwsA(
        isA<AgentFixtureFailure>()
            .having((f) => f.frameIndex, 'frameIndex', 1)
            .having((f) => f.mismatches, 'mismatches', isNotEmpty),
      ),
    );
  });

  test('a fixture without the agent role is skipped', () async {
    var started = false;

    final result = await runAgentFixture(
      fixture(promptFrames, roles: ['client']),
      (transport, setup) async {
        started = true;
        return _StubAgent(transport, chunks: const []);
      },
    );

    expect(result.skipped, isTrue);
    expect(result.skipReason, contains('agent'));
    expect(started, isFalse);
  });

  // Транспортные фикстуры играет транспортный драйвер против процесса
  // бинаря (design.md change `add-codelab-agent-binary`, D8).
  test('a transport fixture is skipped by the in-memory run', () async {
    var started = false;

    final result = await runAgentFixture(
      fixture(
        promptFrames,
        setup: const {
          'cwd': '/work/demo',
          'transport': {'kind': 'stdio'},
        },
      ),
      (transport, setup) async {
        started = true;
        return _StubAgent(transport, chunks: const []);
      },
    );

    expect(result.skipped, isTrue);
    expect(result.skipReason, contains('transport driver'));
    expect(started, isFalse);
  });

  test('a transport fixture runs over the connection of a connector', () async {
    late AgentFixtureSetup seen;

    final result = await runAgentFixtureOver(
      fixture(
        promptFrames,
        setup: const {
          'cwd': '/work/demo',
          'transport': {'kind': 'stdio'},
        },
      ),
      (setup) async {
        seen = setup;
        final link = InProcessAcpLink();
        final agent = _StubAgent(link.agent, chunks: const ['Hello ', 'there']);
        return AgentConnection(client: link.client, agent: agent);
      },
    );

    expect(result.skipped, isFalse);
    expect(seen.fixture.setup.transport!.kind, FixtureTransportKind.stdio);
  });

  test('an unused model step fails the run', () async {
    expect(
      () => runAgentFixture(
        fixture(promptFrames),
        (transport, setup) async => _StubAgent(
          transport,
          chunks: ['Hello there'],
          verifyError: StateError('step 2 was not used'),
        ),
      ),
      throwsA(
        isA<AgentFixtureFailure>().having(
          (f) => f.message,
          'message',
          contains('step 2 was not used'),
        ),
      ),
    );
  });

  test('after.files is checked against the last fs/write_text_file', () async {
    final frames = [
      promptFrames[0],
      {
        'dir': 'a2c',
        'frame': {
          'jsonrpc': '2.0',
          'id': {r'$capture': 'write1'},
          'method': 'fs/write_text_file',
          'params': {
            'sessionId': r'${sessionId}',
            'path': r'${cwd}/README.md',
            'content': '# bar\n',
          },
        },
      },
      {
        'dir': 'c2a',
        'frame': {'jsonrpc': '2.0', 'id': r'${write1}', 'result': null},
      },
      promptFrames[2],
    ];

    await runAgentFixture(
      fixture(
        frames,
        after: {
          'files': {'README.md': '# bar\n'},
        },
      ),
      (transport, setup) async => _StubAgent(
        transport,
        chunks: const [],
        write: ('${setup.cwd}/README.md', '# bar\n'),
      ),
    );

    expect(
      () => runAgentFixture(
        fixture(
          frames,
          after: {
            'files': {'README.md': '# baz\n'},
          },
        ),
        (transport, setup) async => _StubAgent(
          transport,
          chunks: const [],
          write: ('${setup.cwd}/README.md', '# bar\n'),
        ),
      ),
      throwsA(isA<AgentFixtureFailure>()),
    );
  });
}

/// Заглушка агента: handshake, один ход с [chunks] и ответом `end_turn`.
final class _StubAgent implements AgentUnderTest {
  _StubAgent(
    this.transport, {
    required this.chunks,
    this.extraUpdate = false,
    this.extraRead = false,
    this.verifyError,
    this.write,
  }) {
    _subscription = transport.inbound.listen(_onMessage);
    unawaited(transport.start());
  }

  final AcpTransport transport;
  final List<String> chunks;
  final bool extraUpdate;
  final bool extraRead;
  final Object? verifyError;
  final (String, String)? write;
  late final StreamSubscription<JsonRpcMessage> _subscription;
  var stopped = false;
  JsonRpcId? _promptId;

  Future<void> _onMessage(JsonRpcMessage message) async {
    switch (message) {
      case JsonRpcRequest(method: 'initialize', :final id):
        await _send(
          JsonRpcMessage.response(
            id: id,
            result: {
              'protocolVersion': 1,
              'agentCapabilities': <String, Object?>{},
            },
          ),
        );
      case JsonRpcRequest(method: 'session/new', :final id):
        await _send(
          JsonRpcMessage.response(
            id: id,
            result: {'sessionId': 'stub-session'},
          ),
        );
      case JsonRpcRequest(method: 'session/prompt', :final id):
        _promptId = id;
        for (final chunk in chunks) {
          await _send(
            _update({
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': chunk},
            }),
          );
        }
        if (write case (final path, final content)) {
          await _send(
            JsonRpcMessage.request(
              id: const JsonRpcId.string('fs-1'),
              method: 'fs/write_text_file',
              params: {
                'sessionId': 'stub-session',
                'path': path,
                'content': content,
              },
            ),
          );
          return;
        }
        await _finish();
      case JsonRpcResponse():
        await _finish();
      default:
        break;
    }
  }

  Future<void> _finish() async {
    await _send(
      JsonRpcMessage.response(
        id: _promptId!,
        result: {'stopReason': 'end_turn'},
      ),
    );
    if (extraUpdate) {
      await _send(
        _update({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'late'},
        }),
      );
    }
    if (extraRead) {
      await _send(
        JsonRpcMessage.request(
          id: const JsonRpcId.string('fs-9'),
          method: 'fs/read_text_file',
          params: {'sessionId': 'stub-session', 'path': '/etc/hosts'},
        ),
      );
    }
  }

  JsonRpcMessage _update(Map<String, Object?> update) =>
      JsonRpcMessage.notification(
        method: 'session/update',
        params: {'sessionId': 'stub-session', 'update': update},
      );

  Future<void> _send(JsonRpcMessage message) => transport.send(message);

  @override
  void verify() {
    if (verifyError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> stop() async {
    stopped = true;
    await _subscription.cancel();
  }
}
