Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В каждой итерации сначала одной задачей пишутся красные тесты. Их коммитят отдельно, до кода, и только по явной просьбе пользователя. Затем пишется код. В скобках — сценарий спецификации, решение design.md или риск.

Метки исполнителей (CLAUDE.md, таблица зон):
- `[client]` — `codelab_client_core`;
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, правила сторожа desktop и ядра клиента в `codelab_architecture_tests`, скрипт Melos `l10n:check` и его джоб в `tool/ci/ci_scope.dart`.

Документы `docs/architecture/**` и `openspec/**` пишет `codelab-architect`; `README.md`, `doc/` пакетов и `docs/user/` — `docs-writer`; вложенные `AGENTS.md` — исполнитель итерации вместе с кодом.

Итерации и PR в `develop` (design.md, D12):
- 0 — документы (с итерацией 1);
- 1 — каркас и «General»;
- 2 — кит;
- 3 — рабочее место;
- 4 — настройки I;
- 5 — настройки II;
- 6 — закрытие.

Зависимости: 1 ← 0; 2, 3, 4, 5 ← 1; 3 ← 2 (вкладки дока и строки ленты используют тексты кита); 6 ← 2, 3, 4, 5. Итерации 4 и 5 независимы.

Решения пользователя 2026-11-18 (design.md, «Решения пользователя 2026-11-18»): Q1 — язык применяется сразу, механизм — вариант (б) с типизированными разовыми сообщениями (D2, D5); Q2–Q5 — (а); Q6 — исполнитель по глоссарию, сообщения с меткой security вычитывает пользователь.

Главная защита от смеси языков (D9) — общий тест `expectNoStaleLanguage`. Каждая итерация экрана заканчивается его прогоном на своих экранах и тестом смены языка у каждого Cubit-а с текстом из списка D12.

Проверки каждой задачи — только для затронутого (AGENTS.md §21; полный `melos run check` — по просьбе пользователя и на `release/*`):
- `fvm dart format` изменённых файлов;
- `fvm flutter analyze` / `fvm dart analyze` пакета;
- `fvm flutter test` / `fvm dart test` пакета;
- `fvm dart run melos run l10n:check` — при правке ARB и `l10n.yaml`;
- `fvm dart run melos run guard` — при правке `pubspec.yaml`, импортов и `rules.dart`;
- `fvm dart run melos run web-compile` и `conformance:client` — при правке `codelab_client_core` (итерация 3);
- `fvm dart run melos run test:e2e:cli:dart-agent` — при правке `codelab_client_core` (итерация 3: CLI не меняется, это проверяется);
- `test:e2e:app:*` — только в `release/*`.

## 0. Документы (итерация 0)

- [x] 0.1 OpenSpec change: `proposal.md`, `design.md` (D1–D14, Q1–Q6), дельты `app-settings`, `acp-client-kit`, `workspace-architecture`, `tasks.md`; `openspec validate add-desktop-localization --strict`.
- [x] 0.2 Ответы пользователя на Q1–Q6 — в design.md (раздел «Решения пользователя 2026-11-18»), в D и в дельты. *Итог 2026-11-18:* Q1 — сразу, без перезапуска; механизм (б) выбран в design (D2, D5); D9, D12, D13, риски и spec «Язык интерфейса app» переписаны под мгновенное применение, InfoBar о перезапуске убран; меню macOS и панели ОС — по языку системы (D11). Q2 (а), Q3 (а), Q4 (а), Q5 (а); Q6 — глоссарий и вычитка security пользователем. Open Questions — «Нет».
- [x] 0.3 Архитектурные документы (`codelab-architect`):
  - `technology-stack.md` §1 — строка «Локализация интерфейса» (D1);
  - `layers-and-dependencies.md` — правила D5: три вида текста, язык как явный вход Cubit-а, типизированные разовые сообщения;
  - `state-management.md` и `concurrency.md` — единственный владелец языка `AppLanguageCubit`, подписка `AppStrings` с отменой в `close()` (D2, D5);
  - `error-handling.md` §43 — ссылка на D5 и D6: типизированная причина в ядре, текст в app;
  - `testing.md` — локаль в тестах и интеграционных тестах (D9);
  - `12-4-first-run-and-settings.md` — строка 26 таблицы экранов: «Language» на «General» (D2), абзац §12.4.1 о слое локализации;
  - `agent-parity-goals.md` — D-19: change и статус;
  - новый `docs/architecture/l10n-glossary.md` — глоссарий `ru` (Q6).
