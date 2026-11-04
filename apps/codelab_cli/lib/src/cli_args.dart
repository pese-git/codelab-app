import 'package:args/args.dart';
import 'package:codelab_setup/codelab_setup.dart' show before1Note;

/// Версия клиента; печатается `codelab --version`.
const cliVersion = '0.1.0';

/// Ошибка использования: неверные флаги, аргументы, профиль или промпт.
///
/// Почему отдельный тип: такой запуск не стартует агента и завершается кодом
/// `64` с текстом в stderr и пустым stdout (`09-11-stage-6-cli-mvp.md`,
/// коды выхода), а не трассой исключения.
final class UsageError implements Exception {
  const UsageError(this.message, {this.showSecretUsage = false, this.usage});

  final String message;

  /// Нужна ли после сообщения справка `codelab secret` (spec codelab-cli
  /// «Подкоманда codelab secret»). Признак, а не текст справки: ошибки
  /// разбора `secret` не должны цитировать присланные слова (среди них может
  /// быть значение секрета), а справку печатает `runCodelab` (design.md change
  /// `add-agent-secret-store`, D8).
  final bool showSecretUsage;

  /// Справка подкоманды записи (`config`, `provider`, `mcp`), которую
  /// `runCodelab` печатает после сообщения; `null` — справки нет. Текст, а не
  /// признак, потому что справки этих подкоманд не зависят от присланных слов
  /// (change `add-config-writer-and-reload`, D6).
  final String? usage;

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
  provider,
  mcp,
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
    required this.debugSecrets,
    required this.argvHasSecret,
    required this.ui,
    this.filter,
    this.subcommand,
  });

  final CliCommand command;
  final List<String> positional;

  /// Значение `--agent`: id профиля, `stdio:…`, URL или `embedded`; `null` —
  /// профиль `default`, если он есть, иначе встроенный агент.
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

  /// `--debug-secrets`: включает `secrets.lookup` встроенного агента (имя и
  /// источник секрета, без значения). Внешнего агента не касается (spec
  /// codelab-cli «Встроенный агент в CLI»; design.md change
  /// `add-embedded-agent-mode`, D5).
  final bool debugSecrets;

  /// В argv есть слово `secret`: тексты ошибок не цитируют присланные слова и
  /// пути, среди них мог быть секрет (design.md change
  /// `add-agent-secret-store`, D8).
  final bool argvHasSecret;

  /// `--ui`: интерактивный режим; на headless не влияет.
  final UiMode ui;

  /// `test-scenario --filter`: glob по id фикстуры; `null` — все.
  final String? filter;

  /// Разбор листовой подкоманды `config get|set|…`, `provider add|…`,
  /// `mcp add|…` (имя — `subcommand.name`, аргументы — `subcommand.rest`):
  /// у `provider add` и `mcp add` десяток флагов, и общий список позиций
  /// [positional] их не вместил бы; у этих команд [positional] пуст, чтобы
  /// имя и слова подкоманды не жили в двух местах (ревью итерации 4,
  /// arch N2). `null` у остальных команд. Собирает опции общих команд
  /// `run.dart` (change `add-config-writer-and-reload`, D6).
  final ArgResults? subcommand;
}

/// Подкоманды, которые регистрируются позже (этапы 7–9 и после MVP): до
/// своего change они дают `Unknown command`, а не уходят агенту первым
/// сообщением (`09-11-stage-6-cli-mvp.md`, «Спецификация CLI»).
const _laterCommands = {'sessions', 'update', 'login', 'logout', 'trajectory'};

final _durationPart = RegExp(r'(\d+)(h|m|s)');

