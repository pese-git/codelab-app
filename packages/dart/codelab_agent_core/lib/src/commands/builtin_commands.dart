/// Встроенные команды сессии: `/compact`, `/mode`, `/model`, `/status`,
/// `/config`, `/mcp`, `/help` и ответ на неизвестную команду (design.md
/// changes `add-config-writer-and-reload`, D12, R7-1, R7-2, и
/// `add-agent-builtin-slash-commands`, D1–D7; `agent-core-architecture`
/// §13.4, §13.6, §13.7, §17.2.6, §17.5.6, §17.5.7).
///
/// Почему отдельный файл: команды исполняются без модели и без журнала
/// промпта, а тексты ответов фиксированы побайтово. Объявление, разбор, тексты
/// и порядок действий живут здесь одним `switch` по имени (D1, альтернатива
/// «класс на команду» отклонена: пять команд с фиксированными текстами не
/// оправдывают иерархию), а слот хода, события и очередь замен MCP-серверов —
/// в `AgentSession` (рантайм передаёт сюда только порты-функции).
///
/// Как использовать: сессия строит [BuiltinCommands] один раз при открытии,
/// берёт [BuiltinCommands.declare] для `AgentSession.commands`, а на каждый
/// промпт спрашивает [BuiltinCommands.match]; найденную команду исполняет
/// [BuiltinCommands.run] и публикует ответ как одно сообщение агента.
library;

import 'dart:convert';

import '../cancel/cancel_token.dart';
import '../compaction/compactor.dart';
import '../config/config_issue.dart';
import '../mcp/mcp_connector.dart';
import '../permissions/modes.dart';
import '../runtime/config_reload.dart';
import 'command_line.dart';
import 'slash_command.dart';

/// Предел длины строки, пришедшей от пользователя, в ответе (D12): руны.
const _maxUserRunes = 64;

const _configUsage = 'Usage: /config reload | /config check';
const _mcpUsage =
    'Usage: /mcp list | /mcp reload [<id>] | /mcp enable <id> | '
    '/mcp disable <id>';

/// Имена встроенных команд сессии (D1, D2).
///
/// Почему enum: диспетчер [BuiltinCommands.run] и логи работают по закрытому
/// списку, и новая команда без ветки в `switch` не соберётся.
enum BuiltinName {
  compact,
  mode,
  model,
  status,
  config,
  mcp,
  help;

  /// Команда меняет состояние сессии (журнал, режим, модель): такой ход
  /// всегда доводится до конца, а ответ строится по факту (D14).
  bool get changesState => switch (this) {
    compact || mode || model => true,
    status || config || mcp || help => false,
  };
}

/// Команда, найденная в промпте: объявленная встроенная или неизвестная.
///
/// Почему sealed: сессия обязана обработать обе ветки, а неизвестная команда
/// не несёт имени встроенной и не должна случайно попасть в лог (D4, §16).
sealed class BuiltinInvocation {
  const BuiltinInvocation();
}

/// Объявленная в сессии встроенная команда.
///
/// [subcommand] — слово для лога `command.builtin`: распознанная
/// подкоманда или `usage`; присланный аргумент в лог не попадает (§16).
final class BuiltinCall extends BuiltinInvocation {
  const BuiltinCall._(this.name, this.args, this.subcommand, this.raw);

  /// Какая команда.
  final BuiltinName name;

  /// Слова после имени команды (для `config` и `mcp`).
  final List<String> args;

  /// Подкоманда для лога: `reload`, `check`, `list`, `enable`, `disable`,
  /// `usage`, `run`, `set`, `show` или `unknown` (значение не найдено).
  final String subcommand;

  /// Остаток после имени без ведущих пробелов и завершающего `\r?\n`
  /// (`raw` в терминах шаблонов).
  final String raw;
}

/// Слово, не являющееся ни командой сессии, ни шаблоном (D4).
final class UnknownCall extends BuiltinInvocation {
  const UnknownCall._(this.word);

  /// Набранное имя без `/`, до обрезки.
  final String word;

