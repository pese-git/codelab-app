## Context

Задача пользователя (2026-11-18): локализация desktop-приложения на русский и английский. Это D-19 матрицы паритета (`agent-parity-goals.md`): «строки интерфейса app вынесены в слой локализации; языки — английский и русский, выбор по системе и в настройках; тексты, которые видит модель, и строки ядра остаются английскими (agent-core-architecture §12.2); … его введение отложено отдельным решением (dart-agent-and-clients §12.4.1)». Критерий D-19: «widget-тест: переключение языка меняет строки экрана настроек». Место выбора — «Settings › General» (`12-4-first-run-and-settings.md`, таблица экранов, строка 26).

Источники:
- `AGENTS.md` §2, §4, §5, §6, §8, §13–§16; `apps/codelab_desktop/AGENTS.md`; `packages/flutter/codelab_ui/AGENTS.md` (§1 — зависимости, §2 — нет логики, §5 — фиксированные пары «подпись — тон» внутри кита); `packages/dart/codelab_client_core/AGENTS.md`;
- `docs/architecture/technology-stack.md` §1 (утверждённого решения для i18n нет), `error-handling.md` §39, §43 («Failure → Presentation mapping → localized message»), §98 (low-level пакет не формирует локализованный текст), `layers-and-dependencies.md`, `testing.md`, `observability.md`;
- spec `app-settings` («Навигация настроек»), `acp-client-kit` («Инкрементальная проекция транскрипта»), `agent-workbench-ui`, `workspace-architecture`;
- archived change `add-app-settings-shell` (D2 — навигация и `codelab.settings.last_page`, D3 — набор страниц задаёт composition root, D5 — `ConnectionPreferences` в `shared_preferences`).

Что есть в коде (ветка `feature/add-desktop-localization` от `develop` d600aebd, проверено):
- **Desktop.** `FluentApp(title: 'CodeLab', home: …)` без `localizationsDelegates`, `locale` и `supportedLocales`. `FluentApp` по умолчанию добавляет `FluentLocalizations.delegate` и объявляет 41 язык Fluent, включая `ru`. Литералов интерфейса около 550 уникальных (оценка по `'[A-Z]…'`). Около 250 из них — в `application/`: Cubit-ы настроек (`provider_settings_cubit`, `mcp_settings_cubit`, `agents_modes_cubit`, `add_profile_cubit`, `skills_settings_cubit`), `connection_cubit`, мапперы `workbench/application/ui_mappers.dart` и `settings/application/provider_wizard_view.dart`. Состояние рабочего места (`CodeLabShellState`) хранит готовые модели кита с текстом (`CodeLabTranscriptRow`, `CodeLabSessionListItem`, `CodeLabCommandAction`…), которые строят Cubit-ы через `ui_mappers`. `features/usage/application` и `features/terminal/application` по правилу сторожа без `package:flutter/`; заголовки и подписи блока «Turn budget» собирает `usage_budget.dart`. `SettingsPage`/`SettingsGroup` держат английский заголовок в enum. Страница «General» есть в enum, но не в `defaultSettingsPages`.
- **Кит.** Около 150 литералов: фиксированные словари (статусы вызова, сессии, соединения, риски, тоны, приоритеты плана, вкладки дока `ToolPane`), подписи кнопок («Send», «Cancel», «Copy», «Allow», «Reject»), пустые состояния и значения по умолчанию у параметров (`placeholder = 'Message the agent'`, `emptyLabel = 'No transcript yet'`, `reconnectLabel = 'Reconnect'`). Зависимостей от `flutter_localizations` и `intl` нет.
- **Ядро клиента.** Пользователь видит такие тексты ядра: `NoticeItem.text` (заметки `emptyTurn`, `turnStopped`, `detached`, `reconnected`), `ToolRowView.label` (`Read`, `Edit`…), `ProfileDraftIssue.message` (код `ProfileDraftIssueCode` уже есть), сообщения `ProfileCommitter`, `InspectorProjection`, диагностика `WorkspaceDiagnostic.message`. Форматы usage (`usage_format.dart`) — «без `double`, `intl` и локали».
- **Граф.** `fluent_ui 4.17` уже тянет `intl` и `flutter_localizations` (через `material_ui`); в `pubspec.lock` оба есть как transitive. Flutter 3.47 (`.fvmrc`): synthetic package `flutter_gen` удалён, `gen-l10n` пишет код в каталог проекта.
- **Тесты.** 906 вызовов `find.text(…)` в 53 файлах тестов desktop и кита, все по английским строкам. Локаль тестовой платформы по умолчанию — `en-US`. 45 файлов тестов создают `FluentApp` сами.
- **macOS.** `MainMenu.xib` — английские пункты шаблона Flutter; `CFBundleLocalizations` в `Info.plist` нет.

## Goals / Non-Goals

**Goals:**
- весь интерфейс desktop и кита на `en` и `ru`, с выбором языка «по системе» и явным выбором в «Settings › General»;
- ядро клиента остаётся языконезависимым и общим с CLI, а desktop строит текст по типизированным данным;
- английские тексты спецификаций остаются эталоном `en`, существующие тесты не переписываются;
- регрессия «новый литерал мимо каталога» ловится автоматически.

**Non-Goals:** см. proposal, «Не входит».

## Decisions

### D1. Механизм — `flutter_localizations` и `gen-l10n` с ARB

Решение: стандартная локализация Flutter. Каталоги ARB, классы генерирует `fvm flutter gen-l10n`, сообщения — ICU (`plural`, `select`, плейсхолдеры с типами). `intl` нужен сгенерированному коду для `plural` и `Intl.message`.

Почему: в стеке нет утверждённого решения для i18n (`technology-stack.md` §1), а стандартный механизм не добавляет пакетов в граф: `flutter_localizations` — часть SDK, `intl` уже транзитивен через `fluent_ui`. Fluent сам локализуется тем же механизмом (`FluentLocalizations`, есть `ru`), и делегаты складываются в один список `FluentApp`. Тексты получают проверку типов (метод на сообщение, именованные параметры), а `plural` даёт правильные русские формы.

Альтернативы:
- (б) `easy_localization`, `slang` и подобные — новая технология той же задачи (§4), свой формат и runtime-загрузка; выигрыша для двух языков нет;
- (в) рукописные `Map<String, String>` или `switch` по языку — без `plural`, без проверки плейсхолдеров и без инструментов переводчика.

Строка в `technology-stack.md` §1: «Локализация интерфейса (`codelab_desktop`, `codelab_ui`) — `flutter_localizations`, `gen-l10n` (ARB), `intl` для сгенерированного кода».

### D2. Выбор языка, хранение и применение — сразу (решение пользователя Q1: сразу)

- **Где.** Страница «Settings › General» (`SettingsPage.general`) — первое содержимое этой страницы. Страница входит в `defaultSettingsPages`. Строка «Language» собирается из `CodeLabSettingsRow`/`CodeLabSettingsSection` кита (`ComboBox` или радиогруппа Fluent), значения — `System`, `English`, `Русский`. Названия языков — эндонимы, они не переводятся.
- **Хранение.** `shared_preferences`, ключ `codelab.app.language`, значения `en`/`ru`; для `System` ключа нет. Порт `AppLanguagePreferences` (`load()` → `AppLanguageLoad(preference, storedValueInvalid, readFailure)`, где `preference` — `system | en | ru`; `save(…)`) лежит в `lib/core/platform/app_language_preferences.dart`. `load()` не бросает: повреждённое хранилище не должно мешать запуску app. Незнакомое или нестроковое значение даёт `system` и `storedValueInvalid`, сбой открытия хранилища (`SharedPreferences.getInstance`) — `system` и `readFailure` (имя типа ошибки, без текста исключения). Ошибки `save` порт не скрывает. Реализация `SharedPreferencesAppLanguagePreferences` сделана по образцу `ConnectionPreferences` (`add-app-settings-shell`, D5). `config.yaml` и `profiles.json` не трогаются: это настройка app, а не агента и не CLI.
- **Разрешение языка.** Чистая функция `resolveAppLocale(AppLanguagePreference, List<Locale> systemLocales) → Locale` в `lib/app/language/app_locale.dart`:
  - явный `en`/`ru` — он и есть;
  - `system` — `ru`, если `languageCode` первого языка системы `ru`, иначе `en` (Q5 (а)). Берётся только первый язык списка;
  - незнакомое или нестроковое сохранённое значение — `system`. Ключ не перезаписывается (целостность данных, `AGENTS.md` §2), в журнал пишется предупреждение без значения (D13). Сбой чтения хранилища — тоже `system` с событием `app.language_preference_read_failed` (D13).
