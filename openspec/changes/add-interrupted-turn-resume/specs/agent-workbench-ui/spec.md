## ADDED Requirements

### Requirement: Unfinished turn notice with Continue
When a loaded session has `SessionView.unfinishedTurn` (requirement "Продолжение незавершённого хода" of `acp-client-kit`; design.md change `add-interrupted-turn-resume`, D8), the transcript SHALL show a notice below the last turn. Its title SHALL be "The last turn did not finish". Its body SHALL be "Interrupted tool calls: <n>." when `n > 0`, otherwise "The agent stopped before it answered.". The notice SHALL offer a Continue action, enabled exactly when `SessionView.canContinue` is true. Selecting Continue SHALL call `continueTurn()` of the session. The notice SHALL disappear when `unfinishedTurn` becomes null.

The Cubit SHALL only map `SessionView` to the notice. Widgets SHALL NOT decide whether a turn is unfinished and SHALL NOT build the `/continue` prompt. The title, the body and the action label SHALL come from the app localization (English and Russian).

#### Scenario: Continue after an agent crash
- **WHEN** a session whose agent process died during `exec` is loaded after Reconnect, and the agent declares `continue`
- **THEN** the transcript shows "The last turn did not finish" with "Interrupted tool calls: 1." and an enabled Continue action; selecting it sends `/continue` as a new prompt, and the notice disappears

#### Scenario: Notice without the command
- **WHEN** the load response marks the turn unfinished, but the agent does not declare `continue`
- **THEN** the notice is shown with the Continue action disabled

#### Scenario: A regular prompt instead of Continue
- **WHEN** the notice is shown and the user sends a regular message
- **THEN** the notice disappears and the message is sent as usual
