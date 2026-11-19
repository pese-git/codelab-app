import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart'
    show
        ExternalSourceSetting,
        MaskedSetting,
        SecretSetting,
        SettingEditRefusal,
        SettingType,
        TrustBoundarySetting,
        UnknownSetting;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../../../app/language/app_language_cubit.dart';
import '../../../core/platform/app_language_preferences.dart';
import '../../../l10n/l10n.dart';
import 'config_source_label.dart';
import '../application/agent_defaults_cubit.dart';
import '../application/startup_settings_cubit.dart';
import '../application/about_ports.dart';
import 'about_section.dart';
import 'agent_setting_labels.dart';

/// Тело страницы «General» для таблицы `settingsPageBuilders`.
///
/// Почему отдельный хозяин: Cubit блока «Agent defaults» создаётся на каждое
/// открытие страницы (снимок конфига перечитывается при открытии, design.md
/// change `add-app-general-page`, D7), а построитель таблицы — просто функция
/// от `BuildContext`.
Widget buildGeneralPage(BuildContext context) => const GeneralPageHost();

/// Создаёт `AgentDefaultsCubit`, читает снимок и закрывает Cubit вместе со
/// страницей.
///
/// Почему не виджет, создающий зависимости: Cubit собирает composition root
/// (`CodeLabDependencies.createAgentDefaultsCubit`), здесь он только получает
/// владельца жизненного цикла (AGENTS.md §6; образец — `AgentsModesPageHost`).
class GeneralPageHost extends StatefulWidget {
  const GeneralPageHost({super.key});

  @override
  State<GeneralPageHost> createState() => _GeneralPageHostState();
}

class _GeneralPageHostState extends State<GeneralPageHost> {
  AgentDefaultsCubit? _cubit;
  StartupSettingsCubit? _startup;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit == null) {
      final cubit = codeLabDependenciesOf(context).createAgentDefaultsCubit();
      _cubit = cubit;
      unawaited(cubit.reload());
      final startup = codeLabDependenciesOf(
        context,
      ).createStartupSettingsCubit();
      _startup = startup;
      unawaited(startup.load());
    }
  }

  @override
  void dispose() {
    unawaited(_cubit?.close());
    unawaited(_startup?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider<AgentDefaultsCubit>.value(value: _cubit!),
      BlocProvider<StartupSettingsCubit>.value(value: _startup!),
    ],
    child: GeneralPage(about: codeLabDependenciesOf(context).aboutPorts),
  );
}

/// Страница настроек «General»: умолчания агента и язык интерфейса (артборд
/// «26 Settings — General»; отступления — design.md change
/// `add-app-general-page`, D17).
///
/// Почему язык без своего Cubit-а: единственный владелец языка —
/// `AppLanguageCubit` (`add-desktop-localization`, D2); второй владелец
/// разошёлся бы с ним. Блок «Agent defaults» показывает состояние
/// `AgentDefaultsCubit`: ключи конфигурации агента общие с CLI, правила
/// «чьи настройки», «можно ли править» и разбор значения решают мост и Cubit
/// (SETUP-8), страница только отображает и передаёт ввод пользователя.
///
/// Для чего: выбор `System | English | Русский` применяется сразу, без
/// перезапуска (spec app-settings «Язык интерфейса app»); сбой записи
/// показывается предупреждением, язык при этом остаётся применённым. Порядок
/// блоков: InfoBar и «Agent defaults», «Interface», «Startup and files»,
/// «About» (раздел показывается, если передан [about]). Строка «Show ignored
/// files» появится после итерации 3 `add-file-preview-and-tree` (D10): строка
/// без поведения не показывается (SETUP-17).
///
/// Как использовать: строится из `settingsPageBuilders` хозяином
/// [GeneralPageHost]; `AppLanguageCubit` и `AgentDefaultsCubit` берутся из
/// ближайших `BlocProvider`. Названия `English` и `Русский` — эндонимы, они не
/// переводятся.
class GeneralPage extends StatelessWidget {
  const GeneralPage({this.about, super.key});

