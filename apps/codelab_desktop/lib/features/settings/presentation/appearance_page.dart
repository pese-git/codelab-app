import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart'
    show ThemeIssueCode, ThemeReadError, ThemeRole;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../../../app/appearance/app_appearance_cubit.dart';
import '../../../app/appearance/app_appearance_start.dart';
import '../../../core/platform/app_appearance_preferences.dart';
import '../../../l10n/l10n.dart';
import '../application/appearance_settings_cubit.dart';
import 'theme_issue_texts.dart';

/// Тело страницы «Appearance» для таблицы `settingsPageBuilders`.
///
/// Почему отдельный хозяин: Cubit страницы создаётся на каждое открытие
/// (каталог тем перечитывается, design.md change `add-app-appearance-page`,
/// D13), а построитель таблицы — просто функция от `BuildContext`.
Widget buildAppearancePage(BuildContext context) => const AppearancePageHost();

/// Создаёт `AppearanceSettingsCubit`, читает каталог и закрывает Cubit вместе
/// со страницей.
///
/// Почему не виджет, создающий зависимости: Cubit собирает composition root
/// (`CodeLabDependencies.createAppearanceSettingsCubit`), здесь он только
/// получает владельца жизненного цикла (AGENTS.md §6; образец —
/// `GeneralPageHost`). При открытии страница также перечитывает системный
/// акцент: на Linux платформа не сообщает о смене (D7).
class AppearancePageHost extends StatefulWidget {
  const AppearancePageHost({super.key});

  @override
  State<AppearancePageHost> createState() => _AppearancePageHostState();
}

class _AppearancePageHostState extends State<AppearancePageHost> {
  AppearanceSettingsCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit == null) {
      final dependencies = codeLabDependenciesOf(context);
      final cubit = dependencies.createAppearanceSettingsCubit();
      _cubit = cubit;
      _fire(cubit.load());
      _fire(dependencies.appearanceCubit.refreshSystemAccent());
    }
  }

  @override
  void dispose() {
    unawaited(_cubit?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [BlocProvider<AppearanceSettingsCubit>.value(value: _cubit!)],
    child: const AppearancePage(),
  );
}

/// Текст файла темы для показа: экранирование построчно (D10).
///
/// Почему не `escapeForDisplay` по всему тексту: он экранирует и `\n`, поэтому
/// файл склеивался бы в одну строку, а номера строк `warningLines` не
/// совпадали бы. Поэтому текст делится по `\n` (перед ним снимается `\r`),
/// каждая строка экранируется отдельно (управляющие и bidi-символы видимы), и
/// строки склеиваются `\n`. Табуляция заменяется четырьмя пробелами: это не
/// опасный символ, а файл с отступами табами иначе заполнился бы `\u0009`.
String _escapeFileText(String text) => [
  for (final line in text.split(RegExp(r'\r?\n')))
    escapeForDisplay(line.replaceAll('\t', '    ')),
].join('\n');

/// Ширина строки «Accent color», от которой переключатель стоит справа.
const _accentInlineWidth = 560.0;

/// Сколько строк списка проблем показывается (D9а): остальные — строкой «ещё».
const _issueLimit = 50;

/// Запускает операцию без ожидания и не теряет её ошибку (AGENTS.md §12, §16).
///
/// Почему: обработчики нажатий не могут `await`, а необработанное асинхронное
/// исключение пропало бы в зоне; здесь оно уходит в обработчик ошибок Flutter
/// (журнал и отчёт), текст исключения страница не показывает.
void _fire(Future<void> operation) => unawaited(
  operation.onError(
    (Object error, StackTrace stack) => FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'appearance page',
      ),
    ),
  ),
);

/// Ширина области страницы, от которой «Preview» стоит правой колонкой.
const _wideBreakpoint = 960.0;

/// Ширина правой колонки «Preview».
const _previewColumnWidth = 380.0;

/// Образец кода в превью: язык и строки (данные app, не из сессий).
const _previewLanguage = 'dart';
const _previewKeyword = 'final';
const _previewSampleComment = '// Retry with linear backoff';
const _previewSampleRemoved = '−  return retry(attempt);';
const _previewSampleAdded = '+  return retry(attempt + 1);';

