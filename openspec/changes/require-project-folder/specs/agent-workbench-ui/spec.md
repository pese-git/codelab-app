## MODIFIED Requirements

### Requirement: Project selection is independent of the connection type
CodeLab SHALL let the user select the working directory ("project") for sessions as an action independent of the connection profile, and SHALL apply the currently selected project to the next session created regardless of whether the window's profile is the embedded agent, stdio or WebSocket. A project is selected only explicitly: via "Open folder…", a recent project, or the project restored from the previous run's workspace snapshot. CodeLab SHALL NOT substitute the CodeLab process's own current directory (or any other implicit directory) for a project that has not been selected; without a selected project there is no directory for an agent or a session (requirement «Без выбранного проекта нет папки агента и сессий»; design.md change `require-project-folder`, D1, replacing Decision 1 of change `add-open-project-picker`). Whether a stdio agent process starts in its process root (the directory of the trigger that started it) SHALL be the `Run in the project folder` field of that stdio profile (`runInProjectDirectory`, default on in the "Add connection profile" dialog), not a separate workbench toggle (design.md change `add-app-settings-shell`, D6).

#### Scenario: Project applies to a WebSocket session
- **WHEN** the window's profile is a WebSocket profile and the user creates a new session
- **THEN** CodeLab sends the currently selected project's path as `cwd` in `session/new`, the same as it would for stdio

#### Scenario: No project selected — no implicit directory
- **WHEN** CodeLab was launched with the process working directory `/`, there is no workspace snapshot, and the user has not selected a project
- **THEN** no `session/new` is sent, no agent process, embedded agent or WebSocket connection is started, and `WorkspaceState.projectDirectory` stays unset, so the next workspace snapshot does not record `/` as the project

#### Scenario: Switching project keeps the agent and other sessions running
- **WHEN** the agent runs with a session in `/work/a` that is in a turn, and the user selects the project `/work/b`
- **THEN** the agent is not restarted, the turn in `/work/a` continues, the sidebar lists `/work/b`'s sessions from `session/list`, and the next session created gets `cwd` `/work/b`

#### Scenario: stdio process runs from the project directory by default
- **WHEN** the window's profile is a stdio profile with `Run in the project folder` on, and the agent is started by selecting the project `/work/app`
- **THEN** CodeLab spawns the agent process with `/work/app` as its OS-level working directory

#### Scenario: stdio process spawn directory can be decoupled from the project
- **WHEN** the window's profile is a stdio profile with `Run in the project folder` off
- **THEN** CodeLab spawns the agent process without an explicit working directory override, while each session's directory is still sent as `cwd` in `session/new`

#### Scenario: Test connection without a selected project
- **WHEN** no project is selected and the user presses "Test connection" for a stdio profile with `Run in the project folder` on (in the "Add connection profile" dialog or in a profile row)
- **THEN** CodeLab runs the check with the agent process started without an explicit working directory override, as with `Run in the project folder` off; the check sends only `initialize`, and no `session/new` is sent (design.md change `require-project-folder`, D7)

### Requirement: Workbench restores sessions after reconnect and restart
After "Restart agent" (or "Reconnect" for WebSocket), the workbench SHALL reload the open sessions so the active session's transcript matches the agent's replay; a session the agent cannot restore SHALL be shown as "detached" with a notice in its transcript, and prompts to it SHALL fail without reaching the agent. After an app restart, the workbench SHALL select the project from the previous run, which starts the agent (requirement «Агент стартует сам»); on that first start it SHALL list the project's sessions and load the previously active session if its `cwd` is the snapshot's project. A previously active session with another `cwd` SHALL NOT be loaded automatically: it stays a "not loaded" row that the user can open explicitly. When the agent cannot restore the active session, the workbench SHALL start a new session in the project with a notice explaining why. A previous-run project that is a filesystem root (for example `/`, written by versions that substituted the process directory for an unselected project) SHALL NOT be selected: the workbench SHALL record a warning diagnostic, start without a project and without an agent, as it does for a previous-run project whose folder no longer exists (design.md change `require-project-folder`, D10, D16, D19).

