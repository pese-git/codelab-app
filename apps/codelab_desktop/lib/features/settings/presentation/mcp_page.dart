import 'dart:async';

import 'package:codelab_embedded/codelab_embedded.dart' show McpServerState;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../application/mcp_settings_cubit.dart';

/// Тело страницы «MCP servers» для таблицы `settingsPageBuilders`.
///
/// Почему отдельный хозяин: Cubit страницы создаётся на каждое открытие
/// (снимок `config.yaml` перечитывается при открытии, design.md change
/// `add-provider-setup-ui`, D11), а построитель таблицы — просто функция от
/// `BuildContext`.
Widget buildMcpPage(BuildContext context) => const McpPageHost();

/// Создаёт `McpSettingsCubit`, читает снимок и закрывает Cubit вместе со
/// страницей.
///
/// Почему не виджет, создающий зависимости: Cubit собирает composition root
/// (`CodeLabDependencies.createMcpSettingsCubit`); здесь он только получает
/// владельца жизненного цикла (AGENTS.md §6). Закрытие страницы закрывает
/// Cubit и тем отменяет подписку на состояние MCP (D12, D21).
class McpPageHost extends StatefulWidget {
  const McpPageHost({super.key});

  @override
  State<McpPageHost> createState() => _McpPageHostState();
}

