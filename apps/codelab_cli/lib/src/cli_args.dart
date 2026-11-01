import 'package:args/args.dart';

/// Версия клиента; печатается `codelab --version`.
const cliVersion = '0.1.0';

/// Ошибка использования: неверные флаги, аргументы, профиль или промпт.
///
/// Почему отдельный тип: такой запуск не стартует агента и завершается кодом
/// `64` с текстом в stderr и пустым stdout (`09-11-stage-6-cli-mvp.md`,
/// коды выхода), а не трассой исключения.
final class UsageError implements Exception {
  const UsageError(this.message, {this.showSecretUsage = false});

  final String message;

  /// Нужна ли после сообщения справка `codelab secret` (spec codelab-cli
  /// «Подкоманда codelab secret»). Признак, а не текст справки: ошибки
  /// разбора `secret` не должны цитировать присланные слова (среди них может
  /// быть значение секрета), а справку печатает `runCodelab` (design.md change
  /// `add-agent-secret-store`, D8).
  final bool showSecretUsage;

  @override
  String toString() => 'UsageError: $message';
}

/// Что запускает `codelab`.
enum CliCommand {
  repl,
  headless,
  profiles,
  testScenario,
  config,
  secret,
  version,
  help,
}

/// Интерактивный режим `--ui`: построчный REPL или полноэкранный TUI.
///
/// Почему: TUI встаёт рядом с REPL, а не вместо него — REPL остаётся
/// режимом по умолчанию и запасным путём (spec codelab-cli «Команда codelab
/// и разбор флагов»; design.md change `add-cli-tui`, D1, D4).
enum UiMode {
  line('line'),
  tui('tui');

  const UiMode(this.flag);

  final String flag;
}

/// Политика одобрений headless (`--approve`, spec cli-headless «Политика
/// одобрений headless»).
enum ApprovePolicy {
  reject('reject'),
  readOnly('read-only'),
  allowAll('allow-all');

  const ApprovePolicy(this.flag);

  /// Значение флага.
  final String flag;
}

/// Разобранные аргументы `codelab`.
///
/// Почему: флаги — весь вход CLI MVP (файла `cli.yaml` до конца MVP нет,
/// design.md change `add-codelab-cli`, D1), и у них одно разобранное
/// представление для REPL, headless и подкоманд.
///
/// Для чего: вход `runCodelab` — выбор режима, профиля и сессии.
///
/// Как использовать: `parseCliArgs(args)`; ошибка — [UsageError].
/// [positional] — первое сообщение REPL или аргументы подкоманды.
final class CliOptions {
  const CliOptions._({
    required this.command,
    required this.positional,
    required this.agent,
    required this.cwd,
    required this.model,
    required this.configMode,
    required this.resume,
    required this.continueLast,
    required this.prompt,
    required this.promptFile,
    required this.approve,
    required this.timeout,
    required this.noColor,
    required this.verbose,
    required this.ui,
    this.filter,
  });

  final CliCommand command;
  final List<String> positional;

  /// Значение `--agent`: id профиля, `stdio:…`, URL или `embedded`; `null` —
  /// профиль `default`.
  final String? agent;

  /// Рабочая папка сессии; `null` — текущая.
  final String? cwd;

  /// Значение опции конфигурации `model`.
  final String? model;

  /// Значение опции конфигурации `mode` (флаг `--mode`).
  final String? configMode;

  /// Id сессии `--resume`.
  final String? resume;

  /// `--continue`: последняя сессия папки.
  final bool continueLast;

  /// Текст `-p`.
  final String? prompt;

  /// Путь `-f`; `-` — stdin.
  final String? promptFile;

  final ApprovePolicy approve;

  /// Предел на ход headless; `null` — без предела.
  final Duration? timeout;

  final bool noColor;
  final bool verbose;

  /// `--ui`: интерактивный режим; на headless не влияет.
  final UiMode ui;

  /// `test-scenario --filter`: glob по id фикстуры; `null` — все.
  final String? filter;
}

/// Подкоманды, которые регистрируются позже (этапы 7–9 и после MVP): до
/// своего change они дают `Unknown command`, а не уходят агенту первым
/// сообщением (`09-11-stage-6-cli-mvp.md`, «Спецификация CLI»).
const _laterCommands = {
  'provider',
  'mcp',
  'sessions',
  'update',
  'login',
  'logout',
  'trajectory',
};

final _durationPart = RegExp(r'(\d+)(h|m|s)');

