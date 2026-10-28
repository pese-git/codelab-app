import 'dart:async';
import 'dart:io';

import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:path/path.dart' as p;

import 'cli_args.dart';
import 'cli_io.dart';
import 'composition_root.dart';
import 'exit_codes.dart';
import 'headless/headless_runner.dart';
import 'headless/outcome.dart';
import 'headless/prompt_source.dart';
import 'home.dart';
import 'input/io_terminal.dart';
import 'profiles/profile_arg.dart';
import 'profiles/profiles_command.dart';
import 'render/output_surface.dart';
import 'repl/repl.dart';
import 'scenario/test_scenario_command.dart';
import 'tui/tui_runner.dart';
import 'signals.dart';

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
    case CliCommand.testScenario:
      final home = CodelabHome.resolve(environment);
      return runTestScenario(
        options,
        profile: await resolveAgentProfile(
          options.agent,
          store: JsonFileProfileStore(home.profilesFile),
        ),
        environment: environment,
        stdout: io.stdout,
      );
    case CliCommand.headless:
      return _runHeadless(options, environment, io);
    case CliCommand.repl when options.ui == UiMode.tui:
      // Полноэкранный режим рисует кадр в терминал и читает клавиши из
      // него: без TTY на обоих потоках работать нечему (design.md change
      // `add-cli-tui`, D4).
      if (!io.stdinIsTerminal || !io.stdoutIsTerminal) {
        throw const UsageError('--ui tui needs a terminal on stdin and stdout');
      }
      return _runTui(options, environment, io);
    case CliCommand.repl when !io.stdinIsTerminal && options.positional.isEmpty:
      // Ни `-p`, ни `-f`, а stdin — pipe: промпт из stdin, headless (H-01).
      return _runHeadless(options, environment, io);
    case CliCommand.repl:
      return _runRepl(options, environment, io);
  }
}

Future<int> _runRepl(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
) async {
  final cwd = await _sessionFolder(options.cwd);
  final home = CodelabHome.resolve(environment);
  final profile = await resolveAgentProfile(
    options.agent,
    store: JsonFileProfileStore(home.profilesFile),
  );
  await home.ensureExists();

  final terminal = IoTerminal();
  final runtime = buildCliRuntime(
    environment: environment,
    stderr: io.stderr,
    verbose: options.verbose,
  );
  final repl = Repl(
    workspace: runtime.workspace,
    terminal: terminal,
    profile: profile,
    cwd: cwd,
    history: HistoryFile(home.historyFile),
    surface: selectOutputSurface(
      stdoutIsTerminal: stdout.hasTerminal,
      environment: environment,
      noColor: options.noColor,
    ),
    unicode: supportsUnicode(environment),
    firstMessage: options.positional.isEmpty
        ? null
        : options.positional.join(' '),
    resume: options.resume,
    continueLast: options.continueLast,
    model: options.model,
    mode: options.configMode,
    // `/profile <id>` — те же формы, что у `--agent`, и профили
    // `profiles.json` (spec codelab-cli «Профили подключения CLI»).
    resolveProfile: (id) =>
        resolveAgentProfile(id, store: JsonFileProfileStore(home.profilesFile)),
  );
  // SIGTERM — безопасное завершение с кодом 143; SIGINT вне raw-режима —
  // как Ctrl+C, поэтому не через `watchStopSignals`, где второй сигнал
  // выходит сразу (spec codelab-cli «Сигналы CLI»; design.md, D13).
  final signals = watchStopSignals(
    (code) => unawaited(repl.interrupt(code)),
    sigint: const Stream.empty(),
  );
  final sigint = ProcessSignal.sigint.watch().listen((_) => repl.onSigint());
  try {
    return await repl.run();
  } finally {
    // Терминал восстанавливается и при исключении, которое REPL не поймал.
    terminal.restore();
    await sigint.cancel();
    await signals.cancel();
    await runtime.dispose();
  }
}

Future<int> _runTui(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
) async {
  final cwd = await _sessionFolder(options.cwd);
  final home = CodelabHome.resolve(environment);
  final profile = await resolveAgentProfile(
    options.agent,
    store: JsonFileProfileStore(home.profilesFile),
  );
  await home.ensureExists();

  final runtime = buildCliRuntime(
    environment: environment,
    stderr: io.stderr,
    verbose: options.verbose,
  );
  final tui = TuiRunner(
    workspace: runtime.workspace,
    profile: profile,
    cwd: cwd,
    history: HistoryFile(home.historyFile),
    firstMessage: options.positional.isEmpty
        ? null
        : options.positional.join(' '),
    resume: options.resume,
    continueLast: options.continueLast,
    model: options.model,
    mode: options.configMode,
    resolveProfile: (id) =>
        resolveAgentProfile(id, store: JsonFileProfileStore(home.profilesFile)),
    unicode: supportsUnicode(environment),
    color:
        selectOutputSurface(
          stdoutIsTerminal: true,
          environment: environment,
          noColor: options.noColor,
        ) ==
        OutputSurface.ansi,
    output: stdout,
    errorOutput: io.stderr,
  );
  // Сигналы — наши, а не обработчик dart_tui: SIGTERM даёт код 143, ход
  // отменяется (spec codelab-tui «Восстановление терминала после TUI»;
  // design.md change `add-cli-tui`, D7).
  final signals = watchStopSignals((code) => unawaited(tui.interrupt(code)));
  try {
    return await tui.run();
  } finally {
    await signals.cancel();
    await runtime.dispose();
  }
}

Future<int> _runHeadless(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
) async {
  final prompt = await readPrompt(options, io);
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
  final runner = HeadlessRunner(
    workspace: runtime.workspace,
    stdout: io.stdout,
    stderr: io.stderr,
    verbose: options.verbose,
    approve: options.approve,
    timeout: options.timeout,
  );
  // Сигнал отменяет ход; закрытие транспорта и процесса агента — в
  // `finally` ниже (design.md, D13).
  final signals = watchStopSignals((code) => unawaited(runner.interrupt(code)));
  try {
    final outcome = await runner.run(
      profile: profile,
      cwd: cwd,
      prompt: prompt,
      resume: options.resume,
      continueLast: options.continueLast,
      model: options.model,
      mode: options.configMode,
    );
    return exitCodeOf(outcome);
  } finally {
    await signals.cancel();
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
