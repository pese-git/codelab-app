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

/// Фиктивный секрет в query адреса профиля: в вывод CLI не попадает.
const _urlLeak = 'sk-test-leak-query';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_prof_'));
  tearDown(() => dir.delete(recursive: true));

  test('cli/connect-profiles-stdio-ws-embedded: stdio profile from '
      'profiles.json', () async {
    final launch = await E2eCliAgent.current.launch(dir);
    final env = {'CODELAB_HOME': '${dir.path}/codelab', ...launch.environment};
    final added = await CliProcess.run([
      'profiles',
      'add',
      e2eProfileId,
      launch.agent,
    ], environment: env);
    expect(added.exitCode, 0, reason: '$added');

    final result = await CliProcess.run([
      '-a',
      e2eProfileId,
      '--cwd',
      dir.path,
      '-p',
      'hi',
    ], environment: env);

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, contains(launch.answer));
  }, skip: E2eCliAgent.current.needsStoredProfile);

  /// Поднимает `codelab-agent serve --ws`, требующий [_token], и возвращает
  /// порт. Сервер — всегда Dart-агент теста.
  Future<String> startWebSocketAgent() async {
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
    return listening.firstMatch('$stderr')!.group(1)!;
  }

  test('cli/connect-profiles-stdio-ws-embedded: WebSocket with the token '
      'from CODELAB_AGENT_TOKEN', () async {
    final port = await startWebSocketAgent();

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

  test('cli/connect-profiles-stdio-ws-embedded: a profile with '
      'tokenRef env:DEVBOX_TOKEN gets the token of that variable '
      '(spec «Токен из произвольной переменной»; D15)', () async {
    final port = await startWebSocketAgent();
    final home = Directory('${dir.path}/codelab')..createSync();
    File('${home.path}/profiles.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'profiles': [
          {
            'type': 'webSocket',
            'id': 'devbox',
            'label': 'Devbox',
            'uri': 'ws://127.0.0.1:$port/acp',
            'tokenRef': 'env:DEVBOX_TOKEN',
          },
        ],
      }),
    );

    final result = await CliProcess.run(
      ['-a', 'devbox', '--cwd', dir.path, '-p', 'hi'],
      // CODELAB_AGENT_TOKEN CLI не задан: токен берётся только из ссылки.
      environment: {'CODELAB_HOME': home.path, 'DEVBOX_TOKEN': _token},
    );

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, contains('hello over websocket'));
    expect('${result.stdout}${result.stderr}', isNot(contains(_token)));
  }, tags: scriptedOnly);

  // Токен из хранилища секретов (task 1.8 change `add-provider-setup-ui`;
  // spec codelab-cli «Токен из хранилища секретов»): временный CODELAB_HOME с
  // бэкендом `file`, значение — фиктивный токен сервера теста.
  test('cli/connect-profiles-stdio-ws-embedded: a profile with tokenRef '
      'secret:<name> gets the token from the secret store', () async {
    final port = await startWebSocketAgent();
    final home = Directory('${dir.path}/codelab')..createSync();
    File(
      '${home.path}/config.yaml',
    ).writeAsStringSync('secrets:\n  backend: file\n');
    const name = 'codelab/profiles/devbox/token';
    File('${home.path}/profiles.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'profiles': [
          {
            'type': 'webSocket',
            'id': 'devbox',
            'label': 'Devbox',
            'uri': 'ws://127.0.0.1:$port/acp',
            'tokenRef': 'secret:$name',
          },
        ],
      }),
    );
    final environment = {'CODELAB_HOME': home.path};
    final stored = await CliProcess.run(
      ['secret', 'set', name],
      environment: environment,
      stdin: _token,
    );
    expect(stored.exitCode, 0, reason: stored.stderr);

    final shown = await CliProcess.run([
      'profiles',
      'show',
      'devbox',
    ], environment: environment);
    final result = await CliProcess.run([
      '-a',
      'devbox',
      '--cwd',
      dir.path,
      '-p',
      'hi',
    ], environment: environment);

    expect(shown.stdout, contains('token: secret $name (set)'));
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('hello over websocket'));
    final output =
        '${shown.stdout}${shown.stderr}${result.stdout}${result.stderr}';
    expect(output, isNot(contains(_token)));
  }, tags: scriptedOnly);

  // Регрессионная защита (spec codelab-cli «ссылка не вида env: не
  // выводится»): ссылка не вида `env:` могла быть вписана вместо имени
  // переменной вместе с секретом; CLI подключается без токена и нигде не
  // печатает её, в том числе в журнале `--verbose`.
  test('cli/connect-profiles-stdio-ws-embedded: a tokenRef that is not env: '
      'goes without a token and is never printed', () async {
    // Сервер без токена не стартует, поэтому «без токена» проверяется
    // отказом сервера: ссылка не превратилась ни в какой токен.
    final port = await startWebSocketAgent();
    final home = Directory('${dir.path}/codelab')..createSync();
    File('${home.path}/profiles.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'profiles': [
          {
            'type': 'webSocket',
            'id': 'devbox',
            'label': 'Devbox',
            'uri': 'ws://127.0.0.1:$port/acp',
            'tokenRef': 'sk-test-leak-123',
          },
        ],
      }),
    );

    final result = await CliProcess.run(
      ['-a', 'devbox', '--cwd', dir.path, '-p', 'hi', '--verbose'],
      environment: {'CODELAB_HOME': home.path},
    );

    expect(result.exitCode, isNot(0), reason: '$result');
    expect(result.stdout, isNot(contains('hello over websocket')));
    final output = '${result.stdout}${result.stderr}';
    expect(output, isNot(contains('sk-test-leak-123')));
    expect(output, isNot(contains(_token)));
  }, tags: scriptedOnly);

  // Отказ рукопожатия по токену называется своими словами (spec codelab-cli
  // «Отказ подключения из-за токена»): «отверг токен» — токен ушёл, «требует
  // токен» — нет. Значения токенов (фиктивные) в вывод не попадают.
  test('cli/connect-profiles-stdio-ws-embedded: a wrong token is reported as '
      'rejected, a missing one as required', () async {
    final port = await startWebSocketAgent();
    const wrong = 'sk-test-leak-wrong';
    final home = Directory('${dir.path}/codelab')..createSync();
    File('${home.path}/profiles.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'profiles': [
          {
            'type': 'webSocket',
            'id': 'devbox',
            'label': 'Devbox',
            'uri': 'ws://127.0.0.1:$port/acp?t=$_urlLeak',
            'tokenRef': 'env:DEVBOX_TOKEN',
          },
        ],
      }),
    );
    // В тексте — только origin: query адреса несёт секрет.
    final url = 'ws://127.0.0.1:$port';

    final rejected = await CliProcess.run(
      ['-a', 'devbox', '--cwd', dir.path, '-p', 'hi'],
      environment: {'CODELAB_HOME': home.path, 'DEVBOX_TOKEN': wrong},
    );
    final required = await CliProcess.run(
      ['-a', 'devbox', '--cwd', dir.path, '-p', 'hi'],
      // DEVBOX_TOKEN не задан: токен не отправляется.
      environment: {'CODELAB_HOME': home.path},
    );

    expect(rejected.exitCode, 1, reason: '$rejected');
    expect(
      rejected.stderr,
      contains(
        'codelab: cannot start the agent $url: '
        'the agent rejected the token (HTTP 401).',
      ),
    );
    expect(required.exitCode, 1, reason: '$required');
    expect(
      required.stderr,
      contains(
        'codelab: cannot start the agent $url: '
        'the agent requires a token (HTTP 401).',
      ),
    );
    final output =
        '${rejected.stdout}${rejected.stderr}${required.stdout}${required.stderr}';
    expect(output, isNot(contains(wrong)));
    expect(output, isNot(contains(_token)));
    expect(output, isNot(contains(_urlLeak)));
    expect(output, isNot(contains('/acp')));
  }, tags: scriptedOnly);

  // Критерий `cli/connect-profiles-stdio-ws-embedded`, вариант `embedded`:
  // `-a embedded` проводит ход встроенного агента в процессе CLI (CLI из
  // тестовой точки входа со сценарием модели, design.md change
  // `add-embedded-agent-mode`, D8), дочернего процесса агента нет.
  test('cli/connect-profiles-stdio-ws-embedded: embedded runs the turn in '
      'the CLI process', () async {
    final launch = await E2eCliAgent.fromEnvironment({
      'CODELAB_E2E_AGENT': 'embedded',
    }).launch(dir);

    final result = await CliProcess.run(
      ['--agent', 'embedded', '--cwd', dir.path, '-p', 'hi'],
      environment: {
        'CODELAB_HOME': '${dir.path}/codelab',
        ...launch.environment,
      },
      entry: CliEntry.scriptedEmbedded,
    );

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, '${launch.answer}\n');
  });

  test('cli/connect-profiles-stdio-ws-embedded: embedded is not stored in '
      'profiles.json', () async {
    final result = await CliProcess.run(
      ['profiles', 'add', 'x', 'embedded'],
      environment: {'CODELAB_HOME': '${dir.path}/codelab'},
      entry: CliEntry.production,
    );

    expect(result.exitCode, 64, reason: '$result');
    expect(result.stdout, isEmpty);
    expect(
      result.stderr,
      contains('embedded is built in; use --agent embedded'),
    );
  });
}
