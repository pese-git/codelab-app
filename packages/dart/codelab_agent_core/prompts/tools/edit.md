---
id: tools.edit
description: Rules for the write and edit tools
vars: []
tools: [write, edit]
---
# Changing files

- Prefer edit for changes to an existing file; use write for a new file or when the whole
  content changes.
- oldText of edit must match the file byte for byte, including indentation, and occur exactly
  once. Include enough surrounding lines to make it unique.
- If edit reports no match, read the file again: it may have changed since you read it.
- Keep the style of the file: indentation, line endings and naming.
