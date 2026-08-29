## Purpose

The testing and workspace-quality bar CodeLab holds itself to: the Melos scripts every change is checked against, and the layered test coverage (protocol, core state, stdio integration, Flutter UI) that backs the Definition of Done for implementation tasks.

## Requirements

### Requirement: Workspace checks
CodeLab SHALL provide Melos scripts for format, analyze, test, protocol conformance, and full check.

#### Scenario: Full check runs
- **WHEN** `fvm dart run melos run check` is executed in a bootstrapped workspace
- **THEN** formatting, analysis, and tests pass or report actionable failures

#### Scenario: Protocol changed
- **WHEN** ACP protocol models, codecs, or flows change
- **THEN** `fvm dart run melos run protocol-conformance` is run

### Requirement: Protocol unit tests
CodeLab SHALL test protocol encode/decode, unknown field handling, invalid message validation, and protocol error mapping.

#### Scenario: Unknown fields are decoded
- **WHEN** a valid ACP message includes `_meta` or future-compatible fields
- **THEN** round-trip encode/decode preserves supported extension data

#### Scenario: Invalid message is decoded
- **WHEN** invalid ACP data is received
- **THEN** tests verify a typed protocol error instead of an app crash

### Requirement: Core state tests
CodeLab SHALL test session state transitions, duplicate streaming event handling, approval policy, and cancellation paths.

#### Scenario: Duplicate stream event is received
- **WHEN** the same update is emitted twice by fake transport
- **THEN** visible state contains one logical message/tool/approval record

#### Scenario: Cancellation has pending approvals
- **WHEN** cancellation occurs with pending permission requests
- **THEN** tests verify each request receives cancelled outcome

### Requirement: Stdio integration tests
CodeLab SHALL test stdio integration with `codelab-agent` or a compatible test double using the same launch/profile semantics.

#### Scenario: Reference agent initializes
- **WHEN** stdio integration test launches configured command
- **THEN** CodeLab completes ACP `initialize`

#### Scenario: Prompt turn streams
- **WHEN** integration test sends `session/prompt`
- **THEN** CodeLab receives streamed `session/update` and final prompt response

### Requirement: Flutter UI tests
CodeLab SHALL test connection states, prompt composer behavior, streaming transcript rendering, approvals, cancellation visibility, error states, and workbench layout.

#### Scenario: Approval UI renders
- **WHEN** an approval state is provided to UI
- **THEN** inline approval and inspector details are visible with approve/reject controls

#### Scenario: Error state renders next action
- **WHEN** UI receives disconnected or failed state
- **THEN** it shows a user-readable summary and concrete recovery action

### Requirement: Definition of Done enforcement
CodeLab SHALL treat tests, architecture boundaries, safety policy, and UI/UX requirements as acceptance criteria for implementation tasks.

#### Scenario: Implementation task completes
- **WHEN** a task is marked done
- **THEN** relevant tests pass and the task satisfies the Definition of Done in the spec
