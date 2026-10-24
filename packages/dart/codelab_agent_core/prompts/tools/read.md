---
id: tools.read
description: Rules for the read tool
vars: [maxLines, maxKb]
tools: [read]
---
# Reading files

- Read a file before you change it or make claims about it.
- read returns at most {{maxLines}} lines or {{maxKb}} KB. When the output says how to
  continue, call read again with that offset instead of guessing the rest.
- Line numbers in the output ("12| text") are not part of the file: do not copy them into
  edits.