#### Scenario: Reconnect reloads the active session
- **WHEN** a session with a finished turn is active and the user presses "Restart agent" with an agent that supports `session/load`
- **THEN** after the restart the active session shows the same transcript, rebuilt from the agent's replay

#### Scenario: Restart restores the previous session
- **WHEN** the user restarts the app after working in a session in `/work/app`
- **THEN** `/work/app` is the selected project, the agent starts in `/work/app` without any Connect action, the previously active session is loaded with its transcript, and the sidebar lists the project's sessions

#### Scenario: The agent cannot restore sessions
- **WHEN** after a restart the window's agent has no `loadSession`
- **THEN** the workbench starts a new session in the previous project and its transcript shows "The agent cannot restore sessions; a new session was started."

#### Scenario: Snapshot project at the filesystem root is not restored
- **WHEN** the workspace snapshot of the previous run has `projectDirectory` `/` and an active open session with `cwd` `/`, and the app starts
- **THEN** no project is selected, no agent is started, a warning diagnostic names the reason, and after the user selects a project the snapshot's sessions are neither loaded nor written to the next snapshot

#### Scenario: Active session with root cwd under a real project
- **WHEN** the workspace snapshot has `projectDirectory` `/work/app` and the active open session `s2` with `cwd` `/`, and the app starts
- **THEN** `/work/app` is the selected project, the agent starts in `/work/app`, no `session/load` or `session/new` is sent for `s2`, `s2` is listed as "not loaded", and the session pane shows the start screen; selecting `s2` asks for confirmation (requirement «Подтверждение открытия сессии в корне диска») and, after `Open`, loads it with `cwd` `/` without restarting the agent

### Requirement: Selecting a not-loaded session restores its transcript
Focusing a session that is not loaded in the current connection — "not loaded" or "detached" — SHALL start the window's agent if it is not running (requirement «Агент стартует сам»), load the session via `session/load` with the session's own `cwd`, and make it the active session with the transcript replayed by the agent. A running agent SHALL NOT be restarted for this, whatever the session's directory. If starting the agent or loading fails, the previously active session SHALL stay active, the sidebar row SHALL keep its status, and the failure SHALL be recorded as a diagnostic.

#### Scenario: Loading a session from the sidebar
- **WHEN** the user selects a "not loaded" session
- **THEN** the session becomes active and its transcript shows the user prompts and agent replies the agent replayed

#### Scenario: Loading fails
- **WHEN** the agent answers `session/load` with an error
- **THEN** the active session does not change, the sidebar row keeps its status, and a diagnostic records the failure

#### Scenario: Session of another folder loads into the running agent
- **WHEN** the agent runs with process root `/work/a`, a turn is running in a session of `/work/a`, and the user selects a "detached" session with `cwd` `/work/b`
- **THEN** the agent is not restarted, the turn in `/work/a` continues, and the session is loaded via `session/load` with `cwd` `/work/b`, becomes active and accepts prompts again

### Requirement: Empty session after connecting
Without a session in focus, the session pane SHALL show a start screen instead of a connection screen: without a selected project — the text `Open a project to start a session.` and "Open folder…" (key `start-open-project`); with a selected project — `Start a new session in <folder name>.` and "New session" (key `start-new-session`), with the progress text `Starting <profile title>…` while the agent starts. When a session is in focus and has no transcript items and the agent runs, the session pane SHALL show an empty state inviting the user to send the first message. When starting the agent fails, the session pane SHALL show the failure reason with "Retry", which repeats the intent that started the agent, and "Connection settings". The workbench SHALL NOT offer a Connect action (design.md change `require-project-folder`, D18).

#### Scenario: New session while connected
- **WHEN** the agent runs and the user creates a new session
- **THEN** the session pane shows the empty state with the composer focused, and no Connect button

