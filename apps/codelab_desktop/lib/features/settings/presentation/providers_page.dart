import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../application/provider_settings_cubit.dart';
import 'provider_wizard_dialog.dart';

/// Тело страницы «Providers» для таблицы `settingsPageBuilders`.
///
/// Почему отдельный хозяин: Cubit страницы создаётся на каждое открытие
/// (снимок `config.yaml` перечитывается при открытии, design.md change
/// `add-provider-setup-ui`, D10), а построитель таблицы — просто функция от
/// `BuildContext`.
Widget buildProvidersPage(BuildContext context) => const ProvidersPageHost();

/// Создаёт `ProviderSettingsCubit`, читает снимок и закрывает Cubit вместе со
/// страницей.
///
/// Почему не виджет, создающий зависимости: Cubit собирает composition root
/// (`CodeLabDependencies.createProviderSettingsCubit`); здесь он только
/// получает владельца жизненного цикла (AGENTS.md §6). Закрытие страницы
/// закрывает Cubit и тем отбрасывает итоги идущих проверок (D21).
class ProvidersPageHost extends StatefulWidget {
  const ProvidersPageHost({super.key});

  @override
  State<ProvidersPageHost> createState() => _ProvidersPageHostState();
}

class _ProvidersPageHostState extends State<ProvidersPageHost> {
  ProviderSettingsCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit == null) {
      final cubit = codeLabDependenciesOf(
        context,
      ).createProviderSettingsCubit();
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
      BlocProvider.value(value: _cubit!, child: const ProvidersPage());
}

