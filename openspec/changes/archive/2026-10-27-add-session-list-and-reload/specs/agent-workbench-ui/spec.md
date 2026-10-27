## ADDED Requirements

### Requirement: Sessions sidebar lists the project's sessions from the agent
When the agent declares `sessionCapabilities.list`, the sessions sidebar SHALL show the project's sessions from `session/list` after each successful connect or reconnect, after the sessions opened in this run and without duplicates. A session that is not open yet SHALL be shown with its title from the agent and a "not loaded" status. When the agent reports more sessions, the sidebar SHALL offer a "Load more sessions" control that fetches the next page.

#### Scenario: Sessions from the agent's journal
- **WHEN** the user connects to an agent whose journal holds two sessions for the selected project
- **THEN** the sidebar lists both sessions with their titles and a "not loaded" status

#### Scenario: More sessions than one page
- **WHEN** the agent's first `session/list` page has a `nextCursor`
- **THEN** the sidebar shows "Load more sessions", and selecting it appends the next page

### Requirement: Selecting a not-loaded session restores its transcript
Selecting a "not loaded" session in the sidebar SHALL load it via `session/load` and make it the active session with the transcript replayed by the agent. If loading fails, the previously active session SHALL stay active and the failure SHALL be recorded as a diagnostic.

#### Scenario: Loading a session from the sidebar
- **WHEN** the user selects a "not loaded" session
- **THEN** the session becomes active and its transcript shows the user prompts and agent replies the agent replayed

#### Scenario: Loading fails
- **WHEN** the agent answers `session/load` with an error
- **THEN** the active session does not change, the sidebar row stays "not loaded", and a diagnostic records the failure

### Requirement: Workbench restores sessions after reconnect and restart
After `Reconnect`, the workbench SHALL reload the open sessions so the active session's transcript matches the agent's replay; a session the agent cannot restore SHALL be shown as "detached" with a notice in its transcript, and prompts to it SHALL fail without reaching the agent. After an app restart, the workbench SHALL select the project from the previous run and, on the first successful connect, SHALL list the project's sessions and load the previously active session; when the agent cannot restore it, the workbench SHALL start a new session with a notice explaining why.

#### Scenario: Reconnect reloads the active session
- **WHEN** a session with a finished turn is active and the user presses Reconnect to an agent that supports `session/load`
- **THEN** after reconnecting the active session shows the same transcript, rebuilt from the agent's replay

#### Scenario: Restart restores the previous session
- **WHEN** the user restarts the app after working in a session and connects again with the same connection settings
- **THEN** the previous project is selected, the sidebar lists the project's sessions, and the previously active session is loaded with its transcript

#### Scenario: The agent cannot restore sessions
- **WHEN** after a restart the user connects to an agent without `loadSession`
- **THEN** the workbench starts a new session in the previous project and its transcript shows "The agent cannot restore sessions; a new session was started."