ArgParser _parser() {
  final parser = ArgParser()
    ..addOption(
      'agent',
      abbr: 'a',
      valueHelp: 'profile',
      help:
          'Agent profile id, "stdio:<command> [args]", ws:// or wss:// URL '
          '(default: profile "default").',
    )
    ..addOption('cwd', abbr: 'C', valueHelp: 'dir', help: 'Session folder.')
    ..addOption('model', abbr: 'm', valueHelp: 'id', help: 'Model option.')
    ..addOption('mode', valueHelp: 'id', help: 'Mode option.')
    ..addOption(
      'resume',
      abbr: 'r',
      valueHelp: 'sessionId',
      help: 'Load a session instead of a new one.',
    )
    ..addFlag(
      'continue',
      abbr: 'c',
      negatable: false,
      help: 'Load the latest session of the folder.',
    )
    ..addOption(
      'print',
      abbr: 'p',
      valueHelp: 'prompt',
      help: 'Headless: run one prompt and print the answer.',
    )
    ..addOption(
      'prompt-file',
      abbr: 'f',
      valueHelp: 'file',
      help: 'Headless: prompt from a file, "-" for stdin.',
    )
    ..addOption(
      'approve',
      valueHelp: 'policy',
      allowed: [for (final policy in ApprovePolicy.values) policy.flag],
      defaultsTo: ApprovePolicy.reject.flag,
      help: 'Headless approval policy.',
    )
    ..addOption(
      'timeout',
      valueHelp: 'duration',
      help: 'Headless: limit per turn, e.g. 90s or 10m.',
    )
    ..addOption(
      'ui',
      valueHelp: 'mode',
      allowed: [for (final mode in UiMode.values) mode.flag],
      defaultsTo: UiMode.line.flag,
      help: 'Interactive mode: line-by-line REPL or full-screen TUI.',
    )
    ..addFlag('no-color', negatable: false, help: 'No ANSI colors.')
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Connection diagnostics in stderr.',
    )
    ..addFlag('version', negatable: false, help: 'Print the version.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help.');
  // Аргументы подкоманды разбирает она сама: у `profiles add` значение
  // профиля вроде `stdio:… --stdio` не должно попасть в флаги `codelab`.
  parser
    ..addCommand('profiles', ArgParser(allowTrailingOptions: false))
    // Зарегистрирована только `check`: `set`, `migrate` и прочие остаются
    // «Unknown command» (spec codelab-cli «Подкоманда codelab config»).
    ..addCommand(
      'config',
      ArgParser()..addCommand(
        'check',
        ArgParser()..addOption(
          'cwd',
          valueHelp: 'dir',
          help: 'Project directory to load config for (default: current).',
        ),
      ),
    )
    // Три подкоманды без флагов: значение секрета читается только из stdin,
    // флага `--value` нет (argv виден через `ps`; design.md change
    // `add-agent-secret-store`, D8).
    ..addCommand(
      'secret',
      ArgParser()
        ..addCommand('set', ArgParser())
        ..addCommand('delete', ArgParser())
        ..addCommand('list', ArgParser()),
    )
    ..addCommand(
      'test-scenario',
      ArgParser()
        ..addOption('agent', abbr: 'a', valueHelp: 'profile')
        ..addOption('filter', valueHelp: 'glob', help: 'Fixture ids to play.')
        ..addOption(
          'timeout',
          valueHelp: 'duration',
          help: 'Wait for an agent frame (default 30s).',
        ),
    );
  return parser;
}

/// Справка `codelab --help`.
String cliUsage() => '''
Usage:
  codelab [options] [first message]   interactive REPL
  codelab -p "<prompt>" [options]     headless: one turn, answer in stdout
  codelab profiles list|show <id>|add <id> <agent>|remove <id>
  codelab config check [--cwd <dir>]
  codelab secret set|delete|list      manage secrets (value on stdin)
  codelab test-scenario <file-or-dir>... --agent <profile> [--filter <glob>] [--timeout <d>]

Options:
${_parser().usage}''';

