// Сравнение `codelab` и `codelab-agent` на одном входе для e2e подкоманд,
// у которых реализация общая (`SecretCommands`, `McpServerCommands`;
// capability codelab-cli, design.md change
// `add-config-literal-secrets-and-migrate`, D7, D11).
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../support/cli_process.dart';
import 'e2e_agent.dart';

/// Пара бинарей над одним `CODELAB_HOME` и одной рабочей папкой.
///
/// Почему: пути в выводе (`Moved … in <home>/config.yaml`) совпадают
/// буквально, только если оба бинаря работают над одними и теми же путями, а
/// состояние перед каждым прогоном возвращается в исходное. Значения
/// выдуманные, настоящий `~/.codelab` не читается; `HOME` — несуществующая
/// папка внутри временного каталога.
final class DualBinary {
  DualBinary._(this.tmp, this.home, this.project, this.environment);

  /// Создаёт временные каталоги; [dispose] их удаляет.
  factory DualBinary.create(String prefix) {
    // Канонический путь: на macOS `/var` — ссылка на `/private/var`, а
    // писатель раскрывает ссылки.
    final tmp = Directory(
      Directory.systemTemp.createTempSync(prefix).resolveSymbolicLinksSync(),
    );
    final home = '${tmp.path}/home';
    final project = '${tmp.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    return DualBinary._(tmp, home, project, {
      'CODELAB_HOME': home,
      'HOME': '${tmp.path}/no-home',
    });
  }

  final Directory tmp;
  final String home;
  final String project;
  final Map<String, String> environment;

  void dispose() => tmp.deleteSync(recursive: true);

  /// Приводит `CODELAB_HOME` и `<project>/.codelab` к виду [files]: имена
  /// относительно `CODELAB_HOME`, а с префиксом `project/` — относительно
  /// `<project>`.
  void reset(Map<String, String> files) {
    for (final entity in Directory(home).listSync()) {
      entity.deleteSync(recursive: true);
    }
    final dot = Directory('$project/.codelab');
    if (dot.existsSync()) {
      dot.deleteSync(recursive: true);
    }
    files.forEach((name, text) {
      final file = name.startsWith('project/')
          ? File('$project/${name.substring('project/'.length)}')
          : File('$home/$name');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text);
    });
  }

  /// Текст файлов состояния после прогона: имя -> содержимое.
  Map<String, String> files() => {
    for (final entity in [
      ...Directory(home).listSync().whereType<File>(),
      if (Directory('$project/.codelab').existsSync())
        ...Directory('$project/.codelab').listSync().whereType<File>(),
    ])
      entity.path.substring(tmp.path.length): entity.readAsStringSync(),
  };

  Future<CliResult> runAgent(List<String> args, {String? stdin}) async {
    final process = await Process.start(
      dartExecutable(),
      [await E2eCliAgent.agentKernel(), ...args],
      environment: {'PATH': Platform.environment['PATH'] ?? '', ...environment},
      workingDirectory: project,
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

  Future<CliResult> runCli(List<String> args, {String? stdin}) =>
      CliProcess.run(
        args,
        environment: environment,
        workingDirectory: project,
        stdin: stdin,
      );

  /// Запускает [args] у обоих бинарей из состояния [files] и требует
  /// одинаковых кода, stdout, stderr и файлов состояния. Возвращает
  /// результат `codelab`.
  ///
  /// [stderrBeforeUsageOnly]: сравнивать stderr только до первой пустой строки
  /// (после неё идёт справка, которая называет свой бинарь).
  Future<CliResult> expectSame(
    List<String> args, {
    required Map<String, String> files,
    String? stdin,
    bool stderrBeforeUsageOnly = false,
  }) async {
    reset(files);
    final cli = await runCli(args, stdin: stdin);
    final cliFiles = this.files();
    reset(files);
    final agent = await runAgent(args, stdin: stdin);
    final agentFiles = this.files();

    expect(cli.exitCode, agent.exitCode, reason: '$args\n$cli\n$agent');
    expect(cli.stdout, agent.stdout, reason: '$args');
    final agentStderr = agent.stderr.replaceAll('codelab-agent', 'codelab');
    if (stderrBeforeUsageOnly) {
      expect(
        cli.stderr.split('\n\n').first,
        agentStderr.split('\n\n').first,
        reason: '$args',
      );
    } else {
      expect(cli.stderr, agentStderr, reason: '$args');
    }
    expect(cliFiles, agentFiles, reason: '$args');
    return cli;
  }
}
