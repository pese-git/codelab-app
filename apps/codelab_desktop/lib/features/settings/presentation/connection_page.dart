import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../application/connection_settings_cubit.dart';
import 'add_profile_dialog.dart';

/// Тело страницы «Connection» для таблицы `settingsPageBuilders`.
///
/// Почему отдельный виджет-хозяин: Cubit страницы создаётся на каждое открытие
/// (файл профилей перечитывается при открытии, D4), а построитель таблицы —
/// просто функция от `BuildContext`.
Widget buildConnectionPage(BuildContext context) => const ConnectionPageHost();

/// Создаёт `ConnectionSettingsCubit` страницы, читает файл и закрывает Cubit
/// вместе со страницей.
///
/// Почему не виджет, создающий репозитории: Cubit собирает composition root
/// (`CodeLabDependencies.createConnectionSettingsCubit`); здесь он только
/// получает владельца жизненного цикла (AGENTS.md §6: виджет не создаёт
/// зависимостей).
class ConnectionPageHost extends StatefulWidget {
  const ConnectionPageHost({super.key});

  @override
  State<ConnectionPageHost> createState() => _ConnectionPageHostState();
}

class _ConnectionPageHostState extends State<ConnectionPageHost> {
  ConnectionSettingsCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit == null) {
      final cubit = codeLabDependenciesOf(
        context,
      ).createConnectionSettingsCubit();
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
      BlocProvider.value(value: _cubit!, child: const ConnectionPage());
}

