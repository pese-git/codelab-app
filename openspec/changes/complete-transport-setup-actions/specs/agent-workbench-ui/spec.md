## ADDED Requirements

### Requirement: Edit profile focuses the transport form
CodeLab SHALL move keyboard focus to, and scroll into view, the primary field of the active transport profile (Command for stdio, Endpoint for WebSocket) when the user selects "Edit profile" on the connection screen.

#### Scenario: Edit profile on stdio transport
- **WHEN** the active transport type is stdio and user selects "Edit profile"
- **THEN** CodeLab scrolls the transport setup form into view and focuses the Command field

#### Scenario: Edit profile on WebSocket transport
- **WHEN** the active transport type is WebSocket and user selects "Edit profile"
- **THEN** CodeLab scrolls the transport setup form into view and focuses the Endpoint field
