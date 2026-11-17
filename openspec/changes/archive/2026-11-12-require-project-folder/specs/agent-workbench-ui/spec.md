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
Focusing a session that is not loaded in the current connection — "not loaded" or "detached" — SHALL start the window's agent if it is not running (requirement «Агент стартует сам»), load the session via `session/load` with the session's own `cwd`, and make it the active session with the transcript replayed by the agent. A running agent SHALL NOT be restarted for this, whatever the session's directory. If starting the agent or loading fails, the previously active session SHALL stay active, the sidebar row SHALL keep its status, and the failure SHALL be recorded as a diagnostic. Exception: when the running agent did not declare `loadSession`, focusing a "detached" session SHALL show it read-only with its transcript and the detached notice, as before this change, without a `session/load` attempt and without a diagnostic; when the agent is not running, the focus starts it first and then applies the same rule (design.md change `require-project-folder`, Q26 (a)).

#### Scenario: Loading a session from the sidebar
- **WHEN** the user selects a "not loaded" session
- **THEN** the session becomes active and its transcript shows the user prompts and agent replies the agent replayed

#### Scenario: Loading fails
- **WHEN** the agent answers `session/load` with an error
- **THEN** the active session does not change, the sidebar row keeps its status, and a diagnostic records the failure

#### Scenario: Detached session with an agent without loadSession
- **WHEN** the running agent did not declare `loadSession`, and the user selects a "detached" session
- **THEN** the session becomes active and shows its transcript with the detached notice, no `session/load` is sent, no diagnostic is recorded, and prompts to it still fail without reaching the agent

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

### Requirement: Workbench честно отражает спонтанную потерю соединения
CodeLab SHALL отражать спонтанную (не вызванную стартом или перезапуском агента) потерю ACP-соединения как отдельное состояние `lost` в UI, отличное от неудачного старта `failed`, и SHALL очищать состояние активного запроса, которое больше не может считаться достоверным, вместо того чтобы бесконечно показывать `Connected` и зависший `running` turn.

#### Scenario: Агент падает во время активной сессии
- **WHEN** активное соединение (`connectionStatus == connected`) спонтанно теряется — например, дочерний процесс агента завершается неожиданно
- **THEN** CodeLab переводит `connectionStatus` в `lost`, очищает `pendingApproval`, `isPromptSubmitting`, `canCancel`, `isRespondingToApproval` и `isRespondingToConfigOption`, и записывает диагностику с причиной

#### Scenario: Сбой старта или перезапуска не задваивается
- **WHEN** старт агента по триггеру (требование «Агент стартует сам») или «Restart agent» завершается неудачей
- **THEN** CodeLab переводит `connectionStatus` в `failed` и показывает ровно одну diagnostic-запись об этой неудаче — реакция на спонтанную потерю соединения не создаёт вторую, дублирующую запись для того же события

#### Scenario: История сессии не теряется при потере соединения
- **WHEN** происходит спонтанная потеря соединения
- **THEN** CodeLab сохраняет видимыми `transcriptEntries` уже случившейся сессии — они не считаются недостоверными, в отличие от состояния активного запроса

### Requirement: Connection banner above a non-empty transcript
When the transcript of the active session is not empty and the connection is `lost`, `failed` or `reconnecting`, the workbench SHALL show a banner above the transcript that states the connection status and its reason. The banner SHALL offer Retry and Connection settings while the connection is `lost` or `failed`, and SHALL show progress without a Retry action while it is `reconnecting`. After `failed`, Retry SHALL repeat the intent that started the agent; after `lost`, Retry SHALL start the agent again with the window's profile and the previous process root, and the open sessions SHALL be reloaded as after "Restart agent" (requirement «Агент стартует сам», trigger 4; design.md change `require-project-folder`, D13, D18). The banner SHALL NOT be dismissible and SHALL disappear when the connection becomes `connected`. When no session is in focus or its transcript is empty, the workbench SHALL show the start screen or the start failure screen instead of the banner (requirement «Empty session after connecting»).