class _McpPageHostState extends State<McpPageHost> {
  McpSettingsCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit == null) {
      final cubit = codeLabDependenciesOf(context).createMcpSettingsCubit();
      _cubit = cubit;
      unawaited(cubit.reload());
    }
  }

  @override
  void dispose() {
    unawaited(_cubit?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocProvider.value(value: _cubit!, child: const McpPage());
}

/// Страница настроек «MCP servers» (артборд
/// `docs/design/claude-design/Mcp.dc.html`; расхождения — design.md change
/// `add-provider-setup-ui`, D24).
///
/// Почему: MCP-серверы — настройка агента, общая с CLI (`codelab mcp add`),
/// поэтому страница показывает файл агента, а не собственное хранилище (spec
/// app-settings «Страница «MCP servers»»).
///
/// Для чего: только отображение состояния [McpSettingsCubit] и сбор формы.
/// Что можно удалить, какой слой писать, опасно ли действие и что считается
/// занятым именем — решает Cubit и мост `codelab_setup`; страница получает
/// решение пользователя (подтверждение удаления, «Replace it») и вызывает
/// методы Cubit (AGENTS.md §7, §10). Значения секретов живут только в полях
/// формы до нажатия «Save».
///
/// Как использовать: Cubit берётся из `BlocProvider` выше по дереву.
/// Раскрытие строк и содержимое полей — эфемерное состояние виджетов.
class McpPage extends StatefulWidget {
  const McpPage({super.key});

  @override
  State<McpPage> createState() => _McpPageState();
}

class _McpPageState extends State<McpPage> {
  /// Раскрытые строки (имя) — эфемерное состояние виджета.
  final _expanded = <String>{};

  /// Номер редактора по имени: после успешной записи форма пересоздаётся из
  /// файла, а не хранит набранные значения секретов.
  final _epoch = <String, int>{};

  McpSettingsCubit get _cubit => context.read<McpSettingsCubit>();

  Future<bool> _save(
    McpServerDraft draft,
    ConfigLayer target,
    Set<String> replace,
  ) async {
    final saved = await _cubit.save(
      draft,
      target: target,
      replaceSecrets: replace,
    );
    if (saved && mounted && draft.originalName != null) {
      setState(
        () => _epoch.update(draft.name, (n) => n + 1, ifAbsent: () => 1),
      );
    }
    return saved;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<McpSettingsCubit, McpSettingsState>(
      builder: (context, state) => KeyedSubtree(
        key: const ValueKey('settings-mcp'),
        child: switch (state) {
          McpSettingsLoading() => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: ProgressRing()),
          ),
          McpSettingsReadOnly() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(withAdd: false),
              _bar(
                const ValueKey('mcp-read-only'),
                InfoBarSeverity.warning,
                state.notice,
                content: state.hint == null ? null : Text(state.hint!),
              ),
              _StatusPanel(status: state.agentStatus),
            ],
          ),
          McpSettingsUnreadable() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(withAdd: false),
              _bar(
                const ValueKey('mcp-unreadable'),
                InfoBarSeverity.error,
                'Cannot read the agent config. Fix or remove the file; '
                'CodeLab will not overwrite it.',
                content: Text(state.problems.join('\n')),
              ),
              _StatusPanel(status: state.agentStatus),
            ],
          ),
          McpSettingsReady() => _ready(context, state),
        },
      ),
    );
  }

  Widget _header({required bool withAdd}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        const Expanded(
          child: CodeLabText('MCP servers', role: CodeLabTextRole.title),
        ),
        if (withAdd)
          CodeLabButton(
            key: const ValueKey('mcp-add'),
            label: 'Add server',
            icon: FluentIcons.add,
            emphasis: CodeLabButtonEmphasis.primary,
            onPressed: () => _cubit.openNewServer(),
          ),
      ],
    ),
  );

  Widget _bar(
    Key key,
    InfoBarSeverity severity,
    String title, {
    Widget? content,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InfoBar(
      key: key,
      title: Text(title),
      content: content,
      severity: severity,
      isLong: true,
      action: action,
    ),
  );

  Widget _ready(BuildContext context, McpSettingsReady state) {
    final count = state.rows.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(withAdd: true),
        if (state.banner case final banner?) _banner(banner),
        if (state.rejected case final rejected?) _rejected(rejected),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: CodeLabText(
                  '$count ${count == 1 ? 'server' : 'servers'}',
                  role: CodeLabTextRole.strong,
                ),
              ),
              const Flexible(
                child: CodeLabStatusIndicator(
                  label: 'Composition from the config · agent status below',
                  tone: CodeLabStatusTone.active,
                ),
              ),
            ],
          ),
        ),
        if (state.newServerOpen)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _NewServerCard(
              state: state,
              onSave: (draft, target, replace) async {
                await _save(draft, target, replace);
              },
              onCancel: _cubit.cancelNewServer,
            ),
          ),
        if (state.rows.isEmpty && !state.newServerOpen)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: CodeLabText(
                    'No MCP servers yet.',
                    key: ValueKey('mcp-empty'),
                  ),
                ),
                CodeLabButton(
                  key: const ValueKey('mcp-empty-add'),
                  label: 'Add server',
                  icon: FluentIcons.add,
                  onPressed: () => _cubit.openNewServer(),
                ),
              ],
            ),
          )
        else
          for (final row in state.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _ServerCard(
                row: row,
                state: state,
                expanded: _expanded.contains(row.name),
                epoch: _epoch[row.name] ?? 0,
                onToggle: (open) => setState(() {
                  if (open) {
                    _expanded.add(row.name);
                  } else {
                    _expanded.remove(row.name);
                  }
                }),
                onSave: (draft, target, replace) async {
                  await _save(draft, target, replace);
                },
                onRemove: () => unawaited(_confirmRemove(row.name)),
              ),
            ),
        const SizedBox(height: 18),
        _StatusPanel(status: state.agentStatus),
      ],
    );
  }

  Widget _banner(McpBanner banner) => _bar(
    const ValueKey('mcp-banner'),
    switch (banner.kind) {
      McpBannerKind.saved => InfoBarSeverity.success,
      McpBannerKind.conflict => InfoBarSeverity.warning,
      McpBannerKind.error => InfoBarSeverity.error,
    },
    banner.lines.first,
    content: banner.lines.length < 2
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final line in banner.lines.skip(1)) Text(line)],
          ),
  );

  Widget _rejected(McpRejectedConfig rejected) {
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    final server = rejected.editServer;
    return _bar(
      const ValueKey('mcp-rejected'),
      InfoBarSeverity.error,
      rejected.title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Config: invalid', style: mono),
          for (final problem in rejected.problems) Text(problem, style: mono),
          const SizedBox(height: 4),
          CodeLabText(
            'The agent keeps running on the previous config until this is '
            'fixed.',
            role: CodeLabTextRole.caption,
            color: secondary,
          ),
        ],
      ),
      action: server == null
          ? null
          : CodeLabButton(
              key: const ValueKey('mcp-rejected-edit'),
              label: 'Edit $server',
              onPressed: () => setState(() => _expanded.add(server)),
            ),
    );
  }

  /// «Remove»: подтверждение `Remove <name>?` со списком секретов страницы,
  /// которые будут удалены (Q25 (3)); без подтверждения запись не идёт.
  Future<void> _confirmRemove(String name) async {
    final cubit = _cubit;
    final plan = cubit.removalPlan(name);
    if (plan == null) {
      return;
    }
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: CodeLabDialogTitle('Remove $name?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The server is removed from the config file.'),
            if (plan.secrets.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'These stored secrets will be deleted if nothing else uses '
                'them:',
              ),
              const SizedBox(height: 4),
              Column(
                key: const ValueKey('mcp-remove-secrets'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final secret in plan.secrets) Text(secret, style: mono),
                ],
              ),
            ],
          ],
        ),
        actions: [
          Button(
            key: const ValueKey('mcp-remove-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('mcp-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await cubit.remove(name);
  }
}

typedef _SaveDraft =
    Future<void> Function(
      McpServerDraft draft,
      ConfigLayer target,
      Set<String> replace,
    );

/// Строка сервера: Expander артборда (заголовок с тегами, действиями и
/// переключателем, раскрытое тело — редактор или пояснение).
class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.row,
    required this.state,
    required this.expanded,
    required this.epoch,
    required this.onToggle,
    required this.onSave,
    required this.onRemove,
  });

  final McpServerRow row;
  final McpSettingsReady state;
  final bool expanded;
  final int epoch;
  final ValueChanged<bool> onToggle;
  final _SaveDraft onSave;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<McpSettingsCubit>();
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    final name = row.name;
    final fromProjectFile = !row.canToggle && !row.canEnableHere;
    final Widget? body;
    if (!expanded) {
      body = null;
    } else if (row.note case final note?) {
      body = CodeLabText(
        note,
        key: ValueKey('mcp-note-$name'),
        role: CodeLabTextRole.caption,
        color: secondary,
      );
    } else {
      final draft = row.draft;
      body = draft == null
          ? null
          : _McpEditor(
              key: ValueKey('mcp-editor-$name-$epoch'),
              initial: draft,
              layer: row.layer,
              state: state,
              saveKey: ValueKey('mcp-save-$name'),
              onSave: onSave,
              extraActions: [
                CodeLabButton(
                  key: ValueKey('mcp-reconnect-$name'),
                  label: 'Reconnect',
                  onPressed: _canReconnect(state.agentStatus)
                      ? () => unawaited(cubit.reconnectServer(name))
                      : null,
                ),
              ],
              trailingActions: [
                CodeLabButton(
                  key: ValueKey('mcp-remove-$name'),
                  label: 'Remove',
                  emphasis: CodeLabButtonEmphasis.danger,
                  onPressed: row.canRemove && !state.saving ? onRemove : null,
                ),
              ],
            );
    }
    return KeyedSubtree(
      key: ValueKey('mcp-row-$name'),
      child: CodeLabExpanderCard(
        leading: Icon(
          row.entry.kind == McpTransportKind.http
              ? FluentIcons.globe
              : FluentIcons.command_prompt,
          size: 16,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CodeLabText(name),
                CodeLabBadge(label: row.entry.kind.name),
                CodeLabBadge(
                  label: row.sourceLabel,
                  tone: row.layer == ConfigLayer.projectLocal
                      ? CodeLabTone.accent
                      : CodeLabTone.neutral,
                ),
              ],
            ),
            CodeLabText(
              row.entry.target,
              role: CodeLabTextRole.mono,
              color: secondary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fromProjectFile)
              CodeLabButton(
                key: ValueKey('mcp-disable-here-$name'),
                label: 'Disable here',
                onPressed: row.canDisableHere && !state.saving
                    ? () => unawaited(cubit.disableHere(name))
                    : null,
              ),
            if (row.canEnableHere)
              CodeLabButton(
                key: ValueKey('mcp-enable-here-$name'),
                label: 'Enable here',
                onPressed: state.saving
                    ? null
                    : () => unawaited(cubit.enableHere(name)),
              ),
            const SizedBox(width: 8),
            ToggleSwitch(
              key: ValueKey('mcp-toggle-$name'),
              checked: row.enabled,
              onChanged: row.canToggle && !state.saving
                  ? (value) => unawaited(cubit.setEnabled(name, enabled: value))
                  : null,
              content: SizedBox(
                width: 24,
                child: Text(row.enabled ? 'On' : 'Off'),
              ),
            ),
          ],
        ),
        expanded: expanded,
        onToggle: onToggle,
        bodyPadding: const EdgeInsets.fromLTRB(52, 16, 16, 16),
        body: body,
      ),
    );
  }
}

