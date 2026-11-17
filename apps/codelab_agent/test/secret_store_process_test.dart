import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// Хранилище секретов в процессе `codelab-agent serve --stdio` (agent-binary
/// «Хранилище секретов в бинаре», все сценарии; задача 7.1, design.md change
/// `add-agent-secret-store`, D11). Интеграционный тест на Dart VM
/// (`AGENTS.md` §21): процесс бинаря и локальный HTTP-сервер провайдера. Все
/// значения — тестовые, `CODELAB_HOME` — временный каталог.
void main() {
  late Directory temp;
  late String home;
  late HttpServer provider;
  late List<String?> authorizations;

  const value = 'sk-test-0123456789abcdef';

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('codelab_agent_secret_proc_');
    home = '${temp.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    authorizations = [];
    // 401 завершает ход быстро и без повторов; важен только заголовок.
    provider = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    provider.listen((request) async {
      authorizations.add(request.headers.value('authorization'));
      await request.drain<void>();
      request.response
        ..statusCode = 401
        ..headers.contentType = ContentType.json
        ..write('{"error":{"message":"invalid api key"}}');
      await request.response.close();
    });
  });

  tearDown(() async {
    await provider.close(force: true);
    temp.deleteSync(recursive: true);
  });

  String config({
    String backend = '',
    String key = 'api_key_secret: codelab/p',
  }) =>
      '''
${backend.isEmpty ? '' : 'secrets:\n  backend: $backend\n'}providers:
  p:
    kind: openai-compatible
    base_url: http://127.0.0.1:${provider.port}/v1
    $key
    models:
      m: {}
agent:
  default_model: p/m
''';

  Future<AgentProcess> start(
    String yaml, {
    Map<String, String> environment = const {},
    List<String> extra = const [],
  }) async {
    File('$home/config.yaml').writeAsStringSync(yaml);
    final agent = await AgentProcess.start(
      ['serve', '--stdio', '--log-file', '${temp.path}/agent.log', ...extra],
      environment: {'CODELAB_HOME': home, ...environment},
      workingDirectory: temp.path,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    return agent;
  }

  Map<String, Object?> request(int id, String method, Object? params) => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  };

  /// `initialize`, `session/new`, `session/prompt`: ответ на prompt.
  Future<Map<String, Object?>> turn(AgentProcess agent) async {
    agent.sendJson(request(1, 'initialize', {'protocolVersion': 1}));
    await agent.responseTo(1);
    agent.sendJson(
      request(2, 'session/new', {'cwd': temp.path, 'mcpServers': <Object?>[]}),
    );
    final sessionId =
        ((await agent.responseTo(2))['result']! as Map)['sessionId'];
    agent.sendJson(
      request(3, 'session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': 'Hi'},
        ],
      }),
    );
    return agent.responseTo(3);
  }

  String logText() {
    final file = File('${temp.path}/agent.log');
    return file.existsSync() ? file.readAsStringSync() : '';
  }

  /// Ни значения секрета, ни подстроки из 4+ символов в выводе процесса.
  void expectNoValue(AgentProcess agent) {
    // stdout — кадры ACP: значение не должно попасть и в них. Прочитанные
    // тестом кадры накоплены в `stdoutText`.
    for (final text in [agent.stderrText, logText(), agent.stdoutText]) {
      expect(text, isNot(contains(value)));
      expect(text, isNot(contains('sk-test-0123')));
    }
  }

  test('the provider key comes from CODELAB_SECRET_*; the value is in no '
      'output', () async {
    final agent = await start(
      config(),
      environment: {
        'CODELAB_SECRET_CODELAB_P': value,
        'CODELAB_LOG_LEVEL': 'debug',
      },
    );

    final answer = await turn(agent);

    expect(answer['error'], isNotNull);
    expect(authorizations, ['Bearer $value']);
    await agent.closeStdin();
    expect(await agent.exitCode, 0);
    expect(await agent.nextStdoutLine(), isNull);
    expectNoValue(agent);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('a missing secret with secrets.backend: env is a turn error and the '
      'process keeps running', () async {
    final agent = await start(config(backend: 'env'));

    final answer = await turn(agent);

    expect(
      jsonEncode(answer['error']),
      contains(
        'API key secret codelab/p is not set. Run: codelab secret set codelab/p',
      ),
    );
    expect(authorizations, isEmpty);
    // Процесс жив: закрытый stdin завершает его штатно.
    await agent.closeStdin();
    expect(await agent.exitCode, 0);
  }, timeout: const Timeout(Duration(seconds: 120)));

  for (final (label, args, environment) in [
    ('--debug-secrets', ['--debug-secrets'], <String, String>{}),
    ('CODELAB_DEBUG_SECRETS=1', <String>[], {'CODELAB_DEBUG_SECRETS': '1'}),
  ]) {
    test('$label: secrets.lookup without the value', () async {
      final agent = await start(
        config(),
        extra: args,
        environment: {'CODELAB_SECRET_CODELAB_P': value, ...environment},
      );

      await turn(agent);
      await agent.closeStdin();
      expect(await agent.exitCode, 0);

      final lookups = [
        for (final line in const LineSplitter().convert(logText()))
          if (line.contains('"secrets.lookup"') ||
              line.contains('secrets.lookup'))
            line,
      ];
      expect(lookups, isNotEmpty, reason: logText());
      expect(lookups.first, contains('codelab/p'));
      expect(lookups.first, contains('env'));
      expect(lookups.first, contains('true'));
      expectNoValue(agent);
    }, timeout: const Timeout(Duration(seconds: 120)));
  }

  test('without the mode there is no secrets.lookup', () async {
    final agent = await start(
      config(),
      environment: {'CODELAB_SECRET_CODELAB_P': value},
    );

    await turn(agent);
    await agent.closeStdin();
    expect(await agent.exitCode, 0);

    expect(logText(), isNot(contains('secrets.lookup')));
    expect(agent.stderrText, isNot(contains('secrets.lookup')));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('--llm-script ignores secrets.backend: file; secrets.yaml is not '
      'opened', () async {
    // Права 0644 заставили бы бэкенд `file` отказать (`secrets.file.refused`):
    // сценарий обязан использовать `env` и файл не открывать (D11).
    File('$home/secrets.yaml').writeAsStringSync('# plaintext\n');
    Process.runSync('/bin/chmod', ['644', '$home/secrets.yaml']);
    final extra = File('${temp.path}/extra.yaml')
      ..writeAsStringSync('secrets:\n  backend: file\n');
    final agent = await AgentProcess.start(
      [
        'serve',
        '--stdio',
        '--llm-script',
        'test/llm_scripts/hello.json',
        '--config',
        extra.path,
      ],
      environment: {'CODELAB_HOME': home},
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });

    final answer = await turn(agent);

    expect((answer['result']! as Map)['stopReason'], 'end_turn');
    await agent.closeStdin();
    expect(await agent.exitCode, 0);
    expect(agent.stderrText, contains('secrets.backend.selected'));
    final selected = const LineSplitter()
        .convert(agent.stderrText)
        .singleWhere((line) => line.contains('secrets.backend.selected'));
    expect(selected, contains('backend: env'));
    expect(selected, contains('forced by --llm-script'));
    expect(selected, isNot(contains('configured:')));
    expect(agent.stderrText, isNot(contains('secrets.backend.plaintext')));
    expect(agent.stderrText, isNot(contains('secrets.file.refused')));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('secrets.backend: file logs secrets.backend.plaintext at start and '
      'does not create the file', () async {
    final agent = await start(config(backend: 'file'));

    agent.sendJson(request(1, 'initialize', {'protocolVersion': 1}));
    await agent.responseTo(1);
    await agent.stderrContains('secrets.backend.plaintext');

    expect(agent.stderrText, contains('$home/secrets.yaml'));
    expect(File('$home/secrets.yaml').existsSync(), isFalse);
    await agent.closeStdin();
    expect(await agent.exitCode, 0);
    expect(logText(), contains('secrets.backend.plaintext'));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test(
    'secrets.backend: keychain exits 64 before the transport starts',
    () async {
      final agent = await start(config(backend: 'keychain'));

      final code = await agent.exitCode.timeout(const Duration(seconds: 60));

      expect(code, 64, reason: agent.stderrText);
      expect(agent.stderrText, contains('not supported yet'));
      expect(await agent.nextStdoutLine(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