ArgParser _parser() {
  final parser = ArgParser()
    ..addOption(
      'agent',
      abbr: 'a',
      valueHelp: 'profile',
      help:
          'Agent profile id, "embedded", "stdio:<command> [args]", ws:// or '
          'wss:// URL (default: profile "default" if it exists, else '
          '"embedded").',
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
    ..addFlag(
      'debug-secrets',
      negatable: false,
      help: 'Embedded agent: log secret lookups (names, never values).',
    )
    ..addFlag('version', negatable: false, help: 'Print the version.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help.');
  // Аргументы подкоманды разбирает она сама: у `profiles add` значение
  // профиля вроде `stdio:… --stdio` не должно попасть в флаги `codelab`.
  parser
    ..addCommand('profiles', ArgParser(allowTrailingOptions: false))
    // `check`, `path`, `get`, `set`, `unset`; `migrate` и прочее не
    // регистрируются (spec codelab-cli «Подкоманда codelab config»).
    ..addCommand('config', _configParser())
    ..addCommand('provider', _providerParser())
    ..addCommand('mcp', _mcpParser())
    // `set`, `delete`, `list` без флагов: значение секрета читается только из
    // stdin, флага `--value` нет (argv виден через `ps`; design.md change
    // `add-agent-secret-store`, D8). `migrate` — слои и режим флагами,
    // значений в argv нет, stdin не читается; его `--cwd` — флаг
    // подкоманды, а общий `-C/--cwd` с `secret` по-прежнему 64 (design.md
    // change `add-config-literal-secrets-and-migrate`, D7).
    ..addCommand(
      'secret',
      ArgParser()
        ..addCommand('set', ArgParser())
        ..addCommand('delete', ArgParser())
        ..addCommand('list', ArgParser())
        ..addCommand(
          'migrate',
          ArgParser()
            ..addFlag('project', negatable: false)
            ..addFlag('local', negatable: false)
            ..addFlag('all', negatable: false)
            ..addFlag('dry-run', negatable: false)
            ..addFlag('force', negatable: false)
            ..addOption('cwd'),
        ),
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

const _cwdListHelp = 'Project directory to load config for (default: current).';

const _cwdHelp =
    'Project directory for the project and local layers '
    '(default: current).';

/// Флаги слоя `--project` / `--local` (слои 3 и 4; D6).
ArgParser _withLayerFlags(ArgParser parser) => parser
  ..addFlag(
    'project',
    negatable: false,
    help: 'Use <cwd>/.codelab/config.yaml.',
  )
  ..addFlag(
    'local',
    negatable: false,
    help: 'Use <cwd>/.codelab/config.local.yaml.',
  );

/// Парсер подкоманды `codelab config` (`config check` — change
/// `add-agent-configuration`, D13, D14; остальное — change
/// `add-config-writer-and-reload`, D6). `--cwd` подкоманды сильнее общего
/// `-C/--cwd`.
ArgParser _configParser() => ArgParser()
  ..addCommand(
    'check',
    ArgParser()..addOption(
      'cwd',
      valueHelp: 'dir',
      help: 'Project directory to load config for (default: current).',
    ),
  )
  ..addCommand(
    'path',
    _withLayerFlags(
      ArgParser()..addOption('cwd', valueHelp: 'dir', help: _cwdHelp),
    ),
  )
  ..addCommand(
    'get',
    ArgParser()
      ..addOption(
        'layer',
        // Литерал, а не `ConfigGetLayer.values`: этот файл не вправе
        // импортировать мост (guard, `run.dart` — единственное место);
        // равенство перечислению проверяет `config_command_test.dart`.
        allowed: ['user', 'project', 'local', 'merged'],
        help: 'Layer to read (default: merged).',
      )
      ..addOption('cwd', valueHelp: 'dir', help: _cwdHelp),
  )
  ..addCommand(
    'set',
    _withLayerFlags(
      ArgParser()..addOption('cwd', valueHelp: 'dir', help: _cwdHelp),
    ),
  )
  ..addCommand(
    'unset',
    _withLayerFlags(
      ArgParser()..addOption('cwd', valueHelp: 'dir', help: _cwdHelp),
    ),
  );

/// Парсер `codelab provider` (D6). Флага со значением ключа нет намеренно:
/// argv виден через `ps`, ключ читается только из stdin (`--api-key-stdin`)
/// либо задаётся ссылкой. `--cwd` есть только у `list`, как у
/// `codelab-agent`: порядок — `--cwd` подкоманды, общий `-C`, текущая папка;
/// у `add` и `remove` папку задаёт общий `-C` (spec codelab-cli «Подкоманды
/// codelab provider и codelab mcp», сценарий «--cwd у provider list и mcp
/// list»).
ArgParser _providerParser() => ArgParser()
  ..addCommand(
    'add',
    _withLayerFlags(
      ArgParser()
        ..addOption('kind', help: 'openai-compatible, anthropic or gemini.')
        ..addOption('base-url', help: 'Provider endpoint.')
        ..addOption('model', help: 'Model id of the provider.')
        ..addOption('context-window', help: 'Model context window in tokens.')
        ..addOption('api-key-secret', help: 'Name of a stored secret.')
        ..addOption('api-key-env', help: 'Name of an environment variable.')
        ..addFlag(
          'api-key-stdin',
          negatable: false,
          help: 'Read the API key from stdin and store it as codelab/<id>.',
        )
        ..addFlag(
          'default',
          negatable: false,
          help: 'Make <id>/<model> the default model.',
        ),
    ),
  )
  ..addCommand(
    'list',
    ArgParser()..addOption('cwd', valueHelp: 'dir', help: _cwdListHelp),
  )
  ..addCommand('remove', _withLayerFlags(ArgParser()));

/// Парсер `codelab mcp` (D6): правка *файлов* конфига, не агентская `/mcp`.
/// `--cwd` — только у `list` (как у `provider`).
ArgParser _mcpParser() => ArgParser()
  ..addCommand(
    'add',
    _withLayerFlags(
      ArgParser()
        ..addOption('type', help: 'stdio or http.')
        ..addOption('command', help: 'Executable of a stdio server.')
        ..addMultiOption(
          'arg',
          splitCommas: false,
          help: 'Argument of a stdio server; repeat for more.',
        )
        ..addMultiOption(
          'env',
          splitCommas: false,
          help: 'KEY=VALUE variable of a stdio server; repeat for more.',
        )
        ..addOption('url', help: 'Address of an http server.')
        ..addMultiOption(
          'header',
          splitCommas: false,
          help: 'KEY=VALUE header of an http server; repeat for more.',
        )
        // Значение читается из stdin, в файл идёт ссылка (change
        // `add-config-literal-secrets-and-migrate`, D11); семантика как у
        // `codelab-agent mcp add`, проверки флагов — в `McpServerCommands`.
        ..addMultiOption(
          'header-stdin',
          splitCommas: false,
          help: 'Header name whose value is read from stdin and stored.',
        )
        ..addOption(
          'header-scheme',
          help: 'Scheme prefix (Bearer) for --header-stdin.',
        )
        ..addMultiOption(
          'env-stdin',
          splitCommas: false,
          help: 'Variable name whose value is read from stdin and stored.',
        )
        ..addFlag(
          'disabled',
          negatable: false,
          help: 'Write the server with enabled: false.',
        ),
    ),
  )
  ..addCommand(
    'list',
    ArgParser()..addOption('cwd', valueHelp: 'dir', help: _cwdListHelp),
  )
  ..addCommand('remove', _withLayerFlags(ArgParser()));

/// Справка `codelab --help`.
String cliUsage() =>
    '''
Usage:
  codelab [options] [first message]   interactive REPL
  codelab -p "<prompt>" [options]     headless: one turn, answer in stdout
  codelab profiles list|show <id>|add <id> <agent>|remove <id>
  codelab config check [--cwd <dir>]
  codelab config path|get|set|unset ...   read and edit config files
  codelab provider add|list|remove ...    manage LLM providers in config
  codelab mcp add|list|remove ...         manage MCP servers in config
  codelab secret set|delete|list|migrate   manage secrets (set reads the value on stdin)
  codelab test-scenario <file-or-dir>... --agent <profile> [--filter <glob>] [--timeout <d>]

Options:
${_parser().usage}

$before1Note''';

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
    // У `provider add` и `mcp add` рядом с флагами идут ключи, заголовки и
    // переменные: `--api-key=<значение>` по ошибке цитировал бы `package:args`
    // (change `add-config-writer-and-reload`, D6), поэтому фиксированная
    // фраза, как у `secret`.
    for (final (name, usage) in [
      ('provider', providerUsage),
      ('mcp', mcpUsage),
    ]) {
      if (args.contains(name)) {
        throw UsageError('invalid arguments for $name', usage: usage());
      }
    }
    // `config set <key> <value>`: значение может начинаться с `-` (например,
    // `--sk-…`), и `package:args` процитировал бы его как неизвестный флаг;
    // `config unset` — по тому же правилу, что у `codelab-agent`. Ошибки
    // `config check|get|path` по-прежнему называют причину (D6).
    final quiet = _quietConfigVerb(args);
    if (quiet != null) {
      throw UsageError(
        'invalid arguments for config $quiet',
        usage: configUsage(),
      );
    }
    throw UsageError(
      _usageMessage(error),
      usage: args.contains('config') ? configUsage() : null,
    );
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
      argvHasSecret: args.contains('secret'),
      // Ожидание кадра агента; по умолчанию 30 с (spec cli-scenario-driver).
      timeout: _parseDuration(
        command.option('timeout') ?? results.option('timeout') ?? '30s',
      ),
    );
  }
  if (results.command case final command? when command.name == 'config') {
    return _configOptions(results, command, hasSecret: args.contains('secret'));
  }
  if (results.command case final command?
      when command.name == 'provider' || command.name == 'mcp') {
    return _writeCommandOptions(results, command);
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

/// `set` или `unset` после слова `config` в [args], иначе `null`.
///
/// Почему по всему argv, а не по разобранному дереву: верхний парсер падает
/// на первом неверном слове, и до подкоманды разбор мог не дойти (как у
/// `codelab-agent`, `_quietCommandOf`; D6).
String? _quietConfigVerb(List<String> args) {
  final config = args.indexOf('config');
  if (config < 0) {
    return null;
  }
  for (final word in args.skip(config + 1)) {
    if (word == 'set' || word == 'unset') {
      return word;
    }
  }
  return null;
}

/// Флаги подключения и запроса, несовместимые с подкомандами `config`,
/// `provider`, `mcp` и `secret`.
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
  'debug-secrets',
];

/// Справка `codelab config` (в stderr при коде `64`).
///
/// Своя у каждого бинаря, потому что называет его (`codelab-agent` печатает
/// свою); тексты результатов общие (`ConfigCommands`, D6).
String configUsage() =>
    'Usage: codelab config check [--cwd <dir>]\n'
    '       codelab config path [--project | --local] [--cwd <dir>]\n'
    '       codelab config get <key> '
    '[--layer user|project|local|merged] [--cwd <dir>]\n'
    '       codelab config set <key> <value> '
    '[--project | --local] [--cwd <dir>]\n'
    '       codelab config unset <key> '
    '[--project | --local] [--cwd <dir>]\n\n'
    '`check` loads the configuration like the agent does and prints sources, '
    'issues and warnings. `get` prints the raw value of a key and its layer '
    '(references like \${VAR} are not expanded, secret-like values are '
    'masked). `set` and `unset` edit one config file in place and keep its '
    'comments. Nothing prints secret values.';

/// Справка `codelab provider` (в stderr при коде `64`).
String providerUsage() =>
    'Usage: codelab provider add <id> --kind <kind> --model <model> '
    '--context-window <tokens>\n'
    '           [--base-url <url>] [--api-key-secret <name> | '
    '--api-key-env <var> | --api-key-stdin]\n'
    '           [--default] [--project | --local]\n'
    '       codelab provider list [--cwd <dir>]\n'
    '       codelab provider remove <id> [--project | --local]\n\n'
    'Edits the config file in place. The API key is never passed as an '
    'argument: use --api-key-stdin (needs secrets.backend: file), a secret '
    'name or an environment variable name.';

/// Справка `codelab mcp` (в stderr при коде `64`).
String mcpUsage() =>
    'Usage: codelab mcp add <name> --type stdio --command <cmd> '
    '[--arg <a>]... [--env KEY=VALUE]...\n'
    '       codelab mcp add <name> --type http --url <url> '
    '[--header KEY=VALUE]...\n'
    '           [--header-stdin <Name> [--header-scheme <Scheme>]]\n'
    '           [--disabled] [--project | --local]\n'
    '       codelab mcp add <name> --type stdio --command <cmd> '
    '--env-stdin <NAME>\n'
    '       codelab mcp list [--cwd <dir>]\n'
    '       codelab mcp remove <name> [--project | --local]\n\n'
    'Edits the config file in place; it does not connect to servers. Put '
    r'secrets in headers and variables as ${secret:name} or ${VAR}. '
    '--header-stdin and --env-stdin read ONE value from stdin (one flag per '
    'call), store it and write a reference.';

/// Отклоняет флаги подключения и запроса при подкомандах записи.
///
/// Почему: профиль подключения этим подкомандам не нужен, и молчаливое
/// игнорирование скрыло бы опечатку (design.md change `add-agent-configuration`,
/// D14; `add-config-writer-and-reload`, D6). Общий `-C/--cwd` разрешён: он
/// задаёт каталог проекта.
void _rejectConnectionFlags(ArgResults results, String command, String usage) {
  for (final flag in _connectionFlags) {
    if (results.wasParsed(flag)) {
      throw UsageError('--$flag does not apply to $command', usage: usage);
    }
  }
}

/// `codelab config path|get|set|unset|check`.
///
/// Почему здесь, а не в `run.dart`: незарегистрированная подкоманда
/// (`migrate`) и неверное число аргументов — ошибка использования с кодом
/// `64` до любого ввода-вывода (spec codelab-cli «Подкоманда codelab config»).
///
/// Приоритет папки (design.md change `add-agent-configuration`, D14):
/// `--cwd` подкоманды сильнее общего `-C/--cwd`; общий флаг задаёт папку,
/// только если подкоманда её не задала.
CliOptions _configOptions(
  ArgResults results,
  ArgResults config, {
  bool hasSecret = false,
}) {
  final sub = config.command;
  _rejectConnectionFlags(
    results,
    sub == null ? 'config' : 'config ${sub.name}',
    configUsage(),
  );
  if (sub == null) {
    throw UsageError(
      config.rest.isEmpty
          ? 'config needs a subcommand: codelab config path|get|set|unset|check'
          // Spec codelab-cli требует `Unknown command config <слово>`; слово
          // не цитируется только если `secret` есть в argv (D8): там мог
          // оказаться секрет.
          : hasSecret
          ? 'Unknown command config'
          : 'Unknown command config ${config.rest.first}',
      usage: configUsage(),
    );
  }
  final wanted = switch (sub.name) {
    'get' || 'unset' => 1,
    'set' => 2,
    _ => 0,
  };
  _checkArgumentCount(sub, wanted, 'config', configUsage());
  // `--project` вместе с `--local` отсекает общий код (код 64 и текст
  // `<label>: … cannot be combined`), своей проверки здесь нет.
  return _options(
    CliCommand.config,
    results,
    cwd: sub.option('cwd'),
    subcommand: sub,
  );
}

/// `codelab provider add|list|remove` и `codelab mcp add|list|remove` (D6).
///
/// Папка проекта — `--cwd` подкоманды `list`, иначе общий `-C/--cwd`, иначе
/// текущая; у `add` и `remove` собственного `--cwd` подкоманды нет, как у
/// `codelab-agent`: `--cwd` после них — длинная форма общего `-C`, которую
/// `package:args` принимает от верхнего парсера. Сообщения не цитируют
/// присланные слова: среди них мог оказаться ключ или значение заголовка (CFG-10).
CliOptions _writeCommandOptions(ArgResults results, ArgResults command) {
  final name = command.name!;
  final usage = name == 'provider' ? providerUsage() : mcpUsage();
  final sub = command.command;
  _rejectConnectionFlags(
    results,
    sub == null ? name : '$name ${sub.name}',
    usage,
  );
  if (sub == null) {
    throw UsageError(
      command.rest.isEmpty
          ? '$name needs a subcommand: add, list or remove'
          : 'unknown $name arguments (${command.rest.length})',
      usage: usage,
    );
  }
  _checkArgumentCount(sub, sub.name == 'list' ? 0 : 1, name, usage);
  return _options(
    name == 'provider' ? CliCommand.provider : CliCommand.mcp,
    results,
    cwd: sub.name == 'list' ? sub.option('cwd') : null,
    subcommand: sub,
  );
}

void _checkArgumentCount(
  ArgResults sub,
  int wanted,
  String command,
  String usage,
) {
  if (sub.rest.length == wanted) {
    return;
  }
  final what = switch (command) {
    'provider' => 'the provider id',
    'mcp' => 'the server name',
    _ => wanted == 1 ? 'a key' : 'a key and a value',
  };
  throw UsageError(
    sub.rest.length > wanted
        ? 'unknown $command arguments (${sub.rest.length - wanted})'
        : '$command ${sub.name} needs $what',
    usage: usage,
  );
}

/// Справка `codelab secret` (в stderr при коде `64`).
///
/// Своя у каждого бинаря, потому что называет его (`codelab-agent` печатает
/// свою); общие тексты результатов даёт `SecretCommands` (D8).
String secretUsage() =>
    'Usage: codelab secret set|delete|list|migrate\n\n'
    '  codelab secret set <name>     '
    'read the value from stdin (hidden on a terminal)\n'
    '  codelab secret delete <name>\n'
    '  codelab secret list\n'
    '  codelab secret migrate [--all | [--project] [--local]] '
    '[--cwd <dir>] [--dry-run] [--force]\n'
    '      move secrets written in config files to the store '
    '(--force replaces a stored secret for good)\n\n'
    'Works on the backend chosen by secrets.backend in '
    r'$CODELAB_HOME/config.yaml or in the file named by CODELAB_CONFIG. '
    'The value is never passed as an argument and never printed.\n\n'
    '$before1Note';

/// `codelab secret set|delete|list|migrate`: [CliOptions.positional] — имя
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
    throw usage('secret needs a subcommand: set, delete, list or migrate');
  }
  switch (sub.name) {
    case 'set' when sub.rest.isEmpty:
      throw usage('secret set needs the secret name');
    case 'delete' when sub.rest.length != 1:
      throw usage('secret delete needs exactly one name');
    case 'list' when sub.rest.isNotEmpty:
      throw usage('secret list takes no arguments');
    case 'migrate' when sub.rest.isNotEmpty:
      throw usage('secret migrate takes no arguments');
  }
  // `--all` вместе со слоем отсекает общий код `SecretCommands.migrate`
  // (код 64 и справка), своей проверки здесь нет — как у `codelab-agent`.
  return _options(
    CliCommand.secret,
    results,
    positional: [sub.name!, ...sub.rest],
    cwd: sub.name == 'migrate' ? sub.option('cwd') : null,
    subcommand: sub.name == 'migrate' ? sub : null,
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
  bool argvHasSecret = false,
  ArgResults? subcommand,
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
  debugSecrets: results.flag('debug-secrets'),
  argvHasSecret: argvHasSecret,
  subcommand: subcommand,
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
