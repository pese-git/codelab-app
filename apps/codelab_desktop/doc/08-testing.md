# Тестирование app

Глава о том, как проверяется `apps/codelab_desktop`: какие бывают тесты, где лежат двойники, как написать тест Cubit-а и страницы, что делают тесты-сторожа внутри приложения и как устроены интеграционные тесты на устройстве. Общую стратегию задаёт [`docs/architecture/testing.md`](../../../docs/architecture/testing.md), требования к проверкам — спецификация [`testing-quality`](../../../openspec/specs/testing-quality/spec.md). Здесь они не пересказываются: глава показывает, как это устроено в коде app. Краткая таблица команд — в [development.md](development.md#тесты).

Перед главой полезно прочитать [02-composition-root.md](02-composition-root.md): почти все виджет-тесты строят приложение через `createCodeLabRootScope`, и швы этой функции — основа двойников.

## Уровни тестов

Принцип стратегии: тест лежит на самом нижнем уровне, где он ещё проверяет нужное поведение. Нижние уровни быстрее и не зависят от окна, файлов и процессов.

| Уровень | Что проверяет | Где лежит | Как запустить |
|---|---|---|---|
| Тест Cubit-а и чистых функций | состояния, переходы, мапперы, фильтры, порты | `test/features/<фича>/application/`, `test/app/`, `test/core/` | `fvm flutter test <файл>` в `apps/codelab_desktop` |
| Виджет-тест страницы или панели | что показывает виджет из состояния и что вызывает по жесту | `test/features/<фича>/presentation/` | то же |
| Тест в настоящем дереве app | страница или поток через `CodeLabApp`, настоящий граф Cherrypick и двойники портов | те же каталоги; обвязка `test/support/test_app_scope.dart` | то же |
| Тест-сторож внутри app | расхождение копий файлов, каталогов ARB, версии сборки, литералов клавиш | `test/app/`, `test/l10n/`, `test/tool/` | то же |
| Интеграционный тест | настоящее приложение macOS против scripted-агента, Dart-агента или встроенного агента со сценарием модели | `integration_test/` | `test:e2e:app:*`, только в `release/<version>` |

Сторож всего репозитория (`melos run guard`) — отдельный пакет `codelab_architecture_tests`; его правила для app перечислены ниже.

Библиотек моков (`mockito`, `mocktail`) и `bloc_test` в app нет: из тестовых пакетов в `dev_dependencies` приложения только `flutter_test`, `integration_test`, `flutter_driver` и `codelab_acp_testing` (остальное — генераторы и линты: `build_runner`, `cherrypick_generator`, `freezed`, `flutter_lints`). Двойники пишутся вручную; часть из них — на базе `Fake` из `flutter_test`.

## Раскладка `test/`

`test/` повторяет раскладку `lib/`:

| Каталог | Что проверяет |
|---|---|
| `test/app/` | composition root (`app_scope`, закрытие scope, выход), язык (`language/`), оформление (`appearance/`), навигация (`navigation/`), приветственные шаги, порты раздела «About» и страницы «Legal», тесты-сторожа |
| `test/core/` | адаптеры и порты платформы (`platform/`), общие текстовые функции |
| `test/features/workbench/` | рабочее место: Cubit-ы оболочки, мапперы ленты `ui_mappers`, одобрения, виджеты; `application/shell_cubit_characterization/` — характеризационные тесты фасада `CodeLabShellCubit` |
| `test/features/settings/` | страницы настроек: Cubit-ы в `application/`, страницы и диалоги в `presentation/` |
| `test/features/onboarding/`, `protocol/`, `terminal/`, `usage/`, `project_files/` | одноимённые фичи |
| `test/l10n/` | каталоги ARB, список Cubit-ов с текстом, помощник смены языка, общий прогон смены языка |
| `test/tool/` | скрипт `l10n:check` на временной копии пакета |
| `test/support/` | двойники и обвязка (следующий раздел) |
| `test/flutter_test_config.dart`, `test/widget_test.dart`, `test/app_scope_logging_test.dart` | общая настройка прогона, сквозной тест приложения, события журнала composition root |

Имена файлов: `<предмет>_test.dart`. Тест, который проверяет перевод, получает суффикс `_l10n` (`keyboard_page_l10n_test.dart`).

## Что настраивает `flutter_test_config.dart`

Flutter подхватывает `test/flutter_test_config.dart` для каждого тестового файла каталога. Единственная его задача — страж настоящего файла недавних проектов.

- Перед файлом (`setUpAll`) запоминает байты настоящего `$CODELAB_HOME/recent_projects.json` разработчика (дом определяет `resolveCodelabHome`), после файла (`tearDownAll`) сверяет их.
- Если файл изменился или появился, прогон файла падает. Причина: `createCodeLabRootScope` без швов `environment:` и `recentProjectsStore:` берёт `Platform.environment` и пишет проекты теста в общий файл, который читает и `codelab`.
- Лечится швом: тест передаёт `recentProjectsStore: FakeRecentProjectsStore()` или временный `environment: {'CODELAB_HOME': …}`. `CodeLabTestBinding` делает это сам.
- Ложное срабатывание возможно, если во время прогона файл меняет другой процесс (`codelab`, запущенное app): прогон просто повторяют.

У `integration_test/flutter_test_config.dart` другая роль — он описан в разделе про интеграционные тесты.

## Двойники и обвязка: `test/support/`

Двойники лежат в `test/support/`, по одному файлу на порт или сценарий. Каждый файл начинается с комментария (`///` или `//`) «почему, для чего, как использовать» — читайте его до использования. Файлы подключаются относительным импортом (`import '../../../support/…'`).

| Группа | Файлы | Назначение |
|---|---|---|
| Сборка приложения | `test_app_scope.dart` | `CodeLabTestBinding`: строит `createCodeLabRootScope` с двойниками по умолчанию; `closeCodeLabRootScopeInTest` — закрытие scope из teardown |
| | `live_scene.dart` | живое рабочее место с ответом агента, вызовом и одобрением для сквозных прогонов языка и темы |
| | `start_agent.dart` | замена ручного «Connect»: запуск агента по тем же триггерам, что в приложении |
| Хранилища | `in_memory_profile_store.dart`, `fake_recent_projects_store.dart`, `fake_profile_secrets.dart` | профили, недавние проекты и секреты в памяти |
| Порты платформы | `fake_external_link_opener.dart`, `fake_local_folder_opener.dart`, `fake_user_shell_launcher.dart`, `fake_theme_file_picker.dart`, `fake_system_accent_source.dart`, `fake_usage_csv_saver.dart`, `fake_protocol_export_saver.dart` | записывают вызовы порта и возвращают заданный исход; системный диалог, браузер или PTY не открываются |
| Клиентский слой | `fake_client_workspace.dart` (`FakeClientWorkspace`, `FakeSessionHandle`), `fake_protocol_workspace.dart`, `fake_log_record_source.dart`, `fake_project_files.dart` | управляемые `ClientWorkspace`, буфер кадров, журнал и файлы проекта |
| Настройки агента | `fake_provider_settings.dart`, `fake_provider_wizard.dart`, `fake_mcp_status.dart`, `fake_agents_modes_cubit.dart`, `fake_definitions_loader.dart`, `fake_agent_extensions.dart`, `fake_onboarding.dart` | страницы «Providers», «MCP servers», «Agents & modes», «Skills & extensions» и приветственные шаги без файлов конфигурации |
| Настоящие файлы во временной папке | `modes_fixture.dart`, `real_config_session.dart`, `real_skills_session.dart` | Cubit-ы, которые проверяют разбор настоящего `config.yaml`; идут в обычном `test`, не в `testWidgets` |
| Страница «Legal» | `legal_fixture.dart` | двойники портов «Legal» и открытие страницы в настоящем дереве app |
| Язык | `app_strings.dart` (`FixedAppStrings`, `TestAppStrings`), `l10n_app.dart` (`localizedFluentApp`, `l10nTestDelegates`), `l10n_mix.dart` (`expectNoStaleLanguage`), `l10n_page_harness.dart`, `settings_search.dart`, `typed_messages.dart` | английские тексты по умолчанию, смена языка на лету, проверка «не осталось строк прежнего языка» |
| Клавиши | `press_shortcut.dart`, `keyboard_rows.dart` | нажатие записи каталога кита и таблица страницы «Keyboard» из спецификации |
| Прочее | `recording_logger.dart` (`RecordingLogger`), `transcript_rows.dart`, `protocol_fixtures.dart`, `no_text_leak.dart`, `png_fixture.dart` | запись событий журнала, короткие проверки строк ленты, данные панели Protocol, поиск видимого текста, минимальный PNG |

### `CodeLabTestBinding`

`CodeLabTestBinding` — главная обвязка. Конструктор принимает швы `createCodeLabRootScope` и подставляет безопасные значения по умолчанию, чтобы тест не зависел от машины разработчика:

| Шов | Значение по умолчанию в тесте | Зачем |
|---|---|---|
| `transport` | `FakeAcpTransport` из `codelab_acp_testing` | агента нет, кадры подаёт тест |
| `profileStore` | `InMemoryProfileStore` с stdio-профилем | файл `profiles.json` в `testWidgets` зависает |
| `recentProjectsStore` | `FakeRecentProjectsStore` | то же, плюс страж `flutter_test_config.dart` |
| `embeddedOpener` | открыватель, который сразу бросает `StateError` | настоящий читал бы `~/.codelab` |
| `providerSettingsOpener`, `providerSetupProbe` | «не часть этого теста» и «провайдер не нужен» | то же |
| `projectFolderPicker` | диалог закрыт без выбора | системный диалог |
| `directoryExists` | любая папка существует | тесты используют вымышленные пути вроде `/work/app` |
| `locale` | `en` | существующие `find.text` на английском |
| `onboarding` | не показывается | приветственные шаги не мешают тестам рабочего места |
| `stdioDefault` | `true`: профилем по умолчанию выбран stdio-агент | правило «нет выбора — встроенный агент» проверяют тесты с `stdioDefault: false` |

Остальные швы — порты платформы и страниц (`userShellLauncher`, `externalLinkOpener`, `localFolderOpener`, `themeLibrary`, `systemAccentSource`, `startupPreferences`, `aboutInfo`, `legalPorts`, `usageCsvSaver`, `protocolExportSaver`, `projectFiles`, `clock` и другие) — по умолчанию либо двойники, либо настоящие адаптеры, которые в тесте безопасны. Полный перечень — в конструкторе класса. Стартовый проект передаётся параметром `project:`: он кладётся в снимок рабочего пространства и выбирается при создании `SettingsCubit`.

Привязка закрывает root scope в `addTearDown`: Cherrypick хранит статический корень, и тест, упавший до собственного `closeCodeLabRootScope()`, испортил бы все следующие.

## Тест Cubit-а

Cubit — самый частый и самый быстрый тест. Он не поднимает дерево виджетов: создаёт Cubit с портами-двойниками, вызывает методы и проверяет `cubit.state`. `bloc_test` не используется; проверки пишутся обычными `expect`.

Скелет — по реальному тесту `test/features/settings/application/startup_settings_cubit_test.dart` (Cubit переключателя «Reopen the last project»):

```dart
import 'package:codelab_desktop/core/platform/startup_preferences.dart';
import 'package:codelab_desktop/features/settings/application/startup_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_logger.dart';

/// Порт-двойник: записи идут в [saves], сбой задаёт тест.
final class _Port implements StartupPreferences {
  _Port({this.stored = const StartupLoad(true)});

  StartupLoad stored;
  final saves = <bool>[];
  Object? saveError; // `null` — запись проходит

  @override
  Future<StartupLoad> load() async => stored;

  @override
  Future<void> save(bool reopenLastProject) async {
    saves.add(reopenLastProject);
    if (saveError case final error?) throw error;
  }
}

void main() {
  late RecordingLogger logger;
  late _Port port;
  late StartupSettingsCubit cubit;

  StartupSettingsCubit make([_Port? custom]) {
    port = custom ?? _Port();
    cubit = StartupSettingsCubit(preferences: port, logger: logger);
    addTearDown(cubit.close); // Cubit всегда закрывается
    return cubit;
  }

  setUp(() => logger = RecordingLogger());

  test('сбой записи: значение остаётся выбранным, событие без текста ошибки',
      () async {
    make();
    port.saveError = StateError('disk is read-only: /secret/path');

    await cubit.select(false);

    expect(cubit.state.reopenLastProject, isFalse);
    expect(cubit.state.saveFailed, isTrue);
    final failed = logger.entries
        .singleWhere((e) => e['event'] == 'settings.reopen_last_project_save_failed');
    expect(failed['error_type'], 'StateError');
    expect(logger.entries.toString(), isNot(contains('/secret/path')));
  });
}
```

Что берёт этот тест из общей практики app:

- **Порт вместо файла.** Cubit получает порт интерфейсом, тест подставляет свой класс на несколько строк. Настоящий адаптер (`SharedPreferencesStartupPreferences`) проверяет отдельный тест в `test/core/platform/`.
- **Журнал как наблюдаемый результат.** `RecordingLogger` складывает записи в `entries` (поля, `event`, `level`). Тест проверяет и событие, и то, что в записи нет путей и текста ошибки (корневой `AGENTS.md` §16).
- **Закрытие в `addTearDown`.** Cubit с подпиской или таймером без `close()` оставляет их живыми после теста: таймер остаётся «висеть», подписка принимает события следующих тестов.
- **Поздний результат.** Тест `запись после close() не меняет состояние и не бросает` проверяет правило корневого `AGENTS.md` §9: событие старого запроса не меняет актуальное состояние. Такой тест нужен каждому Cubit-у, у которого есть `await` с портом.

### Cubit с подпиской и таймерами

Если Cubit подписывается на поток `ClientWorkspace` и склеивает публикации таймером, тест создаёт его внутри `testWidgets`, а не в `setUp`: обработчик подписки выполняется в зоне вызова `listen`, и таймер из `setUp` шёл бы по настоящему времени, а не по `tester.pump(Duration)`. Пакет `fake_async` в app не подключён. Образец — `test/features/protocol/application/protocol_pane_cubit_test.dart` (вспомогательная функция `testCubit` создаёт Cubit внутри `testWidgets` и закрывает его через `tester.runAsync(cubit.close)`).

Источник состояния клиентского слоя тест подменяет `FakeClientWorkspace` (`test/support/fake_client_workspace.dart`): `emit(WorkspaceState)` публикует состояние синхронно, `hasStateListeners` показывает, отменил ли Cubit подписку в `close()`. Проверка отмены подписки — обязательная часть теста Cubit-а с подпиской (корневой `AGENTS.md` §9).

### Cubit с текстом в состоянии

Cubit, который хранит переведённый текст, получает порт `AppStrings`. Тест передаёт `FixedAppStrings(AppLocalizationsEn())`, а проверку смены языка строит на `TestAppStrings`:

```dart
final strings = TestAppStrings(AppLocalizationsEn());
addTearDown(strings.close);
final cubit = MyCubit(strings: strings); // Cubit из списка D12

strings.emit(AppLocalizationsRu());      // смена языка
// … проверить, что проекция пересобрана, а ввод пользователя остался
await cubit.close();
expect(strings.hasListener, isFalse);    // подписка снята
expect(strings.subscriberCount, 0);
```

Образец целиком — `test/features/settings/application/add_profile_cubit_l10n_test.dart`. Список таких Cubit-ов сверяет `test/l10n/cubit_text_list_test.dart`.

## Виджет-тест страницы

Страницу проверяют двумя способами. Выбор простой: если страница не требует Cubit-ов и портов из composition root, ей хватает оболочки настроек; если требует — поднимается настоящее дерево app.

### Страница в оболочке настроек

Так устроен `test/features/settings/presentation/keyboard_page_test.dart`: страница «Keyboard» не имеет Cubit-а, поэтому тест кладёт её построитель в `SettingsShell` и оборачивает в `localizedFluentApp`.

```dart
Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    localizedFluentApp(
      SettingsShell(
        pages: const SettingsPages(available: {SettingsPage.keyboard}),
        selected: SettingsPage.keyboard,
        onSelected: (_) {},
        onBack: () {},
        builders: {SettingsPage.keyboard: buildKeyboardPage},
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

- `localizedFluentApp` (`test/support/l10n_app.dart`) подключает делегаты app, кита и Fluent: без них `context.l10n` падает. Язык по умолчанию — `en`; для перевода передают `locale: const Locale('ru')`. Свой список делегатов в тесте не собирают.
- Размер окна задаётся через `tester.view`, а не через `MediaQuery`: ширина меньше 760 точек переводит навигацию настроек в узкую раскладку (`settingsNarrowBreakpoint`).
- Элементы ищут по `ValueKey` (`find.byKey(const ValueKey('settings-keyboard-search'))`), а не по тексту: ключи — контракт между страницей и тестом (в том числе интеграционным).

### Страница в настоящем дереве app

Страница, которой нужны Cubit-ы и порты, проверяется через `CodeLabApp` и `CodeLabTestBinding`. Так начинается большинство тестов страницы «General» (`test/features/settings/presentation/general_page_test.dart`, функция `openGeneral`), здесь она сокращена:

```dart
Future<CodeLabTestBinding> openGeneral(
  WidgetTester tester, {
  StartupPreferences? startupPreferences,
}) async {
  final binding = CodeLabTestBinding(
    project: '/workspace',
    settingsPages: const SettingsPages(
      available: {SettingsPage.connection, SettingsPage.general},
    ),
    startupPreferences: startupPreferences, // двойник порта вместо shared_preferences
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
```

- `CodeLabApp(startOnLaunch: false)` не запускает агента после первого кадра: тест решает сам, нужен ли агент.
- Страница открывается тем же `NavigationCubit`, что и у пользователя; прямого вызова построителя нет.
- Cubit-ы и порты, которые нужно проверить, достаются из `binding.scope.resolve<…>()`; двойники порта — тот, который тест передал швом (`startupPreferences`).
- Если страницу рисует Cubit-двойник (`FakeAgentsModesCubit`), он кладётся в дерево через `BlocProvider.value`, а настоящая логика Cubit-а проверяется отдельным тестом в `application/`.

### Что проверять в тесте страницы

- Что страница **показывает** из состояния и какой метод Cubit-а **вызывает** по жесту. Логику разбора, записи и проверок проверяет тест Cubit-а, а не тест страницы.
- Ключи и состояния ошибок: баннеры, предупреждения «Retry», пустые состояния.
- Что в видимом тексте нет секретов и путей (`test/support/no_text_leak.dart` ищет значение именно в видимом тексте, а не в контроллере скрытого поля).
- Не проверять пиксели без необходимости ([testing.md](../../../docs/architecture/testing.md), раздел «Не тестировать пиксели без необходимости»).

### Язык в тестах страниц

Локаль по умолчанию — `en`. Смену языка проверяют так: открыть экран на одном языке, выбрать другой через `AppLanguageCubit`, дождаться `pumpAndSettle` и вызвать `await expectNoStaleLanguage(tester, from: en, to: ru)` из `test/support/l10n_mix.dart`. Помощник собирает видимые строки дерева (`Text`, `RichText`, `placeholder`, `Tooltip.message`, `Semantics.label`) и падает, если среди них осталась строка прежнего языка, у которой есть отличающийся перевод.

Две сквозные проверки идут по всем страницам сразу: `test/l10n/language_switch_sweep_test.dart` (смена `en → ru → en` на рабочем месте и каждой видимой странице) и `test/app/dark_theme_sweep_test.dart` (тёмная и высококонтрастная темы: отсутствие исключений рендера и контраст ролей цвета не ниже 4,5:1). Обе строятся на `defaultSettingsPages`, поэтому новая страница попадает в них автоматически.

## Файловый ввод-вывод в тестах

Правило: внутри `testWidgets` файловый ввод-вывод не используется. Тело `testWidgets` идёт в fake-async зоне: `Future` настоящего файла завершается реальным циклом событий, который зона не прокручивает, и тест зависает.

- `profiles.json`, `recent_projects.json`, `config.yaml` и ресурсы проверяют **обычные `test`** на временном каталоге (`app_scope_profiles_test.dart`, `connection_settings_cubit_test.dart`, `modes_fixture.dart`). `createCodeLabRootScope(environment: {'CODELAB_HOME': …})` даёт настоящий открыватель на изолированной папке.
- В `testWidgets` вместо файла — двойник в памяти (`InMemoryProfileStore`, `FakeRecentProjectsStore`, `FakeProjectFiles`).
- Допустимо синхронное чтение без настоящего `Future`: страница «Legal» читает ресурс через порт `LegalPorts.readAsset`, и тест подставляет `(asset) async => File(asset).readAsStringSync()` вместо `rootBundle`, потому что чтение ресурса из `rootBundle` в fake-async зоне не завершается.
- Закрытие root scope в teardown делает `closeCodeLabRootScopeInTest`: по очереди прокручивает реальный цикл событий (`binding.runAsync`) и очередь fake-async (`binding.idle()`), пока scope не закроется. Простое `await closeCodeLabRootScope()` в teardown зависает, потому что файловые выходы журнала завершаются в настоящем времени.

## Тесты-сторожа внутри app

Часть тестов app — это не проверка функций, а сторож: он падает, когда разошлись два места, которые должны совпадать. Такой тест читает файлы, поэтому идёт обычным `test`.

| Тест | Что сверяет | Когда падает |
|---|---|---|
| `test/app/shortcut_catalog_guard_test.dart` | в `lib/**.dart` (кроме сгенерированного `lib/l10n/app_localizations*.dart`) нет `SingleActivator(`, `CharacterActivator(`, `LogicalKeySet(` и сравнений с `LogicalKeyboardKey.` | кто-то привязал клавишу литералом вместо записи каталога `CodeLabShortcut` |
| `test/features/settings/presentation/keyboard_bindings_test.dart` | каждая запись каталога, привязка которой живёт в app, проверена нажатием | новая запись без сценария нажатия |
| `test/app/legal_assets_test.dart` | `assets/legal/` побайтно равен корневым `LICENSE`, `THIRD_PARTY_NOTICES.md`, `PRIVACY*.md`, `TERMS*.md`, и каждый файл объявлен в `pubspec.yaml` | корневой файл поправили, а копию в app нет; сообщение называет разошедшийся файл |
| `test/app/build_version_test.dart` | константа `codelabDesktopVersion` (`lib/app/build_version.dart`) равна `version` из `pubspec.yaml`; адрес заметок выпуска не расходится с адресом репозитория сайта | версию подняли в одном месте |
| `test/l10n/l10n_catalogs_test.dart` | каталоги `app_en.arb` и `app_ru.arb`: не пусты, наборы ключей равны, плейсхолдеры совпадают, у `plural` в `ru` есть формы `one`, `few`, `many`, `other` | ключ добавлен в один каталог или форма plural пропущена |
| `test/l10n/cubit_text_list_test.dart` | Cubit-ы в `application/`, которые зависят от `AppStrings`, равны эталонному списку, и каждый (кроме фасада) подписан на смену языка | Cubit начал хранить текст, а его не добавили в список и не подписали |
| `test/tool/l10n_check_test.dart` | корневой скрипт `tool/l10n_check.dart` на временной копии пакета ловит устаревший сгенерированный код | медленный: запускает `flutter gen-l10n` |
| `test/app/root_scope_close_test.dart`, `app_exit_wiring_test.dart`, `root_lifecycle_shutdown_test.dart` | закрытие scope и обработчик выхода: сбой `Disposable` пишется событием `app.shutdown_step_failed`, а не уходит необработанным в зону | изменилось закрытие scope или шаги выхода |

Сторож всего репозитория (`melos run guard`, пакет [`codelab_architecture_tests`](../../../packages/dart/codelab_architecture_tests/README.md)) добавляет правила для app: запрет `package:codelab_agent_*` (правило `apps/codelab_desktop`), запрет `dart:io` в `lib/features/onboarding`, `package:flutter/` в `lib/features/terminal/application/`, `package:flutter/` и `dart:io` в `lib/features/usage/application/` и `lib/features/protocol/application/`, запрет `package:desktop_drop/` вне `lib/core/platform/os_drop_region.dart`, `ui_literals_test` (литералы интерфейса в `lib/` без ARB) и другие. Правила лежат в `packages/dart/codelab_architecture_tests/test/support/rules.dart`; нарушение называет файл и строку.

## Интеграционные тесты: как устроены

Интеграционные тесты проверяют настоящее приложение macOS целиком. **Их запускают только в ветке `release/<version>`** как приёмку выпуска (корневой [`AGENTS.md`](../../../AGENTS.md), §21). В ветках `feature/*` и `hotfix/*` для `integration_test/` достаточно `fvm flutter analyze`; эта глава описывает устройство и не предлагает запускать их.

### Каталог

| Путь | Что там |
|---|---|
| `integration_test/*_flow_test.dart` | сценарии: подключение stdio, одобрения, `fs/*`, `terminal/*`, открытие проекта, очередь промптов, несколько сессий, палитра команд, ленты, язык, приветственные шаги, оформление, «Legal», «Usage», страницы настроек |
| `integration_test/flutter_test_config.dart` | общая настройка для каждого теста: язык `en`, размер окна 1440×900, закрытие root scope |
| `integration_test/support/e2e_agent.dart` | `E2eAgent`: какой агент стоит за тестами, как его запускать и как подключаться |
| `integration_test/llm_scripts/*.json` | сценарии модели для Dart-агента и встроенного агента |
| `dart_test.yaml` | тег `scripted-only` |

### Какой агент за тестом

`E2eAgent.current` выбирается `--dart-define=CODELAB_E2E_AGENT=scripted|dart|embedded` (по умолчанию `scripted`). Код `lib/` при этом не меняется, меняется только профиль подключения:

| Значение | Агент | Скрипт |
|---|---|---|
| `scripted` | скриптовый stdio-агент из `codelab_acp_testing` (`writeCodelabCompatibleStdioAgent`, режимы `CodelabCompatibleStdioAgentMode`) | `test:e2e:app:*` по одному сценарию |
| `dart` | бинарь `codelab-agent` (`--dart-define=CODELAB_E2E_AGENT_BIN=…`) со сценарием модели | `test:e2e:app:dart-agent` (собирает агента скриптом `build:agent`) |
| `embedded` | встроенный агент в процессе app: `scriptedEmbeddedAgentOpener` из `package:codelab_embedded/testing.dart` | `test:e2e:app:embedded` |

Импорт `package:codelab_embedded/testing.dart` разрешён сторожем только тестам; в `lib/` приложения его нет, поэтому сценарий модели не попадает в релизную сборку.

Тест вызывает `E2eAgent.current.launch(tempDir, mode: …)`: он создаёт временный `CODELAB_HOME`, пишет в него `profiles.json` с профилем агента и возвращает `E2eLaunch`; `launch.connect(tester, shellCubit)` выбирает профиль на странице «Connection» и запускает агента. Тесты, которые проверяют поведение именно скриптового агента, помечены `tags: scriptedOnly` (константа из `e2e_agent.dart`) и в режимах `dart` и `embedded` исключаются через `--exclude-tags scripted-only`. Тесты `fs/*` и `terminal/*` во встроенном режиме пропускаются: встроенный агент исполняет файлы и команды локально, а не через ACP-методы клиента.

### Сценарии модели

`integration_test/llm_scripts/<режим>.json` задают ответ модели по шагам. Минимальный сценарий — `normal.json`:

```json
{
  "llm": {
    "model": { "provider": "scripted", "modelId": "scripted-1", "contextWindow": 32768 },
    "steps": [
      { "reply": [ { "text": "hello from compatible stdio agent" } ], "stopReason": "stop" }
    ]
  }
}
```

Имя файла совпадает с режимом скриптового агента (`mode.wireName`), поэтому один и тот же тест идёт против любого из трёх агентов и видит одинаковый ответ. Файл — единственное место, где для встроенного и Dart-агента задан «ответ модели»; ответ модели в тестах живого провайдера не запрашивается.

### Что настраивает `integration_test/flutter_test_config.dart`

- перед каждым тестом (`setUp`) подменяет `SharedPreferences` хранилищем в памяти с `codelab.app.language = en`: приёмка не зависит от языка машины;
- меняет размер настоящего окна на 1440×900 через канал `codelab/e2e_window` (только debug-сборка): окно по умолчанию 800×600 попадало бы в узкий класс, где сайдбар и док выдвигаются поверх ленты;
- после каждого теста закрывает root scope (`closeCodeLabRootScope()`): иначе тест, упавший до собственного закрытия, оставил бы статический корень Cherrypick, и следующий тест файла падал бы вторичной ошибкой «Can't resolve dependency `CodeLabRootLifecycle`».

### Один файл на запуск

На macOS `flutter test integration_test -d macos` не поднимает приложение после первого файла, поэтому скрипты `test:e2e:app:dart-agent` и `test:e2e:app:embedded` запускают файлы по одному и возвращают ненулевой итог, если упал хотя бы один. Код 79 («No tests ran») — файл целиком из `scripted-only`: это пропуск, а не падение. Список скриптов и что проверяет каждый — в [development.md](development.md#тесты).

## `test_driver/`

`test_driver/app.dart` — не набор тестов, а точка входа для управления запущенным приложением: включает расширение `flutter_driver` и вызывает обычный `main`.

```dart
void main() {
  enableFlutterDriverExtension();
  app.main();
}
```

Запуск (`fvm flutter run -d macos -t test_driver/app.dart --print-dtd`), стабильные ключи вроде `app-bar-menu`, `sidebar-settings`, `settings-nav-providers` и изолированный прогон с временным `CODELAB_HOME` описаны в [development.md](development.md#управление-запущенным-приложением). Именно для этого ключи `ValueKey` считаются контрактом: их используют и виджет-тесты, и интеграционные, и ручное управление.

## Реальный прогон

Вывод двух файлов: сторож клавиш и тест Cubit-а из примера. Получен командой ниже в рабочем каталоге этой ветки (`fvm flutter test -r expanded`); сообщения менеджера пакетов вырезаны, абсолютные пути убраны, остальное — как напечатано. Репортёр `expanded` печатает строку при старте теста, поэтому номер `+N` — число уже завершённых тестов.

```bash
cd apps/codelab_desktop
fvm flutter test -r expanded \
  test/app/shortcut_catalog_guard_test.dart \
  test/features/settings/application/startup_settings_cubit_test.dart
```

```text
00:00 +0: loading test/app/shortcut_catalog_guard_test.dart
00:00 +0: test/app/shortcut_catalog_guard_test.dart: (setUpAll)
00:00 +0: test/app/shortcut_catalog_guard_test.dart: сторож различает литералы активаторов и комментарии
00:00 +1: test/app/shortcut_catalog_guard_test.dart: вне каталога кита нет литералов активаторов и сравнений клавиш
00:00 +2: test/app/shortcut_catalog_guard_test.dart: (tearDownAll)
00:00 +2: test/features/settings/application/startup_settings_cubit_test.dart: (setUpAll)
00:00 +2: test/features/settings/application/startup_settings_cubit_test.dart: до чтения значение по умолчанию — включено, без сбоя
00:00 +3: test/features/settings/application/startup_settings_cubit_test.dart: load читает выключенное значение
00:00 +4: test/features/settings/application/startup_settings_cubit_test.dart: load нечитаемое значение — включено, ничего не записывается
00:00 +5: test/features/settings/application/startup_settings_cubit_test.dart: select выключение: запись false, значение в состоянии, событие без путей
00:00 +6: test/features/settings/application/startup_settings_cubit_test.dart: select включение: запись true
00:00 +7: test/features/settings/application/startup_settings_cubit_test.dart: сбой записи (D9) переключатель остаётся в выбранном положении, saveFailed, событие с именем типа без текста
00:00 +8: test/features/settings/application/startup_settings_cubit_test.dart: сбой записи (D9) Retry повторяет запись выбранного значения; успех снимает сбой
00:00 +9: test/features/settings/application/startup_settings_cubit_test.dart: сбой записи (D9) Retry без сбоя ничего не пишет
00:00 +10: test/features/settings/application/startup_settings_cubit_test.dart: сбой записи (D9) новый выбор после сбоя снимает предупреждение при успехе
00:00 +11: test/features/settings/application/startup_settings_cubit_test.dart: запись после close() не меняет состояние и не бросает
00:00 +12: test/features/settings/application/startup_settings_cubit_test.dart: (tearDownAll)
00:00 +12: All tests passed!
```

Те же команды дали `All tests passed!` для `test/features/settings/presentation/keyboard_page_test.dart` (25 тестов) и для `test/app/legal_assets_test.dart`, `test/app/build_version_test.dart`, `test/l10n/l10n_catalogs_test.dart`, `test/l10n/cubit_text_list_test.dart` вместе (28 тестов).

## Какие проверки затрагивает изменение

Перед pull request из `feature/*` и `hotfix/*` агент проверяет только затронутое ([development.md](development.md#тесты), корневой [`AGENTS.md`](../../../AGENTS.md), §21):

| Что изменилось | Что запустить |
|---|---|
| любой Dart-файл app | `fvm dart format --set-exit-if-changed <файлы>`, `fvm flutter analyze` и `fvm flutter test` в `apps/codelab_desktop` (можно сузить до файлов теста) |
| виджеты `codelab_ui` | то же в `packages/flutter/codelab_ui`; тесты app, которые используют изменённые виджеты |
| `pubspec.yaml`, импорты между пакетами, правила сторожа | `fvm dart run melos run guard` |
| `.arb`, `l10n.yaml`, сгенерированный код локализации | `fvm flutter gen-l10n` в `apps/codelab_desktop`, затем `fvm dart run melos run l10n:check` |
| `integration_test/` | `fvm flutter analyze`; прогон `test:e2e:app:*` только в `release/<version>` |
| клиентский слой (`codelab_client_core`, `codelab_client_io`), через который работает и CLI | кроме тестов app — скрипты CLI из [AGENTS.md](../../../AGENTS.md) §21 (`test:e2e:cli:dart-agent`, `test:e2e:cli:embedded`) |
| документация app | `cd site && npm ci && npm run verify`, если установлен Node |

Полный `melos run check` перед pull request запускают только по просьбе пользователя; в `release/*` — обязательно вместе с `test:e2e:app:*`.

## Частые проблемы

| Симптом | Причина | Что сделать |
|---|---|---|
| тест с `testWidgets` зависает, ничего не печатает | внутри fake-async зоны идёт файловый ввод-вывод (`profiles.json`, `config.yaml`, чтение файла) | заменить хранилище двойником в памяти или перенести проверку в обычный `test` на временной каталоге |
| после теста: «Can't resolve dependency `CodeLabRootLifecycle`» или странные падения следующих тестов файла | прошлый тест упал до закрытия root scope, статический корень Cherrypick остался | использовать `CodeLabTestBinding` (он закрывает scope в `addTearDown`); в собственных графах — `closeCodeLabRootScopeInTest` |
| «Тест изменил настоящий …/recent_projects.json» | `createCodeLabRootScope` вызван без швов `recentProjectsStore:` и `environment:` | передать `FakeRecentProjectsStore()` или временный `CODELAB_HOME`; если файл менял параллельный процесс, повторить прогон |
| `MissingPluginException` для `shared_preferences` | нет мока канала | `SharedPreferences.setMockInitialValues({…})` в `setUp` (в `CodeLabTestBinding` уже есть) |
| `AppLocalizations.of` падает, «No `AppLocalizations`» | тест собрал `FluentApp` без делегатов | обернуть в `localizedFluentApp(child)` или использовать `l10nTestDelegates` |
| тест Cubit-а с таймером идёт по настоящему времени | Cubit создан в `setUp`, а не в теле `testWidgets` | создать в теле `testWidgets` и двигать время `tester.pump(Duration)` |
| `l10n_catalogs_test`: «наборы ключей en и ru равны» | ключ добавлен в один каталог | добавить в оба, затем `fvm flutter gen-l10n` |
| `l10n:check` падает, хотя ARB верны | сгенерированный `lib/l10n/app_localizations*.dart` не обновлён | `fvm flutter gen-l10n` и закоммитить результат |
| сборка и тесты падают на отсутствии `*.freezed.dart` | сгенерированный код не создан | шаг генерации из [запуска из исходников](../../../docs/user/run-from-source.md#1-подготовка) |
| `shortcut_catalog_guard_test` называет файл и строку | в `lib/` появился литерал `SingleActivator` или сравнение с `LogicalKeyboardKey.` | взять активатор из записи `CodeLabShortcut` ([09-extending.md](09-extending.md)) |
| `legal_assets_test` называет файл | копия в `assets/legal/` разошлась с корневым файлом | скопировать корневой файл заново |

## Смотрите также

- [development.md](development.md) — карта кода и краткая таблица тестов.
- [09-extending.md](09-extending.md) — рецепты изменений; у каждого есть тест и проверки.
- [`AGENTS.md`](../AGENTS.md) приложения — раздел «Тесты» и ключи тестов отдельных страниц.
- [testing.md](../../../docs/architecture/testing.md) — общая стратегия, разделы про Cubit (§26), виджеты (§28), Fluent UI и язык (§30, §30а), интеграционные тесты (§32).
- [state-management.md](../../../docs/architecture/state-management.md), [concurrency.md](../../../docs/architecture/concurrency.md) — правила для Cubit-ов и поздних результатов.
- [Пакет `codelab_ui`](../../../packages/flutter/codelab_ui/README.md) — тесты виджетов кита.
