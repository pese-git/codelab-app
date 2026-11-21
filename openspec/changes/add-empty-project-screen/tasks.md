## Исполнители

- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, правило сторожа app в `packages/dart/codelab_architecture_tests`.
- `[client]` — задач нет: `codelab_client_core`, `codelab_client_io`, `codelab_client_acp` не меняются (порт вида пути — в app, design.md D4).
- `[protocol]` — задач нет: ACP, модели и фикстуры не меняются.
- `[agent]` — задач нет: ядро, мосты `codelab_setup` и `codelab_embedded` не меняются.
- `[site]` — задач нет: руководство app публикуется сайтом без копий, его проверяет джоб `site` в CI.

Задачи документации без метки выполняет `codelab-architect` (`docs/architecture/`, `AGENTS.md`) или `docs-writer` (продуктовые документы) — исполнитель указан в задаче.

TDD (`packages/dart/codelab_agent_core/AGENTS.md` §2): красный тест — отдельная задача до кода. Коммит красного теста — отдельно и только по просьбе пользователя. Задача реализации ссылается на свой красный тест.

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21):
- `fvm dart format` изменённых файлов;
- `fvm flutter analyze` в `apps/codelab_desktop` и `packages/flutter/codelab_ui`;
- тесты изменённых файлов;
- `guard` — при правке `rules.dart` и `pubspec.yaml`;
- `l10n:check` — при правке ARB;
- `test:e2e:cli:dart-agent` и `web-compile` не нужны: клиентский слой и web-безопасные пакеты не меняются.

Тесты с настоящей файловой системой — обычные `test`, не `testWidgets`: настоящий IO внутри fake-async зоны зависает (`apps/codelab_desktop/AGENTS.md`, «Тесты»).

## 0. Документы и решения

- [x] 0.0 Пользователь ответил на Q1–Q6 design.md. `codelab-architect` закрепил ответы в design.md (раздел «Решения пользователя») и, если ответ меняет поведение, — в spec этого change.
- [x] 0.1 `codelab-architect`: `docs/architecture/platform-integration.md` §37 «Drag and drop» — правило app: адаптер `OsDropRegion` в `core/platform/`, список путей → application (`SettingsCubit.openDroppedPaths`), вид пути — порт `LocalPathKindOf`; ограничения macOS (песочница), Windows (UIPI), Linux (GTK). Ссылка на design.md D3, D4.
- [x] 0.2 `codelab-architect`: `12-3-desktop-display.md` §12.3.6 — строка `desktop_drop`: решение принято change `add-empty-project-screen`, D-12 переиспользует адаптер; `delivery-roadmap.md` — пункт «новые зависимости десктопа»: `desktop_drop` решён (после 1.1), `pasteboard` остаётся до D-12.
- [x] 0.3 `codelab-architect`: `docs/architecture/l10n-glossary.md` — «перетащить / бросить папку», «зона перетаскивания», «проект не выбран», «агент не запущен» (предложение; вычитка `ru` — задача 6.3).

## 1. Ворота зависимости

- [x] 1.1 `[desktop]` Проверка `desktop_drop` по `technology-stack.md` §24–§25 (design.md D3, пп. 1–6). Шаги:
  - проверить, есть ли в Flutter 3.47 API приёма внешнего перетаскивания;
  - проверить лицензию пакета и транзитивных пакетов, платформы, нативную регистрацию на macOS, Windows и Linux, сопровождение;
  - выбрать версию для точного пина;
  - собрать пустую интеграцию локально (`fvm flutter build macos --debug`; Linux и Windows — CI-сборкой ветки).

  Итог — новый §20и `technology-stack.md` и строка таблицы стека (выполняет `codelab-architect` по отчёту). Отказ останавливает итерацию 5, дальше — по ответу Q2.

  Итог 2026-11-22: ворота пройдены, пин `0.8.4`, `dbus` 0.7.15 (MPL-2.0, Linux) допущен решением пользователя; §20и и строка таблицы записаны. Открытые issues пакета не просмотрены — остаток закрывают 5.4 (CI трёх ОС) и 5.5.

## 2. Кит `codelab_ui`