- **Единственный владелец языка — `AppLanguageCubit`** (`lib/app/language/app_language_cubit.dart`, root scope, singleton; регистрирует его модуль `CodeLabLanguageModule` в `app_scope.dart` — им же порт `AppStrings`). Состояние — `AppLanguageState(preference, locale, strings: AppLocalizations, saveFailed)`.
  - `main` читает предпочтение и `PlatformDispatcher.instance.locales` до `runApp` и передаёт начальный язык швом `CodeLabBootstrap(language:)`/`createCodeLabRootScope(language:)`. Тип шва — `AppLanguageStart` (`lib/app/language/app_language_start.dart`, фабрика `AppLanguageStart.fromLoad(load, systemLocales)`): `preference` и `locale` плюс диагностика чтения (`storedValueInvalid`, `readFailure`); каталог `AppLocalizations` по нему строит сам Cubit. Без шва — `AppLanguageStart.fallback` (`system`, `en`). Первый кадр поэтому сразу на нужном языке, без мигания английского. Журнал в `main` ещё не настроен, поэтому события о чтении пишет `CodeLabLanguageModule` при сборке root scope (D13).
  - `select(preference)` синхронно применяет язык, то есть делает `emit` нового состояния, и только потом пишет ключ. Записи идут по очереди. При двух быстрых выборах применяется и сохраняется последний: запись, которую обогнал более новый выбор, своё состояние не публикует.
  - Если запись не удалась, язык остаётся применённым до конца сеанса, и выставляется `saveFailed`. Страница показывает `Couldn't save the language. CodeLab will use the previous language after restart.`. В том же InfoBar кнопка `Retry` (ключ `settings-language-save-retry`) повторяет запись текущего выбора — `select(state.preference)`: `RadioGroup` не вызывает `onChanged` для уже выбранного значения. Откатывать язык на глазах у пользователя хуже: экран мигнул бы обратно, а выбор пользователя в этом сеансе ничему не мешает.
  - Повторный `select` того же значения без `saveFailed` новой записи не ставит и завершается вместе с записью, которая ещё идёт.
  - `close()` закрывает Cubit вместе со scope. Сначала ставится флаг закрытия: новые `select` и подписки на `changes` не принимаются. Затем слушатели `changes` закрываются без ожидания `done` (у подписчика на паузе `done` не приходит, и закрытие scope повисло бы). Потом `close()` ждёт запись в полёте не дольше `closeWriteTimeout` (по умолчанию 3 с), чтобы последний выбор дошёл до хранилища до выхода из app. Результат этой записи состояние не публикует (`concurrency.md` §47а).
  - В закрытии root scope Cubit языка закрывает отдельная третья ветвь `CodeLabRootLifecycle`, параллельная веткам терминала и клиента: `_dispose()` → `Future.wait([_closeTerminal(), _closeClient(), _closeLanguage()])`. Почему не в шаге `cubits` клиентской ветки: ожидание записи до 3 с задержало бы рабочее пространство, встроенного агента и транспорт при общем пределе выхода 5 с (`add-client-process-shutdown-on-exit`, D2). По истечении `closeWriteTimeout` пишется `settings.language_save_timeout {timeout_ms}` (D13), и шаг завершается. Шаг называется `language`, он последний в закрытом наборе шагов и попадает в `pendingSteps` и `pending` события `app.exit_timeout`, только если у lifecycle есть Cubit языка (`add-client-process-shutdown-on-exit`, D10). Зависшая запись поэтому видна в журнале выхода как `language`.
- **Кто читает язык.** Потребителей ровно два, и у каждого одна подписка:
  1. `CodeLabApp` — `BlocBuilder<AppLanguageCubit>` над `FluentApp`: `locale: state.locale`. Через `Localizations` (InheritedWidget) новый язык получают все виджеты, которые берут текст через `context.l10n` и `codeLabStringsOf(context)`, и Fluent. Своих подписок у виджетов нет.
  2. Cubit-ы, которые хранят текст в состоянии (D5). Они получают узкий порт `AppStrings` (`AppLocalizations get current`, `Stream<AppLocalizations> get changes`), его реализует `AppLanguageCubit`. Каждый такой Cubit подписывается один раз в конструкторе и отменяет подписку в `close()` (`AGENTS.md` §9, как `_viewSubscription` у `ActiveSessionCubit`). Порт нужен для тестов: Cubit-у подставляют `FixedAppStrings(AppLocalizationsEn())` или управляемый `TestAppStrings`. Без него Cubit-ы зависели бы от всего Cubit языка (§13 — абстракция оправдана независимым тестированием).
- **Что применяется не сразу** (spec app-settings «Язык интерфейса app»):
  - меню macOS и системные панели (`file_selector`, диалоги ОС) — по языку системы (D11, Q4 (а));
  - смена языка ОС, пока выбрано `System`. Язык системы читается при старте и при каждом выборе `System`; `PlatformDispatcher.onLocaleChanged` не слушается. macOS сам просит перезапустить приложения после смены языка, а слушатель стал бы вторым источником языка.
- **Пока перевод неполный** (итерации 1–5), `system` разрешается в `en`, а явный `Русский` доступен для проверки. Порог снимается в итерации закрытия (задача 6.1). Это одна константа в `resolveAppLocale` и её тест, а не флаг конфигурации.
- Отдельного `LanguageSettingsCubit` нет: страница «General» читает и вызывает `AppLanguageCubit` напрямую. Второго держателя того же значения нет.

Альтернативы:
- (а) Применять после перезапуска. Пользователь отказался от этого варианта (Q1).
- Слушать `onLocaleChanged` при `System`. Отклонено (см. выше).

### D3. Каталоги, генерация и проверка

