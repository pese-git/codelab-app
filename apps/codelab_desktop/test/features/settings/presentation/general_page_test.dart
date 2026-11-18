// Красные тесты страницы «General» (задача 1.9 change
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
// Красные тесты: страница — прежняя, блоков нет, тело появится в задаче 2.6.
//
// Контракт ключей (spec): `settings-general-shared-info`,
// `settings-general-agent-defaults`, `settings-general-agent-row-<key>`,
// `settings-general-agent-banner`, `settings-general-agent-read-only`,
// `settings-general-agent-unreadable`. Ключи, которых в spec нет, вводит этот
// тест: `settings-general-agent-loading` (индикатор загрузки).
// Редакторы ищутся по типу виджета внутри строки (`ToggleSwitch`, `ComboBox`,
// `TextBox`), своих ключей у них нет.

import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/features/settings/application/agent_defaults_cubit.dart';
import 'package:codelab_desktop/features/settings/application/agent_defaults_rows.dart';
import 'package:codelab_desktop/features/settings/presentation/general_page.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_shell.dart';
import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/l10n_app.dart';
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
  }) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      settingsPages: const SettingsPages(
        available: {SettingsPage.connection, SettingsPage.general},
      ),
      languagePreferences: languagePreferences,
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

    /// Страница «General» в дереве, как его собирает `CodeLabApp`: язык
    /// выбирает `AppLanguageCubit`, а `FluentApp` не пересоздаётся.
    Future<void> pumpPage(
      WidgetTester tester,
      AgentDefaultsState state, {
      Locale locale = const Locale('en'),
      Size size = const Size(1200, 2600),
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
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AppLanguageCubit>.value(value: language),
            BlocProvider<AgentDefaultsCubit>.value(value: cubit),
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
              home: const ScaffoldPage(
                content: SingleChildScrollView(child: GeneralPage()),
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
        expect(find.text('Startup and files'), findsNothing);
        expect(key('settings-general-reopen-last-project'), findsNothing);
        expect(key('settings-general-show-ignored'), findsNothing);
        expect(key('settings-general-about'), findsNothing);
        for (final hidden in [
          'When I press Enter during a turn',
          'Sidebar opens on',
          'Send crash reports',
          'Privacy policy',
          'Privacy',
          'About',
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
        await tester.pump();

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
        expect(find.byType(ToggleSwitch), findsNothing);
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
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AppLanguageCubit>.value(value: language),
              BlocProvider<AgentDefaultsCubit>.value(value: cubit),
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
        expect(inRow('budget.max_steps', 'Макс. шагов'), findsOneWidget);
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
}