#### Scenario: Start screen without a project
- **WHEN** no project is selected and no session is in focus
- **THEN** the session pane shows `Open a project to start a session.` and "Open folder…" (`start-open-project`), and no Connect button

#### Scenario: Start screen with a project
- **WHEN** the project `/work/app` is selected and no session is in focus
- **THEN** the session pane shows `Start a new session in app.` and "New session" (`start-new-session`); pressing it creates a session with `cwd` `/work/app`

#### Scenario: Agent start fails
- **WHEN** the user selects a project with the embedded agent and an invalid `config.yaml`
- **THEN** the session pane shows the config problems and "Retry"; after the config is fixed, "Retry" (or any other start trigger) starts it

## ADDED Requirements

### Requirement: Без выбранного проекта нет папки агента и сессий
Агент (процесс stdio, встроенный агент, соединение WebSocket) и сессия в desktop SHALL получать папку только из выбранного проекта или из `cwd` существующей сессии (требование «Project selection is independent of the connection type»; design.md change `require-project-folder`, D1, D2, D3, D5, D9).

- **«New session» без проекта** НЕ SHALL создавать сессию, НЕ SHALL запускать агента и НЕ SHALL отправлять агенту сообщений. Вместо этого она SHALL открывать системный выбор папки, как «Open folder…». Выбранная папка становится проектом (это триггер старта агента), а сессия автоматически не создаётся.
- **Папки нет на диске.** Если папка триггера локального профиля (встроенный агент, stdio) исчезла, агент для неё НЕ SHALL запускаться, а сессия НЕ SHALL создаваться или загружаться. Причина `Project folder not found: <path>. Choose an existing folder with Open folder….` SHALL попадать в диагностику уровня `error` с источником `project`.
- **Ожидание восстановления.** Пока проект прошлого запуска восстанавливается, «Connect», «Reconnect» и «New session» SHALL ждать его не дольше 2 с; статус `connecting` / `reconnecting` ставится до ожидания. Если после ожидания проекта нет, подключение SHALL отклоняться до обращения к workspace с диагностикой `Open a project before connecting: choose a folder with Open folder….` и событием `connection.connect_rejected {reason: no_project, profile_id}` без пути, а «New session» SHALL открывать выбор папки (design.md change `require-project-folder`, D3). В итоговой модели без кнопки Connect правило действует для триггеров старта агента.
- **Одна папка на намерение.** Намерение (выбор проекта, новая сессия, фокус, перезапуск) SHALL читать папку один раз. Проверка существования, старт агента и `session/new` / `session/load` SHALL получать одно и то же значение.
- **Встроенный агент** без папки SHALL не открываться: резолвер отказывает `ClientWorkspaceException`, не вызывая открыватель.

#### Scenario: New session без проекта открывает выбор папки
- **WHEN** проект не выбран, и пользователь нажимает «New session» в сайдбаре
- **THEN** открывается системный выбор папки, агенту ничего не отправлено, сессия не создана; после выбора папки `/work/app` она становится выбранным проектом, агент стартует в `/work/app`, а сессий не прибавилось

#### Scenario: Исчезнувшая папка сессии
- **WHEN** агент работает, и пользователь выбирает сессию `notLoaded` с `cwd` `/work/gone`, которой нет на диске, а профиль окна — встроенный агент
- **THEN** `session/load` не отправлен, агент не перезапущен, активная сессия не меняется, диагностика содержит `Project folder not found: /work/gone.`

#### Scenario: Проект сменили во время проверки папки
- **WHEN** выбран проект `/work/a`, пользователь нажимает «New session», и пока идёт проверка существования `/work/a`, выбирает проект `/work/b`
- **THEN** сессия этого намерения получает `cwd` `/work/a` — ту же папку, что проверялась; `/work/b` применяется к следующему «New session»

