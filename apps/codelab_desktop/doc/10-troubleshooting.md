# Частые проблемы разработчика приложения

Глава собирает случаи, с которыми сталкивается тот, кто меняет код `apps/codelab_desktop`. Каждый случай записан одинаково: симптом, причина, что сделать. Тексты ошибок и имена событий журнала взяты из кода; рядом указан файл, где они появляются. Случаи, которые нельзя было подтвердить по коду или запуском, в главу не вошли.

События журнала приложения читаются в файле `application.log` (релиз) или в консоли процесса (отладка), а также в панели «Protocol», вид «Log»: где что лежит — в [operations.md](operations.md#логи-и-диагностика). Как устроены сборка, встроенный агент и профили — в [07-embedded-agent-and-connections.md](07-embedded-agent-and-connections.md).

Случаи по теме:

- сборка и запуск: [нет сгенерированных файлов freezed](#нет-сгенерированных-файлов-freezed), [устарел код Cherrypick](#устарел-сгенерированный-код-cherrypick), [`flutter run` не видит переменные окружения](#приложение-из-flutter-run-не-видит-переменные-окружения);
- тесты: [виджет-тест зависает](#виджет-тест-зависает-на-файловом-вводе-выводе), [тест изменил список недавних проектов](#тест-изменил-настоящий-список-недавних-проектов);
- локализация и литералы: [код локализации устарел](#сгенерированный-код-локализации-устарел), [ключи en и ru разошлись](#наборы-ключей-en-и-ru-разошлись), [сторож нашёл литерал](#сторож-литералов-интерфейса-нашёл-строку);
- границы: [сторож упал на импорте](#сторож-упал-на-импорте), [сторож сочетаний клавиш](#сторож-сочетаний-клавиш-нашёл-литерал), [страница настроек открывается пустой](#страница-настроек-открывается-пустой);
- встроенный агент: [агент не стартует](#встроенный-агент-не-стартует), [баннер про провайдера или конфиг](#баннер-сообщает-о-проблеме-конфигурации-агента), [выход занимает много времени](#выход-из-приложения-занимает-много-времени);
- профили и секреты: [профиль по умолчанию сбросился](#профиль-по-умолчанию-сбросился-или-не-найден), [токен профиля не отправляется](#токен-профиля-не-отправляется), [страница Connection не даёт править профили](#страница-connection-не-даёт-править-профили).

## Нет сгенерированных файлов freezed

**Симптом.** `fvm flutter test` и `fvm flutter analyze` падают сразу: `Target of URI doesn't exist: '…/connection_profile.freezed.dart'` (проверено на отдельном файле с `part 'x.freezed.dart';`). Приложение не собирается.

**Причина.** Файлы `*.freezed.dart` не хранятся в git. В свежем клоне и в новом worktree их нет, а модели `codelab_client_core` и других пакетов на них ссылаются через `part`.

**Что сделать.** Сгенерируйте код из корня репозитория, как описано в [запуске из исходников](../../../docs/user/run-from-source.md#1-подготовка):

```bash
fvm dart run melos exec -c 1 --depends-on=build_runner -- "fvm dart run build_runner build --delete-conflicting-outputs"
```

После смены ветки с правкой аннотированных моделей повторите команду. Новому worktree генерация нужна всегда: файлов в нём нет.

## Устарел сгенерированный код Cherrypick

**Симптом.** Анализатор ругается на `lib/app/app_scope.module.cherrypick.g.dart`: аргументы вызовов методов контракта не совпадают с их сигнатурами.

**Причина.** `app_scope.dart` объявляет контракты модулей аннотацией `@module()` (`CodeLabTransportsModuleContract`, `CodeLabProtocolApplicationModuleContract`, `CodeLabRootLifecycleModuleContract`). Файл `app_scope.module.cherrypick.g.dart` — это `part of 'app_scope.dart'`; его создаёт генератор, и **он лежит в git**, в отличие от `*.freezed.dart`. Список аргументов `currentScope.resolve<…>()` в нём повторяет параметры методов контракта. Добавили параметр методу `rootLifecycle(...)` или новую зависимость в `application(...)` — файл надо пересоздать.

**Что сделать.** В `apps/codelab_desktop`:

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

Закоммитьте изменённый `app_scope.module.cherrypick.g.dart` вместе с правкой контракта. Сами модули (`CodeLabEmbeddedAgentModule`, `CodeLabConnectionModule` и другие) ручные и генерации не требуют, как и швы `createCodeLabRootScope(...)`.

## Приложение из flutter run не видит переменные окружения

**Симптом.** Вы задали `CODELAB_HOME=/tmp/test` и запустили `fvm flutter run -d macos`, но приложение показывает профили и конфигурацию из настоящего `~/.codelab`; ключи из `CODELAB_SECRET_*` тоже не находятся.

**Причина.** `flutter run` не передаёт запущенному приложению переменные окружения терминала. Приложение читает `Platform.environment` процесса (`main.dart`, `CodeLabEmbeddedAgentModule` в `app_scope.dart`), а в нём только окружение macOS по умолчанию. То же у приложения, запущенного из Finder или Dock ([operations.md](operations.md#запуск)).

**Что сделать.** Соберите приложение и запустите исполняемый файл из терминала с нужными переменными — рецепт в [development.md](development.md#изолированный-ручной-прогон):

```bash
CODELAB_HOME=<временная папка> \
  build/macos/Build/Products/Debug/codelab_app.app/Contents/MacOS/codelab_app
```

Путь — от `apps/codelab_desktop`. Для тестов окружение подставляется швом `createCodeLabRootScope(environment:)`: так тест не зависит от вашего окружения.

## Виджет-тест зависает на файловом вводе-выводе

**Симптом.** Тест с `testWidgets` не завершается и падает по таймауту теста (у `testWidgets` по умолчанию 10 минут: `defaultTestTimeout` у `AutomatedTestWidgetsFlutterBinding`); в логе нет ни ошибки, ни исключения.

**Причина.** Внутри `testWidgets` код работает в зоне `fake_async`. Настоящие операции с файлами и процессами в ней не получают реального времени и не завершаются. Типичный источник — настоящий `profiles.json`, `recent_projects.json`, `config.yaml` или `ClientSecretAccess` в scope, собранном без швов.

**Что сделать.** Подставьте двойники швами `createCodeLabRootScope(...)` или `CodeLabTestBinding(...)`:

| Что | Шов и двойник |
|---|---|
| профили | `profileStore:`, `InMemoryProfileStore` (`test/support/in_memory_profile_store.dart`) |
| недавние проекты | `recentProjectsStore:`, `FakeRecentProjectsStore` |
| хранилище секретов | `profileSecrets:`, `FakeProfileSecrets` |
| сессия настроек агента | `providerSettingsOpener:` |
| признак «нужен провайдер» | `providerSetupProbe:` |
| встроенный агент | `embeddedOpener:` — открыватель из `codelab_embedded/testing.dart` только в тестах |
| панель Files, терминал | `projectFiles:`, `userShellLauncher:` и двойники `FakeProjectFiles`, `FakeUserShellLauncher` |

Файлы `profiles.json` и конфигурации проверяйте обычными `test` (не `testWidgets`) на временном каталоге. Обзор тестов — [08-testing.md](08-testing.md), правила — раздел «Тесты» в [`AGENTS.md`](../AGENTS.md).

## Тест изменил настоящий список недавних проектов

**Симптом.** Тестовый файл заканчивается ошибкой в `tearDownAll`: `Тест изменил настоящий <путь>/recent_projects.json: передайте шов recentProjectsStore: или временный environment: {'CODELAB_HOME': …} в createCodeLabRootScope.` (`test/flutter_test_config.dart`).

**Причина.** `createCodeLabRootScope` без швов `environment:` и `recentProjectsStore:` берёт настоящее окружение и пишет проекты теста в `~/.codelab/recent_projects.json`, общий с `codelab`. Из-за этого в списке разработчика появлялись временные папки `codelab_app_embedded_*`. Страж запоминает содержимое файла до тестового файла и сверяет после.

**Что сделать.** Передайте `recentProjectsStore: FakeRecentProjectsStore()` или временный `environment: {'CODELAB_HOME': …}`. Если файл мог изменить другой процесс (запущенный `codelab`, параллельный файл тестов с `-j`), повторите прогон: страж в этом случае срабатывает ложно.

## Сгенерированный код локализации устарел

**Симптом.** `fvm dart run melos run l10n:check` красный. В выводе: `l10n_check: устарел …/lib/l10n/app_localizations_ru.dart`, под ним первая различающаяся строка («в рабочем файле» и «после генерации»), в конце `l10n_check: сгенерированный код устарел; выполните fvm flutter gen-l10n в пакете.` Либо `l10n_check: нет файла …`, `l10n_check: лишний файл …`.

**Причина.** Файлы `lib/l10n/app_localizations*.dart` коммитятся. Корневой скрипт `tool/l10n_check.dart` перегенерирует их во временной копии и сравнивает с рабочими. Вы изменили `.arb`, но не перегенерировали код, или правили сгенерированный файл вручную.

**Что сделать.** В `apps/codelab_desktop`:

```bash
fvm flutter gen-l10n
```

Закоммитьте результат. Для каталога кита то же делают в `packages/flutter/codelab_ui` (его каталог — `lib/src/l10n/`). Порядок добавления строки — в [development.md](development.md#как-добавить-строку-интерфейса).

## Наборы ключей en и ru разошлись

**Симптом.** `fvm flutter test test/l10n/l10n_catalogs_test.dart` падает: `ключи есть в en, но нет в ru`, `ключи есть в ru, но нет в en`, `плейсхолдеры различаются` или `неполные формы plural в ru`.

**Причина.** Новый ключ добавлен в один из каталогов `lib/l10n/app_en.arb` и `app_ru.arb`, у сообщения разные плейсхолдеры, или у `plural` в русском каталоге нет всех форм (`one`, `few`, `many`, `other`).

**Что сделать.** Добавьте ключ в оба каталога с одинаковыми плейсхолдерами; количество — одним сообщением ICU `plural`. Русский текст берите по [глоссарию](../../../docs/architecture/l10n-glossary.md). После правки выполните `fvm flutter gen-l10n`.

## Сторож литералов интерфейса нашёл строку

**Симптом.** Тест `ui_literals_test` пакета `codelab_architecture_tests` падает: `N литералов вне каталога ARB. Вынесите их в ARB (context.l10n) или добавьте в ui_literals_allowlist.txt с причиной:` и список строк `apps/codelab_desktop/lib/…/x.dart:12 -> 'Текст'`.

**Причина.** В `presentation/` или в `lib/app/` появилась строка (сторож сканирует `apps/codelab_desktop/lib/app` и `lib/features`), которая выглядит как текст интерфейса и не лежит в каталоге ARB.

**Что сделать.**

- Если это язык интерфейса — вынесите строку в `app_en.arb` и `app_ru.arb` и возьмите её через `context.l10n`.
- Если английский литерал должен остаться (название продукта, значение конфигурации, пример поля), добавьте запись в `packages/dart/codelab_architecture_tests/test/support/ui_literals_allowlist.txt` в формате `путь | литерал | причина`. Причина обязательна.
- Обратная сторона: запись allowlist, которой в коде больше нет, тоже роняет тест (`в коде записей нет:`). Удалите мёртвую запись.

Запуск: `fvm dart test test/ui_literals_test.dart` в `packages/dart/codelab_architecture_tests`.

## Сторож упал на импорте

**Симптом.** `fvm dart run melos run guard` красный. Причина — строка вида `<файл>:<строка> -> <импорт>` от корня репозитория, например `apps/codelab_desktop/lib/features/settings/presentation/x.dart:3 -> package:codelab_setup/io.dart`. Название теста — `apps/codelab_desktop/lib: no forbidden imports in lib/`. Либо `not in allowlist: <пакет>` для зависимости в `pubspec.yaml`.

**Причина.** Файл `lib/` приложения импортирует то, что запрещает `packages/dart/codelab_architecture_tests/test/support/rules.dart`. Для приложения запрещено:

| Импорт | Где разрешён | Что делать вместо |
|---|---|---|
| `package:codelab_agent_*` | нигде | идти через мосты `codelab_setup` и `codelab_embedded` |
| `package:codelab_embedded/io.dart` | только `lib/app/` | получить агента через `EmbeddedTransportResolver`, не импортируя барель |
| `package:codelab_embedded/testing.dart` | нигде в `lib/`, в том числе в `lib/app/` | сценарий модели передаёт тест швом `createCodeLabRootScope(embeddedOpener:)` |
| `package:codelab_setup/io.dart` | только `lib/app/`; в `features/settings/presentation/` запрещён особо | завести порт в `application/`, реализацию собрать в `lib/app/` |
| `dart:io` | не в `features/onboarding`, `features/project_files`, `features/usage/application`, `features/protocol/application`, `features/settings/presentation` | порт `ProjectFiles`, `UsageCsvSaver`, `LogRecordSource` и другие |
| `package:file_selector/`, `package:url_launcher/` | только `lib/core/platform/` | порты `ProjectFolderPicker`, `ThemeFilePicker`, `ExternalLinkOpener`, `LocalFolderOpener` |
| `package:desktop_drop/` | только `lib/core/platform/os_drop_region.dart` | `OsDropRegion` |
| `package:system_theme/` | только `lib/core/platform/system_accent_source.dart` | порт `SystemAccentSource` |
| `package:pty2/` | только `lib/core/platform/user_shell_launcher.dart` | порт `UserShellLauncher` |
| `dart:ffi` | только `lib/core/platform/build_info.dart` | `BuildInfo` |

Полный набор правил — в файле `rules.dart`: там и обоснование каждого. `package:desktop_drop/` запрещён и в `packages/flutter/codelab_ui`.

**Что сделать.** Не отключайте правило. Перенесите код, которому нужен запрещённый импорт, в `lib/app/` или `lib/core/platform/` и дайте остальному коду порт. Новая зависимость в `pubspec.yaml` — решение OpenSpec change: расширять allowlist без него нельзя. Обратите внимание на запечатанные исключения: правило с `sealExclude` падает ещё и на импорт исключённого файла (`(excluded file)` в строке).

## Сторож сочетаний клавиш нашёл литерал

**Симптом.** `fvm flutter test test/app/shortcut_catalog_guard_test.dart` падает: `Привязки клавиш берут активаторы из CodeLabShortcut (кит):` и список `lib/…/x.dart:42: <строка>`.

**Причина.** В `lib/` (кроме сгенерированного `lib/l10n/app_localizations*.dart`) появился `SingleActivator(`, `CharacterActivator(`, `LogicalKeySet(`, сравнение с `LogicalKeyboardKey.`, чтение `event.logicalKey` или `event.physicalKey`, `switch` по клавише или `isLogicalKeyPressed(`. Единственный источник активаторов — каталог `CodeLabShortcut` в `packages/flutter/codelab_ui`.

**Что сделать.** Добавьте запись в каталог кита и возьмите активатор из него. Что ещё менять в одном изменении (тексты ARB, ветки исчерпывающих `switch` страницы «Keyboard», сценарий нажатия) — [development.md](development.md#как-добавить-сочетание-клавиш). Строки-комментарии сторож не считает.

## Страница настроек открывается пустой

**Симптом.** Пункт страницы есть в навигации настроек, но справа пусто. Тест `every page of the production available set has a body builder` (`test/features/settings/presentation/settings_shell_test.dart`) падает на проверке `containsAll`.

**Причина.** Страница включена в `defaultSettingsPages` (`lib/app/default_settings_pages.dart`), но у неё нет построителя в `settingsPageBuilders` (`lib/features/settings/presentation/settings_shell.dart`). Оболочка берёт `builders[selected]` и при `null` ничего не рисует.

**Что сделать.** Зарегистрируйте построитель: `SettingsPage.<значение>: <функция построителя страницы>` в таблице `settingsPageBuilders`. Таблица неизменяема (`Map.unmodifiable`): менять её в рантайме нельзя, тесты передают свою через параметр `builders` оболочки. Полный порядок добавления страницы — [development.md](development.md#как-добавить-страницу-настроек); без заголовка в `settingsPageTitleOf` код не скомпилируется: `switch` исчерпывающий.

## Встроенный агент не стартует

**Симптом.** Приложение открыто, но агент не запускается: бейдж `No project · agent not started` (`workbenchBadgeNoProject`), на экране «Open a project» нет сессий. Если проекта нет или идут приветственные шаги, в журнале нет события `connection.start_on_launch`: оно пишется, только когда проект восстановлен и вызов дошёл до `startAgent` (проверка существования папки идёт позже).

**Причина.** Агент стартует только по триггеру и только при проекте:

- проекта нет: запуск без сохранённого проекта, или выключен переключатель «Reopen the last project and its tabs» (в журнале `app.reopen_last_project_skipped`). `ConnectionCubit.startOnLaunch` в этом случае возвращается молча;
- идут приветственные шаги: пока показан onboarding, `startOnLaunch` не вызывается. Папка, выбранная на последнем шаге, ставится на удержание (`project.start_held`, debug) и запускает агента после завершения шагов;
- папка проекта исчезла: попытка отклоняется до открытия агента, пишется диагностика `project` с причиной, баннер показывает, что папки нет;
- резолвер получил пустую папку и вернул `Open a project to start the embedded agent.`

**Что сделать.** Откройте папку («Open folder…», Cmd+O, перетаскиванием на экран) — это один из триггеров старта. Проверьте в журнале `app.reopen_last_project_skipped`, `project.start_held`, `connection.start_on_launch`. Если проект есть, а агент не стартует, ищите `connection.start_failed` и записи диагностики `Failed to start embedded ACP agent: …`. Как устроен путь старта — в [07-embedded-agent-and-connections.md](07-embedded-agent-and-connections.md#старт-сессии-со-встроенным-агентом).

## Баннер сообщает о проблеме конфигурации агента

**Симптом.** Вместо рабочего места баннер соединения. Вариант 1: текст `No model provider is configured for the embedded agent.` с кнопкой «Add provider». Вариант 2: список строк вида `<файл>: <ключ>: <сообщение>` и последняя строка `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`.

**Причина.** Открыватель `localEmbeddedAgentOpener` не смог собрать агента и бросил `EmbeddedAgentConfigException`; резолвер превратил её в `ClientWorkspaceException`. Если проверка моста `providerSetupNeeded` по снимку конфига сказала, что нужен провайдер, — вариант 1 (`ProviderSetupOffer`), иначе показывается сырой текст проблем (вариант 2). Если сам снимок прочитать не удалось, резолвер считает, что провайдер не нужен, и показывает вариант 2.

**Что сделать.** Вариант 1: нажмите «Add provider» и пройдите мастер; после записи приложение подключит встроенного агента само (событие `provider_wizard.reconnect`; `provider_wizard.reconnect_skipped` — если за это время началась другая попытка). Вариант 2: исправьте указанные строки `config.yaml` и проверьте файл командой `codelab config check`. Когда ключа провайдера нет, а остальной конфиг верный, соединение открывается, а первый ход завершается заметкой о сбое хода с кнопкой повтора (требование спецификации agent-workbench-ui «Failed turn notice with Retry»).

## Выход из приложения занимает много времени

**Симптом.** После Cmd+Q окно закрывается не сразу. В журнале `app.exit_requested`, затем `app.exit_timeout` с полями `timeout_ms: 5000` и `pending` (имена шагов).

**Причина.** Закрытие идёт параллельно: вкладки терминала, ядро клиента и встроенный агент. Общий предел выхода — 5 с (`AppExitHandler.exitTimeout`): не уложились — приложение отвечает `exit` и пишет `app.exit_timeout`. В `pending` перечислены незавершённые шаги закрытого набора: `terminal`, `cubits`, `workspace`, `embedded`, `migration_offer`, `transport`, `client`, `language`, `appearance` (`CodeLabRootLifecycle._shutdownSteps`). `embedded` в списке значит, что `dispose` агента не успел: он ждёт остановки MCP-процессов, записи журнала сессий или конца хода. Отдельный предел в 10 с (`defaultEmbeddedCloseTimeout`, событие `embedded.close_timeout`, уровень `warning`, без полей) действует при закрытии root scope без запроса на выход; при выходе раньше срабатывают 5 с, поэтому `embedded.close_timeout` в этом случае в журнале не появится.

**Что сделать.** Смотрите `pending`. Для `terminal` — вкладки с зависшей оболочкой: приложение посылает сигнал завершения, а через 3 с принудительно завершает. Для `embedded` — какой MCP-сервер или ход держит агента: события агента в том же журнале (`embedded.agent.failed`, `host.plan`). Для `language` и `appearance` — запись настройки не завершилась (`settings.language_save_timeout`, `appearance.save_timeout`). Событие `app.shutdown_step_failed` с полями `step` и `error_type` значит, что шаг бросил исключение, остальные шаги выполнились. Поведение выхода описано в [operations.md](operations.md#выход-из-приложения). Пределы менять нельзя: это шов тестов, а не настройка.

## Профиль по умолчанию сбросился или не найден

**Симптом.** Вы выбрали профиль `stdio` или WebSocket по умолчанию, а приложение стартует встроенного агента. В журнале `connection_profile.default_reset` (info) или `connection_profile.default_unresolved` (warning, поле `error_type`). На странице «Connection» предупреждение `Profile "default" in profiles.json is ignored: default is the built-in agent. Remove it with codelab profiles remove default.`

**Причина.** `DefaultProfileResolver.resolve` (`lib/features/settings/application/default_profile_resolver.dart`) выбирает профиль по ключу `codelab.connection.default_profile`:

- профиля с таким id нет в читаемом `profiles.json` (его удалили, например, из `codelab`) — ключ сбрасывается, пишется `default_reset`;
- файл не читается или хранилище настроек недоступно — берётся встроенный агент, ключ не трогается, пишется `default_unresolved`;
- профиль с id `default` игнорируется всегда: `default` — второе имя встроенного агента (`reservedProfileIds`), запись от прежней версии остаётся в файле, пока вы её не удалите.

**Что сделать.** Проверьте `$CODELAB_HOME/profiles.json`: профиль есть и файл читаем. Старую запись `default` удалите кнопкой на странице «Connection» или командой `codelab profiles remove default`. Выбор по умолчанию задайте заново на странице «Connection».

## Токен профиля не отправляется

**Симптом.** WebSocket-профиль отвечает отказом: `The agent requires a token (HTTP 401).` или `The agent rejected the token (HTTP 401).` (`workbenchTokenRequired`, `workbenchTokenRejected`). В диагностике `Profile <id> has no stored secret value; connecting without a token.` и событие `connection_profile.token_secret_missing` с `profile_id`. Либо под полем токена: `<NAME> is not set in CodeLab's environment.`

**Причина.** Токен в профиле — только ссылка. Первый текст значит, что токен не ушёл вообще; второй — что ушёл и отвергнут (признак даёт `profileTokenSent`).

- `secret:<имя>`: в хранилище секретов нет значения под этим именем (или хранилище только для чтения). Диагностика и событие пишутся до попытки.
- `env:<NAME>`: переменной нет в окружении процесса приложения. Приложение из Finder не видит переменных оболочки.
- Ссылка не вида `env:` и не `secret:`: подключение идёт без токена, в диагностике `The token-reference format of profile <id> is not supported in this version; connecting without a token.`

**Что сделать.** Запишите секрет `codelab secret set <имя>` или через диалог профиля («Store a new token»; нужен `secrets.backend: file` — иначе хранилище `env` только для чтения и диалог покажет подсказку). Для `env:` запустите приложение из терминала с переменной ([operations.md](operations.md#запуск)). Если вы правили `secrets.backend` в `config.yaml`, перезапуск не нужен: хранилище переоткрывается при каждом открытии диалога и страницы «Connection» (`ReopenableProfileSecrets`).

## Страница Connection не даёт править профили

**Симптом.** «Add profile», «Rename» и «Remove» неактивны, на странице сообщение о причине. Либо при открытии диалога токена пишется, что хранилище секретов недоступно: `Secret store is unavailable: <причина>.`

**Причина.** Два разных сбоя, оба защищают данные:

- недопустимый `CODELAB_HOME` (например, `~user/…` или нет `HOME`): `ConnectionEnvironment.homeProblem` непуст, composition root подставил `UnavailableProfileStore`, а хранилище секретов открылось как `UnavailableProfileSecrets`. Тексты — из `resolveCodelabHome`: `CODELAB_HOME: ~user is not supported, use an absolute path`, `Cannot find the home folder: set CODELAB_HOME or HOME.`;
- `profiles.json` битый или незнакомого формата: приложение не перезаписывает его, а страница показывает ошибку.

**Что сделать.** Задайте абсолютный `CODELAB_HOME` и запустите приложение из терминала с этой переменной. Битый `profiles.json` исправьте или удалите вручную: приложение этого не делает. Событие `secrets.client.backend` в журнале показывает, какой бэкенд открылся (`backend`, `writable`, `reason`).

## Смотрите также

- [07. Встроенный агент и подключения](07-embedded-agent-and-connections.md) — резолверы, профили, секреты, мастер провайдера.
- [development.md](development.md) — карта кода, запуск, тесты, рецепты.
- [operations.md](operations.md) — данные, переменные окружения, логи, выход.
- [`AGENTS.md`](../AGENTS.md) приложения — правила слоёв, границ и тестов, которые проверяют сторожа.
- [Частые проблемы ядра агента](../../../packages/dart/codelab_agent_core/doc/13-troubleshooting.md) — образец формата и случаи на стороне агента.
