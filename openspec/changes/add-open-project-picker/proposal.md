## Why

Working directory ("проект") сегодня выбирается текстовым полем внутри одноразового диалога "Configure connection" — как будто это часть настройки транспорта. Это не соответствует ни протоколу, ни реальной архитектуре: `AcpClientApplication.createSession()` уже читает `cwd` **в момент создания сессии** и шлёт его как параметр `session/new` ([shell_cubit.dart:655-657](../../../apps/codelab_app/lib/features/workbench/application/shell_cubit.dart#L655)) — то есть ACP моделирует `cwd` как свойство **сессии**, а не подключения. У WebSocket-транспорта поля working directory нет вообще (`_WebSocketTransportFields` содержит только Endpoint/Token) — значит `cwd` удалённой сессии сегодня тихо падает на `WorkingDirectoryProvider.currentPath`, то есть на директорию процесса самого CodeLab, что для удалённого агента бессмысленно.

Все три сопоставимых desktop ACP/agent-клиента — Claude Code Desktop, Codex Desktop (OpenAI), OpenCode Desktop — трактуют выбор проекта/папки как первоклассное, независимое от типа подключения действие, привязанное к созданию единицы работы (сессии/таба), а не к настройке транспорта. Claude Code Desktop показывает "Project folder" отдельным pill-селектором в композере перед первым сообщением; Codex Desktop — отдельным действием на стартовом экране, до любого коннекта; OpenCode Desktop привязывает выбор проекта к созданию таба/сессии через нативный OS folder picker. Ни один из них не прячет это в connection settings.

## What Changes

- Working directory ("проект") становится независимым от транспорта, session-level выбором с собственным UI-affordance "Open Project" в сайдбаре сессий — а не полем формы подключения.
- "Open Project" предоставляет: (a) выбор через нативный OS folder picker, (b) список недавно открытых проектов (recents), персистентный между запусками приложения.
- Выбранный проект применяется к следующей создаваемой сессии одинаково для stdio и WebSocket транспортов — закрывает существующий пробел, при котором WebSocket-сессии вообще не могли задать working directory.
- Поле "Working directory" удаляется из диалога "Configure connection".
- Для stdio добавляется явный переключатель "Run agent from project directory" (по умолчанию включён) в диалоге "Configure connection" — вместо того чтобы одно и то же значение молча управляло и логическим `cwd` ACP-сессии, и OS-уровневой рабочей директорией спавна процесса агента (`Process.start(workingDirectory:)`), эта связка становится явным, видимым решением. Выключение переключателя не убирает выбранный проект — он по-прежнему передаётся в `session/new`; выключение только отвязывает `cwd` спавна процесса агента от проекта.
- Персистентность recents — новая для проекта задача: сегодня в CodeLab вообще нет механизма локального хранения между запусками (ширины панелей явно документированы как непереживающие рестарт). Требует введения одной новой утверждённой технологии — простого key-value local storage (например, `shared_preferences`) — и, для нативного пикера, `file_selector` (официальный Flutter-плагин с точно такой же ролью, как `dialog.showOpenDialog` у OpenCode Desktop). Оба — единственные технологии для своей задачи, вводятся впервые и требуют архитектурного решения (см. design.md).
- **BREAKING**: нет для существующих пользователей в рамках одного запуска — но поведение по умолчанию меняется: если раньше working directory нужно было вручную вписать в диалог подключения, теперь по умолчанию (без выбора проекта) сессии продолжают создаваться с `WorkingDirectoryProvider.currentPath`, как и раньше; явный выбор проекта — новая опция, не обязательная для сохранения текущего поведения без изменений в привычках пользователя.

## Capabilities

### New Capabilities

_(нет — расширяется существующая capability)_

### Modified Capabilities

- `agent-workbench-ui`: уточняет требование "Connection profile is edited in a modal dialog" (working directory больше не входит в форму подключения; добавляется stdio-only toggle "Run agent from project directory") и добавляет новые требования: project selection независим от транспорта, "Open Project" picker (native browse + recents), recents переживают перезапуск приложения.

## Impact

- `apps/codelab_app/lib/features/workbench/presentation/widgets/transport_setup_panel.dart` — убрать поле "Working directory" из `_StdioTransportFields`, добавить toggle "Run agent from project directory".
- `apps/codelab_app/lib/features/workbench/presentation/widgets/` — новый widget "Open Project" popover (recents + browse), новая точка входа в сайдбаре сессий рядом с "+ New session".
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — отделить `_selectedCwd`/`state.stdioCwd` от `_stdioConfigFromState().cwd` (spawn-cwd процесса, управляется отдельным bool-полем state, по умолчанию `true`); ввести project-selection state, применяемое к `CreateSessionCommand.cwd` независимо от транспорта.
- `apps/codelab_app/lib/core/platform/` — новый adapter для нативного folder picker (`file_selector`) и новый adapter/repository для recents persistence (`shared_preferences`), по паттерну существующего `WorkingDirectoryProvider`.
- `apps/codelab_app/pubspec.yaml` — новые зависимости `file_selector`, `shared_preferences` (или эквивалент), требуют явного архитектурного решения (design.md) как впервые вводимые технологии для persistence/platform file access.
- Дизайн-референс (не часть кода): canvas "CodeLab Working Directory UX" и артборд "OpenProject" в "CodeLab UI/UX Reference" — визуальная основа для этого change.
