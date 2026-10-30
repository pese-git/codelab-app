## ADDED Requirements

### Requirement: Файлы проекта в бинаре
`codelab-agent serve --stdio` SHALL передавать ядру `ProjectFilesLoader` из `codelab_agent_io` в `AgentCoreServices.projectFiles` (design.md change `add-agent-project-files`, D16). Пользовательская область — `$CODELAB_HOME` процесса. С `--llm-script` пользовательская область НЕ SHALL читаться, а проект SHALL считаться недоверенным (глобальный слой не читается); контекст проекта (`AGENTS.md` дерева `cwd`) SHALL читаться.

`codelab-agent serve --ws` НЕ SHALL передавать загрузчик (решение пользователя 2026-10-30; D2, D16): клиент WebSocket выбирает `cwd` и может быть на другой машине, а чтение шло бы с файловой системы машины агента и отдавало бы удалённому клиенту инструкции любого каталога этой машины. Поэтому по WebSocket не читаются ни файлы проекта (`AGENTS.md`/`CLAUDE.md`, `.codelab/prompts`, `.codelab/agents`), ни файлы `$CODELAB_HOME` (`AGENTS.md`, `prompts/`, `agents/`). Это сужение по транспорту, как у MCP (`mcp.server.skipped`, design.md change `add-agent-mcp-client`, D3): хост SHALL один раз при запуске писать событие `project_files.skipped` (info) с полями `transport: ws` и `reason: "project files are not read over WebSocket"`.

#### Scenario: Шаблон пользователя
- **WHEN** `AgentHost.build` для `--stdio` получает временный `CODELAB_HOME` с `prompts/review.md` и создаёт сессию
- **THEN** `session.commands` содержит `review`

#### Scenario: Сценарий не читает CODELAB_HOME
- **WHEN** `serve --stdio --llm-script` запускается во временном `cwd` с `AGENTS.md`, а `CODELAB_HOME` содержит `prompts/review.md` и `AGENTS.md`
- **THEN** лог `project_context.loaded` называет только `AGENTS.md` из `cwd`, а `available_commands_update` после `session/new` пуст

#### Scenario: WebSocket не читает файлы проекта
- **WHEN** `AgentHost.build` для `--ws` получает временный `CODELAB_HOME` с `AGENTS.md`, а сессия создаётся в `cwd` с `AGENTS.md`
- **THEN** `AgentCoreServices.projectFiles` равен `null`, системный промпт не содержит секции `project_context`, лог содержит одно событие `project_files.skipped` с `transport: ws` и не содержит `project_context.loaded`
