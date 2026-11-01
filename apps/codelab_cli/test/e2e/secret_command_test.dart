// E2E `codelab secret …` (задача 9.2 change `add-agent-secret-store`; spec
// codelab-cli «Подкоманда codelab secret»; agent-secrets «Одинаковый вывод
// двух бинарей»; design.md D8): собранный CLI и собранный `codelab-agent` на
// одних и тех же файлах и окружении. Агент как собеседник не нужен.
//
// Совпадают stdout, код выхода и stderr до справки: справка и сообщения
// разбора argv называют свой бинарь, поэтому у них сравнивается только то,
// что печатает общая `SecretCommands`. Только временные каталоги и
// вымышленные значения; тег `scripted-only` — файл не зависит от агента
// матрицы.
@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';

const _leak = 'sk-LEAK-0123456789';

void main() {
  late Directory tmp;
  late String home;
  late Map<String, String> environment;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_cli_e2e_secret_');
    home = '${tmp.path}/home';
    Directory(home).createSync();
    File('$home/config.yaml').writeAsStringSync('secrets:\n  backend: file\n');
    environment = {'CODELAB_HOME': home, 'HOME': '${tmp.path}/no-home'};
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<CliResult> agent(List<String> args, {String? stdin}) async {
    final process = await Process.start(
      dartExecutable(),
      [await E2eCliAgent.agentKernel(), ...args],
      environment: {'PATH': Platform.environment['PATH'] ?? '', ...environment},
      includeParentEnvironment: false,
    );
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    if (stdin != null) {
      process.stdin.write(stdin);
    }
    await process.stdin.close();
    final out = utf8.decodeStream(process.stdout);
    final err = utf8.decodeStream(process.stderr);
    final code = await process.exitCode.timeout(const Duration(seconds: 60));
    return CliResult(code, await out, await err);
  }

  /// stderr без справки: справка идёт после первой пустой строки и называет
  /// свой бинарь.
  String beforeUsage(String stderr) => stderr.split('\n\n').first;

  test('set with a value argument: both binaries give 64 and the same '
      'output, the value is not printed', () async {
    final cli = await CliProcess.run([
      'secret',
      'set',
      'codelab/x',
      _leak,
    ], environment: environment);
    final other = await agent(['secret', 'set', 'codelab/x', _leak]);

    expect(cli.exitCode, 64, reason: '$cli');
    expect(cli.exitCode, other.exitCode);
    expect(
      cli.stderr,
      contains(
        'pass the secret value on stdin, not as an '
        'argument',
      ),
    );
    expect(cli.stdout, isEmpty);
    expect(cli.stdout, other.stdout);
    expect(beforeUsage(cli.stderr), beforeUsage(other.stderr));
    expect(cli.stderr, contains('codelab secret set|delete|list'));
    expect('${cli.stdout}${cli.stderr}', isNot(contains(_leak)));
    expect(File('$home/secrets.yaml').existsSync(), isFalse);
  }, tags: scriptedOnly);

  test(
    'list: the output and the exit code match codelab-agent secret list',
    () async {
      final cli = await CliProcess.run([
        'secret',
        'list',
      ], environment: environment);
      final other = await agent(['secret', 'list']);

      expect(cli.exitCode, 0, reason: '$cli');
      expect(cli.exitCode, other.exitCode);
      expect(cli.stdout, other.stdout);
      expect(cli.stderr, other.stderr);
    },
    tags: scriptedOnly,
  );

  test('set reads stdin, list shows the name, delete removes it; outputs '
      'match the agent', () async {
    final cliSet = await CliProcess.run(
      ['secret', 'set', 'codelab/x'],
      environment: environment,
      stdin: '$_leak\n',
    );
    expect(cliSet.exitCode, 0, reason: '$cliSet');
    expect(cliSet.stdout, 'Stored secret codelab/x in file\n');
    expect('${cliSet.stdout}${cliSet.stderr}', isNot(contains(_leak)));

    final cliList = await CliProcess.run([
      'secret',
      'list',
    ], environment: environment);
    final agentList = await agent(['secret', 'list']);
    expect(cliList.stdout, contains('codelab/x'));
    expect(cliList.stdout, agentList.stdout);
    expect(cliList.stderr, agentList.stderr);

    final cliDelete = await CliProcess.run([
      'secret',
      'delete',
      'codelab/x',
    ], environment: environment);
    expect(cliDelete.exitCode, 0, reason: '$cliDelete');
    expect(cliDelete.stdout, 'Deleted secret codelab/x from file\n');
    // Агент видит то же хранилище: имя уже удалено.
    final agentDelete = await agent(['secret', 'delete', 'codelab/x']);
    expect(agentDelete.stdout, 'Secret codelab/x was not set in file\n');
  }, tags: scriptedOnly);

  test(
    'no subcommand and unknown subcommand: 64, no quoting of words',
    () async {
      for (final args in [
        ['secret'],
        ['secret', _leak],
      ]) {
        final result = await CliProcess.run(args, environment: environment);
        expect(result.exitCode, 64, reason: '$result');
        expect(result.stdout, isEmpty);
        expect(
          result.stderr,
          startsWith(
            'codelab: secret needs a subcommand: set, delete or '
            'list\n\nUsage: codelab secret set|delete|list',
          ),
        );
        expect(result.stderr, isNot(contains(_leak)));
      }
    },
    tags: scriptedOnly,
  );

  test('-p hi secret list: 64, stdout empty, no agent started', () async {
    final marker = '${tmp.path}/agent-started';
    final result = await CliProcess.run([
      '-p',
      'hi',
      '-a',
      'stdio:touch $marker',
      'secret',
      'list',
    ], environment: environment);

    expect(result.exitCode, 64, reason: '$result');
    expect(result.stdout, isEmpty);
    expect(File(marker).existsSync(), isFalse);
  }, tags: scriptedOnly);

  test('env backend: list is identical in both binaries and shows only the '
      'override names', () async {
    File('$home/config.yaml').writeAsStringSync('secrets:\n  backend: env\n');
    environment = {...environment, 'CODELAB_SECRET_X': '1'};
    final cli = await CliProcess.run([
      'secret',
      'list',
    ], environment: environment);
    final other = await agent(['secret', 'list']);

    expect(cli.exitCode, 0, reason: '$cli');
    expect(cli.exitCode, other.exitCode);
    expect(cli.stdout, other.stdout);
    expect(cli.stderr, other.stderr);
    expect(cli.stdout, contains('Environment overrides: CODELAB_SECRET_X'));
    expect(cli.stdout, isNot(contains('CODELAB_SECRET_X=')));
  }, tags: scriptedOnly);

  test('usage errors: the first message line matches the agent without the '
      'binary prefix', () async {
    // Сообщение — до первой пустой строки; префикс `codelab: ` /
    // `codelab-agent: ` и блок справки у бинарей разные.
    String message(String stderr, String prefix) {
      final head = beforeUsage(stderr);
      expect(head, startsWith(prefix), reason: stderr);
      return head.substring(prefix.length);
    }

    for (final args in [
      ['secret'],
      ['secret', 'set'],
      ['secret', 'list', '-z'],
    ]) {
      final cli = await CliProcess.run(args, environment: environment);
      final other = await agent(args);
      expect(cli.exitCode, 64, reason: '$args $cli');
      expect(other.exitCode, cli.exitCode, reason: '$args');
      expect(
        message(cli.stderr, 'codelab: '),
        message(other.stderr, 'codelab-agent: '),
        reason: '$args',
      );
    }
  }, tags: scriptedOnly);

  test('CODELAB_HOME is not modified by list and by usage errors', () async {
    final before = {
      for (final f in Directory(home).listSync(recursive: true))
        f.path: f is File ? f.readAsStringSync() : 'dir',
    };
    await CliProcess.run(['secret', 'list'], environment: environment);
    await CliProcess.run(['secret', 'set'], environment: environment);

    final after = {
      for (final f in Directory(home).listSync(recursive: true))
        f.path: f is File ? f.readAsStringSync() : 'dir',
    };
    expect(after, before);
    expect(after.keys, ['$home/config.yaml']);
  }, tags: scriptedOnly);

  test('--help names secret set|delete|list', () async {
    final result = await CliProcess.run(['--help'], environment: environment);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('codelab secret set|delete|list'));
  }, tags: scriptedOnly);
}