#### Scenario: The agent process exits during a session
- **WHEN** the active session's transcript has entries and the agent process exits unexpectedly
- **THEN** a "Connection to the agent lost" banner with the reason, a Retry action and a Connection settings action appears above the transcript, and the transcript entries stay visible

#### Scenario: Retry from the banner
- **WHEN** the connection is `lost` and the user selects Retry in the banner, and the start succeeds
- **THEN** the agent starts once with the window's profile, the banner shows progress without the Retry action while starting, and disappears once the connection is `connected`; the active session is loaded again via `session/load`

#### Scenario: Retry from the banner fails
- **WHEN** the user selects Retry in the banner and the attempt fails
- **THEN** the banner shows "Could not connect to the agent" with the failure reason and offers Retry again

#### Scenario: Empty transcript shows the failure screen
- **WHEN** the start of the agent fails while the active session's transcript is empty or no session is in focus
- **THEN** the session pane shows the start failure screen with the reason and Retry, and no banner

### Requirement: App bar with palette search and connection badge
CodeLab SHALL show an app bar with the app name, a search field labelled "Search or run a command" with the palette shortcut, toggles for the available tool panes, and a connection badge. Activating the search field SHALL open the command palette. The badge SHALL show the connection status; while the connection is lost or failed it SHALL offer Retry, which does the same as Retry in the connection banner (requirement «Connection banner above a non-empty transcript»). The badge SHALL NOT offer Connect in any state: the agent starts by the workbench triggers (requirement «Агент стартует сам»; design.md change `require-project-folder`, D18). The app bar SHALL NOT show the agent binary path.

#### Scenario: Search field opens the palette
- **WHEN** the user clicks the "Search or run a command" field
- **THEN** the command palette opens with focus in its search box

#### Scenario: Badge offers Retry after a lost connection
- **WHEN** the agent process exits while connected
- **THEN** the badge reads "Connection lost" and offers Retry, and choosing Retry starts the agent again

#### Scenario: Badge while connected
- **WHEN** the connection is established
- **THEN** the badge reads "Connected", no Connect button is shown, and the profile and transport are available in the badge tooltip

#### Scenario: Badge before the agent starts
- **WHEN** no project is selected and the agent has not started
- **THEN** the badge shows the disconnected status without a Connect button

### Requirement: Командная палитра открывается и выполняет доступные действия
CodeLab SHALL открывать `CodeLabCommandPaletteSurface` при вызове shortcut'а командной палитры и SHALL выполнять `/new` (создание сессии) и `/reconnect` немедленно при выборе, закрывая палитру после этого. `/reconnect` SHALL выполнять то же действие, что «Restart agent» страницы «Connection», включая подтверждение при идущих ходах (spec app-settings «Блок «Behavior» страницы «Connection»»); подпись пункта — «Restart agent» для локального профиля и «Reconnect» для WebSocket (design.md change `require-project-folder`, D22, Q24 (a)).

#### Scenario: Открытие командной палитры показывает surface
- **WHEN** пользователь вызывает shortcut командной палитры (`Ctrl/Cmd+K`)
- **THEN** CodeLab показывает `CodeLabCommandPaletteSurface` поверх workbench

#### Scenario: Закрытие командной палитры
- **WHEN** командная палитра открыта, и пользователь нажимает `Esc` либо выбирает доступную команду
- **THEN** CodeLab скрывает `CodeLabCommandPaletteSurface` и возвращает фокус клавиатуры workbench

#### Scenario: Выбор /new создаёт сессию
- **WHEN** командная палитра открыта, и пользователь выбирает `/new`
- **THEN** CodeLab создаёт новую сессию через существующий флоу создания сессии и закрывает палитру

#### Scenario: Выбор /reconnect перезапускает агента
- **WHEN** командная палитра открыта, агент работает, ходов нет, и пользователь выбирает `/reconnect`
- **THEN** CodeLab перезапускает агента выбранным профилем окна без диалога и закрывает палитру

#### Scenario: /reconnect при идущем ходе
- **WHEN** в сессии окна идёт ход, и пользователь выбирает `/reconnect` в палитре
- **THEN** палитра закрыта и показан диалог подтверждения перезапуска; после «Cancel» агент и ход прежние

