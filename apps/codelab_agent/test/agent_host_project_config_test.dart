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

  // change `defer-restart-keys-in-folder-sessions`, задача 3.1: правка
  // глобального файла после старта, которую перезагрузка откладывает до
  // перезапуска (R0-4), не действует и в сессиях других папок. Настоящий
  // `FileConfigSource`, временные `CODELAB_HOME` и папки, HTTP — `MockClient`.
  group('a deferred global edit after the start (R0-4)', () {
    const oldKey = 'sk-test-leak-0123456789';
    const newKey = 'sk-test-other-9876543210';

    late String plain;
    late String withProvider;

    setUp(() {
      final parent = temp.resolveSymbolicLinksSync();
      plain = '$parent/c';
      withProvider = '$parent/d';
      Directory(plain).createSync(recursive: true);
      File('$withProvider/.codelab/config.local.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
providers:
  local:
    kind: openai-compatible
    base_url: https://local.test/v1
    models:
      m: {}
agent:
  default_model: local/m
''');
      final file = File('${temp.path}/home/config.yaml');
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst(
          'trusted_projects:\n',
          'trusted_projects:\n  - $plain\n  - $withProvider\n',
        ),
      );
    });

    /// Запускает хост и после старта переписывает глобальный файл: ключ
    /// провайдера берётся из `OPENAI_KEY2` вместо `OPENAI_KEY`.
    Future<(AcpPeer, List<http.BaseRequest>, RecordingLogger)> run() async {
      final requests = <http.BaseRequest>[];
      final logger = RecordingLogger();
      final parsed = parseServeArgs(
        ['serve', '--stdio'],
        environment: {
          'CODELAB_HOME': '${temp.path}/home',
          'OPENAI_KEY': oldKey,
          'OPENAI_KEY2': newKey,
          'ANTHROPIC_KEY': 'sk-anthropic-test',
          'CODELAB_SECRET_CODELAB_K': oldKey,
        },
      );
      final host = await buildHost(
        parsed,
        cwd: root,
        logger: logger,
        httpClient: MockClient.streaming((request, body) async {
          requests.add(request);
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"denied"}}')),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final link = InProcessAcpLink();
      unawaited(host.createServer().serve(link.agent));
      await link.client.start();
      addTearDown(() => host.shutdown(grace: Duration.zero));
      final peer = AcpPeer(link.client);
      await peer.call('initialize', {'protocolVersion': 1});
      final file = File('${temp.path}/home/config.yaml');
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst(
          'api_key_env: OPENAI_KEY\n',
          'api_key_env: OPENAI_KEY2\n',
        ),
      );
      return (peer, requests, logger);
    }

    Future<void> turn(AcpPeer peer, String cwd) async {
      final id = await peer.newSession(cwd);
      await peer.send('session/prompt', {
        'sessionId': id,
        'prompt': [
          {'type': 'text', 'text': 'hi'},
        ],
      });
    }

    test('a folder without .codelab/ keeps the key of the applied snapshot; '
        'the trusted folder with its own provider works at once (scenarios '
        '"Глобальная смена api_key_env ждёт перезапуска и в другой папке", '
        '"Проектный провайдер доверенной папки работает сразу")', () async {
      final (peer, requests, logger) = await run();

      await turn(peer, plain);

      final toOpenai = requests.where((r) => r.url.host == 'openai.test');
      expect(toOpenai, hasLength(1));
      expect(
        toOpenai.single.headers['Authorization'],
        'Bearer $oldKey',
        reason: 'R0-4: the new variable waits for the restart',
      );
      final pending = logger.eventsOf('config.session.restart_pending');
      expect(pending, hasLength(1));
      expect(pending.single.fields['cwd'], plain);
      expect(pending.single.fields['keys'], ['providers.openai']);

      await turn(peer, withProvider);

      expect(
        requests.where((r) => r.url.host == 'local.test'),
        hasLength(1),
        reason: 'the provider of the trusted folder needs no restart',
      );
      expect(
        logger
            .eventsOf('config.session.restart_pending')
            .map((e) => e.fields['keys']),
        everyElement(['providers.openai']),
      );
      expect(logger.records.join('\n'), isNot(contains(oldKey)));
      expect(logger.records.join('\n'), isNot(contains(newKey)));
    });

    test('a key supplied by the project layer does not follow a global '
        'address that changed after the start (R0-4, D3; the marker is the '
        'secret value)', () async {
      final parent = temp.resolveSymbolicLinksSync();
      final keyed = '$parent/e';
      File('$keyed/.codelab/config.local.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
providers:
  keyless:
    api_key_secret: codelab/k
agent:
  default_model: keyless/m
''');
      final home = File('${temp.path}/home/config.yaml');
      home.writeAsStringSync(
        home
            .readAsStringSync()
            .replaceFirst(
              'trusted_projects:\n',
              'trusted_projects:\n  - $keyed\n',
            )
            .replaceFirst(
              'providers:\n',
              'providers:\n  keyless:\n    kind: openai-compatible\n'
                  '    base_url: https://k.test/v1\n    models:\n      m: {}\n',
            ),
      );
      final (peer, requests, logger) = await run();
      home.writeAsStringSync(
        home.readAsStringSync().replaceFirst(
          'https://k.test/v1',
          'https://evil.test/v1',
        ),
      );

      await turn(peer, keyed);

      expect(requests.where((r) => r.url.host == 'evil.test'), isEmpty);
      for (final request in requests) {
        expect(request.headers.values.join(), isNot(contains(oldKey)));
      }
      expect(
        logger
            .eventsOf('config.session.restart_pending')
            .map((e) => e.fields['keys'])
            .single,
        contains('providers.keyless'),
      );
      expect(logger.records.join('\n'), isNot(contains(oldKey)));
    });
  });
}

/// Клиент и записанные `CoreConfig` (шов `modelsFor`).
final class AgentPeerSetup {
  AgentPeerSetup(this.peer, this.built);

  final AcpPeer peer;
  final List<CoreConfig> built;
}
