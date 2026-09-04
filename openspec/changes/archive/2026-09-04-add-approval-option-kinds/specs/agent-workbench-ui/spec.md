## ADDED Requirements

### Requirement: Approval options are rendered and bound to shortcuts by kind
CodeLab SHALL carry each approval option's `PermissionOptionKind` (`allow_once`, `allow_always`, `reject_once`, `reject_always`) through to the presentation layer and SHALL bind each kind to a fixed keyboard shortcut, without relying on matching substrings in the option's agent-provided label text.

#### Scenario: Four kinds shown distinctly
- **WHEN** a permission request offers all four standard option kinds
- **THEN** CodeLab shows four distinct options, each bound to its own shortcut, regardless of the exact wording of each option's label

#### Scenario: Non-English or unusual option labels still get shortcuts
- **WHEN** an agent provides an option label that does not contain the words "allow"/"approve"/"reject"/"deny" (e.g. a non-English label)
- **THEN** CodeLab still binds the correct shortcut to that option, based on its `kind`, not its label text

### Requirement: Approval panel offers a collapsed raw input view
CodeLab SHALL show the tool call's raw input in the approval panel behind a collapsed, expand-on-demand disclosure, not always visible by default.

#### Scenario: Raw input is collapsed by default
- **WHEN** an approval panel is shown for a tool call with input data
- **THEN** the raw input is hidden behind a "View raw input" control until the user expands it
