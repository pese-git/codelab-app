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

/// Хранилище секретов хоста `codelab-agent` (agent-binary «Хранилище секретов
/// в бинаре»; задачи 7.1–7.2, design.md change `add-agent-secret-store`, D11).
/// Хост поднимается в процессе теста, HTTP — `MockClient`, реальной сети нет;
/// `CODELAB_HOME` и окружение — временные, настоящий `~/.codelab` не читается.
void main() {
  late Directory temp;
  late String home;

  const value = 'sk-test-0123456789abcdef';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_agent_secrets_');
    home = '${temp.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  const providerConfig = '''
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

  String writeConfig(String text) =>
      (File('${temp.path}/c.yaml')..writeAsStringSync(text)).path;

  ServeOptions options(
    List<String> args, {
    Map<String, String> environment = const {},
    String transport = '--stdio',
  }) => parseServeArgs(
    ['serve', transport, ...args],
    environment: {'CODELAB_HOME': home, ...environment},
  );

  /// Клиент, запоминающий заголовок `Authorization`; ответ 401 завершает ход
  /// быстро и без повторов.
  (http.Client, List<String?>) recordingClient() {
    final authorizations = <String?>[];
    final client = MockClient.streaming((request, body) async {
      authorizations.add(request.headers['authorization']);
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":{"message":"denied"}}')),
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    return (client, authorizations);
  }

  Future<AcpPeer> start(
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
    return AcpPeer(link.client);
  }

  Future<Object?> promptError(AcpPeer peer, {String? session}) async {
    final id = session ?? await peer.openSession(temp.path);
    try {
      await peer.prompt(id, 'hi');
    } on AcpCallFailed catch (error) {
      return error;
    }
    return null;
  }

  for (final transport in ['--stdio', '--ws']) {
    test('$transport: the provider key comes from CODELAB_SECRET_*', () async {
      final path = writeConfig(providerConfig);
      final (client, authorizations) = recordingClient();
      final peer = await start(
        options(
          ['--config', path],
          transport: transport,
          environment: {'CODELAB_SECRET_CODELAB_P': value},
        ),
        client: client,
      );

      await promptError(peer);

      expect(authorizations, ['Bearer $value']);
    });
  }

  test('a missing secret is a turn error, not a crash', () async {
    final path = writeConfig('secrets:\n  backend: env\n$providerConfig');
    final (client, authorizations) = recordingClient();
    final peer = await start(options(['--config', path]), client: client);

    final session = await peer.openSession(temp.path);
    final error = await promptError(peer, session: session);

    expect(
      '$error',
      contains(
        'API key secret codelab/p is not set. Run: codelab secret set codelab/p',
      ),
    );
    expect(authorizations, isEmpty);
    // Сервер продолжает работать: следующий ход тоже отвечает ошибкой хода.
    expect(await promptError(peer, session: session), isA<AcpCallFailed>());
  });

  group('--debug-secrets', () {
    Future<RecordingLogger> run(
      List<String> args,
      Map<String, String> environment,
    ) async {
      final path = writeConfig(providerConfig);
      final logger = RecordingLogger();
      final (client, _) = recordingClient();
      final peer = await start(
        options(['--config', path, ...args], environment: environment),
        client: client,
        logger: logger,
      );
      await promptError(peer);
      return logger;
    }

    test('the flag logs secrets.lookup without the value', () async {
      final logger = await run(
        ['--debug-secrets'],
        {'CODELAB_SECRET_CODELAB_P': value},
      );

      final lookups = logger.eventsOf('secrets.lookup');
      expect(lookups, isNotEmpty);
      expect(lookups.first.fields, {
        'name': 'codelab/p',
        'purpose': 'providers.p.api_key_secret',
        'source': 'env',
        'found': true,
      });
      expect(
        logger.records.map((r) => '${r.event} ${r.fields} ${r.error}').join(),
        isNot(contains(value)),
      );
    });

    test('CODELAB_DEBUG_SECRETS=1 works like the flag', () async {
      final logger = await run(const [], {
        'CODELAB_SECRET_CODELAB_P': value,
        'CODELAB_DEBUG_SECRETS': '1',
      });

      expect(logger.eventsOf('secrets.lookup'), isNotEmpty);
    });

    test('without the mode there are no lookups', () async {
      final logger = await run(const [], {'CODELAB_SECRET_CODELAB_P': value});

      expect(logger.eventsOf('secrets.lookup'), isEmpty);
    });
  });

  group('secrets.backend', () {
    test('file: plaintext warning at start, the file is not created', () async {
      final path = writeConfig('secrets:\n  backend: file\n$providerConfig');
      final logger = RecordingLogger();

      await start(options(['--config', path]), logger: logger);

      final warnings = logger.eventsOf('secrets.backend.plaintext');
      expect(warnings, hasLength(1));
      expect(warnings.single.fields['path'], '$home/secrets.yaml');
      expect(File('$home/secrets.yaml').existsSync(), isFalse);
    });

    test('--llm-script always uses env: secrets.yaml is not opened', () async {
      // Права 0644 заставили бы бэкенд `file` отказать и записать
      // `secrets.file.refused`; событий нет — файл не открывался (D11).
      File('$home/secrets.yaml').writeAsStringSync('# plaintext\n');
      Process.runSync('/bin/chmod', ['644', '$home/secrets.yaml']);
      final path = writeConfig('secrets:\n  backend: file\n');
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

      expect(logger.eventsOf('secrets.backend.plaintext'), isEmpty);
      expect(logger.eventsOf('secrets.file.refused'), isEmpty);
      final selected = logger.eventsOf('secrets.backend.selected').single;
      expect(selected.fields['backend'], 'env');
      expect(selected.fields['reason'], 'forced by --llm-script');
    });
  });
}
