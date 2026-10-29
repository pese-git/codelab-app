import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'support/acp_peer.dart';

/// Сборка ядра бинаря (задача 4.6; agent-binary «Сценарий --llm-script»,
/// «Минимальный конфиг из флагов», «Команда serve»; design.md change
/// `add-codelab-agent-binary`, D3): хост поднимается в процессе теста, а
/// клиент говорит с ним через `InProcessAcpLink`. Журнал сценария на диске —
/// D1, D2 change `add-llm-script-session-store`.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_host_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  String writeScript(Map<String, Object?> llm) {
    final file = File('${temp.path}/script.json')
      ..writeAsStringSync(jsonEncode({'llm': llm}));
    return file.path;
  }

  String sessionsDir() => '${temp.path}/agent-sessions';

  ServeOptions scriptedOptions(
    String script, {
    List<String> extra = const [],
    String transport = '--stdio',
  }) => parseServeArgs(
    ['serve', transport, '--llm-script', script, ...extra],
    environment: {'CODELAB_HOME': '${temp.path}/home'},
  );

  /// Хост, сервер и клиент на одной паре транспортов.
  Future<(AgentHost, AcpPeer)> start(ServeOptions options) async {
    final host = await AgentHost.build(options, logger: RecordingLogger());
    final link = InProcessAcpLink();
    unawaited(host.createServer().serve(link.agent));
    await link.client.start();
    addTearDown(() => host.shutdown(grace: Duration.zero));
    return (host, AcpPeer(link.client));
  }

  group('--llm-script', () {
    test('models: scripted/<id> for each --model', () async {
      final script = writeScript({'steps': <Object?>[]});
      final (host, _) = await start(
        scriptedOptions(
          script,
          extra: ['--model', 'gpt-5', '--model', 'gpt-4'],
        ),
      );
      expect(host.core.runtime.models.models.map((m) => m.id), [
        const ModelId('scripted/gpt-5'),
        const ModelId('scripted/gpt-4'),
      ]);
    });

    test('without --model: the model of llm.model', () async {
      final script = writeScript({
        'model': {
          'provider': 'scripted',
          'modelId': 'demo',
          'contextWindow': 8192,
        },
        'steps': <Object?>[],
      });
      final (host, _) = await start(scriptedOptions(script));
      final models = host.core.runtime.models.models;
      expect(models.single.id, const ModelId('scripted/demo'));
    });

    test(
      r'${cwd} and ${sessionId} follow the session of the request',
      () async {
        final script = writeScript({
          'steps': [
            for (var i = 0; i < 2; i++)
              {
                'reply': [
                  {'text': r'cwd was: ${cwd} in ${sessionId}'},
                ],
                'stopReason': 'stop',
              },
          ],
        });
        final (_, peer) = await start(scriptedOptions(script));
        final first = Directory('${temp.path}/a')..createSync();
        final second = Directory('${temp.path}/b')..createSync();
        final a = await peer.openSession(first.path);
        final b = await peer.newSession(second.path);

        expect(await peer.prompt(b, 'hi'), 'end_turn');
        expect(await peer.prompt(a, 'hi'), 'end_turn');

        expect(peer.agentText(a), 'cwd was: ${first.path} in $a');
        expect(peer.agentText(b), 'cwd was: ${second.path} in $b');
      },
    );

    test('an invalid script is a usage error with the field path', () async {
      final script = writeScript({'steps': 'not a list'});
      expect(
        () =>
            AgentHost.build(scriptedOptions(script), logger: RecordingLogger()),
        throwsA(
          isA<UsageError>().having(
            (e) => e.message,
            'message',
            contains('llm.steps'),
          ),
        ),
      );
    });

    test('a missing script file is a usage error', () async {
      expect(
        () => AgentHost.build(
          scriptedOptions('${temp.path}/missing.json'),
          logger: RecordingLogger(),
        ),
        throwsA(isA<UsageError>()),
      );
    });

    test('sessions stay in memory and CODELAB_HOME is not created', () async {
      final script = writeScript({
        'steps': [
          {
            'reply': [
              {'text': 'hello'},
            ],
            'stopReason': 'stop',
          },
        ],
      });
      final (host, peer) = await start(scriptedOptions(script));
      final init = await peer.call('initialize', {'protocolVersion': 1});
      final caps = init['agentCapabilities']! as Map<String, Object?>;
      expect(caps['loadSession'], isFalse);
      expect(
        host.core.plan.offReasons[HostCapability.sessionPersistence],
        contains('--llm-script'),
      );

      final session = await peer.newSession(temp.path);
      expect(await peer.prompt(session, 'hi'), 'end_turn');
      expect(Directory('${temp.path}/home').existsSync(), isFalse);
    });
  });

  group('--llm-script with --sessions-dir', () {
    String cwdScript() => writeScript({
      'steps': [
        for (var i = 0; i < 2; i++)
          {
            'reply': [
              {'text': r'cwd was: ${cwd}'},
            ],
            'stopReason': 'stop',
          },
      ],
    });

    ServeOptions persistentOptions(String script) =>
        scriptedOptions(script, extra: ['--sessions-dir', sessionsDir()]);

    test('declares loadSession and session/list; journals in the flag '
        'directory, not in CODELAB_HOME', () async {
      final (host, peer) = await start(persistentOptions(cwdScript()));
      final init = await peer.call('initialize', {'protocolVersion': 1});
      final caps = init['agentCapabilities']! as Map<String, Object?>;
      expect(caps['loadSession'], isTrue);
      expect(
        (caps['sessionCapabilities']! as Map<String, Object?>)['list'],
        isNotNull,
      );
      expect(
        host.core.plan.offReasons,
        isNot(contains(HostCapability.sessionPersistence)),
      );

      final session = await peer.newSession(temp.path);
      expect(await peer.prompt(session, 'hi'), 'end_turn');
      expect(Directory(sessionsDir()).existsSync(), isTrue);
      expect(Directory('${temp.path}/home').existsSync(), isFalse);
    });

    test('sessions survive a host restart: list, load replay and '
        r'${cwd} of the loaded session', () async {
      final script = cwdScript();
      final work = Directory('${temp.path}/work')..createSync();

      // Первый процесс: сессия с одним ходом, затем завершение.
      final first = await AgentHost.build(
        persistentOptions(script),
        logger: RecordingLogger(),
      );
      final firstLink = InProcessAcpLink();
      unawaited(first.createServer().serve(firstLink.agent));
      await firstLink.client.start();
      final firstPeer = AcpPeer(firstLink.client);
      final sessionId = await firstPeer.openSession(work.path);
      expect(await firstPeer.prompt(sessionId, 'first question'), 'end_turn');
      await first.shutdown(grace: Duration.zero);

      // Второй процесс над тем же каталогом журналов.
      final (_, peer) = await start(persistentOptions(script));
      await peer.call('initialize', {'protocolVersion': 1});
      final page = await peer.call('session/list', {'cwd': work.path});
      expect((page['sessions']! as List).map((s) => (s as Map)['sessionId']), [
        sessionId,
      ]);

      await peer.call('session/load', {
        'sessionId': sessionId,
        'cwd': work.path,
        'mcpServers': <Object?>[],
      });
      expect(peer.agentText(sessionId), 'cwd was: ${work.path}');

      // Шаги сценария нового процесса начинаются с первого (D3), а `${cwd}`
      // берётся из журнала загруженной сессии (D2).
      expect(await peer.prompt(sessionId, 'second question'), 'end_turn');
      expect(
        peer.agentText(sessionId),
        'cwd was: ${work.path}cwd was: ${work.path}',
      );
      expect(Directory('${temp.path}/home').existsSync(), isFalse);
    });
  });

  group('provider from flags', () {
    ServeOptions providerOptions({String transport = '--stdio'}) =>
        parseServeArgs(
          [
            'serve',
            transport,
            '--provider',
            'openai-compatible',
            '--base-url',
            'http://127.0.0.1:9/v1',
            '--model',
            'gpt-5',
            '--model',
            'gpt-4',
          ],
          environment: {
            'CODELAB_HOME': '${temp.path}/home',
            'CODELAB_API_KEY': 'sk-test-secret',
          },
        );

    test('journals under CODELAB_HOME/sessions and loadSession', () async {
      final (host, peer) = await start(providerOptions());
      final init = await peer.call('initialize', {'protocolVersion': 1});
      final caps = init['agentCapabilities']! as Map<String, Object?>;
      expect(caps['loadSession'], isTrue);
      expect(host.core.runtime.models.models.map((m) => m.id), [
        const ModelId('cli/gpt-5'),
        const ModelId('cli/gpt-4'),
      ]);

      await peer.newSession(temp.path);
      expect(Directory('${temp.path}/home/sessions').existsSync(), isTrue);
    });

    test('the model option lists cli models, cli/gpt-5 first', () async {
      final (_, peer) = await start(providerOptions());
      await peer.call('initialize', {'protocolVersion': 1});
      final result = await peer.call('session/new', {
        'cwd': temp.path,
        'mcpServers': <Object?>[],
      });
      final model = (result['configOptions']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((o) => o['id'] == 'model');
      expect(model['currentValue'], 'cli/gpt-5');
      expect((model['options']! as List).map((o) => (o as Map)['value']), [
        'cli/gpt-5',
        'cli/gpt-4',
      ]);
    });
  });

  group('transport wiring', () {
    test('stdio: ls and search are on', () async {
      final script = writeScript({'steps': <Object?>[]});
      final (host, _) = await start(scriptedOptions(script));
      expect(host.core.plan.toolNames, containsAll(['ls', 'search']));
      expect(host.serverConfig.localListing, isNotNull);
      expect(host.serverConfig.detachGrace, Duration.zero);
    });

    // Обрыв WebSocket отменяет ход, как у stdio: ход без клиента не может
    // ни читать, ни писать файлы (change `cancel-turn-on-ws-disconnect`, D1).
    test('ws: fileListing is off with a reason, no detach grace', () async {
      final script = writeScript({'steps': <Object?>[]});
      final (host, _) = await start(scriptedOptions(script, transport: '--ws'));
      expect(host.core.plan.toolNames, isNot(contains('ls')));
      expect(host.core.plan.offReasons[HostCapability.fileListing], isNotEmpty);
      expect(host.serverConfig.localListing, isNull);
      expect(host.serverConfig.detachGrace, Duration.zero);
    });

    // Клиент по WebSocket может быть на другой машине: процессы stdio-серверов
    // запускались бы на машине агента по описанию из сети (решение по ревью
    // PR #158; design.md change `add-agent-mcp-client`, D3).
    test(
      'ws: mcp is off with a reason; stdio keeps the stdio transport',
      () async {
        final script = writeScript({'steps': <Object?>[]});

        final (ws, _) = await start(scriptedOptions(script, transport: '--ws'));
        final (stdio, _) = await start(scriptedOptions(script));

        expect(
          ws.core.plan.offReasons[HostCapability.mcp],
          'stdio MCP servers are disabled over WebSocket',
        );
        expect(stdio.core.plan.offReasons, isNot(contains(HostCapability.mcp)));
        // С задачи 9.6 по stdio доступны и процессы, и streamable HTTP.
        expect(
          stdio.core.plan.profile.states[HostCapability.mcp],
          isA<CapabilityTransport>().having((c) => c.transports, 'transports', {
            'stdio',
            'http',
          }),
        );
      },
    );

    // agent-binary «Возможности MCP в initialize» (задача 9.6; design.md
    // change `add-agent-mcp-client`, D3): HTTP-транспорт на HTTP-клиенте
    // хоста, поэтому `initialize` обещает `http`; по WebSocket MCP выключен.
    test(
      'initialize: mcpCapabilities.http is true over stdio, false over ws',
      () async {
        final script = writeScript({'steps': <Object?>[]});

        for (final (transport, http) in [('--stdio', true), ('--ws', false)]) {
          final (_, peer) = await start(
            scriptedOptions(script, transport: transport),
          );
          final init = await peer.call('initialize', {'protocolVersion': 1});

          final caps = init['agentCapabilities']! as Map<String, Object?>;
          expect(caps['mcpCapabilities'], {'http': http, 'sse': false});
        }
      },
    );
  });
}
