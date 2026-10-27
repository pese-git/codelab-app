## MODIFIED Requirements

### Requirement: Session pane header
The session pane SHALL have a header with the session title, a project chip named after the folder of the session's `cwd` with the full path as a tooltip, and a mode chip when the agent publishes a mode config option. While the session is busy, the header SHALL show a turn state chip: "Turn running" with a progress indicator while a turn runs, "Waiting for approval" while the turn waits for a pending approval, and "Cancelling…" while a cancellation awaits the agent's answer. An idle, failed or detached session SHALL show no turn state chip.

#### Scenario: Header of an active session
- **WHEN** a session titled "Fix reconnect race" in `/work/codelab-app` is active and the agent publishes the mode "standard"
- **THEN** the header shows "Fix reconnect race", a "codelab-app" chip with the tooltip `/work/codelab-app`, and a "standard" chip

#### Scenario: Turn state in the header
- **WHEN** the active session runs a turn, then the turn waits for an approval, then the user approves and the turn ends
- **THEN** the header shows "Turn running", then "Waiting for approval", then "Turn running", and no turn state chip after the turn ends

## ADDED Requirements

### Requirement: Transcript reads as a conversation
The transcript SHALL be laid out as a conversation in a column centred in the session pane, at most 760 px wide, without a frame around the transcript. A user message SHALL be a bubble aligned to the right, at most 78% of the column width, without a "You" label. An agent reply SHALL be plain text in the column without a card and without an "Agent" label. Consecutive rows SHALL be separated by spacing, not by per-row cards.

#### Scenario: A prompt and its reply
- **WHEN** the user sends "Render replies as markdown" and the agent answers "I'll split the transcript into typed rows."
- **THEN** the transcript shows the prompt in a right-aligned bubble and the answer as plain text below it, and neither row shows a "You" or "Agent" label

#### Scenario: Wide window keeps a readable column
- **WHEN** the session pane is 1200 px wide
- **THEN** the transcript column is 760 px wide and centred in the pane

### Requirement: Model thoughts in a collapsible block
Each `agent_thought_chunk` segment SHALL be shown as a thought block distinct from the agent reply: muted text, a thought icon and a header. While the thought is streaming (it is the last transcript item of a running turn), the header SHALL read "Thinking…" with a progress indicator and the block SHALL be expanded. After the thought ends, the header SHALL read "Thoughts" and the block SHALL collapse to its header without animation. The user's manual choice to expand or collapse a block SHALL win over these defaults and SHALL survive the row scrolling out of view. In `verbose` the block SHALL be expanded by default; in `summary` it SHALL stay a one-line header. Thought text SHALL be shown as is, without markdown, and SHALL NOT be part of the agent reply.

#### Scenario: Thought while streaming
- **WHEN** the agent streams `agent_thought_chunk` updates and nothing else yet
- **THEN** the transcript shows an expanded block headed "Thinking…" with a progress indicator and the thought text

#### Scenario: Thought collapses when the reply starts
- **WHEN** after the thought the agent streams `agent_message_chunk` updates
- **THEN** the thought block collapses to its header "Thoughts", and the reply text is shown below it as plain text

#### Scenario: The user's choice wins
- **WHEN** the user expands a finished thought block, scrolls it out of view and back
- **THEN** the block is still expanded

### Requirement: Tool call as a one-line row
Each tool call SHALL be shown as one row with a status glyph, a label by the tool call's kind, a detail and a status tag, following `ToolRowView` from the client kit (requirement "Строка инструмента без сырого JSON" of `acp-client-kit`). The row SHALL NOT show the protocol kind name or raw JSON. The status tag SHALL read "Queued", "Running", "Done", "Failed" or "Cancelled" by the tool call status, and "Awaiting approval" while the tool call has a pending approval. A row with a secondary line or text output SHALL be expandable: expanded, it SHALL show the secondary line and the text output. In `summary` and `normal` rows SHALL be collapsed by default and in `verbose` expanded; a row with a pending approval SHALL always be expanded.

#### Scenario: Completed read
- **WHEN** the agent reads `lib/main.dart` with a tool call of kind `read` that completes
- **THEN** the transcript shows one row "Read lib/main.dart" with the tag "Done", without the words `read` or `completed` and without its `rawInput`

#### Scenario: Command awaiting approval
- **WHEN** a tool call of kind `execute` with `rawInput.command` "echo running tests" waits for an approval
- **THEN** its row reads "Run echo running tests" with the tag "Awaiting approval" and is expanded with the approval card

#### Scenario: Failed call shows its reason when expanded
- **WHEN** a tool call fails with the text content "File not found: lib/main.dart" and the user expands its row
- **THEN** the row shows "File not found: lib/main.dart" below its header

### Requirement: Approval card inside the tool call row
A pending approval SHALL be shown as a card inside its tool call row. The card SHALL have a title by the tool call's kind:

| Kind | Title |
|---|---|
| `execute` | Run a command? |
| `edit` | Edit a file? |
| `delete` | Delete a file? |
| `move` | Move a file? |
| `read` | Read a file? |
| `search` | Run a search? |
| `fetch` | Fetch a URL? |
| `think`, `other` | Allow this tool call? |

The card SHALL show the tag "Awaiting approval", the approval risk, the reason when present, the command in a monospace terminal-styled block with the `cwd` as a caption when present, and the options. The `allow_once` option SHALL be the primary button; the other options SHALL be standard buttons. Option shortcuts SHALL stay as in requirement "Approval options are rendered and bound to shortcuts by kind", and the raw input SHALL stay behind "View raw input". After the decision the card SHALL be replaced by a tag in the tool call row naming the outcome, as in requirement "Паттерны взаимодействия agent workbench".

#### Scenario: Command approval card
- **WHEN** a tool call of kind `execute` with command "echo running tests" in `/work/app` asks for permission with the four standard option kinds
- **THEN** the card is titled "Run a command?", shows "echo running tests" in a terminal-styled block with `/work/app` below it, and "Allow once" is the only primary button

#### Scenario: Decision leaves a tag
- **WHEN** the user chooses "Allow once"
- **THEN** the card disappears and the tool call row shows a tag "Allow once" with a success tone

### Requirement: Transcript notices by severity
Transcript notices SHALL be styled by their kind. A failed turn notice SHALL be an error InfoBar, as in requirement "Failed turn notice with Retry". A detached session notice SHALL be a warning InfoBar. A notice that a new session was started instead of a restored one, a session reconnection notice, and an empty turn notice SHALL be a neutral one-line note with an info icon. Only the failed turn notice SHALL use the error tone.

#### Scenario: New session after a failed restore
- **WHEN** the agent cannot restore sessions and the workspace starts a new session with a notice
- **THEN** the transcript shows "The agent cannot restore sessions; a new session was started." as a neutral note, not as an error

### Requirement: Empty session after connecting
When the connection is established and the active session has no transcript items, the session pane SHALL show an empty state inviting the user to send the first message instead of the connection screen. The connection screen SHALL be shown only while the connection is not established.

#### Scenario: New session while connected
- **WHEN** the connection is established and the user creates a new session
- **THEN** the session pane shows the empty state with the composer focused, and no Connect button