/// Разбирает аргументы `codelab`.
///
/// Как использовать: вызывается `runCodelab` один раз; ошибка —
/// [UsageError] с текстом для stderr.
CliOptions parseCliArgs(List<String> args) {
  final ArgResults results;
  try {
    results = _parser().parse(args);
  } on ArgParserException catch (error) {
    // `secret` где угодно в argv (и внутри подкоманды, и в верхнем уровне:
    // `--approve=<v> secret set x`): текст `package:args` цитирует присланное
    // слово, а это могло быть значение секрета (D8) — печатается только
    // фиксированная фраза.
    if (args.contains('secret')) {
      throw const UsageError(
        'invalid arguments for secret',
        showSecretUsage: true,
      );
    }
    throw UsageError(_usageMessage(error));
  }

  if (results.flag('help')) {
    return _options(CliCommand.help, results);
  }
  if (results.flag('version')) {
    return _options(CliCommand.version, results);
  }
  if (results.command case final command?
      when command.name == 'test-scenario') {
    return _options(
      CliCommand.testScenario,
      results,
      positional: command.rest,
      agent: command.option('agent'),
      filter: command.option('filter'),
      // Ожидание кадра агента; по умолчанию 30 с (spec cli-scenario-driver).
      timeout: _parseDuration(
        command.option('timeout') ?? results.option('timeout') ?? '30s',
      ),
    );
  }
  if (results.command case final command? when command.name == 'config') {
    return _configOptions(results, command, hasSecret: args.contains('secret'));
  }
  if (results.command case final command? when command.name == 'secret') {
    return _secretOptions(results, command);
  }
  if (results.command case final command?) {
    return _options(CliCommand.profiles, results, positional: command.rest);
  }

  final positional = results.rest;
  if (positional.isNotEmpty && _laterCommands.contains(positional.first)) {
    throw UsageError('Unknown command ${positional.first}');
  }
  final prompt = results.option('print');
  final promptFile = results.option('prompt-file');
  if (prompt != null && promptFile != null) {
    throw const UsageError('Pass either --print or --prompt-file, not both.');
  }
  final headless = prompt != null || promptFile != null;
  if (headless && positional.isNotEmpty) {
    // Слова не цитируются: среди них мог быть секрет (D8).
    throw const UsageError(
      'Unexpected arguments with --print or --prompt-file',
    );
  }
  if (results.option('resume') != null && results.flag('continue')) {
    throw const UsageError('Pass either --resume or --continue, not both.');
  }
  // Полноэкранный режим — только интерактивный: у headless свой вывод
  // (design.md change `add-cli-tui`, D4).
  if (headless && results.option('ui') == UiMode.tui.flag) {
    throw const UsageError('--ui applies only to the interactive mode');
  }
  return _options(
    headless ? CliCommand.headless : CliCommand.repl,
    results,
    positional: positional,
  );
}

/// Флаги подключения и запроса, несовместимые с `codelab config check`.
const _connectionFlags = [
  'agent',
  'model',
  'mode',
  'resume',
  'continue',
  'print',
  'prompt-file',
  'approve',
  'timeout',
  'ui',
];

/// `codelab config …`: только `check [--cwd]`.
///
/// Почему здесь, а не в `run.dart`: незарегистрированная подкоманда
/// (`set`, `migrate`) — ошибка использования с кодом `64` до любого
/// ввода-вывода (spec codelab-cli «Подкоманда codelab config»).
///
/// Приоритет папки (design.md change `add-agent-configuration`, D14):
/// `--cwd` подкоманды сильнее общего `-C/--cwd`; общий флаг задаёт папку,
/// только если подкоманда её не задала.
///
/// Флаги подключения и запроса (`--agent`, `-p`, `--model`, …) вместе с
/// `config` — ошибка `64`: профиль подключения `config check` не учитывает
/// (D14), и молчаливое игнорирование скрыло бы опечатку в команде.
CliOptions _configOptions(
  ArgResults results,
  ArgResults config, {
  bool hasSecret = false,
}) {
  for (final flag in _connectionFlags) {
    if (results.wasParsed(flag)) {
      throw UsageError('--$flag does not apply to config check');
    }
  }
  final check = config.command;
  if (check == null) {
    throw UsageError(
      config.rest.isEmpty
          ? 'config needs a subcommand: codelab config check [--cwd <dir>]'
          // Spec codelab-cli требует `Unknown command config <слово>`; слово
          // не цитируется только если `secret` есть в argv (D8): там мог
          // оказаться секрет.
          : hasSecret
          ? 'Unknown command config; only config check exists'
          : 'Unknown command config ${config.rest.first}',
    );
  }
  if (check.rest.isNotEmpty) {
    // Хвост не цитируется по той же причине (D8): в нём мог оказаться секрет.
    throw const UsageError('Unexpected arguments for config check');
  }
  return _options(CliCommand.config, results, cwd: check.option('cwd'));
}