- [x] 0.4 `[desktop]` `apps/codelab_desktop/AGENTS.md` — раздел «Локализация»: каталог, ключи, `context.l10n`, `AppStrings` в Cubit-ах с текстом (подписка в конструкторе, отмена в `close()`, пересборка проекции), типизированные разовые сообщения, список Cubit-ов с текстом (D12), запрет склейки, что не переводится, тесты на `en` по умолчанию; правило для параллельных changes (D12). `packages/flutter/codelab_ui/AGENTS.md` §1 и §6 — зависимости `flutter_localizations` и `intl`, фолбэк на английский, тест `ru` у словарей (D4).

## 1. Каркас, единственный источник языка и страница «General» (итерация 1)

- [x] 1.1 `[desktop]` Красные тесты разрешения языка и хранения:
  - `app_locale_test.dart`: `resolveAppLocale` — явный `en`/`ru`; `system` с `ru-RU`, `de-DE`, пустым списком, с `ru` вторым языком; до итерации 6 `system` с `ru-RU` даёт `en` (D2; сценарии «По умолчанию — язык системы», «Незнакомый язык системы», «Явный выбор сильнее системы»);
  - `app_language_preferences_test.dart`: `load()` возвращает `AppLanguageLoad` и не бросает: `en`/`ru`/нет ключа; `fr` и нестроковое значение → `system` и `storedValueInvalid` без перезаписи; сбой открытия хранилища → `system` и `readFailure`; `save(system)` удаляет ключ (сценарии «Незнакомое значение в хранилище», «Сбой чтения хранилища»);
  - `l10n_catalogs_test.dart` (desktop): ключи `en` = `ru`, плейсхолдеры совпадают, у `plural` в `ru` формы `one|few|many|other` (сценарий «Каталоги согласованы»; D3).
- [x] 1.2 `[desktop]` Каталоги и разрешение:
  - `pubspec.yaml` (`flutter_localizations`, `intl: any`, `generate: true`), `l10n.yaml`, `lib/l10n/app_en.arb`, `app_ru.arb`, сгенерированный код, `lib/l10n/l10n.dart` (`context.l10n`);
  - `lib/app/language/app_locale.dart` (`resolveAppLocale`), `lib/core/platform/app_language_preferences.dart` (порт, `AppLanguageLoad` и `SharedPreferencesAppLanguagePreferences` со швом `open`).
- [x] 1.3 `[desktop]` Красные тесты `AppLanguageCubit` и порта `AppStrings` (D2, D9; сценарии «Сбой записи», «Два выбора подряд», «Закрытый компонент не реагирует на смену языка»):
  - начальное состояние из шва, без асинхронной загрузки;
  - `select(ru)` публикует новое состояние синхронно, до завершения записи;
  - сбой записи: язык остаётся, `saveFailed`, событие `settings.language_save_failed {error_class}`;
  - `ru`, затем `en` при незавершённой первой записи: итог `en` в состоянии и в хранилище, обогнанная запись состояние не публикует;
  - после `close` запись не применяется, `changes` закрыт; `close` ставит флаг закрытия первым, закрывает слушателей без ожидания `done` (не виснет на подписчике на паузе), ждёт запись в полёте не дольше `closeWriteTimeout` (3 с) и состояние не публикует;
  - повторный `select` того же значения ждёт идущую запись; после сбоя он повторяет запись;
  - `AppStrings.changes` отдаёт новый `AppLocalizations` ровно один раз на смену языка; повторный выбор того же языка события не даёт;
  - события `settings.language_changed {language, locale}`, `app.locale_applied {locale, subscribers}` (D13).
