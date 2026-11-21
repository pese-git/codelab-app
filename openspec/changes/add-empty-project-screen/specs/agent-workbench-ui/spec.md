## MODIFIED Requirements

### Requirement: Project selection is independent of the connection type
CodeLab SHALL let the user select the working directory ("project") for sessions as an action independent of the connection profile, and SHALL apply the currently selected project to the next session created regardless of whether the window's profile is the embedded agent, stdio or WebSocket. A project is selected only explicitly: via "Open folder…" (including Cmd/Ctrl+O), a recent project, a folder dropped onto the no-project screen (requirement «Открытие папки перетаскиванием»; design.md change `add-empty-project-screen`, D4), or the project restored from the previous run's workspace snapshot. CodeLab SHALL NOT substitute the CodeLab process's own current directory (or any other implicit directory) for a project that has not been selected; without a selected project there is no directory for an agent or a session (requirement «Без выбранного проекта нет папки агента и сессий»; design.md change `require-project-folder`, D1, replacing Decision 1 of change `add-open-project-picker`). Whether a stdio agent process starts in its process root (the directory of the trigger that started it) SHALL be the `Run in the project folder` field of that stdio profile (`runInProjectDirectory`, default on in the "Add connection profile" dialog), not a separate workbench toggle (design.md change `add-app-settings-shell`, D6). The application has no separate profile check that would start an agent process outside these triggers, so the rule "no project — no directory" has no exception for it (design.md change `remove-test-connection`, D7, removing D7 of change `require-project-folder`).

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

#### Scenario: No profile check starts an agent without a project
- **WHEN** no project is selected, `profiles.json` contains a stdio profile `dev` with `Run in the project folder` on, and the user opens the "Connection" page and the "Add connection profile" dialog
- **THEN** neither offers a "Test connection" action, and no agent process is started until a project is selected

#### Scenario: A dropped folder is an explicit selection
- **WHEN** no project is selected, the window's profile is a WebSocket profile, and the user drops the folder `/work/app` onto the no-project screen and then creates a new session
- **THEN** the selected project is `/work/app`, and `session/new` carries `cwd` `/work/app`, the same as after choosing `/work/app` in "Open folder…"

### Requirement: App bar with palette search and connection badge
CodeLab SHALL show an app bar with the app name, a search field labelled "Search or run a command" with the palette shortcut, toggles for the available tool panes, and a connection badge. Activating the search field SHALL open the command palette. The badge SHALL show the connection status; while the connection is lost or failed it SHALL offer Retry, which does the same as Retry in the connection banner (requirement «Connection banner above a non-empty transcript»). The badge SHALL NOT offer Connect in any state: the agent starts by the workbench triggers (requirement «Агент стартует сам»; design.md change `require-project-folder`, D18). The app bar SHALL NOT show the agent binary path. While no project is selected and the agent has not started (connection status idle or disconnected), the badge SHALL read `No project · agent not started` with the tooltip `No project is selected, so no agent is running` instead of the status name (frame 11a; design.md change `add-empty-project-screen`, D8); in every other case the badge shows the connection status as above.

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
- **THEN** the badge reads `No project · agent not started`, its tooltip is `No project is selected, so no agent is running`, and no Connect button is shown

#### Scenario: Badge after a folder is chosen
- **WHEN** no project is selected, the badge reads `No project · agent not started`, and the user chooses the folder `/work/app` in "Open folder…"
- **THEN** while the agent starts the badge shows the connecting status, and `No project · agent not started` is no longer shown

