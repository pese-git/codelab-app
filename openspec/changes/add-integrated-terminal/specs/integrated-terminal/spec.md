## ADDED Requirements

### Requirement: Terminal pane in the tool dock with multiple tabs
CodeLab SHALL provide a terminal pane in the workbench tool dock on the right side of the workbench, alongside the other tool panes, supporting multiple independent terminal tabs. The pane SHALL be closed by default and opened from the app bar toggle, a keyboard shortcut or the command palette.

#### Scenario: Opening the terminal pane
- **WHEN** user turns on the Terminal toggle in the app bar
- **THEN** CodeLab shows the terminal pane in the tool dock with at least one active tab and a way to open additional tabs

#### Scenario: Closing a terminal tab
- **WHEN** user closes a terminal tab
- **THEN** CodeLab terminates the underlying process for that tab and removes the tab

#### Scenario: Terminal tabs belong to the focused session
- **WHEN** two sessions are shown side by side and the user moves focus from one to the other
- **THEN** the terminal pane shows the tabs of the focused session, and the processes of the other session's tabs keep running

#### Scenario: Closing the pane keeps terminal sessions
- **WHEN** user closes the terminal pane in the tool dock
- **THEN** the open terminal tabs, their processes and scrollback are kept and shown again when the pane is reopened

#### Scenario: Terminal processes are cleaned up on app close
- **WHEN** CodeLab is closed while terminal tabs are open
- **THEN** all terminal child processes are terminated, none are left running

### Requirement: Terminal starts in the active transport's working directory
CodeLab SHALL start a new terminal tab in the working directory of the active transport profile at the moment the tab is created, and SHALL NOT propagate directory changes made inside the terminal back to the transport configuration.

#### Scenario: New tab uses current profile cwd
- **WHEN** user opens a new terminal tab
- **THEN** the shell starts in the working directory currently configured for the active transport profile

#### Scenario: cd inside terminal does not affect transport config
- **WHEN** user changes directory inside an open terminal tab
- **THEN** the transport profile's working directory field remains unchanged

### Requirement: Terminal is outside the approval-safety flow
CodeLab SHALL clearly indicate that commands run in the terminal panel execute directly as the user and are not subject to the agent's approval-safety permission modes or risk classification.

#### Scenario: First-open disclosure
- **WHEN** user opens the terminal panel for the first time in a session
- **THEN** CodeLab shows a visible notice that terminal commands bypass the agent approval flow and are not secret-redacted

### Requirement: Terminal output is not secret-redacted
CodeLab SHALL NOT apply `SecretRedactor` or any equivalent structured-log redaction to terminal output, and SHALL disclose this to the user rather than implying protection that does not exist.

#### Scenario: Terminal output shown as-is
- **WHEN** a command run in the terminal prints a value that would normally be redacted in diagnostics/logs
- **THEN** CodeLab displays it unmodified in the terminal, consistent with the first-open disclosure
