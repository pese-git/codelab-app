import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_testing/acp_testing.dart';
import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'support/acp_peer.dart';

/// Сборка ядра бинаря (задача 4.6; agent-binary «Сценарий --llm-script»,
/// «Минимальный конфиг из флагов», «Команда serve»; design.md change
/// `add-codelab-agent-binary`, D3): хост поднимается в процессе теста, а
/// клиент говорит с ним через `InProcessAcpLink`.
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

    test('ws: fileListing is off with a reason', () async {
      final script = writeScript({'steps': <Object?>[]});
      final (host, _) = await start(scriptedOptions(script, transport: '--ws'));
      expect(host.core.plan.toolNames, isNot(contains('ls')));
      expect(host.core.plan.offReasons[HostCapability.fileListing], isNotEmpty);
      expect(host.serverConfig.localListing, isNull);
      expect(host.serverConfig.detachGrace, const Duration(seconds: 30));
    });
  });
}
