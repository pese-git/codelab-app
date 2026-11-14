---
id: tool_descriptions.agent
description: Description of the agent tool schema
vars: [maxConcurrent, nesting, background, agentList]
---
Launch a subagent: a separate agent with its own context that does one self-contained assignment and returns a single final report.
Use it to explore a large codebase, review changes or draft a plan without filling your own context.
The subagent does not see this conversation: put everything it needs into `prompt`.
Several agent calls in one response run in parallel, at most {{maxConcurrent}} at a time.
You receive only the final report, not the subagent's intermediate steps.{{background}}
Subagents cannot ask the user questions. {{nesting}}

Agent types:
{{agentList}}
