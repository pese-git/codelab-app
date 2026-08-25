## ADDED Requirements

### Requirement: Collapsible terminal panel with multiple tabs
CodeLab SHALL provide a collapsible terminal panel docked at the bottom of the workbench, supporting multiple independent terminal tabs, collapsed by default.

#### Scenario: Expanding the terminal panel
- **WHEN** user expands the collapsed terminal bar
- **THEN** CodeLab shows the terminal panel with at least one active tab and a way to open additional tabs

#### Scenario: Closing a terminal tab
- **WHEN** user closes a terminal tab
- **THEN** CodeLab terminates the underlying process for that tab and removes the tab

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
