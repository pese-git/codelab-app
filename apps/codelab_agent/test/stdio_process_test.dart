import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// `codelab-agent serve --stdio` как процесс (задача 4.6; agent-binary
/// «Команда serve», «Жизненный цикл процесса», «Минимальный конфиг из
/// флагов», «Логи бинаря»; design.md change `add-codelab-agent-binary`, D7,
/// D10). Интеграционный тест на Dart VM (`AGENTS.md` §21).
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_stdio_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<AgentProcess> serveHello({List<String> extra = const []}) =>
      AgentProcess.start(
        [
          'serve',
          '--stdio',
          '--llm-script',
          'test/llm_scripts/hello.json',
          ...extra,
        ],
        environment: {'CODELAB_HOME': '${temp.path}/home'},
      );

  Map<String, Object?> request(int id, String method, Object? params) => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  };

  test('initialize gets one stdout line; logs go to stderr', () async {
    final agent = await serveHello();
    agent.sendLine(
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}',
    );

    final line = await agent.nextStdoutLine();
    final answer = jsonDecode(line!) as Map<String, Object?>;
    expect(answer['id'], 1);
    expect((answer['result']! as Map)['protocolVersion'], 1);

    await agent.closeStdin();
    expect(await agent.exitCode, 0);
    // После ответа stdout пуст: ни одной строки лога.
    expect(await agent.nextStdoutLine(), isNull);
    expect(agent.stderrText, contains('host.plan'));
  });

  test('a turn streams hello and ends with end_turn; EOF exits 0', () async {
    final agent = await serveHello();
    agent.sendJson(request(1, 'initialize', {'protocolVersion': 1}));
    await agent.responseTo(1);
    agent.sendJson(
      request(2, 'session/new', {'cwd': temp.path, 'mcpServers': <Object?>[]}),
    );
    final created = await agent.responseTo(2);
    final sessionId = (created['result']! as Map)['sessionId'];

    agent.sendJson(
      request(3, 'session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': 'Hi'},
        ],
      }),
    );
    final seen = <Map<String, Object?>>[];
    final answer = await agent.responseTo(3, seen: seen);

    expect((answer['result']! as Map)['stopReason'], 'end_turn');
    final chunks = [
      for (final m in seen)
        if (m case {
          'params': {
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'text': final String text},
            },
          },
        })
          text,
    ];
    expect(chunks.join(), 'hello');

    await agent.closeStdin();
    expect(await agent.exitCode, 0);
  });

  test('EOF during a turn cancels it and exits 0', () async {
    final script = File('${temp.path}/wait.json')
      ..writeAsStringSync(
        jsonEncode({
          'llm': {
            'steps': [
              {
                'reply': [
                  {'text': 'working'},
                ],
                'waitForCancel': true,
              },
            ],
          },
        }),
      );
    final agent = await AgentProcess.start(
      ['serve', '--stdio', '--llm-script', script.path],
      environment: {'CODELAB_HOME': '${temp.path}/home'},
    );
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
          {'type': 'text', 'text': 'Long task'},
        ],
      }),
    );
    // Первый кадр хода — ход идёт.
    expect(await agent.nextStdoutLine(), contains('session/update'));

    await agent.closeStdin();
    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 0);
  });

  test('SIGINT exits 130 and SIGTERM exits 143', () async {
    for (final (signal, code) in [
      (ProcessSignal.sigint, 130),
      (ProcessSignal.sigterm, 143),
    ]) {
      final agent = await serveHello();
      agent.sendJson(request(1, 'initialize', {'protocolVersion': 1}));
      await agent.responseTo(1);
      agent.kill(signal);
      expect(await agent.exitCode, code, reason: '$signal');
    }
  }, skip: Platform.isWindows ? 'POSIX signals' : null);

  test('usage errors exit 64 with the text in stderr', () async {
    final noTransport = await AgentProcess.start([
      'serve',
      '--llm-script',
      'test/llm_scripts/hello.json',
    ]);
    expect(await noTransport.exitCode, 64);
    expect(noTransport.stderrText, contains('--stdio'));

    final logToStdout = await serveHello(extra: ['--log-file', '/dev/stdout']);
    expect(await logToStdout.exitCode, 64);
    expect(
      logToStdout.stderrText,
      contains(
        '--log-file cannot point to stdout: stdout carries the ACP protocol',
      ),
    );
    expect(await logToStdout.nextStdoutLine(), isNull);
  });

  test('CODELAB_API_KEY reaches the provider but no log', () async {
    // Провайдер отвечает 401: ход падает быстро, без повторов (auth).
    final provider = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final keys = <String?>[];
    provider.listen((request) async {
      keys.add(request.headers.value('authorization'));
      await request.drain<void>();
      request.response
        ..statusCode = 401
        ..headers.contentType = ContentType.json
        ..write('{"error":{"message":"invalid api key"}}');
      await request.response.close();
    });
    addTearDown(() => provider.close(force: true));

    final logFile = '${temp.path}/logs/agent.log';
    final agent = await AgentProcess.start(
      [
        'serve',
        '--stdio',
        '--provider',
        'openai-compatible',
        '--base-url',
        'http://127.0.0.1:${provider.port}/v1',
        '--model',
        'gpt-5',
        '--log-level',
        'debug',
        '--log-file',
        logFile,
      ],
      environment: {
        'CODELAB_HOME': '${temp.path}/home',
        'CODELAB_API_KEY': 'sk-test-secret',
      },
    );
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
    final answer = await agent.responseTo(3);
    expect((answer['error']! as Map)['code'], -32603);

    await agent.closeStdin();
    expect(await agent.exitCode, 0);
    expect(keys, contains('Bearer sk-test-secret'));
    expect(agent.stderrText, isNot(contains('sk-test-secret')));
    final logged = File(logFile).readAsStringSync();
    expect(logged, isNotEmpty);
    expect(logged, isNot(contains('sk-test-secret')));
  });
}