/// Страница настроек «Providers» (артборд
/// `docs/design/claude-design/Providers.dc.html`; расхождения — design.md
/// change `add-provider-setup-ui`, D24).
///
/// Почему: провайдеры LLM — настройка агента, а не диалог из ленты; конфиг
/// общий с CLI (`codelab provider add`), поэтому страница показывает файл
/// агента, а не собственное хранилище (spec app-settings «Страница
/// «Providers»»).
///
/// Для чего: только отображение состояния [ProviderSettingsCubit]. Что можно
/// удалить, какой слой писать и опасно ли действие — решает Cubit и мост
/// `codelab_setup`; страница получает решение пользователя (подтверждение
/// удаления, выбор модели) и вызывает методы Cubit. Значения ключей здесь
/// недоступны: строка показывает статус и имя (SETUP-1).
///
/// Как использовать: Cubit берётся из `BlocProvider` выше по дереву. «Add
/// provider» и «Edit» открывают `ProviderWizardDialog` на автомате, который
/// строит Cubit страницы (`openWizard`); после записи страница показывает
/// баннер мастера и перечитывает снимок. Раскрытие строк — эфемерное
/// состояние виджета.
class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key});

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  /// Раскрытые строки (id) — эфемерное состояние виджета (`state-management.md`).
  final _expanded = <String>{};

  /// Открывает мастер: добавление или правка [editId]. Владелец Cubit мастера
  /// — эта страница: после закрытия диалога она закрывает его (отмена
  /// проверки, сброс ключа) и при записи показывает баннер.
  Future<void> _openWizard({String? editId}) async {
    final cubit = context.read<ProviderSettingsCubit>();
    final wizard = await cubit.openWizard(editId: editId);
    if (wizard == null || !mounted) {
      await wizard?.close();
      return;
    }
    await showProviderWizardDialog(context, wizard);
    final banner = wizard.savedBanner;
    await wizard.close();
    if (banner != null && !cubit.isClosed) {
      await cubit.wizardSaved(banner);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderSettingsCubit, ProviderSettingsState>(
      builder: (context, state) => KeyedSubtree(
        key: const ValueKey('settings-providers'),
        child: switch (state) {
          ProviderSettingsLoading() => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: ProgressRing()),
          ),
          ProviderSettingsReadOnly() => _readOnly(state),
          ProviderSettingsUnreadable() => _unreadable(state),
          ProviderSettingsReady() => _ready(context, state),
        },
      ),
    );
  }

  Widget _header({required bool withAdd}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        const Expanded(
          child: CodeLabText('Providers', role: CodeLabTextRole.title),
        ),
        if (withAdd)
          CodeLabButton(
            key: const ValueKey('providers-add'),
            label: 'Add provider',
            icon: FluentIcons.add,
            emphasis: CodeLabButtonEmphasis.primary,
            onPressed: () => unawaited(_openWizard()),
          ),
      ],
    ),
  );

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
      isLong: true,
      action: action,
    ),
  );

  Widget _activeModelRow(String model) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: CodeLabSettingsRow(
      key: const ValueKey('providers-active-model'),
      title: 'Default model',
      description: 'Active in this session: $model',
      leading: FluentIcons.settings,
    ),
  );

  Widget _readOnly(ProviderSettingsReadOnly state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(withAdd: false),
      _bar(
        const ValueKey('providers-read-only'),
        InfoBarSeverity.warning,
        state.notice,
        content: state.hint,
      ),
      if (state.activeModel case final model?) _activeModelRow(model),
    ],
  );

  Widget _unreadable(ProviderSettingsUnreadable state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(withAdd: false),
      _bar(
        const ValueKey('providers-unreadable'),
        InfoBarSeverity.error,
        'Cannot read the agent config. Fix or remove the file; CodeLab will '
        'not overwrite it.',
        content: state.problems.join('\n'),
      ),
      if (state.activeModel case final model?) _activeModelRow(model),
    ],
  );

  Widget _ready(BuildContext context, ProviderSettingsReady state) {
    final cubit = context.read<ProviderSettingsCubit>();
    final resources = FluentTheme.of(context).resources;
    final storage = state.keyStorage;
    final body = CodeLabText.styleOf(context, CodeLabTextRole.body);
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    final secondary = resources.textFillColorSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(withAdd: true),
        if (state.banner case final banner?)
          _bar(
            const ValueKey('providers-banner'),
            switch (banner.kind) {
              ProviderBannerKind.saved => InfoBarSeverity.success,
              ProviderBannerKind.conflict => InfoBarSeverity.warning,
              ProviderBannerKind.error => InfoBarSeverity.error,
            },
            banner.text,
            action: switch (banner.action) {
              ProviderBannerAction.retry => CodeLabButton(
                key: const ValueKey('providers-banner-retry'),
                label: 'Retry',
                icon: FluentIcons.refresh,
                onPressed: () => unawaited(cubit.retryAgentStart()),
              ),
              null => null,
            },
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: CodeLabSettingsRow(
            title: 'Default model',
            description: [
              'Used by new sessions.',
              if (state.activeModel case final model?)
                'Active in this session: $model',
            ].join(' '),
            leading: FluentIcons.settings,
            trailing: SizedBox(
              width: 260,
              child: ComboBox<String>(
                key: const ValueKey('providers-default-model'),
                isExpanded: true,
                value: state.models.contains(state.defaultModel)
                    ? state.defaultModel
                    : null,
                placeholder: const Text('Choose a model'),
                items: [
                  for (final model in state.models)
                    ComboBoxItem<String>(value: model, child: Text(model)),
                ],
                onChanged: state.saving
                    ? null
                    : (model) {
                        if (model != null) {
                          unawaited(cubit.setDefaultModel(model));
                        }
                      },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: CodeLabSettingsRow(
            key: const ValueKey('providers-key-storage'),
            title: 'Key storage: ${storage.backendId}',
            description:
                'Only key names and presence are read — values never enter '
                'the app',
            leading: FluentIcons.permissions,
            trailing: CodeLabBadge(
              label: storage.writable ? 'writable' : 'read-only',
              tone: storage.writable
                  ? CodeLabTone.success
                  : CodeLabTone.warning,
            ),
          ),
        ),
        if (storage.openFilePath case final path?)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: CodeLabText(
              'Keys are stored in an open file $path (mode 0600).',
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
          ),
        if (storage.unavailableReason case final reason?)
          _bar(
            const ValueKey('providers-store-unavailable'),
            InfoBarSeverity.info,
            reason,
          ),
        const Padding(
          padding: EdgeInsets.only(top: 18, bottom: 4),
          child: CodeLabText(
            'Configured providers',
            role: CodeLabTextRole.strong,
          ),
        ),
        if (state.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: CodeLabText(
                    'No providers yet. The embedded agent needs one to run a '
                    'turn.',
                    key: ValueKey('providers-empty'),
                  ),
                ),
                CodeLabButton(
                  key: const ValueKey('providers-empty-add'),
                  label: 'Add provider',
                  icon: FluentIcons.add,
                  onPressed: () => unawaited(_openWizard()),
                ),
              ],
            ),
          )
        else
          for (final row in state.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _ProviderCard(
                row: row,
                expanded: _expanded.contains(row.id),
                busy: state.saving,
                onToggle: (open) => setState(() {
                  if (open) {
                    _expanded.add(row.id);
                  } else {
                    _expanded.remove(row.id);
                  }
                }),
                onCheck: () => unawaited(cubit.check(row.id)),
                onEdit: () => unawaited(_openWizard(editId: row.id)),
                onRemove: () => unawaited(_confirmRemove(cubit, row.id)),
                bodyStyle: body,
                monoStyle: mono,
              ),
            ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: CodeLabText.styleOf(
              context,
              CodeLabTextRole.caption,
            )?.copyWith(color: secondary),
            children: [
              const TextSpan(text: 'Config file: '),
              TextSpan(text: state.configPath, style: mono),
            ],
          ),
        ),
        CodeLabText(
          'Remove asks to confirm with “Also delete the stored key”; removing '
          'the default provider asks for a “New default model”. Rows defined '
          'in the project file are not editable here.',
          role: CodeLabTextRole.caption,
          color: secondary,
        ),
      ],
    );
  }

  /// «Remove»: подтверждение `Remove provider <id>?` с флажком и выбором новой
  /// модели по умолчанию; решение о том, что допустимо, остаётся у Cubit.
  Future<void> _confirmRemove(ProviderSettingsCubit cubit, String id) async {
    final plan = cubit.removalPlan(id);
    if (plan == null) {
      return;
    }
    var deleteKey = plan.offersKeyDeletion;
    String? newDefault;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => ContentDialog(
          title: CodeLabDialogTitle('Remove provider $id?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The provider is removed from the config file. Sessions that '
                'use its models keep running until the agent reloads.',
              ),
              if (plan.offersKeyDeletion) ...[
                const SizedBox(height: 12),
                Checkbox(
                  key: const ValueKey('providers-remove-delete-key'),
                  checked: deleteKey,
                  onChanged: (value) =>
                      setDialogState(() => deleteKey = value ?? false),
                  content: const Flexible(
                    child: Text('Also delete the stored key'),
                  ),
                ),
              ],
              if (plan.needsNewDefault) ...[
                const SizedBox(height: 12),
                const Text('New default model'),
                const SizedBox(height: 4),
                ComboBox<String>(
                  key: const ValueKey('providers-remove-new-default'),
                  isExpanded: true,
                  value: newDefault,
                  placeholder: const Text('Choose a model'),
                  items: [
                    for (final model in plan.newDefaultChoices)
                      ComboBoxItem<String>(value: model, child: Text(model)),
                  ],
                  onChanged: (model) =>
                      setDialogState(() => newDefault = model),
                ),
              ],
            ],
          ),
          actions: [
            Button(
              key: const ValueKey('providers-remove-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('providers-remove-confirm'),
              onPressed: plan.needsNewDefault && newDefault == null
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await cubit.remove(
      id,
      newDefaultModel: newDefault,
      deleteStoredKey: deleteKey,
    );
  }
}

/// Строка провайдера: Expander артборда (заголовок с тегом проверки и
/// кнопками, раскрытое тело с таблицей «Key / Last check / Source»).
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.row,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onCheck,
    required this.onEdit,
    required this.onRemove,
    required this.bodyStyle,
    required this.monoStyle,
  });

  final ProviderRow row;
  final bool expanded;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onCheck;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final TextStyle? bodyStyle;
  final TextStyle? monoStyle;

  @override
  Widget build(BuildContext context) {
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    final check = row.check;
    return CodeLabExpanderCard(
      headerKey: ValueKey('providers-row-${row.id}'),
      leading: const Icon(FluentIcons.cloud, size: 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CodeLabText(row.id),
              if (row.isDefault) ...[
                const SizedBox(width: 8),
                const CodeLabBadge(label: 'Default', tone: CodeLabTone.accent),
              ],
            ],
          ),
          CodeLabText(
            row.subtitle,
            key: ValueKey('providers-key-${row.id}'),
            role: CodeLabTextRole.caption,
            color: secondary,
          ),
          if (row.keyHint case final hint?)
            CodeLabText(
              hint,
              key: ValueKey('providers-key-hint-${row.id}'),
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
          if (row.checkHint case final hint?)
            CodeLabText(
              hint,
              key: ValueKey('providers-check-hint-${row.id}'),
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
          if (row.unencryptedHost case final host?)
            CodeLabText(
              'The key is sent unencrypted to $host.',
              key: ValueKey('providers-unencrypted-${row.id}'),
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: ValueKey('providers-status-${row.id}'),
            child: CodeLabBadge(
              label: check.label,
              tone: switch (check.kind) {
                ProviderCheckKind.ok => CodeLabTone.success,
                ProviderCheckKind.failed ||
                ProviderCheckKind.keyMissing => CodeLabTone.danger,
                _ => CodeLabTone.neutral,
              },
            ),
          ),
          if (!expanded) ...[
            const SizedBox(width: 12),
            ..._actions(subtle: true),
          ],
        ],
      ),
      expanded: expanded,
      onToggle: onToggle,
      bodyPadding: const EdgeInsets.fromLTRB(52, 16, 16, 16),
      body: expanded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CodeLabKeyValueList(
                  entries: [
                    CodeLabKeyValueEntry(
                      label: 'Key',
                      value: row.keyText,
                      monoValue: row.keyMono,
                    ),
                    CodeLabKeyValueEntry(
                      label: 'Last check',
                      value: check.detail,
                    ),
                    CodeLabKeyValueEntry(
                      label: 'Source',
                      monoValue: row.source,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(children: _actions(subtle: false)),
              ],
            )
          : null,
    );
  }

  /// Подсказка неактивной кнопки, если она есть.
  static Widget _withHint(String? hint, Widget button) =>
      hint == null ? button : Tooltip(message: hint, child: button);

  /// Check, Edit и Remove: в свёрнутом заголовке без рамки, в раскрытом теле —
  /// «Check» и «Edit» обычные, «Remove» без рамки (артборд). У строки
  /// нередактируемого слоя только «Check».
  List<Widget> _actions({required bool subtle}) {
    final secondary = subtle
        ? CodeLabButtonEmphasis.subtle
        : CodeLabButtonEmphasis.secondary;
    final remove = CodeLabButton(
      key: ValueKey('providers-remove-${row.id}'),
      label: 'Remove',
      emphasis: CodeLabButtonEmphasis.danger,
      onPressed: row.canRemove && !busy ? onRemove : null,
    );
    return [
      CodeLabButton(
        key: ValueKey('providers-check-${row.id}'),
        label: 'Check',
        emphasis: secondary,
        onPressed: !row.canCheck || row.check.kind == ProviderCheckKind.running
            ? null
            : onCheck,
      ),
      if (row.editable) ...[
        const SizedBox(width: 4),
        _withHint(
          row.editHint,
          CodeLabButton(
            key: ValueKey('providers-edit-${row.id}'),
            label: 'Edit',
            emphasis: secondary,
            onPressed: row.canEdit && !busy ? onEdit : null,
          ),
        ),
        const SizedBox(width: 4),
        _withHint(row.removeHint, remove),
      ],
    ];
  }
}