  /// Размер имени в байтах UTF-8 для лога `command.unknown`: показывает
  /// масштаб ввода, не раскрывая его (D4).
  int get nameBytes => utf8.encode(word).length;
}

/// Результат [BuiltinCommands.run].
///
/// Почему sealed: у команды два исхода хода, и сессия обязана обработать оба
/// (текст ответа; провал, о котором ядро уже сообщило `AgentError`).
sealed class BuiltinReply {
  const BuiltinReply();
}

/// Ответ командой: сессия публикует его одним сообщением агента.
final class BuiltinText extends BuiltinReply {
  const BuiltinText(this.text);

  final String text;
}

/// Ход команды провален, `AgentError` уже опубликован портом (`/compact`,
/// `CompactionFailed`, Q9): сообщения агента нет, ход кончается `failed`.
final class BuiltinTurnFailed extends BuiltinReply {
  const BuiltinTurnFailed();
}

/// Исполнитель встроенных команд одной сессии.
///
/// Порты — функции: ядро не знает, как сессия ставит действия в очередь
/// замен серверов (D10, D11), как сжимает журнал и как пишет смену режима, а
/// команды не должны знать про очередь, писатель журнала и каталог.
final class BuiltinCommands {
  BuiltinCommands({
    this.reloadConfig,
    this.checkConfig,
    this.configStatus,
    this.compactNow,
    required this.mcpDeclared,
    required this.servers,
    required this.reconnect,
    required this.setEnabled,
    required this.currentMode,
    required this.setMode,
    required this.currentModel,
    required this.hasModel,
    required this.setModel,
    required this.workingDirectory,
    required this.commands,
    this.templateNames = const {},
  });

  /// `AgentRuntime.reloadConfig`; `null` — команда `config` не объявлена.
  final Future<ConfigApplyReport> Function()? reloadConfig;

  /// `AgentRuntime.checkConfig`.
  final Future<ConfigLoadResult> Function()? checkConfig;

  /// `AgentRuntime.configStatus` для строк `Config` и `Restart required`
  /// команды `/status`; `null` — команда `config` не объявлена, и `/status`
  /// не раскрывает состояние конфигурации другим путём (R0-3, D7).
  final ConfigStatus Function()? configStatus;

  /// Ручное сжатие сессии с триггером `manual` и указанием `focus`;
  /// `null` — capability `compaction` выключена, команда `compact` не
  /// объявлена (D5, Q10). Отмена [CancelToken] даёт `CancelledException`.
  final Future<CompactionOutcome> Function(String? focus, CancelToken cancel)?
  compactNow;

  /// Команда `mcp` объявлена (capability `mcp` профиля).
  final bool mcpDeclared;

  /// Живая сводка серверов сессии (`McpSessionTools.servers`), не кэш.
  final List<McpServerSummary> Function() servers;

  /// `McpSessionTools.reconnect` через очередь замен сессии. `cancelled` —
  /// признак отмены команды: порт не выполняет задание, отменённое пока
  /// стояло в очереди (D12, «Отмена встроенной команды»).
  final Future<void> Function(String id, bool Function() cancelled) reconnect;

  /// `McpSessionTools.setEnabled` через очередь замен сессии; `cancelled` —
  /// как у [reconnect].
  final Future<void> Function(
    String id,
    bool enabled,
    bool Function() cancelled,
  )
  setEnabled;

  /// Режим сессии на момент вызова (`/mode` без аргумента, `/status`).
  final ModeId Function() currentMode;

  /// `AgentSession.setMode`: тот же путь, что `session/set_config_option`
  /// (D6) — запись `mode_change` и событие `ModeChanged` до возврата.
  final Future<void> Function(ModeId mode) setMode;

  /// Модель сессии как `provider/id`.
  final String Function() currentModel;

  /// Модель есть в каталоге применённого снимка (`ModelId` как `provider/id`).
  final bool Function(String id) hasModel;

  /// `AgentSession.setModel` и событие изменения опции `model` (D6); возвращает
  /// `provider/id` выбранной модели.
  final Future<String> Function(String id) setModel;

  /// `cwd` сессии для `/status`.
  final String workingDirectory;