- [x] 2.1 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_open_project_screen_test.dart`. Spec agent-workbench-ui «Экран без выбранного проекта»: ключи и тексты шести блоков из параметров; `onOpen` и `onOpenSettings` вызываются нажатием; `dropActive: true` — рамка акцента; `dropMessage` — текст с тоном `warning` и иконкой; без `dropMessage` — `dropLabel` и `dropHint`; тёмная тема и окно 800×600 — без переполнения (сценарий «Тёмная тема и низкое окно»); семантика кнопки и ссылки (design.md D1, D10).
- [x] 2.2 `[desktop]` Реализация 2.1: `lib/src/organisms/codelab_open_project_screen.dart`, экспорт в `organisms.dart`, пример в `codelab_organism_previews.dart` на `en` и на `ru` в тёмной теме. Комментарий `CodeLabStartScreen` больше не упоминает `Open a project to start a session.` 2.1 зелёный.
- [x] 2.3 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_session_sidebar_test.dart` (новый или дополнить существующий тест сайдбара). Spec «Sessions sidebar grouped by project», сценарии «No projects yet» и «Open folder… follows the project groups»: пустой `projects` → `No recent projects yet.`; «Open folder…» (`openFolderKey`) — после последней группы внутри списка и до «Settings»; `openFolderShortcut` виден справа; компактный вид без подсказки. Тест каталога на `ru` в `codelab_l10n_test.dart` — строка `codeLabSidebarNoRecentProjects` (design.md D9, D11).
- [x] 2.4 `[desktop]` Реализация 2.3: параметры `openFolderShortcut`, `noProjectsLabel`, перенос пункта; `codeLabSidebarNoRecentProjects` в `lib/src/l10n/codelab_ui_en.arb` и `_ru.arb`, сгенерированный код. 2.3 зелёный, `l10n:check` зелёный.
- [x] 2.5 `[desktop]` Красный: тест `CodeLabAppBar` в `packages/flutter/codelab_ui/test/` — `connectionLabel` заменяет подпись бейджа и не добавляет «Connect»; `null` — прежние подписи по статусу (spec «App bar…», сценарий «Badge before the agent starts»; design.md D8).
- [x] 2.6 `[desktop]` Реализация 2.5: параметр `connectionLabel` в `codelab_app_bar.dart`. 2.5 зелёный.
- [x] 2.7 `[desktop]` Красный: `codelab_shortcuts_test.dart` — запись `openFolder` в группе `global` после `newSession`, `capsFor`/`compactFor` (`⌘O`, `Ctrl+O`); `codelab_shortcut_bindings_test.dart` — Ctrl+O и ⌘O вызывают `CodeLabWorkbenchShortcuts.onOpenFolder`; `shortcut_catalog_guard_test.dart` не меняется и остаётся зелёным (spec «Cmd/Ctrl+O открывает выбор папки»; design.md D7).
- [x] 2.8 `[desktop]` Реализация 2.7: `CodeLabShortcut.openFolder`, `onOpenFolder` в `codelab_workbench_shortcuts.dart`. 2.7 зелёный.
- [x] 2.9 `[desktop]` `packages/flutter/codelab_ui/AGENTS.md` — `CodeLabOpenProjectScreen` в §3 и §4 (только раскладка; перетаскивание принимает app), параметры сайдбара и `connectionLabel`.

## 3. Application app

- [ ] 3.1 `[desktop]` Красный: `apps/codelab_desktop/test/core/platform/local_path_kind_test.dart` (обычный `test`, временный каталог): папка → `directory`; файл → `file`; несуществующий путь → `missing`; ссылка на папку → `directory`; битая ссылка → `missing`; ошибка проверки → `other`, без исключения наружу (design.md D4).
- [ ] 3.2 `[desktop]` Реализация 3.1: `lib/core/platform/local_path_kind.dart` (`LocalPathKind`, `LocalPathKindOf`, `ioLocalPathKind`). 3.1 зелёный.
- [ ] 3.3 `[desktop]` Красный: `apps/codelab_desktop/test/features/workbench/application/project_drop_test.dart` (`SettingsCubit` с фейковым `LocalPathKindOf`, `ProjectFolderPicker`, `RecentProjectsStore`; связка `bindProjectStart` — фейк триггера). Spec «Открытие папки перетаскиванием»:
  - «Брошенная папка открывает проект»: `selectProject`, недавние, триггер вызван один раз, событие `project.drop {outcome: opened, count: 1}`;
  - «Файл отклоняется», «Несколько элементов отклоняются» (вид не запрашивается), «Пропавший путь», «Элемент без локального пути» (`null`, пустая строка, `other`): `dropRejection` нужного типа, триггер не вызван, диагностика `warning`/`project` с текстом spec, событие без пути;
  - «Выделение зоны и сброс отказа» — часть application: `clearDropRejection()` и `selectProject` снимают отказ;
  - «Другой выбор во время проверки»: бросок с незавершённым `kindOf`, затем `browseForProject` → проект второго выбора, отказа нет, триггер один раз;
  - бросок во время восстановления проекта: бросок побеждает;
  - `close()` во время проверки — ничего не выбрано;
  - «Символическая ссылка на папку»: путь не раскрыт (design.md D4);
  - «Пакет macOS принимается как папка»: вид `directory` у `/Applications/Foo.app` — проект выбран (решение Q5 (а)).
