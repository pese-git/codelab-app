## ADDED Requirements

### Requirement: Risk levels
CodeLab SHALL classify agent actions into risk levels `readOnly`, `localWrite`, `network`, `shell`, and `destructive`.

#### Scenario: Tool call is displayed
- **WHEN** a tool call or permission request is received
- **THEN** CodeLab displays the risk level before any approval action

#### Scenario: Destructive action is requested
- **WHEN** an action can delete, reset, force push, migrate, or otherwise cause irreversible change
- **THEN** CodeLab requires explicit approval with exact command or diff when available

### Requirement: Permission modes
CodeLab SHALL provide MVP permission modes `readOnly`, `ask`, `plan`, and `autoEdits`, and SHALL NOT expose `bypass`/full-access mode in MVP.

#### Scenario: Plan mode is active
- **WHEN** permission mode is `plan`
- **THEN** agent can explore and propose a plan but source edits are not allowed

#### Scenario: Ask mode is active
- **WHEN** permission mode is `ask`
- **THEN** write, terminal, network, and destructive operations require explicit approval

### Requirement: ACP permission flow
CodeLab SHALL answer `session/request_permission` by selecting an agent-provided `PermissionOption` or returning outcome `cancelled`.

#### Scenario: User approves an option
- **WHEN** user selects an approval option
- **THEN** CodeLab returns `selected` with the selected `optionId`

#### Scenario: Turn is cancelled during approval
- **WHEN** prompt turn is cancelled while permission requests are pending
- **THEN** CodeLab responds to each pending request with outcome `cancelled`

### Requirement: Secret redaction
CodeLab SHALL redact secrets from logs, diagnostics, inspector details, and persisted/debug state.

#### Scenario: Environment variables are displayed
- **WHEN** launch environment is shown in diagnostics
- **THEN** values that look like tokens, passwords, API keys, or private keys are redacted

#### Scenario: Debug log is opened
- **WHEN** user opens debug/protocol log
- **THEN** sensitive prompts and secrets are hidden unless an explicit debug setting allows them

### Requirement: Review-first changes
CodeLab SHALL show reviewable details before applying or approving file edits and destructive actions.

#### Scenario: File edit is requested
- **WHEN** an edit action includes old and new content
- **THEN** CodeLab presents a diff before approval

#### Scenario: Terminal command is requested
- **WHEN** an execute action is requested
- **THEN** CodeLab shows command, args, cwd, risk, and reason before approval
