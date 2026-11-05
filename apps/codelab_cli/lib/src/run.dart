import 'dart:async';
import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart'
    show
        Deleted,
        Exists,
        Failed,
        NotSet,
        ProfileSecretBackend,
        ProfileSecretDelete,
        ProfileSecretWrite,
        ConnectionProfile,
        ProfileSecretSource,
        ProfileSecrets,
        ReadOnly,
        SecretText,
        Stored;
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgentConfigException, EmbeddedAgentOpener;
import 'package:codelab_setup/io.dart';
import 'package:path/path.dart' as p;

import 'cli_args.dart';
import 'cli_io.dart';
import 'cli_logger.dart';
import 'composition_root.dart';
import 'embedded_logger.dart';
import 'exit_codes.dart';
import 'headless/headless_runner.dart';
import 'headless/outcome.dart';
import 'headless/prompt_source.dart';
import 'home.dart';
import 'input/io_terminal.dart';
import 'profiles/profile_arg.dart';
import 'profiles/profiles_command.dart';
import 'render/output_surface.dart';
import 'render/sanitize.dart';
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
///
/// [embeddedOpener] — шов тестовой точки входа (design.md change
/// `add-embedded-agent-mode`, D8): по умолчанию встроенного агента открывает
/// `localEmbeddedAgentOpener`, тест подставляет открыватель со сценарием
/// модели. Невалидный конфиг встроенного агента — текст исключения в stderr и
/// [usageExit] (spec codelab-cli «Невалидный конфиг встроенного агента»).
Future<int> runCodelab(
  List<String> args, {
  required Map<String, String> environment,
  CliIo io = const ProcessCliIo(),
  EmbeddedAgentOpener? embeddedOpener,
  SignalSeam signals = const SignalSeam(),
}) async {
  try {
    return await _run(args, environment, io, embeddedOpener, signals);
  } on EmbeddedAgentConfigException catch (error) {
    // Текст собирает мост из файлов конфигурации: управляющие символы
    // терминала в stderr не пропускаются.
    io.stderr.writeln(sanitizeTerminalText('codelab: ${error.message}'));
    return usageExit;
  } on UsageError catch (error) {
    io.stderr.writeln('codelab: ${error.message}');
    if (error.showSecretUsage) {
      io.stderr
        ..writeln()
        ..writeln(secretUsage());
    }
    if (error.usage case final usage?) {
      io.stderr
        ..writeln()
        ..writeln(usage);
    }
    return usageExit;
  } finally {
    await io.flush();
  }
}

Future<int> _run(
  List<String> args,
  Map<String, String> environment,
  CliIo io,
  EmbeddedAgentOpener? embeddedOpener,
  SignalSeam signalSeam,
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
        openSecrets: () => _openProfileSecrets(environment, io, false),
      );
    case CliCommand.testScenario:
      final home = CodelabHome.resolve(environment);
      return runTestScenario(
        options,
        profile: await resolveAgentProfile(
          options.agent,
          store: JsonFileProfileStore(home.profilesFile),
          onWarning: io.stderr.writeln,
        ),
        environment: environment,
        stdout: io.stdout,
        stderr: io.stderr,
        profileSecrets: await _openProfileSecrets(environment, io, false),
      );
    case CliCommand.config:
      return options.subcommand!.name == 'check'
          ? _runConfigCheck(options, environment, io)
          : _runConfigEdit(options, environment, io);
    case CliCommand.provider:
      return _runProvider(options, environment, io);
    case CliCommand.mcp:
      return _runMcp(options, environment, io);
    case CliCommand.secret:
      return _runSecret(options, environment, io);
    case CliCommand.headless:
      return _runHeadless(options, environment, io, embeddedOpener, signalSeam);
    case CliCommand.repl when options.ui == UiMode.tui:
      // Полноэкранный режим рисует кадр в терминал и читает клавиши из
      // него: без TTY на обоих потоках работать нечему (design.md change
      // `add-cli-tui`, D4).
      if (!io.stdinIsTerminal || !io.stdoutIsTerminal) {
        throw const UsageError('--ui tui needs a terminal on stdin and stdout');
      }
      return _runTui(options, environment, io, embeddedOpener, signalSeam);
    case CliCommand.repl when !io.stdinIsTerminal && options.positional.isEmpty:
      // Ни `-p`, ни `-f`, а stdin — pipe: промпт из stdin, headless (H-01).
      return _runHeadless(options, environment, io, embeddedOpener, signalSeam);
    case CliCommand.repl:
      return _runRepl(options, environment, io, embeddedOpener, signalSeam);
  }
}