- [x] 1.4 `[desktop]` `lib/app/language/app_language_cubit.dart` (`AppLanguageCubit`, `AppLanguageState`, порт `AppStrings`), `test/support/app_strings.dart` (`FixedAppStrings`, `TestAppStrings` с `hasListener`; самопроверка — `test/app/language/app_strings_doubles_test.dart`).
- [x] 1.5 `[desktop]` Красные тесты подключения к app:
  - `codelab_app_language_test.dart`: `FluentApp` получает `supportedLocales` = `en`, `ru` и делегаты app и Fluent (делегат кита подключается в 2.3). `locale` берётся из `AppLanguageCubit`; первый кадр на языке шва, без кадра на английском;
  - после `select(ru)` `FluentApp` не пересоздаётся: `State` корневого виджета рабочего места тот же, текст композера и фокус сохранены (сценарий «Ввод пользователя сохраняется»; R6);
  - `CodeLabTestBinding()` даёт `en`, `CodeLabTestBinding(locale: Locale('ru'))` — `ru`; помощник `localizedFluentApp` (D9);
  - помощник `expectNoStaleLanguage` (D9) — самопроверка: экран с одной строкой каталога `en` после переключения на `ru` без пересборки даёт падение, с пересборкой — нет.
- [x] 1.6 `[desktop]` `main.dart`: предпочтение и язык читаются до `runApp` (`load()` не бросает), начальный язык — `AppLanguageStart.fromLoad` (`lib/app/language/app_language_start.dart`: `preference`, `locale` и диагностика чтения; без шва — `AppLanguageStart.fallback`, `system`/`en`). Швы `CodeLabBootstrap(language:)` и `createCodeLabRootScope(language:, languagePreferences:)`; `AppLanguageCubit` singleton и порт `AppStrings` регистрирует модуль `CodeLabLanguageModule` root scope, Cubit закрывается вместе со scope (`CodeLabRootLifecycle.dispose`). `BlocBuilder` над `FluentApp` (`buildWhen` по `locale`). События `app.locale_resolved`, `app.language_preference_invalid` и `app.language_preference_read_failed {error_class}` пишет `CodeLabLanguageModule` логгером `codeLabAppLogger()` после настройки журнала (D13). `test/support/`: параметры `locale`, `languagePreference`, `languageStart`, `languagePreferences` у `CodeLabTestBinding`, `l10n_app.dart`, `l10n_mix.dart` (`expectNoStaleLanguage`). `integration_test/flutter_test_config.dart`: `setUp` кладёт `codelab.app.language = en` в подменённое хранилище `SharedPreferences` (D9; `E2eLaunch` app не запускает и язык задать не может); для `integration_test/` — только `fvm flutter analyze` (§21).
- [x] 1.7 `[desktop]` Красный тест скрипта: `melos run l10n:check` падает на ARB, изменённом без перегенерации (spec workspace-architecture «Устаревший сгенерированный код»). *Итог:* автоматический тест `apps/codelab_desktop/test/tool/l10n_check_test.dart` гоняет `tool/l10n_check.dart --package` на временной копии каталога app: актуальные каталоги проходят, ARB, изменённый без перегенерации, даёт ошибку с именем файла.
- [x] 1.8 `[desktop]` Скрипт Melos `l10n:check` по образцу `prompts:check` (`tool/l10n_check.dart`): генерация во временной копии и сравнение для `codelab_desktop` и `codelab_ui`; скрипт добавлен в `check` (D3). Каталог кита на этом шаге — шаблон с одним сообщением, чтобы скрипт работал на обоих пакетах: `packages/flutter/codelab_ui/l10n.yaml` (`arb-dir: lib/src/l10n`), `lib/src/l10n/codelab_ui_en.arb` и `codelab_ui_ru.arb` (`codeLabApprovalAwaiting`), сгенерированный `CodeLabLocalizations`, зависимости `flutter_localizations` и `intl` в `pubspec.yaml` кита.
- [x] 1.9 `[desktop]` Красные тесты страницы «General» и навигации настроек:
  - `general_page_test.dart`: ключи `settings-general-language`, `settings-language-system|en|ru`, эндонимы. Выбор `Русский` без перезапуска переводит заголовок страницы, навигацию настроек и строку «Language» (сценарий «Смена языка применяется сразу на странице настроек» — критерий D-19). Ошибка сбоя записи показывается на новом языке (сценарий «Сбой записи»); кнопка `Retry` (`settings-language-save-retry`) повторяет запись (сценарий «Повтор записи после сбоя»). `English` возвращает английский (сценарий «Возврат к английскому»). `expectNoStaleLanguage` на экране настроек после переключения;
  - `settings_shell_test.dart`: «General» в `defaultSettingsPages` и в группе «App»; заголовки групп и страниц пересобираются при смене языка.