#### Scenario: Выбор /logs открывает полноэкранный log viewer
- **WHEN** командная палитра открыта, и пользователь выбирает `/logs`
- **THEN** CodeLab открывает полноэкранный log viewer (master-detail, поверх притемнённого workbench) и закрывает палитру

### Requirement: Sessions sidebar lists the project's sessions from the agent
When the agent declares `sessionCapabilities.list`, the sessions sidebar SHALL show the project's sessions from `session/list` after each successful start or restart of the agent and after the project is switched while the agent runs (requirement «Агент стартует сам»; design.md change `require-project-folder`, D15), after the sessions opened in this run and without duplicates. A session that is not open yet SHALL be shown with its title from the agent and a "not loaded" status. When the agent reports more sessions, the sidebar SHALL offer a "Load more sessions" control that fetches the next page.

#### Scenario: Sessions from the agent's journal
- **WHEN** the agent starts for the selected project, and its journal holds two sessions for that project
- **THEN** the sidebar lists both sessions with their titles and a "not loaded" status

#### Scenario: More sessions than one page
- **WHEN** the agent's first `session/list` page has a `nextCursor`
- **THEN** the sidebar shows "Load more sessions", and selecting it appends the next page


### Requirement: Sessions sidebar grouped by project
The sessions sidebar SHALL show, from top to bottom, "New session" with its shortcut, a filter field, a "Projects" section with one group per project, "Open folder…", and "Settings" at the bottom. The selected project's group SHALL be expanded and list its sessions with their status and "Load more sessions"; recent projects SHALL be collapsed groups named after the folder. A session opened in this run SHALL be listed in the group of the project whose path equals its `cwd` (exact string match): one agent serves sessions of any folder, and a session of another project keeps running after the project is switched. A recent project's group that holds open sessions SHALL list them with their live status, and stays collapsed only while none of them is running, waiting for approval or failed; it SHALL NOT list that project's `session/list` rows until the project is selected. An open session whose `cwd` matches no group SHALL be listed in the selected project's group with its folder as the subtitle (design.md change `require-project-folder`, Q23 (a)). The filter SHALL narrow the listed sessions by title.

#### Scenario: Groups by project
- **WHEN** the selected project has three sessions and two other projects are in the recent list
- **THEN** the sidebar shows the selected project's group expanded with three sessions and two collapsed groups for the other projects

#### Scenario: Filtering sessions
- **WHEN** the user types "reconnect" into the filter field
- **THEN** only sessions whose title contains "reconnect" (case-insensitive) stay listed

#### Scenario: Session status in the sidebar
- **WHEN** a listed session is running a turn, waiting for approval, failed or not loaded
- **THEN** its row shows the matching status, as in "Sessions sidebar shows live status for background sessions"

#### Scenario: Running session of another project after switching
- **WHEN** a turn is running in a session with `cwd` `/work/a`, `/work/a` is a recent project, and the user selects the project `/work/b`
- **THEN** the `b` group lists `/work/b`'s sessions, the `a` group is expanded and lists the running session with its status, and the session is not listed under `b`

#### Scenario: Open session without its project group
- **WHEN** the selected project is `/work/app` and a session with `cwd` `/work/tools` (not a recent project) is open
- **THEN** the session is listed in the `app` group with the subtitle `/work/tools`

### Requirement: Тип подключения «Встроенный агент»
Встроенный агент SHALL быть первой строкой списка профилей страницы настроек «Connection» (spec app-settings «Список профилей на странице «Connection»»), а не типом в форме подключения (design.md change `add-app-settings-shell`, D6). У строки нет полей. Рабочая папка выбирается «Open Project», как у других профилей. Конфигурация агента берётся из `$CODELAB_HOME/config.yaml` и проектного `.codelab/config.yaml`, ключи — из хранилища секретов агента.

Подключение SHALL строить профиль `ConnectionProfile.embedded(id: 'embedded', hostProfile: 'embedded-app-desktop')`, а транспорт ему даёт `EmbeddedTransportResolver`, зарегистрированный в composition root (`apps/codelab_desktop/lib/app/`). Виджеты и Cubit-ы НЕ SHALL импортировать `package:codelab_embedded/io.dart`.