#### Scenario: Действие во время восстановления проекта
- **WHEN** проект `/work/app` из снимка ещё восстанавливается, и пользователь нажимает «Connect»
- **THEN** статус сразу `connecting`, подключение ждёт восстановления и идёт с папкой `/work/app`; отказа «нет проекта» нет

#### Scenario: Восстановление не завершилось за таймаут
- **WHEN** чтение снимка зависло дольше 2 с, проект не выбран, и пользователь нажал «Connect»
- **THEN** подключение отклонено до обращения к workspace, диагностика содержит `Open a project before connecting: choose a folder with Open folder….`, журнал — `connection.connect_rejected` с `reason: no_project` и `profile_id`, без пути

#### Scenario: Встроенный резолвер без папки
- **WHEN** `EmbeddedTransportResolver.open` вызван с пустой папкой
- **THEN** он завершается `ClientWorkspaceException`, а открыватель встроенного агента не вызывается

### Requirement: Агент стартует сам
Отдельного шага подключения в рабочем месте НЕ SHALL быть. Агент профиля окна SHALL стартовать, если он не работает (в том числе после сбоя старта), на одном из триггеров (design.md change `require-project-folder`, D11–D17):
1. выбор проекта — «Open folder…», недавний проект, проект, восстановленный при запуске;
2. «New session» в выбранном проекте;
3. фокус на сессии `notLoaded` или `detached`;
4. «Retry» экрана или баннера сбоя.

Агент стартует в папке триггера — она становится корнем процесса. Выбор проекта НЕ SHALL создавать сессию. Если агент уже работает, выбор проекта SHALL сразу запрашивать `session/list` нового проекта, без перезапуска.

- **Один агент на окно, любые папки.** Агент SHALL обслуживать сессии любых папок, передавая каждой её `cwd`. Смена проекта, фокус и создание сессии другой папки НЕ SHALL перезапускать агента и НЕ SHALL прерывать ходы других сессий.
- **Единственный перезапуск** — «Restart agent» / «Reconnect» с подтверждением при работе в сессиях (spec app-settings «Блок «Behavior» страницы «Connection»»).
- **После сбоя** любой триггер SHALL снова пытаться стартовать агента. Без действия пользователя (или восстановления проекта при запуске) попытки НЕ SHALL начинаться: таймеров и автоповторов нет. Сбой с тем же профилем, корнем процесса и текстом, что предыдущий, НЕ SHALL добавлять новую запись в диагностику; экран сбоя SHALL показывать `Failed again (<n>)`, журнал — `connection.start_failed {profile_id, repeat}` уровня `debug`. Счётчик SHALL сбрасываться успешным стартом (design.md change `require-project-folder`, D13).
- **Повторы.** Параллельные триггеры, пока агент стартует, НЕ SHALL открывать второй транспорт.
- **Последнее намерение фокуса побеждает.** Устаревшее намерение НЕ SHALL менять фокус и показывать ошибку. Сессия, созданная устаревшим намерением после `session/new`, SHALL оставаться в списке без фокуса.
- **Сочетания.** Cmd/Ctrl+N и пункт палитры `new` SHALL быть доступны, когда выбран проект, независимо от состояния соединения.
- **WebSocket** SHALL подключаться при первом триггере; одно соединение обслуживает все папки.

#### Scenario: Выбор проекта запускает агента без сессии
- **WHEN** агент не запущен, профиль окна — встроенный агент, и пользователь выбирает проект `/work/app` через «Open folder…»
- **THEN** встроенный агент открывается с папкой `/work/app`, сайдбар показывает сессии проекта из `session/list`, `session/new` не отправлен; кнопку Connect пользователь не нажимал

#### Scenario: Сессия другой папки не перезапускает агента
- **WHEN** агент работает с корнем процесса `/work/a`, в сессии `/work/a` идёт ход, и пользователь выбирает проект `/work/b` и нажимает «New session»
- **THEN** открыватель и фабрика транспорта повторно не вызываются, `session/new` отправлен с `cwd` `/work/b`, ход в `/work/a` продолжается и завершается своим ответом