/// `codelab config check`: загрузка конфигурации агента без запуска агента.
///
/// Почему через мост: клиент не импортирует `package:codelab_agent_*`, а вывод
/// и коды обязаны совпасть с `codelab-agent config check` — реализация одна,
/// `ConfigCommands` (design.md change `add-agent-configuration`, D13, D14).
/// Ни `ClientWorkspace`, ни транспорт не создаются, поэтому процесс агента не
/// стартует. Несуществующая папка `--cwd` даёт `64` внутри моста.
Future<int> _runConfigCheck(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
) async {
  try {
    final result = await ConfigCommands().check(
      CheckOptions(
        // Путь как есть, без normalize: `link/../proj` ОС разрешает через
        // symlink, а текст ошибки совпадает с `codelab-agent` (D14).
        cwd: options.cwd ?? Directory.current.path,
        environment: environment,
      ),
    );
    result.stdout.forEach(io.stdout.writeln);
    result.stderr.forEach(io.stderr.writeln);
    return result.exitCode;
  } on Object catch (error) {
    // Как у `codelab-agent config`: неожиданное исключение — одна строка и
    // код `1`, а не трасса Dart и код `255`.
    io.stderr.writeln('codelab: config failed: $error');
    return failureExit;
  }
}

/// Папка проекта подкоманд записи: `--cwd` подкоманды, общий `-C`, текущая.
///
/// Путь как есть, без normalize, как у `config check`: загрузчик и писатель
/// канонизируют его сами, а текст ошибки совпадает с `codelab-agent` (D14).
String _projectDir(CliOptions options) => options.cwd ?? Directory.current.path;

/// Печатает результат общей подкоманды и возвращает её код выхода.
int _printResult(ConfigCommandResult result, CliIo io) {
  result.stdout.forEach(io.stdout.writeln);
  result.stderr.forEach(io.stderr.writeln);
  return result.exitCode;
}