- [ ] 3.4 `[desktop]` Реализация 3.3: `SettingsCubit.openDroppedPaths`, `clearDropRejection`, `ProjectDropRejection` (sealed) в `settings_cubit.dart` или отдельном `project_drop.dart` рядом; `_projectIntent`; конструктор принимает `LocalPathKindOf`. 3.3 зелёный.
- [ ] 3.5 `[desktop]` Красный: в `project_drop_test.dart` или `create_session_project_test.dart` — «Второй запрос при открытом диалоге»: пока `pickFolder` не завершён, второй `browseForProject` и «New session» без проекта (`SessionsCubit`) не вызывают порт второй раз; после выбора папки обе ветки видят один проект (design.md D7).
- [ ] 3.6 `[desktop]` Реализация 3.5: общий незавершённый `Future` выбора в `browseForProject`. 3.5 зелёный; `project_required_test.dart`, `missing_project_folder_test.dart`, `agent_starts_itself_test.dart`, `settings_cubit_startup_test.dart` зелёные без правок (регрессия `require-project-folder`).
- [ ] 3.7 `[desktop]` Красный: тест `ShellState`/`CodeLabShellCubit` (`test/features/workbench/application/`):
  - `awaitingProject` истинно только без проекта при `idle`/`disconnected`;
  - `transportKind` для встроенного, stdio и WebSocket профиля;
  - `dropRejection` проходит из `SettingsState`;
  - фасад вызывает `openDroppedPaths` и `clearDropRejection`;
  - сценарий «Badge after a folder is chosen»: после выбора папки `awaitingProject` ложно (design.md D5, D8).
- [ ] 3.8 `[desktop]` Реализация 3.7: поля и геттер в `shell_state.dart`, `ProfileTransportKind`, проброс в `shell_cubit.dart`, `SettingsOpenSource.startScreen` в `navigation_cubit.dart`, шов `localPathKind:` в `createCodeLabRootScope` и привязка в `app_scope.dart` (по образцу `directoryExists`). 3.7 зелёный.

## 4. Presentation app, сочетание, страница «Keyboard»

- [ ] 4.1 `[desktop]` Красный: `apps/codelab_desktop/test/features/workbench/presentation/open_project_screen_test.dart` (`CodeLabTestBinding`). Spec «Экран без выбранного проекта»:
  - «Встроенный агент без проекта» (`stdioDefault: false`, Linux): тексты, `Ctrl+O`, InfoBar с `Ctrl+N`, открыватель не вызван;
  - «Профиль stdio»: нет `--token` и `abc`, фраза внешнего агента;
  - «Профиль WebSocket»: адрес без userinfo, пути и query, `Connects…`;
  - «Подсказки на macOS» (`debugDefaultTargetPlatformOverride`);
  - «Ссылка на настройки подключения»: открыта «Connection», событие `settings.opened {source: start_screen}`;
  - «Отмена выбора папки»;
  - «Проект выбран»: `start-new-session`, нет `open-project-drop-zone`.

  Вызов колбэков найденного `OsDropRegion`: «Брошенная папка открывает проект» (до агента — фейк `LocalPathKindOf`), «Файл отклоняется» (текст в `open-project-drop-message`), «Выделение зоны и сброс отказа». Обновить `agent_start_screens_test.dart`: текст `Open a project to start a session.` заменён экраном 11a, ключ `start-open-project` прежний (design.md D1, D2, D5, D6).
- [ ] 4.2 `[desktop]` Реализация 4.1: `features/workbench/presentation/widgets/open_project_screen.dart` (`WorkbenchOpenProjectScreen`, функции текстов `projectDropRejectionText`, `openProjectDescriptionOf`, `agentCardDetailOf`), ветка `project == null` в `main_pane.dart`; ARB `workbenchOpenProject*` в `app_en.arb`/`app_ru.arb` (с `@description`, эталон `en` = spec), удаление `workbenchOpenProjectHint`, `fvm flutter gen-l10n`. 4.1 зелёный, `l10n:check` зелёный, `ui_literals_test` зелёный.
- [ ] 4.3 `[desktop]` Красный: `workbench_shell_test.dart`:
  - бейдж `No project · agent not started` с подсказкой (сценарий «Badge before the agent starts»);
  - после выбора папки — статус соединения («Badge after a folder is chosen»);
  - сайдбар «No projects yet» с `Ctrl+O`;
  - Ctrl+O без проекта и ⌘O с проектом вызывают порт выбора папки («Ctrl+O без проекта», «⌘O во время хода в другом проекте» — ход продолжается, открыватель повторно не вызван);
  - «Сочетание в настройках» — порт не вызван.
