import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/io.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/acp_client.dart';

/// Память последней модели встроенного агента (agent-runtime «Последняя
/// выбранная модель»: настольный открыватель передаёт файловую реализацию
/// над своим `$CODELAB_HOME`, сценарный — нет; design.md change
/// `optional-default-model`, D8; задача 4.3). Всё во временном `CODELAB_HOME`,
/// сети нет — `MockClient`.
void main() {
  late Directory temp;
  late String home;
  late Directory project;
  late RecordingLogger logger;
  final opened = <EmbeddedAgent>[];
  final clients = <TestAcpClient>[];

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_last_model_');
    home = '${temp.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    project = Directory('${temp.path}/project')..createSync();
    logger = RecordingLogger();
  });

  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    for (final agent in opened) {
      await agent.dispose();
    }
    clients.clear();
    opened.clear();
    temp.deleteSync(recursive: true);
  });

  Future<(TestAcpClient, Map<String, Object?>)> connect(
    EmbeddedAgent agent,
  ) async {
    opened.add(agent);
    final client = TestAcpClient(agent.clientTransport);
    clients.add(client);
    await client.start();
    await client.initialize();
    final created = await client.call('session/new', {
      'cwd': project.path,
      'mcpServers': <Object?>[],
    });
    return (client, created);
  }

  Object? currentModel(Map<String, Object?> result) =>
      (result['configOptions']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((o) => o['id'] == 'model')['currentValue'];

  File stateFile() => File('$home/state/last-model.json');

  group('localEmbeddedAgentOpener', () {
    void writeConfig() => File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    models:
      m: {}
      m2: {}
''');

    EmbeddedAgentOpener opener() => localEmbeddedAgentOpener(
      environment: {'CODELAB_HOME': home},
      logger: logger,
      httpClient: MockClient(
        (_) async => throw StateError('the test has no network'),
      ),
    );

    test('a model chosen in one agent is the model of the next one: the file '
        'memory sits over CODELAB_HOME', () async {
      writeConfig();
      final first = await opener()(
        cwd: project.path,
        hostProfile: 'embedded-cli',
      );
      final (client, created) = await connect(first);
      expect(currentModel(created), 'p/m');
      // Автоматический выбор файл состояния не создаёт.
      expect(stateFile().existsSync(), isFalse);

      await client.call('session/set_config_option', {
        'sessionId': created['sessionId'],
        'configId': 'model',
        'value': 'p/m2',
      });

      expect(jsonDecode(stateFile().readAsStringSync()), {
        'v': 1,
        'model': 'p/m2',
      });
      final second = await opener()(
        cwd: project.path,
        hostProfile: 'embedded-cli',
      );
      final (_, createdAgain) = await connect(second);
      expect(currentModel(createdAgain), 'p/m2');
    });

    test(
      'an explicit agent.default_model wins over the remembered model',
      () async {
        File('$home/config.yaml').writeAsStringSync(
          'providers:\n  p:\n    kind: openai-compatible\n'
          '    base_url: https://p.test/v1\n    models:\n      m: {}\n'
          '      m2: {}\nagent:\n  default_model: p/m\n',
        );
        Directory('$home/state').createSync();
        stateFile().writeAsStringSync('{"v": 1, "model": "p/m2"}');

        final agent = await opener()(
          cwd: project.path,
          hostProfile: 'embedded-cli',
        );
        final (_, created) = await connect(agent);

        expect(currentModel(created), 'p/m');
      },
    );
  });

  group('scriptedEmbeddedAgentOpener', () {
    test('has no memory: state/ is not created after a model change, a new '
        'agent starts on the first model of the catalog', () async {
      EmbeddedAgentOpener opener() => scriptedEmbeddedAgentOpener(
        llm: {'steps': <Object?>[]},
        codelabHome: home,
        logger: logger,
        models: const ['scripted/a', 'scripted/b'],
      );
      final first = await opener()(
        cwd: project.path,
        hostProfile: 'embedded-cli',
      );
      final (client, created) = await connect(first);

      await client.call('session/set_config_option', {
        'sessionId': created['sessionId'],
        'configId': 'model',
        'value': 'scripted/b',
      });

      expect(Directory('$home/state').existsSync(), isFalse);
      expect(Directory(home).listSync(), isEmpty);
      final second = await opener()(
        cwd: project.path,
        hostProfile: 'embedded-cli',
      );
      final (_, createdAgain) = await connect(second);
      expect(currentModel(createdAgain), 'scripted/a');
    });
  });
}
