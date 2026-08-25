## ADDED Requirements

### Requirement: Command palette opens and executes available actions
CodeLab SHALL open `AcpCommandPaletteSurface` when the command palette shortcut is invoked, and SHALL execute `/new` (create session) and `/reconnect` (reconnect active transport) immediately when selected, closing the palette afterward.

#### Scenario: Opening the command palette shows the surface
- **WHEN** user invokes the command palette shortcut (`Ctrl/Cmd+K`)
- **THEN** CodeLab displays `AcpCommandPaletteSurface` over the workbench

#### Scenario: Closing the command palette
- **WHEN** command palette is open and user presses `Esc`, or selects an available command
- **THEN** CodeLab hides `AcpCommandPaletteSurface` and returns keyboard focus to the workbench

#### Scenario: Selecting /new creates a session
- **WHEN** command palette is open and user selects `/new`
- **THEN** CodeLab creates a new session via the existing session-creation flow and closes the palette

#### Scenario: Selecting /reconnect reconnects the active transport
- **WHEN** command palette is open and user selects `/reconnect`
- **THEN** CodeLab invokes the existing reconnect flow for the active transport and closes the palette

#### Scenario: Selecting /logs reveals the debug log panel
- **WHEN** command palette is open and user selects `/logs`
- **THEN** CodeLab ensures the debug log panel is visible (expanding the inspector if it is currently collapsed by narrow-layout mode) and closes the palette

### Requirement: Command palette marks unimplemented actions as unavailable
CodeLab SHALL present `/plan`, `/permissions`, and `/compact` in the command palette as visibly unavailable actions rather than silently doing nothing when selected, until each underlying capability (plan mode, permission-mode selector, transcript compaction) is implemented.

#### Scenario: Selecting an unavailable command
- **WHEN** command palette is open and user selects `/plan`, `/permissions`, or `/compact`
- **THEN** CodeLab shows the command as disabled/labeled "coming soon" and does not close the palette or emit a fake diagnostic implying the action completed