/// Переподключение сервера возможно, когда панель знает агента: порт
/// встроенного агента или разрешённый `/mcp reload` (D12).
bool _canReconnect(McpAgentStatus status) => switch (status) {
  McpAgentStatusLive() => true,
  McpAgentStatusText(:final canSend) => canSend,
  McpAgentStatusUnavailable() => false,
};

/// Карточка `New server` в начале списка (Q25 (1)): раскрытый редактор с
/// «Save» и «Cancel», без «Reconnect» и «Remove».
class _NewServerCard extends StatelessWidget {
  const _NewServerCard({
    required this.state,
    required this.onSave,
    required this.onCancel,
  });

  final McpSettingsReady state;
  final _SaveDraft onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('mcp-new'),
      child: CodeLabExpanderCard(
        leading: const Icon(FluentIcons.add, size: 16),
        title: const CodeLabText('New server'),
        expanded: true,
        bodyPadding: const EdgeInsets.fromLTRB(52, 16, 16, 16),
        body: _McpEditor(
          initial: null,
          layer: null,
          state: state,
          saveKey: const ValueKey('mcp-new-save'),
          onSave: onSave,
          extraActions: [
            CodeLabButton(
              key: const ValueKey('mcp-new-cancel'),
              label: 'Cancel',
              onPressed: state.saving ? null : onCancel,
            ),
          ],
          trailingActions: const [],
        ),
      ),
    );
  }
}

