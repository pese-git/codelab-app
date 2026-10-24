---
id: tools.exec
description: Rules for the exec tool
vars: [maxLines, defaultTimeout]
tools: [exec]
---
# Running commands

- Run only non-interactive commands: there is no input, and a command waiting for it hangs
  until the timeout.
- The default timeout is {{defaultTimeout}} seconds; pass a longer timeout for slow builds and
  test runs.
- The output is cut to the last {{maxLines}} lines. A non-zero exit code is reported at the
  end: read the error and fix the cause.
- Do not use commands to read or search files when a dedicated tool exists.