### Requirement: Sessions sidebar grouped by project
The sessions sidebar SHALL show, from top to bottom, "New session" with its shortcut, a filter field, a "Projects" section with one group per project followed by "Open folder…" with the Cmd/Ctrl+O shortcut hint, and "Settings" at the bottom. With no project groups (no project selected, no recent projects and no open sessions) the "Projects" section SHALL show `No recent projects yet.` above "Open folder…" (frame 11a; design.md change `add-empty-project-screen`, D9). The compact (icon-only) sidebar keeps "Open folder…" as an icon button next to "Settings" without a shortcut hint. The selected project's group SHALL be expanded and list its sessions with their status and "Load more sessions"; recent projects SHALL be collapsed groups named after the folder. A session opened in this run SHALL be listed in the group of the project whose path equals its `cwd` (exact string match): one agent serves sessions of any folder, and a session of another project keeps running after the project is switched. A recent project's group that holds open sessions SHALL list them with their live status, and stays collapsed only while none of them is running, waiting for approval or failed; it SHALL NOT list that project's `session/list` rows until the project is selected. An open session whose `cwd` matches no group SHALL be listed in the selected project's group with its folder as the subtitle (design.md change `require-project-folder`, Q23 (a)). The filter SHALL narrow the listed sessions by title.

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

#### Scenario: No projects yet
- **WHEN** no project is selected, the recent projects list is empty, and the platform is Linux
- **THEN** the "Projects" section shows `No recent projects yet.`, followed by "Open folder…" with the hint `Ctrl+O`; "Settings" stays at the bottom

#### Scenario: Open folder… follows the project groups
- **WHEN** a project is selected and two other projects are in the recent list
- **THEN** "Open folder…" is listed right after the last project group inside the "Projects" section, and `No recent projects yet.` is not shown

### Requirement: Empty session after connecting
Without a session in focus, the session pane SHALL show a start screen instead of a connection screen: without a selected project — the screen of requirement «Экран без выбранного проекта» with "Open folder…" (key `start-open-project`; design.md change `add-empty-project-screen`, D1, D2); with a selected project — `Start a new session in <folder name>.` and "New session" (key `start-new-session`), with the progress text `Starting <profile title>…` while the agent starts. The session pane header SHALL NOT show a subtitle while no session is in focus (D11). When a session is in focus and has no transcript items and the agent runs, the session pane SHALL show an empty state inviting the user to send the first message. When starting the agent fails, the session pane SHALL show the failure reason with "Retry", which repeats the intent that started the agent, and "Connection settings". The workbench SHALL NOT offer a Connect action (design.md change `require-project-folder`, D18).

#### Scenario: New session while connected
- **WHEN** the agent runs and the user creates a new session
- **THEN** the session pane shows the empty state with the composer focused, and no Connect button

#### Scenario: Start screen without a project
- **WHEN** no project is selected and no session is in focus
- **THEN** the session pane shows `open-project-screen` with "Open folder…" (`start-open-project`), the text `Open a project to start a session.` is not shown anywhere in the window, and no Connect button

#### Scenario: Start screen with a project
- **WHEN** the project `/work/app` is selected and no session is in focus
- **THEN** the session pane shows `Start a new session in app.` and "New session" (`start-new-session`); pressing it creates a session with `cwd` `/work/app`

#### Scenario: Agent start fails
- **WHEN** the user selects a project with the embedded agent and an invalid `config.yaml`
- **THEN** the session pane shows the config problems and "Retry"; after the config is fixed, "Retry" (or any other start trigger) starts it

### Requirement: Агент стартует сам
Отдельного шага подключения в рабочем месте НЕ SHALL быть. Агент профиля окна SHALL стартовать, если он не работает (в том числе после сбоя старта), на одном из триггеров (design.md change `require-project-folder`, D11–D17):
1. выбор проекта — «Open folder…» (и Cmd/Ctrl+O), недавний проект, папка, перетащенная на экран без проекта (требование «Открытие папки перетаскиванием»; design.md change `add-empty-project-screen`, D4), проект, восстановленный при запуске; если при запуске показан onboarding (spec app-onboarding «Показ onboarding при первом запуске»), восстановленный проект становится триггером только после «Start using CodeLab», а до этого агент окна НЕ SHALL стартовать (design.md change `add-app-onboarding`, D5);
2. «New session» в выбранном проекте;
3. фокус на сессии `notLoaded` или `detached`;
4. «Retry» экрана или баннера сбоя.