/// Строка `env` или `headers` формы.
class _ValueRow {
  _ValueRow({
    required String key,
    required String value,
    required this.secret,
    this.storedRef,
    this.keepRaw,
  }) : key = TextEditingController(text: key),
       value = TextEditingController(text: value);

  final TextEditingController key;
  final TextEditingController value;
  bool secret;

  /// Ссылка `${secret:…}` сохранённого секрета: пустое поле — «не менять».
  String? storedRef;

  /// Сырое значение, которое список скрывает маской (`maskedValues` моста):
  /// поле пусто, пока его не тронули, и тогда пишется это значение.
  final String? keepRaw;

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

/// Редактор сервера (`McpServerDraft`): поля типа, строки `env`/`headers` с
/// флажком «Secret», цель «Save to» и кнопки.
///
/// Почему состояние формы здесь: набранные значения — эфемерный ввод до
/// «Save» (`state-management.md`); Cubit получает готовый черновик и сам
/// проверяет его (`validate(existingNames:)`), страница политику не решает.
/// Ключи полей — `mcp-draft-*` без имени сервера (D11).
class _McpEditor extends StatefulWidget {
  const _McpEditor({
    super.key,
    required this.initial,
    required this.layer,
    required this.state,
    required this.saveKey,
    required this.onSave,
    required this.extraActions,
    required this.trailingActions,
  });

  /// Черновик правки; `null` — новый сервер.
  final McpServerDraft? initial;

  /// Слой существующего сервера (цель «Save to» только для чтения, Q27).
  final ConfigLayer? layer;
  final McpSettingsReady state;
  final Key saveKey;
  final _SaveDraft onSave;
  final List<Widget> extraActions;
  final List<Widget> trailingActions;

  @override
  State<_McpEditor> createState() => _McpEditorState();
}

class _McpEditorState extends State<_McpEditor> {
  /// Подсказка поля со скрытым значением: список его маскирует (D11).
  static const _hiddenHint = 'Hidden — leave empty to keep';

  late final TextEditingController _name;
  late final TextEditingController _command;
  late final TextEditingController _args;
  late final TextEditingController _url;
  late McpTransportKind _kind;
  late ConfigLayer _target;
  late final List<_ValueRow> _env;
  late final List<_ValueRow> _headers;

