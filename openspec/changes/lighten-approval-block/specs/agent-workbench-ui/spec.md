## MODIFIED Requirements

### Requirement: Tool call as a one-line row
Each tool call SHALL be shown as one row with a status glyph, a label by the tool call's kind, a detail and a status tag, following `ToolRowView` from the client kit (requirement "Строка инструмента без сырого JSON" of `acp-client-kit`). The row SHALL NOT show the protocol kind name or raw JSON. The status tag SHALL read "Queued", "Running", "Done", "Failed" or "Cancelled" by the tool call status. A row with a secondary line or text output SHALL be expandable: expanded, it SHALL show the secondary line and the text output. In `summary` and `normal` rows SHALL be collapsed by default and in `verbose` expanded; a row with a pending approval SHALL always be expanded.

While the tool call has a pending approval, its row SHALL show instead of the status tag the approval risk as a tag ("Read-only", "Local write", "Network", "Shell", "Destructive"), and its detail SHALL be the full subject of the request — the command for a tool call of kind `execute` — without truncation: the detail SHALL wrap up to three lines, and a longer detail SHALL offer "Show full command" that shows the rest in place. The row SHALL be marked by an accent stripe on its leading edge.

#### Scenario: Completed read
- **WHEN** the agent reads `lib/main.dart` with a tool call of kind `read` that completes
- **THEN** the transcript shows one row "Read lib/main.dart" with the tag "Done", without the words `read` or `completed` and without its `rawInput`

#### Scenario: Command awaiting approval
- **WHEN** a tool call of kind `execute` with `rawInput.command` "echo running tests" waits for an approval with the risk `shell`
- **THEN** its row reads "Run echo running tests" with the tag "Shell", has an accent stripe on its leading edge and is expanded with the approval prompt

#### Scenario: Long command is never cut before the decision
- **WHEN** a tool call of kind `execute` waits for an approval with a command longer than three lines of the row
- **THEN** the row shows the first three lines of the command and "Show full command", and choosing "Show full command" shows the whole command without an ellipsis

#### Scenario: Failed call shows its reason when expanded
- **WHEN** a tool call fails with the text content "File not found: lib/main.dart" and the user expands its row
- **THEN** the row shows "File not found: lib/main.dart" below its header

### Requirement: Approval card inside the tool call row
A pending approval SHALL be shown inside its tool call row as one decision line below the row header, not as a separate card. The decision line SHALL start with a question by the tool call's kind:

| Kind | Question |
|---|---|
| `execute` | Allow this command? |
| `edit` | Allow this edit? |
| `delete` | Allow deleting this file? |
| `move` | Allow this move? |
| `read` | Allow reading this file? |
| `search` | Allow this search? |
| `fetch` | Allow this request? |
| `think`, `other` | Allow this tool call? |

The decision line SHALL show two buttons: the `allow_once` option as the primary button and the `reject_once` option as a standard button; when the request has no `allow_once` option, the first allow option SHALL take its place, and when it has no `reject_once` option, the first reject option SHALL. Every other option and "View raw input" SHALL be items of a "More options" menu on the same line. Each button and menu item SHALL show its option's shortcut; option shortcuts SHALL stay as in requirement "Approval options are rendered and bound to shortcuts by kind" and SHALL work whether the option is a button or a menu item. The reason, when present, SHALL be shown as a muted line below the question. The raw input SHALL stay collapsed until the user chooses "View raw input", as in requirement "Approval panel offers a collapsed raw input view". The decision line SHALL NOT repeat the command shown in the row header. After the decision the decision line SHALL be replaced by a tag in the tool call row naming the outcome, as in requirement "Паттерны взаимодействия agent workbench".

#### Scenario: Command approval prompt
- **WHEN** a tool call of kind `execute` with command "echo running tests" asks for permission with the four standard option kinds
- **THEN** below the row header one line reads "Allow this command?" with the primary button "Allow once", the standard button "Reject" and a "More options" button, and the command is not shown a second time

#### Scenario: Always options live in the menu
- **WHEN** the user opens "More options" on that approval
- **THEN** the menu lists the `allow_always` and `reject_always` options with their shortcuts and "View raw input"

#### Scenario: Shortcut of a menu option
- **WHEN** the approval is focused and the user presses the shortcut of `allow_always` without opening the menu
- **THEN** CodeLab selects the `allow_always` option for that approval

#### Scenario: Decision leaves a tag
- **WHEN** the user chooses "Allow once"
- **THEN** the decision line disappears and the tool call row shows a tag "Allow once" with a success tone
