## MODIFIED Requirements

### Requirement: Подкоманда config бинаря
`codelab-agent config path|get|set|unset|check`, `codelab-agent provider add|list|remove` и `codelab-agent mcp add|list|remove` SHALL работать без запуска сервера, без открытия транспорта и без чтения stdin. Исключение — `provider add --api-key-stdin`: он читает ключ из stdin. Тексты, правила и коды выхода — общая реализация `ConfigCommands`, `ProviderCommands` и `McpServerCommands` (capability `agent-configuration`, требования «Подкоманда config check» и «Подкоманды записи и чтения конфига»). Флагов `serve` у этих команд нет; окружение, включая `CODELAB_CONFIG` и `CODELAB_PROVIDER_*`, учитывается.

Ошибкой использования с кодом `64` и справкой команды в stderr SHALL завершаться:
- `codelab-agent config`, `provider` или `mcp` без подкоманды;
- неизвестная подкоманда (в том числе `config migrate`);
- лишние или недостающие аргументы;
- ошибка разбора аргументов: неизвестный флаг, флаг без значения.

Присланные слова argv НЕ SHALL цитироваться в stderr у `config set`, `config unset`, `provider` и `mcp` (design.md change `add-config-writer-and-reload`, D6): ошибка разбора печатает фиксированную фразу `invalid arguments for config set` (`… config unset`, `… provider`, `… mcp`), неизвестная подкоманда и лишние аргументы — `unknown <cmd> arguments (<n>)`, где `<n>` — число лишних слов. У `config check|path|get` ошибка разбора МОЖЕТ печатать причину `package:args`.

Общая справка бинаря (`serveUsage`, печатается при ошибке использования `serve`) SHALL упоминать `config`, `provider` и `mcp`.

#### Scenario: Проверка без сервера
- **WHEN** запускается `codelab-agent config check` в каталоге с валидным `config.yaml`
- **THEN** stdout заканчивается `Config: valid`, код `0`, процесс не открывает транспорт ACP

#### Scenario: Запись без сервера
- **WHEN** запускается `codelab-agent config set budget.max_steps 10`
- **THEN** код `0`, `$CODELAB_HOME/config.yaml` содержит `max_steps: 10`, комментарии файла сохранены, транспорт ACP не открыт

#### Scenario: Неизвестная подкоманда
- **WHEN** запускается `codelab-agent config migrate` или `codelab-agent mcp frob`
- **THEN** код `64`, в stderr — справка соответствующей команды; файлы конфига не изменены

#### Scenario: Ошибка разбора аргументов config
- **WHEN** запускается `codelab-agent config check --bogus` или `codelab-agent config check --cwd` без значения
- **THEN** код `64`, stderr содержит причину и справку команды `config`, stdout пуст

#### Scenario: Ошибка разбора аргументов записи не цитирует argv
- **WHEN** запускается `codelab-agent config set budget.max_steps --sk-1`, `codelab-agent provider add gw --api-key sk-1` или `codelab-agent mcp frob`
- **THEN** код `64`, stdout пуст, stderr содержит соответственно `invalid arguments for config set`, `invalid arguments for provider`, `unknown mcp arguments (1)` и справку команды; ни `sk-1`, ни `frob` в stderr нет

#### Scenario: Общая справка называет подкоманды
- **WHEN** бинарь запущен с неизвестным флагом `serve`, например `codelab-agent serve --stdio --bogus`
- **THEN** код `64`, справка в stderr содержит `config`, `provider` и `mcp`

## ADDED Requirements

### Requirement: Флаги предконфигурации провайдера
`codelab-agent serve` SHALL принимать `--provider-type <kind>` и `--provider-config <json | @путь>` (путь — относительно текущего каталога процесса). Они задают предконфигурацию провайдера слоем флагов по правилам capability `agent-configuration`, «Предконфигурация провайдера из окружения», и затеняют переменные `CODELAB_PROVIDER_*` (design.md change `add-config-writer-and-reload`, D3; CFG-12).

Ошибка использования, код `64`, до старта транспорта:
- задан только один из двух флагов;
- флаги сочетаются с `--provider` или `--base-url` (текст `--provider-type cannot be combined with --provider`);
- файл `@путь` не читается.

Значение `--provider-config` НЕ SHALL попадать в лог, stderr и строковое представление опций. Справка `serve` SHALL рекомендовать форму `@путь`: JSON в argv виден другим пользователям через `ps`. Литеральный секретный заголовок в JSON флага — проблема `inlineSecret` (capability `agent-configuration`, «Предконфигурация провайдера из окружения»).

Внутри слоя флагов предконфигурация SHALL применяться первой, `--model` — после неё.

#### Scenario: Флаги затеняют переменные
- **WHEN** окружение задаёт `CODELAB_PROVIDER_TYPE` и `CODELAB_PROVIDER_CONFIG` провайдера `env`, а запуск — `--provider-type anthropic --provider-config @p.json` с провайдером `a`
- **THEN** каталог содержит модели `a`, но не `env`; лог содержит `config.preconfig.shadowed {by: "flags"}`

#### Scenario: Сочетание с --provider
- **WHEN** запуск — `serve --stdio --provider openai-compatible --base-url http://x --model m --provider-type anthropic --provider-config '{…}'`
- **THEN** код `64` до чтения stdin, stderr содержит `--provider-type cannot be combined with --provider`

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
- **THEN** `available_commands_update` не содержит `config` и `mcp`; промпт `/config check` уходит модели как текст (`agent_host_ws_commands_test.dart`)

#### Scenario: Сценарий без перезагрузки
- **WHEN** `serve --stdio --llm-script s.yaml` работает, и меняется `--config` файл
- **THEN** перезагрузки нет, команды `config` в `available_commands_update` нет