  /// Данные и порты раздела «About»; `null` — раздел не показывается (тесты
  /// блоков «Agent defaults» на Cubit-двойниках).
  final AboutPorts? about;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<AppLanguageCubit>();
    return BlocBuilder<AppLanguageCubit, AppLanguageState>(
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeLabText(
            l10n.settingsPageGeneralTitle,
            role: CodeLabTextRole.title,
          ),
          const SizedBox(height: 12),
          if (state.saveFailed) ...[
            // Только типизированный исход: текста исключения нет (D2).
            InfoBar(
              key: const ValueKey('settings-language-save-failed'),
              title: Text(l10n.settingsLanguageSaveFailed),
              severity: InfoBarSeverity.warning,
              // Повтор записи: `RadioGroup` не вызывает `onChanged` для уже
              // выбранного значения, поэтому отдельная кнопка.
              action: Button(
                key: const ValueKey('settings-language-save-retry'),
                onPressed: () => unawaited(cubit.select(state.preference)),
                child: Text(l10n.settingsLanguageSaveRetry),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const _AgentDefaultsBlock(),
          CodeLabSettingsSection(
            title: l10n.settingsGeneralSectionInterface,
            children: [
              CodeLabSettingsRow(
                key: const ValueKey('settings-general-language'),
                title: l10n.settingsLanguageTitle,
                trailing: RadioGroup<AppLanguagePreference>(
                  groupValue: state.preference,
                  onChanged: (value) {
                    if (value != null) unawaited(cubit.select(value));
                  },
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _option(
                        AppLanguagePreference.system,
                        'settings-language-system',
                        l10n.settingsLanguageSystem,
                      ),
                      _option(
                        AppLanguagePreference.en,
                        'settings-language-en',
                        l10n.settingsLanguageEnglish,
                      ),
                      _option(
                        AppLanguagePreference.ru,
                        'settings-language-ru',
                        l10n.settingsLanguageRussian,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const _StartupSection(),
          if (about case final ports?) AboutSection(ports: ports),
        ],
      ),
    );
  }

  Widget _option(AppLanguagePreference value, String key, String label) =>
      RadioButton<AppLanguagePreference>(
        key: ValueKey(key),
        value: value,
        content: Text(label),
      );
}

/// Блок «Agent defaults» вместе с InfoBar `settings-general-shared-info`.
///
/// Для чего: только отображение [AgentDefaultsState]. InfoBar о файле и CLI
/// показывается лишь у готового блока: у удалённого и стороннего агента
/// локальный `config.yaml` не читается, и называть его нельзя (SETUP-2).
class _AgentDefaultsBlock extends StatelessWidget {
  const _AgentDefaultsBlock();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AgentDefaultsCubit, AgentDefaultsState>(
      builder: (context, state) {
        final body = switch (state) {
          AgentDefaultsLoading() => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ProgressRing(
                  key: ValueKey('settings-general-agent-loading'),
                ),
              ),
            ),
          ],
          AgentDefaultsReadOnly() => [
            InfoBar(
              key: const ValueKey('settings-general-agent-read-only'),
              title: Text(switch (state.kind) {
                AgentDefaultsReadOnlyKind.remote =>
                  l10n.settingsGeneralReadOnlyRemote(state.subject),
                AgentDefaultsReadOnlyKind.notManaged =>
                  l10n.settingsGeneralReadOnlyManaged(state.subject),
              }),
              severity: InfoBarSeverity.warning,
            ),
          ],
          AgentDefaultsUnreadable() => [
            if (state.banner case final banner?)
              _Banner(banner: banner, configHome: state.configHome),
            InfoBar(
              key: const ValueKey('settings-general-agent-unreadable'),
              title: Text(l10n.settingsGeneralUnreadable),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: switch (state.reason) {
                  // Тексты проблем — от загрузчика ядра, как есть
                  // (английские); остальные причины — из ARB (D7).
                  AgentDefaultsUnreadableReason.loader => [
                    for (final p in state.problems) Text(p),
                  ],
                  AgentDefaultsUnreadableReason.cannotRead => [
                    Text(l10n.settingsGeneralUnreadableCannotRead),
                  ],
                  AgentDefaultsUnreadableReason.homeUnavailable => [
                    Text(l10n.settingsGeneralUnreadableHome),
                  ],
                  AgentDefaultsUnreadableReason.userLayerUnreadable => [
                    Text(l10n.settingsGeneralUnreadableUserLayer),
                  ],
                },
              ),
              severity: InfoBarSeverity.error,
            ),
          ],
          AgentDefaultsReady() => [
            CodeLabText(
              l10n.settingsGeneralAgentDefaultsCaption,
              role: CodeLabTextRole.caption,
            ),
            const SizedBox(height: 8),
            if (state.banner case final banner?)
              _Banner(banner: banner, configHome: state.configHome),
            for (final group in state.groups) ...[
              // Подзаголовок раздела реестра: строки `budget.max_steps` и
              // `subagents.max_steps` называются одинаково, различает их
              // только группа (D2).
              _GroupTitle(section: group.section),
              for (final row in group.rows) ...[
                _AgentRow(
                  key: ValueKey('settings-general-agent-row-${row.field.key}'),
                  row: row,
                  error: state.fieldErrors.contains(row.field.key),
                  saving: state.saving,
                ),
                const SizedBox(height: 4),
              ],
            ],
          ],
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state is AgentDefaultsReady) ...[
              InfoBar(
                key: const ValueKey('settings-general-shared-info'),
                title: Text(l10n.settingsGeneralSharedInfo(state.configHome)),
                severity: InfoBarSeverity.info,
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                key: const ValueKey('settings-general-agent-defaults'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: CodeLabText(
                      l10n.settingsGeneralAgentDefaultsTitle,
                      role: CodeLabTextRole.strong,
                    ),
                  ),
                  ...body,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Баннер результата записи `settings-general-agent-banner`.
///
/// Текст строится здесь из типизированных данных на языке интерфейса (D7,
/// D15); значения и пути приходят готовыми из Cubit.
class _Banner extends StatelessWidget {
  const _Banner({required this.banner, required this.configHome});

  final AgentDefaultsBanner banner;
  final String configHome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tail = switch (banner.restart) {
      AgentDefaultsRestart.none => '',
      AgentDefaultsRestart.afterRestart =>
        ' ${l10n.settingsGeneralTailAfterRestart}',
      AgentDefaultsRestart.whenStarts =>
        ' ${l10n.settingsGeneralTailWhenStarts}',
    };
    final (text, severity) = switch (banner.kind) {
      AgentDefaultsBannerKind.saved => (
        '${l10n.settingsGeneralSaved}$tail',
        InfoBarSeverity.success,
      ),
      AgentDefaultsBannerKind.overridden => (
        '${l10n.settingsGeneralSavedOverridden(configSourceLabel(l10n, banner.overriddenByKind, forGeneral: true), banner.effective ?? '')}$tail',
        InfoBarSeverity.warning,
      ),
      AgentDefaultsBannerKind.savedUnverified => (
        l10n.settingsGeneralSavedUnverified(configHome),
        InfoBarSeverity.success,
      ),
      AgentDefaultsBannerKind.conflict => (
        l10n.settingsGeneralConflict,
        InfoBarSeverity.warning,
      ),
      AgentDefaultsBannerKind.rejected => (
        // Проблемы писателя — его текст как есть (D5).
        banner.problems.isEmpty
            ? l10n.settingsGeneralRejected
            : banner.problems.join('\n'),
        InfoBarSeverity.error,
      ),
      AgentDefaultsBannerKind.inlineSecret => (
        l10n.settingsGeneralRefusalSecret,
        InfoBarSeverity.error,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InfoBar(
        key: const ValueKey('settings-general-agent-banner'),
        title: Text(text),
        severity: severity,
      ),
    );
  }
}

/// Строка ключа реестра: подпись, тег, ключ, источник, описание, пометки и
/// редактор по типу (D5).
///
/// Почему своя раскладка, а не `CodeLabSettingsRow`: строке нужны тег, ключ в
/// моноширинном шрифте, источник и несколько пометок; кит принимает только
/// заголовок и описание, а бизнес-данных в `codelab_ui` быть не должно.
class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.row,
    required this.error,
    required this.saving,
    super.key,
  });

  final AgentDefaultsRow row;
  final bool error;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final resources = FluentTheme.of(context).resources;
    final field = row.field;
    final descriptor = field.descriptor;
    final description = agentSettingDescriptionOf(l10n, field.key);
    final refusal = row.refusal;
    final secondary = resources.textFillColorSecondary;
    final critical = resources.systemFillColorCritical;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resources.cardBackgroundFillColorDefault,
        border: Border.all(color: resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      CodeLabText(
                        agentSettingLabelOf(l10n, field.key) ?? field.key,
                      ),
                      _Tag(l10n.settingsGeneralTagShared),
                      if (field.restartRequired)
                        CodeLabText(
                          l10n.settingsGeneralAppliesAfterRestart,
                          role: CodeLabTextRole.caption,
                          color: secondary,
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      _KeyText(field.key, color: secondary),
                      CodeLabText(
                        configSourceLabel(
                          l10n,
                          field.source?.kind,
                          forGeneral: true,
                        ),
                        role: CodeLabTextRole.caption,
                        color: secondary,
                      ),
                    ],
                  ),
                  if (description != null)
                    // Без ограничения строк: на узком окне описание переносится
                    // целиком, многоточие съедало смысл (D17).
                    CodeLabText(
                      description,
                      role: CodeLabTextRole.caption,
                      color: secondary,
                    ),
                  if (row.overriddenByKind case final layer?)
                    CodeLabText(
                      l10n.settingsGeneralOverriddenBy(
                        configSourceLabel(l10n, layer, forGeneral: true),
                      ),
                      role: CodeLabTextRole.caption,
                      color: secondary,
                    ),
                  if (refusal != null)
                    CodeLabText(
                      _refusalText(
                        l10n,
                        refusal,
                        configSourceLabel(
                          l10n,
                          field.source?.kind,
                          forGeneral: true,
                        ),
                      ),
                      role: CodeLabTextRole.caption,
                      color: secondary,
                    ),
                  if (error)
                    CodeLabText(
                      _hintText(
                        l10n,
                        descriptor.type,
                        descriptor.min,
                        descriptor.max,
                      ),
                      role: CodeLabTextRole.caption,
                      color: critical,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: refusal != null
                  ? Text(_valueText(l10n, row))
                  : _editor(l10n),
            ),
          ],
        ),
      ),
    );
  }

  String _valueText(AppLocalizations l10n, AgentDefaultsRow row) =>
      row.field.effectiveValue == null && row.field.entryCount == null
      ? l10n.settingsGeneralNotSet
      : row.field.displayValue;

  Widget _editor(AppLocalizations l10n) {
    final field = row.field;
    final descriptor = field.descriptor;
    final cubitCall = _Submit(field.key);
    switch (descriptor.type) {
      case SettingType.bool:
        return Align(
          alignment: Alignment.centerRight,
          child: Builder(
            builder: (context) => ToggleSwitch(
              checked: field.effectiveValue == true,
              onChanged: saving
                  ? null
                  : (value) => cubitCall.send(context, '$value'),
            ),
          ),
        );
      case SettingType.enumeration:
        final current = '${field.effectiveValue}';
        final values = descriptor.enumValues ?? const <String>[];
        return Builder(
          builder: (context) => ComboBox<String>(
            value: values.contains(current) ? current : null,
            isExpanded: true,
            items: [
              for (final v in values) ComboBoxItem(value: v, child: Text(v)),
            ],
            onChanged: saving
                ? null
                : (value) {
                    if (value != null) cubitCall.send(context, value);
                  },
          ),
        );
      default:
        final value = field.effectiveValue;
        return Builder(
          builder: (context) => _TextEditor(
            value: value == null ? '' : '$value',
            placeholder: l10n.settingsGeneralNotSet,
            enabled: !saving,
            onSubmit: (text) => cubitCall.send(context, text),
          ),
        );
    }
  }

  static String _refusalText(
    AppLocalizations l10n,
    SettingEditRefusal refusal,
    String sourceName,
  ) => switch (refusal) {
    SecretSetting() => l10n.settingsGeneralRefusalSecret,
    MaskedSetting() => l10n.settingsGeneralRefusalMasked,
    ExternalSourceSetting() => l10n.settingsGeneralRefusalExternal(sourceName),
    // Без `_ =>`: новая ветка `SettingEditRefusal` ломает сборку и требует
    // решения о тексте (контракт моста, D6).
    UnknownSetting() ||
    TrustBoundarySetting() => l10n.settingsGeneralRefusalOther,
  };

  /// Подсказка формата по типу и границам дескриптора (D5); введённого
  /// значения в ней нет (CFG-10).
  static String _hintText(
    AppLocalizations l10n,
    SettingType type,
    num? min,
    num? max,
  ) => switch (type) {
    SettingType.int =>
      min != null && max != null
          ? l10n.settingsGeneralHintIntRange('${min.toInt()}', '${max.toInt()}')
          : min != null
          ? l10n.settingsGeneralHintIntMin('${min.toInt()}')
          : l10n.settingsGeneralHintInt,
    SettingType.duration => l10n.settingsGeneralHintDuration,
    _ => l10n.settingsGeneralHintNumber,
  };
}

