## MODIFIED Requirements

### Requirement: Tool dock with closable pane tabs
CodeLab SHALL host tool panes in a dock on the right, with one closable tab per open pane. Each available pane SHALL have a toggle in the app bar that opens it, makes it active, or closes it when it is already active. With no open panes the dock SHALL NOT be shown. The open panes, the active pane and the dock width SHALL persist across restarts. Whether a pane is available SHALL be decided by that pane's own predicate (its data source exists in this window and for the current connection); a pane without data SHALL NOT be offered. An unavailable pane SHALL have no toggle and no tab, but SHALL stay in the saved layout and SHALL reappear when its predicate becomes true again. The Plan and Protocol panes are always available; the Files pane follows `workspace-file-browser` (design.md change `add-file-preview-and-tree`, D7).

#### Scenario: Opening and closing a pane
- **WHEN** the user clicks the Plan toggle, then closes the Plan tab
- **THEN** the dock appears with the Plan tab active, and after closing it the dock disappears and the transcript takes the width

#### Scenario: Two panes as tabs
- **WHEN** Plan and Protocol are both open
- **THEN** the dock shows two tabs, and clicking a tab makes that pane active

#### Scenario: Open panes survive a restart
- **WHEN** Plan and Protocol are open with Protocol active, and CodeLab is restarted
- **THEN** the dock opens with both tabs and Protocol active

#### Scenario: Unavailable pane is hidden but kept in the layout
- **WHEN** Files and Plan are open with an embedded-agent connection, and the window switches to a WebSocket profile, then back to the embedded agent
- **THEN** while on the WebSocket profile the dock shows only Plan and there is no Files toggle, and after switching back the Files tab is shown again
