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

const _token = 'e2e-secret-token';

Future<String?> _agentKernel() async {
  final source = File('$appDirectory/../codelab_agent/bin/codelab_agent.dart');
  if (!source.existsSync()) {
    return null;
  }
  final dir = await Directory.systemTemp.createTemp('codelab_agent_kernel_');
  final output = '${dir.path}/codelab_agent.dill';
  final result = await Process.run(dartExecutable(), [
    'compile',
    'kernel',
    source.path,
    '-o',
    output,
  ], workingDirectory: '$appDirectory/../codelab_agent');
  return result.exitCode == 0 ? output : null;
}

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_prof_'));
  tearDown(() => dir.delete(recursive: true));

  test('cli/connect-profiles-stdio-ws-embedded: stdio profile from '
      'profiles.json', () async {
    final env = {'CODELAB_HOME': '${dir.path}/codelab'};
    final agent = await scriptedAgent(dir);
    final added = await CliProcess.run([
      'profiles',
      'add',
      'default',
      agent,
    ], environment: env);
    expect(added.exitCode, 0, reason: '$added');

    final result = await CliProcess.run([
      '--cwd',
      dir.path,
      '-p',
      'hi',
    ], environment: env);

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, contains('hello from compatible stdio agent'));
  });

  test('cli/connect-profiles-stdio-ws-embedded: WebSocket with the token '
      'from CODELAB_AGENT_TOKEN', () async {
    final kernel = await _agentKernel();
    if (kernel == null) {
      markTestSkipped('the codelab-agent kernel does not compile');
      return;
    }
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
  });

  test('cli/connect-profiles-stdio-ws-embedded: embedded is 64', () async {
    final result = await CliProcess.run(
      ['--agent', 'embedded', '-p', 'hi'],
      environment: {'CODELAB_HOME': '${dir.path}/codelab'},
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Embedded agent is not available'));
    expect(result.stdout, isEmpty);
  });
}
