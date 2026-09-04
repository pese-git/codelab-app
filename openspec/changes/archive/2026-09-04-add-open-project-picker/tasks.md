## 1. Application state (shell_cubit)

- [x] 1.1 Добавить `selectedProjectPath: String?` в `CodeLabShellState`, независимое от `transportType`/`stdioCwd`
- [x] 1.2 Добавить `runAgentFromProjectDirectory: bool` (default `true`) в `CodeLabShellState`
- [x] 1.3 Изменить `createSession()`: использовать `selectedProjectPath ?? _workingDirectoryProvider.currentPath` вместо `_selectedCwd`, независимо от `transportType`
- [x] 1.4 Изменить `_stdioConfigFromState()`: `cwd` = `runAgentFromProjectDirectory ? (selectedProjectPath ?? _workingDirectoryProvider.currentPath) : null`
- [x] 1.5 Добавить методы `selectProject(String path)`, `toggleRunAgentFromProjectDirectory(bool value)` в `CodeLabShellCubit`
- [x] 1.6 Убедиться, что `state.stdioCwd`-поле и связанный с ним текстовый ввод удалены из state/UI (заменены на `selectedProjectPath` + toggle)

## 2. Platform adapters

- [x] 2.1 Добавить зависимость `file_selector` в `apps/codelab_app/pubspec.yaml`
- [x] 2.2 Добавить зависимость `shared_preferences` в `apps/codelab_app/pubspec.yaml`
- [x] 2.3 Создать `abstract interface class ProjectFolderPicker { Future<String?> pickFolder({String? initialDirectory}); }` в `apps/codelab_app/lib/core/platform/project_folder_picker.dart`
- [x] 2.4 Реализовать `FileSelectorProjectFolderPicker` (обёртка над `file_selector`'s `getDirectoryPath()`)
- [x] 2.5 Создать `abstract interface class RecentProjectsStore { Future<List<RecentProject>> load(); Future<void> record(String path); }` и модель `RecentProject { path, lastOpenedAt }`
- [x] 2.6 Реализовать `SharedPreferencesRecentProjectsStore` — один JSON-массив под одним ключом, ограничение по количеству записей (см. design.md decision 4)

## 3. UI — acp_ui organism

- [x] 3.1 Создать `AcpProjectPicker` organism в `packages/flutter/acp_ui/lib/src/organisms/` — принимает `currentProjectPath`, `recentProjects`, `onProjectSelected`, `onBrowseRequested`; сам не обращается к platform adapters
- [x] 3.2 Добавить "Open Project" row над списком сессий в месте использования `AcpSessionSidebar` (или расширить сам `AcpSessionSidebar` необязательным слотом) — открывает `AcpProjectPicker` popover
- [x] 3.3 Экспортировать `AcpProjectPicker` через `organisms.dart`/`acp_ui.dart`

## 4. UI — codelab_app wiring

- [x] 4.1 Удалить поле "Working directory" из `_StdioTransportFields` (`transport_setup_panel.dart`)
- [x] 4.2 Добавить toggle "Run agent from project directory" в `_StdioTransportFields`, привязанный к `state.runAgentFromProjectDirectory`/`cubit.toggleRunAgentFromProjectDirectory`
- [x] 4.3 Подключить `AcpProjectPicker` в workbench-виджете, где рендерится сайдбар сессий, передав `cubit.selectProject`/browse-callback

## 5. Dependency injection (CherryPick)

- [x] 5.1 Забиндить `ProjectFolderPicker`/`RecentProjectsStore` в `CodeLabPlatformModule` (по образцу `WorkingDirectoryProvider`)
- [x] 5.2 Прокинуть их в `CodeLabShellCubit` через конструктор/модуль, регенерировать cherrypick codegen

## 6. Тесты

- [x] 6.1 Unit-тест: `createSession()` шлёт `selectedProjectPath` как `cwd` независимо от `transportType` (stdio и WebSocket)
- [x] 6.2 Unit-тест: без выбранного проекта `cwd` падает на `WorkingDirectoryProvider.currentPath`, как и раньше
- [x] 6.3 Unit-тест: `_stdioConfigFromState().cwd` следует `runAgentFromProjectDirectory` (true → совпадает с проектом, false → `null`)
- [x] 6.4 Widget-тест: `AcpProjectPicker` показывает recents, вызывает `onProjectSelected` при клике по recent-элементу, вызывает `onBrowseRequested` при клике "Browse for folder…"
- [x] 6.5 Тест `SharedPreferencesRecentProjectsStore`: `record()` затем `load()` возвращает записанный путь; превышение лимита отбрасывает наименее недавние записи

## 7. Документация

- [x] 7.1 Обновить `docs/architecture/technology-stack.md`: добавить `file_selector` и `shared_preferences` как утверждённые технологии для platform file access / local persistence
- [x] 7.2 Обновить `docs/architecture/platform-integration.md`, если появляется новый паттерн, не покрытый существующими примерами (folder picker + local persistence adapter)

## 8. Проверка

- [x] 8.1 `fvm dart run melos run format`
- [x] 8.2 `fvm dart run melos run analyze`
- [x] 8.3 `fvm dart run melos run test`
