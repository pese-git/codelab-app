// Красные тесты страницы «Appearance» (задача 5.5 change
// `add-app-appearance-page`; spec app-settings «Страница «Appearance»:
// видимость и состав», «Режим оформления и темы режимов», «Системный
// акцент», «Карточки тем и превью», «Пользовательские темы на странице
// «Appearance»», «Импорт темы на странице «Appearance»», «Контраст на фоне
// кода», «Хранение оформления» (ошибка сохранения); design.md D10, D11, D14,
// D15; артборд «10 Settings — Appearance»).
//
// Страница читает `AppearanceSettingsCubit` (временное состояние страницы) и
// `AppAppearanceCubit` (применённое оформление) из ближайших `BlocProvider` и
// только рисует состояние и передаёт жесты. Состояние страницы задаёт
// Cubit-двойник (`_FakeSettingsCubit`): он не читает каталог и не импортирует
// файлы, а записывает вызовы; реальный Cubit проверяет
// `appearance_settings_cubit_test.dart`.
//
// Ключи — из spec: `settings-appearance`, `-mode`, `-mode-light|dark|system`,
// `-system-accent`, `-themes`, `-theme-<id>`, `-theme-<id>-warnings`,
// `-import`, `-issues`, `-issues-summary`, `-open-folder`, `-reload`,
// `-issue-<n>`, `-unset-roles`, `-preview`, `-contrast`, `-contrast-<role>`,
// `-reset`, `-use`, `-fallback`, `-save-retry`, `-import-failed`,
// `-import-replace`. Ключей, которых в spec нет, вводит этот тест:
// `settings-appearance-themes-loading` (индикатор загрузки каталога),
// `settings-appearance-file` (просмотр текста файла).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/appearance/app_appearance_cubit.dart';
import 'package:codelab_desktop/app/appearance/app_appearance_start.dart';
import 'package:codelab_desktop/app/appearance/built_in_themes.dart';
import 'package:codelab_desktop/app/appearance/fluent_theme_builder.dart';
import 'package:codelab_desktop/app/default_settings_pages.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/app_appearance_preferences.dart';
import 'package:codelab_desktop/core/platform/system_accent_source.dart';
import 'package:codelab_desktop/features/settings/application/appearance_settings_cubit.dart';
import 'package:codelab_desktop/features/settings/application/contrast_checks.dart';
import 'package:codelab_desktop/features/settings/presentation/appearance_page.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_shell.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_local_folder_opener.dart';
import '../../../support/fake_theme_file_picker.dart';
import '../../../support/l10n_app.dart';
import '../../../support/l10n_mix.dart';
import '../../../support/l10n_page_harness.dart';
import '../../../support/settings_search.dart';

// ---- данные ----

const _twoWarnings = '''{
  "name": "acme-night",
  "extends": "dark",
  "colors": {
    "accent": "#b4a0ff",
    "acent": "#b4a0ff",
    "success": "#a6e3a1",
    "error": "#f38ba8",
    "tab_bg": "#1b1830",
    "code": { "keyword": "#ff79c6", "string": "#a6e3a1",
      "type": "#89b4fa", "comment": "#c0c4d8" }
  }
}''';

ThemeLoaded _parsed(String name, String text) =>
    ThemeFile.parse('$name.json', text) as ThemeLoaded;

AppearanceThemeCard _builtIn(String id) {
  final file = builtInThemeFile(id);
  final theme = buildFluentTheme(file);
  return AppearanceThemeCard(
    id: id,
    kind: id == 'high-contrast'
        ? AppearanceThemeKind.builtIn
        : AppearanceThemeKind.builtInDefault,
    loaded: true,
    mode: id == 'light' ? Brightness.light : Brightness.dark,
    theme: theme,
    contrast: checkContrast(theme),
  );
}

AppearanceThemeCard _custom(
  String id,
  String text, {
  int parseWarnings = 0,
  List<ContrastCheck>? contrast,
}) {
  final loaded = _parsed(id, text);
  final theme = buildFluentTheme(loaded.theme);
  return AppearanceThemeCard(
    id: id,
    kind: AppearanceThemeKind.custom,
    loaded: true,
    mode: loaded.theme.base == ThemeBase.light
        ? Brightness.light
        : Brightness.dark,
    extendsBase: loaded.theme.base.jsonName,
    theme: theme,
    contrast: contrast ?? checkContrast(theme),
    parseWarnings: parseWarnings,
  );
}

const _invalidCard = AppearanceThemeCard(
  id: 'broken',
  kind: AppearanceThemeKind.custom,
  loaded: false,
);