- [x] 1.10 `[desktop]` `general_page.dart` (читает и вызывает `AppLanguageCubit`, своего Cubit-а нет — D2), запись в `settingsPageBuilders` и `defaultSettingsPages`. `SettingsPage`/`SettingsGroup` без поля `title`, заголовки дают функции presentation `settingsPageTitleOf(l10n, page)` и `settingsGroupTitleOf(l10n, group)` в `features/settings/presentation/settings_titles.dart` (D5, п. 8); `SettingsSearchIndex.search` получает параметром `titlesOf` заголовки на текущем языке и на английском. InfoBar сбоя записи с кнопкой `Retry` (сообщение `settingsLanguageSaveRetry`). Сообщения `en`/`ru` страницы и навигации. Джоб `l10n` (`l10n:check`) в суженном прогоне CI: `tool/ci/ci_scope.dart` по путям каталогов desktop и кита, тест в `codelab_architecture_tests/test/ci_scope_test.dart` (решение пользователя 2026-11-18, D3).

## 2. Кит `codelab_ui` (итерация 2)

- [x] 2.1 `[desktop]` Красные тесты кита:
  - `codelab_l10n_test.dart`: каждый фиксированный словарь (`CodeLabToolCallStatus`, `CodeLabSessionStatus`, `CodeLabConnectionStatus`, `CodeLabConnectionBannerStatus`, `CodeLabApprovalRisk`, тоны вариантов одобрения, `CodeLabPlanEntryPriority`, `CodeLabTurnState`, `ToolPane`) на `ru` с делегатом и на `en` без делегата (сценарии «Тексты кита на русском», «Кит без делегата»; D4);
  - параметры по умолчанию: `CodeLabPromptComposer()` без `placeholder` на `ru` — перевод, с `placeholder: 'X'` — `X`; так же `emptyLabel`, `reconnectLabel`, `actionsLabel`;
  - `l10n_catalogs_test.dart` кита (D3);
  - `ru` без переполнения: строка статуса, теги вызова, кнопки одобрения, навигация настроек при 760 px (D8, R4).
- [x] 2.2 `[desktop]` Кит: каталог `lib/src/l10n/` (`l10n.yaml` и шаблон — из 1.8) дополняется до около 150 сообщений в `codelab_ui_en.arb` и `codelab_ui_ru.arb`, сгенерированный код, `lib/src/l10n/strings.dart` (`codeLabStringsOf`), экспорт `CodeLabLocalizations` из бареля; все литералы `lib/src/**` через каталог; `ToolPane` без поля `label` → `toolPaneTitleOf` (D4); параметры по умолчанию → `String?`; превью — в `en` и один экран превью в `ru`. Уточнения итерации (D4): `CodeLabApprovalPrompt.noSuchOption` и `CodeLabApprovalRisk.label` остаются публичными английскими эталонами, на экране — каталог (`labelOf(context)`); `CodeLabCommandAction.defaults` остаются литералами до 3.4; расширение `expectNoStaleLanguage` каталогом кита перенесено в 3.3/3.4.
- [x] 2.3 `[desktop]` App: делегат кита в `FluentApp` и в `localizedFluentApp` (в итерации 1 не подключён), переход читателей `ToolPane.label` на `toolPaneTitleOf`; тесты desktop зелёные без правки ожидаемых строк.
- [x] 2.4 `[desktop]` Вычитка пользователем сообщений кита с меткой security (D14, R5): `codeLabApprovalAllow`, `codeLabApprovalReject`, `codeLabApprovalScopeOnce`, `codeLabApprovalScopeAlways`, `codeLabApprovalAwaiting`, `codeLabApprovalViewRawInput`, `codeLabApprovalHideRawInput`, `codeLabApprovalNoSuchOption`, `codeLabApprovalToneSafe`, `codeLabApprovalToneReview`, `codeLabApprovalToneRisk`, `codeLabRiskReadOnly`, `codeLabRiskLocalWrite`, `codeLabRiskNetwork`, `codeLabRiskShell`, `codeLabRiskDestructive`, `codeLabRiskUnknown`, `codeLabFileSecretWarning`, `codeLabFileOutsideLink` (метка security добавлена в ходе ревью). *Итог:* решение пользователя 2026-11-18: принято без правок; `codeLabApprovalToneReview` — «Требует проверки» (решение пользователя 2026-11-18); отметки — в `docs/architecture/l10n-glossary.md` §5, §6.