  /// Текст аргументов как показан изначально: без правки список остаётся
  /// прежним, а не пересобирается разбиением по пробелам.
  late final String _initialArgs;

  /// Поля, значения которых список скрывает (`McpServerDraft.maskedValues`):
  /// редактор не показывает их, пустое поле означает «не менять».
  late final Set<String> _masked;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final draft = widget.initial;
    _masked = draft?.maskedValues ?? const {};
    _name = TextEditingController(text: draft?.name ?? '');
    _command = TextEditingController(
      text: _masked.contains('command') ? '' : draft?.command ?? '',
    );
    _initialArgs = draft?.args.join('\n') ?? '';
    _args = TextEditingController(
      text: _masked.contains('args') ? '' : _initialArgs,
    );
    _url = TextEditingController(
      text: _masked.contains('url') ? '' : draft?.url ?? '',
    );
    _kind = draft?.kind ?? McpTransportKind.stdio;
    _target = widget.layer ?? ConfigLayer.user;
    _env = _rowsOf(draft?.env, 'env', _masked);
    _headers = _rowsOf(draft?.headers, 'headers', _masked);
  }

  static List<_ValueRow> _rowsOf(
    Map<String, McpValueDraft>? table,
    String table0,
    Set<String> masked,
  ) => [
    for (final MapEntry(:key, :value) in (table ?? const {}).entries)
      switch (value) {
        McpTextValue(:final value) when masked.contains('$table0.$key') =>
          _ValueRow(key: key, value: '', secret: false, keepRaw: value),
        McpTextValue(:final value) => _ValueRow(
          key: key,
          value: value,
          secret: false,
        ),
        McpStoredSecret(:final reference) => _ValueRow(
          key: key,
          value: '',
          secret: true,
          storedRef: reference,
        ),
        McpNewSecret() => _ValueRow(key: key, value: '', secret: true),
      },
  ];

  @override
  void dispose() {
    for (final c in [_name, _command, _args, _url]) {
      c.dispose();
    }
    for (final row in [..._env, ..._headers]) {
      row.dispose();
    }
    super.dispose();
  }

  /// Ключи передаются как набраны, без `trim`: пробелы по краям и ключи,
  /// равные после `trim`, — проблемы черновика моста (`validate`). Точно
  /// совпавшие ключи в карте слились бы, поэтому их ловит [_duplicateKey]
  /// до отправки.
  Map<String, McpValueDraft> _tableOf(List<_ValueRow> rows) => {
    for (final row in rows)
      row.key.text: row.secret
          ? (row.storedRef != null && row.value.text.isEmpty
                ? McpValueDraft.stored(row.storedRef!)
                : McpValueDraft.secret(SecretValue(row.value.text)))
          : (row.keepRaw != null && row.value.text.isEmpty
                ? McpValueDraft.text(row.keepRaw!)
                : McpValueDraft.text(row.value.text)),
  };

  /// Первый ключ активной таблицы, набранный дважды точно так же.
  String? _duplicateKey() {
    final seen = <String>{};
    for (final row in _kind == McpTransportKind.http ? _headers : _env) {
      // Строки без имени — проблема моста («Enter a name for every value»).
      if (row.key.text.trim().isNotEmpty && !seen.add(row.key.text)) {
        return row.key.text.trim();
      }
    }
    return null;
  }

  McpServerDraft _draft() {
    final initial = widget.initial;
    final args =
        initial != null &&
            (_args.text == _initialArgs ||
                (_masked.contains('args') && _args.text.isEmpty))
        ? initial.args
        // Один аргумент на строку как есть: пробелы внутри сохраняются, без
        // кавычек и экранирования; пустые строки отбрасываются (решение
        // 2026-11-08).
        : [
            for (final line in _args.text.split(RegExp(r'\r?\n')))
              if (line.isNotEmpty) line,
          ];
    final env = _tableOf(_env);
    final headers = _tableOf(_headers);
    return initial == null
        ? McpServerDraft(
            name: _name.text.trim(),
            kind: _kind,
            command: _command.text.trim(),
            args: args,
            url: _url.text.trim(),
            env: env,
            headers: headers,
          )
        : initial.copyWith(
            kind: _kind,
            command: _masked.contains('command') && _command.text.isEmpty
                ? initial.command
                : _command.text.trim(),
            args: args,
            url: _masked.contains('url') && _url.text.isEmpty
                ? initial.url
                : _url.text.trim(),
            env: env,
            headers: headers,
          );
  }

