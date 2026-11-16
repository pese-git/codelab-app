import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
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

  // design.md change `add-agent-mcp-client`, D15: драйвер только загружает
  // `setup.mcp` и `after.mcpCalls` и отдаёт их фабрике агента.
  test('setup.mcp and after.mcpCalls reach the agent factory', () async {
    late AgentFixtureSetup seen;

    await runAgentFixture(
      fixture(
        promptFrames,
        setup: const {
          'cwd': '/work/demo',
          'mcp': {
            'fake': {
              'tools': [
                {
                  'name': 'echo',
                  'inputSchema': {'type': 'object'},
                },
              ],
            },
          },
        },
        after: const {
          'mcpCalls': {'fake': <Object?>[]},
        },
      ),
      (transport, setup) async {
        seen = setup;
        return _StubAgent(transport, chunks: ['Hello ', 'there']);
      },
    );

    expect(seen.mcp['fake']!.era, FixtureMcpEra.modern);
    expect(seen.mcp['fake']!.tools.single['name'], 'echo');
    expect(seen.after!.mcpCalls['fake'], isEmpty);
  });

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

  // Кадр `optional` + `repeat`: ноль или больше подряд идущих совпадений,
  // затем следующий обязательный кадр (строки прогресса субагента).
  for (final count in [0, 3]) {
    test('an optional repeated frame absorbs $count matching frames', () async {
      final progress = {
        'dir': 'a2c',
        'optional': true,
        'repeat': '+',
        'frame': {
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {
            'sessionId': r'${sessionId}',
            'update': {
              'sessionUpdate': 'agent_thought_chunk',
              'content': {
                'type': 'text',
                'text': {r'$any': true},
              },
            },
          },
        },
      };
      final frames = [promptFrames.first, progress, ...promptFrames.skip(1)];
      final result = await runAgentFixture(
        fixture(frames),
        (transport, setup) async =>
            _StubAgent(transport, chunks: ['Hello ', 'there'], thoughts: count),
      );
      expect(result.skipped, isFalse);
    });
  }

  // Регрессия нестабильности CI: необязательный кадр — «следующий фактический
  // кадр» (§14.4), а не «кадр в окне тишины». Строки прогресса субагента
  // троттлятся по реальным часам, а запись журнала на медленном диске
  // задерживает название сессии, поэтому пауза перед необязательным кадром
  // может превысить `quietPeriod`; такой кадр не должен доставаться
  // следующему обязательному кадру.
  group('a late optional frame', () {
    Map<String, Object?> thought({bool repeat = false}) => {
      'dir': 'a2c',
      'optional': true,
      if (repeat) 'repeat': '+',
      'frame': {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': r'${sessionId}',
          'update': {
            'sessionUpdate': 'agent_thought_chunk',
            'content': {
              'type': 'text',
              'text': {r'$any': true},
            },
          },
        },
      },
    };

    for (final repeat in [false, true]) {
      test('is absorbed after a pause longer than the quiet period '
          '(repeat: $repeat)', () async {
        final frames = [
          promptFrames.first,
          thought(repeat: repeat),
          ...promptFrames.skip(1),
        ];
        final result = await runAgentFixture(
          fixture(frames),
          (transport, setup) async => _StubAgent(
            transport,
            chunks: ['Hello ', 'there'],
            thoughts: repeat ? 3 : 1,
            pause: const Duration(milliseconds: 150),
          ),
          quietPeriod: const Duration(milliseconds: 30),
        );
        expect(result.skipped, isFalse);
      });
    }

    test('before a required repeated frame keeps its \$text check', () async {
      final frames = [
        promptFrames.first,
        thought(repeat: true),
        ...promptFrames.skip(1),
      ];
      expect(
        () => runAgentFixture(
          fixture(frames),
          (transport, setup) async => _StubAgent(
            transport,
            chunks: ['Hello ', 'world'],
            thoughts: 2,
            pause: const Duration(milliseconds: 150),
          ),
          quietPeriod: const Duration(milliseconds: 30),
        ),
        throwsA(
          isA<AgentFixtureFailure>().having(
            (f) => f.message,
            'message',
            contains('repeated frames differ'),
          ),
        ),
      );
    });

    test('a non-repeated optional frame absorbs at most one frame', () async {
      final frames = [promptFrames.first, thought(), ...promptFrames.skip(1)];
      expect(
        () => runAgentFixture(
          fixture(frames),
          (transport, setup) async => _StubAgent(
            transport,
            chunks: ['Hello ', 'there'],
            thoughts: 2,
            pause: const Duration(milliseconds: 150),
          ),
          quietPeriod: const Duration(milliseconds: 30),
        ),
        throwsA(
          isA<AgentFixtureFailure>().having(
            (f) => f.message,
            'message',
            contains('a2c frame differs'),
          ),
        ),
      );
    });
  });

  // Граница по содержимому не ослабляет сверку: открытый шаблон
  // закрывается обязательным кадром и после него ничего не поглощает.
  group('an open frame does not hide a violation', () {
    final title = {
      'dir': 'a2c',
      'optional': true,
      'frame': {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': r'${sessionId}',
          'update': {
            'sessionUpdate': 'session_info_update',
            'title': {r'$any': true},
          },
        },
      },
    };

    test('a title after the prompt response fails the run (ACP-3)', () async {
      final frames = [...promptFrames.take(2), title, promptFrames.last];
      await expectLater(
        runAgentFixture(
          fixture(frames),
          (transport, setup) async =>
              _StubAgent(transport, chunks: ['Hello there'], lateTitle: true),
        ),
        throwsA(
          isA<AgentFixtureFailure>().having(
            (f) => f.toString(),
            'toString',
            allOf(contains('unexpected frames'), contains('session_info')),
          ),
        ),
      );
    });

    test('an open frame at the end does not absorb an fs request', () async {
      final frames = [...promptFrames, title];
      await expectLater(
        runAgentFixture(
          fixture(frames),
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
  });

  // Срок ожидания обязательного кадра — один на всё ожидание: бесконечный
  // поток поглощаемых кадров (heartbeat зависшего субагента) не держит
  // прогон вечно. До исправления тест висел до таймаута самого теста.
  test('absorbed frames do not extend the frame timeout', () async {
    final progress = {
      'dir': 'a2c',
      'optional': true,
      'repeat': '+',
      'frame': {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': r'${sessionId}',
          'update': {
            'sessionUpdate': 'agent_thought_chunk',
            'content': {
              'type': 'text',
              'text': {r'$any': true},
            },
          },
        },
      },
    };
    await expectLater(
      runAgentFixture(
        fixture([promptFrames.first, progress, ...promptFrames.skip(1)]),
        (transport, setup) async => _StubAgent(
          transport,
          chunks: ['Hello there'],
          thoughts: 1 << 20,
          pause: const Duration(milliseconds: 20),
        ),
        frameTimeout: const Duration(milliseconds: 300),
        quietPeriod: const Duration(milliseconds: 30),
      ),
      throwsA(
        isA<AgentFixtureFailure>().having(
          (f) => f.message,
          'message',
          allOf(contains('timed out'), contains('absorbed')),
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 10)));

  // Окно перед `c2a` ограничено сроком: агент, который стримит без пауз до
  // `session/cancel`, не держит прогон вечно. Заглушка отмену не понимает,
  // поэтому прогон падает по таймауту ответа — но падает, а не висит.
  test('a stream without pauses does not block a c2a frame', () async {
    final progress = {
      'dir': 'a2c',
      'optional': true,
      'repeat': '+',
      'frame': {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': r'${sessionId}',
          'update': {
            'sessionUpdate': 'agent_thought_chunk',
            'content': {
              'type': 'text',
              'text': {r'$any': true},
            },
          },
        },
      },
    };
    final cancel = {
      'dir': 'c2a',
      'frame': {
        'jsonrpc': '2.0',
        'method': 'session/cancel',
        'params': {'sessionId': r'${sessionId}'},
      },
    };
    await expectLater(
      runAgentFixture(
        fixture([promptFrames.first, progress, cancel, promptFrames.last]),
        (transport, setup) async => _StubAgent(
          transport,
          chunks: ['Hello there'],
          thoughts: 1 << 20,
          pause: const Duration(milliseconds: 10),
        ),
        frameTimeout: const Duration(milliseconds: 300),
        quietPeriod: const Duration(milliseconds: 50),
      ),
      throwsA(
        isA<AgentFixtureFailure>().having(
          (f) => f.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 10)));

  // Хвост обязательного `repeat` тоже не ограничен окном тишины: чанк,
  // пришедший позже `quietPeriod`, — продолжение повтора, а не лишний кадр.
  test('a late tail of a required repeated frame joins its \$text', () async {
    final result = await runAgentFixture(
      fixture(promptFrames),
      (transport, setup) async => _StubAgent(
        transport,
        chunks: ['Hello ', 'there'],
        pause: const Duration(milliseconds: 150),
        pauseChunks: true,
      ),
      quietPeriod: const Duration(milliseconds: 30),
    );
    expect(result.skipped, isFalse);
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
    this.lateTitle = false,
    this.thoughts = 0,
    this.pause = Duration.zero,
    this.pauseChunks = false,
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

  /// Название сессии после ответа на `session/prompt` — нарушение ACP-3.
  final bool lateTitle;

  /// Сколько кадров `agent_thought_chunk` отправить до текста ответа.
  final int thoughts;

  /// Пауза перед каждым `agent_thought_chunk` (и перед каждым чанком
  /// ответа после первого при [pauseChunks]): так медленный CI задерживает
  /// кадры агента дольше окна тишины драйвера.
  final Duration pause;
  final bool pauseChunks;
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
        for (var i = 0; i < thoughts; i++) {
          await Future<void>.delayed(pause);
          // Бесконечный поток кадров обрывается вместе с прогоном.
          if (stopped) {
            return;
          }
          await _send(
            _update({
              'sessionUpdate': 'agent_thought_chunk',
              'content': {'type': 'text', 'text': 'thinking'},
            }),
          );
        }
        for (final (i, chunk) in chunks.indexed) {
          if (pauseChunks && i > 0) {
            await Future<void>.delayed(pause);
          }
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
    if (lateTitle) {
      await _send(
        _update({'sessionUpdate': 'session_info_update', 'title': 'Late'}),
      );
    }
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
