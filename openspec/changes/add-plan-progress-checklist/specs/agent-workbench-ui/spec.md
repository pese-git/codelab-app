## ADDED Requirements

### Requirement: Progress checklist reflects the agent's plan
CodeLab SHALL render the agent's plan as a progress checklist, sourced from `SessionUpdate.plan` entries, showing each entry's priority and status without inventing statuses the protocol does not define.

#### Scenario: Plan update renders a checklist
- **WHEN** the active session receives a `SessionUpdate.plan` with one or more entries
- **THEN** CodeLab shows a checklist with one row per entry, each showing its status (pending/in_progress/completed) and priority (high/medium/low)

#### Scenario: No plan yet — no checklist shown
- **WHEN** the active session has not received any `plan` update
- **THEN** CodeLab does not show a checklist or an empty-state placeholder for it

#### Scenario: A later plan update replaces the checklist
- **WHEN** a new `SessionUpdate.plan` arrives for the active session
- **THEN** CodeLab replaces the displayed checklist with the entries from the new update

### Requirement: Docked plan summary below the transcript
CodeLab SHALL show a compact summary of the current plan docked below the transcript, directly above the composer, expandable into the full checklist by clicking anywhere on the summary row.

#### Scenario: Summary names the active step
- **WHEN** a plan has an entry with status in_progress and the summary is collapsed
- **THEN** the compact summary shows that entry's description, and a count of remaining pending entries if any remain

#### Scenario: Summary shows an aggregate count when nothing is in progress
- **WHEN** a plan has no entry with status in_progress, or the summary is expanded
- **THEN** the compact summary shows an aggregate count (total entries if none are completed yet, or completed-out-of-total otherwise) instead of naming a specific entry

#### Scenario: Summary is omitted when the plan is fully completed
- **WHEN** every entry in the current plan has status completed
- **THEN** CodeLab does not show the compact summary row, though the full checklist remains reachable until every entry is completed

#### Scenario: Dismissing the plan clears the summary until the next update
- **WHEN** the user dismisses the plan summary
- **THEN** CodeLab stops showing the plan summary and checklist for that session until a new plan update arrives

### Requirement: Full checklist has a bounded, independently scrollable height
CodeLab SHALL cap the expanded checklist's height and scroll its entries independently, so a long plan does not push the transcript or composer out of view.

#### Scenario: Plan with many entries stays within a bounded height
- **WHEN** the expanded checklist has more entries than fit in its maximum height
- **THEN** the entries scroll within the checklist without resizing the surrounding layout