/// Страница настроек «Connection»: профили подключения и блок «Behavior»
/// (макет `docs/design/claude-design/Connection.dc.html`; расхождения и их
/// решения — design.md change `add-app-settings-shell`, D20).
///
/// Почему: подключение окна к агенту — настройка app, а не диалог из сайдбара;
/// профили общие с CLI (spec app-settings «Список профилей на странице
/// «Connection»»).
///
/// Для чего: только отображение состояния `ConnectionSettingsCubit`. Что
/// доступно (Remove, Restart), решает Cubit (`canRemove`, `canRestart`);
/// страница получает решение пользователя и вызывает его методы. Значение
/// токена здесь недоступно: строка показывает только источник.
///
/// Как использовать: `Cubit` берётся из `BlocProvider` выше по дереву.
/// «Add profile» открывает диалог (`showAddProfileDialog`) с Cubit-ом из
/// composition root; «Rename» строки вызывает `ConnectionSettingsCubit`.
/// Проверки профиля на странице нет: профиль проверяет «Use» и старт агента
/// (change `remove-test-connection`, D1, D4). Правка имени идёт в самой строке: открытый
/// редактор — эфемерное состояние страницы.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  /// Раскрытие справки — эфемерное состояние виджета (`state-management.md`).
  var _helpExpanded = false;

  /// Строка, в которой открыт редактор «Rename»; эфемерное состояние
  /// виджета, как и справка.
  String? _renamingId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionSettingsCubit, ConnectionSettingsState>(
      builder: (context, state) {
        final cubit = context.read<ConnectionSettingsCubit>();
        return switch (state) {
          ConnectionSettingsLoading() => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: ProgressRing()),
          ),
          ConnectionSettingsLoaded() => _content(context, cubit, state),
        };
      },
    );
  }

  Widget _content(
    BuildContext context,
    ConnectionSettingsCubit cubit,
    ConnectionSettingsLoaded state,
  ) {
    final ready = state is ConnectionSettingsReady ? state : null;
    final rows = state.rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: CodeLabText('Connection', role: CodeLabTextRole.title),
            ),
            // В CommandBar только «Add profile»: «Restart agent» стоит рядом
            // со своим объяснением в блоке «Behavior» (D9).
            CodeLabButton(
              key: const ValueKey('connection-add-profile'),
              label: 'Add profile',
              icon: FluentIcons.add,
              emphasis: CodeLabButtonEmphasis.primary,
              onPressed: ready == null
                  ? null
                  : () => unawaited(_addProfile(cubit)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (state is ConnectionSettingsUnreadable)
          _bar(
            const ValueKey('connection-profiles-unreadable'),
            InfoBarSeverity.error,
            switch (state.path) {
              final path? =>
                'Cannot read $path: ${state.reason}. Fix or remove the '
                    'file; CodeLab will not overwrite it.',
              null => 'Cannot use the profiles: ${state.reason}.',
            },
          ),
        if (state.failure case final failure?)
          _bar(
            const ValueKey('connection-failure'),
            InfoBarSeverity.error,
            failure,
          ),
        if (state.showsReadOnlyNotice)
          _bar(
            const ValueKey('connection-remote-read-only'),
            InfoBarSeverity.warning,
            'Read-only: this agent runs on ${state.remoteOrigin}',
            content:
                'Change providers and MCP on that host: codelab provider add, '
                'codelab mcp add, codelab config set.',
          ),
        if (ready != null && ready.ignoredDefaultEntry)
          _bar(
            const ValueKey('connection-profiles-ignored-default'),
            InfoBarSeverity.warning,
            'Profile "default" in profiles.json is ignored: default is the '
            'built-in agent. Remove it with codelab profiles remove default.',
            action: CodeLabButton(
              label: 'Remove',
              onPressed: () => unawaited(_removeIgnoredDefault(cubit)),
            ),
          ),
        CodeLabSettingsSection(
          title: 'Profiles',
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: CodeLabText(
                'Shared with codelab_cli through profiles.json in '
                r'$CODELAB_HOME. The default profile is used when the '
                'agent starts, until you choose another with Use.',
                role: CodeLabTextRole.caption,
              ),
            ),
            // Радиокнопки строк образуют одну группу: выбранная — профиль по
            // умолчанию, а не текущий; «Use» профиль по умолчанию не
            // меняет (D5, D18).
            RadioGroup<String>(
              groupValue: switch (state) {
                ConnectionSettingsReady(:final defaultProfileId) =>
                  defaultProfileId,
                ConnectionSettingsUnreadable() => rows.first.id,
              },
              onChanged: (id) {
                if (id != null) {
                  unawaited(cubit.selectDefault(id));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in rows) ...[
                    if (row != rows.first) const SizedBox(height: 4),
                    _ProfileRowCard(
                      row: row,
                      editable: ready != null,
                      onUse: () => unawaited(cubit.use(row.id)),
                      renaming: _renamingId == row.id,
                      onStartRename: () => setState(() => _renamingId = row.id),
                      onCancelRename: () => setState(() => _renamingId = null),
                      onSaveRename: (label) =>
                          unawaited(_renameProfile(cubit, row.id, label)),
                      onRemove: () => unawaited(_removeProfile(cubit, row)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        // «Behavior» не зависит от `profiles.json` и есть в любом состоянии
        // (D4).
        CodeLabSettingsSection(
          title: 'Behavior',
          children: [_restartRow(cubit, state)],
        ),
        const SizedBox(height: 12),
        CodeLabExpanderCard(
          // Ключ — на нажимаемом заголовке, а не на всей карточке: по нему
          // автотест раскрывает справку.
          headerKey: const ValueKey('connection-join-cli-help'),
          leading: const Icon(FluentIcons.command_prompt, size: 16),
          title: const CodeLabText('Join a session started in the CLI'),
          expanded: _helpExpanded,
          onToggle: (value) => setState(() => _helpExpanded = value),
          // Справка без замка, режима «только чтение» и «Fork»: lease не
          // реализован (D10).
          body: _helpExpanded
              ? const CodeLabText(
                  'On the host run codelab-agent serve --ws <port>; the CLI '
                  'connects with codelab -a <profile>. Choose the same '
                  'WebSocket profile here; its sessions appear in the '
                  'sidebar.',
                  role: CodeLabTextRole.caption,
                )
              : null,
        ),
      ],
    );
  }

  Widget _restartRow(
    ConnectionSettingsCubit cubit,
    ConnectionSettingsLoaded state,
  ) {
    return CodeLabSettingsRow(
      key: const ValueKey('connection-restart-row'),
      title: state.restartTitle,
      // Честный текст о переподключении цели без обещания `session/cancel`
      // (D9).
      description: state.restartHint ?? state.restartDescription,
      leading: FluentIcons.refresh,
      trailing: CodeLabButton(
        key: const ValueKey('connection-restart-agent'),
        label: state.restartButtonLabel,
        onPressed: state.canRestart
            ? () => unawaited(cubit.restartAgent())
            : null,
      ),
    );
  }

  Widget _bar(
    Key key,
    InfoBarSeverity severity,
    String title, {
    String? content,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InfoBar(
      key: key,
      title: Text(title),
      content: content == null ? null : Text(content),
      severity: severity,
      action: action,
      isLong: true,
    ),
  );

  /// «Add profile»: диалог с собственным Cubit-ом (D12).
  ///
  /// Cubit живёт ровно столько, сколько диалог: закрытие диалога любым
  /// способом (Done, Cancel, Esc) закрывает Cubit. Если профиль записан,
  /// страница перечитывает файл.
  Future<void> _addProfile(ConnectionSettingsCubit settings) async {
    final add = codeLabDependenciesOf(context).createAddProfileCubit();
    unawaited(add.start());
    await showAddProfileDialog(context, add);
    // Профилей за жизнь диалога может быть несколько («Add another»), и
    // закрыт он мог быть любым способом: перечитываются все записанные, а не
    // только последний из состояния (M1).
    final saved = add.savedProfiles;
    await add.close();
    if (!mounted) {
      return;
    }
    if (saved.isNotEmpty) {
      await settings.profilesChanged();
    }
  }

  Future<void> _renameProfile(
    ConnectionSettingsCubit cubit,
    String id,
    String label,
  ) async {
    final renamed = await cubit.renameProfile(id, label);
    if (renamed && mounted) {
      setState(() => _renamingId = null);
    }
  }

  /// Подтверждение и удаление: решение — за пользователем, запрет удаления
  /// текущего и встроенного — за Cubit (проверяется и при прямом вызове).
  Future<void> _removeProfile(
    ConnectionSettingsCubit cubit,
    ConnectionProfileRow row,
  ) async {
    final decision = await _confirmRemove(
      title: 'Remove profile ${row.title}?',
      details:
          'The entry is deleted from profiles.json. Environment variables '
          'and other settings are not touched.',
      // Флажок только у собственного секрета профиля; чужой секрет («Use
      // stored secret») не удаляется никогда (design.md change
      // `add-provider-setup-ui`, D14).
      ownSecret: row.ownTokenSecret,
    );
    if (decision.confirmed && mounted) {
      await cubit.removeProfile(row.id, deleteOwnSecret: decision.deleteSecret);
    }
  }

  Future<void> _removeIgnoredDefault(ConnectionSettingsCubit cubit) async {
    final decision = await _confirmRemove(
      title: 'Remove the ignored "default" profile?',
      details:
          'Only the "default" entry is deleted from profiles.json; other '
          'profiles stay.',
    );
    if (decision.confirmed && mounted) {
      await cubit.removeIgnoredDefault();
    }
  }

  /// Диалог подтверждения «Remove». [ownSecret] — имя собственного секрета
  /// токена профиля: тогда показывается флажок «Also delete the stored
  /// token …», по умолчанию включённый (§12.4.9, шаг 8). Что с секретом
  /// делать и можно ли, решает `ProfileCommitter`, виджет передаёт только
  /// выбор пользователя.
  Future<({bool confirmed, bool deleteSecret})> _confirmRemove({
    required String title,
    required String details,
    String? ownSecret,
  }) async {
    var deleteSecret = ownSecret != null;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: CodeLabDialogTitle(title),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(details),
              if (ownSecret != null) ...[
                const SizedBox(height: 12),
                Checkbox(
                  key: const ValueKey('connection-remove-delete-token'),
                  checked: deleteSecret,
                  onChanged: (value) =>
                      setDialogState(() => deleteSecret = value ?? false),
                  content: Flexible(
                    child: Text('Also delete the stored token $ownSecret'),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          Button(
            key: const ValueKey('connection-remove-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('connection-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    final confirmed = result ?? false;
    return (confirmed: confirmed, deleteSecret: confirmed && deleteSecret);
  }
}

/// Карточка одной строки профиля.
class _ProfileRowCard extends StatelessWidget {
  const _ProfileRowCard({
    required this.row,
    required this.editable,
    required this.onUse,
    required this.renaming,
    required this.onStartRename,
    required this.onCancelRename,
    required this.onSaveRename,
    required this.onRemove,
  });

  final ConnectionProfileRow row;

  /// Файл прочитан: «Rename» и «Remove» доступны (битый файл не трогаем).
  final bool editable;
  final VoidCallback onUse;

  /// Открыт редактор «Rename» этой строки.
  final bool renaming;
  final VoidCallback onStartRename;
  final VoidCallback onCancelRename;
  final ValueChanged<String> onSaveRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final id = row.id;
    final token = row.token;

    return DecoratedBox(
      key: ValueKey('connection-profile-row-$id'),
      decoration: BoxDecoration(
        color: resources.cardBackgroundFillColorDefault,
        border: Border.all(
          color: row.isCurrent
              ? FluentTheme.of(context).accentColor
              : resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Радиокнопка выбирает профиль по умолчанию, а не текущий:
                // «Use» профиль по умолчанию не меняет (D5, D18).
                RadioButton<String>(
                  key: ValueKey('connection-profile-default-$id'),
                  value: id,
                  enabled: !row.isUnsaved,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (renaming)
                        _RenameEditor(
                          // Id в ключе: у каждой строки свой редактор.
                          key: ValueKey('connection-profile-rename-editor-$id'),
                          id: id,
                          initial: row.label,
                          onSave: onSaveRename,
                          onCancel: onCancelRename,
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Одна строка с многоточием; полный текст — в
                            // подсказке (D4).
                            Tooltip(
                              message: row.title,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                child: Text(
                                  row.title,
                                  key: ValueKey('connection-profile-title-$id'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FluentTheme.of(
                                    context,
                                  ).typography.bodyStrong,
                                ),
                              ),
                            ),
                            if (row.isDefault)
                              const CodeLabBadge(
                                label: 'Default',
                                tone: CodeLabTone.accent,
                              ),
                            if (row.isCurrent)
                              const CodeLabBadge(
                                label: 'Current',
                                tone: CodeLabTone.success,
                              ),
                            if (row.isSelected)
                              const CodeLabBadge(
                                label: 'Selected',
                                tone: CodeLabTone.accent,
                              ),
                            // Состояние соединения окна — без текста ошибки: её
                            // показывает баннер рабочего места (D4).
                            if (row.status case final status?)
                              KeyedSubtree(
                                key: ValueKey('connection-profile-status-$id'),
                                child: CodeLabBadge(
                                  label: status.label,
                                  tone: switch (status) {
                                    ConnectionRowStatus.connecting =>
                                      CodeLabTone.warning,
                                    ConnectionRowStatus.connected =>
                                      CodeLabTone.success,
                                    ConnectionRowStatus.failed =>
                                      CodeLabTone.danger,
                                  },
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 2),
                      if (row.isUnsaved)
                        const CodeLabText(
                          'Current connection (not saved)',
                          role: CodeLabTextRole.caption,
                        ),
                      CodeLabText(row.summary, role: CodeLabTextRole.caption),
                      if (token != null)
                        Column(
                          key: ValueKey('connection-profile-token-$id'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _tokenTexts(token),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // «Use» выбирает профиль для следующего старта и агента не
                // трогает (D18); у выбранного профиля вместо него метка
                // «Selected». Ручного Connect нет.
                if (row.canUse)
                  CodeLabButton(
                    key: ValueKey('connection-profile-use-$id'),
                    label: 'Use',
                    emphasis: CodeLabButtonEmphasis.primary,
                    onPressed: onUse,
                  ),
                if (row.hasFileActions)
                  CodeLabButton(
                    key: ValueKey('connection-profile-rename-$id'),
                    label: 'Rename',
                    onPressed: editable && !renaming ? onStartRename : null,
                  ),
                if (row.hasFileActions) _removeButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// «Remove»: недоступна у текущего и выбранного профиля с подсказкой `Use
  /// another profile first.` (spec app-settings, D18); решение о доступности
  /// принимает Cubit (`canRemove`).
  Widget _removeButton() {
    final button = CodeLabButton(
      key: ValueKey('connection-profile-remove-${row.id}'),
      label: 'Remove',
      onPressed: editable && row.canRemove ? onRemove : null,
    );
    return row.isCurrent || row.isSelected
        ? Tooltip(message: 'Use another profile first.', child: button)
        : button;
  }

  /// Источник токена: только имя переменной или ссылки, без значения (D13).
  static List<Widget> _tokenTexts(ProfileTokenView token) => switch (token) {
    NoTokenView() => const [
      CodeLabText('No token', role: CodeLabTextRole.caption),
    ],
    EnvTokenView(:final name, :final isSet) => [
      CodeLabText('From \$$name', role: CodeLabTextRole.caption),
      if (!isSet)
        CodeLabText(
          "$name is not set in CodeLab's environment.",
          role: CodeLabTextRole.caption,
        ),
    ],
    SecretTokenView(:final name, :final backend, :final isSet) => [
      // Имя секрета — текст, а не редактируемое поле: правки профиля в 1.0
      // нет (D24). Наличие определено без чтения значения.
      CodeLabText('Token secret $name', role: CodeLabTextRole.caption),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: CodeLabBadge(
            label: '$backend · ${isSet ? 'set' : 'missing'}',
            tone: isSet ? CodeLabTone.success : CodeLabTone.warning,
          ),
        ),
      ),
    ],
    UnsupportedTokenView() => const [
      CodeLabText(
        'unrecognized token reference (not supported in this version)',
        role: CodeLabTextRole.caption,
      ),
    ],
  };
}

/// Редактор «Rename» в строке профиля: имя, «Save» и «Cancel».
///
/// Почему в строке, а не диалогом: меняется одно поле, и подпись должна
/// оставаться рядом со строкой (design.md change `add-app-settings-shell`,
/// D14). Контроллер принадлежит State и освобождается в `dispose`.
///
/// Для чего: собирает ввод; пустое имя не сохраняется (кнопка недоступна), а
/// запись и отклонение пустого имени повторяет Cubit. Начальное значение —
/// `label` профиля, как он записан в файле.
class _RenameEditor extends StatefulWidget {
  const _RenameEditor({
    required this.id,
    required this.initial,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  final String id;
  final String initial;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;

  @override
  State<_RenameEditor> createState() => _RenameEditorState();
}

class _RenameEditorState extends State<_RenameEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _controller.text.trim();
    return Row(
      children: [
        Expanded(
          child: TextBox(
            key: ValueKey('connection-profile-rename-field-${widget.id}'),
            controller: _controller,
            autofocus: true,
            placeholder: 'Name',
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (name.isNotEmpty) {
                widget.onSave(name);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        CodeLabButton(
          key: ValueKey('connection-profile-rename-save-${widget.id}'),
          label: 'Save',
          emphasis: CodeLabButtonEmphasis.primary,
          onPressed: name.isEmpty ? null : () => widget.onSave(name),
        ),
        const SizedBox(width: 8),
        CodeLabButton(
          key: ValueKey('connection-profile-rename-cancel-${widget.id}'),
          label: 'Cancel',
          onPressed: widget.onCancel,
        ),
      ],
    );
  }
}