Агент стартует в папке триггера — она становится корнем процесса. Исключение — триггер 3 для сессии, чей `cwd` — корень диска: корнем процесса SHALL быть выбранный проект, а корень диска — только если проект не выбран, и только после подтверждения (требование «Подтверждение открытия сессии в корне диска»; design.md change `require-project-folder`, Q27 (a)). Сама сессия в любом случае загружается со своим `cwd`. Выбор проекта НЕ SHALL создавать сессию. Если агент уже работает, выбор проекта SHALL сразу запрашивать `session/list` нового проекта, без перезапуска.

- **Один агент на окно, любые папки.** Агент SHALL обслуживать сессии любых папок, передавая каждой её `cwd`. Смена проекта, фокус и создание сессии другой папки НЕ SHALL перезапускать агента и НЕ SHALL прерывать ходы других сессий.
- **Единственный перезапуск** — «Restart agent» / «Reconnect» (страница «Connection», диалог переноса секретов, пункт палитры `/reconnect`) с подтверждением при работе в сессиях; во время старта он вытесняет идущую попытку (spec app-settings «Блок «Behavior» страницы «Connection»»; Q24 (a), Q25 (a)).
- **После сбоя** любой триггер SHALL снова пытаться стартовать агента. Без действия пользователя (или восстановления проекта при запуске) попытки НЕ SHALL начинаться: таймеров и автоповторов нет. Сбой с тем же профилем, корнем процесса и текстом, что предыдущий, НЕ SHALL добавлять новую запись в диагностику; экран сбоя SHALL показывать `Failed again (<n>)`, журнал — `connection.start_failed {profile_id, repeat}` уровня `debug`. Счётчик SHALL сбрасываться успешным стартом (design.md change `require-project-folder`, D13).
- **Повторы.** Параллельные триггеры, пока агент стартует, НЕ SHALL открывать второй транспорт.
- **Последнее намерение фокуса побеждает.** Устаревшее намерение НЕ SHALL менять фокус и показывать ошибку. Сессия, созданная устаревшим намерением после `session/new`, SHALL оставаться в списке без фокуса.
- **Сочетания.** Cmd/Ctrl+N и пункт палитры `new` SHALL быть доступны на рабочем месте всегда, с проектом и без него, независимо от состояния соединения, и SHALL делать то же, что кнопка «New session» сайдбара. С выбранным проектом они создают сессию в нём. Без проекта они открывают системный выбор папки по правилу «New session» без проекта: агент не стартует до выбора, сессия после выбора автоматически не создаётся. Пока выбор папки, запрошенный app, открыт, повторный Cmd/Ctrl+N второй диалог НЕ SHALL открывать (требование «Cmd/Ctrl+O открывает выбор папки»). Подсказка `<shortcut> without a project opens the same folder picker.` в InfoBar экрана без проекта опирается на это правило (design.md change `add-empty-project-screen`, D7а).
- **WebSocket** SHALL подключаться при первом триггере; одно соединение обслуживает все папки.

#### Scenario: ⌘N без проекта открывает выбор папки
- **WHEN** проект не выбран, платформа — macOS, и пользователь нажимает ⌘N на рабочем месте
- **THEN** открывается системный выбор папки, агенту ничего не отправлено, агент не запущен, сессия не создана; после выбора `/work/app` она становится выбранным проектом, агент стартует в `/work/app`, `session/new` не отправлен

#### Scenario: Отмена выбора папки после Ctrl+N
- **WHEN** проект не выбран, платформа — Linux, пользователь нажимает Ctrl+N и закрывает системный диалог без выбора
- **THEN** проект не выбран, агент не запущен, сессия не создана, экран `open-project-screen` по-прежнему показан

#### Scenario: Повторный Ctrl+N при открытом диалоге
- **WHEN** проект не выбран, выбор папки открыт по Ctrl+N, и пользователь снова нажимает Ctrl+N
- **THEN** второй диалог не открывается, порт выбора папки вызван один раз

#### Scenario: Пункт палитры «New session» без проекта
- **WHEN** проект не выбран, и пользователь выбирает в палитре команд пункт `new`
- **THEN** открывается системный выбор папки, как по Ctrl+N; агенту ничего не отправлено, сессия не создана

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