/// Карточка `acme-night` с двумя предупреждениями и её данные панели.
AppearanceSelection _twoWarningsSelection({String? text}) {
  final card = _custom('acme-night', _twoWarnings, parseWarnings: 2);
  final parsed = _parsed('acme-night', _twoWarnings);
  return AppearanceSelection(
    card: card,
    fileText: text ?? _twoWarnings,
    issues: [for (final w in parsed.warnings) AppearanceParseIssue(w)],
    unsetRoles: const [
      ThemeRole.warning,
      ThemeRole.info,
      ThemeRole.selection,
      ThemeRole.codeNumber,
      ThemeRole.codeFunction,
    ],
  );
}

AppearanceSettingsState _state({
  List<AppearanceThemeCard>? custom,
  String selectedId = 'dark',
  AppearanceSelection? selection,
  bool loading = false,
  AppearanceImport import = const AppearanceImport(),
}) {
  final cards = [
    _builtIn('light'),
    _builtIn('dark'),
    _builtIn('high-contrast'),
    ...?custom,
  ];
  return AppearanceSettingsState(
    loading: loading,
    cards: cards,
    selectedId: selectedId,
    selection:
        selection ??
        AppearanceSelection(card: cards.singleWhere((c) => c.id == selectedId)),
    import: import,
    themesLabel: '~/.codelab/themes/*.json',
  );
}

/// Cubit-двойник: состояние задаёт тест, вызовы записываются.
final class _FakeSettingsCubit extends AppearanceSettingsCubit {
  _FakeSettingsCubit(AppearanceSettingsState initial, AppAppearanceCubit app)
    : super(
        library: InMemoryThemeLibrary(),
        appearance: app,
        picker: FakeThemeFilePicker(),
        folderOpener: FakeLocalFolderOpener(),
        systemBrightness: () => Brightness.dark,
      ) {
    emit(initial);
  }

  final calls = <String>[];

  void set(AppearanceSettingsState state) => emit(state);

  @override
  Future<void> load() async => calls.add('load');

  @override
  Future<void> reload() async => calls.add('reload');

  @override
  Future<void> select(String id) async {
    calls.add('select:$id');
    final card = state.cards.singleWhere((c) => c.id == id);
    emit(
      state.copyWith(
        selectedId: id,
        selection: id == 'acme-night'
            ? _twoWarningsSelection()
            : AppearanceSelection(card: card),
      ),
    );
  }

  @override
  Future<void> importJson() async => calls.add('import');

  @override
  Future<void> confirmReplace() async => calls.add('replace');

  @override
  void cancelReplace() => calls.add('cancel-replace');

  @override
  Future<void> openFolder() async => calls.add('open-folder');

  @override
  Future<void> useSelected() async => calls.add('use');

  @override
  Future<void> resetSelected() async => calls.add('reset');
}

/// Хранилище, чья запись падает один раз.
final class _FailsOnce implements AppAppearancePreferences {
  int saves = 0;

  @override
  Future<AppAppearanceLoad> load() async =>
      const AppAppearanceLoad(AppAppearanceSettings());

  @override
  Future<void> save(AppAppearanceSettings settings) async {
    saves++;
    if (saves == 1) throw StateError('disk is read-only: /secret/path');
  }
}

final class _Memory implements AppAppearancePreferences {
  @override
  Future<AppAppearanceLoad> load() async =>
      const AppAppearanceLoad(AppAppearanceSettings());

  @override
  Future<void> save(AppAppearanceSettings settings) async {}
}

/// Источник акцента с поддержкой — строка «Accent color» видна.
final class _SupportedAccent implements SystemAccentSource {
  @override
  bool get supported => true;

  @override
  Future<int?> read() async => 0xFFFF2D55;

  @override
  Stream<int?> get changes => const Stream.empty();
}

