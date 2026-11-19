import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../../../l10n/l10n.dart';
import '../application/provider_settings_cubit.dart';
import 'message_spans.dart';
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
          ProviderSettingsReadOnly() => _readOnly(context, state),
          ProviderSettingsUnreadable() => _unreadable(context, state),
          ProviderSettingsReady() => _ready(context, state),
        },
      ),
    );
  }

  Widget _header(BuildContext context, {required bool withAdd}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: CodeLabText(
            context.l10n.settingsPageProvidersTitle,
            role: CodeLabTextRole.title,
          ),
        ),
        if (withAdd)
          CodeLabButton(
            key: const ValueKey('providers-add'),
            label: context.l10n.providersAdd,
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

  Widget _activeModelRow(BuildContext context, String model) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: CodeLabSettingsRow(
      key: const ValueKey('providers-active-model'),
      title: context.l10n.providersDefaultModel,
      description: context.l10n.providersActiveInSession(model),
      leading: FluentIcons.settings,
    ),
  );

  Widget _readOnly(BuildContext context, ProviderSettingsReadOnly state) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, withAdd: false),
          _bar(
            const ValueKey('providers-read-only'),
            InfoBarSeverity.warning,
            state.notice,
            content: state.hint,
          ),
          if (state.activeModel case final model?)
            _activeModelRow(context, model),
        ],
      );

  Widget _unreadable(BuildContext context, ProviderSettingsUnreadable state) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, withAdd: false),
          _bar(
            const ValueKey('providers-unreadable'),
            InfoBarSeverity.error,
            context.l10n.providersUnreadable,
            content: state.problems.join('\n'),
          ),
          if (state.activeModel case final model?)
            _activeModelRow(context, model),
        ],
      );

  Widget _ready(BuildContext context, ProviderSettingsReady state) {
    final cubit = context.read<ProviderSettingsCubit>();
    final l10n = context.l10n;
    final resources = FluentTheme.of(context).resources;
    final storage = state.keyStorage;
    final body = CodeLabText.styleOf(context, CodeLabTextRole.body);
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    final secondary = resources.textFillColorSecondary;
    // Значение вне списка моделей ComboBox показывает как пустое, поэтому и
    // подсказки у него нет.
    final selected = state.models.contains(state.defaultModel)
        ? state.defaultModel
        : null;
    final combo = ComboBox<String>(
      key: const ValueKey('providers-default-model'),
      isExpanded: true,
      value: selected,
      placeholder: Text(l10n.providersChooseModel),
      // На узком окне строка сжимает ComboBox (CodeLabSettingsRow),
      // а список fluent_ui 4.16 той же ширины, что и кнопка: длинные
      // имена с общим началом без подсказки неразличимы, и легко
      // записать в конфиг не ту модель по умолчанию.
      items: [
        for (final model in state.models)
          ComboBoxItem<String>(
            value: model,
            child: Tooltip(
              message: model,
              child: Text(model, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
      onChanged: state.saving
          ? null
          : (model) {
              if (model != null) {
                unawaited(cubit.setDefaultModel(model));
              }
            },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, withAdd: true),
        if (state.banner case final banner?)
          _bar(
            const ValueKey('providers-banner'),
            switch (banner.kind) {
              ProviderBannerKind.saved => InfoBarSeverity.success,
              ProviderBannerKind.conflict => InfoBarSeverity.warning,
              ProviderBannerKind.error => InfoBarSeverity.error,
            },
            // Баннер хранится типизированным; текст строится на текущем
            // языке, поэтому уже показанный баннер переводится (D5).
            providerMessageText(l10n, banner.message),
            action: switch (banner.action) {
              ProviderBannerAction.retry => CodeLabButton(
                key: const ValueKey('providers-banner-retry'),
                label: l10n.commonRetry,
                icon: FluentIcons.refresh,
                onPressed: () => unawaited(cubit.retryAgentStart()),
              ),
              null => null,
            },
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: CodeLabSettingsRow(
            title: l10n.providersDefaultModel,
            // Две независимые фразы через пробел, как раньше; каждая — своё
            // сообщение каталога.
            description: [
              l10n.providersUsedByNewSessions,
              if (state.activeModel case final model?)
                l10n.providersActiveInSession(model),
            ].join(' '),
            leading: FluentIcons.settings,
            trailing: SizedBox(
              width: 260,
              // Выбранное значение обрезается многоточием на узкой строке, а
              // подсказки пунктов внутри кнопки ComboBox не получают наведения
              // (IgnorePointer), поэтому полное имя даёт подсказка над самим
              // ComboBox.
              child: selected == null
                  ? combo
                  : Tooltip(message: selected, child: combo),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: CodeLabSettingsRow(
            key: const ValueKey('providers-key-storage'),
            title: l10n.providersKeyStorage(storage.backendId),
            description: l10n.providersKeyStorageDescription,
            leading: FluentIcons.permissions,
            trailing: CodeLabBadge(
              label: storage.writable
                  ? l10n.providersStorageWritable
                  : l10n.providersStorageReadOnly,
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
              l10n.providersKeysInOpenFile(path),
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
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 4),
          child: CodeLabText(
            l10n.providersConfigured,
            role: CodeLabTextRole.strong,
          ),
        ),
        if (state.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: CodeLabText(
                    l10n.providersEmpty,
                    key: const ValueKey('providers-empty'),
                  ),
                ),
                CodeLabButton(
                  key: const ValueKey('providers-empty-add'),
                  label: l10n.providersAdd,
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
            // Одно сообщение, путь внутри моноширинный (D5, правило 7).
            children: messageSpans((m) => l10n.providersConfigFile(m[0]), [
              TextSpan(text: state.configPath, style: mono),
            ]),
          ),
        ),
        CodeLabText(
          l10n.providersRemoveHelp,
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
          // Текст строится по `context` диалога: открытый диалог
          // переводится вместе с деревом (D5, п. 9).
          title: CodeLabDialogTitle(context.l10n.providersRemoveTitle(id)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.providersRemoveDetails),
              if (plan.offersKeyDeletion) ...[
                const SizedBox(height: 12),
                Checkbox(
                  key: const ValueKey('providers-remove-delete-key'),
                  checked: deleteKey,
                  onChanged: (value) =>
                      setDialogState(() => deleteKey = value ?? false),
                  content: Flexible(
                    child: Text(context.l10n.providersRemoveDeleteKey),
                  ),
                ),
              ],
              if (plan.needsNewDefault) ...[
                const SizedBox(height: 12),
                Text(context.l10n.providersRemoveNewDefault),
                const SizedBox(height: 4),
                ComboBox<String>(
                  key: const ValueKey('providers-remove-new-default'),
                  isExpanded: true,
                  value: newDefault,
                  placeholder: Text(context.l10n.providersChooseModel),
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
              child: Text(context.l10n.commonCancel),
            ),
            FilledButton(
              key: const ValueKey('providers-remove-confirm'),
              onPressed: plan.needsNewDefault && newDefault == null
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.commonRemove),
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
///
/// На узкой карточке (меньше [_wideHeaderMinWidth]) кнопки свёрнутой строки
/// переносятся под подпись внутри заголовка; на широкой остаются справа.
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

  /// Ширина карточки, с которой бейдж и кнопки помещаются в шапку рядом с
  /// именем. Слагается из: поля шапки 16+6, значок 16 и промежутки 12×3,
  /// имя не уже ~190, бейдж проверки ~100, три кнопки с промежутками ~230,
  /// шеврон 32 — около 640 pt. Уже — кнопки уходят под подпись внутри
  /// заголовка (D10: в свёрнутой строке они остаются).
  static const _wideHeaderMinWidth = 640.0;

  @override
  Widget build(BuildContext context) {
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    final check = row.check;
    // Узость берём по ширине самой карточки, а не окна: в окне по умолчанию
    // (`MainMenu.xib`, 800 pt) странице достаётся ~400 pt, и бейдж с тремя
    // кнопками в шапке вытесняли имя и переполняли Row.
    return LayoutBuilder(
      builder: (context, constraints) => _card(
        context,
        narrow: constraints.maxWidth < _wideHeaderMinWidth,
        secondary: secondary,
        check: check,
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required bool narrow,
    required Color secondary,
    required ProviderCheckView check,
  }) {
    return CodeLabExpanderCard(
      headerKey: ValueKey('providers-row-${row.id}'),
      leading: const Icon(FluentIcons.cloud, size: 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                // Имя может обрезаться многоточием — полное по подсказке.
                child: Tooltip(
                  message: row.id,
                  child: CodeLabText(
                    row.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (row.isDefault) ...[
                const SizedBox(width: 8),
                // Flexible: русская метка длиннее английской (D8), на узкой
                // карточке она сжимается с многоточием, а не переполняет Row.
                Flexible(
                  child: CodeLabBadge(
                    label: context.l10n.commonDefault,
                    tone: CodeLabTone.accent,
                  ),
                ),
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
              context.l10n.settingsKeyUnencryptedToHost(host),
              key: ValueKey('providers-unencrypted-${row.id}'),
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
          // Узко: кнопки под подписью, рядом с предупреждением об `http://`.
          if (!expanded && narrow)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _actions(context, subtle: true, gaps: false),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: ValueKey('providers-status-${row.id}'),
            // Верхняя граница ширины тега: русский итог проверки длиннее
            // английского (D8), длиннее предела он сжимается с многоточием.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
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
          ),
          if (!expanded && !narrow) ...[
            const SizedBox(width: 12),
            ..._actions(context, subtle: true),
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
                      label: context.l10n.providersRowKey,
                      value: row.keyText,
                      monoValue: row.keyMono,
                      tail: row.keyTail,
                    ),
                    CodeLabKeyValueEntry(
                      label: context.l10n.providersRowLastCheck,
                      value: check.detail,
                    ),
                    CodeLabKeyValueEntry(
                      label: context.l10n.providersRowSource,
                      monoValue: row.source,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Wrap: три русские кнопки могут не поместиться в строку (D8).
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _actions(context, subtle: false, gaps: false),
                ),
              ],
            )
          : null,
    );
  }

  /// Подсказка неактивной кнопки, если она есть.
  static Widget _withHint(String? hint, Widget button) =>
      hint == null ? button : Tooltip(message: hint, child: button);

  /// Check, Edit и Remove: в свёрнутом заголовке без рамки (справа от бейджа,
  /// а на узкой карточке — под подписью; [gaps] `false` — без промежутков,
  /// их задаёт `Wrap`), в раскрытом теле —
  /// «Check» и «Edit» обычные, «Remove» без рамки (артборд). У строки
  /// нередактируемого слоя только «Check».
  List<Widget> _actions(
    BuildContext context, {
    required bool subtle,
    bool gaps = true,
  }) {
    final l10n = context.l10n;
    final secondary = subtle
        ? CodeLabButtonEmphasis.subtle
        : CodeLabButtonEmphasis.secondary;
    final remove = CodeLabButton(
      key: ValueKey('providers-remove-${row.id}'),
      label: l10n.commonRemove,
      emphasis: CodeLabButtonEmphasis.danger,
      onPressed: row.canRemove && !busy ? onRemove : null,
    );
    return [
      CodeLabButton(
        key: ValueKey('providers-check-${row.id}'),
        label: l10n.commonCheck,
        emphasis: secondary,
        onPressed: !row.canCheck || row.check.kind == ProviderCheckKind.running
            ? null
            : onCheck,
      ),
      if (row.editable) ...[
        if (gaps) const SizedBox(width: 4),
        _withHint(
          row.editHint,
          CodeLabButton(
            key: ValueKey('providers-edit-${row.id}'),
            label: l10n.commonEdit,
            emphasis: secondary,
            onPressed: row.canEdit && !busy ? onEdit : null,
          ),
        ),
        if (gaps) const SizedBox(width: 4),
        _withHint(row.removeHint, remove),
      ],
    ];
  }
}
