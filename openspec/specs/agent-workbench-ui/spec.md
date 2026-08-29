## Purpose

The Fluent-based desktop workbench UI: layout, Atomic Design widget organization in `acp_ui`, the interaction patterns an agent workbench needs (sessions sidebar, approvals, view modes, command palette, etc.), and keyboard-first ergonomics.

## Requirements

### Requirement: Fluent desktop workbench
CodeLab SHALL use `fluent_ui` as the base Flutter UI framework and SHALL NOT use Material/Cupertino as the base design framework.

#### Scenario: UI framework is checked
- **WHEN** UI packages are analyzed
- **THEN** public CodeLab UI components are built with `fluent_ui`

#### Scenario: Compatibility import is needed
- **WHEN** a third-party package requires Material/Cupertino compatibility
- **THEN** the import is isolated and does not define CodeLab public UI style

### Requirement: Workbench layout
CodeLab SHALL provide a desktop workbench layout with command bar, sessions pane, transcript/prompt area, and inspector.

#### Scenario: Main workspace opens
- **WHEN** user opens CodeLab
- **THEN** the first screen is the usable client workbench, not a marketing page

#### Scenario: Narrow window adapts
- **WHEN** available width is constrained
- **THEN** sessions pane compacts and inspector can collapse without hiding prompt composer or cancel state

### Requirement: Atomic Design widget organization
CodeLab SHALL organize reusable `acp_ui` widgets under `atomics`, `molecules`, and `organisms`.

#### Scenario: Atomic widget is added
- **WHEN** a minimal reusable control is implemented
- **THEN** it is placed under `atomics`

#### Scenario: Workflow panel is added
- **WHEN** a large workflow block such as transcript, approval, or session sidebar is implemented
- **THEN** it is placed under `organisms`

### Requirement: Agent workbench interaction patterns
CodeLab SHALL support sessions/tasks sidebar, prompt-area control strip, permission mode selector, plan mode, inline approvals, view modes, progress checklist, inspector-first details, command palette or slash commands, review-first changes, session isolation, compact transcript, and context indicators.

#### Scenario: Pending approval is shown
- **WHEN** agent requests permission during a prompt turn
- **THEN** approval appears inline in transcript and in inspector with risk, reason, command/cwd/diff when available

#### Scenario: View mode changes
- **WHEN** user selects `summary`, `normal`, or `verbose`
- **THEN** transcript and tool call details adjust their verbosity without losing data

#### Scenario: Switching sessions shows only that session's own state
- **WHEN** user switches the active session (via the sidebar, or by creating a new one)
- **THEN** CodeLab shows that session's own transcript, inspector entries, and pending approval (if any) — never state left over from the previously active session

### Requirement: Keyboard-first desktop UX
CodeLab SHALL support keyboard ergonomics for prompt submit, cancel, approve/reject, inspector navigation, and command palette or slash commands.

#### Scenario: User submits prompt from keyboard
- **WHEN** focus is in prompt composer and user invokes submit shortcut
- **THEN** CodeLab sends the prompt without requiring pointer interaction

#### Scenario: User opens command palette
- **WHEN** user invokes command palette shortcut
- **THEN** CodeLab presents core actions such as `/new`, `/plan`, `/permissions`, `/logs`, `/compact`, and `/reconnect`

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

### Requirement: Command palette opens inline from the prompt composer
CodeLab SHALL open the command palette inline, anchored above the prompt composer and without moving keyboard focus away from it, when the user types `/` as the first character of a new word in the composer's input, and SHALL filter the visible commands live as the user continues typing in the composer.

#### Scenario: Slash at the start of a word opens the inline palette
- **WHEN** the composer is empty or the cursor is immediately after whitespace, and the user types `/`
- **THEN** CodeLab shows the command palette anchored above the composer, focus remains in the composer's text input

#### Scenario: Slash inside a word does not open the palette
- **WHEN** the user types `/` immediately after a non-whitespace character (e.g. as part of a path or URL already being typed)
- **THEN** CodeLab does not open the command palette

#### Scenario: Continuing to type filters the inline list
- **WHEN** the inline command palette is open and the user types additional characters in the composer
- **THEN** CodeLab filters the visible commands to match the text typed after the triggering `/`

#### Scenario: Enter selects the highlighted command while the inline palette is open
- **WHEN** the inline command palette is open and the user presses `Enter`
- **THEN** CodeLab selects the currently highlighted command instead of inserting a newline into the composer

#### Scenario: Selecting a command from the inline palette clears the trigger text
- **WHEN** user selects a command from the inline palette
- **THEN** CodeLab removes the `/word` fragment from the composer text and executes the command the same way as when selected via the keyboard-shortcut-triggered palette

#### Scenario: Deleting the triggering slash closes the inline palette
- **WHEN** the inline command palette is open and the user deletes the `/` character that triggered it
- **THEN** CodeLab closes the inline palette without executing any command

### Requirement: Command palette marks unimplemented actions as unavailable
CodeLab SHALL present `/plan`, `/permissions`, and `/compact` in the command palette as visibly unavailable actions rather than silently doing nothing when selected, until each underlying capability (plan mode, permission-mode selector, transcript compaction) is implemented.

#### Scenario: Selecting an unavailable command
- **WHEN** command palette is open and user selects `/plan`, `/permissions`, or `/compact`
- **THEN** CodeLab shows the command as disabled/labeled "coming soon" and does not close the palette or emit a fake diagnostic implying the action completed

#### Scenario: Enter highlights an unavailable command in the inline palette
- **WHEN** the inline command palette is open, an unavailable command (`/plan`, `/permissions`, or `/compact`) is the currently highlighted entry, and the user presses `Enter`
- **THEN** CodeLab treats this the same as any other selection of that command — the palette stays open, no action is emitted, and the composer text is unchanged

### Requirement: Command palette presents agent-advertised commands
CodeLab SHALL present commands the active agent has declared through `SessionUpdate.availableCommandsUpdate` in the command palette (both the `Ctrl/Cmd+K` surface and the inline `/` trigger), visually distinguished from the six client-native commands, and SHALL NOT invoke them as a protocol method — selecting one SHALL insert `/{name} ` (plus the declared input hint, if any, as placeholder text) into the prompt composer instead, leaving the user to complete and submit it as an ordinary prompt.

#### Scenario: Agent declares available commands
- **WHEN** the active session receives a `SessionUpdate.availableCommandsUpdate` with one or more entries
- **THEN** CodeLab adds those commands to the palette in a section visually separate from the six client-native commands, without removing or replacing any client-native command

#### Scenario: A later update replaces the agent command list
- **WHEN** a new `SessionUpdate.availableCommandsUpdate` arrives for the active session
- **THEN** CodeLab replaces the previously displayed agent-declared commands with the entries from the new update

#### Scenario: No agent commands declared
- **WHEN** the active session has not received any `availableCommandsUpdate`
- **THEN** CodeLab shows only the six client-native commands in the palette

#### Scenario: Selecting an agent-declared command
- **WHEN** user selects a command that came from `availableCommandsUpdate`
- **THEN** CodeLab inserts `/{name} ` (and the command's input hint as placeholder text, if the command declares one) into the prompt composer, closes the palette, and does not call any protocol method — the user submits it themselves via the normal prompt flow

#### Scenario: Switching sessions shows that session's own agent-declared commands
- **WHEN** the active session changes
- **THEN** CodeLab shows the newly active session's own agent-declared commands — restored from that session's last `availableCommandsUpdate` if it sent one, or empty if it has not — never the previous session's list