#### Scenario: Восстановленный проект при первом показе onboarding
- **WHEN** снимок прошлого запуска содержит проект `/work/app`, флага `codelab.app.onboarding_done` нет, и app запускается
- **THEN** пока показан onboarding, открыватель встроенного агента не вызывается; после «Start using CodeLab» он вызван ровно один раз с папкой `/work/app`

#### Scenario: Перетащенная папка запускает агента без сессии
- **WHEN** агент не запущен, проект не выбран, профиль окна — встроенный агент, и пользователь перетаскивает папку `/work/app` на экран без проекта
- **THEN** встроенный агент открывается с папкой `/work/app` ровно один раз, сайдбар показывает сессии проекта из `session/list`, `session/new` не отправлен, `/work/app` добавлен в недавние проекты

## ADDED Requirements

### Requirement: Экран без выбранного проекта
Если проект не выбран и панель сессии показывает стартовый экран (сессии в фокусе нет, лента пуста, соединение не установлено и не в состоянии сбоя или потери), панель SHALL показывать экран `open-project-screen` по кадру 11a (design.md change `add-empty-project-screen`, D1, D2). Сверху вниз на нём:
1. иконка-герой и заголовок `Open a project`;
2. пояснение, которое зависит от профиля окна (D6):
   - встроенный агент — `Choose the folder you want to work in. The agent starts in it, and sessions get it as their working directory. The agent can't read or write outside it.`;
   - stdio — `Choose the folder you want to work in. The agent starts in it, and sessions get it as their working directory. An external agent applies its own rules to files outside it.`;
   - WebSocket — `Choose the folder you want to work in. Sessions get it as their working directory. An external agent applies its own rules to files outside it.`;
3. кнопка `Open folder…` (ключ `start-open-project`) с подсказкой сочетания Cmd/Ctrl+O для платформы. Кнопка открывает системный выбор папки, как «Open folder…» сайдбара;
4. зона перетаскивания (ключ `open-project-drop-zone`) с текстами `Drop a folder here to open it` и `Files are not accepted — only a folder` (требование «Открытие папки перетаскиванием»);
5. карточка агента окна (ключ `open-project-agent`, D5):
   - имя профиля — та же подпись, что в подсказке бейджа; у встроенного агента — переведённая;
   - строка транспорта: для встроенного агента `in-process · profile of this window`; для stdio `stdio · <command> · profile of this window`, где команда без аргументов; для WebSocket `WebSocket · <scheme>://<host>:<port> · profile of this window`, без userinfo, пути и query;
   - пояснение: для встроенного агента и stdio — `Starts when you open a folder. Nothing runs before that.`; для WebSocket — `Connects when you open a folder. Nothing connects before that.`;
   - ссылка `Change in Settings › Connection` (ключ `open-project-agent-settings`): открывает настройки на странице «Connection» через навигацию app;
6. InfoBar (ключ `open-project-info`) с заголовком `New session needs a folder` и текстом `<shortcut> without a project opens the same folder picker. Opened folders appear in the sidebar as recent projects.` Здесь `<shortcut>` — подсказка сочетания «New session» для платформы: `Ctrl+N` на Windows и Linux, `⌘N` на macOS.

Показ экрана НЕ SHALL запускать агента, открывать транспорт и отправлять агенту сообщения. Экран с выбранным проектом («New session») и экран сбоя старта этим требованием не меняются.

Тексты SHALL браться из каталогов ARB `en` и `ru`. Имя профиля пользователя, команда и адрес показываются как есть. Аргументы stdio, переменные окружения и токен профиля на экране НЕ SHALL показываться. Цвета SHALL браться из темы Fluent и палитры кита: в тёмной теме экран соответствует кадру `ProjectsEmpty-dark`. При нехватке высоты колонка экрана прокручивается, а не переполняется.

#### Scenario: Встроенный агент без проекта
- **WHEN** проект не выбран, недавних проектов нет, профиль окна — встроенный агент, платформа — Linux
- **THEN** панель сессии показывает `open-project-screen`: заголовок `Open a project`, пояснение с фразой `The agent can't read or write outside it.`, кнопку `Open folder…` с подсказкой `Ctrl+O`, зону с `Drop a folder here to open it`, карточку `Embedded agent` с `in-process · profile of this window` и `Starts when you open a folder. Nothing runs before that.`, InfoBar `New session needs a folder` с текстом, начинающимся на `Ctrl+N without a project`; открыватель встроенного агента не вызван, агенту ничего не отправлено

