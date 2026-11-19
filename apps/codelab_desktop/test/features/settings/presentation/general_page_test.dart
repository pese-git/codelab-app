// Тесты страницы «General» (задача 1.9 change
// `add-desktop-localization`; spec app-settings «Язык интерфейса app»:
// «Смена языка применяется сразу на странице настроек» — критерий D-19,
// «Сбой записи», «Возврат к английскому»; design.md D2, D9).
//
// Страница читает и вызывает `AppLanguageCubit`, своего Cubit-а у неё нет.
// Тесты идут через настоящее дерево app (`CodeLabApp`): язык должен
// переключаться без перезапуска и без пересоздания `FluentApp`.
//
// Блоки «Agent defaults» (задача 2.5 change `add-app-general-page`; spec
// app-settings «Страница «General»: состав и порядок», «Умолчания агента на
// странице «General»: доступ и строки» и «…запись»; design.md D2, D5, D7,
// D15, D17) проверяются на Cubit-двойнике: `GeneralPage` читает
// `AgentDefaultsCubit` из `BlocProvider` (в приложении его кладёт хозяин
// страницы, как у «Agents & modes»), а запись, разбор и источники проверяет
// `agent_defaults_cubit_test.dart`. Здесь — что страница показывает из
// состояния и какой метод Cubit вызывает при выборе пользователя.
//
// Реализация блоков — задачи 2.6, 3.6 и 5.10 change `add-app-general-page`.
//
// Контракт ключей (spec): `settings-general-shared-info`,
// `settings-general-agent-defaults`, `settings-general-agent-row-<key>`,
// `settings-general-agent-banner`, `settings-general-agent-read-only`,
// `settings-general-agent-unreadable`. Ключи, которых в spec нет, вводит этот
// тест: `settings-general-agent-loading` (индикатор загрузки).
// Редакторы ищутся по типу виджета внутри строки (`ToggleSwitch`, `ComboBox`,
// `TextBox`), своих ключей у них нет.

import 'dart:io';

import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/core/platform/startup_preferences.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/app/build_version.dart';
import 'package:codelab_desktop/core/platform/external_link_opener.dart';
import 'package:codelab_desktop/core/platform/local_folder_opener.dart';
import 'package:codelab_desktop/features/settings/application/about_diagnostics.dart';
import 'package:codelab_desktop/features/settings/application/about_ports.dart';
import 'package:codelab_desktop/features/settings/application/agent_defaults_cubit.dart';
import 'package:codelab_desktop/features/settings/application/agent_defaults_rows.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/startup_settings_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/general_page.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_shell.dart';
import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/fake_external_link_opener.dart';
import '../../../support/fake_local_folder_opener.dart';
import '../../../support/l10n_app.dart';
import '../../../support/modes_fixture.dart';
import '../../../support/fake_provider_settings.dart' show FakeWorkspace;
import '../../../support/recording_logger.dart';
import '../../../support/l10n_mix.dart';
import '../../../support/settings_search.dart';
import '../../../support/test_app_scope.dart';

/// Порт хранения, у которого запись всегда падает.
final class _FailingPreferences implements AppLanguagePreferences {
  final saves = <AppLanguagePreference>[];

  @override
  Future<AppLanguageLoad> load() async =>
      const AppLanguageLoad(AppLanguagePreference.system);

  @override
  Future<void> save(AppLanguagePreference preference) {
    saves.add(preference);
    return Future.error(StateError('disk is read-only: /secret/path'));
  }
}

/// Первая запись падает, следующие идут в настоящее хранилище.
final class _FailsOncePreferences implements AppLanguagePreferences {
  final _real = const SharedPreferencesAppLanguagePreferences();
  var _failed = false;

  @override
  Future<AppLanguageLoad> load() => _real.load();

  @override
  Future<void> save(AppLanguagePreference preference) {
    if (_failed) return _real.save(preference);
    _failed = true;
    return Future.error(StateError('disk is read-only'));
  }
}

/// Порт настроек запуска: запись [saves], сбой записи задаёт тест.
final class _StartupPort implements StartupPreferences {
  _StartupPort({this.failSaves = 0});

  /// Сколько первых записей падает.
  int failSaves;
  final saves = <bool>[];

  @override
  Future<StartupLoad> load() async => const StartupLoad(true);

  @override
  Future<void> save(bool reopenLastProject) async {
    saves.add(reopenLastProject);
    if (failSaves > 0) {
      failSaves--;
      throw StateError('disk is read-only: /secret/path');
    }
  }
}

/// Cubit-двойник: состояние задаёт тест, вызовы страницы — в [calls].
final class FakeAgentDefaultsCubit extends Cubit<AgentDefaultsState>
    implements AgentDefaultsCubit {
  FakeAgentDefaultsCubit(super.initialState);

  /// Вызовы страницы по порядку: `reload`, `submit:<ключ>=<текст>`.
  final calls = <String>[];

  @override
  Future<void> reload() async => calls.add('reload');

  @override
  Future<void> submit(String key, String raw) async =>
      calls.add('submit:$key=$raw');

  /// Показывает состояние (в самом Cubit `emit` защищён).
  void show(AgentDefaultsState state) => emit(state);
}

const _user = ConfigSourceView(kind: ConfigSourceKind.user, label: 'u');
const _local = ConfigSourceView(
  kind: ConfigSourceKind.projectLocal,
  label: 'l',
);
const _env = ConfigSourceView(kind: ConfigSourceKind.environment, label: 'env');
const _extra = ConfigSourceView(kind: ConfigSourceKind.extraFile, label: 'x');

/// Строки реестра всех общих ключей `scope: shared` без шаблонов `*`;
/// [values] и [sources] задают значение и источник отдельных ключей.
List<SettingFieldView> _fields({
  Map<String, Object?> values = const {},
  Map<String, ConfigSourceView> sources = const {},
}) => [
  for (final d in SettingsRegistry.all)
    if (d.scope == SettingScope.shared && !d.key.contains('*'))
      SettingFieldView(
        key: d.key,
        descriptor: d,
        value: values[d.key],
        source: sources[d.key],
      ),
];

/// Заменяет строку [key] группы на [row] (отказ, которого мост не даёт для
/// ключей `general`: секрет, маска).
List<AgentDefaultsGroup> _replaced(
  List<AgentDefaultsGroup> groups,
  String key,
  AgentDefaultsRow Function(AgentDefaultsRow row) change,
) => [
  for (final g in groups)
    AgentDefaultsGroup(
      section: g.section,
      rows: [for (final r in g.rows) r.field.key == key ? change(r) : r],
    ),
];

AgentDefaultsReady _ready({
  Map<String, Object?> values = const {},
  Map<String, ConfigSourceView> sources = const {},
  AgentDefaultsBanner? banner,
  Set<String> fieldErrors = const {},
  String configHome = '~/.codelab',
  List<AgentDefaultsGroup> Function(List<AgentDefaultsGroup>)? groups,
}) {
  final built = agentDefaultsGroupsOf(
    _fields(values: values, sources: sources),
  );
  return AgentDefaultsReady(
    groups: groups?.call(built) ?? built,
    banner: banner,
    fieldErrors: fieldErrors,
    configHome: configHome,
  );
}

