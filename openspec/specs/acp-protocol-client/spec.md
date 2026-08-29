## Purpose

CodeLab's implementation of the Agent Client Protocol (ACP) itself — JSON-RPC 2.0 message handling, the `initialize` handshake, session setup, the prompt turn lifecycle, and idempotent handling of the resulting event stream. This capability is the wire-protocol boundary between CodeLab and any ACP-compliant agent; `docs/acp/protocol/` is its normative source.

## Requirements

### Requirement: Official ACP source of truth
CodeLab SHALL implement ACP behavior according to `docs/acp/protocol/` and `docs/acp/protocol/17-Schema.md`.

#### Scenario: Protocol contract changes
- **WHEN** ACP message models or methods are implemented
- **THEN** they match the official protocol docs and schema files

#### Scenario: Custom extension is needed
- **WHEN** CodeLab adds custom protocol data or methods
- **THEN** custom data uses `_meta` and custom method names start with `_`

### Requirement: JSON-RPC 2.0 message handling
CodeLab SHALL encode, decode, and validate ACP messages as JSON-RPC 2.0 requests, responses, and notifications.

#### Scenario: Valid inbound message
- **WHEN** a valid ACP JSON-RPC message is received
- **THEN** `acp_protocol` decodes it into a typed model

#### Scenario: Invalid inbound message
- **WHEN** invalid JSON or invalid ACP shape is received
- **THEN** CodeLab emits a typed protocol error and does not crash

### Requirement: Initialization and capabilities
CodeLab SHALL perform `initialize` before session setup and SHALL honor negotiated protocol version and capabilities.

#### Scenario: Compatible protocol version
- **WHEN** agent responds to `initialize` with a supported `protocolVersion`
- **THEN** CodeLab stores agent info, capabilities, and enters ready-for-session state

#### Scenario: Unsupported protocol version
- **WHEN** agent responds with an unsupported `protocolVersion`
- **THEN** CodeLab closes the connection and shows a user-readable compatibility error

### Requirement: Session setup
CodeLab SHALL support `session/new` and SHALL call `session/load` only when `agentCapabilities.loadSession` is available.

#### Scenario: New session is created
- **WHEN** user creates a session
- **THEN** CodeLab sends `session/new` with absolute `cwd` and stores returned `sessionId`

#### Scenario: Load session is unsupported
- **WHEN** agent does not advertise `loadSession`
- **THEN** CodeLab does not offer or call `session/load`

### Requirement: Prompt turn lifecycle
CodeLab SHALL support `session/prompt`, streamed `session/update`, `session/request_permission`, `session/cancel`, and final `session/prompt` response with `stopReason`.

#### Scenario: Prompt streams updates
- **WHEN** user sends a prompt
- **THEN** CodeLab sends `session/prompt` and renders incoming `session/update` notifications as typed timeline events

#### Scenario: Prompt completes
- **WHEN** agent responds to `session/prompt` with `stopReason`
- **THEN** CodeLab marks the active prompt turn as completed, failed, refused, maxed, or cancelled according to the stop reason

### Requirement: Idempotent state transitions
CodeLab SHALL handle duplicate, late, or interleaved stream events without corrupting visible session state.

#### Scenario: Duplicate update arrives
- **WHEN** the same session update is delivered more than once
- **THEN** CodeLab does not duplicate visible messages, approvals, or tool call records

#### Scenario: Late update after cancel
- **WHEN** a late `session/update` arrives after `session/cancel` but before prompt response
- **THEN** CodeLab accepts it without moving the turn out of cancellation flow