Без сохранённого выбора профиля по умолчанию профилем по умолчанию SHALL быть встроенный агент; профиль `default` из `profiles.json` app не учитывает (design.md change `add-app-settings-shell`, D5).

Требования к поведению:
- **Невалидная или отсутствующая конфигурация** встроенного агента SHALL переводить подключение в `ConnectionFailed` (design.md change `add-embedded-agent-mode`, D13, п. 2). Баннер соединения SHALL показывать текст `EmbeddedAgentConfigException`: проблемы загрузчика в форме `config check` и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`. Значений секретов в нём нет.
- **Нет ключа провайдера.** Подключение SHALL открываться. Первый ход с этим провайдером SHALL завершаться ошибкой провайдера с именем секрета без значения и показываться заметкой «Failed turn» (требование «Failed turn notice with Retry»), как у внешнего агента. Отдельной проверки готовности провайдера при подключении нет.
- **Одобрения, очередь промптов, список сессий, отмена хода и транскрипт** встроенного агента SHALL работать теми же компонентами, что для внешнего агента.
- **Обрыв соединения** (отказ встроенного агента, `ConnectionLost`) SHALL отображаться так же, как обрыв внешнего агента.
- **«Restart agent» во время старта** встроенного агента SHALL прерывать прежнюю попытку без промежуточного `ConnectionFailed`: баннер соединения показывает подключение новой попытки, агент прерванной попытки освобождается резолвером (требование acp-client-kit «Явный автомат соединения»; design.md change `add-embedded-agent-mode`, D6; design.md change `require-project-folder`, Q25 (a)). Параллельные триггеры старта второй попытки не начинают (требование «Агент стартует сам»).
- **Закрытие root scope** SHALL ждать остановки встроенного агента не дольше 10 s. По истечении приложение SHALL писать событие `embedded.close_timeout` уровня `warning` без текста ошибки и продолжать освобождение транспорта и `AcpClientApplication` (D9).

#### Scenario: Выбор встроенного агента
- **WHEN** работает stdio-профиль, пользователь нажимает «Use» в строке «Embedded agent» на странице «Connection», затем «Restart agent»
- **THEN** CodeLab подключается к встроенному агенту без запуска дочернего процесса, а метка подключения — `Embedded agent`

#### Scenario: Встроенный агент по умолчанию
- **WHEN** CodeLab запускается впервые с пустым `CODELAB_HOME`, и пользователь выбирает проект через «Open folder…»
- **THEN** CodeLab стартует встроенного агента

#### Scenario: Нет конфигурации встроенного агента
- **WHEN** `$CODELAB_HOME` не содержит `config.yaml`, и встроенный агент стартует при выборе проекта
- **THEN** подключение в состоянии `ConnectionFailed`, баннер показывает проблему конфигурации и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`, где `<home>` — путь `CODELAB_HOME`

#### Scenario: Невалидный проектный конфиг встроенного агента
- **WHEN** выбранный проект содержит `.codelab/config.yaml` с `budget.max_steps: 0`, и встроенный агент стартует при выборе проекта
- **THEN** подключение в состоянии `ConnectionFailed`, баннер называет файл, строку и ключ `budget.max_steps` и содержит ту же подсказку

#### Scenario: Нет ключа провайдера
- **WHEN** `config.yaml` валиден и задаёт провайдера с `api_key_secret: codelab/p`, секрет `codelab/p` не задан, встроенный агент стартует при выборе проекта, и пользователь создаёт сессию и отправляет промпт
- **THEN** подключение установлено, ход завершается заметкой «Failed turn» с ошибкой провайдера, называющей `codelab/p`, без значения секрета

#### Scenario: Одобрение во встроенном режиме
- **WHEN** встроенный агент спрашивает одобрение `write` в режиме `standard`, и пользователь выбирает вариант отказа в карточке одобрения
- **THEN** файл не изменён, а строка вызова в транскрипте показывает отказ