- [ ] 4.4 `[desktop]` Реализация 4.3: `connectionLabel`, `openFolderShortcut`, `onOpenFolder: cubit.browseForProject` в `workbench_shell.dart`; ARB `workbenchBadgeNoProject*`. 4.3 зелёный.
- [x] 4.5 `[desktop]` Красный: `test/features/settings/presentation/keyboard_page_test.dart` и `keyboard_page_l10n_test.dart` — spec app-settings «Страница «Keyboard»: строки таблицы»: 21 строка на Linux, «Строка «Open folder»», «Поиск строки «Open folder»», «Сочетаний без поведения нет» без `O`; `keyboard_bindings_test.dart` — нажатие Ctrl+O и ⌘O на рабочем месте вызывает выбор папки (spec «Сочетания app и страница «Keyboard» не расходятся»).
- [x] 4.6 `[desktop]` Реализация 4.5: ветки `openFolder` в `keyboardShortcutActionOf`, `keyboardShortcutWhereOf`, `keyboardShortcutGroupOf` (`presentation/keyboard_page.dart`), ARB `settingsKeyboardActionOpenFolder` (`en`/`ru`). 4.5 зелёный. Проверить, что `macos/Runner/Base.lproj/MainMenu.xib` не содержит пункта с ⌘O (design.md D7).

## 5. Адаптер, плагин, сторож

- [ ] 5.1 `[desktop]` Красный: сторож — `packages/dart/codelab_architecture_tests` (проверка правила в `import_guard_test.dart` по образцу правила `system_theme`): импорт `package:desktop_drop/` вне `apps/codelab_desktop/lib/core/platform/os_drop_region.dart` — нарушение; в адаптере — нет (spec workspace-architecture «Плагин перетаскивания из ОС только в адаптере платформы», оба сценария; design.md D12).
- [ ] 5.2 `[desktop]` Реализация 5.1: `PackageRule` в `test/support/rules.dart` с комментарием по-русски (почему, ссылка на D3). 5.1 зелёный, `melos run guard` зелёный.
- [ ] 5.3 `[desktop]` Красный: `apps/codelab_desktop/test/core/platform/os_drop_region_test.dart` — события плагина (вход, выход, бросок с путями, элемент с пустым путём) переводятся в `onEntered`, `onExited`, `onDropped([..., null])`. События подаются через канал плагина в `TestDefaultBinaryMessenger` или публичные типы событий, если пакет их даёт (design.md D3).
- [ ] 5.4 `[desktop]` Реализация 5.3: зависимость `desktop_drop` с точным пином из 1.1 в `apps/codelab_desktop/pubspec.yaml` (комментарий со ссылкой на D3 и §20и), `melos bootstrap`, `lib/core/platform/os_drop_region.dart`; `WorkbenchOpenProjectScreen` оборачивает организм в `OsDropRegion`. 5.3 и 4.1 зелёные; `fvm flutter analyze` и `guard` зелёные; сборка `fvm flutter build macos --debug` локально, Linux и Windows — CI.
- [ ] 5.5 `[desktop]` Ручная проверка запущенного app на macOS разработчиком (не прогон `test:e2e:app:*` и не условие merge в `develop`): Finder → папка открывается и агент стартует; файл, две папки и `.app` дают ожидаемый исход; тёмная тема сверена с `ProjectsEmpty-dark`. Windows и Linux — ручная проверка в `release/<version>` (корневой `AGENTS.md` §21). Итог записать в описание PR.

## 6. Документация

- [ ] 6.1 `codelab-architect`: `apps/codelab_desktop/AGENTS.md` — раздел «Экран без проекта»: организм и ключи, `OsDropRegion` — единственный импорт `desktop_drop`, `LocalPathKindOf`, правило «вид пути решает `SettingsCubit`», `ProjectDropRejection`, поздний результат, `project.drop` без путей, Cmd/Ctrl+O, `SettingsOpenSource.startScreen`; ссылка на D1–D12.
- [ ] 6.2 `docs-writer`: `apps/codelab_desktop/README.md` (шаги первого запуска: экран «Open a project», перетаскивание папки, Ctrl+O) и `apps/codelab_desktop/doc/user-guide.md`:
  - раздел «Первый запуск» — новый экран, карточка агента, отказы перетаскивания, ограничение UIPI на Windows;
  - раздел о проектах в сайдбаре — «Open folder…» в конце списка «Projects», `No recent projects yet.`, Ctrl+O;
  - список сочетаний, если он есть в руководстве.

  Снимок `doc/images/first-launch-no-project.png` и `sidebar-projects.png` переснять или убрать ссылку, если снимок сделать нельзя. Стандарт — `.claude/skills/codelab-docs/SKILL.md`.
- [ ] 6.3 Вычитка `ru` новых строк ARB app и кита пользователем по `l10n-glossary.md` (отказы перетаскивания и текст о границе папки — метка `security` в `@description`).
- [ ] 6.4 `openspec validate add-empty-project-screen --strict` зелёный; проверки затронутого по §21 перечислены в описании PR, полный `melos run check` не запускался (если пользователь не попросил).