#### Scenario: Профиль stdio
- **WHEN** проект не выбран, и профиль окна — stdio-профиль `dev` с командой `/usr/local/bin/codelab-agent` и аргументами `serve --stdio --token abc`
- **THEN** карточка показывает `dev` и `stdio · /usr/local/bin/codelab-agent · profile of this window`, текста `--token` и `abc` на экране нет, а пояснение заканчивается фразой `An external agent applies its own rules to files outside it.`

#### Scenario: Профиль WebSocket
- **WHEN** проект не выбран, и профиль окна — WebSocket-профиль `remote` с адресом `ws://user:pw@127.0.0.1:8765/acp?t=1`
- **THEN** карточка показывает `WebSocket · ws://127.0.0.1:8765 · profile of this window` и `Connects when you open a folder. Nothing connects before that.`, а пояснение не содержит фразы `The agent starts in it`

#### Scenario: Подсказки на macOS
- **WHEN** проект не выбран, и платформа — macOS
- **THEN** у кнопки `Open folder…` подсказка `⌘O`, а текст InfoBar начинается на `⌘N without a project`

#### Scenario: Ссылка на настройки подключения
- **WHEN** проект не выбран, и пользователь нажимает `Change in Settings › Connection`
- **THEN** открыты настройки на странице «Connection», агент не запущен, агенту ничего не отправлено

#### Scenario: Отмена выбора папки
- **WHEN** проект не выбран, пользователь нажимает `Open folder…` и закрывает системный диалог без выбора
- **THEN** проект не выбран, экран `open-project-screen` по-прежнему показан, агент не запущен

#### Scenario: Проект выбран
- **WHEN** выбран проект `/work/app`, и сессии в фокусе нет
- **THEN** экрана `open-project-screen` и зоны перетаскивания нет, стартовый экран предлагает «New session» (`start-new-session`), как до этого change

#### Scenario: Тёмная тема и низкое окно
- **WHEN** проект не выбран, тема app — тёмная, окно 800×600
- **THEN** экран построен без ошибок переполнения, все шесть блоков доступны прокруткой, цвета текста и рамки зоны взяты из тёмной темы Fluent

### Requirement: Открытие папки перетаскиванием
Экран без выбранного проекта (требование «Экран без выбранного проекта») SHALL принимать элементы, перетащенные из файлового менеджера ОС, в любой точке экрана (design.md change `add-empty-project-screen`, D3, D4). Пока элементы над экраном, зона `open-project-drop-zone` SHALL быть выделена. Выделение снимается, когда элементы покидают экран или брошены. На рабочем месте с выбранным проектом, в настройках и в onboarding приёма перетаскивания этим требованием нет.