/// Передаёт ввод пользователя Cubit-у: решение «записать ли» принимает он.
final class _Submit {
  const _Submit(this.key);

  final String key;

  void send(BuildContext context, String raw) =>
      unawaited(context.read<AgentDefaultsCubit>().submit(key, raw));
}

/// Небольшой тег рядом с подписью строки.
class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = FluentTheme.of(context).accentColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: CodeLabText(text, role: CodeLabTextRole.caption),
      ),
    );
  }
}

/// Поле ввода строки: применяется по Enter и при потере фокуса (D5).
///
/// Почему владеет контроллером: текст в поле — эфемерное состояние ввода, а не
/// состояние страницы. Значение из Cubit подставляется, только пока поле не в
/// фокусе, чтобы перечитывание снимка не стирало набираемый текст.
class _TextEditor extends StatefulWidget {
  const _TextEditor({
    required this.value,
    required this.placeholder,
    required this.enabled,
    required this.onSubmit,
  });

  final String value;
  final String placeholder;
  final bool enabled;
  final ValueChanged<String> onSubmit;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  /// Текст, который уже показан или отправлен: потеря фокуса без правки
  /// ничего не отправляет.
  late String _committed;

  @override
  void initState() {
    super.initState();
    _committed = widget.value;
    _controller = TextEditingController(text: widget.value);
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_TextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.hasFocus) {
      _committed = widget.value;
      _controller.text = widget.value;
    }
  }

  void _onFocus() {
    if (!_focus.hasFocus && _controller.text != _committed) {
      _commit();
    }
  }

  void _commit() {
    _committed = _controller.text;
    widget.onSubmit(_controller.text);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextBox(
    controller: _controller,
    focusNode: _focus,
    placeholder: widget.placeholder,
    enabled: widget.enabled,
    onSubmitted: (_) => _commit(),
  );
}

