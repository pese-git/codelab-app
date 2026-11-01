import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcMessageWire;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/io.dart';
import 'package:http/http.dart' as web;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/acp_client.dart';

/// Настольный открыватель встроенного агента (embedded-agent «Конфигурация и
/// секреты встроенного агента», сценарии «Ключ провайдера из secrets.yaml»,
/// «Невалидный конфиг», «Нет конфигурации», «Нет ключа провайдера»;
/// design.md change `add-embedded-agent-mode`, D5).
///
/// Всё во временном каталоге: `CODELAB_HOME` и окружение открывателя задаёт
/// тест, настоящие `~/.codelab` и переменные процесса не читаются. Сети нет —
/// `MockClient`; процессов, кроме `exec` сценария, нет.
void main() {
  const value = 'sk-test-0123456789abcdef';

  late Directory temp;
  late String home;
  late Directory project;
  late RecordingLogger logger;
  EmbeddedAgent? agent;
  TestAcpClient? client;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_local_opener_');
    home = '${temp.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    project = Directory('${temp.path}/project')..createSync();
    logger = RecordingLogger();
  });

  tearDown(() async {
    await client?.close();
    await agent?.dispose();
    agent = client = null;
    temp.deleteSync(recursive: true);
  });

  String providers({String secrets = ''}) =>
      '''
$secrets
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    api_key_secret: codelab/p
    models:
      m: {}
agent:
  default_model: p/m
''';

  void writeHome(String yaml) =>
      File('$home/config.yaml').writeAsStringSync(yaml);

  void writeSecret() {
    final file = File('$home/secrets.yaml')
      ..writeAsStringSync('"codelab/p": "$value"\n');
    Process.runSync('/bin/chmod', ['600', file.path]);
  }

  /// Ответ 401 завершает ход быстро и без повторов; заголовок запоминается.
  (web.Client, List<String?>) denyingClient() {
    final authorizations = <String?>[];
    final mock = MockClient.streaming((request, body) async {
      authorizations.add(request.headers['authorization']);
      return web.StreamedResponse(
        Stream.value(utf8.encode('{"error":{"message":"denied"}}')),
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    return (mock, authorizations);
  }

  /// Успешный потоковый ответ провайдера: один текстовый чанк и конец хода.
  web.Client answeringClient(String text) =>
      MockClient.streaming((request, body) async {
        String chunk(Map<String, Object?> delta, String? finish) =>
            'data: ${jsonEncode({
              'id': 'c',
              'object': 'chat.completion.chunk',
              'created': 1,
              'model': 'm',
              'choices': [
                {'index': 0, 'delta': delta, 'finish_reason': finish},
              ],
            })}\n\n';
        final sse = [
          chunk({'role': 'assistant', 'content': text}, null),
          chunk({}, 'stop'),
          'data: [DONE]\n\n',
        ].join();
        return web.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

  EmbeddedAgentOpener opener({
    Map<String, String> environment = const {},
    web.Client? http,
  }) => localEmbeddedAgentOpener(
    environment: {'CODELAB_HOME': home, ...environment},
    logger: logger,
    httpClient: http,
  );

  Future<String> connect(
    EmbeddedAgent opened, {
    List<Map<String, Object?>> mcpServers = const [],
  }) async {
    agent = opened;
    client = TestAcpClient(opened.clientTransport);
    await client!.start();
    await client!.initialize();
    final created = await client!.call('session/new', {
      'cwd': project.path,
      'mcpServers': mcpServers,
    });
    return created['sessionId']! as String;
  }

  /// Итог `session/prompt`: `stopReason` или текст ошибки запроса.
  Future<String> promptOutcome(String sessionId) async {
    try {
      return await client!.prompt(sessionId, 'hi');
    } on StateError catch (error) {
      return '$error';
    }
  }

  String frames() =>
      [for (final m in client!.received) jsonEncode(m.toJson())].join('\n');

  group('provider key', () {
    test('comes from secrets.yaml with secrets.backend: file; the value is '
        'neither logged nor sent to the client', () async {
      writeHome(providers(secrets: 'secrets:\n  backend: file\n'));
      writeSecret();
      final (mock, authorizations) = denyingClient();

      final session = await connect(
        await opener(http: mock)(
          cwd: project.path,
          hostProfile: 'embedded-cli',
        ),
      );
      await promptOutcome(session);

      expect(authorizations, ['Bearer $value']);
      expect(
        logger.eventsOf('secrets.backend.selected').single.fields['backend'],
        'file',
      );
      expect(logger.records.join('\n'), isNot(contains(value)));
      expect(frames(), isNot(contains(value)));
    });

    test('comes from CODELAB_SECRET_* with the default backend', () async {
      writeHome(providers());
      final (mock, authorizations) = denyingClient();

      final session = await connect(
        await opener(
          environment: {'CODELAB_SECRET_CODELAB_P': value},
          http: mock,
        )(cwd: project.path, hostProfile: 'embedded-app-desktop'),
      );
      await promptOutcome(session);

      expect(authorizations, ['Bearer $value']);
      expect(logger.records.join('\n'), isNot(contains(value)));
    });

    test('is missing: the agent opens, the first turn fails naming the '
        'secret, no request leaves', () async {
      writeHome(providers());
      final (mock, authorizations) = denyingClient();

      final session = await connect(
        await opener(http: mock)(
          cwd: project.path,
          hostProfile: 'embedded-cli',
        ),
      );
      final outcome = await promptOutcome(session);

      expect(outcome, contains('codelab/p'));
      expect(outcome, isNot(equals('end_turn')));
      expect(authorizations, isEmpty);
    });
  });

  group('invalid configuration', () {
    test('a project config with budget.max_steps: 0 names the file and the '
        'key; no http client is created', () async {
      writeHome(providers());
      File('${project.path}/.codelab/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('budget:\n  max_steps: 0\n');
      var created = 0;

      final thrown = await web.runWithClient(
        () async {
          try {
            await opener()(cwd: project.path, hostProfile: 'embedded-cli');
          } on EmbeddedAgentConfigException catch (error) {
            return error;
          }
          return null;
        },
        () {
          created++;
          return MockClient((_) async => throw StateError('no network'));
        },
      );

      expect(thrown, isNotNull);
      expect(
        thrown!.message,
        matches(RegExp(r'\.codelab/config\.yaml:\d+:\d+: budget\.max_steps: ')),
      );
      expect(created, 0, reason: 'http.Client() must not be created');
    });

    test(
      'warnings of the load are logged before the exception is thrown',
      () async {
        writeHome(providers());
        File('${project.path}/.codelab/config.yaml')
          ..createSync(recursive: true)
          ..writeAsStringSync('budget:\n  max_steps: 0\n');

        final thrown = await opener(environment: {'CODELAB_TYPO_X': '1'})(
          cwd: project.path,
          hostProfile: 'embedded-cli',
        ).then<Object?>((_) => null, onError: (Object e) => e);

        expect(thrown, isA<EmbeddedAgentConfigException>());
        expect(
          logger.eventsOf('config.env.unknown').single.fields['name'],
          'CODELAB_TYPO_X',
        );
      },
    );

    test('an empty CODELAB_HOME: the loader problem and the hint as the last '
        'line', () async {
      final thrown = await opener()(
        cwd: project.path,
        hostProfile: 'embedded-cli',
      ).then<Object?>((_) => null, onError: (Object e) => e);

      expect(thrown, isA<EmbeddedAgentConfigException>());
      final error = thrown! as EmbeddedAgentConfigException;
      expect(error.issues, isNotEmpty);
      expect(
        error.message.split('\n').last,
        'Configure the embedded agent in $home/config.yaml; '
        'check it with: codelab config check',
      );
    });

    test(
      'an inline key in the config is a problem without the value',
      () async {
        writeHome(
          providers().replaceFirst(
            'api_key_secret: codelab/p',
            'api_key: sk-leak-0123456789',
          ),
        );

        final thrown = await opener()(
          cwd: project.path,
          hostProfile: 'embedded-cli',
        ).then<Object?>((_) => null, onError: (Object e) => e);

        expect(thrown, isA<EmbeddedAgentConfigException>());
        expect(
          (thrown! as EmbeddedAgentConfigException).message,
          isNot(contains('sk-leak')),
        );
      },
    );

    test('CODELAB_HOME with ~user and CODELAB_CONFIG with a foreign '
        'extension are config exceptions with the loader text', () async {
      final tilde =
          await localEmbeddedAgentOpener(
            environment: {'CODELAB_HOME': '~bob/x'},
            logger: logger,
          )(cwd: project.path, hostProfile: 'embedded-cli').then<Object?>(
            (_) => null,
            onError: (Object e) => e,
          );
      final toml = await opener(environment: {'CODELAB_CONFIG': 'x.toml'})(
        cwd: project.path,
        hostProfile: 'embedded-cli',
      ).then<Object?>((_) => null, onError: (Object e) => e);

      expect(
        tilde,
        isA<EmbeddedAgentConfigException>().having(
          (e) => e.message,
          'message',
          contains('CODELAB_HOME: ~user is not supported'),
        ),
      );
      expect(toml, isA<EmbeddedAgentConfigException>());
      // Источник берётся из исключения загрузчика, а не угадывается.
      expect(
        (tilde! as EmbeddedAgentConfigException).issues.single.source,
        'CODELAB_HOME',
      );
      expect(
        (toml! as EmbeddedAgentConfigException).issues.single.source,
        'CODELAB_CONFIG',
      );
    });
  });

  group('resources', () {
    test('a turn is journaled in \$CODELAB_HOME/sessions as JSONL', () async {
      writeHome(providers());
      final session = await connect(
        await opener(
          environment: {'CODELAB_SECRET_CODELAB_P': value},
          http: answeringClient('journal-marker'),
        )(cwd: project.path, hostProfile: 'embedded-cli'),
      );

      expect(await promptOutcome(session), 'end_turn');
      await agent!.dispose();

      final journals = [
        for (final entity in Directory(
          '$home/sessions',
        ).listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.jsonl')) entity,
      ];
      expect(journals, hasLength(1));
      expect(journals.single.readAsStringSync(), contains('journal-marker'));
    });

    test(
      'profile.embedded-cli.* narrows the embedded-cli profile only',
      () async {
        writeHome(
          '${providers()}profile:\n  embedded-cli:\n    shell_exec: "off"\n',
        );
        Future<Map<String, Object?>> planOf(String profile) async {
          logger = RecordingLogger();
          final opened = await opener(
            environment: {'CODELAB_SECRET_CODELAB_P': value},
            http: answeringClient('x'),
          )(cwd: project.path, hostProfile: profile);
          await opened.dispose();
          return logger.eventsOf('host.plan').single.fields;
        }

        final cli = await planOf('embedded-cli');
        final app = await planOf('embedded-app-desktop');

        expect(cli['tools'], isNot(contains('exec')));
        expect((cli['off']! as Map).keys, contains('shellExec'));
        expect(app['tools'], contains('exec'));
      },
    );

    test('an owned http client is created after the config and closed by '
        'dispose; a passed one is not closed', () async {
      writeHome(providers());
      final owned = _SpyClient();
      final passed = _SpyClient();

      final created = await web.runWithClient(
        () => opener()(cwd: project.path, hostProfile: 'embedded-cli'),
        () => owned,
      );
      await created.dispose();
      final given = await opener(http: passed)(
        cwd: project.path,
        hostProfile: 'embedded-cli',
      );
      await given.dispose();

      expect(owned.closeCalls, 1);
      expect(passed.closeCalls, 0);
    });

    test('an MCP server starts from the environment given to the opener, not '
        'from the process one', () async {
      writeHome(providers());
      final pidFile = File('${temp.path}/server.pid');
      final homeFile = File('${temp.path}/server.home');
      addTearDown(() {
        if (pidFile.existsSync()) {
          Process.killPid(
            int.parse(pidFile.readAsStringSync()),
            ProcessSignal.sigkill,
          );
        }
      });
      final lib = await Isolate.resolvePackageUri(
        Uri.parse('package:codelab_embedded/io.dart'),
      );
      final root = File.fromUri(lib!).parent.parent.path;

      await connect(
        await opener(
          environment: {
            'HOME': '/opener-home-marker',
            'PATH': Platform.environment['PATH'] ?? '',
          },
          http: answeringClient('x'),
        )(cwd: project.path, hostProfile: 'embedded-cli'),
        mcpServers: [
          {
            'name': 'fake',
            'command': Platform.resolvedExecutable,
            'args': [
              '$root/test/support/fake_mcp_stdio_server.dart',
              pidFile.path,
              homeFile.path,
            ],
            'env': <Object?>[],
          },
        ],
      );

      expect(homeFile.readAsStringSync(), '/opener-home-marker');
    });

    test('a profile outside embedded-* is a wiring error before any '
        'resource: no http client is created', () async {
      writeHome(providers());
      var created = 0;

      final thrown = await web.runWithClient(
        () => opener()
            .call(cwd: project.path, hostProfile: 'agent-serve')
            .then<Object?>((_) => null, onError: (Object e) => e),
        () {
          created++;
          return _SpyClient();
        },
      );

      expect(thrown, isA<HostWiringException>());
      expect(created, 0);
    });
  });
}

final class _SpyClient extends web.BaseClient {
  int closeCalls = 0;

  @override
  Future<web.StreamedResponse> send(web.BaseRequest request) =>
      throw StateError('no network');

  @override
  void close() => closeCalls++;
}