Решение о брошенных элементах SHALL принимать application (`SettingsCubit`) по видам путей из порта платформы. Виджет и адаптер плагина только передают список путей.
- **Ровно один элемент с локальным путём, и это существующая папка** (по символическим ссылкам ОС переходит): это выбор проекта, тот же, что выбор этой папки в «Open folder…». Папка становится выбранным проектом и попадает в недавние. Это триггер 1 старта агента профиля окна (требование «Агент стартует сам»): папка проверяется на существование, агент стартует в ней, затем `session/list`. `session/new` НЕ SHALL отправляться. Путь берётся так, как его отдала ОС, без разрешения ссылок, как у «Open folder…». Журнал: `project.drop {outcome: opened, count: 1}`. Проверок сверх вида пути бросок не добавляет: пакет macOS (`.app` и другие каталоги-пакеты) — папка, корень диска принимается так же, как в «Open folder…» (решения пользователя Q5 (а), Q6 (а) 2026-11-22).
- **Отказы.** Причина `not_a_folder` — элемент — обычный файл. `multiple` — элементов больше одного, даже если все они папки. `missing` — пути нет на диске. `unsupported` — у элемента нет локального пути, путь не абсолютный путь файловой системы ОС app (URI со схемой вроде `https://…` или `smb://…`, относительный путь), вид пути другой (устройство, сокет) или проверка вида завершилась ошибкой. Плагин на Linux отдаёт не-файловые URI как «путь», а в них бывают userinfo и токены. Поэтому неабсолютный путь отклоняется до проверки вида, и его текст НЕ SHALL попадать в состояние, на экран, в диагностику и в событие журнала (design.md change `add-empty-project-screen`, D4; ревью итерации 1). При отказе проект НЕ SHALL меняться, агент НЕ SHALL стартовать, агенту НЕ SHALL отправляться сообщения. Зона SHALL показывать текст причины (ключ `open-project-drop-message`, тон `warning`):
  - `not_a_folder` — `That's a file. Drop a folder to open it as a project.`;
  - `multiple` — `Drop one folder at a time.`;
  - `missing` — `The dropped item no longer exists: <path>.`;
  - `unsupported` — `This item can't be opened as a project. Drop a folder from your file system.`

  Текст держится до следующего входа перетаскивания на экран, следующего броска или выбора проекта. Отказ SHALL записываться в диагностику уровня `warning` с источником `project`: `Dropped item rejected (<reason>): <path>.`, для `multiple` — `Dropped items rejected (multiple): <n> items.`, для `unsupported` без локального пути и для неабсолютного пути — `Dropped item rejected (unsupported).` без пути. В журнал SHALL писаться событие `project.drop {outcome: rejected, reason, count}`. Путей и имён в событии нет.
- **Поздний результат.** Проверка вида асинхронна. Если пока она идёт, пользователь выбрал проект другим явным действием («Open folder…», Cmd/Ctrl+O, недавний проект, «New session» с выбором папки) или app закрывает рабочее место, результат броска SHALL отбрасываться: проект не меняется, текст отказа не показывается. Восстановление проекта прошлого запуска бросок не отменяет: бросок — более позднее явное намерение пользователя.

#### Scenario: Брошенная папка открывает проект
- **WHEN** проект не выбран, профиль окна — встроенный агент, и пользователь бросает на экран папку `/work/app`
- **THEN** выбран проект `/work/app`, он первый в недавних, открыватель встроенного агента вызван ровно один раз с папкой `/work/app`, отправлен `session/list`, `session/new` не отправлен, журнал содержит `project.drop` с `outcome: opened` без пути

#### Scenario: Файл отклоняется
- **WHEN** проект не выбран, и пользователь бросает файл `/work/app/README.md`
- **THEN** проект не выбран, агент не запущен, зона показывает `That's a file. Drop a folder to open it as a project.`, диагностика содержит `Dropped item rejected (not_a_folder): /work/app/README.md.` уровня `warning`, событие `project.drop` содержит `reason: not_a_folder` и не содержит пути

#### Scenario: Несколько элементов отклоняются
- **WHEN** проект не выбран, и пользователь бросает сразу папки `/work/a` и `/work/b`
- **THEN** ни одна папка не выбрана проектом, агент не запущен, зона показывает `Drop one folder at a time.`, событие `project.drop` содержит `reason: multiple` и `count: 2`

#### Scenario: Пропавший путь
- **WHEN** проект не выбран, и пользователь бросает элемент `/work/gone`, которого к моменту проверки нет на диске
- **THEN** проект не выбран, агент не запущен, зона показывает `The dropped item no longer exists: /work/gone.`

#### Scenario: Элемент без локального пути
- **WHEN** проект не выбран, и плагин передал брошенный элемент без локального пути
- **THEN** проект не выбран, зона показывает `This item can't be opened as a project. Drop a folder from your file system.`, событие `project.drop` содержит `reason: unsupported`

#### Scenario: Ссылка вместо папки
- **WHEN** проект не выбран, и плагин передал брошенный элемент с «путём» `https://user:token@example.com/repo`
- **THEN** проект не выбран, агент не запущен, вид пути не проверялся, зона показывает `This item can't be opened as a project. Drop a folder from your file system.`, диагностика содержит `Dropped item rejected (unsupported).` уровня `warning`, событие `project.drop` содержит `reason: unsupported`; строки `user`, `token` и `example.com` нет ни в состоянии отказа, ни на экране, ни в диагностике, ни в журнале