#### Scenario: Restart agent во время старта встроенного агента
- **WHEN** встроенный агент стартует при выборе проекта, и, пока он ещё открывается, пользователь нажимает «Restart agent»
- **THEN** баннер соединения не показывает `ConnectionFailed` прерванной попытки, подключение завершается исходом второй попытки, а агент первой попытки остановлен

#### Scenario: Зависшая остановка встроенного агента
- **WHEN** root scope закрывается, а остановка встроенного агента не завершается за 10 s
- **THEN** в логе приложения есть `embedded.close_timeout` уровня `warning`, а транспорт и `AcpClientApplication` освобождены

### Requirement: Встроенный агент без провайдера
Если встроенный агент не открылся только потому, что нет ни одного провайдера с моделью (`providerSetupNeeded` моста `codelab_setup` истинно для снимка конфига, с которым он открывался: нет файла, нет провайдеров или у них нет моделей; spec client-agent-setup «Готовность провайдера»; без `agent.default_model` при провайдере с моделью агент открывается на первой модели, design.md change `optional-default-model`, D3), баннер соединения SHALL показывать `No model provider is configured for the embedded agent.` и действие «Add provider» (ключ `connection-banner-add-provider`) вместо сырого текста проблем (решение пользователя 2026-11-06; design.md change `add-provider-setup-ui`, D26). Признак SHALL определяться по типизированным проблемам загрузчика и составу слоёв конфига, а не по тексту. Прочие ошибки конфига встроенного агента SHALL показываться как раньше.

«Add provider» SHALL открывать мастер провайдера (spec app-settings «Мастер провайдера в app») с целью `user` по умолчанию и неснимаемым «Make default». После `ConfigSaved` app SHALL повторять намерение, вызвавшее неудачный старт встроенного агента (как «Retry», требование «Агент стартует сам»; design.md change `require-project-folder`, D13), если с момента сбоя не начиналась новая попытка старта окна; если началась (с любым профилем), повтора НЕ SHALL быть. Отмена мастера SHALL оставлять баннер.

#### Scenario: Новая установка
- **WHEN** app с пустым `CODELAB_HOME` стартует встроенного агента при выборе проекта
- **THEN** баннер показывает `No model provider is configured for the embedded agent.` и «Add provider», текста `no model is configured` (сырая проблема `config.model.none`, design.md change `optional-default-model`, D4) и `codelab config check` в нём нет

#### Scenario: Провайдер добавлен из баннера
- **WHEN** пользователь нажимает «Add provider» в баннере, проходит мастер и сохраняет провайдера
- **THEN** `config.yaml` содержит провайдера и `agent.default_model` (мастер с неснимаемым «Make default» пишет ключ, D7; для старта агента ключ не обязателен), app повторяет старт встроенного агента, баннер исчезает, а модель видна в селекторе композера

#### Scenario: Другой профиль за время мастера
- **WHEN** мастер открыт из баннера, и пока он открыт, окно начинает старт stdio-профиля (диалог модальный, поэтому тест выбирает профиль `ConnectionCommands.use` и начинает старт `ConnectionCommands.restart`), затем пользователь сохраняет провайдера
- **THEN** конфиг записан, повтора старта встроенного агента нет, агент окна — stdio-профиль, журнал содержит `provider_wizard.reconnect_skipped`

#### Scenario: Прочая ошибка конфига
- **WHEN** `config.yaml` задаёт провайдера и `agent.default_model`, но содержит `budget.max_steps: 0`; либо задаёт провайдера `gw` и `agent.default_model: gw/typo`, которой нет в каталоге
- **THEN** баннер показывает прежний текст проблемы с подсказкой `codelab config check`, действия «Add provider» нет


## ADDED Requirements

### Requirement: Без выбранного проекта нет папки агента и сессий
Агент (процесс stdio, встроенный агент, соединение WebSocket) и сессия в desktop SHALL получать папку только из выбранного проекта или из `cwd` существующей сессии (требование «Project selection is independent of the connection type»; design.md change `require-project-folder`, D1, D2, D3, D5, D9).

