## ADDED Requirements

### Requirement: Read-only file preview from a tool call
CodeLab SHALL let the user open a read-only preview of a file referenced by a tool call, showing line numbers and highlighting the range from `ToolCallLocation` when available, and SHALL label the content as sourced from the agent's tool call.

#### Scenario: Opening preview from a tool call card
- **WHEN** user selects the preview action on a tool call entry (transcript or inspector) that references a file
- **THEN** CodeLab opens the file preview panel showing the content already returned by the agent, with the relevant line range highlighted if a `ToolCallLocation` is present

#### Scenario: Preview panel does not allow editing
- **WHEN** the file preview panel is open
- **THEN** the content is not editable and no write action is offered

### Requirement: Read-only file preview from the directory tree
CodeLab SHALL let the user browse the working directory as a lazily-expanded tree and open a read-only preview of any file in it, reading the file directly from disk, and SHALL label that content as read directly from disk (not from the agent).

#### Scenario: Browsing the directory tree
- **WHEN** user switches the sidebar to the "Files" tab
- **THEN** CodeLab shows a lazily-expandable tree rooted at the current working directory, excluding common noise directories (`.git`, `.dart_tool`, `build`, `node_modules`, and similar)

#### Scenario: Opening a file from the tree
- **WHEN** user selects a file node in the tree
- **THEN** CodeLab reads the file from disk and opens the same read-only preview panel used for tool-call previews, labeled as read directly from disk

#### Scenario: File too large to preview
- **WHEN** the selected file exceeds the preview size limit
- **THEN** CodeLab shows a message that the file is too large to preview instead of its content

### Requirement: Following keeps the preview panel in sync with the active tool call
CodeLab SHALL offer a "Following" toggle on a tool-call-sourced preview panel that, when enabled, updates the panel to the most recent `ToolCallLocation` reported for the active session.

#### Scenario: Following updates on new tool call activity
- **WHEN** Following is enabled and a new `ToolCallLocation` arrives for the active session
- **THEN** CodeLab updates the preview panel to the new location without requiring the user to reopen it

#### Scenario: Following does not apply to disk-sourced previews
- **WHEN** a preview panel is showing content read directly from disk
- **THEN** CodeLab does not offer the Following toggle for it