/// Ключи всех 18 строк блока.
final _rowKeys = [
  for (final d in SettingsRegistry.all)
    if (d.scope == SettingScope.shared &&
        settingsPageOwnerOf(d.key) == SettingsPageOwner.general)
      d.key,
];

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  /// Открывает страницу «General» в настоящем дереве app.
  Future<CodeLabTestBinding> openGeneral(
    WidgetTester tester, {
    AppLanguagePreferences? languagePreferences,
    StartupPreferences? startupPreferences,
    Map<String, Object> preferences = const {},
    AboutInfo? aboutInfo,
    ExternalLinkOpener? externalLinkOpener,
    LocalFolderOpener? localFolderOpener,
  }) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      settingsPages: const SettingsPages(
        available: {SettingsPage.connection, SettingsPage.general},
      ),
      languagePreferences: languagePreferences,
      startupPreferences: startupPreferences,
      preferences: preferences,
      aboutInfo: aboutInfo,
      externalLinkOpener: externalLinkOpener,
      localFolderOpener: localFolderOpener,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await binding.scope.resolve<NavigationCubit>().openSettings(
      page: SettingsPage.general,
      source: SettingsOpenSource.sidebar,
    );
    await tester.pumpAndSettle();
    return binding;
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> choose(WidgetTester tester, String optionKey) async {
    await tester.tap(key(optionKey));
    await tester.pumpAndSettle();
  }

  testWidgets('показывает строку Language и три значения с эндонимами', (
    tester,
  ) async {
    await openGeneral(tester);

    expect(key('settings-general-language'), findsOneWidget);
    expect(find.text(en.settingsLanguageTitle), findsWidgets);
    for (final option in ['system', 'en', 'ru']) {
      expect(key('settings-language-$option'), findsOneWidget);
    }
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text(en.settingsLanguageSystem), findsOneWidget);
  });

  testWidgets('выбор Русский без перезапуска переводит страницу, навигацию и '
      'строку Language (критерий D-19)', (tester) async {
    final binding = await openGeneral(tester);
    final cubit = binding.scope.resolve<AppLanguageCubit>();

    await choose(tester, 'settings-language-ru');

    expect(cubit.state.locale, const Locale('ru'));
    // Английские подписи ушли, русские на месте.
    expect(find.text(en.settingsPageGeneralTitle), findsNothing);
    expect(find.text(en.settingsLanguageTitle), findsNothing);
    expect(find.text(ru.settingsPageGeneralTitle), findsWidgets);
    expect(find.text(ru.settingsLanguageTitle), findsWidgets);
    expect(find.text(ru.settingsLanguageSystem), findsOneWidget);
    // Эндонимы не переводятся.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    // Навигация настроек: пункты и заголовки групп пересобраны.
    expect(find.text('Connection'), findsNothing);
    expect(find.text('Agent'), findsNothing);
    expect(find.text('App'), findsNothing);
    await expectNoStaleLanguage(tester, from: en, to: ru);
  });

  testWidgets('English возвращает английский', (tester) async {
    await openGeneral(tester);

    await choose(tester, 'settings-language-ru');
    await choose(tester, 'settings-language-en');

    expect(find.text(en.settingsPageGeneralTitle), findsWidgets);
    expect(find.text(en.settingsLanguageTitle), findsWidgets);
    expect(find.text(ru.settingsLanguageTitle), findsNothing);
    await expectNoStaleLanguage(tester, from: ru, to: en);
  });

  testWidgets('выбор сохраняется в хранилище; System удаляет ключ', (
    tester,
  ) async {
    await openGeneral(tester);

    await choose(tester, 'settings-language-ru');
    expect(
      (await const SharedPreferencesAppLanguagePreferences().load()).preference,
      AppLanguagePreference.ru,
    );

    await choose(tester, 'settings-language-system');
    expect(
      (await const SharedPreferencesAppLanguagePreferences().load()).preference,
      AppLanguagePreference.system,
    );
  });

  testWidgets('сбой записи: язык применён, ошибка на новом языке без текста '
      'исключения', (tester) async {
    final failing = _FailingPreferences();
    final binding = await openGeneral(tester, languagePreferences: failing);

    await choose(tester, 'settings-language-ru');

    // Выбранная радиокнопка — ru, хотя запись не удалась.
    expect(
      tester
          .widget<RadioGroup<AppLanguagePreference>>(
            find.byType(RadioGroup<AppLanguagePreference>),
          )
          .groupValue,
      AppLanguagePreference.ru,
    );

    expect(
      binding.scope.resolve<AppLanguageCubit>().state.locale,
      const Locale('ru'),
    );
    expect(find.text(ru.settingsLanguageSaveFailed), findsOneWidget);
    // Кнопка Retry — на русском.
    expect(find.text(ru.settingsLanguageSaveRetry), findsOneWidget);
    expect(find.text(en.settingsLanguageSaveRetry), findsNothing);
    expect(find.text(en.settingsLanguageSaveFailed), findsNothing);
    expect(find.textContaining('/secret/path'), findsNothing);
    expect(find.textContaining('read-only'), findsNothing);
    await expectNoStaleLanguage(tester, from: en, to: ru);
  });

  testWidgets('кнопка Повторить в предупреждении повторяет запись выбранного '
      'языка', (tester) async {
    final failing = _FailingPreferences();
    await openGeneral(tester, languagePreferences: failing);
    await choose(tester, 'settings-language-ru');
    expect(failing.saves, [AppLanguagePreference.ru]);

    expect(find.text(ru.settingsLanguageSaveRetry), findsOneWidget);
    await tester.tap(key('settings-language-save-retry'));
    await tester.pumpAndSettle();

    expect(failing.saves, [AppLanguagePreference.ru, AppLanguagePreference.ru]);
  });

  testWidgets('Retry после сбоя: запись проходит, ключ ru, ошибка скрыта, '
      'интерфейс на русском', (tester) async {
    final binding = await openGeneral(
      tester,
      languagePreferences: _FailsOncePreferences(),
    );
    await choose(tester, 'settings-language-ru');
    expect(key('settings-language-save-failed'), findsOneWidget);

    await tester.tap(key('settings-language-save-retry'));
    await tester.pumpAndSettle();

    expect(key('settings-language-save-failed'), findsNothing);
    expect(
      (await const SharedPreferencesAppLanguagePreferences().load()).preference,
      AppLanguagePreference.ru,
    );
    expect(
      binding.scope.resolve<AppLanguageCubit>().state.locale,
      const Locale('ru'),
    );
    expect(find.text(ru.settingsLanguageTitle), findsWidgets);
  });

  // --- Блоки «Agent defaults» (задача 2.5 change `add-app-general-page`) -----

  group('Agent defaults на Cubit-двойнике', () {
    late AppLanguageCubit language;
    late FakeAgentDefaultsCubit cubit;
    late StartupSettingsCubit startup;

    /// Страница «General» в дереве, как его собирает `CodeLabApp`: язык
    /// выбирает `AppLanguageCubit`, а `FluentApp` не пересоздаётся.
    Future<void> pumpPage(
      WidgetTester tester,
      AgentDefaultsState state, {
      Locale locale = const Locale('en'),
      Size size = const Size(1200, 2600),
      AboutPorts? about,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      language = AppLanguageCubit(
        preferences: const SharedPreferencesAppLanguagePreferences(),
        preference: AppLanguagePreference.system,
        locale: locale,
      );
      addTearDown(language.close);
      cubit = FakeAgentDefaultsCubit(state);
      addTearDown(cubit.close);
      startup = StartupSettingsCubit(preferences: _StartupPort());
      addTearDown(startup.close);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AppLanguageCubit>.value(value: language),
            BlocProvider<AgentDefaultsCubit>.value(value: cubit),
            BlocProvider<StartupSettingsCubit>.value(value: startup),
          ],
          child: BlocBuilder<AppLanguageCubit, AppLanguageState>(
            buildWhen: (a, b) => a.locale != b.locale,
            builder: (context, lang) => FluentApp(
              locale: lang.locale,
              localizationsDelegates: const [
                ...AppLocalizations.localizationsDelegates,
                CodeLabLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: ScaffoldPage(
                content: SingleChildScrollView(
                  child: GeneralPage(about: about),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder row(String k) => key('settings-general-agent-row-$k');

    /// Текст [text] внутри строки ключа [k].
    Finder inRow(String k, String text) =>
        find.descendant(of: row(k), matching: find.text(text));

    Finder editor<T extends Widget>(String k) =>
        find.descendant(of: row(k), matching: find.byType(T));

    double top(WidgetTester tester, Finder finder) =>
        tester.getTopLeft(finder).dy;

    group('Состав и порядок (D17)', () {
      testWidgets('InfoBar, затем Agent defaults, затем Interface; без '
          '"Startup and files" и "About" до итераций 3–5', (tester) async {
        await pumpPage(tester, _ready());

        expect(key('settings-general-shared-info'), findsOneWidget);
        expect(key('settings-general-agent-defaults'), findsOneWidget);
        expect(key('settings-general-language'), findsOneWidget);
        expect(
          top(tester, key('settings-general-shared-info')),
          lessThan(top(tester, key('settings-general-agent-defaults'))),
        );
        expect(
          top(tester, key('settings-general-agent-defaults')),
          lessThan(top(tester, key('settings-general-language'))),
        );
        expect(find.text('Agent defaults'), findsOneWidget);
        expect(find.text(en.settingsGeneralSectionInterface), findsOneWidget);
        // Строки без поведения не показываются (SETUP-17, D8, D17), блок без
        // видимых строк скрыт вместе с заголовком.
        // «Startup and files» есть со строкой «Reopen…» (итерация 3), строки
        // «Show ignored files» (итерация 4) и «About» (итерация 5) ещё нет.
        expect(key('settings-general-show-ignored'), findsNothing);
        for (final hidden in [
          'When I press Enter during a turn',
          'Sidebar opens on',
          'Send crash reports',
          'Privacy policy',
          'Privacy',
        ]) {
          expect(find.text(hidden), findsNothing, reason: hidden);
        }
      });

      testWidgets('строки идут по группам: Budget, Agent, Subagents, '
          'Logging', (tester) async {
        await pumpPage(tester, _ready());

        final order = [
          'budget.max_steps',
          'budget.max_duration',
          'compaction.enabled',
          'subagents.enabled',
          'subagents.cancel_grace',
          'logging.level',
        ];
        for (final k in order) {
          expect(row(k), findsOneWidget, reason: k);
        }
        for (var i = 1; i < order.length; i++) {
          expect(
            top(tester, row(order[i - 1])),
            lessThan(top(tester, row(order[i]))),
            reason: '${order[i - 1]} выше ${order[i]}',
          );
        }
      });

      testWidgets('есть строка для каждого из 18 ключей, чужих ключей нет', (
        tester,
      ) async {
        await pumpPage(tester, _ready());

        expect(_rowKeys, hasLength(18));
        for (final k in _rowKeys) {
          expect(row(k), findsOneWidget, reason: k);
        }
        for (final other in [
          'permissions.mode',
          'agent.effort',
          'agent.default_model',
          'trusted_projects',
          'mcp.servers',
          'permissions.deny',
        ]) {
          expect(row(other), findsNothing, reason: other);
        }
      });

      testWidgets('под заголовком блока подпись о записи для всех '
          'проектов', (tester) async {
        await pumpPage(tester, _ready());

        expect(
          find.text('Changes are saved for all projects.'),
          findsOneWidget,
        );
      });
    });

    group('Поиск «Find a setting» (spec «Страница «General»: состав»)', () {
      const pages = [SettingsPage.connection, SettingsPage.general];

      test('находит General по ключевым словам блоков', () {
        for (final word in const [
          'language',
          'budget',
          'steps',
          'compaction',
          'subagent',
          'log level',
          'startup',
          'reopen',
          'ignored',
          'about',
          'version',
          'license',
          'diagnostics',
        ]) {
          expect(
            searchSettings(pages, word),
            contains(SettingsPage.general),
            reason: word,
          );
        }
      });

      test('ключевые слова General не отнимают у Connection его слова', () {
        for (final word in const ['token', 'restart', 'profile', 'stdio']) {
          expect(searchSettings(pages, word), [
            SettingsPage.connection,
          ], reason: word);
        }
      });

      testWidgets('в ru General находится и по переводам ключевых слов', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          localizedFluentApp(
            locale: const Locale('ru'),
            SettingsShell(
              pages: const SettingsPages(
                available: {SettingsPage.connection, SettingsPage.general},
              ),
              selected: SettingsPage.connection,
              onSelected: (_) {},
              onBack: () {},
              builders: {
                for (final page in SettingsPage.values)
                  page: (_) => Text('body of ${page.slug}'),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final word in const ['бюджет', 'язык', 'лицензия', 'субагент']) {
          await tester.enterText(
            find.byKey(CodeLabSettingsNavigation.searchKey),
            word,
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(ValueKey(SettingsPage.general.navKey)),
            findsOneWidget,
            reason: word,
          );
        }
      });
    });

    group('InfoBar settings-general-shared-info (D17)', () {
      testWidgets('называет файл в домашней папке по homePathLabel', (
        tester,
      ) async {
        await pumpPage(tester, _ready());

        expect(key('settings-general-shared-info'), findsOneWidget);

        final info = tester.widget<InfoBar>(
          key('settings-general-shared-info'),
        );
        expect(info.severity, InfoBarSeverity.info);
        final text = find.descendant(
          of: key('settings-general-shared-info'),
          matching: find.textContaining('~/.codelab/config.yaml'),
        );
        expect(text, findsWidgets);
        expect(
          find.textContaining('Shared with the codelab CLI.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('codelab /settings shows them too.'),
          findsOneWidget,
        );
        // Коды целей в текст интерфейса не выносятся (D17).
        expect(find.textContaining('E-15'), findsNothing);
        expect(find.textContaining('codelab_cli'), findsNothing);
      });

      testWidgets('путь берётся из состояния, а не из константы', (
        tester,
      ) async {
        await pumpPage(tester, _ready(configHome: '~/work/codelab-home'));

        expect(
          find.textContaining('~/work/codelab-home/config.yaml'),
          findsOneWidget,
        );
        expect(find.textContaining('~/.codelab/config.yaml'), findsNothing);
      });
    });

    group('Строка: значение, источник, подпись', () {
      testWidgets('показывает подпись, ключ, значение, источник, тег и '
          'описание', (tester) async {
        await pumpPage(
          tester,
          _ready(
            values: {'budget.max_steps': 80},
            sources: {'budget.max_steps': _user},
          ),
        );

        const k = 'budget.max_steps';
        expect(inRow(k, 'Max steps'), findsOneWidget);
        expect(inRow(k, k), findsOneWidget);
        expect(inRow(k, '80'), findsOneWidget);
        expect(inRow(k, 'user'), findsOneWidget);
        expect(inRow(k, 'shared'), findsOneWidget);
        expect(inRow(k, 'Model requests per turn.'), findsOneWidget);
        // Источник по умолчанию называется как есть.
        expect(inRow('compaction.enabled', 'default'), findsOneWidget);
      });

      testWidgets('незаданный ключ без умолчания — "Not set"', (tester) async {
        await pumpPage(tester, _ready());

        expect(inRow('budget.max_tokens', 'Not set'), findsOneWidget);
        expect(inRow('budget.max_tokens', 'default'), findsOneWidget);
        expect(find.textContaining('(not set)'), findsNothing);
      });

      testWidgets('(applies after restart) только у ключей с перезапуском', (
        tester,
      ) async {
        await pumpPage(tester, _ready());

        expect(
          inRow('logging.level', '(applies after restart)'),
          findsOneWidget,
        );
        expect(
          inRow('budget.max_steps', '(applies after restart)'),
          findsNothing,
        );
        expect(find.text('(applies after restart)'), findsOneWidget);
      });

      testWidgets('источник project или local оставляет редактор и называет '
          'слой', (tester) async {
        await pumpPage(
          tester,
          _ready(
            values: {'compaction.enabled': false},
            sources: {'compaction.enabled': _local},
          ),
        );

        const k = 'compaction.enabled';
        expect(inRow(k, 'This project overrides it (local).'), findsOneWidget);
        expect(editor<ToggleSwitch>(k), findsOneWidget);
        expect(inRow(k, 'local'), findsOneWidget);
      });
    });

    group('Редакторы по типу (D5)', () {
      testWidgets('bool — ToggleSwitch, enumeration — ComboBox, остальные — '
          'TextBox', (tester) async {
        await pumpPage(tester, _ready());

        expect(editor<ToggleSwitch>('compaction.enabled'), findsOneWidget);
        expect(editor<ToggleSwitch>('subagents.enabled'), findsOneWidget);
        expect(editor<ComboBox<String>>('logging.level'), findsOneWidget);
        for (final k in [
          'budget.max_steps', // int
          'budget.max_cost', // float
          'budget.max_duration', // duration
          'subagents.max_depth',
          'subagents.progress_interval',
        ]) {
          expect(editor<TextBox>(k), findsOneWidget, reason: k);
          expect(editor<ToggleSwitch>(k), findsNothing, reason: k);
        }
        expect(editor<TextBox>('compaction.enabled'), findsNothing);
        expect(editor<TextBox>('logging.level'), findsNothing);
      });

      testWidgets('переключатель передаёт Cubit-у true/false', (tester) async {
        await pumpPage(tester, _ready());

        expect(editor<ToggleSwitch>('compaction.enabled'), findsOneWidget);

        await tester.tap(editor<ToggleSwitch>('compaction.enabled'));
        await tester.pumpAndSettle();

        // Умолчание `true`: нажатие выключает.
        expect(cubit.calls, contains('submit:compaction.enabled=false'));
      });

      testWidgets('выпадающий список передаёт выбранное значение', (
        tester,
      ) async {
        await pumpPage(tester, _ready());

        expect(editor<ComboBox<String>>('logging.level'), findsOneWidget);

        await tester.tap(editor<ComboBox<String>>('logging.level'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('debug').last);
        await tester.pumpAndSettle();

        expect(cubit.calls, contains('submit:logging.level=debug'));
      });

      testWidgets('поле ввода применяется по Enter', (tester) async {
        await pumpPage(tester, _ready());

        expect(editor<TextBox>('budget.max_steps'), findsOneWidget);

        await tester.enterText(editor<TextBox>('budget.max_steps'), '80');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(cubit.calls, contains('submit:budget.max_steps=80'));
      });

      testWidgets('поле ввода применяется и при потере фокуса', (tester) async {
        await pumpPage(tester, _ready());

        expect(editor<TextBox>('budget.max_tokens'), findsOneWidget);

        await tester.enterText(editor<TextBox>('budget.max_tokens'), '5000');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        expect(cubit.calls, contains('submit:budget.max_tokens=5000'));
      });

      testWidgets('очищенное поле передаёт пустую строку (сброс)', (
        tester,
      ) async {
        await pumpPage(
          tester,
          _ready(
            values: {'budget.max_tokens': 100000},
            sources: {'budget.max_tokens': _user},
          ),
        );

        expect(editor<TextBox>('budget.max_tokens'), findsOneWidget);

        await tester.enterText(editor<TextBox>('budget.max_tokens'), '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(cubit.calls, contains('submit:budget.max_tokens='));
      });

      testWidgets('страница не разбирает ввод сама: текст уходит как есть', (
        tester,
      ) async {
        await pumpPage(tester, _ready());

        expect(editor<TextBox>('budget.max_steps'), findsOneWidget);

        await tester.enterText(editor<TextBox>('budget.max_steps'), '0');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(cubit.calls, contains('submit:budget.max_steps=0'));
      });
    });

    group('Подсказка формата по ошибке разбора (D5)', () {
      testWidgets('по типу и границам дескриптора, без введённого значения', (
        tester,
      ) async {
        await pumpPage(
          tester,
          _ready(
            fieldErrors: {
              'budget.max_steps',
              'subagents.max_depth',
              'budget.max_cost',
              'budget.max_duration',
            },
          ),
        );

        expect(
          inRow('budget.max_steps', 'Enter a whole number of 1 or greater.'),
          findsOneWidget,
        );
        expect(
          inRow('subagents.max_depth', 'Enter a whole number from 1 to 3.'),
          findsOneWidget,
        );
        expect(inRow('budget.max_cost', 'Enter a number.'), findsOneWidget);
        expect(
          inRow(
            'budget.max_duration',
            'Enter a duration like 500ms, 30s, 2m or 1h.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('без ошибки подсказок нет', (tester) async {
        await pumpPage(tester, _ready());

        expect(find.textContaining('Enter a'), findsNothing);
      });
    });

    group('Отказ в правке (D6)', () {
      testWidgets('секрет: значение и подпись без редактора', (tester) async {
        await pumpPage(
          tester,
          _ready(
            groups: (g) => _replaced(
              g,
              'budget.max_steps',
              (r) => AgentDefaultsRow(
                field: r.field,
                refusal: const SecretSetting('budget.max_steps'),
              ),
            ),
          ),
        );

        const k = 'budget.max_steps';
        expect(inRow(k, 'Change it with codelab secret set.'), findsOneWidget);
        expect(editor<TextBox>(k), findsNothing);
        expect(editor<ToggleSwitch>(k), findsNothing);
        expect(editor<ComboBox<String>>(k), findsNothing);
        expect(inRow(k, '50'), findsOneWidget);
      });

      testWidgets('маска: правка в файле конфига', (tester) async {
        await pumpPage(
          tester,
          _ready(
            groups: (g) => _replaced(
              g,
              'logging.level',
              (r) => AgentDefaultsRow(
                field: r.field,
                refusal: const MaskedSetting('logging.level'),
              ),
            ),
          ),
        );

        const k = 'logging.level';
        expect(
          inRow(
            k,
            'This value contains a secret; change it in the config file.',
          ),
          findsOneWidget,
        );
        expect(editor<ComboBox<String>>(k), findsNothing);
      });

      testWidgets('окружение: Set by env, значение видно, редактора нет', (
        tester,
      ) async {
        await pumpPage(
          tester,
          _ready(
            values: {'budget.max_steps': 11},
            sources: {'budget.max_steps': _env},
          ),
        );

        const k = 'budget.max_steps';
        expect(
          inRow(k, 'Set by env; it cannot be changed here.'),
          findsOneWidget,
        );
        expect(inRow(k, '11'), findsOneWidget);
        expect(inRow(k, 'env'), findsOneWidget);
        expect(editor<TextBox>(k), findsNothing);
      });

      testWidgets('файл --config: Set by config', (tester) async {
        await pumpPage(
          tester,
          _ready(
            values: {'compaction.enabled': false},
            sources: {'compaction.enabled': _extra},
          ),
        );

        const k = 'compaction.enabled';
        expect(
          inRow(k, 'Set by config; it cannot be changed here.'),
          findsOneWidget,
        );
        expect(editor<ToggleSwitch>(k), findsNothing);
      });
    });

    group('Только чтение, нечитаемый конфиг, загрузка', () {
      testWidgets('WebSocket: предупреждение без пути, нет строк и InfoBar, '
          'Language остаётся', (tester) async {
        await pumpPage(
          tester,
          const AgentDefaultsReadOnly(
            kind: AgentDefaultsReadOnlyKind.remote,
            subject: 'wss://devbox:7420',
          ),
        );

        expect(key('settings-general-agent-read-only'), findsOneWidget);

        final bar = tester.widget<InfoBar>(
          key('settings-general-agent-read-only'),
        );
        expect(bar.severity, InfoBarSeverity.warning);
        expect(
          find.descendant(
            of: key('settings-general-agent-read-only'),
            matching: find.textContaining(
              'Read-only: this agent runs on wss://devbox:7420. '
              'Change its settings on that host: codelab config set.',
            ),
          ),
          findsOneWidget,
        );
        expect(key('settings-general-shared-info'), findsNothing);
        expect(row('budget.max_steps'), findsNothing);
        expect(find.byType(TextBox), findsNothing);
        expect(key('settings-general-language'), findsOneWidget);
      });

      testWidgets('сторонний агент: Agent settings are managed by <name>', (
        tester,
      ) async {
        await pumpPage(
          tester,
          const AgentDefaultsReadOnly(
            kind: AgentDefaultsReadOnlyKind.notManaged,
            subject: 'python',
          ),
        );

        expect(
          find.descendant(
            of: key('settings-general-agent-read-only'),
            matching: find.textContaining(
              'Agent settings are managed by python.',
            ),
          ),
          findsOneWidget,
        );
        expect(key('settings-general-shared-info'), findsNothing);
        expect(row('budget.max_steps'), findsNothing);
      });

      testWidgets('битый конфиг: проблемы загрузчика, редакторов нет', (
        tester,
      ) async {
        await pumpPage(
          tester,
          const AgentDefaultsUnreadable(
            reason: AgentDefaultsUnreadableReason.loader,
            problems: ['config.yaml:12:3: budget: Expected node content.'],
          ),
        );

        expect(key('settings-general-agent-unreadable'), findsOneWidget);
        expect(
          find.descendant(
            of: key('settings-general-agent-unreadable'),
            matching: find.textContaining('Expected node content.'),
          ),
          findsOneWidget,
        );
        expect(row('budget.max_steps'), findsNothing);
        expect(find.byType(TextBox), findsNothing);
        // Переключатель строки «Reopen…» вне блока Agent defaults.
        expect(
          find.descendant(
            of: key('settings-general-agent-defaults'),
            matching: find.byType(ToggleSwitch),
          ),
          findsNothing,
        );
        expect(key('settings-general-language'), findsOneWidget);
      });

      testWidgets('загрузка: индикатор в блоке, Language доступен', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 2600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        language = AppLanguageCubit(
          preferences: const SharedPreferencesAppLanguagePreferences(),
          preference: AppLanguagePreference.system,
          locale: const Locale('en'),
        );
        addTearDown(language.close);
        cubit = FakeAgentDefaultsCubit(const AgentDefaultsLoading());
        addTearDown(cubit.close);
        startup = StartupSettingsCubit(preferences: _StartupPort());
        addTearDown(startup.close);
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AppLanguageCubit>.value(value: language),
              BlocProvider<AgentDefaultsCubit>.value(value: cubit),
              BlocProvider<StartupSettingsCubit>.value(value: startup),
              BlocProvider<StartupSettingsCubit>.value(value: startup),
            ],
            child: localizedFluentApp(
              const ScaffoldPage(
                content: SingleChildScrollView(child: GeneralPage()),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(key('settings-general-agent-loading'), findsOneWidget);
        expect(row('budget.max_steps'), findsNothing);
        expect(key('settings-general-language'), findsOneWidget);
      });
    });

    group('About: сбои без падения страницы', () {
      const info = AboutInfo(
        version: '0.1.0',
        os: 'macOS',
        arch: 'arm64',
        embeddedAgentVersion: '0.1.0',
        licenseName: 'MIT',
        licenseCopyright: 'Copyright (c) 2026 x',
        configHome: '~/.codelab',
        logDirectory: '/tmp/logs-marker',
        thirdPartyNotices: '',
      );

      AboutPorts ports(
        RecordingLogger logger, {
        Future<AboutInfo> Function()? loadInfo,
        Future<AboutWindow> Function()? window,
      }) => AboutPorts(
        info: loadInfo ?? () async => info,
        window:
            window ??
            () async => (
              connection: DiagnosticsConnection.embedded,
              state: DiagnosticsConnectionState.connected,
              access: DiagnosticsAccess.editable,
              customConfigHome: false,
            ),
        externalLinks: FakeExternalLinkOpener(),
        folders: FakeLocalFolderOpener(),
        logger: logger,
      );

      Iterable<Map<String, Object?>> events(RecordingLogger l, String name) =>
          l.entries.where((e) => e['event'] == name);

      testWidgets('сбой «Copy diagnostics» (снимок окна бросает): InfoBar '
          'сбоя без текста исключения, событие failed', (tester) async {
        final logger = RecordingLogger();
        await pumpPage(
          tester,
          const AgentDefaultsUnreadable(
            reason: AgentDefaultsUnreadableReason.cannotRead,
          ),
          about: ports(
            logger,
            window: () async => throw StateError('boom /secret/path'),
          ),
        );
        await tester.tap(find.text('CodeLab 0.1.0'));
        await tester.pumpAndSettle();

        await tester.tap(key('settings-general-about-copy-diagnostics'));
        await tester.pumpAndSettle();

        expect(key('settings-general-about-copy-failed'), findsOneWidget);
        expect(find.text("Couldn't copy the diagnostics."), findsOneWidget);
        expect(find.text('Diagnostics copied.'), findsNothing);
        expect(find.textContaining('/secret/path'), findsNothing);
        final event = events(logger, 'settings.about_action').single;
        expect(event['action'], 'copy_diagnostics');
        expect(event['outcome'], 'failed');
        expect('${logger.entries}', isNot(contains('/secret/path')));
      });

      testWidgets('сбой буфера обмена: тот же InfoBar и событие failed', (
        tester,
      ) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              throw PlatformException(code: 'clipboard-gone');
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final logger = RecordingLogger();
        await pumpPage(
          tester,
          const AgentDefaultsUnreadable(
            reason: AgentDefaultsUnreadableReason.cannotRead,
          ),
          about: ports(logger),
        );
        await tester.tap(find.text('CodeLab 0.1.0'));
        await tester.pumpAndSettle();

        await tester.tap(key('settings-general-about-copy-diagnostics'));
        await tester.pumpAndSettle();

        expect(key('settings-general-about-copy-failed'), findsOneWidget);
        expect(
          events(logger, 'settings.about_action').single['outcome'],
          'failed',
        );
      });

      testWidgets('сбой чтения ресурсов: раздел не прячется молча — InfoBar и '
          'событие с именем типа без пути', (tester) async {
        final logger = RecordingLogger();
        await pumpPage(
          tester,
          const AgentDefaultsUnreadable(
            reason: AgentDefaultsUnreadableReason.cannotRead,
          ),
          about: ports(
            logger,
            loadInfo: () async => throw StateError('no asset /secret/assets'),
          ),
        );

        expect(key('settings-general-about-load-failed'), findsOneWidget);
        expect(find.text("Couldn't load the About section."), findsOneWidget);
        expect(find.textContaining('/secret/assets'), findsNothing);
        final failed = events(logger, 'settings.about_load_failed').single;
        expect(failed['error_type'], 'StateError');
        expect(failed['level'], 'warning');
        expect('${logger.entries}', isNot(contains('/secret/assets')));
      });
    });

    // Подзаголовки групп (задача 7.1 change `add-app-general-page`, D2):
    // строки `budget.max_steps` и `subagents.max_steps` одинаково называются
    // «Max steps», различает их только группа.
    group('Подзаголовки групп (D2)', () {
      const groupKey = 'settings-general-agent-group-';

      Future<void> checkOrder(WidgetTester tester) async {
        final order = [
          key('${groupKey}budget'),
          row('budget.max_steps'),
          row('budget.max_duration'),
          key('${groupKey}agent'),
          row('compaction.enabled'),
          key('${groupKey}subagents'),
          row('subagents.max_steps'),
          row('subagents.cancel_grace'),
          key('${groupKey}logging'),
          row('logging.level'),
        ];
        for (final finder in order) {
          expect(finder, findsOneWidget, reason: '$finder');
        }
        for (var i = 1; i < order.length; i++) {
          expect(
            tester.getTopLeft(order[i - 1]).dy,
            lessThan(tester.getTopLeft(order[i]).dy),
            reason: 'позиция ${i - 1} выше позиции $i',
          );
        }
      }

      Finder titleOf(String section) => find.descendant(
        of: key('$groupKey$section'),
        matching: find.byType(Text),
      );

      testWidgets('en: порядок и тексты равны разделам реестра', (
        tester,
      ) async {
        await pumpPage(tester, _ready());

        await checkOrder(tester);
        for (final entry in {
          'budget': 'Budget',
          'agent': 'Agent',
          'subagents': 'Subagents',
          'logging': 'Logging',
        }.entries) {
          expect(
            find.descendant(
              of: key('$groupKey${entry.key}'),
              matching: find.text(entry.value),
            ),
            findsOneWidget,
            reason: entry.key,
          );
        }
      });

      testWidgets('ru: «Бюджет», «Агент», «Субагенты», «Журнал агента»', (
        tester,
      ) async {
        await pumpPage(tester, _ready(), locale: const Locale('ru'));

        await checkOrder(tester);
        for (final entry in {
          'budget': 'Бюджет',
          'agent': 'Агент',
          'subagents': 'Субагенты',
          'logging': 'Журнал агента',
        }.entries) {
          expect(
            find.descendant(
              of: key('$groupKey${entry.key}'),
              matching: find.text(entry.value),
            ),
            findsOneWidget,
            reason: entry.key,
          );
        }
        expect(titleOf('budget'), findsOneWidget);
      });

      testWidgets('пустая группа подзаголовка не даёт', (tester) async {
        await pumpPage(
          tester,
          _ready(
            groups: (all) => [
              for (final g in all)
                if (g.section == 'Logging') g,
            ],
          ),
        );

        expect(key('${groupKey}logging'), findsOneWidget);
        for (final section in ['budget', 'agent', 'subagents']) {
          expect(key('$groupKey$section'), findsNothing, reason: section);
        }
      });

      testWidgets('смена языка со подзаголовками не оставляет английского', (
        tester,
      ) async {
        await pumpPage(tester, _ready());
        expect(key('${groupKey}budget'), findsOneWidget);

        await choose(tester, 'settings-language-ru');

        expect(key('${groupKey}budget'), findsOneWidget);
        await expectNoStaleLanguage(tester, from: en, to: ru);
      });
    });

    // Баннер снимается новой правкой (задача 7.3, D7): сценарий «Неверный ввод
    // после успешной записи» на настоящем Cubit-е с файлом во временной папке.
    group('Баннер и неверный ввод (D7)', () {
      testWidgets('после «Saved.» неверный ввод снимает баннер, подсказка '
          'видна', (tester) async {
        late ModesFixture fx;
        late AgentDefaultsCubit real;
        await tester.runAsync(() async {
          fx = await ModesFixture.open();
          real = AgentDefaultsCubit(
            workspace: FakeWorkspace(),
            defaultProfile: () async => embeddedConnectionProfile,
            open: (access, env) async => ModesSession(fx.store),
            environment: {'HOME': fx.home},
            codelabHome: fx.home,
            projectDirectory: () => fx.project,
          );
          await real.reload();
        });
        addTearDown(real.close);
        addTearDown(() => fx.dispose());
        tester.view.physicalSize = const Size(1200, 2600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(
          localizedFluentApp(
            MultiBlocProvider(
              providers: [
                BlocProvider<AppLanguageCubit>.value(
                  value: AppLanguageCubit(
                    preferences:
                        const SharedPreferencesAppLanguagePreferences(),
                    preference: AppLanguagePreference.system,
                    locale: const Locale('en'),
                  ),
                ),
                BlocProvider<AgentDefaultsCubit>.value(value: real),
                BlocProvider<StartupSettingsCubit>.value(
                  value: StartupSettingsCubit(preferences: _StartupPort()),
                ),
              ],
              child: const ScaffoldPage(
                content: SingleChildScrollView(child: GeneralPage()),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.runAsync(() => real.submit('budget.max_steps', '80'));
        await tester.pump();
        expect(key('settings-general-agent-banner'), findsOneWidget);
        expect(find.text('Saved.'), findsOneWidget);

        await tester.runAsync(() => real.submit('budget.max_steps', '0'));
        await tester.pump();

        expect(key('settings-general-agent-banner'), findsNothing);
        expect(
          find.descendant(
            of: row('budget.max_steps'),
            matching: find.text('Enter a whole number of 1 or greater.'),
          ),
          findsOneWidget,
        );
      });
    });

    // Узкое окно не обрезает описания и ключи (задача 7.5, D17): окно 760 px
    // на русском.
    group('Узкое окно не обрезает описания и ключи (D17)', () {
      const heartbeat = 'subagents.heartbeat_interval';

      Text textIn(WidgetTester tester, Finder scope, String text) => tester
          .widget<Text>(find.descendant(of: scope, matching: find.text(text)));

      testWidgets('описание «Reopen» показано целиком: maxLines не задан, '
          'многоточия нет', (tester) async {
        await pumpPage(
          tester,
          _ready(),
          locale: const Locale('ru'),
          size: const Size(760, 3600),
        );

        final description = textIn(
          tester,
          key('settings-general-reopen-last-project'),
          ru.settingsGeneralReopenDescription,
        );

        expect(description.maxLines, isNull);
        expect(description.overflow, isNot(TextOverflow.ellipsis));
        expect(tester.takeException(), isNull);
      });

      testWidgets('описания строк ключей без maxLines', (tester) async {
        await pumpPage(
          tester,
          _ready(),
          locale: const Locale('ru'),
          size: const Size(760, 3600),
        );

        for (final entry in {
          'budget.max_steps': 'Запросов к модели за ход.',
          'subagents.heartbeat_interval':
              'Пауза, после которой молчащий вызов субагента сообщает, что он '
              'жив.',
        }.entries) {
          final description = textIn(tester, row(entry.key), entry.value);
          expect(description.maxLines, isNull, reason: entry.key);
          expect(
            description.overflow,
            isNot(TextOverflow.ellipsis),
            reason: entry.key,
          );
        }
      });

      testWidgets('ключ рвётся только после «.» и «_»: сегменты — по одной '
          'строке', (tester) async {
        await pumpPage(
          tester,
          _ready(),
          locale: const Locale('ru'),
          size: const Size(760, 3600),
        );

        final last = find.descendant(
          of: row(heartbeat),
          matching: find.text('interval'),
        );
        expect(last, findsOneWidget, reason: 'сегмент interval');
        final line = tester.getSize(last);
        for (final segment in ['subagents.', 'heartbeat_', 'interval']) {
          final finder = find.descendant(
            of: row(heartbeat),
            matching: find.text(segment),
          );
          expect(finder, findsOneWidget, reason: segment);
          expect(tester.getSize(finder).height, line.height, reason: segment);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('для скринридера весь ключ — одна метка', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpPage(
          tester,
          _ready(),
          locale: const Locale('ru'),
          size: const Size(760, 3600),
        );

        expect(find.bySemanticsLabel(heartbeat), findsOneWidget);
        semantics.dispose();
      });
    });

    group('Причина Unreadable — из ARB (D7)', () {
      const cases = {
        AgentDefaultsUnreadableReason.cannotRead: (
          'Cannot read the agent settings.',
          'Не удаётся прочитать настройки агента.',
        ),
        AgentDefaultsUnreadableReason.homeUnavailable: (
          'The CodeLab home folder is not available.',
          'Папка CodeLab недоступна.',
        ),
        AgentDefaultsUnreadableReason.userLayerUnreadable: (
          'The user config.yaml cannot be read.',
          'Пользовательский config.yaml не читается.',
        ),
      };

      cases.forEach((reason, texts) {
        testWidgets('${reason.name}: текст на языке интерфейса, без '
            'английского после смены языка', (tester) async {
          await pumpPage(tester, AgentDefaultsUnreadable(reason: reason));
          expect(
            find.descendant(
              of: key('settings-general-agent-unreadable'),
              matching: find.text(texts.$1),
            ),
            findsOneWidget,
          );

          await choose(tester, 'settings-language-ru');

          expect(
            find.descendant(
              of: key('settings-general-agent-unreadable'),
              matching: find.text(texts.$2),
            ),
            findsOneWidget,
          );
          expect(find.text(texts.$1), findsNothing);
          await expectNoStaleLanguage(tester, from: en, to: ru);
        });
      });

      testWidgets('проблемы загрузчика показываются как есть и на русском', (
        tester,
      ) async {
        await pumpPage(
          tester,
          const AgentDefaultsUnreadable(
            reason: AgentDefaultsUnreadableReason.loader,
            problems: ['config.yaml:12:3: budget: Expected node content.'],
          ),
          locale: const Locale('ru'),
        );

        expect(
          find.descendant(
            of: key('settings-general-agent-unreadable'),
            matching: find.textContaining('Expected node content.'),
          ),
          findsOneWidget,
        );
      });
    });

    group('Баннер записи settings-general-agent-banner (en)', () {
      Future<InfoBar> bannerOf(
        WidgetTester tester,
        AgentDefaultsBanner banner, {
        String configHome = '~/.codelab',
      }) async {
        await pumpPage(tester, _ready(banner: banner, configHome: configHome));
        expect(key('settings-general-agent-banner'), findsOneWidget);
        return tester.widget<InfoBar>(key('settings-general-agent-banner'));
      }

      Finder text(String value) => find.descendant(
        of: key('settings-general-agent-banner'),
        matching: find.textContaining(value),
      );

      testWidgets('Saved.', (tester) async {
        await bannerOf(
          tester,
          const AgentDefaultsBanner(
            AgentDefaultsBannerKind.saved,
            key: 'budget.max_steps',
          ),
        );

        expect(text('Saved.'), findsOneWidget);
        expect(text('Applies'), findsNothing);
      });

      testWidgets('перезапуск: после Restart agent и при старте агента', (
        tester,
      ) async {
        await bannerOf(
          tester,
          const AgentDefaultsBanner(
            AgentDefaultsBannerKind.saved,
            key: 'logging.level',
            restart: AgentDefaultsRestart.afterRestart,
          ),
        );
        expect(text('Saved. Applies after Restart agent.'), findsOneWidget);

        cubit.show(
          _ready(
            banner: const AgentDefaultsBanner(
              AgentDefaultsBannerKind.saved,
              key: 'logging.level',
              restart: AgentDefaultsRestart.whenStarts,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(text('Saved. Applies when the agent starts.'), findsOneWidget);
      });

      testWidgets('перекрытие: warning с источником и действующим значением', (
        tester,
      ) async {
        final bar = await bannerOf(
          tester,
          const AgentDefaultsBanner(
            AgentDefaultsBannerKind.overridden,
            key: 'compaction.enabled',
            overriddenBy: 'local',
            effective: 'false',
          ),
        );

        expect(bar.severity, InfoBarSeverity.warning);
        expect(
          text(
            'Saved to all projects; local overrides it: the agent uses false.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('перекрытие ключа с перезапуском несёт хвост', (
        tester,
      ) async {
        await bannerOf(
          tester,
          const AgentDefaultsBanner(
            AgentDefaultsBannerKind.overridden,
            key: 'logging.level',
            restart: AgentDefaultsRestart.afterRestart,
            overriddenBy: 'local',
            effective: 'error',
          ),
        );

        expect(
          text(
            'Saved to all projects; local overrides it: the agent uses '
            'error. Applies after Restart agent.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('конфликт записи', (tester) async {
        await bannerOf(
          tester,
          const AgentDefaultsBanner(AgentDefaultsBannerKind.conflict),
        );

        expect(
          text(
            'The config file changed on disk; the page was reloaded. '
            'Try again.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('отказ писателя: error, текст проблемы как есть', (
        tester,
      ) async {
        final bar = await bannerOf(
          tester,
          const AgentDefaultsBanner(
            AgentDefaultsBannerKind.rejected,
            key: 'budget.max_cost',
            problems: ['budget.max_cost: must be greater than 0'],
          ),
        );

        expect(bar.severity, InfoBarSeverity.error);
        expect(text('budget.max_cost: must be greater than 0'), findsOneWidget);
      });

      testWidgets('значение, похожее на секрет', (tester) async {
        await bannerOf(
          tester,
          const AgentDefaultsBanner(AgentDefaultsBannerKind.inlineSecret),
        );

        expect(text('Change it with codelab secret set.'), findsOneWidget);
      });

      testWidgets('записано, перечитать не удалось: путь по homePathLabel', (
        tester,
      ) async {
        await pumpPage(
          tester,
          const AgentDefaultsUnreadable(
            reason: AgentDefaultsUnreadableReason.loader,
            problems: ['config.yaml:1:1: broken'],
            banner: AgentDefaultsBanner(
              AgentDefaultsBannerKind.savedUnverified,
            ),
            configHome: '~/work/codelab-home',
          ),
        );

        expect(
          find.descendant(
            of: key('settings-general-agent-banner'),
            matching: find.textContaining(
              'Saved to ~/work/codelab-home/config.yaml.',
            ),
          ),
          findsOneWidget,
        );
      });

      testWidgets('без баннера в состоянии его нет на странице', (
        tester,
      ) async {
        await pumpPage(tester, _ready());

        expect(key('settings-general-agent-banner'), findsNothing);
      });
    });

    group('Русский язык', () {
      const ruLocale = Locale('ru');

      Finder inBanner(String value) => find.descendant(
        of: key('settings-general-agent-banner'),
        matching: find.textContaining(value),
      );

      testWidgets('блок, подписи ключей, тег, пометки и подпись записи', (
        tester,
      ) async {
        await pumpPage(
          tester,
          _ready(
            values: {'budget.max_steps': 80},
            sources: {'budget.max_steps': _user},
          ),
          locale: ruLocale,
        );

        expect(find.text('Умолчания агента'), findsOneWidget);
        expect(find.text('Agent defaults'), findsNothing);
        expect(find.text(ru.settingsGeneralSectionInterface), findsOneWidget);
        expect(
          find.text('Изменения сохраняются для всех проектов.'),
          findsOneWidget,
        );
        // Подписи и описания ключей — из ARB (D2); ключ и источник как есть.
        expect(inRow('budget.max_steps', 'Лимит шагов'), findsOneWidget);
        expect(
          inRow('budget.max_steps', 'Запросов к модели за ход.'),
          findsOneWidget,
        );
        expect(inRow('budget.max_steps', 'budget.max_steps'), findsOneWidget);
        expect(inRow('budget.max_steps', 'user'), findsOneWidget);
        expect(inRow('budget.max_steps', 'Общая'), findsOneWidget);
        expect(inRow('budget.max_steps', 'Max steps'), findsNothing);
        expect(inRow('budget.max_tokens', 'Не задано'), findsOneWidget);
        expect(
          inRow('logging.level', '(применится после перезапуска)'),
          findsOneWidget,
        );
        expect(find.text('(applies after restart)'), findsNothing);
        expect(find.textContaining('Shared with'), findsNothing);
        expect(find.textContaining('~/.codelab/config.yaml'), findsOneWidget);
        expect(find.textContaining('codelab /settings'), findsOneWidget);
      });

      testWidgets('баннеры записи', (tester) async {
        await pumpPage(
          tester,
          _ready(
            banner: const AgentDefaultsBanner(
              AgentDefaultsBannerKind.saved,
              key: 'logging.level',
              restart: AgentDefaultsRestart.afterRestart,
            ),
          ),
          locale: ruLocale,
        );
        expect(inBanner('Сохранено.'), findsOneWidget);
        expect(inBanner('Перезапустить агента'), findsOneWidget);
        expect(inBanner('Saved'), findsNothing);

        cubit.show(
          _ready(
            banner: const AgentDefaultsBanner(
              AgentDefaultsBannerKind.overridden,
              key: 'compaction.enabled',
              overriddenBy: 'local',
              effective: 'false',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(inBanner('Сохранено для всех проектов'), findsOneWidget);
        expect(inBanner('local'), findsOneWidget);
        expect(inBanner('false'), findsOneWidget);

        cubit.show(
          _ready(
            banner: const AgentDefaultsBanner(AgentDefaultsBannerKind.conflict),
          ),
        );
        await tester.pumpAndSettle();
        expect(inBanner('изменился на диске'), findsOneWidget);

        cubit.show(
          _ready(
            banner: const AgentDefaultsBanner(
              AgentDefaultsBannerKind.inlineSecret,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(inBanner('codelab secret set'), findsOneWidget);
        expect(inBanner('Change it'), findsNothing);
      });

      testWidgets('подсказки формата, отказы и перекрытие', (tester) async {
        await pumpPage(
          tester,
          _ready(
            values: {'budget.max_duration': '5s', 'compaction.enabled': false},
            sources: {
              'budget.max_duration': _env,
              'compaction.enabled': _local,
            },
            fieldErrors: {'budget.max_steps', 'budget.max_cost'},
          ),
          locale: ruLocale,
        );

        expect(find.textContaining('Enter a'), findsNothing);
        expect(
          find.descendant(
            of: row('budget.max_steps'),
            matching: find.textContaining('Введите'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row('budget.max_cost'),
            matching: find.textContaining('Введите'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('it cannot be changed here'), findsNothing);
        expect(
          find.descendant(
            of: row('budget.max_duration'),
            matching: find.textContaining('изменить здесь нельзя'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('This project overrides'), findsNothing);
        expect(
          find.descendant(
            of: row('compaction.enabled'),
            matching: find.textContaining('переопределяет'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('только чтение на русском', (tester) async {
        await pumpPage(
          tester,
          const AgentDefaultsReadOnly(
            kind: AgentDefaultsReadOnlyKind.remote,
            subject: 'wss://devbox:7420',
          ),
          locale: ruLocale,
        );

        expect(
          find.descendant(
            of: key('settings-general-agent-read-only'),
            matching: find.textContaining('Только чтение'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('wss://devbox:7420'), findsOneWidget);
        expect(find.textContaining('Read-only'), findsNothing);
      });

      testWidgets('при ширине окна 760 px строки и баннеры не '
          'переполняются', (tester) async {
        await pumpPage(
          tester,
          _ready(
            values: {'logging.level': 'debug', 'budget.max_steps': 80},
            sources: {
              'logging.level': _local,
              'budget.max_steps': _env,
              'budget.max_cost': _user,
            },
            fieldErrors: {'budget.max_duration', 'subagents.max_depth'},
            banner: const AgentDefaultsBanner(
              AgentDefaultsBannerKind.overridden,
              key: 'logging.level',
              restart: AgentDefaultsRestart.afterRestart,
              overriddenBy: 'local',
              effective: 'debug',
            ),
            configHome: '~/work/very/long/path/to/codelab-home',
          ),
          locale: ruLocale,
          size: const Size(760, 3200),
        );

        expect(row('logging.level'), findsOneWidget);
        expect(key('settings-general-agent-banner'), findsOneWidget);
        expect(key('settings-general-shared-info'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('Смена языка и строка Language', () {
      testWidgets('строка Language и её ключи не изменились', (tester) async {
        await pumpPage(tester, _ready());

        expect(key('settings-general-language'), findsOneWidget);
        expect(find.text(en.settingsLanguageTitle), findsWidgets);
        for (final option in ['system', 'en', 'ru']) {
          expect(key('settings-language-$option'), findsOneWidget);
        }
        expect(find.text('English'), findsOneWidget);
        expect(find.text('Русский'), findsOneWidget);
      });

      testWidgets(
        'выбор языка на странице с Agent defaults применяется сразу',
        (tester) async {
          await pumpPage(tester, _ready());
          expect(key('settings-general-agent-defaults'), findsOneWidget);

          await choose(tester, 'settings-language-ru');

          expect(language.state.locale, const Locale('ru'));
          expect(find.text('Умолчания агента'), findsOneWidget);
          expect(find.text(ru.settingsLanguageTitle), findsWidgets);
        },
      );

      testWidgets('смена языка со страницей, баннером и перекрытием не '
          'оставляет строк прежнего языка', (tester) async {
        await pumpPage(
          tester,
          _ready(
            values: {'compaction.enabled': false},
            sources: {'compaction.enabled': _local},
            fieldErrors: {'budget.max_steps'},
            banner: const AgentDefaultsBanner(
              AgentDefaultsBannerKind.overridden,
              key: 'compaction.enabled',
              overriddenBy: 'local',
              effective: 'false',
              restart: AgentDefaultsRestart.whenStarts,
            ),
          ),
        );
        expect(key('settings-general-agent-banner'), findsOneWidget);
        expect(find.text('Agent defaults'), findsOneWidget);

        await choose(tester, 'settings-language-ru');

        expect(find.text('Agent defaults'), findsNothing);
        expect(find.text('Умолчания агента'), findsOneWidget);
        expect(key('settings-general-agent-banner'), findsOneWidget);
        await expectNoStaleLanguage(tester, from: en, to: ru);

        await choose(tester, 'settings-language-en');

        expect(find.text('Agent defaults'), findsOneWidget);
        expect(find.text('Умолчания агента'), findsNothing);
        await expectNoStaleLanguage(tester, from: ru, to: en);
      });
    });
  });

  // --- «Reopen the last project and its tabs» (задача 3.5 change
  // `add-app-general-page`; spec app-settings «Открытие последнего проекта при
  // запуске»; design.md D9). Страница идёт через настоящее дерево app. ------

  group('Reopen the last project and its tabs (D9)', () {
    const rowKey = 'settings-general-reopen-last-project';
    const failedKey = 'settings-general-reopen-last-project-save-failed';
    const retryKey = 'settings-general-reopen-last-project-retry';

    Finder toggle() =>
        find.descendant(of: key(rowKey), matching: find.byType(ToggleSwitch));

    bool checked(WidgetTester tester) =>
        tester.widget<ToggleSwitch>(toggle()).checked;

    Future<void> flip(WidgetTester tester) async {
      expect(toggle(), findsOneWidget);
      await tester.tap(toggle());
      await tester.pumpAndSettle();
    }

    testWidgets('блок «Startup and files» со строкой и подписью идёт после '
        'Interface; строки Show ignored files ещё нет', (tester) async {
      await openGeneral(tester);

      expect(key(rowKey), findsOneWidget);
      expect(find.text('Startup and files'), findsOneWidget);
      expect(find.text('Reopen the last project and its tabs'), findsOneWidget);
      expect(
        find.text(
          'On: open the last project and its open sessions. Off: start with '
          'recent projects in the sidebar. Applies at the next start.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(key('settings-general-language')).dy,
        lessThan(tester.getTopLeft(key(rowKey)).dy),
      );
      expect(key('settings-general-show-ignored'), findsNothing);
      expect(toggle(), findsOneWidget);
      expect(checked(tester), isTrue);
    });

    testWidgets('сохранённое false показывается выключенным', (tester) async {
      await openGeneral(tester, preferences: {kReopenLastProjectKey: false});

      expect(toggle(), findsOneWidget);
      expect(checked(tester), isFalse);
    });

    testWidgets('выключение пишет false, включение удаляет ключ', (
      tester,
    ) async {
      await openGeneral(tester);

      await flip(tester);
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kReopenLastProjectKey), isFalse);
      expect(checked(tester), isFalse);

      await flip(tester);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kReopenLastProjectKey), isFalse);
      expect(checked(tester), isTrue);
    });

    testWidgets('переключение не трогает текущую работу: проект, сессии, '
        'подключение и кадры агенту не меняются', (tester) async {
      final binding = await openGeneral(tester);
      final shell = binding.scope.resolve<CodeLabShellCubit>();
      final before = shell.state;
      final sentBefore = binding.transport.sentMessages.length;
      expect(before.selectedProjectPath, '/workspace');

      await flip(tester);
      await flip(tester);

      expect(shell.state.selectedProjectPath, '/workspace');
      expect(shell.state.connectionStatus, before.connectionStatus);
      expect(shell.state.sessions, before.sessions);
      expect(shell.state.activeSessionId, before.activeSessionId);
      expect(binding.transport.sentMessages.length, sentBefore);
      expect(key('settings-general-agent-defaults'), findsOneWidget);
    });

    testWidgets('сбой записи: переключатель в выбранном положении, '
        'предупреждение без текста исключения и Retry', (tester) async {
      final port = _StartupPort(failSaves: 1);
      await openGeneral(tester, startupPreferences: port);

      await flip(tester);

      expect(port.saves, [false]);
      expect(checked(tester), isFalse);
      expect(key(failedKey), findsOneWidget);
      expect(
        find.text(
          "Couldn't save this setting. The previous value applies at the "
          'next start.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('/secret/path'), findsNothing);
      expect(find.textContaining('read-only'), findsNothing);
      expect(key(retryKey), findsOneWidget);
      expect(
        find.descendant(of: key(retryKey), matching: find.text('Retry')),
        findsOneWidget,
      );
    });

    testWidgets('Retry повторяет запись; успех скрывает предупреждение', (
      tester,
    ) async {
      final port = _StartupPort(failSaves: 1);
      await openGeneral(tester, startupPreferences: port);
      await flip(tester);
      expect(key(retryKey), findsOneWidget);

      await tester.tap(key(retryKey));
      await tester.pumpAndSettle();

      expect(port.saves, [false, false]);
      expect(key(failedKey), findsNothing);
      expect(checked(tester), isFalse);
    });

    testWidgets('без сбоя предупреждения нет', (tester) async {
      await openGeneral(tester);

      await flip(tester);

      expect(key(failedKey), findsNothing);
      expect(key(retryKey), findsNothing);
    });

    testWidgets('на русском: блок, подпись строки и смена языка с '
        'предупреждением не оставляют английского', (tester) async {
      await openGeneral(tester, startupPreferences: _StartupPort(failSaves: 1));
      await flip(tester);
      expect(key(failedKey), findsOneWidget);

      await choose(tester, 'settings-language-ru');

      expect(find.text('Startup and files'), findsNothing);
      expect(find.text('Запуск и файлы'), findsOneWidget);
      expect(
        find.descendant(
          of: key(rowKey),
          matching: find.textContaining('Открывать последний проект'),
        ),
        findsWidgets,
      );
      expect(
        find.text(
          "Couldn't save this setting. The previous value applies at the "
          'next start.',
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: key(retryKey), matching: find.text('Повторить')),
        findsOneWidget,
      );
      expect(key(failedKey), findsOneWidget);
      await expectNoStaleLanguage(tester, from: en, to: ru);
    });
  });

  // --- Раздел «About» (задача 5.9 change `add-app-general-page`; spec
  // app-settings «Раздел «About» страницы «General»», «Диагностика для отчёта
  // без секретов и путей», «События журнала страницы «General»»; design.md
  // D11–D14, D17). Страница идёт через настоящее дерево app, порты ссылок и
  // каталогов, данные `AboutInfo` и буфер обмена — двойники. -----------------

  group('About (D11–D14)', () {
    const logDir = '/tmp/about-logs-marker';
    final root = File('../../LICENSE').readAsLinesSync();
    final about = AboutInfo(
      version: '0.1.0',
      os: 'macOS',
      arch: 'arm64',
      embeddedAgentVersion: '0.1.0',
      licenseName: 'MIT',
      licenseCopyright: root[2],
      configHome: '~/.codelab-about',
      logDirectory: logDir,
      thirdPartyNotices: File(
        '../../THIRD_PARTY_NOTICES.md',
      ).readAsStringSync(),
    );

    late FakeExternalLinkOpener links;
    late FakeLocalFolderOpener folders;
    late CodeLabTestBinding binding;
    late List<String> clipboard;

    Future<void> openAbout(WidgetTester tester) async {
      links = FakeExternalLinkOpener();
      folders = FakeLocalFolderOpener();
      clipboard = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      binding = await openGeneral(
        tester,
        aboutInfo: about,
        externalLinkOpener: links,
        localFolderOpener: folders,
      );
    }

    Future<void> expand(WidgetTester tester) async {
      expect(key('settings-general-about'), findsOneWidget);
      await tester.ensureVisible(key('settings-general-about'));
      await tester.tap(find.text('CodeLab 0.1.0'));
      await tester.pumpAndSettle();
    }

    Future<void> press(WidgetTester tester, String buttonKey) async {
      expect(key(buttonKey), findsOneWidget);
      await tester.ensureVisible(key(buttonKey));
      await tester.tap(key(buttonKey));
      await tester.pumpAndSettle();
    }

    Iterable<Map<String, Object?>> aboutEvents() => binding.scope
        .resolve<LogBuffer>()
        .entries
        .value
        .where((e) => e['event'] == 'settings.about_action');

    testWidgets('заголовок: версия сборки, ОС, архитектура и версия '
        'встроенного агента; Channel и Signed by нет', (tester) async {
      await openAbout(tester);

      expect(key('settings-general-about'), findsOneWidget);
      expect(find.text('CodeLab 0.1.0'), findsOneWidget);
      expect(find.text('macOS arm64 · embedded agent 0.1.0'), findsOneWidget);
      expect(find.text('Channel'), findsNothing);
      expect(find.text('Signed by'), findsNothing);
      // «About» идёт после блока «Startup and files».
      expect(
        tester.getTopLeft(key('settings-general-reopen-last-project')).dy,
        lessThan(tester.getTopLeft(key('settings-general-about')).dy),
      );
    });

    testWidgets('развёрнутый раздел: лицензия, папка настроек, четыре кнопки '
        'и InfoBar об обновлениях', (tester) async {
      await openAbout(tester);

      await expand(tester);

      expect(find.text('License'), findsOneWidget);
      expect(find.text('MIT'), findsOneWidget);
      expect(find.text(root[2]), findsOneWidget);
      expect(find.text('Config folder'), findsOneWidget);
      expect(find.text('~/.codelab-about'), findsOneWidget);
      for (final k in [
        'settings-general-about-copy-diagnostics',
        'settings-general-about-third-party',
        'settings-general-about-release-notes',
        'settings-general-about-open-logs',
      ]) {
        expect(key(k), findsOneWidget, reason: k);
      }
      final updates = tester.widget<InfoBar>(
        key('settings-general-about-updates'),
      );
      expect(updates.severity, InfoBarSeverity.info);
      expect(
        find.text(
          'Updates come from the installer or your package manager — the app '
          'does not update itself.',
        ),
        findsOneWidget,
      );
      expect(find.text('Channel'), findsNothing);
      expect(find.text('Signed by'), findsNothing);
      expect(find.text('Privacy policy'), findsNothing);
      expect(find.text('Send crash reports'), findsNothing);
    });

    group('Third-party notices', () {
      testWidgets('диалог офлайн: запись из THIRD_PARTY_NOTICES.md и список '
          'лицензий пакетов', (tester) async {
        LicenseRegistry.addLicense(
          () => Stream.value(
            const LicenseEntryWithLineBreaks(['marker_pkg_5_9'], 'Marker text'),
          ),
        );
        await openAbout(tester);
        await expand(tester);

        await press(tester, 'settings-general-about-third-party');

        expect(key('settings-general-third-party-dialog'), findsOneWidget);
        expect(
          find.descendant(
            of: key('settings-general-third-party-dialog'),
            matching: find.textContaining('JetBrains Mono', findRichText: true),
          ),
          findsWidgets,
        );
        expect(
          find.descendant(
            of: key('settings-general-third-party-dialog'),
            matching: find.text('marker_pkg_5_9'),
          ),
          findsOneWidget,
        );
        final opened = aboutEvents().where((e) => e['action'] == 'third_party');
        expect(opened.single['outcome'], 'opened');
      });
    });

    // Только записи реестра (задача 7.7, D13): без заголовка первого уровня,
    // вводной, «Формат записи» и шаблона; подпись на языке интерфейса.
    group('Third-party notices: только записи реестра (D13)', () {
      const dialogKey = 'settings-general-third-party-dialog';
      const captionEn =
          'Entries of the CodeLab third-party notices register, as kept in '
          'the repository.';
      const captionRu =
          'Записи реестра сторонних уведомлений CodeLab в том виде, в каком '
          'они хранятся в репозитории.';

      Finder inDialog(Finder matching) =>
          find.descendant(of: key(dialogKey), matching: matching);

      testWidgets('en: записи на русском, подпись на английском, служебных '
          'разделов нет, заголовок диалога один раз', (tester) async {
        await openAbout(tester);
        await expand(tester);

        await press(tester, 'settings-general-about-third-party');

        expect(key(dialogKey), findsOneWidget);
        expect(
          inDialog(find.textContaining('JetBrains Mono', findRichText: true)),
          findsWidgets,
        );
        expect(inDialog(find.text(captionEn)), findsOneWidget);
        expect(
          inDialog(find.textContaining('Формат записи', findRichText: true)),
          findsNothing,
        );
        expect(
          inDialog(
            find.textContaining('<Название источника>', findRichText: true),
          ),
          findsNothing,
        );
        expect(inDialog(find.text('Third-party notices')), findsOneWidget);
      });

      testWidgets('ru: подпись на русском, записи те же', (tester) async {
        await openAbout(tester);
        await choose(tester, 'settings-language-ru');
        await expand(tester);

        await press(tester, 'settings-general-about-third-party');

        expect(inDialog(find.text(captionRu)), findsOneWidget);
        expect(inDialog(find.text(captionEn)), findsNothing);
        expect(
          inDialog(find.textContaining('JetBrains Mono', findRichText: true)),
          findsWidgets,
        );
        expect(
          inDialog(find.textContaining('Формат записи', findRichText: true)),
          findsNothing,
        );
      });
    });

    group('Release notes', () {
      testWidgets('открываются через порт один раз с адресом CHANGELOG.md', (
        tester,
      ) async {
        expect(kCodeLabReleaseNotesUrl, isNotEmpty);
        await openAbout(tester);
        await expand(tester);

        await press(tester, 'settings-general-about-release-notes');

        expect(links.opened, [Uri.parse(kCodeLabReleaseNotesUrl)]);
        expect(key('settings-general-about-open-failed'), findsNothing);
        final event = aboutEvents().single;
        expect(event['action'], 'release_notes');
        expect(event['outcome'], 'opened');
      });

      testWidgets('сбой: InfoBar без адреса и текста исключения', (
        tester,
      ) async {
        await openAbout(tester);
        links.outcome = ExternalLinkOutcome.failed;
        await expand(tester);

        await press(tester, 'settings-general-about-release-notes');

        expect(key('settings-general-about-open-failed'), findsOneWidget);
        expect(find.text("Couldn't open the release notes."), findsOneWidget);
        expect(find.textContaining('CHANGELOG'), findsNothing);
        expect(aboutEvents().single['outcome'], 'failed');
      });

      testWidgets('схема вне политики порта: тот же InfoBar, исход '
          'rejected_scheme', (tester) async {
        await openAbout(tester);
        links.outcome = ExternalLinkOutcome.rejectedScheme;
        await expand(tester);

        await press(tester, 'settings-general-about-release-notes');

        expect(find.text("Couldn't open the release notes."), findsOneWidget);
        expect(aboutEvents().single['outcome'], 'rejected_scheme');
      });
    });

    group('Open log folder', () {
      testWidgets('каталог журналов открывается без создания', (tester) async {
        await openAbout(tester);
        await expand(tester);

        await press(tester, 'settings-general-about-open-logs');

        expect(folders.calls, [(directory: logDir, create: false)]);
        expect(key('settings-general-about-open-failed'), findsNothing);
        final event = aboutEvents().single;
        expect(event['action'], 'open_logs');
        expect(event['outcome'], 'opened');
      });

      testWidgets('не открылся: InfoBar без пути', (tester) async {
        await openAbout(tester);
        folders.outcome = FolderOpenOutcome.failed;
        await expand(tester);

        await press(tester, 'settings-general-about-open-logs');

        expect(key('settings-general-about-open-failed'), findsOneWidget);
        expect(find.text("Couldn't open the log folder."), findsOneWidget);
        expect(find.textContaining('about-logs-marker'), findsNothing);
        expect(aboutEvents().single['outcome'], 'failed');
      });

      testWidgets('каталога нет: тот же InfoBar, исход missing', (
        tester,
      ) async {
        await openAbout(tester);
        folders.outcome = FolderOpenOutcome.missing;
        await expand(tester);

        await press(tester, 'settings-general-about-open-logs');

        expect(find.text("Couldn't open the log folder."), findsOneWidget);
        expect(aboutEvents().single['outcome'], 'missing');
      });
    });

    group('Copy diagnostics', () {
      testWidgets('кладёт в буфер фиксированный текст и показывает '
          'подтверждение', (tester) async {
        await openAbout(tester);
        await expand(tester);

        await press(tester, 'settings-general-about-copy-diagnostics');

        expect(clipboard, hasLength(1));
        final lines = clipboard.single.trim().split('\n');
        expect(lines, hasLength(7));
        expect(lines[0], 'CodeLab 0.1.0');
        expect(lines[1], 'OS: macOS arm64');
        expect(lines[2], 'Embedded agent: 0.1.0');
        expect(lines[3], 'UI language: en (preference: system)');
        // Окно ещё не подключено, профиль по умолчанию — свой stdio-агент.
        expect(lines[4], 'Connection: stdio · disconnected');
        expect(lines[5], 'Agent settings: editable');
        // `CODELAB_HOME` зависит от машины, поэтому признак — по образцу.
        expect(lines[6], matches(RegExp(r'^Config folder: (default|custom)$')));
        expect(find.text('Diagnostics copied.'), findsOneWidget);
        final event = aboutEvents().single;
        expect(event['action'], 'copy_diagnostics');
        expect(event['outcome'], 'copied');
      });

      testWidgets('в буфере нет путей, адресов и значений конфигурации', (
        tester,
      ) async {
        await openAbout(tester);
        await expand(tester);

        await press(tester, 'settings-general-about-copy-diagnostics');

        expect(clipboard, hasLength(1));
        final text = clipboard.single;
        expect(text, isNotEmpty);
        for (final leak in [
          'about-logs-marker',
          '.codelab-about',
          '/workspace',
          'http',
          '://',
          root[2],
        ]) {
          expect(text, isNot(contains(leak)), reason: leak);
        }
      });

      testWidgets('на русском: подписи английские, язык в строке', (
        tester,
      ) async {
        await openAbout(tester);
        await choose(tester, 'settings-language-ru');
        await expand(tester);

        await press(tester, 'settings-general-about-copy-diagnostics');

        expect(clipboard, hasLength(1));
        expect(clipboard.single, contains('UI language: ru (preference: ru)'));
        expect(clipboard.single, isNot(matches(RegExp(r'[А-Яа-яЁё]'))));
        expect(find.text('Diagnostics copied.'), findsNothing);
        expect(find.text('Диагностика скопирована.'), findsOneWidget);
      });

      testWidgets('события журнала без путей и адресов', (tester) async {
        await openAbout(tester);
        await expand(tester);
        folders.outcome = FolderOpenOutcome.failed;

        await press(tester, 'settings-general-about-open-logs');
        await press(tester, 'settings-general-about-release-notes');
        await press(tester, 'settings-general-about-copy-diagnostics');

        expect(aboutEvents(), hasLength(3));
        final text = aboutEvents().toList().toString();
        expect(text, isNot(contains('about-logs-marker')));
        expect(text, isNot(contains('github.com')));
        expect(text, isNot(contains('CHANGELOG')));
      });
    });

    group('смена языка с открытым About', () {
      testWidgets('раздел, InfoBar сбоя и подписи не оставляют английского', (
        tester,
      ) async {
        await openAbout(tester);
        folders.outcome = FolderOpenOutcome.failed;
        await expand(tester);
        await press(tester, 'settings-general-about-open-logs');
        expect(key('settings-general-about-open-failed'), findsOneWidget);

        await choose(tester, 'settings-language-ru');

        expect(find.text("Couldn't open the log folder."), findsNothing);
        expect(key('settings-general-about-open-failed'), findsOneWidget);
        expect(find.text('License'), findsNothing);
        expect(find.text('Config folder'), findsNothing);
        // Версия и название продукта не переводятся (глоссарий §2).
        expect(find.text('CodeLab 0.1.0'), findsOneWidget);
        await expectNoStaleLanguage(tester, from: en, to: ru);
      });

      testWidgets('открытый диалог сторонних уведомлений тоже переводится', (
        tester,
      ) async {
        await openAbout(tester);
        await expand(tester);
        await press(tester, 'settings-general-about-third-party');
        expect(key('settings-general-third-party-dialog'), findsOneWidget);

        await tester.runAsync(
          () => binding.scope.resolve<AppLanguageCubit>().select(
            AppLanguagePreference.ru,
          ),
        );
        await tester.pumpAndSettle();

        expect(key('settings-general-third-party-dialog'), findsOneWidget);
        // Заголовок самого THIRD_PARTY_NOTICES.md — содержимое юридического
        // документа и не переводится, поэтому `expectNoStaleLanguage` для
        // диалога дал бы ложное срабатывание: проверяем подписи диалога.
        final dialog = key('settings-general-third-party-dialog');
        expect(
          find.descendant(
            of: dialog,
            matching: find.text('Сторонние уведомления'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('Лицензии пакетов')),
          findsOneWidget,
        );
        expect(find.text('Закрыть'), findsOneWidget);
        expect(find.text('Close'), findsNothing);
        expect(find.text('Package licenses'), findsNothing);
      });
    });
  });
}
