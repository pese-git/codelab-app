## ADDED Requirements

### Requirement: Фикстуры встроенных команд агента
Корпус SHALL содержать фикстуры с ролью `agent` и ссылками `spec` на `14-Slash Commands.md`, `05-Prompt Turn.md` и, для режима, `13-Session Config Options.md` и `12-Session Model.md` (design.md change `add-agent-builtin-slash-commands`, D8; строки Must K-02, R-08):
- `acp/slash-compact` (K-02) — сессия с историей, достаточной для среза (`setup.config` с малым `compaction.keep_recent_tokens`), затем `session/prompt` с `/compact <указание>`: scripted-суммаризатор получает блок `<focus>` с указанием; ответ — один `agent_message_chunk` `Compacted: <X> → <Y> tokens.` и `stopReason: end_turn`; ни `tool_call`, ни `plan` в ходе нет;
- `acp/slash-help` (R-08) — `available_commands_update` после `session/new`, затем `/help`: один `agent_message_chunk` со списком команд в порядке объявления и `stopReason: end_turn`, запросов к scripted-модели нет;
- `acp/slash-mode-plan` (R-08, сценарий приёмки) — сессия в режиме `standard`: `/help`, затем `/mode plan` — `current_mode_update` с `plan`, `config_option_update` с полным снимком, `agent_message_chunk` `Mode: plan.`, `stopReason: end_turn`; затем `/nope` — `agent_message_chunk` `Unknown command: /nope. Run /help to list commands.` и `stopReason: end_turn`; запросов к scripted-модели нет.

Все уведомления хода SHALL идти до ответа на `session/prompt` (ACP-3).

#### Scenario: /mode plan в корпусе
- **WHEN** агентский драйвер проигрывает `acp/slash-mode-plan`
- **THEN** кадры совпадают с фикстурой, scripted-модель не получила ни одного запроса

#### Scenario: /compact в корпусе
- **WHEN** агентский драйвер проигрывает `acp/slash-compact`
- **THEN** кадры совпадают с фикстурой, суммаризатор получил указание, основная модель после `/compact` запросов не получила

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер получает одну из этих фикстур
- **THEN** он её пропускает с причиной «роль только agent»

## MODIFIED Requirements

### Requirement: Фикстуры файлов проекта этапа 8
Корпус SHALL содержать фикстуры с ролью `agent` и ссылками `spec` на `14-Slash Commands.md` и `13-Session Config Options.md` (design.md change `add-agent-project-files`, D15):
- `acp/prompt-template-command` (E-07) — шаблон `.codelab/prompts/review.md` доверенного проекта; `available_commands_update` после `session/new` содержит встроенные `compact`, `mode`, `model`, `status`, `mcp`, `help` (capability `compaction` и `mcp` агентского прогона включены; design.md change `add-config-writer-and-reload`, D12; design.md change `add-agent-builtin-slash-commands`, D2), затем `review` с `input.hint`; `session/prompt` с `/review lib/parser "error handling"` — scripted-модель получает развёрнутый текст; после `session/load` реплей содержит `user_message_chunk` с исходной командой;
- `acp/available-commands-no-tools` (R-07, часть шаблонов и встроенных команд) — встроенные инструменты, fake MCP-сервер с `echo` и один шаблон; список команд — встроенные `compact`, `mode`, `model`, `status`, `mcp`, `help` и шаблон, без инструментов (design.md change `add-config-writer-and-reload`, D12; design.md change `add-agent-builtin-slash-commands`, D2);
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
