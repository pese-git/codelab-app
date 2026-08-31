## ADDED Requirements

### Requirement: Panel borders are resizable by dragging
CodeLab SHALL let the user resize the sessions pane and the inspector pane by dragging their shared border with the main pane, in the desktop layout mode, within fixed minimum and maximum bounds.

#### Scenario: Dragging the sessions/main divider resizes the sessions pane
- **WHEN** user drags the divider between the sessions pane and the main pane in desktop layout
- **THEN** CodeLab resizes the sessions pane width live, following the pointer, and the main pane fills the remaining space

#### Scenario: Dragging the main/inspector divider resizes the inspector pane
- **WHEN** user drags the divider between the main pane and the inspector pane in desktop layout
- **THEN** CodeLab resizes the inspector pane width live, following the pointer

#### Scenario: Resize is clamped to a minimum width
- **WHEN** user drags a divider toward a width below its configured minimum
- **THEN** CodeLab stops shrinking the pane at the minimum width, never collapsing it to zero

#### Scenario: Resize is clamped to a maximum width
- **WHEN** user drags a divider toward a width above its configured maximum
- **THEN** CodeLab stops growing the pane at the maximum width, never letting it consume the entire main pane

#### Scenario: Cursor indicates a draggable border
- **WHEN** the pointer hovers over a resizable divider, before any drag starts
- **THEN** CodeLab shows a horizontal-resize cursor

#### Scenario: Resized widths persist across widget rebuilds within a run
- **WHEN** a panel has been resized and the workbench widget tree rebuilds (e.g. due to an unrelated state change)
- **THEN** the panel keeps the resized width, not the original default
