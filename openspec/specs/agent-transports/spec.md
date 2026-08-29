## Purpose

The replaceable transport layer connecting CodeLab to an ACP agent process or endpoint — a common transport port, concrete stdio and WebSocket implementations, the built-in `Codelab Agent` reference profile, and the fake/test doubles used to drive the rest of the app without a real agent.

## Requirements

### Requirement: Common transport port
CodeLab SHALL expose a common transport abstraction for inbound messages, outbound sends, lifecycle events, graceful shutdown, and typed errors.

#### Scenario: Transport is replaceable
- **WHEN** core logic sends or receives ACP messages
- **THEN** it works through the transport port and not through stdio/WebSocket concrete classes

#### Scenario: Transport fails
- **WHEN** transport connection fails
- **THEN** CodeLab maps the failure to a typed transport state and user-readable diagnostic

### Requirement: Stdio transport
CodeLab SHALL support local ACP agents over JSON-RPC 2.0 over stdio.

#### Scenario: Child process starts
- **WHEN** user connects through stdio
- **THEN** CodeLab launches the configured command as a child process with configured args, cwd, and env

#### Scenario: Protocol and diagnostics streams are separated
- **WHEN** the child process writes to stdout and stderr
- **THEN** stdout is parsed as ACP protocol stream and stderr is shown as diagnostics/log stream

### Requirement: Reference codelab-agent profile
CodeLab SHALL provide a built-in editable stdio profile for `https://github.com/pese-git/codelab-agent`.

#### Scenario: Default profile is shown
- **WHEN** user opens connection setup
- **THEN** CodeLab offers `Codelab Agent` with command `codelab`, args `serve --stdio`, and env `CODELAB_LOG_LEVEL=DEBUG`

#### Scenario: Default profile connects
- **WHEN** user starts the default profile in an environment with `codelab` available
- **THEN** CodeLab launches `codelab serve --stdio` and performs ACP `initialize`

### Requirement: WebSocket transport
CodeLab SHALL support remote ACP agents over WebSocket for MVP remote workflows.

#### Scenario: Remote agent connects
- **WHEN** user configures a WebSocket endpoint and token/header if required
- **THEN** CodeLab opens the connection and performs ACP initialization over WebSocket

#### Scenario: WebSocket disconnects
- **WHEN** the WebSocket closes unexpectedly
- **THEN** CodeLab enters disconnected state and offers reconnect

### Requirement: Transport testing
CodeLab SHALL include fake transport and integration tests for stdio and codelab-agent compatibility.

#### Scenario: Fake transport drives core tests
- **WHEN** core state-machine tests run
- **THEN** fake transport can emit inbound messages and capture outbound messages deterministically

#### Scenario: Stdio integration handles process errors
- **WHEN** codelab-agent exits, emits invalid JSON, or writes stderr diagnostics
- **THEN** CodeLab records typed states and diagnostics without crashing
