import 'dart:io';

import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:path/path.dart' as p;

import 'cli_args.dart';
import 'cli_io.dart';
import 'composition_root.dart';
import 'exit_codes.dart';
import 'headless/headless_runner.dart';
import 'headless/outcome.dart';
import 'home.dart';
import 'profiles/profile_arg.dart';
import 'profiles/profiles_command.dart';

/// Запуск `codelab` от аргументов до кода выхода (design.md change
/// `add-codelab-cli`, D2).
///
/// Почему отдельная функция: `bin/` — только точка входа, а выбор режима,
/// коды выхода и то, что попадает в stdout, должны быть одни для процесса и
/// модульных тестов.
///
/// Как использовать: `exit(await runCodelab(args, environment:
/// Platform.environment))`; тесты передают [io] с буферами. Ошибка
/// использования — текст в stderr, пустой stdout и [usageExit].
Future<int> runCodelab(
  List<String> args, {
  required Map<String, String> environment,
  CliIo io = const ProcessCliIo(),
}) async {
  try {
    return await _run(args, environment, io);
  } on UsageError catch (error) {
    io.stderr.writeln('codelab: ${error.message}');
    return usageExit;
  } finally {
    await io.flush();
  }
}

Future<int> _run(
  List<String> args,
  Map<String, String> environment,
  CliIo io,
) async {
  final options = parseCliArgs(args);
  switch (options.command) {
    case CliCommand.version:
      io.stdout.writeln('codelab $cliVersion');
      return okExit;
    case CliCommand.help:
      io.stdout.writeln(cliUsage());
      return okExit;
    case CliCommand.profiles:
      final home = CodelabHome.resolve(environment);
      await home.ensureExists();
      return runProfilesCommand(
        options.positional,
        store: JsonFileProfileStore(home.profilesFile),
        stdout: io.stdout,
        stderr: io.stderr,
      );
    case CliCommand.headless:
      return _runHeadless(options, environment, io);
    case CliCommand.repl:
      // REPL появляется в итерации 3 (tasks 6.6); до неё — ошибка
      // использования, а не молчание.
      throw const UsageError('The interactive REPL is not implemented yet.');
  }
}

Future<int> _runHeadless(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
) async {
  // Промпт из файла и stdin — итерация 2 (tasks 4.6).
  final prompt = options.prompt;
  if (prompt == null) {
    throw const UsageError('--prompt-file is not implemented yet.');
  }
  if (prompt.trim().isEmpty) {
    throw const UsageError('No prompt.');
  }
  final cwd = await _sessionFolder(options.cwd);
  final home = CodelabHome.resolve(environment);
  final profile = await resolveAgentProfile(
    options.agent,
    store: JsonFileProfileStore(home.profilesFile),
  );

  final runtime = buildCliRuntime(
    environment: environment,
    stderr: io.stderr,
    verbose: options.verbose,
  );
  try {
    final outcome = await HeadlessRunner(
      workspace: runtime.workspace,
      stdout: io.stdout,
      stderr: io.stderr,
      verbose: options.verbose,
    ).run(profile: profile, cwd: cwd, prompt: prompt);
    return exitCodeOf(outcome);
  } finally {
    await runtime.dispose();
  }
}

/// Абсолютный путь рабочей папки сессии; несуществующая папка — ошибка
/// использования, а не сбой агента.
Future<String> _sessionFolder(String? value) async {
  final path = p.normalize(p.absolute(value ?? Directory.current.path));
  if (!await Directory(path).exists()) {
    throw UsageError('No such folder: $path');
  }
  return path;
}