- `apps/codelab_desktop/l10n.yaml`: `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, `output-localization-file: app_localizations.dart`, `output-class: AppLocalizations`, `nullable-getter: false`, `required-resource-attributes: true`, `untranslated-messages-file: build/l10n_untranslated.json`. В `pubspec.yaml` — `flutter: generate: true`, `flutter_localizations: sdk: flutter`, `intl: any`. Версию `intl` закрепляет `flutter_localizations` SDK, поэтому своя граница версии привела бы к конфликту решателя.
- `packages/flutter/codelab_ui/l10n.yaml` — то же с `arb-dir: lib/src/l10n`, `codelab_ui_en.arb`, `CodeLabLocalizations`, `codelab_localizations.dart`, `nullable-getter: true` (нужен фолбэк, D4).
- **Сгенерированный код коммитится** (как `*.freezed.dart`): `dart analyze` в CI и у агентов работает без шага генерации. Скрипт Melos `l10n:check` по образцу `prompts:check` (`tool/l10n_check.dart`) перегенерирует оба пакета во временной копии и сравнивает с рабочими файлами. Скрипт входит в `check`, и в затронутые проверки §21 — при правке ARB. В CI на pull request скрипт идёт отдельным джобом `l10n` суженного прогона (решение пользователя 2026-11-18): `tool/ci/ci_scope.dart` включает его, если в `codelab_desktop` или `codelab_ui` изменён `l10n.yaml`, ARB, сгенерированный `*_localizations*.dart` или `pubspec.yaml` (в нём настройки генерации: `generate`, `flutter_localizations`, `intl`). Правка самого `tool/l10n_check.dart` — файл вне пакетов, она даёт полный прогон (`testing.md` §74).
- **Ключи** — camelCase `<экран><элемент><смысл>`: `settingsLanguageTitle`, `workbenchSidebarNewSession`, `providersRemoveKeptSecret`. У каждого сообщения — `@key.description` с контекстом для переводчика (где показывается, что в плейсхолдерах). Плейсхолдеры типизированы (`String`, `int`); количество — только `plural`, без склейки `n == 1 ? … : …`.
- **Эталон `en`.** Текст `en` каждого сообщения, приведённого в спецификации, совпадает со спецификацией символ в символ, поэтому существующие сценарии и тесты остаются верными.
- **Согласованность.** Тест `l10n_catalogs_test.dart` в каждом пакете: наборы ключей `en` и `ru` равны, плейсхолдеры каждого сообщения совпадают, у `ru`-сообщений с `plural` есть формы `one`, `few`, `many`, `other`. `gen-l10n` сам такие ошибки не считает фатальными: он только пишет `untranslated-messages-file`.

### D4. `codelab_ui` — свой каталог и фолбэк на английский

Решение: у кита свои `codelab_ui_en.arb`/`codelab_ui_ru.arb` и делегат `CodeLabLocalizations`. Барель экспортирует `CodeLabLocalizations` (`delegate`, `supportedLocales`). Внутри кита тексты берёт одна функция `codeLabStringsOf(context)`: `CodeLabLocalizations.of(context) ?? CodeLabLocalizationsEn()`. Она не экспортируется, файл — `lib/src/l10n/strings.dart`.

- Фиксированные словари кита (статусы, риски, тоны, приоритеты, вкладки `ToolPane`, «Selected», «Awaiting approval») остаются внутри кита: это его пары «подпись — тон» (`codelab_ui/AGENTS.md` §5). App по-прежнему выбирает значение enum, а не текст.
- `ToolPane` сейчас хранит английский заголовок полем enum (`files('Files', …)`). Поле заменяется на функцию кита `toolPaneTitleOf(context, pane)`. Внешние читатели `ToolPane.label` в app переходят на неё.
- Параметры со строкой по умолчанию (`placeholder`, `emptyLabel`, `reconnectLabel`, `actionsLabel`, `newSessionShortcut` не трогается — это клавиша) становятся `String?`: `null` — текст кита. Вызовы app, которые передают свою строку, не меняются.
- Без делегата в дереве кит показывает английский. Поэтому 45 тестовых `FluentApp` кита, превью и любые хосты кита без локализации работают как раньше (spec app-settings, сценарий «Кит без делегата»).
- Логики в ките не прибавляется: выбор текста по enum, который уже есть, — это вёрстка (§2 `codelab_ui/AGENTS.md`).
- Публичные английские эталоны `en` остаются, на экране текст берётся из каталога. `CodeLabApprovalPrompt.noSuchOption` сохраняется, потому что на константу ссылаются тесты и спецификации; на экране — `codeLabApprovalNoSuchOption`. `CodeLabApprovalRisk.label` — публичный английский эталон с собственным набором литералов (независимый `switch`, не чтение каталога `en`); на экране — `labelOf(context)`. Совпадение обоих эталонов с каталогом `en` сверяет `codelab_l10n_en_reference_test.dart` кита: эталон и каталог не выводятся друг из друга, поэтому тест ловит правку только одного из них. Новые публичные строковые константы кита не вводятся.
- `CodeLabCommandAction.defaults` — команды app, а не словарь кита. В итерации 2 они остаются английскими литералами: это значение по умолчанию `CodeLabCommandPaletteSurface.actions` для превью и тестов кита. В итерации 3 подписи и описания пунктов хоста (`defaults`, а также `Files`, `Agents`, `Usage` из `ui_mappers`) переводит app по `id` через `AppLocalizations` (D5). `slashCommand` не переводится. Кэш команд хоста учитывает язык (R1).
  - *Поиск команд хоста после перевода (решение пользователя 2026-11-18, закрывает открытый вопрос итерации 2):* команды хоста ищутся в палитре (по `Ctrl/Cmd+K` и inline из композера — у обеих один `CommandCatalog.search`) и по подписи и описанию на текущем языке, и по английским. Это то же правило, что у поиска настроек по заголовку (D5, п. 8): пользователь ищет и по тому, что видит, и по английскому названию из документации. Команды агента (имя и описание от агента) не переводятся и ищутся как раньше. Поиск по имени команды (`slashCommand` без `/`) работает при любом языке: имя не переводится.
  - *Исключение: пункт перезапуска локального агента (решение пользователя 2026-11-19).* У локального агента (встроенного или `stdio`) пункт `reconnect` показывается как `Restart agent` с описанием `paletteRestartDescription` (Q24 и D22 прежних changes; `_hostTextOf(localRestart:)` в `ui_mappers.dart`). `HostCommand` этого пункта получает в `label` и `description` ту же видимую подпись и описание на текущем языке, а на `ru` — ещё английские `Restart agent` и описание в `searchAliases`. Поиск идёт по тому, что видит пользователь. Поэтому на `en` у локального агента набор результатов меняется: пункт находится по `restart` и описанию перезапуска. По имени `reconnect` он находится как раньше. Это единственное отступление от правила «на английском результаты совпадают с прежними» (spec app-settings «Локализация интерфейса app», сценарий «Пункт перезапуска локального агента ищется по видимой подписи»). Альтернатива — искать по скрытой подписи `Reconnect`, когда на экране `Restart agent`. Отклонена: пункт находился бы по слову, которого пользователь не видит, и не находился бы по тому, что он видит.
  - *Механизм.* Правила поиска палитры живут в ядре клиента — `CommandCatalog.search` (`codelab_client_core`, spec acp-client-kit «Каталог команд палитры»; change `add-command-palette-agent-commands`, D4), а не в app. Поиск настроек — функция app, поэтому там хватило параметра `titlesOf`. Здесь `HostCommand` получает аддитивное поле `searchAliases` (`List<String>`, по умолчанию пусто). Это дополнительные строки поиска, которые сравниваются тем же последним правилом, что название и описание (подстрока без учёта регистра). Префикс, подстрока и подпоследовательность имени не меняются. Ядро не знает, что это английский текст: поле языконезависимо (spec workspace-architecture «Ядро клиента не зависит от языка интерфейса»). У команд агента дополнительных строк нет. CLI поле не заполняет, и его поиск не меняется.
  - *Что заполняет app.* `_hostCommandOf` в `ui_mappers.dart` получает `AppLocalizations` текущего языка. `label` и `description` — перевод по `id`. `searchAliases` — английские подпись и описание из `AppLocalizationsEn()`, без тех, что совпадают с `label` или `description`; на `en` поле пусто, и поиск совпадает с прежним. Английский каталог берётся так же, как в `settings_shell.dart` для `titlesOf` (`settingsPageTitleOf(AppLocalizationsEn(), page)`): прямой `AppLocalizationsEn()` равен `lookupAppLocalizations(const Locale('en'))` и не тянет `Locale` в `application/`. `_hostCommandsCache` получает язык в ключе (R1). Строка палитры по-прежнему строится из `CodeLabCommandAction` по `id` (`_paletteActionOf`), поэтому `searchAliases` на экран не попадает.
  - *Альтернативы.* (б) Дописать английские строки в `HostCommand.description`. Поле документировано как описание команды, и CLI показывает описание своих команд хоста, так что смысл поля размылся бы. Отклонено. (в) Два каталога в app, на текущем языке и на английском, и слияние результатов. Тогда app повторяет порядок правил поиска ядра: английское совпадение должно встать внутрь последнего правила в порядке `commands`. Правила отбора снова ушли бы из ядра в хост (D5 change `add-command-palette-agent-commands`). Отклонено. (г) Искать только на текущем языке. Тогда английская подпись из документации и руководства перестала бы находить команду на `ru`, хотя поиск настроек её находит. Пользователь это отверг.

Альтернативы:
- (б) все строки кита — параметры от app. Это сотни новых параметров, и пары «подпись — тон» уходят из кита, вопреки §5. Отклонено;
- (в) кит читает `AppLocalizations` app — кит не может зависеть от app (`AGENTS.md` §5). Отклонено;
- (г) один общий пакет каталогов для app и кита — новый пакет ради двух файлов ARB (§13). Отклонено.

`codelab_ui/AGENTS.md` §1 (зависимости) дополняется: `flutter_localizations`, `intl` — только для каталога кита.

### D5. Где собирается текст и как он пересобирается при смене языка (механизм Q1 — вариант (б) с типизированными разовыми сообщениями)

**Выбор.** Текст на экране бывает трёх видов, и у каждого свой путь пересборки:

| Вид текста | Где сейчас | Путь при смене языка |
|---|---|---|
| **Текст виджета** — подписи, кнопки, пустые состояния, InfoBar с постоянным текстом, словари кита | `build` виджета, кит | `context.l10n` / `codeLabStringsOf(context)`. Пересобирается Flutter-ом через `Localizations`, без подписок |
| **Производный текст в состоянии** — модели кита, которые Cubit строит из текущих входов: строки ленты и заметки (`NoticeReason`), сайдбар, шапка, строка статуса, палитра, строки страниц настроек | Cubit-ы и мапперы `application/` (`ui_mappers.dart`, `provider_wizard_view.dart`) | язык — **явный вход** Cubit-а, как `usage` и статус сессии. По событию `AppStrings.changes` Cubit пересобирает состояние из последних входов (последний `SessionView`, снимок настроек, состояние соединения) с новым `AppLocalizations` и сбрасывает кэши, у которых ключ без языка |
| **Разовое сообщение** — исход действия или события, которое не повторится: «Provider X removed…», «Default model saved.», ошибки записи конфига, отказ удаления, сбой сохранения CSV, причина отказа подключения | Cubit собирает строку в момент события | в состоянии хранится **типизированное сообщение** (sealed-класс с аргументами, например `ProviderRemoved(id, secretOutcome)`). Текст собирает presentation по `context.l10n`, поэтому он пересобирается как текст виджета. Пересобрать строку из входов нельзя: входа уже нет |

Правила:
1. Состояние, которое строится из входов, — функция `(входы, язык)`. Cubit не хранит переведённую строку, которую нельзя пересобрать из его входов. Это проверяет общий тест смеси языков (D9).
   *Отказ по токену (решение пользователя 2026-11-19, итерация 3).* Отказ 401/403 при подключении `ConnectionCubit` хранит типизированно: статус HTTP и признак «токен отправлен». Это вход проекции, а не готовая строка. Текст баннера строится из ARB и пересобирается при смене языка. Остальные ошибки соединения — текст ядра в `connectionMessage` (`ConnectionLost.message`, `ConnectionFailed.message`). Он показывается как есть и остаётся диагностикой без перевода (D6, D7). App не разбирает эту строку и не пытается угадать по ней причину (п. 5).
2. `AppStrings.current` читается только внутри проекции. Строки, сохранённые раньше, не используются повторно: при смене языка пересобирается вся проекция, а не отдельные поля.
3. Подписка на `AppStrings.changes` — одна на Cubit, создаётся в конструкторе и отменяется в `close()`. Событие после `close` игнорируется (`isClosed`). Других источников языка у Cubit-ов нет.
4. `features/usage/application` и `features/terminal/application` остаются без Flutter (правила сторожа). Оттуда выходят типизированные значения: enum `UsageBudgetRowKind` (строки Steps, Tokens, Cost, Time блока «Turn budget») и `UsageBudgetTitle.thisTurn|lastTurn`; enum `UsageCardKind` (карточки Input, Output, Cost, Turns · steps) и подробности карточки — sealed `UsageCardDetail`; `UsageModelKind`, `UsageLedgerLineKind`, `UsageStepTitle`, а также sealed статус вкладки терминала `TerminalTabStatus`. Точные имена задаёт код исполнителя итерации 3. Текст собирает presentation (`usage_pane_view.dart`, `terminal_tab_view.dart`). Это текст виджета, подписки не нужны. Кэш `ActiveSessionCubit` для данных Usage остаётся языконезависимым.
5. Ядро клиента текст не переводит (D6): app не разбирает английскую строку ядра.
6. Текст интерфейса в журнал не попадает. События журнала и их поля английские и от языка не зависят.
7. Тексты от агента подставляются плейсхолдером как есть (D7). Склейка фраз из частей запрещена: `'In $backendId as '` и подобное становится одним сообщением с плейсхолдерами.
8. Enum с английским заголовком (`SettingsPage.title`, `SettingsGroup.title`, `ToolPane.label`) теряет поле заголовка. Текст по значению даёт функция presentation; `slug` и `navKey` остаются. Для настроек это `settingsPageTitleOf(l10n, page)` и `settingsGroupTitleOf(l10n, group)` в `features/settings/presentation/settings_titles.dart` (итерация 1). Поиск настроек `SettingsSearchIndex.search(visible, query, titlesOf:)` получает параметром `titlesOf` заголовки страницы на текущем языке и на английском: пользователь ищет и по тому, что видит, и по английскому названию из документации. Ключевые слова страниц (`SettingsSearchIndex.keywords`) есть на обоих языках, и поиск по ним работает при любом языке интерфейса (решение пользователя 2026-11-18, задача 3.3; MODIFIED «Навигация настроек»). После итерации 1 они были только английскими.
9. Открытый диалог (подтверждение перезапуска агента, «Remove profile …?», мастер провайдера) пересобирается вместе с деревом. Его текст строится в `build` или берётся из состояния своего Cubit-а по правилам выше. Черновик, введённый пользователем, при смене языка не сбрасывается.

**Почему (б), а не (в).** Оба варианта переключают язык сразу. Разовые сообщения в обоих типизированы, по `error-handling.md` §43.
- (в) «текст вне состояния целиком» перенёс бы построение моделей кита из Cubit-ов в `build`. `CodeLabShellState` перестал бы хранить `transcriptRows`, `sessions`, `statusBar` и палитру. Это переделка публичной поверхности фасада: на её поля опираются 23 файла тестов, включая характеризационные тесты фасада (spec testing-quality «Характеризационные тесты фасада приложения»). Кроме того, ленту пришлось бы переотображать на каждый `build`, нужна была бы мемоизация в presentation, а сейчас пересчёт идёт только при смене входов (`apps/codelab_desktop/AGENTS.md`, «Панель Usage»). По §2 риск для корректности состояния и производительности выше выигрыша.
- (б) оставляет форму состояния и кэширование как есть. Язык добавляется ещё одним явным входом проекции, по образцу уже существующих входов (`usage`, `usageLedger`, статус, одобрения). Переходы состояния явные и тестируются (`AGENTS.md` §8).
- Риск (б) — Cubit, который забыли подписать на смену языка. Это закрывают три вещи: правило 1, общий тест смеси языков на живом рабочем месте и на каждой странице настроек (D9) и ревью по списку Cubit-ов с текстом (D12).

**Почему не отказ от текста в Cubit-ах вообще.** Модели кита с текстом для виджетов Cubit-ы строят и сейчас (`apps/codelab_desktop/AGENTS.md`, «Лента переписки»). Это слой представления app, а не low-level пакет из `error-handling.md` §98. Граница §43 соблюдается там, где она важна: ядро клиента отдаёт типизированные причины и сбои.

### D6. Тексты из ядра клиента

Ядро клиента общее с CLI и web-безопасное (`codelab_client_core/AGENTS.md`). Оно остаётся английским и без `intl` (D10). Desktop строит текст по типизированным данным:

| Текст ядра | Что видит desktop | Решение |
|---|---|---|
| `NoticeItem.text` видов `emptyTurn`, `turnStopped` | `stopReason`, имя лимита бюджета | **новое** аддитивное поле причины (spec acp-client-kit «Типизированная причина заметки транскрипта») |
| `NoticeItem.text` видов `detached`, `reconnected` | причина: агент не восстанавливает сессии / не удалось, id сессии | **новое** поле причины, тот же тип |
| `NoticeItem` вида `error` | `PromptFailure` (уже есть, `failureTitleOf` в app) | заголовок переводит app; тело — сообщение агента как есть |
| Подпись решённого одобрения `ResolvedApprovalView.label` (`Cancelled`, `Resolved` — запасные строки ядра) | `outcome` (`ApprovalOutcomeView`) и **новое** аддитивное поле `agentLabel` (`String?`): название выбранного варианта от агента или id варианта; `null` — подписи агента нет | ядро даёт `agentLabel`, хост показывает его как есть (D7); при `null` хост строит запасную подпись по `outcome`: `cancelled` → `workbenchApprovalCancelled`, иначе `workbenchApprovalResolved`. `label` ядра не меняется и остаётся для CLI |
| `ToolRowView.label` | `ToolCallItem.details.kind` | app переводит метку по `ToolKind`; для `other` и субагента — `label` ядра (это заголовок от агента) |
| `ProfileDraftIssue.message` | `ProfileDraftIssueCode` (есть) | app переводит по коду |
| Поиск `CommandCatalog.search` по `HostCommand.label`/`description` | подпись и описание команды хоста на языке app | **новое** аддитивное поле `HostCommand.searchAliases`: app кладёт туда английские подпись и описание (D4; spec acp-client-kit «Каталог команд палитры», MODIFIED) |
| `ProfileCommitter` (`ProfileSaveFailed` и др.) | sealed результат | app переводит по варианту; причину хранилища секретов (`reason`) показывает как есть — это текст бэкенда |
| `InspectorProjection`, `WorkspaceDiagnostic.message`, `ClientWorkspaceException.message` | — | не переводятся: диагностика (D7) |
| `ConnectionLost.message`, `ConnectionFailed.message` | причина потери или отказа соединения — готовый английский текст ядра | не переводятся: диагностика (D7). Баннер и шапка подставляют её плейсхолдером `{reason}` в переведённую рамку (`workbenchConnectionFailedAgain`); app эту строку не разбирает (D5, п. 5). Своё сообщение app строит только там, где у него есть тип причины: отказ по токену 401/403 (статус и признак «токен отправлен» хранятся типизированно, текст из ARB пересобирается при смене языка — D5, п. 1; решение пользователя 2026-11-19), «Could not start the agent.» |
| `formatUsage*` | готовые строки чисел | без изменений (D8) |

Тексты порта переноса секретов (`SecretMigrationOutcome`, desktop). `items` (строки `describe()` пунктов плана), `problem` и `detail` порт строит готовым английским текстом. В нём есть пути файлов конфигурации, подсказка бэкенда `env` с веткой платформы и текст конфликта имени. В итерации 3 они показываются как есть, по-английски, при любом языке. `SecretMigrationPortProblem.text` — та же строка. Это принятое ограничение до отдельного решения, а не правило D7. Чтобы перевести их, порту нужен типизированный отчёт: код проблемы и признак платформы вместо готовой строки. Это правка контракта порта и мигратора (`add-config-literal-secrets-and-migrate`, D8), в этот change она не входит. Текст, который app строит сам — заголовки, статусы диалога, `secretMigrationPlanFailed`/`ApplyFailed` с `{errorClass}`, — переводится.

Подпись профиля встроенного агента (`EmbeddedProfile.label`, `features/settings/application/embedded_profile.dart`, `Embedded agent`) переводится в итерации 4 вместе со страницей «Connection» и списком профилей. В итерации 3 переводится только подпись типа соединения в шапке рабочего места (`workbenchTransportEmbedded`), которую строит `ConnectionCubit` по типу профиля.

Тип причины — sealed `NoticeReason` в `transcript/transcript_item.dart` (`EmptyTurnReason(stopReason?)`, `TurnStoppedReason(stopReason, budgetLimit?)`, `SessionRestoreReason(cause, sessionId?)` с enum `cause: agentCannotRestore | restoreFailed`). Это предложение. Точные имена выбирает исполнитель `[client]`, наблюдаемое поведение задаёт spec. Поле необязательное (`NoticeReason? reason`): старые потребители и `copyWith` не ломаются. Набор известных лимитов — тот же `_knownBudgetLimits`, что у текста, поэтому текст и причина не расходятся. Инвариант «инкрементальная проекция = проекция с нуля» распространяется на причину. ACP не меняется: все данные уже есть в read-модели хода.

### D7. Что не переводится

Список — в spec app-settings «Локализация интерфейса app». Пояснения:
- **«Debug log» и «Inspector»** — инструменты диагностики. Их содержимое строят ядро клиента и журнал, и оно должно совпадать с тем, что пользователь пришлёт в отчёте об ошибке. Заголовки вкладок дока (`ToolPane`) переводятся, содержимое — нет (решение пользователя Q3 (а)).
- **Протокол и конфигурация:** `stopReason`, `kind`, имена методов, ключи `budget.*`, `config.yaml`, `CODELAB_HOME`, `secret:`/`env:`, команды `codelab …` и slash-команды — плейсхолдеры или неизменяемые части сообщения. Переводчик не может их испортить: в `@description` они перечислены как «не переводить».
- **Провайдеры и продукты:** `OpenAI-compatible`, `Anthropic`, `Gemini`, `MCP`, `ACP`, `CodeLab`. Подпись `Unknown kind` переводится.
- **Клавиши:** `⌘`, `⌥`, `Ctrl+K` — как есть.

### D8. Числа, даты, множественное число

- **Usage** (токены `94.0k`, деньги `$1.20`, проценты `79%`, время `m:ss`) — формат ядра клиента, общий с CLI и CSV (spec agent-workbench-ui «Строка статуса сессии под композером»; `add-usage-extension`, D24). В русском интерфейсе он остаётся с точкой, без пробелов между разрядами (решение пользователя Q2 (а)): одинаковые числа на экране, в CSV и в отчётах; `k`/`M` — технические обозначения, как в IDE.
- **Даты** — сегодня `yyyy-MM-dd HH:mm` в списке сессий (`_minuteOf`) не зависит от языка и остаётся.
- **Количество** — только ICU `plural` (`{count, plural, one{…} few{…} many{…} other{…}}`). Затронутые места: подтверждение перезапуска агента («N running sessions»), счётчики панели Agents, «Remove N …», очередь промптов, и любое новое «N …». Исключение — счётчик очереди «{count} queued» → «в очереди: {count}»: число стоит после двоеточия, форма не зависит от числа, и `plural` не нужен (ревью итерации 2, 2026-11-18). Такая форма допустима только там, где число отделено двоеточием и слова с ним не согласуются.
- **Длина строк.** Русские подписи в среднем на 20–30 % длиннее. Подписи кнопок и тегов не обрезаются логикой: раскладка кита уже держит многоточие и подсказку для заголовков. Для узких мест (навигация настроек 760 px, строка статуса, теги вызовов, кнопки диалогов) в итерациях есть виджет-тесты на `ru` без переполнения (`tester.takeException()` пуст).

### D9. Тесты

- **Локаль по умолчанию — `en`.** `CodeLabTestBinding` получает параметр `locale` (по умолчанию `Locale('en')`) и передаёт начальный язык `AppLanguageStart` в шов `createCodeLabRootScope(language:)`. Выбор в начальном состоянии задаёт `languagePreference` (по умолчанию `system`), целиком начальный язык с диагностикой чтения — `languageStart`, хранилище выбора — `languagePreferences`. Двойники порта `AppStrings` — `test/support/app_strings.dart` (`FixedAppStrings`, `TestAppStrings` с `hasListener`). Тестовые `FluentApp` в desktop без scope получают делегаты из одного помощника `test/support/l10n_app.dart` (`localizedFluentApp(child, locale: …)`). Существующие `find.text('…')` на английском не меняются: эталон `en` совпадает со спецификациями (D3).
- **Тесты кита** без делегата продолжают работать (D4). Для каждого фиксированного словаря кита есть тест на `ru` с делегатом.
- **Cubit-тесты.** Cubit-ы с текстом получают `FixedAppStrings(AppLocalizationsEn())`, поэтому проверки строк не меняются. Каждый Cubit с текстом в состоянии получает тест с `TestAppStrings`:
  - смена языка даёт новое состояние, в котором производный текст на `ru`;
  - кэши не возвращают старый язык;
  - разовые сообщения хранятся типизированными и не меняются;
  - после `close` подписка отменена (`hasListener == false`), и событие языка не даёт `emit`.
- **`AppLanguageCubit`:**
  - `select` применяет язык до записи;
  - сбой записи оставляет язык и ставит `saveFailed`;
  - при двух быстрых выборах сохраняется последний;
  - после `close` ничего не применяется: `select` и подписки отклоняются, запись в полёте ждётся не дольше `closeWriteTimeout` и состояние не публикует, `close` не виснет на подписчике на паузе;
  - повтор записи кнопкой `Retry` после сбоя;
  - `load()` не бросает: незнакомое и нестроковое значение, сбой открытия хранилища;
  - подписчиков `changes` ровно столько, сколько Cubit-ов с текстом, и повторное подключение не добавляет второй подписки (`AGENTS.md` §9).
- **Тест смеси языков (главная защита D5).** Помощник `test/support/l10n_mix.dart`: `expectNoStaleLanguage(tester, from: AppLocalizationsEn(), to: AppLocalizationsRu())` собирает все видимые строки дерева (`Text`, `RichText`, `placeholder` полей, `Tooltip.message`, `Semantics.label`). Тест падает, если среди них есть значение сообщения без плейсхолдеров из каталога `from` (app или кита), у которого перевод в `to` отличается. Сценарий: экран в `en` с данными → `AppLanguageCubit.select(ru)` → `pumpAndSettle` → помощник. Ответы агента, пути и команды в каталог не входят, поэтому ложных срабатываний нет. Похожие строки (`OK`, `MCP`) помощник пропускает: их `ru` совпадает с `en`. Прогоны:
  - живое рабочее место: лента с ответом агента, вызовом инструмента в статусе `running`, заметками `turnStopped` и `error`, ожидающим одобрением; сайдбар с сессиями в разных статусах; шапка и строка статуса; баннер потери соединения; открытая палитра; доки Files, Agents, Usage (с «Turn budget»), Terminal;
  - открытый диалог подтверждения перезапуска агента;
  - каждая видимая страница настроек в рабочем состоянии и в состоянии с InfoBar и ошибкой: «Connection» (ошибка чтения `profiles.json`), «Providers» (только чтение, исход удаления), «MCP servers», «Agents & modes», «Skills & extensions», «General» (сбой записи);
  - обратно `ru` → `en`.
- **Точечные тесты пересборки:**
  - уже показанная заметка `turnStopped` после смены языка показывает перевод по `NoticeReason`;
  - тег статуса вызова и статус сессии в сайдбаре пересобраны;
  - текст ошибки подключения и InfoBar страницы пересобраны;
  - введённый текст композера и черновик диалога профиля сохранились;
  - фокус и прокрутка ленты не сбросились.
- **Интеграционные тесты** (`integration_test/`, только `release/*`) не зависят от языка машины: `integration_test/flutter_test_config.dart` в `setUp` каждого теста кладёт `codelab.app.language = en` в подменённое хранилище `SharedPreferences` (`setMockInitialValues`). `E2eLaunch` для этого не подходит: он готовит агента и `CODELAB_HOME`, а app не запускает. Тест `settings_language_flow_test.dart`: выбор `Русский` на странице «General», затем возврат на рабочее место с живой сессией — тексты на русском без перезапуска; затем `English`.
- **Охват.** Тест литералов (D10) — регрессионная сетка для новых строк.

### D10. Пакеты, зависимости, сторож

- Затронутые пакеты по ADR-0002: `codelab_desktop` (app), `codelab_ui` (Flutter-кит), `codelab_client_core` (слой `core` стороны `client`, аддитивно: `NoticeItem.reason`, `HostCommand.searchAliases`, `ResolvedApprovalView.agentLabel`). Новых пакетов нет, направление зависимостей не меняется, граф в `README.md` и `docs/architecture/README.md` не меняется.
- Новые прямые внешние зависимости: `flutter_localizations` (SDK) и `intl` — в `codelab_desktop` и `codelab_ui`. В `pubspec.lock` новых пакетов нет. Allowlist сторожа (`desktopAllowlist`) проверяет только `codelab_*`, его правка не нужна. PKG-2 (allowlist ядра агента) не затрагивается.
- **Новое правило сторожа** в `codelab_architecture_tests/test/support/rules.dart`: `PackageRule('packages/dart/codelab_client_core', forbidden: ['package:intl/', 'package:flutter_localizations/'])` и такое же для `codelab_client_acp` (spec workspace-architecture «Ядро клиента не зависит от языка интерфейса»). `package:flutter/` там уже запрещён правилом `webUnsafe`. `intl` web-безопасен, поэтому `webUnsafe` его не ловит. Правило фиксирует решение D6, а не web-безопасность.
- **Тест литералов** — `codelab_architecture_tests/test/ui_literals_test.dart` (итерация закрытия): в `apps/codelab_desktop/lib/features/**/presentation/`, `lib/app/` и `packages/flutter/codelab_ui/lib/src/` (кроме `*_previews.dart` и `l10n/`) нет строковых литералов, начинающихся с буквы, в позициях `Text('…')`, `CodeLabText('…')`, `label:`, `tooltip:`, `placeholder:`, `title:`, `message:`, `content: Text(`. Исключения — `test/support/ui_literals_allowlist.txt` с причиной у каждой строки. Это эвристика, а не разбор AST, поэтому список позиций узкий; литералы в `application/` проверяет ревью. Альтернатива — свой lint на `analyzer` — несоразмерна (§13).
- Импорт `lib/l10n/` из `features/usage/application` и `features/terminal/application` сторож относительным путём не ловит: правила сторожа сравнивают префиксы URI. Защита — правило `package:flutter/` для этих каталогов: сгенерированный класс без Flutter не использовать нельзя, и ревью видит импорт. Отдельное правило не вводится.

### D11. Меню macOS (решение пользователя Q4 (а))

Решение: `Info.plist` — `CFBundleLocalizations` = `en`, `ru`; `macos/Runner/ru.lproj/MainMenu.strings` с переводом пунктов шаблона (About, Hide, Quit, Edit, Window, Help…). macOS выбирает язык меню по языку системы, а не по `codelab.app.language`. Поэтому при русской системе и явном `English` в настройках меню будет русским. Ограничение описывается в документации пользователя. Заодно системные панели (`file_selector`) и стандартные пункты получают русский язык, когда система русская: без `CFBundleLocalizations` macOS показывает их на английском.

Вместе с системными панелями ОС это единственная часть интерфейса app, которая не следует выбору в настройках и не переключается сразу (D2). Альтернатива (б): писать `AppleLanguages` в user defaults приложения при смене языка — тогда и меню, и системные панели следуют выбору после перезапуска. Это платформенный код в `core/platform/` и запись в defaults ОС; можно сделать отдельным change. (в) Не трогать меню — оно останется английским и при русском интерфейсе.

### D12. Итерации

Оценка объёма — около 720 сообщений: app около 550, кит около 150, тексты ядра около 20. Перевод `ru` пишется вместе с ключом, а не отдельным проходом. Итерации разбиты по экранам:

| Итерация | Что | Сообщений (оценка) | PR |
|---|---|---|---|
| 0 | документы | — | с итерацией 1 |
| 1 | каркас: зависимости, `l10n.yaml`, делегаты, разрешение языка, порт, `AppLanguageCubit` и `AppStrings`, «General» с «Language», `l10n:check`, тест каталогов, шаблон каталога кита, помощники `localizedFluentApp` и `expectNoStaleLanguage`, язык `en` в `integration_test/flutter_test_config.dart` | ~15 | 1 |
| 2 | кит `codelab_ui` целиком | ~150 | 2 |
| 3 | рабочее место: оболочка, сайдбар, композер, баннеры, лента и заметки (с `[client]` причиной заметок), одобрение, палитра, доки Files, Agents, Usage, Terminal, диалоги перезапуска и переноса секретов, навигация и поиск настроек | ~210 | 3 |
| 4 | настройки I: Connection, «Add connection profile», Providers, мастер провайдера | ~200 | 4 |
| 5 | настройки II: MCP servers, Agents & modes, Skills & extensions | ~150 | 5 |
| 6 | закрытие: `system` → `ru`, тест литералов, меню macOS, документация, приёмка | — | 6 |

Итерации 2 и 3 зависят от 1; 4 и 5 — от 1 и независимы друг от друга. Итерация 6 идёт последней. Между итерациями `develop` остаётся рабочим: `system` даёт `en` до итерации 6 (D2).

**Активные changes.** `add-app-skills-page`, `add-file-preview-and-tree`, `add-integrated-terminal` добавляют строки в те же экраны (`add-settings-agents-modes`, `add-desktop-usage-pane`, `add-subagents-and-tasks` архивированы 2026-11-18, их строки уже в `develop` и входят в сверку итерации экрана). После слияния итерации 1 новые строки в этих changes пишутся сразу ключами ARB с `en` и `ru`. Правило попадает в `apps/codelab_desktop/AGENTS.md` (задача 0.3). Итерация экрана в начале сверяет свой список строк с `develop`.

**Список Cubit-ов с текстом в состоянии** (подписка на `AppStrings`, D5): `ConnectionCubit`, `ActiveSessionCubit`, `SessionsCubit`, фасад `CodeLabShellCubit` (своей подписки нет — уточнение итерации 3 ниже), `ConnectionSettingsCubit`, `AddProfileCubit`, `ProviderSettingsCubit`, `ProviderWizardCubit`, `McpSettingsCubit`, `AgentsModesCubit`, `SkillsSettingsCubit`. Итерация экрана начинает со сверки списка по коду (поиск литералов в `application/`). Каждый Cubit из списка получает тест смены языка (D9). Cubit, который перестал хранить текст, из списка уходит.

*Уточнение итерации 3 (сверка списка по коду, 2026-11-19).* У фасада `CodeLabShellCubit` своей подписки на `AppStrings` нет. Каталог палитры (`paletteCatalogOf`) он собирает, когда пересчитывает своё состояние вслед за частями, и язык берёт из `parts.strings.current`. При смене языка пересчёт запускают `emit` Cubit-ов частей: `ConnectionCubit`, `ActiveSessionCubit` и `SessionsCubit` подписаны и пересобирают состояние. Поэтому фасад остаётся в списке Cubit-ов с текстом и получает тест смены языка, а отдельный подписчик ему не нужен. Если когда-нибудь ни одна часть не сделает `emit` при смене языка, палитра останется на старом языке. Это ловит тест палитры после смены языка (задача 3.3, R1).

Цена такого пересчёта. При смене языка фасад пересчитывает состояние до трёх раз синхронно, по разу на каждую подписанную часть. Промежуточные состояния бывают смешанными: одна часть уже на новом языке, другая ещё на старом. Последнее состояние целиком на новом языке. `BlocBuilder` перерисовывается не чаще раза в кадр, поэтому промежуточные состояния на экран не попадают. Свести всё в один `emit` можно только через общий диспетчер языка, который упорядочил бы пересборку частей и фасада. Это отклонено: новый механизм ради трёх синхронных пересчётов на действие пользователя несоразмерен (`AGENTS.md` §13; R5).

`SecretMigrationCubit` из списка ушёл. После 3.4 в его состоянии нет текста, который зависит от языка. Сбой — sealed `SecretMigrationFailure`: `SecretMigrationUnexpected(errorClass)` переводит presentation, а `SecretMigrationPortProblem(text)` — текст порта, он показывается как есть (D6). Тексты диалога и InfoBar строит виджет по `context.l10n`. Смена языка поэтому состояние не меняет, и подписка была бы пустым обработчиком. Cubit на `AppStrings` не подписывается и порт не получает.
- Почему так. По D5 п. 3 подписка нужна Cubit-у с производным текстом в состоянии. Подписка «на вырост» — абстракция без задачи (`AGENTS.md` §13). Она добавляет ещё одного подписчика в число `app.locale_applied {subscribers}` (D13), а по этому числу ищут утёкшую подписку. Ещё она создаёт ложное впечатление, что Cubit пересобирает текст.
- Чем это защищено. Если в состоянии `SecretMigrationCubit` снова появится текст, зависящий от языка, его поймает тест смены языка на открытом диалоге переноса (`secret_migration_banner_l10n_test.dart`, «смена языка пересобирает открытый диалог с планом»). Вместе с таким текстом Cubit возвращается в этот список, получает порт и тест смены языка по D9.
- Что остаётся. Сбой по-прежнему хранится типизированным, а его текст собирает presentation по `context.l10n`. Это проверяют виджет-тесты баннера на `ru` и тест смены языка на открытом диалоге. Cubit-тест, где событие языка сравнивается с состоянием сбоя, теряет смысл: события языка у Cubit-а больше нет (задача 3.6).

### D13. Наблюдаемость

Логгер `codelab_desktop.settings`, компонент `settings`:
- info `settings.language_changed {language, locale}` (`system | en | ru`; `locale` — применённый язык);
- warning `settings.language_save_failed {error_class}` — только `runtimeType`;
- warning `settings.language_save_timeout {timeout_ms}` — `close()` не дождался записи выбора за `closeWriteTimeout` (D2): выбор мог не дойти до хранилища. Без значения выбора и текста ошибки.

Логгер app `codeLabAppLogger()` (`codelab_desktop.app`, компонент `app`):
- info `app.locale_resolved {preference, locale}` при старте — пишет `CodeLabLanguageModule` при сборке root scope;
- warning `app.language_preference_invalid` — без значения ключа: в хранилище незнакомое или нестроковое значение;
- warning `app.language_preference_read_failed {error_class}` — хранилище не открылось при старте, язык взят как при `System`; только `runtimeType` ошибки;
- оба предупреждения пишет `CodeLabLanguageModule` вместе с `app.locale_resolved` по диагностике шва `AppLanguageStart`: порт читает язык в `main` до настройки журнала и сам не логирует;
- шаг `language` в `pending` события `app.exit_timeout`, если запись выбора не завершилась к пределу выхода (D2);
- debug `app.locale_applied {locale, subscribers}` после каждой смены языка: по числу подписчиков `AppStrings.changes` видна утёкшая или пропущенная подписка. Пишет `AppLanguageCubit` через параметр `appLogger`; события `settings.*` идут в его `logger`.

Язык системы в события не пишется. Тексты интерфейса в события не попадают (D5, п. 6).

### D14. Безопасность и данные

- В ARB нет секретов, путей пользователя и значений токенов. Плейсхолдеры с путями и именами секретов заполняются теми же значениями, что и сейчас: правила «токен — только ссылка» и «секрет — только имя» не меняются.
- Переводы предупреждений безопасности (`ws://` без шифрования, «This file may contain secrets.», раскрытие вывода терминала, подтверждение корня диска, риски одобрения) сохраняют смысл и силу предупреждения. Эти сообщения помечены в `@description` как «security», и итерация не закрывается без их ревью человеком (задачи 3.x, 4.x).
- Переводится только текст. Смысл, тон и порядок кнопок одобрения (`Allow`/`Reject`, риск, «Only this time»/«Always») не меняются, клавиши одобрения не зависят от языка. Решение по-прежнему привязано к своему tool call.

## Risks / Trade-offs

- [R1] **Смесь языков после переключения:** Cubit с текстом забыли подписать на `AppStrings`, или кэш проекции не учитывает язык. → Правило D5.1, общий тест `expectNoStaleLanguage` на живом рабочем месте и всех страницах настроек (D9), список Cubit-ов с текстом и тест смены языка у каждого (D12), событие `app.locale_applied` с числом подписчиков (D13).
- [R2] **Разовое сообщение собрано строкой:** его нельзя пересобрать, и после переключения оно остаётся на старом языке. → Разовые сообщения типизированы (D5). Тест смеси языков открывает страницы в состоянии с InfoBar и ошибкой.
- [R3] **Утечка подписок и поздние события** (§9, §12): Cubit закрыт, а событие языка приходит; переподключение или смена сессии создаёт вторую подписку. → Одна подписка на Cubit в конструкторе, отмена в `close()`, проверка `isClosed`. Тест: `hasListener == false` после `close`, число подписчиков не растёт после переподключения и смены сессии (D9). Подписка принадлежит Cubit-у, а не сессии.
- [R4] **Гонка выбора и записи:** два быстрых выбора, запись старого завершается позже. → Записи идут по очереди, побеждает последний выбор, обогнанная запись не публикует состояние (D2). Тест в D9.
- [R5] **Цена пересчёта:** при смене языка перестраивается вся лента активной сессии. Это один раз на действие пользователя и того же порядка, что пересчёт на новый `SessionView`. Фоновые сессии пересобирают только строки сайдбара. → Приемлемо; заметную задержку видно в `transcript_rendering_flow_test.dart` (`release/*`).
- [R6] **Потеря пользовательского ввода при пересборке:** текст композера, черновик диалога, фокус, прокрутка. → Меняется только `FluentApp.locale`, `FluentApp` не пересоздаётся, поэтому контроллеры и `State` виджетов сохраняются. Точечные тесты в D9.
- [R7] Смесь языков между итерациями. → `system` даёт `en` до итерации 6; явный `Русский` — только для проверки.
- [R8] Регрессия: новый литерал мимо каталога, особенно в параллельных changes. → Правило в `apps/codelab_desktop/AGENTS.md`, тест литералов (D10), сверка в начале каждой итерации экрана.
- [R9] Переполнение раскладки русскими строками. → Тесты на `ru` в узких местах (D8), многоточие с подсказкой в ките.
- [R10] Качество перевода, особенно предупреждений безопасности. → `@description`, вычитка пользователем сообщений с меткой security (D14, Q6).
- [R11] Расхождение `en` с текстом спецификаций. → Эталон `en` = спецификация (D3); существующие тесты на английском это проверяют.
- [R12] Сгенерированный код устарел. → `l10n:check` в `check`, в затронутых проверках при правке ARB и в CI-джобе `l10n` суженного прогона (D3).
- [R13] Конфликт версии `intl` с `flutter_localizations`. → `intl: any` (D3).
- [R14] **Не следуют выбору сразу:** меню macOS и панели ОС (по языку системы), смена языка ОС при `System` (до перезапуска). Перечислено в spec и в документации пользователя (D2, D11).

## Migration Plan

1. Итерация 1 — каркас. Существующее поведение на `en` не меняется. Появляется страница «General», и всё, что уже переведено, переключается на новый язык сразу.
2. Итерации 2–5 — по экранам. Каждая заканчивается зелёными тестами `en`, тестами `ru` и тестом смеси языков своих экранов.
3. Итерация 6 — `system` → `ru` для русской системы, меню macOS, документация, приёмка `settings_language_flow_test.dart` в `release/*`.

Откат: удаление ключа `codelab.app.language` возвращает поведение «по системе». Откат кода — revert итерации; данные пользователя (`profiles.json`, `config.yaml`) change не меняет.

## Решения пользователя 2026-11-18

- **Q1. Когда применяется язык** — сразу, без перезапуска. Пользователь выбрал не рекомендованный вариант (а). Механизм выбран в design: (б) — язык становится явным входом Cubit-ов, у которых в состоянии есть текст; разовые сообщения типизированы (D2, D5). Исключения — меню macOS, панели ОС и смена языка ОС при `System` (D2, D11).
- **Q2. Числа usage** — (а) формат ядра, как в CLI и CSV (D8).
- **Q3. «Debug log» и «Inspector»** — (а) переводятся только заголовки вкладок (D7).
- **Q4. Меню macOS** — (а) `CFBundleLocalizations` и `ru.lproj`, меню по языку системы (D11).
- **Q5. Язык системы не `en` и не `ru`** — (а) английский (D2).
- **Q6. Перевод** — исполнитель по глоссарию `docs/architecture/l10n-glossary.md` («session — сессия», «turn — ход», «approval — одобрение», «prompt — промпт», «tool call — вызов инструмента»); сообщения с меткой security вычитывает пользователь (D14).
- **CI-джоб `l10n`** — `l10n:check` включён в суженный прогон CI на pull request (`tool/ci/ci_scope.dart`) по путям каталогов desktop и кита (D3). Без этого устаревший сгенерированный код вскрывался бы только после merge в `develop`.
- **Повтор записи и сбой чтения** — по итогам ревью итерации 1 дельта spec app-settings «Язык интерфейса app» дополнена: кнопка `Retry` рядом с ошибкой записи (сценарий «Сбой записи» и новый «Повтор записи после сбоя») и запуск на `System` с предупреждением без текста ошибки, если хранилище не прочиталось (новый сценарий «Сбой чтения хранилища»). Реализация — D2, события — D13.
- **Закрытие владельца языка при выходе** — по итогам повторного ревью итерации 1 в change добавлена дельта spec agent-workbench-ui: MODIFIED «Выход из приложения завершает процессы клиента». Закрытие `AppLanguageCubit` — третья параллельная ветвь с ожиданием записи выбора не дольше 3 s; шаг `language` входит в закрытый набор `pending` события `app.exit_timeout` (в `pending` он есть, только если закрытие владельца языка не завершилось к пределу); по истечении 3 s — warning `settings.language_save_timeout {timeout_ms}`; новый сценарий «Запись выбора языка не завершилась к пределу» (D2, D13).
- **Поиск команд хоста в палитре на двух языках** — да. Пользователь закрыл открытый вопрос D4 до задачи 3.3. Команды хоста в палитре ищутся по подписи и описанию на текущем языке и на английском, как настройки по заголовку (D5, п. 8). Команды агента (имена и описания от агента) не переводятся и ищутся как раньше. Поиск по `/команде` (`slashCommand`) работает при любом языке. Механизм — аддитивное поле `HostCommand.searchAliases` в `codelab_client_core` (D4, D6). Поэтому в change добавлена дельта MODIFIED spec acp-client-kit «Каталог команд палитры», а в дельту app-settings «Локализация интерфейса app» — сценарии поиска палитры. Задачи — 3.1 и 3.2 `[client]` (поле и поиск в ядре), 3.3 и 3.4 `[desktop]` (заполнение в app).
- **Каталог кита — `packages/flutter/codelab_ui/lib/src/l10n/`** (вариант (а)): каталог кита — внутренняя реализация, как `strings.dart` (D4) и исключение `l10n/` теста литералов (D10). Путь в spec workspace-architecture «Ядро клиента не зависит от языка интерфейса» исправлен с `lib/l10n/` на `lib/src/l10n/` по коду итерации 1 (задача 1.8); каталог app остаётся в `apps/codelab_desktop/lib/l10n/`.

## Решения пользователя 2026-11-19

- **Вычитка security итерации 3** (задача 3.5) — принято без правок: `workbenchRootSessionTitle`, `workbenchRootSessionBody`, `secretMigrationWarning`, `terminalDisclosure`, `terminalLinkTitle`, `terminalLinkRefusal`.
- **Спорные термины итерации 3** — приняты предложения глоссария: Ledger → «История расхода»; «Перезапустите встроенного агента»; «токены: {tokens}»; «Подключение к агенту потеряно»; «Переписка слишком длинная для модели»; «Агенту не удалось авторизоваться у провайдера модели». `think` → «Обдумывание» и `fetch` → «Загрузка» остаются (`l10n-glossary.md` §4–§6).
- **Пункт перезапуска локального агента в палитре** ищется по видимой подписи `Restart agent` и её описанию, на `ru` — ещё по их английскому тексту. Это исключение из правила «на английском результаты поиска совпадают с прежними» (D4; spec app-settings «Локализация интерфейса app», новый сценарий).
- **Отказ по токену переводится в итерации 3.** Причина хранится типизированно (статус, токен отправлен), текст строится из ARB и пересобирается при смене языка. Прочие ошибки соединения — текст ядра без перевода (D5, п. 1; D6).
- **`SecretMigrationCubit` не подписывается на `AppStrings`** — в его состоянии нет текста, зависящего от языка (D12, задача 3.6).

## Open Questions

Нет.
