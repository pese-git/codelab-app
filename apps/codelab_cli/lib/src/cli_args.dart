import 'package:args/args.dart';

/// Версия клиента; печатается `codelab --version`.
const cliVersion = '0.1.0';

/// Ошибка использования: неверные флаги, аргументы, профиль или промпт.
///
/// Почему отдельный тип: такой запуск не стартует агента и завершается кодом
/// `64` с текстом в stderr и пустым stdout (`09-11-stage-6-cli-mvp.md`,
/// коды выхода), а не трассой исключения.
final class UsageError implements Exception {
  const UsageError(this.message);

  final String message;

  @override
  String toString() => 'UsageError: $message';
}

/// Что запускает `codelab`.
enum CliCommand { repl, headless, profiles, testScenario, version, help }

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
  'config',
  'provider',
  'mcp',
  'secret',
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
    throw UsageError(
      'Unexpected arguments with --print or --prompt-file: '
      '${positional.join(' ')}',
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

CliOptions _options(
  CliCommand command,
  ArgResults results, {
  List<String> positional = const [],
  String? agent,
  String? filter,
  Duration? timeout,
}) => CliOptions._(
  command: command,
  positional: List.unmodifiable(positional),
  agent: agent ?? results.option('agent'),
  filter: filter,
  cwd: results.option('cwd'),
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