void main() {
  late AppAppearanceCubit app;
  late _FakeSettingsCubit settings;

  AppAppearanceCubit buildApp({
    AppAppearanceSettings values = const AppAppearanceSettings(),
    ThemeLoaded? dark,
    bool accentSupported = false,
    AppAppearancePreferences? preferences,
  }) {
    final cubit = AppAppearanceCubit(
      preferences: preferences ?? _Memory(),
      library: InMemoryThemeLibrary(),
      accentSource: accentSupported
          ? _SupportedAccent()
          : const UnsupportedSystemAccentSource(),
      start: AppAppearanceStart(
        settings: values,
        darkTheme: dark,
        systemAccentSupported: accentSupported,
        systemAccent: accentSupported ? 0xFFFF2D55 : null,
      ),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    AppearanceSettingsState state, {
    Locale locale = const Locale('en'),
    double width = 1200,
    AppAppearanceCubit? appearance,
    Brightness system = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = system;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    app = appearance ?? app;
    settings = _FakeSettingsCubit(state, app);
    addTearDown(settings.close);
    await tester.pumpWidget(
      localizedFluentApp(
        locale: locale,
        ScaffoldPage(
          padding: EdgeInsets.zero,
          content: MultiBlocProvider(
            providers: [
              BlocProvider<AppAppearanceCubit>.value(value: app),
              BlocProvider<AppearanceSettingsCubit>.value(value: settings),
            ],
            child: const SingleChildScrollView(child: AppearancePage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey('settings-appearance$name'));

  setUp(() => app = buildApp());

  group('видимость, состав и порядок (spec «Страница «Appearance»»)', () {
    testWidgets('все блоки в порядке артборда, превью — правая колонка от '
        '960 px', (tester) async {
      app = buildApp(accentSupported: true);
      await pumpPage(
        tester,
        _state(
          custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)],
          selectedId: 'acme-night',
          selection: _twoWarningsSelection(),
        ),
      );

      for (final suffix in const [
        '',
        '-mode',
        '-system-accent',
        '-themes',
        '-import',
        '-issues',
        '-preview',
        '-contrast',
        '-reset',
        '-use',
      ]) {
        expect(
          key(suffix),
          findsOneWidget,
          reason: 'settings-appearance$suffix',
        );
      }
      double top(String suffix) => tester.getTopLeft(key(suffix)).dy;
      expect(top('-mode'), lessThan(top('-system-accent')));
      expect(top('-system-accent'), lessThan(top('-themes')));
      expect(top('-themes'), lessThan(top('-import')));
      expect(top('-import'), lessThan(top('-issues')));
      // «Preview» стоит правой колонкой: правее карточек тем.
      expect(
        tester.getTopLeft(key('-preview')).dx,
        greaterThanOrEqualTo(tester.getTopRight(key('-themes')).dx),
      );
    });

    testWidgets('«Узкая область»: при 800 px «Preview» под панелью проблем', (
      tester,
    ) async {
      app = buildApp(accentSupported: true);
      await pumpPage(
        tester,
        _state(
          custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)],
          selectedId: 'acme-night',
          selection: _twoWarningsSelection(),
        ),
        width: 800,
      );

      expect(
        tester.getTopLeft(key('-preview')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(key('-issues')).dy),
      );
    });

    test('«Страница видна»: appearance в defaultSettingsPages сразу после '
        'general и имеет построитель', () {
      final visible = defaultSettingsPages.visible.toList();

      expect(visible, contains(SettingsPage.appearance));
      expect(
        visible.indexOf(SettingsPage.appearance),
        visible.indexOf(SettingsPage.general) + 1,
      );
      expect(settingsPageBuilders, contains(SettingsPage.appearance));
    });

    group('«Поиск по ключевому слову»', () {
      const pages = [SettingsPage.general, SettingsPage.appearance];

      test('английские слова находят Appearance при любом языке', () {
        for (final word in const [
          'theme',
          'dark',
          'light',
          'mode',
          'color',
          'accent',
          'contrast',
          'json',
        ]) {
          expect(
            searchSettings(pages, word),
            contains(SettingsPage.appearance),
            reason: word,
          );
          expect(
            searchSettings(pages, word, locale: 'ru'),
            contains(SettingsPage.appearance),
            reason: 'ru: $word',
          );
        }
      });

      test('русские слова находят Appearance при русском интерфейсе', () {
        for (final word in const [
          'тема',
          'тёмная',
          'светлая',
          'режим',
          'цвет',
          'акцент',
          'контраст',
          'оформление',
        ]) {
          expect(
            searchSettings(pages, word, locale: 'ru'),
            contains(SettingsPage.appearance),
            reason: word,
          );
        }
      });

      test('сообщение settingsSearchKeywordsAppearance есть в en и ru', () {
        expect(
          settingsKeywordsMessageOf('en', SettingsPage.appearance),
          isNotNull,
        );
        expect(
          settingsKeywordsMessageOf('ru', SettingsPage.appearance),
          isNotNull,
        );
      });
    });
  });

  group('«Mode» (spec «Режим оформления и темы режимов»)', () {
    testWidgets('три значения Light, Dark, Match system; у Match system в '
        'скобках режим системы', (tester) async {
      await pumpPage(tester, _state(), system: Brightness.dark);

      expect(key('-mode-light'), findsOneWidget);
      expect(key('-mode-dark'), findsOneWidget);
      expect(key('-mode-system'), findsOneWidget);
      expect(
        tester.getTopLeft(key('-mode-light')).dx,
        lessThan(tester.getTopLeft(key('-mode-dark')).dx),
      );
      expect(
        tester.getTopLeft(key('-mode-dark')).dx,
        lessThan(tester.getTopLeft(key('-mode-system')).dx),
      );
      expect(find.text('Match system (dark)'), findsOneWidget);
    });

    testWidgets('при светлой системе — Match system (light)', (tester) async {
      await pumpPage(tester, _state(), system: Brightness.light);

      expect(find.text('Match system (light)'), findsOneWidget);
    });

    testWidgets('выбор значения вызывает AppAppearanceCubit.setMode', (
      tester,
    ) async {
      await pumpPage(tester, _state());

      await tester.tap(key('-mode-dark'));
      await tester.pumpAndSettle();

      expect(app.state.mode, AppearanceMode.dark);
    });
  });

  group('«Accent color» (spec «Системный акцент»)', () {
    testWidgets('строка видна, когда платформа отдаёт акцент; переключатель '
        'выключен по умолчанию', (tester) async {
      app = buildApp(accentSupported: true);
      await pumpPage(tester, _state());

      expect(key('-system-accent'), findsOneWidget);
      expect(find.text('Use system accent'), findsOneWidget);
      expect(
        tester
            .widget<ToggleSwitch>(
              find.descendant(
                of: key('-system-accent'),
                matching: find.byType(ToggleSwitch),
              ),
            )
            .checked,
        isFalse,
      );
    });

    testWidgets(
      'переключатель включает системный акцент в AppAppearanceCubit',
      (tester) async {
        app = buildApp(accentSupported: true);
        await pumpPage(tester, _state());

        await tester.tap(
          find.descendant(
            of: key('-system-accent'),
            matching: find.byType(ToggleSwitch),
          ),
        );
        await tester.pumpAndSettle();

        expect(app.state.systemAccent, isTrue);
      },
    );

    testWidgets('«Платформа без системного акцента»: строки нет', (
      tester,
    ) async {
      await pumpPage(tester, _state());

      expect(key('-system-accent'), findsNothing);
      expect(find.text('Use system accent'), findsNothing);
    });
  });

  group('карточки тем (spec «Карточки тем и превью»)', () {
    testWidgets('встроенные, затем пользовательские; вид и теги режимов', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _state(custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)]),
      );

      for (final id in const ['light', 'dark', 'high-contrast', 'acme-night']) {
        expect(key('-theme-$id'), findsOneWidget, reason: id);
      }
      final order = [
        for (final id in const ['light', 'dark', 'high-contrast', 'acme-night'])
          tester.getTopLeft(key('-theme-$id')),
      ];
      // Порядок слева направо и сверху вниз: каждая следующая не раньше.
      for (var i = 1; i < order.length; i++) {
        expect(
          order[i].dy > order[i - 1].dy || order[i].dx > order[i - 1].dx,
          isTrue,
          reason: 'карточка $i стоит после предыдущей',
        );
      }
      String textIn(String id) => tester
          .widgetList<RichText>(
            find.descendant(
              of: key('-theme-$id'),
              matching: find.byType(RichText),
            ),
          )
          .map((w) => w.text.toPlainText())
          .join(' | ');
      expect(textIn('light'), contains('Fluent Light'));
      expect(textIn('light'), contains('Built-in · default'));
      expect(textIn('light'), contains('Light mode'));
      expect(textIn('dark'), contains('Fluent Dark'));
      expect(textIn('dark'), contains('Built-in · default'));
      expect(textIn('dark'), contains('Dark mode'));
      expect(textIn('high-contrast'), contains('High contrast'));
      expect(textIn('high-contrast'), isNot(contains('default')));
      expect(textIn('high-contrast'), contains('Dark mode'));
      expect(textIn('acme-night'), contains('acme-night'));
      expect(textIn('acme-night'), contains('Custom · extends dark'));
      expect(textIn('acme-night'), contains('Dark mode'));
    });

    testWidgets('мини-превью кода показано на карточке', (tester) async {
      await pumpPage(tester, _state());

      expect(
        find.descendant(
          of: key('-theme-dark'),
          matching: find.byKey(
            const ValueKey('settings-appearance-theme-dark-preview'),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('бейдж «N warnings» учитывает число (ICU plural)', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _state(
          custom: [
            _custom('acme-night', _twoWarnings, parseWarnings: 2),
            _custom(
              'one',
              _twoWarnings.replaceAll('acme-night', 'one'),
              parseWarnings: 1,
            ),
          ],
        ),
      );

      expect(
        find.descendant(
          of: key('-theme-acme-night-warnings'),
          matching: find.text('2 warnings'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('-theme-one-warnings'),
          matching: find.text('1 warning'),
        ),
        findsOneWidget,
      );
      expect(key('-theme-dark-warnings'), findsNothing);
    });

    testWidgets('тема, которая не загрузилась: тег Invalid вместо бейджа', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _state(
          custom: [_invalidCard],
          selectedId: 'broken',
          selection: const AppearanceSelection(
            card: _invalidCard,
            fileText: '{',
            error: ThemeIssue(ThemeIssueCode.invalidJson, line: 1, column: 1),
          ),
        ),
      );

      expect(
        find.descendant(
          of: key('-theme-broken'),
          matching: find.text('Invalid'),
        ),
        findsOneWidget,
      );
      expect(key('-theme-broken-warnings'), findsNothing);
    });

    testWidgets('«Выбор карточки не применяет тему»: нажатие вызывает '
        'select, оформление app не меняется', (tester) async {
      await pumpPage(
        tester,
        _state(custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)]),
      );

      await tester.tap(key('-theme-acme-night'));
      await tester.pumpAndSettle();

      expect(settings.calls, contains('select:acme-night'));
      expect(app.state.darkTheme, 'dark');
      expect(find.text('Use acme-night'), findsOneWidget);
    });

    testWidgets('пока каталог читается, на месте пользовательских тем '
        'индикатор, встроенные карточки работают', (tester) async {
      await pumpPage(tester, _state(loading: true));

      expect(key('-themes-loading'), findsOneWidget);
      expect(key('-theme-light'), findsOneWidget);
      expect(key('-theme-high-contrast'), findsOneWidget);
    });
  });

  group('«Custom themes» и импорт', () {
    testWidgets('путь каталога с ~ и кнопка «Import JSON…»', (tester) async {
      await pumpPage(tester, _state());

      expect(find.text('~/.codelab/themes/*.json'), findsOneWidget);
      expect(find.text('Import JSON…'), findsOneWidget);
      await tester.tap(key('-import'));
      await tester.pump();
      expect(settings.calls, contains('import'));
    });

    testWidgets('пока идёт импорт, кнопка недоступна', (tester) async {
      await pumpPage(
        tester,
        _state(
          import: const AppearanceImport(
            status: AppearanceImportStatus.importing,
          ),
        ),
      );

      await tester.tap(key('-import'));
      await tester.pump();

      expect(settings.calls, isNot(contains('import')));
    });

    testWidgets('ошибка разбора: InfoBar с именем файла и позицией', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _state(
          import: const AppearanceImport(
            status: AppearanceImportStatus.failed,
            fileName: 'night.json',
            issue: ThemeIssue(ThemeIssueCode.invalidJson, line: 3, column: 7),
          ),
        ),
      );

      final bar = tester.widget<InfoBar>(key('-import-failed'));
      expect(bar.severity, InfoBarSeverity.error);
      expect(
        find.textContaining("Couldn't import night.json:"),
        findsOneWidget,
      );
      expect(find.textContaining('3:7'), findsOneWidget);
    });

    testWidgets('ошибка записи: без текста исключения', (tester) async {
      await pumpPage(
        tester,
        _state(
          import: const AppearanceImport(
            status: AppearanceImportStatus.failed,
            fileName: 'night.json',
            writeFailed: true,
          ),
        ),
      );

      expect(find.textContaining("Couldn't save the theme to"), findsOneWidget);
      expect(find.textContaining('~/.codelab/themes'), findsWidgets);
    });

    testWidgets('нужна замена: диалог, «Replace» и «Cancel»', (tester) async {
      await pumpPage(
        tester,
        _state(
          import: const AppearanceImport(
            status: AppearanceImportStatus.needsReplace,
            name: 'acme-night',
          ),
        ),
      );

      expect(find.text('Replace the theme "acme-night"?'), findsOneWidget);
      await tester.tap(key('-import-replace'));
      await tester.pumpAndSettle();
      expect(settings.calls, contains('replace'));
    });

    testWidgets('«Cancel» в диалоге замены вызывает cancelReplace', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _state(
          import: const AppearanceImport(
            status: AppearanceImportStatus.needsReplace,
            name: 'acme-night',
          ),
        ),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(settings.calls, contains('cancel-replace'));
    });
  });

  group('панель проблем (spec «Пользовательские темы на странице»)', () {
    Future<void> pumpTwoWarnings(WidgetTester tester, {String? text}) =>
        pumpPage(
          tester,
          _state(
            custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)],
            selectedId: 'acme-night',
            selection: _twoWarningsSelection(text: text),
          ),
        );

    testWidgets('«Тема с двумя предупреждениями»: InfoBar, строки, список, '
        'справка', (tester) async {
      await pumpTwoWarnings(tester);

      final bar = tester.widget<InfoBar>(key('-issues-summary'));
      expect(bar.severity, InfoBarSeverity.warning);
      expect(find.text('acme-night loaded with 2 warnings'), findsOneWidget);
      expect(
        find.textContaining(
          'Unknown keys were ignored; the theme is applied. Missing roles '
          'come from extends: "dark" (Fluent Dark).',
        ),
        findsOneWidget,
      );
      final preview = tester.widget<CodeLabFilePreview>(
        find.byType(CodeLabFilePreview),
      );
      expect(preview.warningLines, {6, 9});
      String textOf(String suffix) => tester
          .widgetList<RichText>(
            find.descendant(of: key(suffix), matching: find.byType(RichText)),
          )
          .map((w) => w.text.toPlainText())
          .join(' ');
      expect(
        textOf('-issue-1'),
        allOf(
          contains('acme-night.json:6:5 unknown key "acent"'),
          contains('Ignored. Did you mean "accent"?'),
        ),
      );
      expect(
        textOf('-issue-2'),
        allOf(
          contains('acme-night.json:9:5 unknown key "tab_bg"'),
          contains('Ignored — not a theme role.'),
        ),
      );
      expect(key('-issue-3'), findsNothing);
    });

    testWidgets('справка о незаданных ролях: N, база, список, пояснение', (
      tester,
    ) async {
      await pumpTwoWarnings(tester);

      final text = tester
          .widgetList<RichText>(
            find.descendant(
              of: key('-unset-roles'),
              matching: find.byType(RichText),
            ),
          )
          .map((w) => w.text.toPlainText())
          .join(' ');
      expect(text, contains('5 roles not set — taken from "dark"'));
      expect(text, contains('For reference, not a warning'));
      expect(text, contains('warning'));
      expect(text, contains('code.number'));
      expect(text, isNot(contains('status_bg')));
      expect(text, isNot(contains('approval_border')));
    });

    testWidgets('кнопки «Open folder» и «Reload» вызывают Cubit', (
      tester,
    ) async {
      await pumpTwoWarnings(tester);

      expect(find.text('Open folder'), findsOneWidget);
      expect(find.text('Open file'), findsNothing);
      await tester.tap(key('-open-folder'));
      await tester.tap(key('-reload'));
      await tester.pump();

      expect(settings.calls, containsAll(['open-folder', 'reload']));
    });

    testWidgets(
      '«Управляющие символы в файле»: U+202E показан экранированным',
      (tester) async {
        await pumpTwoWarnings(
          tester,
          text: _twoWarnings.replaceFirst('acme-night', 'acme\u202Enight'),
        );

        final rendered = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((w) => w.text.toPlainText())
            .join('\n');
        expect(rendered, isNot(contains('\u202E')));
        expect(rendered, contains(r'\u202e'));
      },
    );

    testWidgets('тема с ошибкой: InfoBar error, текст файла, без справки', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _state(
          custom: [_invalidCard],
          selectedId: 'broken',
          selection: const AppearanceSelection(
            card: _invalidCard,
            fileText: '{',
            error: ThemeIssue(ThemeIssueCode.invalidJson, line: 1, column: 1),
          ),
        ),
      );

      final bar = tester.widget<InfoBar>(key('-issues-summary'));
      expect(bar.severity, InfoBarSeverity.error);
      expect(find.text("broken couldn't be loaded"), findsOneWidget);
      expect(find.byType(CodeLabFilePreview), findsOneWidget);
      expect(key('-unset-roles'), findsNothing);
    });

    testWidgets('нет предупреждений и ошибок, но есть незаданные роли: '
        'только справка', (tester) async {
      final card = _custom(
        'quiet',
        '{"name": "quiet", "extends": "dark", "colors": {"accent": "#b4a0ff"}}',
      );
      await pumpPage(
        tester,
        _state(
          custom: [card],
          selectedId: 'quiet',
          selection: AppearanceSelection(
            card: card,
            fileText: '{}',
            unsetRoles: const [ThemeRole.warning, ThemeRole.info],
          ),
        ),
      );

      expect(key('-issues'), findsOneWidget);
      expect(key('-unset-roles'), findsOneWidget);
      expect(key('-issues-summary'), findsNothing);
      expect(key('-issue-1'), findsNothing);
    });

    testWidgets('у встроенной темы панели проблем нет', (tester) async {
      await pumpPage(tester, _state());

      expect(key('-issues'), findsNothing);
    });

    testWidgets('низкий контраст: строка в списке проблем', (tester) async {
      final card = _custom(
        'dim',
        '{"name":"dim","extends":"dark","colors":{}}',
        contrast: [
          const ContrastCheck(
            role: ThemeRole.codeComment,
            color: Color(0xFF3A3650),
            ratio: 1.9,
          ),
        ],
      );
      await pumpPage(
        tester,
        _state(
          custom: [card],
          selectedId: 'dim',
          selection: AppearanceSelection(
            card: card,
            fileText: '{}',
            issues: const [
              AppearanceLowContrastIssue(ThemeRole.codeComment, 1.9),
            ],
          ),
        ),
      );

      expect(key('-issue-1'), findsOneWidget);
      expect(
        find.descendant(
          of: key('-issue-1'),
          matching: find.textContaining('Low contrast'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('-issue-1'),
          matching: find.textContaining('code.comment'),
        ),
        findsOneWidget,
      );
    });
  });

  group('«Preview» и контраст', () {
    testWidgets('превью рисуется цветами выбранной темы, а не применённой', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _state(
          custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)],
          selectedId: 'acme-night',
          selection: _twoWarningsSelection(),
        ),
      );

      for (final label in const [
        'dart',
        'Link',
        'Done',
        '84% context',
        'Failed',
      ]) {
        expect(
          find.descendant(of: key('-preview'), matching: find.text(label)),
          findsWidgets,
          reason: label,
        );
      }
      final theme = _custom('acme-night', _twoWarnings).theme!;
      final done = tester.widget<Text>(
        find.descendant(of: key('-preview'), matching: find.text('Done')).first,
      );
      expect(done.style?.color, CodeLabPalette.of(theme).success);
      expect(done.style?.color, const Color(0xFFA6E3A1));
    });

    testWidgets('строки контраста с отношением и вердиктом AA / Low', (
      tester,
    ) async {
      final card = _custom(
        'acme-night',
        _twoWarnings,
        parseWarnings: 2,
        contrast: const [
          ContrastCheck(
            role: ThemeRole.text,
            color: Color(0xFFFFFFFF),
            ratio: 12.34,
          ),
          ContrastCheck(
            role: ThemeRole.codeComment,
            color: Color(0xFF3A3650),
            ratio: 3.2,
          ),
          ContrastCheck(
            role: ThemeRole.codeKeyword,
            color: Color(0xFFFF79C6),
            ratio: 4.8,
          ),
          ContrastCheck(
            role: ThemeRole.info,
            color: Color(0xFF89B4FA),
            ratio: 4.5,
          ),
          ContrastCheck(
            role: ThemeRole.error,
            color: Color(0xFFF38BA8),
            ratio: 7.0,
          ),
        ],
      );
      await pumpPage(
        tester,
        _state(
          custom: [card],
          selectedId: 'acme-night',
          selection: AppearanceSelection(card: card, fileText: _twoWarnings),
        ),
      );

      String row(String role) => tester
          .widgetList<RichText>(
            find.descendant(
              of: key('-contrast-$role'),
              matching: find.byType(RichText),
            ),
          )
          .map((w) => w.text.toPlainText())
          .join(' ');
      expect(
        row('text'),
        allOf(contains('Text'), contains('12.3:1'), contains('AA')),
      );
      expect(
        row('code.comment'),
        allOf(contains('Comment'), contains('3.2:1'), contains('Low')),
      );
      expect(
        row('code.keyword'),
        allOf(contains('Keyword'), contains('4.8:1'), contains('AA')),
      );
      expect(
        row('info'),
        allOf(contains('Link'), contains('4.5:1'), contains('AA')),
      );
      expect(
        row('error'),
        allOf(contains('Error'), contains('7.0:1'), contains('AA')),
      );
      expect(
        find.text(
          'Text roles need 4.5:1. A role below that still applies, with a '
          'warning on its card.',
        ),
        findsOneWidget,
      );
    });
  });

  group('«Use» и «Reset» (spec «Карточки тем и превью»)', () {
    testWidgets(
      '«Use acme-night» доступна для загруженной темы, не назначенной '
      'режиму, и вызывает Cubit',
      (tester) async {
        await pumpPage(
          tester,
          _state(
            custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)],
            selectedId: 'acme-night',
            selection: _twoWarningsSelection(),
          ),
        );

        expect(find.text('Use acme-night'), findsOneWidget);
        await tester.tap(key('-use'));
        await tester.pump();

        expect(settings.calls, contains('use'));
      },
    );

    testWidgets('«Use» недоступна для темы, которая уже назначена режиму', (
      tester,
    ) async {
      app = buildApp(
        values: const AppAppearanceSettings(
          mode: AppearanceMode.dark,
          darkTheme: 'acme-night',
        ),
        dark: _parsed('acme-night', _twoWarnings),
      );
      await pumpPage(
        tester,
        _state(
          custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)],
          selectedId: 'acme-night',
          selection: _twoWarningsSelection(),
        ),
      );

      await tester.tap(key('-use'));
      await tester.pump();

      expect(settings.calls, isNot(contains('use')));
    });

    testWidgets('«Use» недоступна для темы, которая не загрузилась', (
      tester,
    ) async {
      await pumpPage(
        tester,
        _state(
          custom: [_invalidCard],
          selectedId: 'broken',
          selection: const AppearanceSelection(
            card: _invalidCard,
            fileText: '{',
            error: ThemeIssue(ThemeIssueCode.invalidJson, line: 1, column: 1),
          ),
        ),
      );

      await tester.tap(key('-use'));
      await tester.pump();

      expect(settings.calls, isNot(contains('use')));
    });

    testWidgets('«Reset» недоступна, если режиму уже назначена тема по '
        'умолчанию', (tester) async {
      await pumpPage(tester, _state(selectedId: 'dark'));

      await tester.tap(key('-reset'));
      await tester.pump();

      expect(settings.calls, isNot(contains('reset')));
    });

    testWidgets('«Reset» доступна, если режиму назначена другая тема', (
      tester,
    ) async {
      app = buildApp(
        values: const AppAppearanceSettings(
          mode: AppearanceMode.dark,
          darkTheme: 'acme-night',
        ),
        dark: _parsed('acme-night', _twoWarnings),
      );
      await pumpPage(
        tester,
        _state(
          custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)],
          selectedId: 'acme-night',
          selection: _twoWarningsSelection(),
        ),
      );

      await tester.tap(key('-reset'));
      await tester.pump();

      expect(settings.calls, contains('reset'));
    });
  });

  group('InfoBar страницы', () {
    testWidgets('«Удалённый файл темы»: settings-appearance-fallback называет '
        'тему и встроенную замену', (tester) async {
      app = buildApp(
        values: const AppAppearanceSettings(
          mode: AppearanceMode.dark,
          darkTheme: 'acme-night',
        ),
      );
      await pumpPage(tester, _state());

      expect(key('-fallback'), findsOneWidget);
      expect(
        find.text(
          '"acme-night" couldn\'t be loaded. Using Fluent Dark until it is '
          'fixed.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('без отката InfoBar fallback нет', (tester) async {
      await pumpPage(tester, _state());

      expect(key('-fallback'), findsNothing);
    });

    testWidgets('«Сбой записи»: ошибка и Retry, Retry повторяет запись', (
      tester,
    ) async {
      final failing = _FailsOnce();
      final failingApp = buildApp(preferences: failing);
      await pumpPage(tester, _state(), appearance: failingApp);
      await tester.runAsync(() => failingApp.setMode(AppearanceMode.dark));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't save the appearance. CodeLab will use the previous "
          'appearance after restart.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('/secret/path'), findsNothing);
      await tester.tap(key('-save-retry'));
      await tester.pumpAndSettle();

      expect(failing.saves, 2);
      expect(failingApp.state.saveFailed, isFalse);
      expect(key('-save-retry'), findsNothing);
    });
  });

  group('русский интерфейс (spec «Все тексты страницы…», D15)', () {
    testWidgets('подписи из app_ru.arb; имена, ключи и отношения как есть', (
      tester,
    ) async {
      app = buildApp(accentSupported: true);
      await pumpPage(
        tester,
        _state(
          custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)],
          selectedId: 'acme-night',
          selection: _twoWarningsSelection(),
        ),
        locale: const Locale('ru'),
        system: Brightness.dark,
      );

      for (final ru in const [
        'Режим',
        'Цвет акцента',
        'Цветовая тема',
        'Свои темы',
        'Высокий контраст',
        'Как в системе',
      ]) {
        expect(find.textContaining(ru), findsWidgets, reason: ru);
      }
      // Имена тем не переводятся.
      expect(find.textContaining('Fluent Light'), findsWidgets);
      expect(find.textContaining('Fluent Dark'), findsWidgets);
      expect(find.textContaining('acme-night'), findsWidgets);
      // Английские подписи блоков не остались.
      expectNoEnglish(const ['Color theme', 'Custom themes', 'Accent color']);
      // Позиции и ключи в списке проблем — как есть.
      expect(find.textContaining('acme-night.json:6:5'), findsOneWidget);
    });

    testWidgets('смена языка на странице не оставляет строк прежнего языка', (
      tester,
    ) async {
      final language = PageLanguage(const Locale('en'));
      addTearDown(language.dispose);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      app = buildApp(accentSupported: true);
      settings = _FakeSettingsCubit(
        _state(
          custom: [_custom('acme-night', _twoWarnings, parseWarnings: 2)],
          selectedId: 'acme-night',
          selection: _twoWarningsSelection(),
        ),
        app,
      );
      addTearDown(settings.close);
      await tester.pumpWidget(
        language.wrap(
          ScaffoldPage(
            padding: EdgeInsets.zero,
            content: MultiBlocProvider(
              providers: [
                BlocProvider<AppAppearanceCubit>.value(value: app),
                BlocProvider<AppearanceSettingsCubit>.value(value: settings),
              ],
              child: const SingleChildScrollView(child: AppearancePage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Color theme'), findsOneWidget);

      await language.select(tester, const Locale('ru'));
      await expectNoStaleLanguage(
        tester,
        from: AppLocalizationsEn(),
        to: AppLocalizationsRu(),
        ignore: const {'acme-night', 'Dark', 'Light'},
      );
      expect(find.text('Color theme'), findsNothing);
      expect(find.text('Цветовая тема'), findsOneWidget);

      await language.select(tester, const Locale('en'));
      await expectNoStaleLanguage(
        tester,
        from: AppLocalizationsRu(),
        to: AppLocalizationsEn(),
        ignore: const {'acme-night'},
      );
      expect(find.text('Color theme'), findsOneWidget);
    });
  });
}