/// `codelab config path|get|set|unset`: чтение и правка файлов конфига без
/// агента.
///
/// Почему через мост: вывод, коды и байты файла обязаны совпасть с
/// `codelab-agent config …` — реализация одна, `ConfigCommands` (design.md
/// change `add-config-writer-and-reload`, D6). Транспорт и `ClientWorkspace`
/// не создаются; `CodelabHome.ensureExists` не вызывается, поэтому
/// `sessions/`, `profiles.json` и `cli_history` не появляются. Неожиданное
/// исключение — строка и код `1`, а не трасса и `255`, как у `config check`.
Future<int> _runConfigEdit(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
) async {
  final sub = options.subcommand!;
  final commands = ConfigCommands();
  final cwd = _projectDir(options);
  try {
    return _printResult(switch (sub.name) {
      'path' => await commands.path(
        ConfigPathOptions(
          cwd: cwd,
          environment: environment,
          // Без флагов — все слои; флаг выбирает один; оба сразу — код 64
          // от общего кода (D6).
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
      ),
      'get' => await commands.get(
        ConfigGetOptions(
          key: sub.rest.single,
          cwd: cwd,
          environment: environment,
          // Без `--layer` — merged: итог всех слоёв (решение D6).
          layer: ConfigGetLayer.parse(sub.option('layer')),
        ),
      ),
      'set' => await commands.set(
        ConfigSetOptions(
          key: sub.rest[0],
          value: sub.rest[1],
          cwd: cwd,
          environment: environment,
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
      ),
      _ => await commands.unset(
        ConfigUnsetOptions(
          key: sub.rest.single,
          cwd: cwd,
          environment: environment,
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
      ),
    }, io);
  } on Object catch (error) {
    // Текст исключения мог бы процитировать значение: только тип (CFG-10).
    io.stderr.writeln('codelab: config failed: ${error.runtimeType}');
    return failureExit;
  }
}

/// `codelab provider add|list|remove`: провайдеры в файлах конфига без агента.
///
/// Почему через мост: как у `config`, вывод и байты общие с
/// `codelab-agent provider` (`ProviderCommands`, D6). Ключ читается только
/// скрытым вводом `StdinSecretInput` с `--api-key-stdin` и нигде не
/// печатается; в stderr при сбое — только тип исключения (CFG-10).
Future<int> _runProvider(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
) async {
  final sub = options.subcommand!;
  final commands = ProviderCommands();
  final cwd = _projectDir(options);
  try {
    return _printResult(switch (sub.name) {
      'list' => await commands.list(
        ProviderListOptions(cwd: cwd, environment: environment),
      ),
      'remove' => await commands.remove(
        ProviderRemoveOptions(
          id: sub.rest.single,
          cwd: cwd,
          environment: environment,
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
      ),
      _ => await commands.add(
        ProviderAddOptions(
          id: sub.rest.single,
          cwd: cwd,
          environment: environment,
          kind: sub.option('kind'),
          baseUrl: sub.option('base-url'),
          model: sub.option('model'),
          contextWindow: sub.option('context-window'),
          apiKeySecret: sub.option('api-key-secret'),
          apiKeyEnv: sub.option('api-key-env'),
          apiKeyStdin: sub.flag('api-key-stdin'),
          makeDefault: sub.flag('default'),
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
        StdinSecretInput(),
      ),
    }, io);
  } on Object catch (error) {
    io.stderr.writeln('codelab: provider failed: ${error.runtimeType}');
    return failureExit;
  }
}

/// `codelab mcp add|list|remove`: MCP-серверы в файлах конфига без агента.
///
/// Через `McpServerCommands` (D6); к серверам не подключается. Значения
/// `--env` и `--header` не печатаются.
Future<int> _runMcp(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
) async {
  final sub = options.subcommand!;
  final commands = McpServerCommands();
  final cwd = _projectDir(options);
  try {
    return _printResult(switch (sub.name) {
      'list' => await commands.list(
        McpListOptions(cwd: cwd, environment: environment),
      ),
      'remove' => await commands.remove(
        McpRemoveOptions(
          name: sub.rest.single,
          cwd: cwd,
          environment: environment,
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
      ),
      _ => await commands.add(
        McpAddOptions(
          name: sub.rest.single,
          cwd: cwd,
          environment: environment,
          type: sub.option('type'),
          command: sub.option('command'),
          args: sub.multiOption('arg'),
          env: sub.multiOption('env'),
          url: sub.option('url'),
          headers: sub.multiOption('header'),
          disabled: sub.flag('disabled'),
          project: sub.flag('project'),
          local: sub.flag('local'),
          // Значение читается из stdin только при одном из `-stdin` флагов
          // (change `add-config-literal-secrets-and-migrate`, D11).
          headerStdin: sub.multiOption('header-stdin'),
          headerScheme: sub.option('header-scheme'),
          envStdin: sub.multiOption('env-stdin'),
        ),
      ),
    }, io);
  } on Object catch (error) {
    io.stderr.writeln('codelab: mcp failed: ${error.runtimeType}');
    return failureExit;
  }
}

/// `codelab secret set|delete|list|migrate`: хранилище секретов без агента.
///
/// Почему через мост: клиент не импортирует `package:codelab_agent_*`, а вывод
/// и коды обязаны совпасть с `codelab-agent secret` — реализация одна,
/// `SecretCommands` (design.md change `add-agent-secret-store`, D8, D15).
/// Ни `ClientWorkspace`, ни транспорт не создаются; `ensureExists`,
/// профили и история здесь не вызываются, поэтому `sessions/`,
/// `profiles.json` и `cli_history` не появляются. В `CODELAB_HOME` пишет
/// `set` и `delete` с бэкендом `file` — в `secrets.yaml`; `list` и ошибки
/// использования его не меняют.
Future<int> _runSecret(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
) async {
  // Тильда и `~user` проверяются тем же правилом, что у остальных команд CLI
  // (`CodelabHome.resolve`, D17); ошибка — `64` до обращения к хранилищу.
  // Окружение дальше уходит как есть: раскрытие повторяет `codelabHomeOf`.
  CodelabHome.resolve(environment);
  final [name, ...rest] = options.positional;
  final commands = SecretCommands();
  try {
    final SecretCommandResult result;
    switch (name) {
      case 'set':
        result = await commands.set(
          SecretSetOptions(
            name: rest.first,
            environment: environment,
            // Лишний аргумент — вероятно, значение: дальше идёт только
            // признак, сам аргумент не передаётся и не печатается (D8).
            hasValueArgument: rest.length > 1,
          ),
          StdinSecretInput(),
        );
      case 'delete':
        result = await commands.delete(
          SecretDeleteOptions(name: rest.single, environment: environment),
        );
      case 'migrate':
        final migrate = options.subcommand!;
        result = await commands.migrate(
          SecretMigrateOptions(
            environment: environment,
            cwd: _projectDir(options),
            project: migrate.flag('project'),
            local: migrate.flag('local'),
            all: migrate.flag('all'),
            dryRun: migrate.flag('dry-run'),
            force: migrate.flag('force'),
          ),
        );
      default:
        result = await commands.list(
          SecretListOptions(environment: environment),
        );
    }
    result.stdout.forEach(io.stdout.writeln);
    result.stderr.forEach(io.stderr.writeln);
    if (result.showUsage) {
      io.stderr
        ..writeln()
        ..writeln(secretUsage());
    }
    return result.exitCode;
  } on Object catch (error) {
    // Только тип исключения: текст чужой реализации мог бы цитировать
    // значение секрета (CFG-10); код `1`, а не трасса Dart и код `255`.
    io.stderr.writeln('codelab: secret failed: ${error.runtimeType}');
    return failureExit;
  }
}

Future<int> _runRepl(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
  EmbeddedAgentOpener? embeddedOpener,
  SignalSeam signalSeam,
) async {
  final cwd = await _sessionFolder(options.cwd);
  final home = CodelabHome.resolve(environment);
  final profile = await resolveAgentProfile(
    options.agent,
    store: JsonFileProfileStore(home.profilesFile),
    onWarning: io.stderr.writeln,
  );
  await home.ensureExists();

  final terminal = IoTerminal();
  final profileSecrets = await _openProfileSecrets(
    environment,
    io,
    options.verbose,
  );
  await _warnIfTokenSecretMissing(
    profile,
    profileSecrets,
    environment,
    io,
    verbose: options.verbose,
  );
  final runtime = buildCliRuntime(
    environment: environment,
    stderr: io.stderr,
    verbose: options.verbose,
    debugSecrets: options.debugSecrets,
    embeddedOpener: embeddedOpener,
    profileSecrets: profileSecrets,
  );
  final repl = Repl(
    tokenSource: ProfileSecretSource(environment, stored: profileSecrets),
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
    resolveProfile: (id) => resolveAgentProfile(
      id,
      store: JsonFileProfileStore(home.profilesFile),
      // Без предупреждения о прежней записи `default`: оно показывается один
      // раз при старте (до TUI), а посреди сессии stderr писал бы поверх
      // экрана интерфейса; в REPL оно также только шумит между ходами (D21).
    ),
  );
  // SIGTERM — безопасное завершение с кодом 143; SIGINT вне raw-режима —
  // как Ctrl+C, а не остановка (spec codelab-cli «Сигналы CLI»; design.md,
  // D13). Обработчики живут до конца `dispose` встроенного агента: когда
  // режим закончен (`stopped`), любой сигнал выходит сразу (D6, «Выход CLI»).
  var stopped = false;
  final signals = watchModeSignals(
    onStop: (code) => unawaited(repl.interrupt(code)),
    isStopped: () => stopped,
    onSigint: repl.onSigint,
    seam: signalSeam,
  );
  try {
    return await repl.run();
  } finally {
    // Терминал восстанавливается и при исключении, которое REPL не поймал.
    terminal.restore();
    stopped = true;
    try {
      await runtime.dispose();
    } finally {
      await signals.cancel();
    }
  }
}

Future<int> _runTui(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
  EmbeddedAgentOpener? embeddedOpener,
  SignalSeam signalSeam,
) async {
  final cwd = await _sessionFolder(options.cwd);
  final home = CodelabHome.resolve(environment);
  final profile = await resolveAgentProfile(
    options.agent,
    store: JsonFileProfileStore(home.profilesFile),
    onWarning: io.stderr.writeln,
  );
  await home.ensureExists();

  final profileSecrets = await _openProfileSecrets(
    environment,
    io,
    options.verbose,
  );
  await _warnIfTokenSecretMissing(
    profile,
    profileSecrets,
    environment,
    io,
    verbose: options.verbose,
  );
  final runtime = buildCliRuntime(
    environment: environment,
    stderr: io.stderr,
    verbose: options.verbose,
    debugSecrets: options.debugSecrets,
    embeddedOpener: embeddedOpener,
    profileSecrets: profileSecrets,
  );
  final tui = TuiRunner(
    tokenSource: ProfileSecretSource(environment, stored: profileSecrets),
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
    resolveProfile: (id) => resolveAgentProfile(
      id,
      store: JsonFileProfileStore(home.profilesFile),
      // Без предупреждения о прежней записи `default`: оно показывается один
      // раз при старте (до TUI), а посреди сессии stderr писал бы поверх
      // экрана интерфейса; в REPL оно также только шумит между ходами (D21).
    ),
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
  var stopped = false;
  final signals = watchModeSignals(
    onStop: (code) => unawaited(tui.interrupt(code)),
    isStopped: () => stopped,
    seam: signalSeam,
  );
  try {
    return await tui.run();
  } finally {
    stopped = true;
    try {
      await runtime.dispose();
    } finally {
      await signals.cancel();
    }
  }
}

Future<int> _runHeadless(
  CliOptions options,
  Map<String, String> environment,
  CliIo io,
  EmbeddedAgentOpener? embeddedOpener,
  SignalSeam signalSeam,
) async {
  final prompt = await readPrompt(options, io);
  final cwd = await _sessionFolder(options.cwd);
  final home = CodelabHome.resolve(environment);
  final profile = await resolveAgentProfile(
    options.agent,
    store: JsonFileProfileStore(home.profilesFile),
    onWarning: io.stderr.writeln,
  );

  final profileSecrets = await _openProfileSecrets(
    environment,
    io,
    options.verbose,
  );
  await _warnIfTokenSecretMissing(
    profile,
    profileSecrets,
    environment,
    io,
    verbose: options.verbose,
  );
  final runtime = buildCliRuntime(
    environment: environment,
    stderr: io.stderr,
    verbose: options.verbose,
    debugSecrets: options.debugSecrets,
    embeddedOpener: embeddedOpener,
    profileSecrets: profileSecrets,
  );
  final runner = HeadlessRunner(
    tokenSource: ProfileSecretSource(environment, stored: profileSecrets),
    workspace: runtime.workspace,
    stdout: io.stdout,
    stderr: io.stderr,
    verbose: options.verbose,
    approve: options.approve,
    timeout: options.timeout,
  );
  // Сигнал отменяет ход; закрытие транспорта и процесса агента — в
  // `finally` ниже (design.md, D13).
  var stopped = false;
  final signals = watchModeSignals(
    onStop: (code) => unawaited(runner.interrupt(code)),
    isStopped: () => stopped,
    seam: signalSeam,
  );
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
    stopped = true;
    try {
      await runtime.dispose();
    } finally {
      await signals.cancel();
    }
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

/// Открывает хранилище секретов для токенов профилей `secret:<имя>`.
///
/// Почему здесь: IO-барель `codelab_setup/io.dart` разрешён только в
/// `run.dart` (правило сторожа, design.md change `add-agent-configuration`,
/// D14), а kit не знает стороны агента — порт `ProfileSecrets` собирается на
/// стыке (design.md change `add-provider-setup-ui`, D13).
///
/// Для чего: подключение по `secret:` читает токен из того же хранилища, что
/// codelab-app (`ClientSecretAccess`: переменная `CODELAB_SECRET_<…>`, затем
/// бэкенд `secrets.backend`). Лог хранилища идёт в stderr только с `--verbose`
/// и без значений.
Future<ProfileSecrets> _openProfileSecrets(
  Map<String, String> environment,
  CliIo io,
  bool verbose,
) => openCliProfileSecrets(
  environment: environment,
  logger: verbose
      ? CliEmbeddedLogger(io.stderr)
      : const CliEmbeddedLogger.silent(),
);

/// Собирает [ProfileSecrets] CLI поверх `ClientSecretAccess` для
/// `CODELAB_HOME` из [environment].
///
/// Почему публичная: адаптер живёт в `run.dart` (там разрешён IO-барель моста),
/// а его поведение — порядок проверок, `Exists`, типизированные сбои —
/// проверяется модульным тестом на временном `CODELAB_HOME`. Обычному коду
/// нужен только `runCodelab`.
Future<ProfileSecrets> openCliProfileSecrets({
  required Map<String, String> environment,
  required Logger logger,
}) async {
  final home = CodelabHome.resolve(environment).path;
  final access = await ClientSecretAccess.open(
    codelabHome: home,
    environment: environment,
    logger: logger,
  );
  return _ClientProfileSecrets(access, home);
}

/// Предупреждение D13 в stderr, если у профиля `secret:` без значения.
///
/// Почему до подключения и в stderr: подключение без токена — не ошибка, но
/// сервер ответит отказом, и причину надо назвать; режимы REPL, TUI и
/// headless пишут её тем же каналом, что остальные предупреждения старта
/// (`onWarning: io.stderr.writeln`), до открытия экрана TUI. Текст — только id
/// профиля (design.md change `add-provider-setup-ui`, D13).
Future<void> _warnIfTokenSecretMissing(
  ConnectionProfile profile,
  ProfileSecrets secrets,
  Map<String, String> environment,
  CliIo io, {
  required bool verbose,
}) async {
  if (await ProfileSecretSource(
    environment,
    stored: secrets,
  ).isSecretMissing(profile)) {
    io.stderr.writeln(secretMissingMessage(profile.id));
    if (verbose) {
      // Событие журнала `--verbose` (D18): только id профиля, как у app.
      CliLogger(io.stderr).warning(
        'connection_profile.token_secret_missing',
        context: {'profile_id': profile.id},
      );
    }
  }
}

/// [ProfileSecrets] kit поверх `ClientSecretAccess` моста настроек.
///
/// Почему адаптер: kit объявляет свой порт без зависимости от стороны агента
/// (D13), а `ClientSecretAccess` отдаёт результаты `SecretAdmin`; здесь они
/// переводятся в закрытые результаты порта. Значения в результаты не
/// попадают, тексты сбоев — без цитат ввода.
///
/// Как использовать: создаётся только `_openProfileSecrets`; `read` и
/// `isSet` идут без кэша, `store` не перезаписывает существующее имя
/// (`Exists`, SETUP-5).
final class _ClientProfileSecrets implements ProfileSecrets {
  _ClientProfileSecrets(this._access, this._home);

  final ClientSecretAccess _access;

  /// Папка `CODELAB_HOME` для подсказки бэкенда только для чтения.
  final String _home;

  @override
  ProfileSecretBackend get backend {
    final info = _access.backend;
    return ProfileSecretBackend(
      id: info.id,
      writable: info.writable,
      unavailableReason: info.unavailableReason,
    );
  }

  @override
  Future<List<String>> names() async => switch (await _access.admin.list()) {
    SecretListing(:final names) => names,
    SecretListFailed(:final reason) => throw SecretStoreUnavailableException(
      backend: _access.backend.id,
      reason: reason,
    ),
  };

  @override
  Future<bool> isSet(String name) => _access.isSet(name);

  @override
  Future<String?> read(String name) => _access.read(name);

  /// Порядок как у адаптера app: проверки без значения (`checkStore`: имя и
  /// бэкенд только для чтения) раньше `isSet` (с учётом переменной
  /// `CODELAB_SECRET_<…>`), и только затем запись. `SecretUpdated` — секрет
  /// появился между проверкой и записью, то есть создан не нами: это
  /// `Exists`, и откат его не трогает.
  @override
  Future<ProfileSecretWrite> store(String name, SecretText value) async {
    try {
      if (await _access.admin.checkStore(name) case final early?) {
        return _writeResult(early);
      }
      if (await _access.isSet(name)) {
        return const Exists();
      }
      return _writeResult(await _access.admin.store(name, value.reveal()));
    } on Object catch (error) {
      return Failed(_failureText(error));
    }
  }

  @override
  Future<ProfileSecretDelete> delete(String name) async {
    try {
      return switch (await _access.admin.delete(name)) {
        SecretDeleted() => const Deleted(),
        SecretNotSet() => const NotSet(),
        final SecretReadOnly readOnly => _readOnly(readOnly),
        SecretFailed(:final reason) => Failed(reason),
        SecretInvalidName() => const Failed('Invalid secret name.'),
      };
    } on Object catch (error) {
      return Failed(_failureText(error));
    }
  }

  ProfileSecretWrite _writeResult(SecretWriteOutcome outcome) =>
      profileSecretWriteOf(outcome, home: _home);

  ReadOnly _readOnly(SecretReadOnly readOnly) =>
      ReadOnly(secretReadOnlyHint(readOnly, _home));

  // Текст чужого исключения мог бы процитировать значение: только тип.
  static String _failureText(Object error) =>
      'secret store failed: ${error.runtimeType}';
}

/// Переводит исход `SecretAdmin.store` в результат порта [ProfileSecrets].
///
/// Почему отдельная функция: перевод проверяется модульным тестом без
/// хранилища. `SecretUpdated` — имя появилось между проверкой и записью, то
/// есть секрет создан не нами: это [Exists], и откат записи профиля его не
/// удаляет. Подсказка бэкенда только для чтения — строчная, без точки, как
/// текст `codelab secret` (design.md change `add-provider-setup-ui`, D3).
ProfileSecretWrite profileSecretWriteOf(
  SecretWriteOutcome outcome, {
  required String home,
}) => switch (outcome) {
  SecretStored() => const Stored(),
  SecretUpdated() => const Exists(),
  final SecretReadOnly readOnly => ReadOnly(secretReadOnlyHint(readOnly, home)),
  SecretFailed(:final reason) => Failed(reason),
  SecretInvalidName() => const Failed('Invalid secret name.'),
  SecretInvalidValue(:final reason) => Failed('Invalid token: $reason.'),
  SecretCollision(:final variable) => Failed(
    'Another stored secret uses the same environment variable $variable.',
  ),
};