  /// `AgentSession.commands` для `/help`: порядок списка — порядок строк.
  final List<SlashCommand> Function() commands;

  /// Имена шаблонов сессии: слово, совпавшее с шаблоном, не неизвестная
  /// команда, его разворачивает `expandCommand` (D3, шаг 3).
  final Set<String> templateNames;

  /// Объявления для `AgentSession.commands` в порядке §13.4 (D2): `compact`,
  /// `mode`, `model`, `status`, `config`, `mcp`, `help`; отсутствующая
  /// пропускается. [compact] — включена capability `compaction`, [config] —
  /// есть `ConfigSource` и `configCommand` (R0-3), [mcp] — включена
  /// capability `mcp` профиля.
  static List<SlashCommand> declare({
    required bool compact,
    required bool config,
    required bool mcp,
  }) => [
    if (compact)
      const SlashCommand(
        name: 'compact',
        description: 'Compact the session history',
        source: SlashCommandSource.builtin,
        inputHint: '[focus]',
      ),
    const SlashCommand(
      name: 'mode',
      description: 'Switch the session mode',
      source: SlashCommandSource.builtin,
      inputHint: 'plan | ask | standard | accept-edits | bypass',
    ),
    const SlashCommand(
      name: 'model',
      description: 'Switch the model',
      source: SlashCommandSource.builtin,
      inputHint: 'provider/model',
    ),
    const SlashCommand(
      name: 'status',
      description: 'Show the model, mode, working directory and MCP servers',
      source: SlashCommandSource.builtin,
    ),
    if (config)
      const SlashCommand(
        name: 'config',
        description: 'Reload or check the agent config',
        source: SlashCommandSource.builtin,
        inputHint: 'reload | check',
      ),
    if (mcp)
      const SlashCommand(
        name: 'mcp',
        description: 'List, reload, enable or disable MCP servers',
        source: SlashCommandSource.builtin,
        inputHint: 'list | reload [<id>] | enable <id> | disable <id>',
      ),
    const SlashCommand(
      name: 'help',
      description: 'List commands',
      source: SlashCommandSource.builtin,
    ),
  ];

  /// Разбирает первый текстовый блок промпта по порядку D3:
  /// 1. не `/` в первой позиции или слово вне `^[A-Za-z0-9][A-Za-z0-9:_-]*$`
  ///    (`/usr/bin/foo`, ведущий пробел) — `null`, промпт уходит модели;
  /// 2. объявленная в сессии команда — [BuiltinInvocation] для [run];
  /// 3. имя шаблона — `null`, дальше его разворачивает `expandCommand`;
  /// 4. иначе — неизвестная команда ([BuiltinInvocation.isUnknown], D4).
  ///
  /// Необъявленные `/config`, `/mcp`, `/compact` дают шаг 4, а не шаг 1
  /// (Q6, Q10): ответ не раскрывает конфигурацию, модель не получает текста,
  /// который пользователь набрал как команду.
  BuiltinInvocation? match(String text) {
    final line = parseCommandLine(text);
    if (line == null) {
      return null;
    }
    final word = line.word;
    final raw = line.raw;
    final name = switch (word) {
      'compact' when compactNow != null => BuiltinName.compact,
      'mode' => BuiltinName.mode,
      'model' => BuiltinName.model,
      'status' => BuiltinName.status,
      'help' => BuiltinName.help,
      'config' when reloadConfig != null => BuiltinName.config,
      'mcp' when mcpDeclared => BuiltinName.mcp,
      _ => null,
    };
    if (name == null) {
      return templateNames.contains(word) ? null : UnknownCall._(word);
    }
    // Слова делятся только у объявленной команды: чужой текст не
    // разбирается.
    final args = raw
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    final arg = raw.trim();
    final subcommand = switch (name) {
      BuiltinName.config =>
        args.length == 1 && (args[0] == 'reload' || args[0] == 'check')
            ? args[0]
            : 'usage',
      BuiltinName.mcp => _mcpSubcommand(args),
      BuiltinName.mode =>
        arg.isEmpty
            ? 'show'
            : (ModeId.tryParse(arg) == null ? 'unknown' : 'set'),
      BuiltinName.model =>
        arg.isEmpty ? 'show' : (_isModelArg(arg) ? 'set' : 'unknown'),
      BuiltinName.compact => 'run',
      // `status` и `help`: аргументы игнорируются (D7).
      BuiltinName.status || BuiltinName.help => 'show',
    };
    return BuiltinCall._(name, args, subcommand, raw);
  }

