## ADDED Requirements

### Requirement: Messages queue instead of failing when the session is busy
CodeLab SHALL queue a submitted prompt client-side, without attempting to send it and without losing the typed text, when the active session cannot currently accept a new prompt turn (a turn is running or an approval is pending), instead of attempting the send and showing a failure.

#### Scenario: Submitting while awaiting approval queues the message
- **WHEN** user submits a prompt while the active session has a pending approval
- **THEN** CodeLab adds the message to the queue instead of sending it, and does not show a "prompt failed" entry in the transcript

#### Scenario: Submitting while a turn is running queues the message
- **WHEN** user submits a prompt while the active session's turn is still running
- **THEN** CodeLab adds the message to the queue instead of attempting to send it

#### Scenario: Submitting while the session is free sends immediately
- **WHEN** user submits a prompt while the active session is idle or active
- **THEN** CodeLab sends it immediately, unchanged from current behavior

### Requirement: Queued messages panel with per-item and bulk actions
CodeLab SHALL show a queued-messages panel, visible only when the queue is non-empty, offering Edit, Delete, and Send Now per item, and Clear All for the whole queue.

#### Scenario: Editing a queued message
- **WHEN** user selects Edit on a queued message
- **THEN** CodeLab removes it from the queue and places its text back into the prompt composer for editing

#### Scenario: Deleting a queued message
- **WHEN** user selects Delete on a queued message
- **THEN** CodeLab removes it from the queue without sending it

#### Scenario: Send Now attempts immediate delivery
- **WHEN** user selects Send Now on a queued message and the session is currently free
- **THEN** CodeLab sends that message immediately, out of FIFO order

#### Scenario: Send Now during a race returns the message to the queue
- **WHEN** user selects Send Now on a queued message but the session is still busy at that moment
- **THEN** CodeLab returns the message to its place in the queue without showing an error

#### Scenario: Clear All empties the queue
- **WHEN** user selects Clear All
- **THEN** CodeLab removes every queued message without sending any of them

### Requirement: Queue drains automatically when the session becomes free
CodeLab SHALL automatically send the oldest queued message once the active session returns to an idle/active state, without requiring user action.

#### Scenario: Oldest message sends automatically after the block clears
- **WHEN** the active session's turn completes or its pending approval is resolved, and the queue is non-empty
- **THEN** CodeLab automatically sends the oldest queued message
