## Исполнители

- `[agent]` — `codelab_setup`, `codelab_embedded` (мосты агентской стороны);
- `[client]` — `codelab_client_core`, `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`;
- `[protocol]` — задач нет: ACP, модели и фикстуры не меняются (design.md, D8).

TDD (`packages/dart/codelab_agent_core/AGENTS.md` §2): красный тест — отдельная задача и отдельный коммит до кода (коммит — только по просьбе пользователя). Задача реализации ссылается на свой красный тест.

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` или `fvm flutter analyze` пакета;
- тесты пакета;
- `web-compile` — при правке основных барелей `codelab_setup` и `codelab_embedded`;
- `guard` — при правке `rules.dart`;
- `l10n:check` — при правке ARB;
- `test:e2e:cli:dart-agent` — при правке `apps/codelab_cli`.

Интеграционный тест app в `feature/*` только компилируется.

## 0. Документы

- [x] 0.1 `[desktop]` `12-4-first-run-and-settings.md` §12.4.9:
  - строка «General (26)»: подмножество строк реестра и таблица классификации (D2), цель `user` (D4), порядок блоков по артборду (D17), «Reopen the last project» (D9), «About» без канала и подписи (D11);
  - фраза «Language — первое содержимое страницы» заменяется порядком D17;
  - строка `codelab.input.enter_while_running` — «появится с change steering (C-03)».

  `12-3-desktop-display.md` A11 — та же пометка о строке «General».
- [x] 0.2 `[desktop]` `docs/architecture/l10n-glossary.md` — термины D15 (подраздел «Страница «General»» §4).
- [x] 0.3 Документы change `add-file-preview-and-tree`: задача 3.4, требование «Игнорируемые записи по `.gitignore`» и Migration Plan — порт `FileBrowserPreferences`, владелец значения `ShowIgnoredFilesCubit` в root scope, строка «General» пишет то же значение (D10). Сделано при подготовке этого change.

## 1. Итерация 1 — правила правки в мосте

- [x] 1.1 `[agent]` Красный: `packages/dart/codelab_setup/test/views/setting_edit_rules_test.dart` на снимках настоящего `FileAgentConfigStore` (`support/real_home.dart`). Сценарии client-agent-setup «Правила правки строк настроек агента»:
  - «Порядок веток» — секрет из окружения;
  - «Источник config»;
  - «Замаскированное значение» с маркером `sk-test-leak-…` (нет в `toString()` отказа и строки);
  - «Обычный ключ можно править»;
  - неизвестный ключ и ключ `fileOnly` — `UnknownSetting`;
  - `trusted_projects` — `TrustBoundarySetting`.
- [x] 1.2 `[agent]` Реализация 1.1: `lib/src/views/setting_edit_rules.dart` (D6), экспорт из основного бареля; web-smoke (`test/web_smoke/main.dart`) вызывает `settingEditRefusalOf`. `packages/dart/codelab_setup/AGENTS.md` §1 — строка о правилах. 1.1 зелёный, `web-compile` зелёный.
- [x] 1.3 `[client]` Красный: `apps/codelab_cli/test/setup/settings_rows_test.dart` — сценарий «Тексты CLI не меняются»: все четыре текста отказа `/settings` для каждой ветки `SettingEditRefusal` побайтно, в том числе источники `config` и `env`.
- [x] 1.4 `[client]` Реализация 1.3: `settings_rows.dart` строит тексты по ветке моста, удаляет `isTrustBoundary`, `isSecretKey`, `isExternalSource`. `settingWriteLayerOf` и `applySetting` не меняются (D6). 1.3 и прежние тесты `/settings` REPL и TUI зелёные, `test:e2e:cli:dart-agent` зелёный.

## 2. Итерация 2 — блок «Agent defaults»

- [x] 2.1 `[desktop]` Красный: `test/features/settings/application/agent_defaults_rows_test.dart` (требование «…доступ и строки», сценарий «Новый ключ реестра без решения»; D2, D5):
  - каждый ключ `SettingsRegistry.all` со `scope: shared` есть в таблице классификации;
  - у каждого ключа `general` тип из набора редакторов D5;
  - английские сообщения ARB подписи и описания совпадают с `label` и `description` реестра;
  - группировка Budget, Agent, Subagents, Logging и порядок реестра внутри группы.
- [x] 2.2 `[desktop]` Реализация 2.1: `features/settings/application/agent_defaults_rows.dart`, сообщения подписей ключей в `app_en.arb` и `app_ru.arb`. 2.1 зелёный, `l10n:check` зелёный.
- [x] 2.3 `[desktop]` Красный: `test/features/settings/application/agent_defaults_cubit_test.dart` на настоящем `FileAgentConfigStore` во временной папке (`test/support/modes_fixture.dart`). Требования «…доступ и строки» и «…запись», все сценарии данных:
  - «Строки из своего подмножества», «WebSocket-агент» (локальный файл не читается), «Битый конфиг»;
  - «Смена лимита шагов», «Неверное число» (значения нет в подсказке и событиях), «Ключ с перезапуском», «Перекрытие проектным файлом», «Значение из окружения», «Сброс поля», «Конфликт записи», «Смена подключения во время записи»;
  - поздний снимок после `reload`, смены папки фокуса и `close()` — `agent_defaults.load_discarded`;
  - правка во время новой загрузки — `save_failed` с `outcome: stale`;
  - повторная правка во время `saving` игнорируется;
  - события «Запись без значения в журнале».
- [x] 2.4 `[desktop]` Реализация 2.3: `AgentDefaultsCubit`, `AgentDefaultsState` (D7), фабрика `CodeLabDependencies.createAgentDefaultsCubit` в `lib/app/app_scope.dart` на `ProviderSettingsOpener`. 2.3 зелёный.
- [x] 2.5 `[desktop]` Красный: `test/features/settings/presentation/general_page_test.dart` на Cubit-двойнике:
  - сценарий «Порядок блоков» (без «About» до итерации 5) и «Поиск по ключевому слову»;
  - ключи `settings-general-*` требования «…доступ и строки»;
  - редакторы по типу;
  - пометка `(applies after restart)`;
  - подписи отказов;
  - баннеры записи на `en` и `ru`;
  - InfoBar `settings-general-shared-info` с `~/.codelab` (`homePathLabel`);
  - строка «Language» и её ключи не изменились (существующие тесты языка зелёные);
  - `expectNoStaleLanguage` для страницы с баннером;
  - русская раскладка без переполнения при 760 px.
- [x] 2.6 `[desktop]` Реализация 2.5: блоки в `general_page.dart` (строка «Language» без изменений), ключевые слова «General» в `en` и `ru` (после решения пользователя 2026-11-19 — в ARB, задачи 6.4 и 6.5), сообщения ARB. 2.5 зелёный, `l10n:check` зелёный.

## 3. Итерация 3 — «Reopen the last project and its tabs»

- [x] 3.1 `[client]` Красный: `packages/dart/codelab_client_core/test/restore/workspace_restorer_test.dart` и `test/workspace/client_workspace_restore_test.dart` — сценарии acp-client-kit «Старт без восстановления рабочего пространства»:
  - «Снимок не восстанавливается» — `session/load` нет, сессий снимка в списке нет;
  - «Снимок пишется по ходу работы»;
  - повторный и перекрёстный вызовы `restoreProject` и `startWithoutRestore` — пустая операция.
- [x] 3.2 `[client]` Реализация 3.1: `ClientWorkspace.startWithoutRestore()`, `WorkspaceRestorer.skip()` (запись разрешена, `_restoring` пуст, снимок не читается; D9). Фейки `ClientWorkspace` в тестах app и CLI получают метод. 3.1 зелёный.
- [x] 3.3 `[desktop]` Красный: `test/core/platform/startup_preferences_test.dart` — `load` не бросает (сбой хранилища и небулево значение дают `true` и признак), `save(true)` удаляет ключ, `save(false)` пишет `false`. `test/features/workbench/application/settings_cubit_startup_test.dart` — сценарии app-settings «Открытие последнего проекта при запуске»:
  - «По умолчанию проект прошлого запуска открывается»;
  - «Выключено — старт без проекта» (проект не выбран, `startOnLaunch` агента не стартует, `startWithoutRestore` вызван ровно раз);
  - «Выключено — снимок нового запуска пишется»;
  - сбой чтения — как при включённом, событие `app.reopen_last_project_unreadable`;
  - `app.reopen_last_project_skipped`.
- [x] 3.4 `[desktop]` Реализация 3.3: `core/platform/startup_preferences.dart` (`StartupPreferences`, `SharedPreferencesStartupPreferences`), `SettingsCubit._restoreProject` читает порт до восстановления, привязка в `app_scope.dart`, шов `createCodeLabRootScope(startupPreferences:)`. 3.3 зелёный.
- [x] 3.5 `[desktop]` Красный: `test/features/settings/application/startup_settings_cubit_test.dart` и дополнение `general_page_test.dart` — строка `settings-general-reopen-last-project`, сценарий «Переключение не трогает текущую работу», сбой записи с «Retry» (`settings-general-reopen-last-project-retry`), событие `settings.reopen_last_project_changed`.
- [x] 3.6 `[desktop]` Реализация 3.5: `StartupSettingsCubit`, строка в блоке «Startup and files», ARB. 3.5 зелёный.

## 4. Итерация 4 — «Show ignored files» (после итерации 3 `add-file-preview-and-tree`)

- [ ] 4.1 `[desktop]` Красный: дополнение `general_page_test.dart` и `test/features/project_files/project_files_pane_test.dart` — сценарий «Одна настройка на две точки»: переключение на «General» меняет `ShowIgnoredFilesCubit`, переключатель `file-tree-show-ignored` открытой панели и приглушённую `build`. Без привязки `ProjectFiles` строки нет.
- [ ] 4.2 `[desktop]` Реализация 4.1: строка `settings-general-show-ignored` поверх `ShowIgnoredFilesCubit` (вводит задача 3.4 `add-file-preview-and-tree`), ARB. 4.1 зелёный.

## 5. Итерация 5 — «About»

- [x] 5.1 `[agent]` Красный: `packages/dart/codelab_embedded/test/embedded_agent_version_test.dart` — сценарий embedded-agent «Константа совпадает с agentInfo» (сценарный открыватель, `initialize`); web-smoke читает константу.
- [x] 5.2 `[agent]` Реализация 5.1: экспорт `embeddedAgentVersion` из `lib/codelab_embedded.dart`, строка в `packages/dart/codelab_embedded/AGENTS.md`. 5.1 зелёный, `web-compile` зелёный.
- [x] 5.3 `[desktop]` Красный: `test/app/build_version_test.dart` — `codelabDesktopVersion` равен `version` из `pubspec.yaml`, `kCodeLabReleaseNotesUrl` начинается с `repoUrl` из `site/src/site.config.ts`. `test/app/legal_assets_test.dart` — сценарии licensing-and-attribution «Копия разошлась с корнем» и «Строка лицензии из ресурса». `test/core/platform/build_info_test.dart` — отображение `Abi` и ОС на `macOS arm64`, `Linux x64`, `Windows x64`.
- [x] 5.4 `[desktop]` Реализация 5.3: `lib/app/build_version.dart`, `core/platform/build_info.dart`, `assets/legal/` и раздел `flutter: assets:` в `pubspec.yaml`. 5.3 зелёный.
- [x] 5.5 `[desktop]` Красный: `packages/dart/codelab_architecture_tests/test/import_guard_test.dart` — `dart:ffi` в `apps/codelab_desktop/lib` вне `lib/core/platform/build_info.dart` запрещён (D1).
- [x] 5.6 `[desktop]` Реализация 5.5: правило в `test/support/rules.dart`. 5.5 зелёный, `guard` зелёный.
- [x] 5.7 `[desktop]` Красный: `test/features/settings/application/about_diagnostics_test.dart` — сценарии app-settings «Ничего лишнего в буфере» (маркеры в URL, id профиля, папке проекта, `CODELAB_HOME`, окружении) и «Текст не зависит от языка». Все поля из перечня требования для каждого вида подключения и доступа.
- [x] 5.8 `[desktop]` Реализация 5.7: `about_diagnostics.dart` (`AboutInfo`, `DiagnosticsContext`, `diagnosticsReportOf`), сборка `AboutInfo` в `app_scope.dart`. 5.7 зелёный.
- [x] 5.9 `[desktop]` Красный: дополнение `general_page_test.dart` на `FakeExternalLinkOpener`, `FakeLocalFolderOpener` и двойнике буфера обмена:
  - сценарии «Версии в заголовке», «Сторонние уведомления офлайн», «Release notes через порт», «Каталог журналов не открылся»;
  - «Copy diagnostics» и `Diagnostics copied.`;
  - InfoBar `settings-general-about-updates`;
  - нет строк «Channel» и «Signed by»;
  - события `settings.about_action`;
  - `expectNoStaleLanguage` с открытым «About» и диалогом уведомлений.
- [x] 5.10 `[desktop]` Реализация 5.9: раздел «About» (`Expander`), диалог `settings-general-third-party-dialog` (markdown `codelab_ui` и `LicenseRegistry`), ARB. 5.9 зелёный, `l10n:check` зелёный.

## 6. Документация и приёмка

- [x] 6.1 `[desktop]` `apps/codelab_desktop/AGENTS.md` — раздел «Страница «General»»:
  - `AgentDefaultsCubit`, `StartupSettingsCubit`, классификация ключей и тест полноты (D2);
  - цель `user` (D4);
  - `StartupPreferences` и `startWithoutRestore` (D9);
  - владелец `show_ignored` (D10);
  - источники «About» и правило `dart:ffi` (D1, D11);
  - диагностика по белому списку (D12);
  - копии `assets/legal/` (D13);
  - события (D16).
- [x] 6.2 `[desktop]` `docs-writer`: `apps/codelab_desktop/doc/user-guide.md` (раздел о странице «General»: умолчания агента, запуск без прошлого проекта, «About», что копирует «Copy diagnostics») и `docs/user/configuration.md` (умолчания агента правятся и в app, запись в `$CODELAB_HOME/config.yaml`).
- [x] 6.3 `[desktop]` Сверка §12.4.9, A11 и D17 с кодом, `openspec validate add-app-general-page --strict`, проверки затронутого (§21) по итерациям.
- [x] 6.4 `[desktop]` Красный: ключевые слова поиска настроек в ARB (решение пользователя 2026-11-19; design.md D15; заменяет D5 п. 8 `add-desktop-localization` в редакции 2026-11-18). `test/features/settings/application/settings_search_index_test.dart` и тест оболочки настроек:
  - сценарии app-settings «Навигация настроек» change `add-desktop-localization`: «Русское ключевое слово при русском интерфейсе» (`токен` → `settings-nav-connection`), «Английское ключевое слово при русском интерфейсе» (`token` → `settings-nav-connection`), «Русское ключевое слово при английском интерфейсе» (`токен` → `No settings match "токен"`);
  - сценарий этого change «Русское ключевое слово «General» зависит от языка интерфейса» (`сжатие`);
  - у каждой видимой страницы есть `settingsSearchKeywords<Page>` в `app_en.arb` и `app_ru.arb`, ни одно слово после разбиения по запятой не пусто;
  - прежние английские ключевые слова всех страниц находят свою страницу на обоих языках, слова одной страницы не находят другую (`restart`, `token`, `profile`).
- [ ] 6.5 `[desktop]` Реализация 6.4: сообщения `settingsSearchKeywords<Page>` для всех страниц, `SettingsSearchIndex.search(visible, query, titlesOf:, localizedKeywordsOf:)` без статического `keywords`, `SettingsShell` передаёт слова языка интерфейса и английские (`AppLocalizationsEn`). 6.4 зелёный, `l10n:check` зелёный.