  /// Форма `--role` — после MVP (§17.10.5): как неизвестная модель.
  bool _isModelArg(String arg) => !arg.startsWith('--') && hasModel(arg);

  static String _mcpSubcommand(List<String> args) {
    if (args.isEmpty) {
      return 'list';
    }
    return switch (args[0]) {
      'list' when args.length == 1 => 'list',
      'reload' when args.length <= 2 => 'reload',
      'enable' when args.length == 2 => 'enable',
      'disable' when args.length == 2 => 'disable',
      _ => 'usage',
    };
  }

  /// Исполняет команду и возвращает ответ.
  ///
  /// Почему [BuiltinReply], а не строка: ответ почти всегда текст, но отказ
  /// сжатия (`CompactionFailed`) — провал хода без сообщения агента (Q9).
  ///
  /// [cancelled] — признак отмены команды (`session/cancel`, токен
  /// промпта, закрытие сессии), [cancel] — тот же сигнал токеном для
  /// `/compact`. После отмены команда не начинает новых действий над
  /// серверами: ответ уже никто не ждёт, а действие изменило бы набор
  /// инструментов посреди следующего хода (D12, «Отмена встроенной команды»;
  /// D11). Исключения портов (`servers`, `reloadConfig`, `reconnect`,
  /// `compactNow`, `setMode`, `setModel`) не перехватываются здесь: сессия
  /// превращает их в провал хода. Единственное исключение — [checkConfig]:
  /// сбой загрузки становится текстом ответа.
  Future<BuiltinReply> run(
    BuiltinInvocation call, {
    required bool Function() cancelled,
    required CancelToken cancel,
  }) async => switch (call) {
    UnknownCall(:final word) => BuiltinText(
      'Unknown command: /${_truncate(word)}. Run /help to list commands.',
    ),
    final BuiltinCall c => switch (c.name) {
      BuiltinName.config => BuiltinText(await _config(c)),
      BuiltinName.mcp => BuiltinText(await _mcp(c, cancelled)),
      BuiltinName.compact => await _compact(c, cancel),
      BuiltinName.mode => BuiltinText(await _mode(c, cancel)),
      BuiltinName.model => BuiltinText(await _model(c, cancel)),
      BuiltinName.status => BuiltinText(_status()),
      BuiltinName.help => BuiltinText(_help()),
    },
  };

  /// `/compact [focus]`: `manual`, пустое указание — без `focus` (D5).
  Future<BuiltinReply> _compact(BuiltinCall call, CancelToken cancel) async {
    final focus = call.raw.trim().isEmpty ? null : call.raw;
    return switch (await compactNow!(focus, cancel)) {
      Compacted(:final tokensBefore, :final tokensAfter) => BuiltinText(
        'Compacted: $tokensBefore → $tokensAfter tokens.',
      ),
      NothingToCompact() => const BuiltinText('Nothing to compact.'),
      CompactionFailed() => const BuiltinTurnFailed(),
    };
  }

  static final _modeList = ModeId.values.map((m) => m.value).join(', ');

  /// `/mode [<id>]`: смена идёт через `setMode`, ответ — основной id (D6).
  Future<String> _mode(BuiltinCall call, CancelToken cancel) async {
    final arg = call.raw.trim();
    if (arg.isEmpty) {
      return 'Mode: ${currentMode().value}. Available: $_modeList.';
    }
    final mode = ModeId.tryParse(arg);
    if (mode == null) {
      return 'Unknown mode: ${_truncate(arg)}. Available: $_modeList.';
    }
    // Отмена до применения: ни записи, ни события смены (D14). После начала
    // смена доводится до конца, и ответ строится по факту.
    cancel.throwIfCancelled();
    await setMode(mode);
    return 'Mode: ${mode.value}.';
  }

