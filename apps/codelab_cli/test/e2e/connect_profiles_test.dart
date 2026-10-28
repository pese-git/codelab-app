// Профили подключения: stdio из `profiles.json`, WebSocket к
// `codelab-agent serve --ws` и `embedded` (tasks 7.7; spec codelab-cli
// «Профили подключения CLI»; U-06; design.md change `add-codelab-cli`, D4).
//
// Бинарь агента компилируется в kernel из `apps/codelab_agent` как отдельный
// процесс: CLI не импортирует `package:codelab_agent_*` (сторож), а тест
// проверяет настоящий сервер по сокету.
@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';

const _token = 'e2e-secret-token';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_prof_'));
  tearDown(() => dir.delete(recursive: true));

  test('cli/connect-profiles-stdio-ws-embedded: stdio profile from '
      'profiles.json', () async {
    final env = {'CODELAB_HOME': '${dir.path}/codelab'};
    final launch = await E2eCliAgent.current.launch(dir);
    final added = await CliProcess.run([
      'profiles',
      'add',
      'default',
      launch.agent,
    ], environment: env);
    expect(added.exitCode, 0, reason: '$added');

    final result = await CliProcess.run([
      '--cwd',
      dir.path,
      '-p',
      'hi',
    ], environment: env);

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, contains(launch.answer));
  });

  test('cli/connect-profiles-stdio-ws-embedded: WebSocket with the token '
      'from CODELAB_AGENT_TOKEN', () async {
    final kernel = await E2eCliAgent.agentKernel();
    final script = File('${dir.path}/hello.json')
      ..writeAsStringSync(
        jsonEncode({
          'llm': {
            'model': {
              'provider': 'scripted',
              'modelId': 'scripted-1',
              'contextWindow': 32768,
            },
            'steps': [
              {
                'reply': [
                  {'text': 'hello over websocket'},
                ],
                'stopReason': 'stop',
              },
            ],
          },
        }),
      );
    final server = await Process.start(
      dartExecutable(),
      [kernel, 'serve', '--ws', '--port', '0', '--llm-script', script.path],
      environment: {
        'CODELAB_HOME': '${dir.path}/agent-home',
        'CODELAB_AGENT_TOKEN': _token,
      },
    );
    addTearDown(() => server.kill(ProcessSignal.sigkill));
    // Вывод сервера читается до конца: закрытый pipe уронил бы агента на
    // следующей записи в лог.
    final stderr = StringBuffer();
    server.stdout.drain<void>().ignore();
    final listening = RegExp(r'serve\.ws\.listening .*port: (\d+)');
    server.stderr.transform(utf8.decoder).listen(stderr.write);
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (listening.firstMatch('$stderr') == null) {
      if (DateTime.now().isAfter(deadline)) {
        fail('codelab-agent did not listen:\n$stderr');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final port = listening.firstMatch('$stderr')!.group(1);

    final result = await CliProcess.run(
      ['--agent', 'ws://127.0.0.1:$port/acp', '--cwd', dir.path, '-p', 'hi'],
      environment: {
        'CODELAB_HOME': '${dir.path}/codelab',
        'CODELAB_AGENT_TOKEN': _token,
      },
    );

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, contains('hello over websocket'));
    expect('${result.stdout}${result.stderr}', isNot(contains(_token)));
    // Сервер — всегда Dart-агент теста: в прогоне `dart` тест не повторяется.
  }, tags: scriptedOnly);

  test('cli/connect-profiles-stdio-ws-embedded: embedded is 64', () async {
    final result = await CliProcess.run(
      ['--agent', 'embedded', '-p', 'hi'],
      environment: {'CODELAB_HOME': '${dir.path}/codelab'},
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Embedded agent is not available'));
    expect(result.stdout, isEmpty);
  }, tags: scriptedOnly);
}
