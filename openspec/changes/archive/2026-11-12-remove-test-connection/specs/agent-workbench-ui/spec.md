## MODIFIED Requirements

### Requirement: Project selection is independent of the connection type
CodeLab SHALL let the user select the working directory ("project") for sessions as an action independent of the connection profile, and SHALL apply the currently selected project to the next session created regardless of whether the window's profile is the embedded agent, stdio or WebSocket. A project is selected only explicitly: via "Open folder…", a recent project, or the project restored from the previous run's workspace snapshot. CodeLab SHALL NOT substitute the CodeLab process's own current directory (or any other implicit directory) for a project that has not been selected; without a selected project there is no directory for an agent or a session (requirement «Без выбранного проекта нет папки агента и сессий»; design.md change `require-project-folder`, D1, replacing Decision 1 of change `add-open-project-picker`). Whether a stdio agent process starts in its process root (the directory of the trigger that started it) SHALL be the `Run in the project folder` field of that stdio profile (`runInProjectDirectory`, default on in the "Add connection profile" dialog), not a separate workbench toggle (design.md change `add-app-settings-shell`, D6). The application has no separate profile check that would start an agent process outside these triggers, so the rule "no project — no directory" has no exception for it (design.md change `remove-test-connection`, D7, removing D7 of change `require-project-folder`).

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