  /// `/model [<provider/model>]` (D6, Q3).
  Future<String> _model(BuiltinCall call, CancelToken cancel) async {
    final arg = call.raw.trim();
    if (arg.isEmpty) {
      return 'Model: ${currentModel()}. Run /model <provider/model> to '
          'switch.';
    }
    if (!_isModelArg(arg)) {
      return 'Unknown model: ${_truncate(arg)}. Run /status to see the '
          'current model.';
    }
    cancel.throwIfCancelled();
    return 'Model: ${await setModel(arg)}.';
  }

  /// `/status`: четыре строки, `Config` и `Restart required` — только при
  /// объявленной `/config` (D7, Q2, R0-3).
  String _status() {
    final all = servers();
    final status = configStatus?.call();
    return [
      'Model: ${currentModel()}',
      'Mode: ${currentMode().value}',
      'Working directory: $workingDirectory',
      all.isEmpty
          ? 'MCP servers: none'
          : 'MCP servers: ${all.map((s) => '${s.name} (${s.state.name})').join(', ')}',
      if (status != null) ..._configLines(status),
    ].join('\n');
  }

  static List<String> _configLines(ConfigStatus status) {
    final count = status.lastIssues.length;
    final failedAt = status.lastFailureAt?.toUtc().toIso8601String();
    return [
      if (count == 0)
        'Config: ok'
      else
        'Config: reload failed at $failedAt '
            '(${count == 1 ? '1 issue' : '$count issues'}). '
            'Run /config check.',
      if (status.pendingRestartKeys.isNotEmpty)
        'Restart required: ${status.pendingRestartKeys.join(', ')}',
    ];
  }

  /// `/help`: `Commands:` и по строке на команду списка сессии (D7, Q1;
  /// §17.2.9).
  String _help() => [
    'Commands:',
    for (final c in commands())
      '/${c.name}'
          '${c.inputHint == null ? '' : ' ${c.inputHint}'}'
          ' - ${c.description}'
          '${c.source == SlashCommandSource.template ? ' (template)' : ''}',
  ].join('\n');

  Future<String> _config(BuiltinCall call) async {
    if (call.subcommand == 'reload') {
      final report = await reloadConfig!();
      return _reloadLines(report, mcp: false).join('\n');
    }
    if (call.subcommand == 'check') {
      final ConfigLoadResult result;
      try {
        result = await checkConfig!();
      } on Object catch (error) {
        return 'Config check failed (${error.runtimeType}). '
            'See the agent log.';
      }
      return _checkLines(result).join('\n');
    }
    return _configUsage;
  }

  Future<String> _mcp(BuiltinCall call, bool Function() cancelled) async {
    final args = call.args;
    switch (call.subcommand) {
      case 'list':
        return _table(servers());
      case 'reload' when args.length == 2:
        final id = args[1];
        if (!_known(id)) {
          return _unknown(id);
        }
        await reconnect(id, cancelled);
        return _table(servers());
      case 'reload':
        return _reloadAll(cancelled);
      case 'enable' || 'disable':
        final id = args[1];
        if (!_known(id)) {
          return _unknown(id);
        }
        await setEnabled(id, call.subcommand == 'enable', cancelled);
        return _table(servers());
      default:
        return _mcpUsage;
    }
  }

  /// `/mcp reload`: `reloadConfig()`, затем пробуждение `failed`, затем итог
  /// и таблица на момент ответа (D12).
  ///
  /// При исходе `failed` серверы НЕ будятся: текст ответа обещает «MCP
  /// servers unchanged» (D12, решение по итерации 7), а прежний снимок
  /// остаётся целиком.
  Future<String> _reloadAll(bool Function() cancelled) async {
    final report = await reloadConfig!();
    final lines = _reloadLines(report, mcp: true);
    if (report.outcome != ConfigReloadOutcome.failed) {
      for (final server in servers()) {
        // Отменённая команда серверы не будит: перезагрузка, начатая
        // рантаймом, дошла до конца, но ответ никто не ждёт (D12).
        if (cancelled()) {
          break;
        }
        if (server.state == McpServerState.failed) {
          await reconnect(server.name, cancelled);
        }
      }
    }
    return [...lines, _table(servers())].join('\n');
  }

