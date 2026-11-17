## ADDED Requirements

### Requirement: Фикстуры файлов проекта этапа 8
Корпус SHALL содержать фикстуры с ролью `agent` и ссылками `spec` на `14-Slash Commands.md` и `13-Session Config Options.md` (design.md change `add-agent-project-files`, D15):
- `acp/prompt-template-command` (E-07) — шаблон `.codelab/prompts/review.md` доверенного проекта; `available_commands_update` после `session/new` содержит `review` с `input.hint`; `session/prompt` с `/review lib/parser "error handling"` — scripted-модель получает развёрнутый текст; после `session/load` реплей содержит `user_message_chunk` с исходной командой;
- `acp/available-commands-no-tools` (R-07, часть шаблонов) — встроенные инструменты, fake MCP-сервер с `echo` и один шаблон; список команд — только шаблон;
- `acp/set-config-option-agent` (R-15) — `.codelab/agents/reviewer.md` с многострочным `tools`; `configOptions` содержит `agent`; `session/set_config_option` с `agent: reviewer` даёт `current_mode_update`, ответ с согласованными `agent`, `model`, `mode`; следующий запрос к модели содержит только схемы из списка.

Файлы сценария SHALL задаваться `setup.files`; формат фикстур НЕ SHALL меняться. Фабрика агентского прогона `codelab_agent_acp` SHALL подключать `ProjectFilesLoader` с временным `CODELAB_HOME` и принимать в `setup.config` ключ `trusted_projects` с подстановкой `${cwd}`; другой неизвестный ключ — по-прежнему громкий провал.

#### Scenario: Команда шаблона
- **WHEN** агентский драйвер проигрывает `acp/prompt-template-command`
- **THEN** кадры совпадают с фикстурой, scripted-модель получила развёрнутый текст

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер получает одну из этих фикстур
- **THEN** он её пропускает с причиной «роль только agent»
