## MODIFIED Requirements

### Requirement: WebSocket transport
CodeLab SHALL support remote ACP agents over WebSocket for MVP remote workflows, including user-initiated and automatic reconnect after disconnect.

#### Scenario: Remote agent connects
- **WHEN** user configures a WebSocket endpoint and token/header if required
- **THEN** CodeLab opens the connection and performs ACP initialization over WebSocket

#### Scenario: WebSocket disconnects
- **WHEN** the WebSocket closes unexpectedly
- **THEN** CodeLab enters disconnected state and offers reconnect

#### Scenario: User reconnects a WebSocket transport
- **WHEN** user selects reconnect while the active transport is WebSocket
- **THEN** CodeLab opens a new WebSocket connection using the current endpoint/token configuration and performs ACP initialization, updating connection status and diagnostics on success or failure

#### Scenario: WebSocket reconnect fails
- **WHEN** a WebSocket reconnect attempt fails (network error, auth failure, or protocol mismatch)
- **THEN** CodeLab sets connection status to failed and records a user-readable diagnostic describing the failure, without leaving the UI in the connecting state indefinitely