/// Блок «Startup and files»: строка «Reopen the last project and its tabs»
/// (design.md change `add-app-general-page`, D9).
///
/// Для чего: только отображение [StartupSettingsState]. Строка «Show ignored
/// files» появится в этом блоке вместе со своим владельцем значения (D10,
/// SETUP-17). Значение применяется при следующем запуске, поэтому текущую
/// работу переключение не трогает.
class _StartupSection extends StatelessWidget {
  const _StartupSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<StartupSettingsCubit>();
    return BlocBuilder<StartupSettingsCubit, StartupSettingsState>(
      builder: (context, state) => CodeLabSettingsSection(
        title: l10n.settingsGeneralSectionStartup,
        children: [
          if (state.saveFailed)
            InfoBar(
              key: const ValueKey(
                'settings-general-reopen-last-project-save-failed',
              ),
              // Только типизированный исход: текста исключения нет (D9).
              title: Text(l10n.settingsGeneralStartupSaveFailed),
              severity: InfoBarSeverity.warning,
              action: Button(
                key: const ValueKey(
                  'settings-general-reopen-last-project-retry',
                ),
                onPressed: () => unawaited(cubit.retry()),
                child: Text(l10n.settingsLanguageSaveRetry),
              ),
            ),
          CodeLabSettingsRow(
            key: const ValueKey('settings-general-reopen-last-project'),
            title: l10n.settingsGeneralReopenTitle,
            description: l10n.settingsGeneralReopenDescription,
            // Описание переносится целиком: у обрезанного «Applies at the next
            // start» терялся смысл строки (D17).
            descriptionMaxLines: null,
            trailing: ToggleSwitch(
              checked: state.reopenLastProject,
              onChanged: (value) => unawaited(cubit.select(value)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Подзаголовок группы строк «Agent defaults»: раздел реестра на языке
/// интерфейса, ключ `settings-general-agent-group-<раздел строчными>` (D2).
class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.section});

  /// Имя раздела реестра: `Budget`, `Agent`, `Subagents`, `Logging`.
  final String section;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = switch (section) {
      'Budget' => l10n.settingsGeneralGroupBudget,
      'Agent' => l10n.settingsGeneralGroupAgent,
      'Subagents' => l10n.settingsGeneralGroupSubagents,
      'Logging' => l10n.settingsGeneralGroupLogging,
      // Раздел без перевода (новый ключ реестра): показывается как есть.
      _ => section,
    };
    return Padding(
      key: ValueKey('settings-general-agent-group-${section.toLowerCase()}'),
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: CodeLabText(title, role: CodeLabTextRole.caption),
    );
  }
}

/// Ключ реестра (`subagents.heartbeat_interval`) моноширинным шрифтом.
///
/// Почему сегменты: на узком окне длинный ключ ломался посреди слова. Ключ
/// режется после `.` и `_`, сегменты идут `Wrap`-ом, и перенос возможен только
/// между ними (D17). Для скринридера весь ключ — одна метка, а не набор
/// обрывков.
class _KeyText extends StatelessWidget {
  const _KeyText(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final segments = text.split(RegExp(r'(?<=[._])'));
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Wrap(
        children: [
          for (final segment in segments)
            CodeLabText(segment, role: CodeLabTextRole.mono, color: color),
        ],
      ),
    );
  }
}
