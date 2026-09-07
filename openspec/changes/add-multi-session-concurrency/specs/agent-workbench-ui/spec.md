## ADDED Requirements

### Requirement: Sessions run prompt turns independently of the active session
CodeLab SHALL allow a session's prompt turn to continue running while a different session is active, and SHALL allow the active session to start its own prompt turn even while another session's turn is still running, as long as the active session itself is not busy.

#### Scenario: Starting a second session while the first is still running
- **WHEN** a session has a prompt turn running or an approval pending, and the user creates or switches to a different, idle session
- **THEN** CodeLab lets the user submit a prompt in the newly active session immediately, without queuing it, regardless of the other session's state

#### Scenario: A background session's turn keeps running while another session is active
- **WHEN** a session's prompt turn is running while a different session is active
- **THEN** CodeLab does not cancel, pause, or otherwise interrupt the background session's turn — it continues until it completes, fails, or is explicitly cancelled

#### Scenario: A background session's turn completes while another session is active
- **WHEN** a non-active session's prompt turn completes, fails, or its approval is resolved while a different session is active
- **THEN** CodeLab updates that session's own transcript and status without altering the transcript, composer, or submitting state currently shown for the active session

### Requirement: Sessions sidebar shows live status for background sessions
CodeLab SHALL keep each session's status indicator in the sessions sidebar current — including idle, running, and awaiting-approval — regardless of whether that session is the currently active one.

#### Scenario: A background session's status updates as its turn progresses
- **WHEN** a non-active session's prompt turn starts running, requests an approval, or completes
- **THEN** the sessions sidebar reflects that session's current status without requiring the user to switch to it first

## MODIFIED Requirements

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

#### Scenario: Another session being busy does not queue a message for the active session
- **WHEN** user submits a prompt in the active session while a *different* session has a turn running or an approval pending
- **THEN** CodeLab sends the message immediately, exactly as it would if no other session existed — only the active session's own busy state can cause queuing

### Requirement: Queue drains automatically when the session becomes free
CodeLab SHALL automatically send the oldest queued message once the active session returns to an idle/active state, without requiring user action.

#### Scenario: Oldest message sends automatically after the block clears
- **WHEN** the active session's turn completes or its pending approval is resolved, and the queue is non-empty
- **THEN** CodeLab automatically sends the oldest queued message

#### Scenario: A background session's own queue drains when its own turn completes
- **WHEN** a non-active session's turn completes or its pending approval is resolved while a different session is active, and that non-active session's own queue is non-empty
- **THEN** CodeLab automatically sends that session's oldest queued message, without requiring the user to switch to it first