/// Страница настроек «Appearance» (артборд «10 Settings — Appearance»;
/// отступления — design.md change `add-app-appearance-page`, D14).
///
/// Почему два Cubit: применённое оформление (режим, темы, системный акцент,
/// откат и сбой записи) принадлежит `AppAppearanceCubit` на весь процесс, а
/// временное состояние страницы (каталог, выбранная для превью карточка,
/// импорт) — `AppearanceSettingsCubit`. Страница только показывает их
/// состояние и передаёт решения пользователя.
///
/// Для чего: блоки в порядке артборда — «Mode», «Accent color» (только где
/// платформа отдаёт акцент, SETUP-17), «Color theme», «Custom themes»,
/// панель проблем выбранной темы и «Preview» с контрастом, «Reset» и «Use».
/// «Preview» — правая колонка от 960 px, иначе под остальными блоками. Выбор
/// карточки тему НЕ применяет. Текст файла темы и значения из него проходят
/// `escapeForDisplay` (D10).
///
/// Как использовать: строится из `settingsPageBuilders` хозяином
/// [AppearancePageHost]; оба Cubit берутся из ближайших `BlocProvider`.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _ReplaceDialogGate(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideBreakpoint;
          final left = const _LeftColumn();
          const right = _PreviewColumn();
          return Column(
            key: const ValueKey('settings-appearance'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CodeLabText(
                l10n.settingsPageAppearanceTitle,
                role: CodeLabTextRole.title,
              ),
              const SizedBox(height: 12),
              const _AppInfoBars(),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: 24),
                    const SizedBox(width: _previewColumnWidth, child: right),
                  ],
                )
              else ...[
                left,
                right,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Имя встроенной темы на языке интерфейса; имя пользовательской — как есть.
String _themeName(AppLocalizations l10n, String id) => switch (id) {
  'light' => l10n.appearanceThemeFluentLight,
  'dark' => l10n.appearanceThemeFluentDark,
  'high-contrast' => l10n.appearanceThemeHighContrast,
  // Карточка пользовательской темы: имя файла как есть, но экранированное —
  // оно приходит из каталога на диске.
  _ when id.startsWith(customThemeIdPrefix) => escapeForDisplay(
    id.substring(customThemeIdPrefix.length),
  ),
  _ => escapeForDisplay(id),
};

/// Имя встроенной темы, которой заменяется тема режима, и её режим.
String _fallbackName(AppLocalizations l10n, Brightness brightness) =>
    brightness == Brightness.light
    ? l10n.appearanceThemeFluentLight
    : l10n.appearanceThemeFluentDark;

/// Тема, назначенная режиму [brightness].
String _assigned(AppAppearanceState state, Brightness brightness) =>
    brightness == Brightness.light ? state.lightTheme : state.darkTheme;

/// InfoBar-ы применённого оформления: откат к встроенной теме и сбой записи.
class _AppInfoBars extends StatelessWidget {
  const _AppInfoBars();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AppAppearanceCubit, AppAppearanceState>(
      builder: (context, state) {
        final fallback = [
          if (state.fallback == AppearanceFallback.light ||
              state.fallback == AppearanceFallback.both)
            l10n.appearanceFallback(
              state.lightTheme,
              _fallbackName(l10n, Brightness.light),
            ),
          if (state.fallback == AppearanceFallback.dark ||
              state.fallback == AppearanceFallback.both)
            l10n.appearanceFallback(
              state.darkTheme,
              _fallbackName(l10n, Brightness.dark),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fallback.isNotEmpty) ...[
              InfoBar(
                key: const ValueKey('settings-appearance-fallback'),
                title: Text(fallback.first),
                content: fallback.length > 1 ? Text(fallback[1]) : null,
                severity: InfoBarSeverity.warning,
              ),
              const SizedBox(height: 12),
            ],
            if (state.saveFailed) ...[
              // Только типизированный исход: текста исключения нет (D13).
              InfoBar(
                key: const ValueKey('settings-appearance-save-failed'),
                title: Text(l10n.appearanceSaveFailed),
                severity: InfoBarSeverity.warning,
                action: Button(
                  key: const ValueKey('settings-appearance-save-retry'),
                  onPressed: () =>
                      _fire(context.read<AppAppearanceCubit>().retrySave()),
                  child: Text(l10n.appearanceSaveRetry),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

/// Блоки слева: «Mode», «Accent color», «Color theme», «Custom themes» и
/// панель проблем.
class _LeftColumn extends StatelessWidget {
  const _LeftColumn();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ModeRow(),
      _AccentRow(),
      _ThemesBlock(),
      _CustomBlock(),
      _IssuesBlock(),
    ],
  );
}

class _ModeRow extends StatelessWidget {
  const _ModeRow();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final system = MediaQuery.platformBrightnessOf(context);
    return BlocBuilder<AppAppearanceCubit, AppAppearanceState>(
      buildWhen: (a, b) => a.mode != b.mode,
      builder: (context, state) {
        final cubit = context.read<AppAppearanceCubit>();
        Widget option(AppearanceMode value, String name, String label) =>
            RadioButton<AppearanceMode>(
              key: ValueKey('settings-appearance-mode-$name'),
              value: value,
              content: Text(label),
            );
        return CodeLabSettingsSection(
          key: const ValueKey('settings-appearance-mode'),
          title: l10n.appearanceModeTitle,
          children: [
            CodeLabSettingsRow(
              title: l10n.appearanceModeTitle,
              description: l10n.appearanceModeDescription,
              trailing: RadioGroup<AppearanceMode>(
                groupValue: state.mode,
                onChanged: (value) {
                  if (value != null) _fire(cubit.setMode(value));
                },
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    option(
                      AppearanceMode.light,
                      'light',
                      l10n.appearanceModeLight,
                    ),
                    option(
                      AppearanceMode.dark,
                      'dark',
                      l10n.appearanceModeDark,
                    ),
                    option(
                      AppearanceMode.system,
                      'system',
                      l10n.appearanceModeSystem(
                        system == Brightness.dark
                            ? l10n.appearanceSystemDark
                            : l10n.appearanceSystemLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AccentRow extends StatelessWidget {
  const _AccentRow();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AppAppearanceCubit, AppAppearanceState>(
      buildWhen: (a, b) =>
          a.systemAccent != b.systemAccent ||
          a.systemAccentSupported != b.systemAccentSupported,
      builder: (context, state) {
        // Видимость не меняется после первого кадра: `supported` известно
        // при старте (D7).
        if (!state.systemAccentSupported) return const SizedBox.shrink();
        void change(bool value) =>
            _fire(context.read<AppAppearanceCubit>().setSystemAccent(value));
        return CodeLabSettingsSection(
          title: l10n.appearanceAccentTitle,
          children: [
            KeyedSubtree(
              key: const ValueKey('settings-appearance-system-accent'),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Переключатель с подписью не сжимается: в узкой области
                  // (окно около 600 px, контент около 350 px) справа от описания
                  // он давал переполнение строки на 116 px, поэтому там он
                  // стоит под описанием, а не в `trailing`.
                  if (constraints.maxWidth >= _accentInlineWidth) {
                    return CodeLabSettingsRow(
                      title: l10n.appearanceAccentTitle,
                      description: l10n.appearanceAccentDescription,
                      trailing: ToggleSwitch(
                        checked: state.systemAccent,
                        onChanged: change,
                        content: Text(l10n.appearanceAccentToggle),
                      ),
                    );
                  }
                  return CodeLabSettingsRow(
                    title: l10n.appearanceAccentTitle,
                    description: l10n.appearanceAccentDescription,
                    // Внутри карточки строки, а не отдельным блоком под ней.
                    // Подпись переносится, а не сжимает строку: у
                    // `ToggleSwitch` с `content` своя `Row` без гибкой части, и
                    // в узкой области она переполняется.
                    footer: Row(
                      children: [
                        ToggleSwitch(
                          checked: state.systemAccent,
                          onChanged: change,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l10n.appearanceAccentToggle)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThemesBlock extends StatelessWidget {
  const _ThemesBlock();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AppearanceSettingsCubit, AppearanceSettingsState>(
      builder: (context, state) {
        final builtIn = [
          for (final card in state.cards)
            if (card.kind != AppearanceThemeKind.custom) card,
        ];
        final custom = [
          for (final card in state.cards)
            if (card.kind == AppearanceThemeKind.custom) card,
        ];
        return Padding(
          key: const ValueKey('settings-appearance-themes'),
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CodeLabText(
                  l10n.appearanceThemesTitle,
                  role: CodeLabTextRole.strong,
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in [...builtIn, ...custom])
                    _ThemeCard(
                      card: card,
                      selected: card.id == state.selectedId,
                    ),
                  if (state.loading)
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: ProgressRing(
                          key: ValueKey('settings-appearance-themes-loading'),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Карточка темы: мини-превью кода, имя, вид, тег режима и бейдж `N warnings`
/// или тег `Invalid`.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.card, required this.selected});

  final AppearanceThemeCard card;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final resources = FluentTheme.of(context).resources;
    final accent = FluentTheme.of(context).accentColor;
    final kind = switch (card.kind) {
      AppearanceThemeKind.builtInDefault => l10n.appearanceKindBuiltInDefault,
      AppearanceThemeKind.builtIn => l10n.appearanceKindBuiltIn,
      AppearanceThemeKind.custom =>
        card.extendsBase == null
            ? l10n.appearanceKindCustomUnknown
            : l10n.appearanceKindCustom(card.extendsBase!),
    };
    return GestureDetector(
      key: ValueKey('settings-appearance-theme-${card.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          _fire(context.read<AppearanceSettingsCubit>().select(card.id)),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 210,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: resources.cardBackgroundFillColorDefault,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? accent.defaultBrushFor(FluentTheme.of(context).brightness)
                    : resources.cardStrokeColorDefault,
                width: selected ? 2 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MiniPreview(card: card),
                  const SizedBox(height: 8),
                  CodeLabText(
                    _themeName(l10n, card.id),
                    role: CodeLabTextRole.strong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CodeLabText(kind, role: CodeLabTextRole.caption),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (card.mode != null)
                        CodeLabBadge(
                          label: card.mode == Brightness.light
                              ? l10n.appearanceTagLightMode
                              : l10n.appearanceTagDarkMode,
                        ),
                      if (!card.loaded)
                        CodeLabBadge(
                          label: l10n.appearanceTagInvalid,
                          tone: CodeLabTone.danger,
                        )
                      else if (card.warningCount > 0)
                        KeyedSubtree(
                          key: ValueKey(
                            'settings-appearance-theme-${card.id}-warnings',
                          ),
                          child: CodeLabBadge(
                            label: l10n.appearanceWarningsBadge(
                              card.warningCount,
                            ),
                            tone: CodeLabTone.warning,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Цвет ссылки роли `info`: у `AccentColor` — оттенок режима темы.
Color _linkColor(FluentThemeData theme) {
  final info = CodeLabPalette.of(theme).info;
  return info is AccentColor ? info.defaultBrushFor(theme.brightness) : info;
}

/// Мини-превью кода в цветах темы карточки (фон кода, текст и классы
/// токенов); у темы, которая не загрузилась, — приглушённая заглушка.
class _MiniPreview extends StatelessWidget {
  const _MiniPreview({required this.card});

  final AppearanceThemeCard card;

  @override
  Widget build(BuildContext context) {
    final theme = card.theme;
    final resources = FluentTheme.of(context).resources;
    final code = theme == null ? null : CodeLabCodeTheme.of(theme);
    final plain = code?.plain ?? resources.textFillColorSecondary;
    TextSpan span(String text, CodeLabTokenClass? tokenClass) => TextSpan(
      text: text,
      style: TextStyle(
        color: tokenClass == null ? plain : code?.colorOf(tokenClass) ?? plain,
      ),
    );
    return DecoratedBox(
      key: ValueKey('settings-appearance-theme-${card.id}-preview'),
      decoration: BoxDecoration(
        color: code?.background ?? resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          width: double.infinity,
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
              children: [
                span(_previewSampleComment, CodeLabTokenClass.comment),
                const TextSpan(text: '\n'),
                span('$_previewKeyword ', CodeLabTokenClass.keyword),
                span('delay = ', null),
                span('250', CodeLabTokenClass.number),
                span(';\n', null),
                span('return ', CodeLabTokenClass.keyword),
                span("'ok'", CodeLabTokenClass.string),
                span(';', null),
              ],
            ),
            maxLines: 4,
            overflow: TextOverflow.clip,
          ),
        ),
      ),
    );
  }
}

class _CustomBlock extends StatelessWidget {
  const _CustomBlock();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AppearanceSettingsCubit, AppearanceSettingsState>(
      buildWhen: (a, b) =>
          a.import != b.import ||
          a.themesLabel != b.themesLabel ||
          a.themesDirectoryLabel != b.themesDirectoryLabel ||
          a.catalogFailed != b.catalogFailed,
      builder: (context, state) {
        final importing =
            state.import.status == AppearanceImportStatus.importing;
        final failed = state.import.status == AppearanceImportStatus.failed;
        final label = state.themesLabel;
        // Готовая подпись каталога из composition root: страница не режет
        // маску `*.json` из подписи строкой.
        final directory = state.themesDirectoryLabel ?? '';
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CodeLabText(
                l10n.appearanceCustomTitle,
                role: CodeLabTextRole.strong,
              ),
              if (label != null)
                CodeLabText(label, role: CodeLabTextRole.caption),
              if (state.catalogFailed) ...[
                const SizedBox(height: 8),
                // Причина (исключение порта) в тексте не показывается: в ней
                // бывают пути; «Reload» повторяет чтение.
                InfoBar(
                  key: const ValueKey('settings-appearance-catalog-failed'),
                  title: Text(l10n.appearanceCatalogFailed(directory)),
                  severity: InfoBarSeverity.warning,
                  action: Button(
                    key: const ValueKey('settings-appearance-catalog-reload'),
                    onPressed: () =>
                        _fire(context.read<AppearanceSettingsCubit>().reload()),
                    child: Text(l10n.appearanceReload),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Button(
                  key: const ValueKey('settings-appearance-import'),
                  onPressed: importing
                      ? null
                      : () => _fire(
                          context.read<AppearanceSettingsCubit>().importJson(),
                        ),
                  child: Text(l10n.appearanceImportButton),
                ),
              ),
              if (failed) ...[
                const SizedBox(height: 8),
                InfoBar(
                  key: const ValueKey('settings-appearance-import-failed'),
                  title: Text(
                    state.import.pickerFailed
                        ? l10n.appearanceImportPickerFailed
                        : state.import.sourceChanged
                        ? l10n.appearanceImportSourceChanged
                        : state.import.writeFailed
                        ? l10n.appearanceImportFailedGeneric
                        : l10n.appearanceImportFailed(
                            escapeForDisplay(state.import.fileName ?? ''),
                            state.import.issue == null
                                ? ''
                                : themeErrorAt(l10n, state.import.issue!),
                          ),
                  ),
                  severity: InfoBarSeverity.error,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Панель проблем выбранной темы: InfoBar, текст файла, список проблем и
/// справка о незаданных ролях. Показывается, только если есть что показать.
class _IssuesBlock extends StatelessWidget {
  const _IssuesBlock();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AppearanceSettingsCubit, AppearanceSettingsState>(
      buildWhen: (a, b) => a.selection != b.selection,
      builder: (context, state) {
        final selection = state.selection;
        if (selection == null) return const SizedBox.shrink();
        final hasError = selection.error != null || selection.readError != null;
        final hasIssues = selection.issues.isNotEmpty;
        final hasUnset = selection.unsetRoles.isNotEmpty && !hasError;
        if (!hasError && !hasIssues && !hasUnset) {
          return const SizedBox.shrink();
        }
        final id = selection.card.id;
        final file = escapeForDisplay('${selection.card.name}.json');
        final name = _themeName(l10n, id);
        final cubit = context.read<AppearanceSettingsCubit>();
        final base = selection.card.extendsBase ?? 'dark';
        final text = selection.fileText;
        return Padding(
          key: const ValueKey('settings-appearance-issues'),
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasError || hasIssues)
                InfoBar(
                  key: const ValueKey('settings-appearance-issues-summary'),
                  title: Text(
                    hasError
                        ? l10n.appearanceIssuesError(name)
                        : l10n.appearanceIssuesSummary(
                            name,
                            selection.card.warningCount,
                          ),
                  ),
                  content: hasError
                      ? null
                      : Text(_issuesHint(l10n, selection, base)),
                  severity: hasError
                      ? InfoBarSeverity.error
                      : InfoBarSeverity.warning,
                  action: Wrap(
                    spacing: 8,
                    children: [
                      Button(
                        key: const ValueKey('settings-appearance-open-folder'),
                        onPressed: () => _fire(cubit.openFolder()),
                        child: Text(l10n.appearanceOpenFolder),
                      ),
                      Button(
                        key: const ValueKey('settings-appearance-reload'),
                        onPressed: () => _fire(cubit.reload()),
                        child: Text(l10n.appearanceReload),
                      ),
                    ],
                  ),
                ),
              if (text != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  key: const ValueKey('settings-appearance-file'),
                  height: 240,
                  child: CodeLabFilePreview(
                    relativePath: file,
                    content: CodeLabFilePreviewContent.text(
                      _escapeFileText(text),
                    ),
                    warningLines: selection.warningLines,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ..._issueRows(l10n, selection, file),
              if (hasUnset) ...[
                const SizedBox(height: 8),
                _UnsetRoles(roles: selection.unsetRoles, base: base),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Строки списка проблем: не больше [_issueLimit], остальное — строкой
  /// «… and M more warnings». Файл может содержать любое число предупреждений,
  /// а список строит виджеты на каждую (D9а); бейдж карточки и InfoBar считают
  /// все.
  /// Пояснение под InfoBar по составу проблем: фраза о неизвестных ключах — только
  /// если они есть, о ролях из `extends` — только если есть незаданные роли.
  String _issuesHint(
    AppLocalizations l10n,
    AppearanceSelection selection,
    String base,
  ) {
    final hasUnknownKeys = selection.issues.any(
      (i) =>
          i is AppearanceParseIssue &&
          i.issue.code == ThemeIssueCode.unknownKey,
    );
    return [
      hasUnknownKeys
          ? l10n.appearanceIssuesHintUnknownKeys
          : l10n.appearanceIssuesHintApplied,
      if (selection.unsetRoles.isNotEmpty)
        l10n.appearanceIssuesHintExtends(base, _themeName(l10n, base)),
    ].join(' ');
  }

  List<Widget> _issueRows(
    AppLocalizations l10n,
    AppearanceSelection selection,
    String file,
  ) {
    final head = <({String title, String? note})>[
      if (selection.error case final error?)
        (title: themeErrorTitle(l10n, file, error), note: null),
      if (selection.readError case final ThemeReadError error)
        (title: themeReadErrorReason(l10n, error), note: null),
    ];
    final total = head.length + selection.issues.length;
    // Тексты строятся только для показанных строк.
    final rows = [
      ...head,
      for (final issue in selection.issues.take(
        (_issueLimit - head.length).clamp(0, _issueLimit),
      ))
        switch (issue) {
          AppearanceParseIssue(:final issue) => (
            title: themeIssueTitle(l10n, file, issue),
            note: themeIssueNote(l10n, issue),
          ),
          AppearanceLowContrastIssue(:final role, :final ratio) => (
            title: l10n.appearanceIssueLowContrast(
              role.qualifiedName,
              ratio.toStringAsFixed(1),
            ),
            note: l10n.appearanceIssueLowContrastHint,
          ),
        },
    ];
    return [
      for (var i = 0; i < rows.length; i++)
        Padding(
          key: ValueKey('settings-appearance-issue-${i + 1}'),
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeLabText(escapeForDisplay(rows[i].title)),
              if (rows[i].note case final note?)
                CodeLabText(note, role: CodeLabTextRole.caption),
            ],
          ),
        ),
      if (total > rows.length)
        Padding(
          key: const ValueKey('settings-appearance-issues-more'),
          padding: const EdgeInsets.only(bottom: 6),
          child: CodeLabText(
            l10n.appearanceIssuesMore(total - rows.length),
            role: CodeLabTextRole.caption,
          ),
        ),
    ];
  }
}

/// Справка о незаданных ролях: «N roles not set — taken from "dark"».
class _UnsetRoles extends StatelessWidget {
  const _UnsetRoles({required this.roles, required this.base});

  final List<ThemeRole> roles;
  final String base;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const ValueKey('settings-appearance-unset-roles'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeLabText(
          l10n.appearanceUnsetRoles(roles.length, base),
          role: CodeLabTextRole.strong,
        ),
        CodeLabText(
          '${l10n.appearanceUnsetRolesNote}: '
          '${roles.map((r) => r.qualifiedName).join(', ')}',
          role: CodeLabTextRole.caption,
        ),
      ],
    );
  }
}

/// Правая колонка: «Preview», «Contrast on code background», «Reset» и «Use».
class _PreviewColumn extends StatelessWidget {
  const _PreviewColumn();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AppearanceSettingsCubit, AppearanceSettingsState>(
      buildWhen: (a, b) => a.selection != b.selection,
      builder: (context, state) {
        final selection = state.selection;
        if (selection == null) return const SizedBox.shrink();
        final card = selection.card;
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                key: const ValueKey('settings-appearance-preview'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CodeLabText(
                    l10n.appearancePreviewTitle,
                    role: CodeLabTextRole.strong,
                  ),
                  const SizedBox(height: 8),
                  _PreviewBody(card: card),
                ],
              ),
              const SizedBox(height: 12),
              _ContrastBlock(card: card),
              const SizedBox(height: 12),
              _ActionButtons(card: card),
            ],
          ),
        );
      },
    );
  }
}

/// Образец: блок кода, строки diff и статусы — цветами выбранной темы.
class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.card});

  final AppearanceThemeCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = card.theme ?? FluentTheme.of(context);
    final code = CodeLabCodeTheme.of(theme);
    final palette = CodeLabPalette.of(theme);
    TextSpan span(String text, CodeLabTokenClass? tokenClass) => TextSpan(
      text: text,
      style: TextStyle(
        color: tokenClass == null ? code.plain : code.colorOf(tokenClass),
      ),
    );
    Widget status(IconData icon, String label, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: code.background,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _previewLanguage,
                  style: TextStyle(
                    color: code.colorOf(CodeLabTokenClass.comment),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    children: [
                      span(
                        '$_previewSampleComment\n',
                        CodeLabTokenClass.comment,
                      ),
                      span('$_previewKeyword ', CodeLabTokenClass.keyword),
                      span('delay = ', null),
                      span('250', CodeLabTokenClass.number),
                      span(';', null),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ColoredBox(
                  color: palette.diffRemoveBackground,
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      _previewSampleRemoved,
                      style: TextStyle(
                        color: code.plain,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                ColoredBox(
                  color: palette.diffAddBackground,
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      _previewSampleAdded,
                      style: TextStyle(
                        color: code.plain,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                // Статусы — часть карточки превью: их цвета принадлежат выбранной
                // теме и рисуются на её фоне, а не на фоне страницы (ручная
                // проверка: тёмная страница и светлая тема давали нечитаемый
                // текст).
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    Text(
                      l10n.appearancePreviewLink,
                      style: TextStyle(
                        color: _linkColor(theme),
                        decoration: TextDecoration.underline,
                        fontSize: 12,
                      ),
                    ),
                    status(
                      FluentIcons.accept,
                      l10n.appearancePreviewDone,
                      palette.success,
                    ),
                    status(
                      FluentIcons.warning,
                      l10n.appearancePreviewContext,
                      palette.warning,
                    ),
                    status(
                      FluentIcons.chrome_close,
                      l10n.appearancePreviewFailed,
                      palette.danger,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Блок «Contrast on code background»: строки по ролям, вердикт и пояснение.
class _ContrastBlock extends StatelessWidget {
  const _ContrastBlock({required this.card});

  final AppearanceThemeCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = <(ThemeRole, String)>[
      (ThemeRole.text, l10n.appearanceContrastText),
      (ThemeRole.codeComment, l10n.appearanceContrastComment),
      (ThemeRole.codeKeyword, l10n.appearanceContrastKeyword),
      (ThemeRole.info, l10n.appearancePreviewLink),
      (ThemeRole.error, l10n.appearanceContrastError),
    ];
    return Column(
      key: const ValueKey('settings-appearance-contrast'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CodeLabText(l10n.appearanceContrastTitle, role: CodeLabTextRole.strong),
        const SizedBox(height: 6),
        for (final (role, label) in rows)
          if (card.contrast.where((c) => c.role == role).firstOrNull
              case final check?)
            Padding(
              key: ValueKey(
                'settings-appearance-contrast-${role.qualifiedName}',
              ),
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: check.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const SizedBox(width: 14, height: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: CodeLabText(label)),
                  CodeLabText('${check.ratio.toStringAsFixed(1)}:1'),
                  const SizedBox(width: 8),
                  CodeLabBadge(
                    label: check.passes
                        ? l10n.appearanceContrastPass
                        : l10n.appearanceContrastLow,
                    tone: check.passes
                        ? CodeLabTone.success
                        : CodeLabTone.warning,
                  ),
                ],
              ),
            ),
        const SizedBox(height: 4),
        CodeLabText(l10n.appearanceContrastNote, role: CodeLabTextRole.caption),
      ],
    );
  }
}

/// «Reset» и «Use `<name>`»: доступность зависит от темы, назначенной режиму.
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.card});

  final AppearanceThemeCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<AppearanceSettingsCubit>();
    return BlocBuilder<AppAppearanceCubit, AppAppearanceState>(
      builder: (context, state) {
        final mode = card.mode;
        final assigned = mode == null ? null : _assigned(state, mode);
        final defaultId = mode == Brightness.light ? 'light' : 'dark';
        // Оформлению назначается имя темы, а не идентификатор карточки.
        final canUse = card.loaded && assigned != card.name;
        final canReset = mode != null && assigned != defaultId;
        // Wrap, а не Row: по-русски «Использовать <имя>» не помещается рядом с
        // «Сбросить» в правой колонке 380 px.
        return Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            Button(
              key: const ValueKey('settings-appearance-reset'),
              onPressed: canReset ? () => _fire(cubit.resetSelected()) : null,
              child: Text(l10n.appearanceReset),
            ),
            FilledButton(
              key: const ValueKey('settings-appearance-use'),
              onPressed: canUse ? () => _fire(cubit.useSelected()) : null,
              child: Text(l10n.appearanceUse(_themeName(l10n, card.id))),
            ),
          ],
        );
      },
    );
  }
}

/// Диалог замены темы: открывается, когда импорт сообщил `needsReplace`.
///
/// Почему `BlocListener` плюс проверка начального состояния: слушатель отдаёт
/// только последующие изменения, а страница может открыться уже поверх
/// `needsReplace` (состояние готово до первого кадра) — тогда диалог
/// открывается из `didChangeDependencies` после первого кадра.
class _ReplaceDialogGate extends StatefulWidget {
  const _ReplaceDialogGate({required this.child});

  final Widget child;

  @override
  State<_ReplaceDialogGate> createState() => _ReplaceDialogGateState();
}

class _ReplaceDialogGateState extends State<_ReplaceDialogGate> {
  bool _open = false;
  bool _initialChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialChecked) return;
    _initialChecked = true;
    final state = context.read<AppearanceSettingsCubit>().state;
    if (state.import.status == AppearanceImportStatus.needsReplace) {
      // Диалогу нужен готовый Navigator: открываем после первого кадра.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fire(_show(state.import.name ?? ''));
      });
    }
  }

  Future<void> _show(String name) async {
    if (_open) return;
    _open = true;
    final cubit = context.read<AppearanceSettingsCubit>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return ContentDialog(
          title: Text(l10n.appearanceReplaceTitle(escapeForDisplay(name))),
          content: Text(l10n.appearanceReplaceBody),
          actions: [
            Button(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              key: const ValueKey('settings-appearance-import-replace'),
              onPressed: () {
                _fire(cubit.confirmReplace());
                Navigator.of(dialogContext).pop();
              },
              child: Text(l10n.appearanceReplaceConfirm),
            ),
          ],
        );
      },
    );
    _open = false;
    // Закрытие без «Replace» (Cancel, Esc) — отказ от замены.
    if (cubit.state.import.status == AppearanceImportStatus.needsReplace) {
      cubit.cancelReplace();
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<AppearanceSettingsCubit, AppearanceSettingsState>(
        listenWhen: (a, b) =>
            a.import.status != b.import.status &&
            b.import.status == AppearanceImportStatus.needsReplace,
        listener: (context, state) => _fire(_show(state.import.name ?? '')),
        child: widget.child,
      );
}