## 3. Рабочее место (итерация 3)

- [ ] 3.1 `[client]` Красные тесты причины заметки в `codelab_client_core`: `turnStopped` с `max_tokens`, `refusal`, `max_turn_requests` с известным и незнакомым лимитом; `emptyTurn` со `stopReason` и без; `detached` и `reconnected` с причинами «агент не восстанавливает» и «не удалось» с id сессии; равенство причины в инкрементальной проекции и проекции с нуля; `text` не изменился (spec acp-client-kit «Типизированная причина заметки транскрипта», все сценарии; D6).
- [ ] 3.2 `[client]` Sealed `NoticeReason` и поле `NoticeItem.reason` (аддитивно), заполнение в `TranscriptProjector`, `ClientWorkspace` (`detach`, восстановление после переподключения), `WorkspaceRestorer`; барель. Проверки: `web-compile`, `conformance:client`, `test:e2e:cli:dart-agent` (CLI без изменений — сценарий «CLI не меняется»).
- [ ] 3.3 `[desktop]` Красные тесты рабочего места на `ru` и `en`:
  - маппер ленты: заметки по `NoticeReason` и `PromptFailure`, метка вызова по `ToolKind`, `other` и субагент — строка агента; ответ агента без изменений (сценарии «Заметка исхода хода на русском», «Ответ агента не переводится»);
  - сайдбар (группы, пустые состояния, «Open folder…», «Settings»), шапка сессии, композер, баннер соединения и экран подключения, InfoBar настройки провайдера и переноса секретов, подтверждение корня диска;
  - палитра: пункты хоста `Files`, `Agents`, `Usage` и их описания; команды агента без изменений;
  - подтверждение перезапуска агента: `plural` на 1, 2, 5 сессий в `ru` (сценарий «Склонение количества»);
  - панель Usage: заголовок `This turn`/`Last turn`, строки Steps/Tokens/Cost/Time, заметка `Couldn't save the file.` — по типизированным значениям application (D5, п. 2); числа — формат ядра (D8);
  - Terminal, Files, Agents: подписи панелей и пустых состояний; содержимое «Debug log» и «Inspector» без перевода (D7);
  - поиск настроек по английскому и переведённому заголовку, `No settings match` на `ru` (MODIFIED «Навигация настроек», новые сценарии); русские ключевые слова страниц (`SettingsSearchIndex.keywords`) — поиск по ключевым словам на любом из двух языков, как требует MODIFIED «Навигация настроек» (решение пользователя 2026-11-18: в итерации 3; после итерации 1 ключевые слова только английские);
  - `expectNoStaleLanguage` учитывает каталог кита (D9; перенесено из итерации 2): самопроверка помощника — экран с видимой строкой кита на `en` (например, «Running» тега вызова) после `select(ru)` даёт падение, с переводом — проходит;
  - палитра: пункты хоста из `CodeLabCommandAction.defaults` (`New session`, `Logs`, `Reconnect` …) и их описания на `ru`, `slashCommand` без изменений; после смены языка каталог команд хоста не возвращает старый язык (D4, R1);
  - **смена языка на живом рабочем месте** (сценарий «Живое рабочее место пересобирается»): ответ агента, вызов `running`, заметки `turnStopped` и `error`, ожидающее одобрение, сайдбар со статусами, баннер потери соединения, открытая палитра, доки Files, Agents, Usage с «Turn budget», Terminal → `select(ru)` → `expectNoStaleLanguage`; уже показанная заметка `turnStopped` перерисована по `NoticeReason`; ответ агента не изменился; затем `en`;
  - открытый диалог подтверждения перезапуска агента пересобирается, `plural` сохраняется;
  - ввод сохраняется: текст композера, прокрутка ленты, фокус; агенту ничего не отправлено (сценарий «Ввод пользователя сохраняется»);
  - Cubit-тесты `ConnectionCubit`, `ActiveSessionCubit`, `SessionsCubit`, `SecretMigrationCubit` и фасада с `TestAppStrings`: смена языка даёт состояние с переводом; кэш ленты и строки статуса не возвращает старый язык; разовые сообщения типизированы; после `close` событие языка не даёт `emit` и `hasListener == false`; после переподключения и смены сессии число подписчиков `AppStrings.changes` не выросло (D5, D9; R1–R3).