  bool _known(String id) => servers().any((s) => s.name == id);

  String _unknown(String id) =>
      'Unknown MCP server: ${_truncate(id)}. Run /mcp list.';

  static String _truncate(String value) {
    final runes = value.runes;
    return runes.length <= _maxUserRunes
        ? value
        : String.fromCharCodes(runes.take(_maxUserRunes));
  }

  /// Строки итога перезагрузки: R7-1, R7-2. Для `/mcp reload` исход
  /// `failed` говорит про неизменные серверы.
  static List<String> _reloadLines(
    ConfigApplyReport report, {
    required bool mcp,
  }) {
    final first = switch (report.outcome) {
      ConfigReloadOutcome.applied when report.changedKeys.isEmpty =>
        'Config reloaded: no keys applied now.',
      ConfigReloadOutcome.applied =>
        report.changedKeys.length == 1
            ? 'Config reloaded: 1 key changed.'
            : 'Config reloaded: ${report.changedKeys.length} keys changed.',
      ConfigReloadOutcome.unchanged => 'Config unchanged.',
      ConfigReloadOutcome.failed => _failedLine(report.issues.length, mcp),
    };
    return [
      first,
      if (report.restartRequiredKeys.isNotEmpty)
        'Restart required: ${report.restartRequiredKeys.join(', ')}',
    ];
  }

  static String _failedLine(int count, bool mcp) {
    final issues = count == 1 ? '1 issue' : '$count issues';
    return mcp
        ? 'Config reload failed ($issues); MCP servers unchanged. '
              'Run /config check.'
        : 'Config reload failed ($issues). Current settings kept. '
              'Run /config check.';
  }

  /// `/config check`: первая строка общая с `config check` CLI, без
  /// склонения (R7-2); проблемы — `ConfigIssue.toString()` без обрезки.
  static List<String> _checkLines(ConfigLoadResult result) {
    final restart = [
      for (final warning in result.warnings)
        if (warning.event == 'config.reload.restart_required') warning.key,
    ];
    return [
      if (result.issues.isEmpty)
        'Config: valid'
      else
        'Config: invalid (issues: ${result.issues.length})',
      for (final issue in result.issues) '- $issue',
      'Sources: ${result.sources.join(', ')}',
      if (restart.isNotEmpty) 'Restart required: ${restart.join(', ')}',
    ];
  }

  /// Таблица §17.5.7 в блоке `text`: колонки выровнены по самой длинной
  /// ячейке плюс два пробела, последняя без хвостовых пробелов.
  static String _table(List<McpServerSummary> servers) {
    if (servers.isEmpty) {
      return 'No MCP servers.';
    }
    final rows = <List<String>>[
      ['ID', 'SOURCE', 'TRANSPORT', 'STATE', 'TOOLS', 'LAST ERROR'],
      for (final s in servers)
        [
          s.name,
          s.origin.name,
          s.transport,
          s.state.name,
          '${s.toolCount}',
          _lastError(s),
        ],
    ];
    final widths = [
      for (var c = 0; c < 5; c++)
        rows.map((r) => r[c].runes.length).reduce((a, b) => a > b ? a : b) + 2,
    ];
    final lines = [
      for (final row in rows)
        [
          for (var c = 0; c < 5; c++)
            row[c] + ' ' * (widths[c] - row[c].runes.length),
          row[5],
        ].join(),
    ];
    return '```text\nMCP servers (${servers.length})\n${lines.join('\n')}\n```';
  }

  static String _lastError(McpServerSummary s) {
    final error = s.lastError ?? '-';
    final retry = s.retryIn;
    if (s.state != McpServerState.failed || retry == null) {
      return error;
    }
    final seconds = (retry.inMilliseconds / 1000).round();
    return '$error (retry in ${seconds < 1 ? 1 : seconds}s)';
  }
}
