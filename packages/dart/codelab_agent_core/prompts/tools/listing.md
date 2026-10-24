---
id: tools.listing
description: Rules for the ls and search tools
vars: [limit]
tools: [ls, search]
---
# Finding files

- Use ls to see a directory and search to find text in files; do not run shell commands for
  this.
- ls shows at most {{limit}} entries; narrow the path when the list is cut.
- search skips version control, build and hidden directories. Narrow a broad search with the
  path or glob arguments instead of reading many files.