- [ ] 3.4 `[desktop]` Реализация: сообщения `workbench`, `usage`, `terminal`, `project_files`, `settings_shell`, `settings_search_index` в ARB; `AppLocalizations` параметром у `ui_mappers`; порт `AppStrings` у Cubit-ов рабочего места с текстом (`ConnectionCubit`, `ActiveSessionCubit`, `SessionsCubit`, `SecretMigrationCubit`) — подписка в конструкторе, пересборка проекции из последних входов, язык в ключе кэша, отмена в `close()`; разовые сообщения — sealed-типы, текст в presentation; типизированные значения из `usage/application` и `terminal/application`, текст в их presentation; события журнала без текста интерфейса (D5, п. 4). Палитра: подписи и описания команд хоста по `id` через `AppLocalizations`, язык — в ключе кэша `_hostCommandsCache`; `CodeLabCommandAction.defaults` в ките не меняется (D4). `test/support/l10n_mix.dart`: кандидаты устаревшего языка — из каталогов app и кита (`codelab_ui_<язык>.arb`), doc-комментарий помощника обновляется.
- [ ] 3.5 `[desktop]` Ревью пользователем переводов app с меткой security этой итерации (подтверждение корня диска, раскрытие вывода терминала) (D14, R5). Строки кита — риски одобрения, кнопки и тоны одобрения, «This file may contain secrets.» — уже вычитаны в 2.4; повторно смотрятся только если меняются.

## 4. Настройки I: Connection и Providers (итерация 4)

- [ ] 4.1 `[desktop]` Красные тесты на `ru` и `en`:
  - «Connection»: строки профилей, метки `Default`/`Current`/`Selected`, бейджи попытки, InfoBar записи `default`, ошибка чтения `profiles.json` с путём плейсхолдером, блок «Behavior»;
  - «Add connection profile»: варианты токена, ошибки черновика по `ProfileDraftIssueCode`, исходы `ProfileCommitter` по варианту, предупреждения `ws://` и «Save anyway», «<NAME> is not set in CodeLab's environment.» с именем плейсхолдером;
  - «Providers» и мастер: источники ключа одним сообщением с плейсхолдерами (нет склейки `'In $backendId as '`), исходы удаления с командой `codelab secret delete <имя>` без изменений (сценарий «Команда в переведённой фразе»), отказы удаления, ошибки записи конфига, InfoBar «Read-only»;
  - Cubit-ы (`ConnectionSettingsCubit`, `AddProfileCubit`, `ProviderSettingsCubit`, `ProviderWizardCubit`) с `FixedAppStrings(AppLocalizationsEn())` — прежние строки; с `TestAppStrings` — смена языка пересобирает производный текст; исходы удаления, ошибки записи конфига и отказы — типизированные сообщения; после `close` событий нет (D5, D9);
  - **смена языка на страницах** «Connection» (с InfoBar записи `default` и с ошибкой чтения `profiles.json`), «Providers» (только чтение; исход удаления), в открытых диалоге «Add connection profile» (черновик и предупреждение `ws://` сохраняются) и мастере провайдера → `expectNoStaleLanguage` (сценарий «Уже показанные ошибки и InfoBar пересобираются»).
- [ ] 4.2 `[desktop]` Реализация: сообщения страниц и диалогов; `AppStrings` у Cubit-ов и `AppLocalizations` параметром у `provider_wizard_view.dart`; разовые сообщения — sealed-типы; перевод `ProfileDraftIssue` по коду (D6).
- [ ] 4.3 `[desktop]` Ревью пользователем переводов с меткой security (`ws://`, токены, секреты) (D14).