- **«New session» без проекта** НЕ SHALL создавать сессию, НЕ SHALL запускать агента и НЕ SHALL отправлять агенту сообщений. Вместо этого она SHALL открывать системный выбор папки, как «Open folder…». Выбранная папка становится проектом (это триггер старта агента), а сессия автоматически не создаётся.
- **Папки нет на диске.** Если папка триггера локального профиля (встроенный агент, stdio) исчезла, агент для неё НЕ SHALL запускаться, а сессия НЕ SHALL создаваться или загружаться. Причина `Project folder not found: <path>. Choose an existing folder with Open folder….` SHALL попадать в диагностику уровня `error` с источником `project`.
- **Ожидание восстановления.** Пока проект прошлого запуска восстанавливается, «New session», «Restart agent» и старт при запуске SHALL ждать его не дольше 2 с. Если после ожидания проекта нет, агент НЕ SHALL стартовать: «New session» SHALL открывать выбор папки, «Restart agent» без прежнего корня SHALL отклоняться до обращения к workspace с событием `connection.connect_rejected {reason: no_project, profile_id}` без пути, а старт при запуске SHALL не выполняться (design.md change `require-project-folder`, D3, D19). Итерация A применяла это правило к кнопкам «Connect» и «Reconnect», которых после итерации B нет.
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
- **WHEN** проект `/work/app` из снимка ещё восстанавливается, и пользователь нажимает «New session»
- **THEN** действие ждёт восстановления, агент стартует с папкой `/work/app`, сессия создаётся с `cwd` `/work/app`; выбора папки и отказа «нет проекта» нет

#### Scenario: Восстановление не завершилось за таймаут
- **WHEN** чтение снимка зависло дольше 2 с, проект не выбран, и пользователь нажал «New session»
- **THEN** агент не стартует, обращения к workspace нет, открывается выбор папки

#### Scenario: Встроенный резолвер без папки
- **WHEN** `EmbeddedTransportResolver.open` вызван с пустой папкой
- **THEN** он завершается `ClientWorkspaceException`, а открыватель встроенного агента не вызывается

### Requirement: Агент стартует сам
Отдельного шага подключения в рабочем месте НЕ SHALL быть. Агент профиля окна SHALL стартовать, если он не работает (в том числе после сбоя старта), на одном из триггеров (design.md change `require-project-folder`, D11–D17):
1. выбор проекта — «Open folder…», недавний проект, проект, восстановленный при запуске;
2. «New session» в выбранном проекте;
3. фокус на сессии `notLoaded` или `detached`;
4. «Retry» экрана или баннера сбоя.

Агент стартует в папке триггера — она становится корнем процесса. Исключение — триггер 3 для сессии, чей `cwd` — корень диска: корнем процесса SHALL быть выбранный проект, а корень диска — только если проект не выбран, и только после подтверждения (требование «Подтверждение открытия сессии в корне диска»; design.md change `require-project-folder`, Q27 (a)). Сама сессия в любом случае загружается со своим `cwd`. Выбор проекта НЕ SHALL создавать сессию. Если агент уже работает, выбор проекта SHALL сразу запрашивать `session/list` нового проекта, без перезапуска.

- **Один агент на окно, любые папки.** Агент SHALL обслуживать сессии любых папок, передавая каждой её `cwd`. Смена проекта, фокус и создание сессии другой папки НЕ SHALL перезапускать агента и НЕ SHALL прерывать ходы других сессий.
- **Единственный перезапуск** — «Restart agent» / «Reconnect» (страница «Connection», диалог переноса секретов, пункт палитры `/reconnect`) с подтверждением при работе в сессиях; во время старта он вытесняет идущую попытку (spec app-settings «Блок «Behavior» страницы «Connection»»; Q24 (a), Q25 (a)).
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

#### Scenario: Сессия в корне диска не делает корень диска корнем процесса
- **WHEN** агент не запущен, выбран проект `/work/app`, и пользователь выбирает сессию `notLoaded` с `cwd` `/` и подтверждает `Open`
- **THEN** агент стартует с корнем процесса `/work/app`, а `session/load` отправлен с `cwd` `/`

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
