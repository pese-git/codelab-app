## MODIFIED Requirements

### Requirement: Slash-меню и клиентские команды
Строка, начинающаяся с `/`, SHALL разбираться как команда. Каталог SHALL строиться `CommandCatalog` из команд клиента и `SessionView.agentCommands`; клиентская команда SHALL иметь приоритет, а одноимённая команда агента SHALL быть доступна как `/agent:<имя>`; команда агента SHALL отправляться промптом `/<имя> [аргументы]`. Новое `available_commands_update` SHALL сразу менять каталог. Tab SHALL дополнять имя по `CommandCatalog.search`: один кандидат — подставить, несколько — показать список с пометкой команд агента (U-03). Клиентские команды MVP: `/help`, `/help keys`, `/exit`, `/quit`, `/new`, `/sessions`, `/resume <n или id>`, `/mode [id]`, `/model [id]`, `/config [id] [значение]`, `/cancel`, `/queue`, `/queue drop <n>`, `/queue clear`, `/profile [id]`, `/reconnect`, `/plan`, `/clear`, `/thoughts dim|collapsed|hidden` (U-04). `/mode` и `/model` без аргумента SHALL показывать значения опции конфигурации с отметкой текущего; с аргументом — отправлять `session/set_config_option`; неизвестное значение SHALL давать сообщение без запроса (U-05). Неизвестная команда SHALL давать сообщение `Unknown command /<имя>` без запроса к агенту.

#### Scenario: Меню объединяет команды агента
- **WHEN** агент объявил команды `compact` и `plan`, и пользователь вводит `/` и Tab
- **THEN** список содержит команды клиента и `compact`, `plan` с пометкой агента; `/plan` выполняет клиентскую команду, `/agent:plan` отправляет промпт `/plan`

#### Scenario: Одноимённые команды клиента и Dart-агента
- **WHEN** CLI подключён к Dart-агенту или встроенному агенту, агент объявил встроенные `compact`, `mode`, `model`, `status`, `mcp`, `help`, и пользователь вводит `/` и Tab
- **THEN** список содержит клиентские `/help`, `/mode`, `/model` и `/config`, команды агента `/compact`, `/status`, `/mcp` с пометкой агента и одноимённые команды агента как `/agent:help`, `/agent:mode`, `/agent:model`; `/help` печатает справку клиента без `session/prompt`, `/agent:help` отправляет промпт `/help` и печатает ответ агента (`cli/slash-menu-merges-agent-commands`, U-03; design.md change `add-agent-builtin-slash-commands`, D10)

#### Scenario: Выбор модели
- **WHEN** агент предлагает опцию `model` со значениями `a` и `b`, и пользователь вводит `/model b`
- **THEN** агент получает `session/set_config_option` с `configId: model` и `value: b`

#### Scenario: Неизвестная модель
- **WHEN** пользователь вводит `/model zzz`
- **THEN** печатается сообщение о неизвестном значении, `session/set_config_option` не отправляется