## 5. Настройки II: MCP, Agents & modes, Skills (итерация 5)

- [ ] 5.1 `[desktop]` Красные тесты на `ru` и `en`: страница «MCP servers» (таблица «Agent status» — подписи колонок и действий переводятся, ответ `/mcp` в `CodeLabMonospaceBlock` без изменений; InfoBar «Read-only»; ошибки и подтверждения), «Agents & modes», «Skills & extensions»; Cubit-ы `McpSettingsCubit`, `AgentsModesCubit`, `SkillsSettingsCubit` с `FixedAppStrings` и `TestAppStrings` — пересборка, типизированные разовые сообщения, отписка в `close()`; смена языка на трёх страницах в рабочем состоянии и в состоянии с InfoBar и ошибкой → `expectNoStaleLanguage` (D9).
- [ ] 5.2 `[desktop]` Реализация: сообщения трёх страниц, `AppStrings` у Cubit-ов, разовые сообщения — sealed-типы; имена и описания агентов, режимов, навыков и серверов — как есть (D7).

## 6. Закрытие (итерация 6)

- [ ] 6.1 `[desktop]` Красные тесты: `resolveAppLocale(system, [ru-RU])` → `ru` (сценарий «По умолчанию — язык системы»; снять временное правило D2). Итоговый прогон `expectNoStaleLanguage` по всем экранам одним тестом `language_switch_sweep_test.dart`: рабочее место с данными и каждая видимая страница настроек, `en → ru → en`. Сверка списка Cubit-ов с текстом (D12) с кодом: поиск `AppStrings` и литералов в `application/`.
- [ ] 6.2 `[desktop]` Зелёный 6.1; найденные расхождения списка Cubit-ов исправляются здесь же.
- [ ] 6.3 `[desktop]` Красные тесты сторожа: `ui_literals_test.dart` с allowlist (D10, R3); правило `package:intl/` и `package:flutter_localizations/` для `codelab_client_core` и `codelab_client_acp` (spec workspace-architecture «intl в ядре клиента») — тест на временном файле, как остальные тесты `import_guard_test.dart`.
- [ ] 6.4 `[desktop]` Правила в `rules.dart`, `ui_literals_test.dart`, `ui_literals_allowlist.txt`; оставшиеся литералы — в каталог или в allowlist с причиной. Проверка: `melos run guard`.
- [ ] 6.5 `[desktop]` Меню macOS: `CFBundleLocalizations` (`en`, `ru`) в `Info.plist`, `macos/Runner/ru.lproj/MainMenu.strings`, проект Xcode знает локализацию (D11, Q4 (а); сценарий «Меню macOS следует системе»). Проверка — `fvm flutter build macos --debug` и ручной осмотр меню при русской системе; запуск на устройстве — только в `release/*`.
- [ ] 6.6 `[desktop]` Интеграционный тест `integration_test/settings_language_flow_test.dart` (живая сессия → «General» → `Русский` → рабочее место на русском без перезапуска → `English`) и скрипт `test:e2e:app:*` для него. В `feature/*` — только `fvm flutter analyze`; запуск — в `release/*` (§21, D9).
- [ ] 6.7 Документация (`docs-writer`): `docs/user/` — язык интерфейса, «System», мгновенное применение; меню macOS и панели ОС по языку системы; смена языка ОС при «System» — после перезапуска; что не переводится; `README.md` и `doc/` `codelab_ui` — делегат кита и фолбэк; `README.md` desktop — локализация.
- [ ] 6.8 Сверка перед архивацией: тексты `en` всех сообщений, приведённых в спецификациях, совпадают со спецификациями; MODIFIED «Навигация настроек» сверен с текущим текстом `openspec/specs/app-settings/spec.md` (сверено после архивации `add-settings-agents-modes` 2026-11-18; повторить, если до архивации этого change другой change изменит требование); MODIFIED «Выход из приложения завершает процессы клиента» сверен с текущим текстом `openspec/specs/agent-workbench-ui/spec.md` (все прежние сценарии на месте, набор `pending` совпадает с `CodeLabRootLifecycle._shutdownSteps`); статус D-19 в `agent-parity-goals.md`.
