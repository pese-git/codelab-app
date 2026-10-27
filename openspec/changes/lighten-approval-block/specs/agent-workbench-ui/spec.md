## MODIFIED Requirements

### Requirement: Tool call as a one-line row
Each tool call SHALL be shown as one row with a status glyph, a label by the tool call's kind, a detail and a status tag, following `ToolRowView` from the client kit (requirement "Строка инструмента без сырого JSON" of `acp-client-kit`). The row SHALL NOT show the protocol kind name or raw JSON. The status tag SHALL read "Queued", "Running", "Done", "Failed" or "Cancelled" by the tool call status. A row with a secondary line or text output SHALL be expandable: expanded, it SHALL show the secondary line and the text output. In `summary` and `normal` rows SHALL be collapsed by default and in `verbose` expanded; a row with a pending approval SHALL always be expanded.

While the tool call has a pending approval, its row SHALL show instead of the status tag the approval risk as a tag ("Read-only", "Local write", "Network", "Shell", "Destructive"), and its detail SHALL be the full subject of the request — the command for a tool call of kind `execute` — without truncation: the detail SHALL wrap up to three lines, and a longer detail SHALL offer "Show full command" that shows the rest in place.

#### Scenario: Completed read
- **WHEN** the agent reads `lib/main.dart` with a tool call of kind `read` that completes
- **THEN** the transcript shows one row "Read lib/main.dart" with the tag "Done", without the words `read` or `completed` and without its `rawInput`

#### Scenario: Command awaiting approval
- **WHEN** a tool call of kind `execute` with `rawInput.command` "echo running tests" waits for an approval with the risk `shell`
- **THEN** its row reads "Run echo running tests" with the tag "Shell" and is expanded with the decision bar

#### Scenario: Long command is never cut before the decision
- **WHEN** a tool call of kind `execute` waits for an approval with a command longer than three lines of the row
- **THEN** the row shows the first three lines of the command and "Show full command", and choosing "Show full command" shows the whole command without an ellipsis

#### Scenario: Failed call shows its reason when expanded
- **WHEN** a tool call fails with the text content "File not found: lib/main.dart" and the user expands its row
- **THEN** the row shows "File not found: lib/main.dart" below its header

### Requirement: Approval card inside the tool call row
A pending approval SHALL be shown inside its tool call row as one decision bar at the bottom of the row, not as a separate card. The decision bar SHALL separate the decision from its scope: it SHALL show an "Allow" button and a "Reject" button and a scope selector with "Only this time" and "Always". A button SHALL answer with the agent's option of its decision and the selected scope:

| Button | Only this time | Always |
|---|---|---|
| Allow | `allow_once` | `allow_always` |
| Reject | `reject_once` | `reject_always` |

The scope SHALL default to "Only this time" when the request has an `allow_once` or `reject_once` option, and to "Always" otherwise. A scope SHALL be offered only when the request has an option of that scope. A button whose decision has no option in the selected scope SHALL be disabled and SHALL say that the agent offers no such option. The "Always" scope SHALL show the names of the agent's `allow_always` and `reject_always` options. The scope SHALL apply to this approval only. Each button SHALL show the shortcut of the option it answers with; option shortcuts SHALL stay as in requirement "Approval options are rendered and bound to shortcuts by kind" and SHALL work whatever scope is selected. The decision bar SHALL NOT repeat the command shown in the row header and SHALL NOT carry a title. The reason, when present, SHALL be shown as a muted line above the decision bar. The raw input SHALL stay collapsed until the user chooses "View raw input" in the decision bar, as in requirement "Approval panel offers a collapsed raw input view". After the decision the decision bar SHALL be replaced by a tag in the tool call row naming the outcome, as in requirement "Паттерны взаимодействия agent workbench".

#### Scenario: Command decision bar
- **WHEN** a tool call of kind `execute` with command "echo running tests" asks for permission with the four standard option kinds
- **THEN** the bottom of its row shows "Allow", "Reject" and the scope "Only this time", and the command is not shown a second time

#### Scenario: Allow once by default
- **WHEN** the user chooses "Allow" without changing the scope
- **THEN** CodeLab selects the `allow_once` option for that approval

#### Scenario: Always is an explicit scope
- **WHEN** the user selects the scope "Always" and chooses "Reject"
- **THEN** CodeLab selects the `reject_always` option for that approval

#### Scenario: A scope without an option for a decision
- **WHEN** a request offers only `allow_always` and `reject_once` and the scope is "Only this time"
- **THEN** "Reject" is enabled, "Allow" is disabled and says the agent offers no such option, and selecting "Always" enables "Allow" and disables "Reject"

#### Scenario: Shortcut of an always option
- **WHEN** the approval is focused, the scope is "Only this time" and the user presses the shortcut of `allow_always`
- **THEN** CodeLab selects the `allow_always` option for that approval

#### Scenario: Decision leaves a tag
- **WHEN** the user chooses "Allow" with the scope "Only this time" and the agent's `allow_once` option is named "Allow once"
- **THEN** the decision bar disappears and the tool call row shows a tag "Allow once" with a success tone
