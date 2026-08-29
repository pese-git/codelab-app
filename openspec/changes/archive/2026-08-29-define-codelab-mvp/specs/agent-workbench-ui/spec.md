## ADDED Requirements

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

### Requirement: Keyboard-first desktop UX
CodeLab SHALL support keyboard ergonomics for prompt submit, cancel, approve/reject, inspector navigation, and command palette or slash commands.

#### Scenario: User submits prompt from keyboard
- **WHEN** focus is in prompt composer and user invokes submit shortcut
- **THEN** CodeLab sends the prompt without requiring pointer interaction

#### Scenario: User opens command palette
- **WHEN** user invokes command palette shortcut
- **THEN** CodeLab presents core actions such as `/new`, `/plan`, `/permissions`, `/logs`, `/compact`, and `/reconnect`