#### Scenario: WebSocket подключается первым триггером
- **WHEN** профиль окна — WebSocket, и пользователь выбирает проект `/work/a`, затем создаёт сессии в `/work/a` и `/work/b`
- **THEN** соединение открыто один раз при выборе проекта, `session/new` отправлены с `cwd` `/work/a` и `/work/b`

#### Scenario: Параллельные триггеры — один агент
- **WHEN** агент не запущен, пользователь выбирает проект `/work/app` и, пока агент открывается, дважды нажимает «New session»
- **THEN** открыватель встроенного агента вызван один раз; фокус у сессии последнего намерения, сессия первого, если агент её создал, есть в списке без фокуса

#### Scenario: Быстрое переключение сессий
- **WHEN** пользователь выбирает сессию `notLoaded` `s1`, и пока идёт её `session/load`, выбирает сессию `s2`
- **THEN** в фокусе `s2`; `s1` после загрузки остаётся в списке открытой, но фокус не получает; ошибок уровня `error` нет

#### Scenario: После сбоя любой триггер повторяет старт
- **WHEN** старт встроенного агента завершился сбоем конфигурации, и пользователь выбирает сессию `notLoaded`, затем нажимает «New session»
- **THEN** каждое действие начинает ровно одну новую попытку; между действиями попыток нет, сколько бы времени ни прошло

#### Scenario: Одинаковый сбой не плодит записи
- **WHEN** старт три раза подряд падает с одной и той же ошибкой при том же профиле и корне
- **THEN** в диагностике одна запись уровня `error`, экран сбоя показывает `Failed again (2)`; после исправления и успешного старта следующий сбой — снова новая запись

### Requirement: Подтверждение открытия сессии в корне диска
Фокус на сессии `notLoaded` или `detached`, чей `cwd` после нормализации (`p.normalize`) — корень файловой системы (`/`, `C:\` и т. п.), SHALL сначала показывать диалог `This session runs in the disk root (<cwd>). The agent gets access to the whole disk. Open anyway?` с кнопками `Open` и `Cancel` (design.md change `require-project-folder`, D24).

- `session/load` и старт агента для этого намерения SHALL идти только после `Open`.
- `Cancel` или закрытие диалога НЕ SHALL менять фокус, статус строки и отправлять агенту сообщения.
- Новое действие фокуса во время диалога SHALL закрывать его как `Cancel`; повторный клик по той же сессии при открытом диалоге SHALL игнорироваться.
- Решение SHALL писаться событием `session.root_open {decision}` без пути.
- Сессии с `cwd` вне корня диска подтверждения НЕ SHALL требовать.

#### Scenario: Open загружает сессию в корне
- **WHEN** в списке сессия `s2` со статусом `notLoaded` и `cwd` `/`, и пользователь выбирает её
- **THEN** показан диалог `This session runs in the disk root (/). The agent gets access to the whole disk. Open anyway?`, агенту ничего не отправлено; после `Open` отправлен `session/load` с `cwd` `/`, и `s2` в фокусе

#### Scenario: Cancel ничего не меняет
- **WHEN** пользователь выбрал `s2` с `cwd` `/` и в диалоге нажал `Cancel`
- **THEN** фокус прежний, `s2` по-прежнему `notLoaded`, `session/load` не отправлен, в журнале `session.root_open` с `decision: cancel`

#### Scenario: Ненормализованный корень
- **WHEN** `cwd` сессии — `/tmp/..` или `//`
- **THEN** диалог показан, как для `/`

#### Scenario: Другое действие во время диалога
- **WHEN** диалог для `s2` открыт, и пользователь выбирает сессию `s3` с `cwd` `/work/app`
- **THEN** диалог закрыт как `Cancel`, `s3` открывается без подтверждения