#### Scenario: Относительный путь отклоняется
- **WHEN** проект не выбран, и плагин передал брошенный элемент с путём `work/app`
- **THEN** проект не выбран, вид пути не проверялся, зона показывает текст `unsupported`, а диагностика — `Dropped item rejected (unsupported).` без пути

#### Scenario: Выделение зоны и сброс отказа
- **WHEN** зона показывает текст отказа, и пользователь снова наводит перетаскиваемый элемент на экран
- **THEN** текст отказа скрыт, зона выделена; когда элемент уходит с экрана без броска, выделение снято, а проект не выбран

#### Scenario: Папка исчезла после проверки вида
- **WHEN** брошенная папка `/work/app` прошла проверку вида, но удалена до старта встроенного агента
- **THEN** агент не стартует, диагностика содержит `Project folder not found: /work/app. Choose an existing folder with Open folder….` уровня `error` с источником `project`, как при выборе этой папки в «Open folder…»

#### Scenario: Другой выбор во время проверки
- **WHEN** проект не выбран, пользователь бросает папку `/work/a`, и пока идёт проверка её вида, выбирает `/work/b` в «Open folder…»
- **THEN** выбран проект `/work/b`, агент стартовал один раз с папкой `/work/b`, текста отказа нет, `/work/a` проектом не выбран

#### Scenario: Символическая ссылка на папку
- **WHEN** проект не выбран, и пользователь бросает `/work/link`, символическую ссылку на папку `/srv/app`
- **THEN** выбран проект `/work/link` — путь, как его отдала ОС

#### Scenario: Пакет macOS принимается как папка
- **WHEN** проект не выбран, платформа — macOS, и пользователь бросает пакет `/Applications/Foo.app`
- **THEN** выбран проект `/Applications/Foo.app`, текста отказа нет, журнал содержит `project.drop` с `outcome: opened`

### Requirement: Cmd/Ctrl+O открывает выбор папки
На рабочем месте сочетание Cmd/Ctrl+O (запись каталога `CodeLabShortcut.openFolder`; основной модификатор привязан и к Ctrl, и к ⌘ на всех платформах) SHALL открывать системный выбор папки, как «Open folder…» сайдбара (design.md change `add-empty-project-screen`, D7). Сочетание работает при любом состоянии соединения, с проектом и без него. Выбранная папка — выбор проекта (триггер 1 требования «Агент стартует сам»), закрытый без выбора диалог ничего не меняет. В настройках и в onboarding сочетание ничего не делает.

Пока открыт выбор папки, запрошенный app, повторный запрос («Open folder…», Cmd/Ctrl+O, «New session» без проекта) НЕ SHALL открывать второй диалог. Подсказки сочетания у «Open folder…» на экране без проекта и в сайдбаре SHALL браться из той же записи каталога для платформы.

#### Scenario: Ctrl+O без проекта
- **WHEN** проект не выбран, платформа — Linux, и пользователь нажимает Ctrl+O
- **THEN** открывается системный выбор папки; после выбора `/work/app` агент профиля окна стартует в `/work/app`, `session/new` не отправлен

#### Scenario: ⌘O во время хода в другом проекте
- **WHEN** платформа — macOS, в сессии проекта `/work/a` идёт ход, и пользователь нажимает ⌘O и выбирает `/work/b`
- **THEN** выбран проект `/work/b`, агент не перезапущен, ход в `/work/a` продолжается

#### Scenario: Второй запрос при открытом диалоге
- **WHEN** выбор папки открыт по Ctrl+O, и, пока он открыт, срабатывают «Open folder…» и «New session» без проекта
- **THEN** порт выбора папки вызван один раз

#### Scenario: Сочетание в настройках
- **WHEN** открыты настройки, и пользователь нажимает Ctrl+O
- **THEN** выбор папки не открывается, проект не меняется
