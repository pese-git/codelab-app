import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/acp_peer.dart';
import 'support/build_host.dart';

/// Проектный конфиг сессий в `serve` (agent-binary «Проектный конфиг сессий в
/// serve»; design.md change `require-project-folder`, D21, Q18): порт
/// `ProjectConfigLoader` есть только у `serve --stdio` без `--llm-script`.
///
/// Хост поднимается в процессе теста, HTTP — `MockClient`, функция модели
/// сессии папки подменена швом `modelsFor`, который запоминает `CoreConfig`,
/// построенные для каждой папки. Всё во временном каталоге.
void main() {
  late Directory temp;
  late String root;
  late String other;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_project_cfg_');
    final canonical = temp.resolveSymbolicLinksSync();
    root = '$canonical/a';
    other = '$canonical/b';
    Directory('$root/.codelab').createSync(recursive: true);
    Directory('$other/.codelab').createSync(recursive: true);
    // `trusted_projects` читается только из пользовательского конфига.
    Directory('${temp.path}/home').createSync();
    File('${temp.path}/home/config.yaml').writeAsStringSync('''
trusted_projects:
  - $root
  - $other
providers:
  openai:
    kind: openai-compatible
    base_url: https://openai.test/v1
    api_key_env: OPENAI_KEY
    models:
      gpt-5: {}
  anthropic:
    kind: anthropic
    base_url: https://anthropic.test
    api_key_env: ANTHROPIC_KEY
    models:
      claude-sonnet-4: {}
agent:
  default_model: openai/gpt-5
''');
    // У корня свой проектный слой: без него снимка без проекта нет вовсе.
    File(
      '$root/.codelab/config.yaml',
    ).writeAsStringSync('budget:\n  max_steps: 9\n');
    File('$other/.codelab/config.local.yaml').writeAsStringSync('''
budget:
  max_steps: 3
''');
  });

  tearDown(() => temp.delete(recursive: true));

  ServeOptions options(List<String> args, {String transport = '--stdio'}) =>
      parseServeArgs(
        ['serve', transport, ...args],
        environment: {
          'CODELAB_HOME': '${temp.path}/home',
          'OPENAI_KEY': 'sk-openai-test',
          'ANTHROPIC_KEY': 'sk-anthropic-test',
        },
      );

  /// Хост и клиент; второй элемент — `CoreConfig`, по которым строились
  /// функции модели (первый — корень запуска).
  Future<(AgentPeerSetup, RecordingLogger)> start(ServeOptions options) async {
    final built = <CoreConfig>[];
    final logger = RecordingLogger();
    final host = await buildHost(
      options,
      cwd: root,
      logger: logger,
      httpClient: MockClient.streaming(
        (request, body) async => http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"denied"}}')),
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
      modelsFor: (config) {
        built.add(config);
        return (
          stream: (model, context, {cancel}) =>
              throw StateError('no model call in this test'),
          catalog: StaticModelCatalog(config.providers, logger: logger),
        );
      },
    );
    final link = InProcessAcpLink();
    unawaited(host.createServer().serve(link.agent));
    await link.client.start();
    addTearDown(() => host.shutdown(grace: Duration.zero));
    final peer = AcpPeer(link.client);
    await peer.call('initialize', {'protocolVersion': 1});
    return (AgentPeerSetup(peer, built), logger);
  }

  Future<Object?> newSession(AcpPeer peer, String cwd) async {
    try {
      return await peer.call('session/new', {
        'cwd': cwd,
        'mcpServers': <Object?>[],
      });
    } on AcpCallFailed catch (error) {
      return error;
    }
  }

  test('serve --stdio: the session of a trusted folder gets the config of '
      'that folder; --model and --provider flags are in its layers', () async {
    final (setup, logger) = await start(
      options(['--model', 'anthropic/claude-sonnet-4']),
    );

    final created = await newSession(setup.peer, other);

    expect(created, isA<Map<String, Object?>>());
    final forFolder = setup.built.where((c) => c.projectRoot == other);
    expect(forFolder, hasLength(1), reason: 'built from the folder config');
    expect(forFolder.single.budget.maxSteps, 3);
    expect(
      forFolder.single.defaultModel.id,
      'claude-sonnet-4',
      reason: 'the flag layer is above the project layers',
    );
    final log = logger.eventsOf('config.session.project').single;
    expect(log.fields['cwd'], other);
    expect(log.fields['trusted'], isTrue);
    expect(logger.eventsOf('config.session.outside_root'), isEmpty);
  });

  test(
    'serve --stdio: a session in the launch root builds no extra config',
    () async {
      final (setup, logger) = await start(options(const []));

      await newSession(setup.peer, root);

      expect(setup.built.where((c) => c.projectRoot == other), isEmpty);
      expect(logger.eventsOf('config.session.project'), isEmpty);
    },
  );

  test('serve --ws: no port, the session of another folder gets '
      'withoutProject (Q18)', () async {
    final (setup, logger) = await start(options(const [], transport: '--ws'));

    final created = await newSession(setup.peer, other);

    expect(created, isA<Map<String, Object?>>());
    expect(
      setup.built.where((c) => c.projectRoot == other),
      isEmpty,
      reason: 'no folder config is built over WebSocket',
    );
    expect(logger.eventsOf('config.session.project'), isEmpty);
    final outside = logger.eventsOf('config.session.outside_root').single;
    expect(outside.fields['cwd'], other);
  });

  test('--llm-script: no port', () async {
    final script = File('${temp.path}/script.json')
      ..writeAsStringSync(
        jsonEncode({
          'llm': {'steps': <Object?>[]},
        }),
      );
    final logger = RecordingLogger();
    final scripted = parseServeArgs(
      ['serve', '--stdio', '--llm-script', script.path],
      environment: {'CODELAB_HOME': '${temp.path}/home'},
    );
    final host = await buildHost(scripted, cwd: root, logger: logger);
    final link = InProcessAcpLink();
    unawaited(host.createServer().serve(link.agent));
    await link.client.start();
    addTearDown(() => host.shutdown(grace: Duration.zero));
    final peer = AcpPeer(link.client);
    await peer.call('initialize', {'protocolVersion': 1});

    final created = await newSession(peer, other);

    expect(created, isA<Map<String, Object?>>());
    expect(logger.eventsOf('config.session.project'), isEmpty);
  });
}

/// Клиент и записанные `CoreConfig` (шов `modelsFor`).
final class AgentPeerSetup {
  AgentPeerSetup(this.peer, this.built);

  final AcpPeer peer;
  final List<CoreConfig> built;
}
