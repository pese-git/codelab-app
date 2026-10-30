import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/acp_peer.dart';
import 'support/build_host.dart';

/// Хост ядра, собранный из `config.yaml` (agent-binary «Конфиг бинаря из
/// файлов, окружения и флагов», «Логи бинаря», «MCP-серверы в бинаре»;
/// agent-configuration «Наблюдаемость загрузки конфигурации»; задача 9.2,
/// design.md change `add-agent-configuration`, D4, D10, D11, D16). Хост
/// поднимается в процессе теста, HTTP — `MockClient`, реальной сети нет.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_config_');
  });

  tearDown(() => temp.delete(recursive: true));

  const providerEntries = '''
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
''';
  const agentSection = 'agent:\n  default_model: openai/gpt-5\n';
  const providers = providerEntries + agentSection;

  String writeConfig(String text) {
    final file = File('${temp.path}/c.yaml')..writeAsStringSync(text);
    return file.path;
  }

  ServeOptions options(
    List<String> args, {
    Map<String, String> environment = const {},
  }) => parseServeArgs(
    ['serve', '--stdio', ...args],
    environment: {
      'CODELAB_HOME': '${temp.path}/home',
      'OPENAI_KEY': 'sk-openai-test',
      'ANTHROPIC_KEY': 'sk-anthropic-test',
      ...environment,
    },
  );

  Future<(AgentHost, AcpPeer)> start(
    ServeOptions options, {
    http.Client? client,
    Logger? logger,
  }) async {
    final host = await buildHost(
      cwd: temp.path,
      options,
      logger: logger ?? RecordingLogger(),
      httpClient: client,
    );
    final link = InProcessAcpLink();
    unawaited(host.createServer().serve(link.agent));
    await link.client.start();
    addTearDown(() => host.shutdown(grace: Duration.zero));
    return (host, AcpPeer(link.client));
  }

  /// Клиент, который запоминает адреса запросов и отвечает 401: ход падает
  /// быстро и без повторов.
  (http.Client, List<Uri>) recordingClient() {
    final requests = <Uri>[];
    final client = MockClient.streaming((request, body) async {
      requests.add(request.url);
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":{"message":"denied"}}')),
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    return (client, requests);
  }

  group('providers from config.yaml', () {
    test('the model option lists both providers; the request goes to the '
        'base_url of the chosen one', () async {
      final path = writeConfig(providers);
      final (client, requests) = recordingClient();
      final (_, peer) = await start(
        options(['--config', path, '--model', 'anthropic/claude-sonnet-4']),
        client: client,
      );
      await peer.call('initialize', {'protocolVersion': 1});
      final created = await peer.call('session/new', {
        'cwd': temp.path,
        'mcpServers': <Object?>[],
      });

      final model = (created['configOptions']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((o) => o['id'] == 'model');
      expect(model['currentValue'], 'anthropic/claude-sonnet-4');
      expect((model['options']! as List).map((o) => (o as Map)['value']), [
        'openai/gpt-5',
        'anthropic/claude-sonnet-4',
      ]);

      await expectLater(
        peer.prompt(created['sessionId']! as String, 'hi'),
        throwsA(isA<AcpCallFailed>()),
      );
      expect(requests, isNotEmpty);
      expect(requests.map((u) => u.host).toSet(), {'anthropic.test'});
    });

    test('a model of the other provider is chosen by default_model', () async {
      final path = writeConfig(providers);
      final (client, requests) = recordingClient();
      final (_, peer) = await start(
        options(['--config', path]),
        client: client,
      );
      final session = await peer.openSession(temp.path);

      await expectLater(
        peer.prompt(session, 'hi'),
        throwsA(isA<AcpCallFailed>()),
      );
      expect(requests.map((u) => u.host).toSet(), {'openai.test'});
    });

    test('sessions.dir of the config is the journal root', () async {
      final path = writeConfig(
        '${providers}sessions:\n  dir: ${temp.path}/journals\n  fsync: never\n',
      );
      final (_, peer) = await start(options(['--config', path]));

      await peer.openSession(temp.path);

      expect(Directory('${temp.path}/journals').existsSync(), isTrue);
      expect(Directory('${temp.path}/home/sessions').existsSync(), isFalse);
    });

    test('a broken config makes build fail with the issues', () async {
      final path = writeConfig('${providers}budget:\n  max_stepz: 3\n');

      await expectLater(
        buildHost(
          cwd: temp.path,
          options(['--config', path]),
          logger: RecordingLogger(),
        ),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.single.key,
            'key',
            'budget.max_stepz',
          ),
        ),
      );
    });
  });

  group('profile', () {
    test('profile.agent-serve.mcp: [http] narrows the transports', () async {
      final path = writeConfig(
        '${providers}profile:\n  agent-serve:\n    mcp: [http]\n',
      );

      final (host, _) = await start(options(['--config', path]));

      expect(
        host.core.plan.profile.states[HostCapability.mcp],
        isA<CapabilityTransport>().having((c) => c.transports, 'transports', {
          'http',
        }),
      );
    });

    test('widening the profile is a config issue', () async {
      final path = writeConfig(
        '${providers}profile:\n  agent-serve:\n    mcp: [stdio, http, sse]\n',
      );

      await expectLater(
        buildHost(
          cwd: temp.path,
          options(['--config', path]),
          logger: RecordingLogger(),
        ),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.single.key,
            'key',
            'profile.agent-serve.mcp',
          ),
        ),
      );
    });
  });

  group('logging', () {
    test('logging.file of the config; a flag beats it', () async {
      final path = writeConfig(
        '${providers}logging:\n  file: ${temp.path}/a.log\n  level: debug\n',
      );
      final fromConfig = options(['--config', path]);
      final fromFlag = options([
        '--config',
        path,
        '--log-file',
        '${temp.path}/b.log',
      ]);

      final byConfig = logSettings(
        fromConfig,
        loadServeConfig(fromConfig, cwd: temp.path),
      );
      final byFlag = logSettings(
        fromFlag,
        loadServeConfig(fromFlag, cwd: temp.path),
      );

      expect(
        (byConfig.level, byConfig.file),
        (LogLevel.debug, '${temp.path}/a.log'),
      );
      expect(byFlag.file, '${temp.path}/b.log');
      expect(byFlag.level, LogLevel.debug);
    });

    test('without a file key no log file is created', () {
      final path = writeConfig(providers);
      final opts = options(['--config', path]);

      final settings = logSettings(opts, loadServeConfig(opts, cwd: temp.path));

      expect(settings.file, isNull);
      expect(settings.level, LogLevel.info);
    });

    test('a variable beats the config, a flag beats the variable', () {
      final path = writeConfig('${providers}logging:\n  level: debug\n');
      final byEnv = options(
        ['--config', path],
        environment: {'CODELAB_LOG_LEVEL': 'WARNING'},
      );
      final byFlag = options(
        ['--config', path, '--log-level', 'error'],
        environment: {'CODELAB_LOG_LEVEL': 'WARNING'},
      );

      expect(
        logSettings(byEnv, loadServeConfig(byEnv, cwd: temp.path)).level,
        LogLevel.warning,
      );
      expect(
        logSettings(byFlag, loadServeConfig(byFlag, cwd: temp.path)).level,
        LogLevel.error,
      );
    });

    test('host.config.loaded and warnings; no value reaches the log', () async {
      final path = writeConfig('''
$providerEntries  openai2:
    kind: openai-compatible
    base_url: https://openai2.test/v1
    headers:
      Authorization: "Bearer \${TOKEN}"
    models:
      m: {}
$agentSection
loop:
  misuse:
    warn_after: 3
''');
      final logger = RecordingLogger();

      await start(
        options(['--config', path], environment: {'TOKEN': 'tok-test-secret'}),
        logger: logger,
      );

      final loaded = logger.eventsOf('host.config.loaded').single;
      expect(loaded.level, LogLevel.info);
      expect(loaded.fields['sources'], contains(path));
      expect(loaded.fields['warnings'], 1);
      expect(loaded.fields, contains('project_root'));
      // Поля D16 — `key` и `source`; `message` — текст без значений.
      expect(
        logger.eventsOf('config.key.not_applied').single.fields,
        allOf(
          containsPair('key', 'loop.misuse.warn_after'),
          containsPair('source', path),
        ),
      );
      for (final record in logger.records) {
        expect(
          '${record.event} ${record.fields} ${record.error}',
          isNot(contains('tok-test-secret')),
        );
        expect(
          '${record.event} ${record.fields} ${record.error}',
          isNot(contains('sk-openai-test')),
        );
      }
    });

    test(
      'a provider without a key gives config.provider.key_missing',
      () async {
        final path = writeConfig(providers);
        final logger = RecordingLogger();

        await start(
          parseServeArgs(
            ['serve', '--stdio', '--config', path],
            environment: {'CODELAB_HOME': '${temp.path}/home'},
          ),
          logger: logger,
        );

        expect(
          logger
              .eventsOf('config.provider.key_missing')
              .map((r) => r.fields['provider']),
          containsAll(['openai', 'anthropic']),
        );
      },
    );
  });

  group('MCP servers of the config', () {
    // E-03, часть конфигурации: сервер `type: http` из `mcp.servers`,
    // HTTP-клиент хоста — `MockClient` над `FakeMcpServer`.
    test(
      'an HTTP server is available to the model from the first turn',
      () async {
        final fake = FakeMcpServer(
          tools: [
            FakeMcpTool(
              'echo',
              inputSchema: const {
                'type': 'object',
                'properties': {
                  'text': {'type': 'string'},
                },
                'required': ['text'],
              },
            ),
          ],
          responses: {'echo': FakeToolResponse.text('hi')},
        );
        final client = MockClient.streaming(
          (request, body) => fake.handleHttp(request, body),
        );
        final path = writeConfig('''
mcp:
  servers:
    - name: fake
      type: http
      url: https://fake.mcp.test/mcp
''');
        final (host, peer) = await start(
          options([
            '--llm-script',
            'test/llm_scripts/mcp_echo.json',
            '--config',
            path,
            '--permission-mode',
            'bypass',
          ]),
          client: client,
        );

        final session = await peer.openSession(temp.path);
        expect(await peer.prompt(session, 'Повтори hi'), 'end_turn');

        expect(fake.calls, hasLength(1));
        expect(jsonEncode(fake.calls.single), contains('hi'));
        expect(host.core.plan.offReasons, isNot(contains(HostCapability.mcp)));
        final updates = jsonEncode([
          for (final n in peer.notifications) n.params,
        ]);
        expect(updates, contains('mcp__fake__echo'));
        expect(updates, contains('completed'));
      },
    );
  });

  group('--provider flags over the config', () {
    ServeOptions provider(Map<String, String> environment) => parseServeArgs(
      [
        'serve',
        '--stdio',
        '--provider',
        'openai-compatible',
        '--base-url',
        'https://flag.test/v1',
        '--model',
        'm',
      ],
      environment: {'CODELAB_HOME': '${temp.path}/home', ...environment},
    );

    /// Заголовки первого запроса модели при ходе на [provider].
    Future<Map<String, String>> firstRequestHeaders(
      ServeOptions options,
    ) async {
      final headers = <String, String>{};
      final client = MockClient.streaming((request, body) async {
        headers.addAll(request.headers);
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"denied"}}')),
          401,
          headers: {'content-type': 'application/json'},
        );
      });
      final (_, peer) = await start(options, client: client);
      final session = await peer.openSession(temp.path);
      await expectLater(
        peer.prompt(session, 'hi'),
        throwsA(isA<AcpCallFailed>()),
      );
      return {for (final e in headers.entries) e.key.toLowerCase(): e.value};
    }

    test('without CODELAB_API_KEY the request leaves without Authorization, '
        'and headers of the global providers.cli do not leak', () async {
      Directory('${temp.path}/home').createSync();
      File('${temp.path}/home/config.yaml').writeAsStringSync('''
providers:
  cli:
    kind: openai-compatible
    base_url: https://global.test/v1
    api_key_env: GLOBAL_KEY
    headers:
      X-Org: org-secret
    models:
      other: {}
''');

      final headers = await firstRequestHeaders(
        provider({'GLOBAL_KEY': 'sk-global-secret'}),
      );

      expect(headers, isNot(contains('authorization')));
      expect(headers, isNot(contains('x-org')));
    });

    test('with CODELAB_API_KEY the key goes in Authorization', () async {
      final headers = await firstRequestHeaders(
        provider({'CODELAB_API_KEY': 'sk-flag-secret'}),
      );

      expect(headers['authorization'], 'Bearer sk-flag-secret');
    });
  });

  group('--llm-script with sessions keys of the config', () {
    test('sessions.dir and sessions.fsync are not applied and are logged '
        'with their source', () async {
      final path = writeConfig(
        'sessions:\n  dir: ${temp.path}/cfg-sessions\n  fsync: always\n',
      );
      final logger = RecordingLogger();

      await start(
        options([
          '--llm-script',
          'test/llm_scripts/hello.json',
          '--config',
          path,
        ]),
        logger: logger,
      );

      final logged = logger.eventsOf('config.key.not_applied');
      expect(
        [for (final r in logged) r.fields['key']],
        ['sessions.dir', 'sessions.fsync'],
      );
      expect({for (final r in logged) r.fields['source']}, {path});
      expect(Directory('${temp.path}/cfg-sessions').existsSync(), isFalse);
    });
  });

  group('invalid config', () {
    test('unknown CODELAB_* variables are logged as config.env.unknown', () {
      final path = writeConfig('${providers}budget:\n  max_stepz: 3\n');
      final opts = options(
        ['--config', path],
        environment: {'CODELAB_MODLE': 'x'},
      );
      final loaded = loadServeConfig(opts, cwd: temp.path);
      final logger = RecordingLogger();

      expect(loaded.config, isNull);
      logStartupWarnings(logger, opts, loaded);

      expect(
        logger.eventsOf('config.env.unknown').single.fields['message'],
        contains('CODELAB_MODLE'),
      );
    });
  });

  group('the log file of the config', () {
    /// Логгер так, как его собирает `runCodelabAgent`.
    HostLogger logger(ServeOptions opts) {
      final settings = logSettings(opts, loadServeConfig(opts, cwd: temp.path));
      return HostLogger(
        level: settings.level,
        sinks: [if (settings.file case final file?) FileLogSink.open(file)],
      );
    }

    test('debug goes to a.log with mode 0600', () async {
      final path = writeConfig(
        '${providers}logging:\n  file: ${temp.path}/a.log\n  level: debug\n',
      );

      final log = logger(options(['--config', path]));
      log.log(LogLevel.debug, 'test.debug');
      await log.close();

      final file = File('${temp.path}/a.log');
      expect(file.readAsStringSync(), contains('"event":"test.debug"'));
      expect(file.statSync().mode & 0x1ff, 384, reason: '0600');
    });

    test('--log-file b.log leaves a.log untouched', () async {
      final path = writeConfig(
        '${providers}logging:\n  file: ${temp.path}/a.log\n  level: debug\n',
      );

      final log = logger(
        options(['--config', path, '--log-file', '${temp.path}/b.log']),
      );
      log.log(LogLevel.debug, 'test.debug');
      await log.close();

      expect(File('${temp.path}/a.log').existsSync(), isFalse);
      expect(
        File('${temp.path}/b.log').readAsStringSync(),
        contains('test.debug'),
      );
    });
  });
}
