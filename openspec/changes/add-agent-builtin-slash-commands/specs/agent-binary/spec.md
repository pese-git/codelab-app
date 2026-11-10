## MODIFIED Requirements

### Requirement: Файлы проекта в бинаре
`codelab-agent serve --stdio` SHALL передавать ядру `ProjectFilesLoader` из `codelab_agent_io` в `AgentCoreServices.projectFiles` (design.md change `add-agent-project-files`, D16). Пользовательская область — `$CODELAB_HOME` процесса. С `--llm-script` пользовательская область НЕ SHALL читаться, а проект SHALL считаться недоверенным (глобальный слой не читается); контекст проекта (`AGENTS.md` дерева `cwd`) SHALL читаться.

`codelab-agent serve --ws` НЕ SHALL передавать загрузчик (решение пользователя 2026-10-30; D2, D16): клиент WebSocket выбирает `cwd` и может быть на другой машине, а чтение шло бы с файловой системы машины агента и отдавало бы удалённому клиенту инструкции любого каталога этой машины. Поэтому по WebSocket не читаются ни файлы проекта (`AGENTS.md`/`CLAUDE.md`, `.codelab/prompts`, `.codelab/agents`), ни файлы `$CODELAB_HOME` (`AGENTS.md`, `prompts/`, `agents/`). Это сужение по транспорту, как у MCP (`mcp.server.skipped`, design.md change `add-agent-mcp-client`, D3): хост SHALL один раз при запуске писать событие `project_files.skipped` (info) с полями `transport: ws` и `reason: "project files are not read over WebSocket"`.

#### Scenario: Шаблон пользователя
- **WHEN** `AgentHost.build` для `--stdio` получает временный `CODELAB_HOME` с `prompts/review.md` и создаёт сессию
- **THEN** `session.commands` содержит `review`

#### Scenario: Сценарий не читает CODELAB_HOME
- **WHEN** `serve --stdio --llm-script` запускается во временном `cwd` с `AGENTS.md`, а `CODELAB_HOME` содержит `prompts/review.md` и `AGENTS.md`
- **THEN** лог `project_context.loaded` называет только `AGENTS.md` из `cwd`, а `available_commands_update` после `session/new` содержит только встроенные команды сессии, без шаблона `review`

#### Scenario: WebSocket не читает файлы проекта
- **WHEN** `AgentHost.build` для `--ws` получает временный `CODELAB_HOME` с `AGENTS.md`, а сессия создаётся в `cwd` с `AGENTS.md`
- **THEN** `AgentCoreServices.projectFiles` равен `null`, системный промпт не содержит секции `project_context`, лог содержит одно событие `project_files.skipped` с `transport: ws` и не содержит `project_context.loaded`

### Requirement: Перезагрузка конфига в serve
`codelab-agent serve --stdio` и `serve --ws` SHALL передавать ядру `FileConfigSource` корня запуска с окружением и флагами процесса и `modelsFor` над той же функцией модели и каталогом, что при старте (design.md change `add-config-writer-and-reload`, D13). Начальные `streamFunction` и `services.models` SHALL браться из одного вызова `modelsFor`. Оба хоста SHALL передавать `AgentCoreServices.agentConfigPaths` (PERM-11, D8). `serve --ws` SHALL собирать ядро с `configCommand: false`: команда `/config` по WebSocket не объявляется и не исполняется (R0-3), а перезагрузка по наблюдателю работает. При `config.watch: false` источник SHALL создаваться без наблюдателя. Со сценарием `--llm-script` источник НЕ SHALL передаваться. Источник SHALL закрываться после `runtime.dispose()` при остановке процесса.

#### Scenario: Правка конфига работающего агента
- **WHEN** `serve --stdio` работает с открытой сессией, и в `$CODELAB_HOME/config.yaml` добавляется модель провайдера
- **THEN** клиент получает `config_option_update` с новой моделью не позже 5 с, процесс не перезапускался (`config_reload_process_test.dart`)

#### Scenario: Битая правка
- **WHEN** в работающий `serve --stdio` приходит ручная правка с `budget.max_steps: 0`
- **THEN** клиент не получает кадров, лог содержит `config.reload.failed` с файлом, строкой и ключом, следующий ход работает по прежнему конфигу

#### Scenario: WebSocket без /config
- **WHEN** клиент подключается к `serve --ws` и создаёт сессию
- **THEN** `available_commands_update` не содержит `config` и `mcp`; промпт `/config check` получает ответ `Unknown command: /config. Run /help to list commands.` без запроса к модели (`agent_host_ws_commands_test.dart`; capability `agent-slash-commands`, «Неизвестная команда»)

#### Scenario: Сценарий без перезагрузки
- **WHEN** `serve --stdio --llm-script s.yaml` работает, и меняется `--config` файл
- **THEN** перезагрузки нет, команды `config` в `available_commands_update` нет
