import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// `codelab-agent secret migrate` как процесс (agent-binary «Подкоманда
/// secret бинаря», сценарии «Секрет из файла переносится», «Предупреждение о
/// 1.0 в справке», «Неизвестная подкоманда»; design.md change
/// `add-config-literal-secrets-and-migrate`, D7, D13, R8-7). Интеграционный
/// тест на Dart VM: процессы во временных `CODELAB_HOME` и `HOME`, значения
/// выдуманные.
void main() {
  late Directory temp;
  late String home;
  late String project;

  final key = 'sk-${'a1b2c3d4e5' * 3}';
  const note =
      'Note: before 1.0, tool output, prompts and session logs are not '
      'redacted: secrets they contain reach the model provider and session '
      'files as is.';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_agent_migrate_');
    home = '${temp.path}/home';
    project = '${temp.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  String config({bool literal = true}) =>
      'secrets:\n  backend: file\n'
      'providers:\n  lm:\n    kind: openai-compatible\n'
      '    base_url: https://llm.test/v1\n'
      '${literal ? '    api_key: $key\n' : '    api_key_secret: codelab/lm\n'}'
      '    models:\n      m: {}\nagent:\n  default_model: lm/m\n';

  Future<AgentProcess> start(List<String> args) async {
    final agent = await AgentProcess.start(
      args,
      environment: {'CODELAB_HOME': home, 'HOME': temp.path},
      workingDirectory: project,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    return agent;
  }

  Future<(int, String, String)> run(List<String> args) async {
    final agent = await start(args);
    await agent.closeStdin();
    final code = await agent.exitCode.timeout(const Duration(seconds: 60));
    final out = StringBuffer();
    String? line;
    while ((line = await agent.nextStdoutLine()) != null) {
      out.writeln(line);
    }
    return (code, out.toString(), agent.stderrText);
  }

  /// Запускает `serve --stdio`, дожидается `initialize` и возвращает лог.
  Future<String> serveLog(String name) async {
    final logFile = '${temp.path}/logs/$name.log';
    final agent = await start([
      'serve',
      '--stdio',
      '--log-file',
      logFile,
      '--log-level',
      'trace',
    ]);
    agent.sendJson({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': 1},
    });
    final initialized = await agent.responseTo(1);
    await agent.closeStdin();
    final code = await agent.exitCode.timeout(const Duration(seconds: 30));
    expect(initialized['result'], isNotNull, reason: agent.stderrText);
    expect(code, 0, reason: agent.stderrText);
    return File(logFile).readAsStringSync();
  }

  test('a literal key: serve warns, secret migrate moves it, serve restarts '
      'without the warning', () async {
    File('$home/config.yaml').writeAsStringSync(config());

    final before = await serveLog('before');
    expect(before, contains('config.secret.in_file'));
    expect(before, contains('codelab secret migrate'));
    expect(before, isNot(contains(key)));

    final (code, out, err) = await run(['secret', 'migrate']);

    expect(code, 0, reason: err);
    expect(out, contains('Moved providers.lm.api_key in '));
    expect(out, contains('restart the agent to use the moved secrets'));
    expect('$out$err', isNot(contains(key)));
    expect(
      File('$home/config.yaml').readAsStringSync(),
      allOf(contains('api_key_secret: codelab/lm'), isNot(contains(key))),
    );
    expect(
      File('$home/secrets.yaml').readAsStringSync(),
      contains('codelab/lm'),
    );

    final after = await serveLog('after');
    expect(after, isNot(contains('config.secret.in_file')));
    expect(after, isNot(contains(key)));
  }, timeout: const Timeout(Duration(seconds: 180)));

  test('--dry-run prints the plan and changes nothing', () async {
    File('$home/config.yaml').writeAsStringSync(config());
    final configBefore = File('$home/config.yaml').readAsStringSync();

    final (code, out, err) = await run(['secret', 'migrate', '--dry-run']);

    expect(code, 0, reason: err);
    expect(
      out,
      contains('providers.lm.api_key -> api_key_secret: codelab/lm (new)'),
    );
    expect(File('$home/config.yaml').readAsStringSync(), configBefore);
    expect(File('$home/secrets.yaml').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('argv: --all with --project, a positional word and an unknown flag '
      'are usage errors that do not echo the words', () async {
    File('$home/config.yaml').writeAsStringSync(config());

    for (final args in [
      ['secret', 'migrate', '--all', '--project'],
      ['secret', 'migrate', 'sk-leaked-word'],
      ['secret', 'migrate', '--sk-leaked-flag'],
    ]) {
      final (code, out, err) = await run(args);

      expect(code, 64, reason: err);
      expect(out, isEmpty);
      expect(err, contains('Usage: codelab-agent secret'));
      expect(err, isNot(contains('sk-leaked')));
    }
    expect(File('$home/secrets.yaml').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 180)));

  test('--cwd names the project directory', () async {
    File('$home/config.yaml').writeAsStringSync(config(literal: false));

    final (code, _, err) = await run([
      'secret',
      'migrate',
      '--cwd',
      '${temp.path}/missing',
    ]);

    expect(code, 64);
    expect(err, contains('no such directory'));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('secret without a subcommand: the message names migrate and the '
      'help carries the 1.0 note; so does the serve usage', () async {
    final (code, _, err) = await run(['secret']);
    expect(code, 64);
    expect(
      err,
      contains(
        'codelab-agent: secret needs a subcommand: set, delete, list or '
        'migrate',
      ),
    );
    expect(err, contains(note));
    expect(err, contains('secret migrate'));

    // У `serve` нет флага `--help`: справка печатается при ошибке
    // использования (код 64), и строка о 1.0 стоит в ней.
    final (serveCode, _, serveErr) = await run(['serve']);
    expect(serveCode, 64);
    expect(serveErr, contains(note));
  }, timeout: const Timeout(Duration(seconds: 120)));
}