/// Справка `codelab secret` (в stderr при коде `64`).
///
/// Своя у каждого бинаря, потому что называет его (`codelab-agent` печатает
/// свою); общие тексты результатов даёт `SecretCommands` (D8).
String secretUsage() =>
    'Usage: codelab secret set|delete|list\n\n'
    '  codelab secret set <name>     '
    'read the value from stdin (hidden on a terminal)\n'
    '  codelab secret delete <name>\n'
    '  codelab secret list\n\n'
    'Works on the backend chosen by secrets.backend in '
    r'$CODELAB_HOME/config.yaml or in the file named by CODELAB_CONFIG. '
    'The value is never passed as an argument and never printed.';

/// `codelab secret set|delete|list`: [CliOptions.positional] — имя
/// подкоманды и её аргументы.
///
/// Почему проверки здесь: ошибка использования — код `64` до любого
/// ввода-вывода (spec codelab-cli «Подкоманда codelab secret»). Флаги
/// подключения вместе с `secret` — тоже `64`: хранилищу профиль не нужен, и
/// молчаливое игнорирование скрыло бы опечатку. Сообщения не цитируют
/// присланные слова: лишний аргумент `set` — вероятно, значение секрета, он
/// уходит дальше только признаком `hasValueArgument` (D8).
CliOptions _secretOptions(ArgResults results, ArgResults secret) {
  UsageError usage(String message) =>
      UsageError(message, showSecretUsage: true);
  // `-C/--cwd` тоже лишний: рабочая папка сессии хранилищу не нужна.
  for (final flag in [..._connectionFlags, 'cwd']) {
    if (results.wasParsed(flag)) {
      throw usage('--$flag does not apply to secret');
    }
  }
  final sub = secret.command;
  if (sub == null) {
    throw usage('secret needs a subcommand: set, delete or list');
  }
  switch (sub.name) {
    case 'set' when sub.rest.isEmpty:
      throw usage('secret set needs the secret name');
    case 'delete' when sub.rest.length != 1:
      throw usage('secret delete needs exactly one name');
    case 'list' when sub.rest.isNotEmpty:
      throw usage('secret list takes no arguments');
  }
  return _options(
    CliCommand.secret,
    results,
    positional: [sub.name!, ...sub.rest],
  );
}

CliOptions _options(
  CliCommand command,
  ArgResults results, {
  List<String> positional = const [],
  String? cwd,
  String? agent,
  String? filter,
  Duration? timeout,
}) => CliOptions._(
  command: command,
  positional: List.unmodifiable(positional),
  agent: agent ?? results.option('agent'),
  filter: filter,
  cwd: cwd ?? results.option('cwd'),
  model: results.option('model'),
  configMode: results.option('mode'),
  resume: results.option('resume'),
  continueLast: results.flag('continue'),
  prompt: results.option('print'),
  promptFile: results.option('prompt-file'),
  approve: ApprovePolicy.values.firstWhere(
    (policy) => policy.flag == results.option('approve'),
  ),
  timeout:
      timeout ??
      switch (results.option('timeout')) {
        null => null,
        final value => _parseDuration(value),
      },
  noColor: results.flag('no-color'),
  verbose: results.flag('verbose'),
  ui: UiMode.values.firstWhere((mode) => mode.flag == results.option('ui')),
);

/// `90s`, `10m`, `1h30m`; ноль и единицы без суффикса — ошибка.
Duration _parseDuration(String value) {
  final matches = _durationPart.allMatches(value).toList();
  if (matches.isEmpty || matches.map((m) => m[0]).join() != value) {
    throw UsageError('Invalid duration "$value": use e.g. 90s, 10m, 1h30m.');
  }
  var duration = Duration.zero;
  for (final match in matches) {
    final amount = int.parse(match[1]!);
    duration += switch (match[2]) {
      'h' => Duration(hours: amount),
      'm' => Duration(minutes: amount),
      _ => Duration(seconds: amount),
    };
  }
  if (duration == Duration.zero) {
    throw UsageError('Invalid duration "$value": must be positive.');
  }
  return duration;
}

/// Незарегистрированный флаг — `Unknown flag <имя>`, как требует §9.11 для
/// флагов более позднего этапа; остальные ошибки `package:args` — как есть.
String _usageMessage(ArgParserException error) {
  if (error.message.startsWith('Could not find')) {
    final name = RegExp(r'"(-[^"]*)"').firstMatch(error.message)?[1];
    return 'Unknown flag ${name ?? error.argumentName ?? ''}'.trimRight();
  }
  return error.message;
}
