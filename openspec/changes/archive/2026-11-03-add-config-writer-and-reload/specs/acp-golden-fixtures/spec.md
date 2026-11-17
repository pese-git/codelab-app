## MODIFIED Requirements

### Requirement: Фикстуры файлов проекта этапа 8
Корпус SHALL содержать фикстуры с ролью `agent` и ссылками `spec` на `14-Slash Commands.md` и `13-Session Config Options.md` (design.md change `add-agent-project-files`, D15):
- `acp/prompt-template-command` (E-07) — шаблон `.codelab/prompts/review.md` доверенного проекта; `available_commands_update` после `session/new` содержит встроенную `mcp` (capability `mcp` агентского прогона включена; design.md change `add-config-writer-and-reload`, D12), затем `review` с `input.hint`; `session/prompt` с `/review lib/parser "error handling"` — scripted-модель получает развёрнутый текст; после `session/load` реплей содержит `user_message_chunk` с исходной командой;
- `acp/available-commands-no-tools` (R-07, часть шаблонов и встроенных команд) — встроенные инструменты, fake MCP-сервер с `echo` и один шаблон; список команд — встроенная `mcp` и шаблон, без инструментов (design.md change `add-config-writer-and-reload`, D12);
- `acp/set-config-option-agent` (R-15) — `.codelab/agents/reviewer.md` с многострочным `tools`; `configOptions` содержит `agent`; `session/set_config_option` с `agent: reviewer` даёт `current_mode_update`, ответ с согласованными `agent`, `model`, `mode`; следующий запрос к модели содержит только схемы из списка;
- `acp/slash-mcp-list` (E-13, агентская часть; E-04) — `session/new` с одним сервером клиента и конфигом с двумя серверами, один из которых `enabled: false`:
  - `/mcp list` — один `agent_message_chunk` с таблицей `agent-core-architecture` §17.5.7 побайтово, `stopReason: end_turn`, запросов к scripted-модели нет;
  - `/mcp disable <id>` — строка сервера в состоянии `disabled`;
  - `/mcp frob` — текст `Usage: …`;
  - после `session/load` реплей не содержит ни одной из этих команд.

Файлы сценария SHALL задаваться `setup.files`; формат фикстур НЕ SHALL меняться. Фабрика агентского прогона `codelab_agent_acp` SHALL подключать `ProjectFilesLoader` с временным `CODELAB_HOME` и принимать в `setup.config` ключи `trusted_projects` (с подстановкой `${cwd}`) и `mcp.servers`. Сервер `mcp.servers` с `type: stdio` и `command`, равным имени fake-сервера фабрики, подключается к этому fake-серверу; любой другой `command` — громкий провал. Другой неизвестный ключ — по-прежнему громкий провал. Фабрика НЕ SHALL передавать ядру `ConfigSource`: перезагрузка проверяется тестами хоста.

#### Scenario: Команда шаблона
- **WHEN** агентский драйвер проигрывает `acp/prompt-template-command`
- **THEN** кадры совпадают с фикстурой, scripted-модель получила развёрнутый текст

#### Scenario: Таблица /mcp list
- **WHEN** агентский драйвер проигрывает `acp/slash-mcp-list`
- **THEN** кадры совпадают с фикстурой побайтово, scripted-модель не получила ни одного запроса, журнал сессии не содержит записей команд

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер получает одну из этих фикстур
- **THEN** он её пропускает с причиной «роль только agent»