  Future<void> _save({Set<String> replace = const {}}) async {
    final duplicate = _duplicateKey();
    if (duplicate != null) {
      // Совпавшие ключи слились бы в карте черновика: отказ публикует Cubit.
      context.read<McpSettingsCubit>().rejectDraft(
        server: widget.initial?.name,
        name: widget.initial?.name ?? _name.text.trim(),
        problems: [
          McpDraftProblem(
            _kind == McpTransportKind.http
                ? McpDraftField.headers
                : McpDraftField.env,
            'Two values are named $duplicate.',
          ),
        ],
      );
      return;
    }
    await widget.onSave(_draft(), _target, replace);
  }

  Widget _field(Key key, TextEditingController controller, {String? hint}) =>
      TextBox(
        key: key,
        controller: controller,
        placeholder: hint,
        style: CodeLabText.styleOf(context, CodeLabTextRole.mono),
      );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final storage = state.secretStorage;
    final server = widget.initial?.name;
    final rows = _kind == McpTransportKind.http ? _headers : _env;
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    final busy = state.saving;
    final issues = state.draftIssues?.server == server
        ? state.draftIssues
        : null;
    final question = state.replaceQuestion?.server == server
        ? state.replaceQuestion
        : null;
    final canTargetProject = state.canSaveToProject;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CodeLabForm(
          children: [
            CodeLabFormRow(
              label: 'Name',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: TextBox(
                  key: const ValueKey('mcp-draft-name'),
                  controller: _name,
                  readOnly: !_isNew,
                  style: mono,
                ),
              ),
            ),
            CodeLabFormRow(
              label: 'Type',
              child: RadioGroup<McpTransportKind>(
                groupValue: _kind,
                onChanged: (kind) {
                  if (kind != null) {
                    setState(() => _kind = kind);
                  }
                },
                child: const Row(
                  children: [
                    RadioButton<McpTransportKind>(
                      key: ValueKey('mcp-draft-type-stdio'),
                      value: McpTransportKind.stdio,
                      content: Text('stdio'),
                    ),
                    SizedBox(width: 20),
                    RadioButton<McpTransportKind>(
                      key: ValueKey('mcp-draft-type-http'),
                      value: McpTransportKind.http,
                      content: Text('http'),
                    ),
                  ],
                ),
              ),
            ),
            if (_kind == McpTransportKind.stdio) ...[
              CodeLabFormRow(
                label: 'Command',
                child: _field(
                  const ValueKey('mcp-draft-command'),
                  _command,
                  hint: _masked.contains('command') ? _hiddenHint : null,
                ),
              ),
              CodeLabFormRow(
                label: 'Arguments',
                notes: const [CodeLabFormNote('One argument per line.')],
                child: TextBox(
                  key: const ValueKey('mcp-draft-args'),
                  controller: _args,
                  placeholder: _masked.contains('args') ? _hiddenHint : null,
                  minLines: 2,
                  maxLines: 6,
                  style: CodeLabText.styleOf(context, CodeLabTextRole.mono),
                ),
              ),
            ] else
              CodeLabFormRow(
                label: 'URL',
                child: _field(
                  const ValueKey('mcp-draft-url'),
                  _url,
                  hint: _masked.contains('url') ? _hiddenHint : null,
                ),
              ),
            CodeLabFormRow(
              label: _kind == McpTransportKind.http ? 'Headers' : 'Environment',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _valueRow(rows, i, storage, server),
                  if (!storage.writable)
                    CodeLabFormNote(
                      storage.unavailableReason ??
                          'The secret store is read-only.',
                      tone: CodeLabFormNoteTone.warning,
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: HyperlinkButton(
                      key: const ValueKey('mcp-draft-add-row'),
                      onPressed: () => setState(
                        () => rows.add(
                          _ValueRow(key: '', value: '', secret: false),
                        ),
                      ),
                      child: Text(
                        _kind == McpTransportKind.http
                            ? '+ Add header'
                            : '+ Add variable',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            CodeLabFormRow(
              label: 'Save to',
              notes: [
                if (!_isNew)
                  const CodeLabFormNote(
                    'To move a server to another file, remove it and add it '
                    'again.',
                  ),
              ],
              child: RadioGroup<ConfigLayer>(
                groupValue: _target,
                onChanged: (layer) {
                  if (layer != null && _isNew) {
                    setState(() => _target = layer);
                  }
                },
                child: Wrap(
                  spacing: 20,
                  runSpacing: 6,
                  children: [
                    RadioButton<ConfigLayer>(
                      key: const ValueKey('mcp-draft-target-user'),
                      value: ConfigLayer.user,
                      enabled: _isNew,
                      content: const Text('User config'),
                    ),
                    RadioButton<ConfigLayer>(
                      key: const ValueKey('mcp-draft-target-local'),
                      value: ConfigLayer.projectLocal,
                      enabled: _isNew && canTargetProject,
                      content: const Text('This project only'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (issues != null)
          for (final problem in issues.problems)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CodeLabFormNote(
                problem.message,
                tone: CodeLabFormNoteTone.error,
              ),
            ),
        if (question != null) _replaceQuestion(question, secondary),
        const SizedBox(height: 18),
        Row(
          children: [
            CodeLabButton(
              key: widget.saveKey,
              label: 'Save',
              emphasis: CodeLabButtonEmphasis.primary,
              onPressed: busy ? null : () => unawaited(_save()),
            ),
            for (final action in widget.extraActions) ...[
              const SizedBox(width: 8),
              action,
            ],
            const Spacer(),
            ...widget.trailingActions,
          ],
        ),
      ],
    );
  }

  Widget _valueRow(
    List<_ValueRow> rows,
    int i,
    McpSecretStorage storage,
    String? server,
  ) {
    final row = rows[i];
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    final serverName = server ?? _name.text.trim();
    final key = row.key.text.trim();
    final secretName = serverName.isEmpty || key.isEmpty
        ? null
        : McpSettingsCubit.secretNameFor(serverName, key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 10, // Артборд: колонки ключа и значения 1fr : 1.4fr.
                child: TextBox(
                  key: ValueKey('mcp-draft-key-$i'),
                  controller: row.key,
                  placeholder: 'Name',
                  style: mono,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 14,
                child: row.secret
                    ? PasswordBox(
                        key: ValueKey('mcp-draft-value-$i'),
                        controller: row.value,
                        placeholder: row.storedRef == null
                            ? 'Secret value'
                            : 'stored',
                      )
                    : TextBox(
                        key: ValueKey('mcp-draft-value-$i'),
                        controller: row.value,
                        placeholder: row.keepRaw != null
                            ? _hiddenHint
                            : 'Value',
                        style: mono,
                      ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey('mcp-draft-remove-row-$i'),
                icon: const Icon(FluentIcons.cancel, size: 12),
                onPressed: () => setState(() {
                  rows.removeAt(i).dispose();
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Checkbox(
            key: ValueKey('mcp-draft-secret-$i'),
            checked: row.secret,
            onChanged: storage.writable
                ? (value) => setState(() {
                    row.secret = value ?? false;
                    if (!row.secret) {
                      row.storedRef = null;
                    }
                  })
                : null,
            content: Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Secret — stored in ${storage.backendId}'),
                    if (secretName != null) ...[
                      const TextSpan(text: ' as '),
                      TextSpan(text: secretName, style: mono),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// «Replace it»: секрет с этим именем уже есть, перезапись — только по
  /// явному выбору (SETUP-5).
  Widget _replaceQuestion(McpReplaceQuestion question, Color secondary) {
    final cubit = context.read<McpSettingsCubit>();
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InfoBar(
        key: const ValueKey('mcp-replace-secret'),
        severity: InfoBarSeverity.warning,
        isLong: true,
        title: const Text('A secret with this name is already stored'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final name in question.names) Text(name, style: mono),
            const SizedBox(height: 4),
            const Text(
              'The new value replaces the secret for every server that '
              'refers to it.',
            ),
            const Text(
              'A running agent keeps the old value until the server '
              'reconnects.',
            ),
          ],
        ),
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CodeLabButton(
              key: const ValueKey('mcp-replace-confirm'),
              label: 'Replace it',
              onPressed: () =>
                  unawaited(_save(replace: question.names.toSet())),
            ),
            const SizedBox(width: 8),
            CodeLabButton(
              key: const ValueKey('mcp-replace-keep'),
              label: 'Keep it',
              onPressed: cubit.dismissReplaceQuestion,
            ),
          ],
        ),
      ),
    );
  }
}

/// Панель «Agent status» (артборд `Mcp`): живая таблица встроенного агента
/// или текст `/mcp list` агента вне процесса (D12, Q23).
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status});

  final McpAgentStatus status;

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  static CodeLabStatusTone _tone(McpServerState state) => switch (state) {
    McpServerState.connected => CodeLabStatusTone.active,
    McpServerState.connecting => CodeLabStatusTone.warning,
    McpServerState.failed => CodeLabStatusTone.danger,
    McpServerState.disabled => CodeLabStatusTone.idle,
  };

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<McpSettingsCubit>();
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    final Widget caption;
    final List<Widget> actions;
    final Widget body;
    switch (status) {
      case McpAgentStatusUnavailable():
        caption = const SizedBox.shrink();
        actions = const [];
        body = CodeLabText(
          'Open a session to see live status',
          key: const ValueKey('mcp-status-unavailable'),
          color: secondary,
        );
      case McpAgentStatusLive(:final rows, :final updatedAt):
        caption = CodeLabStatusIndicator(
          label: 'Live from the embedded agent · ${_clock(updatedAt)}',
          tone: CodeLabStatusTone.active,
        );
        actions = [
          CodeLabButton(
            key: const ValueKey('mcp-status-reload-all'),
            label: 'Reload all',
            onPressed: () => unawaited(cubit.reloadAll()),
          ),
        ];
        body = CodeLabStatusTable(
          columns: const ['SERVER', 'STATE', 'TOOLS', 'LAST ERROR'],
          rows: [
            for (final row in rows)
              CodeLabStatusTableRow(
                key: ValueKey('mcp-status-row-${row.name}'),
                cells: [
                  CodeLabStatusTableCell(row.name, mono: true),
                  CodeLabStatusTableCell(
                    row.stateLabel,
                    tone: _tone(row.state),
                  ),
                  CodeLabStatusTableCell(row.tools, muted: row.tools == '—'),
                  CodeLabStatusTableCell(
                    row.lastError,
                    mono: row.lastError != '—',
                    muted: row.lastError == '—',
                  ),
                ],
                action: row.canReconnect
                    ? CodeLabStatusTableAction(
                        key: ValueKey('mcp-status-reconnect-${row.name}'),
                        label: 'Reconnect',
                        onPressed: () =>
                            unawaited(cubit.reconnectServer(row.name)),
                      )
                    : null,
              ),
          ],
        );
      case McpAgentStatusText(:final text, :final canSend, :final notice):
        caption = const SizedBox.shrink();
        actions = [
          CodeLabButton(
            key: const ValueKey('mcp-status-refresh'),
            label: 'Refresh',
            onPressed: canSend ? () => unawaited(cubit.refresh()) : null,
          ),
          const SizedBox(width: 8),
          CodeLabButton(
            key: const ValueKey('mcp-status-reload-all'),
            label: 'Reload all',
            onPressed: canSend ? () => unawaited(cubit.reloadAll()) : null,
          ),
        ];
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: CodeLabText(
                  notice,
                  key: const ValueKey('mcp-status-notice'),
                  role: CodeLabTextRole.caption,
                  color: secondary,
                ),
              ),
            if (text != null)
              CodeLabMonospaceBlock(
                text,
                key: const ValueKey('mcp-status-text'),
              ),
          ],
        );
    }
    return KeyedSubtree(
      key: const ValueKey('mcp-status'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const Expanded(
                  child: CodeLabText(
                    'Agent status',
                    role: CodeLabTextRole.strong,
                  ),
                ),
                caption,
                if (actions.isNotEmpty) const SizedBox(width: 12),
                ...actions,
              ],
            ),
          ),
          body,
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: CodeLabText(
              'From the embedded agent. For a stdio or remote agent this '
              'panel shows the reply of /mcp list as text.',
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }
}
