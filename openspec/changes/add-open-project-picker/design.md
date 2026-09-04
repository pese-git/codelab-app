## Context

`state.stdioCwd` сегодня управляет одновременно двумя разными вещами через `_stdioConfigFromState()` ([shell_cubit.dart:1171-1183](../../../apps/codelab_app/lib/features/workbench/application/shell_cubit.dart#L1171)):

1. `cwd`, отправляемый в `session/new` (логический working directory ACP-сессии — что агент считает "проектом");
2. `StdioAcpTransportConfig.cwd`, который транспорт передаёт как `Process.start(workingDirectory:)` — OS-уровневая рабочая директория самого процесса агента.

Оба смысла сегодня живут в ОДНОМ текстовом поле "Working directory" внутри диалога "Configure connection", видимом только для stdio-транспорта. У WebSocket-транспорта (`_WebSocketTransportFields`) поля working directory нет вовсе — `_selectedCwd` в этом случае всегда падает на `WorkingDirectoryProvider.currentPath` (директория процесса CodeLab), что не имеет отношения к тому, чем реально управляет удалённый агент.

При этом `createSession()` читает `_selectedCwd` **в момент вызова**, а не один раз при подключении — то есть `cwd` уже сегодня семантически привязан к моменту создания сессии, а не к подключению. UI просто не отражает это.

**Явное решение по этому change**: working directory — session-level, transport-independent концепция ("проект"), выбирается через отдельный "Open Project" affordance, а не через форму подключения. Spawn-cwd процесса агента (актуально только для stdio) остаётся отдельной, явно управляемой опцией, а не побочным эффектом того же поля.

## Goals / Non-Goals

**Goals:**
- Выбор проекта (working directory сессии) не зависит от типа транспорта и работает одинаково для stdio и WebSocket.
- Recents (недавно открытые проекты) переживают перезапуск приложения.
- Нативный OS folder picker вместо самодельного file browser (тот же принцип, что у OpenCode Desktop через `dialog.showOpenDialog`).
- Spawn-cwd процесса локального stdio-агента остаётся управляемым, но явно, отдельным переключателем, а не скрытой связкой с working directory.
- Удаление working directory field из диалога "Configure connection" не ломает текущее поведение по умолчанию (без выбранного проекта сессии по-прежнему создаются с `WorkingDirectoryProvider.currentPath`).

**Non-Goals:**
- Не проектируется multi-root/multiple-projects-per-session (как `--add-dir` у Codex CLI) — вне рамок этого change.
- Не меняется `fs/read_text_file`/`fs/write_text_file` working-directory containment (`add-acp-fs-client-support`) — тот механизм по-прежнему резолвит путь относительно `session.cwd`, откуда бы он ни был выбран.
- Не вводится синхронизация recents между устройствами/аккаунтами — только локальное хранение на этой машине.
- Не проектируется отдельный "стартовый экран" в духе Codex Desktop (start a chat / create a project / open a folder) — "Open Project" остаётся частью существующего workbench, привязанным к сайдбару сессий, а не отдельным экраном до входа в workbench.

## Decisions

### 1. Working directory — новое, отдельное от `AcpClientApplication`/transport-конфигурации, application-state поле в `CodeLabShellState`

`state.stdioCwd` перестаёт быть источником `cwd` для `session/new`. Вводится новое поле `state.selectedProjectPath` (nullable `String`), независимое от `transportType`. `createSession()` использует `selectedProjectPath ?? _workingDirectoryProvider.currentPath` вместо сегодняшнего `_selectedCwd`.

- Альтернатива (отклонена): хранить проект как часть `AcpTransport`/`StdioAcpTransportConfig`. Отклонена — противоречит уже реальной ACP-семантике (`cwd` — параметр `session/new`, не `initialize`/transport-level), и не решает проблему WebSocket.

### 2. `state.stdioCwd` остаётся, но переименовывается по смыслу в spawn-cwd override, используется только для `StdioAcpTransportConfig.cwd`

Поле в state, ранее называвшееся "working directory" в UI, остаётся как internal source для `Process.start(workingDirectory:)`, но:
- по умолчанию (`state.runAgentFromProjectDirectory == true`) `_stdioConfigFromState()` использует `selectedProjectPath ?? WorkingDirectoryProvider.currentPath` как spawn-cwd — то есть поведение "по умолчанию совпадает с выбранным проектом" сохраняется без явных действий пользователя;
- при `runAgentFromProjectDirectory == false` spawn-cwd остаётся `null` (наследуется от процесса CodeLab, как сегодня ведёт себя `Process.start` без `workingDirectory`) — редкий, продвинутый случай (агенту нужна другая cwd, отличная от открытого проекта).

Это делает существующую неявную связку явной, не убирая её как поведение по умолчанию.

- Альтернатива (отклонена): полностью развести project directory и spawn-cwd на два независимых текстовых поля. Отклонена — для 99% локальных агентов они совпадают; отдельное текстовое поле для редкого случая добавляло бы постоянный UI-шум ради экономии одного переключателя.

### 3. Нативный folder picker — `file_selector` (официальный Flutter-плагин)

`file_selector` — плагин команды Flutter (не сторонний), предоставляет `getDirectoryPath()` на всех трёх desktop-платформах через нативные диалоги ОС (`NSOpenPanel` на macOS, common file dialog на Windows, GTK/portal на Linux) — тот же принцип, что `dialog.showOpenDialog` у OpenCode Desktop (Electron). Изолируется за новым узким портом в `apps/codelab_app/lib/core/platform/`, по образцу `WorkingDirectoryProvider`:

```dart
abstract interface class ProjectFolderPicker {
  Future<String?> pickFolder({String? initialDirectory});
}
```

- Альтернатива (отклонена): писать собственный in-app file browser (Flutter widget поверх `dart:io Directory.list()`). Отклонена явно — прямое нарушение принципа "используй нативный OS-пикер, не изобретай свой" (вывод из исследования всех трёх конкурентов; OpenCode Desktop — самый явный пример).

### 4. Персистентность recents — `shared_preferences` (первое введение persistence-технологии в проект)

В проекте сегодня нет НИ ОДНОГО механизма локального хранения между запусками — это первое такое решение, требующее явного архитектурного решения по `AGENTS.md §4`. `shared_preferences` — официальный Flutter-плагин команды Flutter, простейшее решение задачи "небольшой список строк переживает рестарт" (recents — не более ~10 путей + timestamp). Хранится за новым портом:

```dart
abstract interface class RecentProjectsStore {
  Future<List<RecentProject>> load();
  Future<void> record(String path);
}
```

- Альтернатива (отклонена): `hive`/`sqflite`/файл в app support directory вручную. Отклонены как избыточные для задачи "список из ≤10 строк" — `shared_preferences` уже официально поддержан Flutter-командой, не требует схемы/миграций, и это единственная задача persistence в проекте на сегодня (нет других данных, которые оправдывали бы более тяжёлое решение).
- Формат хранения: один JSON-массив `[{path, lastOpenedAt}]` под одним ключом — не список разрозненных ключей (упрощает атомарную запись и версионирование формата в будущем).

### 5. "Open Project" — новый organism-виджет в `acp_ui`, а не встроенная в `codelab_app` разметка

По аналогии с `AcpSessionSidebar` (уже existing organism в `acp_ui`), новый popover — `AcpProjectPicker` (или аналогичное имя) в `packages/flutter/acp_ui/lib/src/organisms/`, принимающий `currentProjectPath`, `recentProjects`, `onProjectSelected`, `onBrowseRequested` — сам НЕ обращается к `file_selector`/`shared_preferences` напрямую (widgets не создают platform adapters, `AGENTS.md §6`/§7). Вызов `onBrowseRequested` делегируется `CodeLabShellCubit`, которая уже владеет platform-портами.

- Альтернатива (отклонена): встроить popover прямо в `apps/codelab_app`, без переиспользуемого organism. Отклонена — `AcpSessionSidebar`, рядом с которым появляется этот popover, уже живёт в `acp_ui`; несогласованность слоя нарушала бы уже установленный паттерн (`AGENTS.md §14`).

## Risks / Trade-offs

- [Первое введение persistence-зависимости — расширяет утверждённый technology stack] → задокументировано здесь как явное архитектурное решение (design.md), затрагивает `docs/architecture/technology-stack.md` (требует правки в рамках задач этого change) — не остаётся тихим расхождением между документацией и кодом.
- [`file_selector` на Linux зависит от доступности xdg-desktop-portal/GTK — может не работать одинаково на всех Linux-окружениях] → deferred: плагин уже официально поддерживает Linux desktop как target-платформу проекта (`docs/architecture/technology-stack.md`); специфика конкретных Linux DE — за пределами этого change, как и для остального Linux-специфичного кода (`docs/architecture/platform-integration.md §45`).
- [Разделение project directory и spawn-cwd на два переключаемых состояния может запутать пользователя, ожидающего одного поля "working directory", как раньше] → смягчается: по умолчанию (`runAgentFromProjectDirectory == true`) поведение идентично сегодняшнему неявному совпадению; toggle виден только когда открыт диалог подключения для stdio, не добавляет постоянного UI-шума.
- [`selectedProjectPath` не persisted как часть текущей активной сессии — если приложение перезапущено с активным подключением, что происходит с уже созданными сессиями] → вне рамок этого change: существующие сессии продолжают жить с тем `cwd`, который был передан при их `session/new`; `selectedProjectPath` влияет только на СЛЕДУЮЩУЮ создаваемую сессию, как и сегодняшний `_selectedCwd`.
