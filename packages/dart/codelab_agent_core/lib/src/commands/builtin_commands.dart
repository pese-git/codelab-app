/// Встроенные команды сессии `/config` и `/mcp` (design.md change
/// `add-config-writer-and-reload`, D12, R7-1, R7-2; `agent-core-architecture`
/// §17.5.6, §17.5.7).
///
/// Почему отдельный файл: команды исполняются без модели и без журнала, а
/// тексты ответов фиксированы побайтово. Разбор, тексты и порядок действий
/// живут здесь, а слот хода, события и очередь замен MCP-серверов — в
/// `AgentSession` (рантайм передаёт сюда только порты).
///
/// Как использовать: сессия строит [BuiltinCommands] один раз при открытии,
/// берёт [BuiltinCommands.declared] для `AgentSession.commands`, а на каждый
/// промпт спрашивает [BuiltinCommands.match]; найденную команду исполняет
/// [BuiltinCommands.run] и публикует ответ как одно сообщение агента.
library;

import '../config/config_issue.dart';
import '../mcp/mcp_connector.dart';
import '../runtime/config_reload.dart';
import 'slash_command.dart';

/// Предел длины строки, пришедшей от пользователя, в ответе (D12): руны.
const _maxUserRunes = 64;

const _configUsage = 'Usage: /config reload | /config check';
const _mcpUsage =
    'Usage: /mcp list | /mcp reload [<id>] | /mcp enable <id> | '
    '/mcp disable <id>';

/// Команда, найденная в промпте.
///
/// [subcommand] — слово для лога `command.builtin`: распознанная
/// подкоманда или `usage`; присланный аргумент в лог не попадает (§16).
final class BuiltinInvocation {
  const BuiltinInvocation._(this.name, this.args, this.subcommand);

  /// `config` или `mcp`.
  final String name;

  /// Слова после имени команды.
  final List<String> args;

  /// Подкоманда для лога: `reload`, `check`, `list`, `enable`, `disable`
  /// или `usage`.
  final String subcommand;
}

/// Исполнитель встроенных команд одной сессии.
///
/// Порты — функции: ядро не знает, как сессия ставит действия в очередь
/// замен серверов (D10, D11), а команды не должны знать про очередь.
final class BuiltinCommands {
  BuiltinCommands({
    this.reloadConfig,
    this.checkConfig,
    required this.mcpDeclared,
    required this.servers,
    required this.reconnect,
    required this.setEnabled,
  });

  /// `AgentRuntime.reloadConfig`; `null` — команда `config` не объявлена.
  final Future<ConfigApplyReport> Function()? reloadConfig;

  /// `AgentRuntime.checkConfig`.
  final Future<ConfigLoadResult> Function()? checkConfig;

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

  /// Объявления для `AgentSession.commands`: `config`, затем `mcp` (D12,
  /// §13.4). [config] — есть `ConfigSource` и `configCommand` (R0-3), [mcp] —
  /// включена capability `mcp` профиля.
  static List<SlashCommand> declare({
    required bool config,
    required bool mcp,
  }) => [
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
  ];

  /// Находит объявленную команду в [text] (первый текстовый блок): слово до
  /// первого пробельного символа равно `/config` или `/mcp`. Необъявленная
  /// команда и любое другое слово — `null`, промпт идёт дальше как обычный.
  BuiltinInvocation? match(String text) {
    // Как у шаблонов (`expand_command.dart`): команда начинается с `/` в
    // первой позиции, ведущие пробелы команду не делают.
    if (!text.startsWith('/')) {
      return null;
    }
    final end = text.indexOf(RegExp(r'\s'));
    final word = end < 0 ? text : text.substring(0, end);
    final isConfig = word == '/config' && reloadConfig != null;
    final isMcp = word == '/mcp' && mcpDeclared;
    if (!isConfig && !isMcp) {
      return null;
    }
    // Слова делятся только у объявленной команды: чужой текст не разбирается.
    final args = end < 0
        ? const <String>[]
        : text
              .substring(end)
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .toList(growable: false);
    if (isConfig) {
      final known =
          args.length == 1 && (args[0] == 'reload' || args[0] == 'check');
      return BuiltinInvocation._('config', args, known ? args[0] : 'usage');
    }
    return BuiltinInvocation._('mcp', args, _mcpSubcommand(args));
  }

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

  /// Исполняет команду и возвращает текст ответа одним [String].
  ///
  /// Почему строка, а не объект ответа: у ответа нет других полей, а вид
  /// сообщения (одно сообщение агента) решает сессия.
  ///
  /// [cancelled] — признак отмены команды (`session/cancel`, токен промпта,
  /// закрытие сессии). После отмены команда не начинает новых действий над
  /// серверами: ответ уже никто не ждёт, а действие изменило бы набор
  /// инструментов посреди следующего хода (D12, «Отмена встроенной команды»; D11). Исключения портов
  /// (`servers`, `reloadConfig`, `reconnect`) не перехватываются здесь:
  /// сессия превращает их в провал хода. Единственное исключение —
  /// [checkConfig]: сбой загрузки становится текстом ответа.
  Future<String> run(
    BuiltinInvocation call, {
    required bool Function() cancelled,
  }) => switch (call.name) {
    'config' => _config(call),
    _ => _mcp(call, cancelled),
  };

  Future<String> _config(BuiltinInvocation call) async {
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

  Future<String> _mcp(BuiltinInvocation call, bool Function() cancelled) async {
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
