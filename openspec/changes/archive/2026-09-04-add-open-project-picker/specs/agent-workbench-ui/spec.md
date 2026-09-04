## MODIFIED Requirements

### Requirement: Connection profile is edited in a modal dialog
CodeLab SHALL present the transport setup form (profile, command, args, environment for stdio; endpoint and token for WebSocket) inside a modal dialog rather than as a permanently visible panel in the main workbench pane. Working directory ("project") SHALL NOT be a field of this dialog — it is selected independently of the connection, via the "Open Project" picker (see "Project selection is independent of the connection type" below). For stdio, the dialog SHALL additionally present a "Run agent from project directory" toggle, defaulting to on, controlling whether the agent process is spawned with the currently selected project's directory as its OS-level working directory. The dialog SHALL be reachable both from a persistent "Configure connection" affordance in the command bar and from a compact "Configure connection" prompt on the empty/disconnected connection screen — the same label in both places, not two names for one action — and SHALL NOT open automatically on app start.

#### Scenario: Opening the dialog from the command bar
- **WHEN** a session is active (transcript non-empty) and user selects "Configure connection" in the command bar
- **THEN** CodeLab opens the connection setup dialog over the current screen without navigating away from the active session

#### Scenario: Opening the dialog from the empty connection screen
- **WHEN** no transport is connected and user selects "Configure connection" on the connection screen
- **THEN** CodeLab opens the same connection setup dialog, pre-filled with the current transport type and field values

#### Scenario: Dialog does not open unprompted
- **WHEN** CodeLab starts for the first time with no prior connection
- **THEN** the connection setup dialog remains closed until the user explicitly opens it

#### Scenario: Editing fields inside the dialog
- **WHEN** user changes a field value while the dialog is open
- **THEN** CodeLab applies the change to connection state immediately, the same way it does today for the inline form

#### Scenario: Closing the dialog
- **WHEN** user dismisses the dialog (close button or Esc)
- **THEN** CodeLab returns to the workbench with the field values as last edited, without connecting or discarding them

#### Scenario: stdio process runs from the project directory by default
- **WHEN** transport is stdio, the "Run agent from project directory" toggle is on (default), and a project is selected (or none is, falling back to the current process directory)
- **THEN** CodeLab spawns the agent process with that same directory as its OS-level working directory

#### Scenario: stdio process spawn directory can be decoupled from the project
- **WHEN** transport is stdio and the user turns off "Run agent from project directory"
- **THEN** CodeLab spawns the agent process without an explicit working directory override (inherits CodeLab's own process directory), while the selected project's path is still sent as `cwd` in `session/new` for sessions created afterward

## ADDED Requirements

### Requirement: Project selection is independent of the connection type
CodeLab SHALL let the user select the working directory ("project") for sessions as an action independent of the transport connection, and SHALL apply the currently selected project to the next session created regardless of whether the active transport is stdio or WebSocket.

#### Scenario: Project applies to a WebSocket session
- **WHEN** CodeLab is connected via WebSocket and the user creates a new session
- **THEN** CodeLab sends the currently selected project's path as `cwd` in `session/new`, the same as it would for stdio

#### Scenario: No project selected falls back to the current process directory
- **WHEN** the user creates a session and no project has been explicitly selected
- **THEN** CodeLab uses the same fallback it uses today (the CodeLab process's own current directory) as the session's `cwd`

#### Scenario: Switching connection does not clear the selected project
- **WHEN** the user reconnects or switches transport type while a project is selected
- **THEN** the selected project remains the same, and is used for the next session created after the switch

### Requirement: "Open Project" offers native browse and recent projects
CodeLab SHALL provide an "Open Project" affordance, reachable from the sessions sidebar, that lets the user pick a project directory via the operating system's native folder-selection dialog, and SHALL show a list of recently opened project directories for one-click reselection.

#### Scenario: Picking a folder via the native dialog
- **WHEN** the user selects "Browse for folder…" in the "Open Project" picker
- **THEN** CodeLab opens the operating system's native folder-selection dialog, and on a folder being chosen, sets it as the selected project

#### Scenario: Selecting a recent project
- **WHEN** the user opens "Open Project" and selects an entry from the recent-projects list
- **THEN** CodeLab sets that path as the selected project without opening the native folder dialog

#### Scenario: Currently selected project is visible without opening the picker
- **WHEN** a project is selected
- **THEN** the sessions sidebar shows that project's name (or path) in the "Open Project" row without requiring the user to open the picker

### Requirement: Recent projects persist across app restarts
CodeLab SHALL remember recently opened project directories across application restarts, on the local machine.

#### Scenario: A newly opened project appears in recents after restart
- **WHEN** the user opens a project directory (via browse or by it becoming the selected project) and then restarts CodeLab
- **THEN** that directory still appears in the "Open Project" recents list

#### Scenario: Recents list has a bound
- **WHEN** the number of distinct opened project directories exceeds the recents list's capacity
- **THEN** CodeLab keeps only the most recently opened entries, dropping the least recently used ones, rather than growing the list without bound
