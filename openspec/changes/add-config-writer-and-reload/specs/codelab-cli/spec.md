## MODIFIED Requirements

### Requirement: Подкоманда codelab config
`codelab config path|get|set|unset|check` SHALL работать без запуска агента и без подключения по ACP. Подкоманды вызывают общую реализацию `ConfigCommands` через `package:codelab_setup/io.dart` (design.md change `add-agent-configuration`, D13, D14; design.md change `add-config-writer-and-reload`, D6), поэтому их вывод и коды выхода совпадают с `codelab-agent config` (capability `agent-configuration`).

**Корень и `cwd`.** Корень состояния — `CODELAB_HOME` (по умолчанию `~/.codelab`). `config check`, `config path` и `config get` его не изменяют; `config set` и `config unset` меняют только файл выбранного слоя. `cwd` берётся по порядку: `--cwd` подкоманды, общий `-C`/`--cwd`, текущий каталог. Значение передаётся загрузчику как есть, без лексической нормализации, — канонизирует путь загрузчик, как у `codelab-agent`. Проверяется окружение процесса `codelab`; профиль подключения не учитывается.

**Ошибки использования** — код `64`:
- флаги подключения и запроса (`-a`/`--agent`, `-m`/`--model`, `--mode`, `-r`/`--resume`, `-c`/`--continue`, `-p`/`--print`, `-f`/`--prompt-file`, `--approve`, `--timeout`, `--ui`) вместе с `config`;
- `codelab config` без подкоманды — текст `config needs a subcommand: codelab config path|get|set|unset|check` в stderr;
- неизвестная подкоманда (в том числе `migrate`) — `Unknown command config <sub>` в stderr.

Клиент НЕ SHALL импортировать `package:codelab_agent_*` напрямую.

#### Scenario: Проверка конфига из CLI
- **WHEN** `codelab config check --cwd <dir>` запускается для каталога, где глобальный `config.yaml` задаёт провайдера и `agent.default_model`, а `<dir>/.codelab/config.yaml` содержит `budget.max_steps: 0`
- **THEN** stdout содержит проблему `budget.max_steps` с файлом и строкой, последняя строка `Config: invalid (issues: 1)`, код `1`, ни один процесс агента не запущен (`cli/config-check-reports-issues`)

#### Scenario: Запись совпадает с бинарём агента
- **WHEN** `codelab config set budget.max_steps 10` и `codelab-agent config set budget.max_steps 10` запускаются с одинаковыми копиями `CODELAB_HOME` и окружением
- **THEN** stdout, stderr, код выхода и итоговые байты `config.yaml` у двух бинарей совпадают (`apps/codelab_cli/test/e2e/config_write_command_test.dart`)

#### Scenario: Запись в локальный слой проекта
- **WHEN** запускается `codelab -C <dir> config set permissions.mode plan --local`
- **THEN** создан `<dir>/.codelab/config.local.yaml` с `permissions.mode: plan`, глобальный конфиг не изменён

#### Scenario: Неизвестная подкоманда config
- **WHEN** запускается `codelab config migrate` или `codelab config frobnicate`
- **THEN** код `64`, stdout пуст, stderr содержит `Unknown command config migrate` (соответственно `frobnicate`), процесс агента не запущен, файлы конфига не изменены

#### Scenario: config без подкоманды
- **WHEN** запускается `codelab config`
- **THEN** код `64`, stdout пуст, stderr содержит `config needs a subcommand: codelab config path|get|set|unset|check`

#### Scenario: --cwd подкоманды сильнее общего
- **WHEN** запускается `codelab -C <a> config check --cwd <b>`, где проектный конфиг `<b>` содержит проблему, а `<a>` — валидный
- **THEN** проверяется `<b>`: stdout содержит проблему из `<b>/.codelab/config.yaml`, код `1`

#### Scenario: Без --cwd подкоманды берётся общий
- **WHEN** запускается `codelab -C <b> config check` из другого каталога
- **THEN** проверяется `<b>`, вывод и код те же, что у `codelab config check --cwd <b>`

#### Scenario: Относительный путь и `..` канонизирует загрузчик
- **WHEN** `codelab config check --cwd <rel>` и `codelab-agent config check --cwd <rel>` запускаются из одного каталога с одинаковыми `CODELAB_HOME` и окружением, где `<rel>` — относительный путь, содержащий `..`
- **THEN** stdout, stderr и код выхода двух бинарей совпадают; CLI не нормализует путь сам до передачи загрузчику

#### Scenario: Флаги подключения с config — ошибка использования
- **WHEN** запускается `codelab --agent <cmd> config check`, `codelab -p hi config set budget.max_steps 1` или `codelab --prompt-file <f> config check`
- **THEN** код `64`, stdout пуст, в stderr — ошибка использования; процесс агента не запущен, конфиг не проверяется и не меняется

#### Scenario: config check не меняет CODELAB_HOME
- **WHEN** `codelab config check` запускается с пустым временным `CODELAB_HOME`
- **THEN** после выхода в `CODELAB_HOME` нет `sessions/`, `profiles.json` и `cli_history`

## ADDED Requirements

### Requirement: Подкоманды codelab provider и codelab mcp
`codelab provider add|list|remove` и `codelab mcp add|list|remove` SHALL вызывать общие `ProviderCommands` и `McpServerCommands` через `package:codelab_setup/io.dart` (только из `lib/src/run.dart`). Вывод, коды выхода и записанные байты SHALL совпадать с `codelab-agent provider|mcp` (design.md change `add-config-writer-and-reload`, D6). Правила флагов подключения, `cwd` и неизвестной подкоманды — как у `codelab config`.

`codelab provider add` без обязательных флагов (`--kind`, `--model`, `--context-window`) в этой сборке SHALL быть ошибкой использования `64`: мастер на TTY — change `add-provider-setup-ui`. Ключ `--api-key-stdin` SHALL читаться скрытым вводом `StdinSecretInput`, как у `codelab secret set`. Значение ключа НЕ SHALL попадать в stdout, `profiles.json`, `cli_history` и лог CLI.

Справка `codelab --help` SHALL содержать строки `codelab provider add|list|remove` и `codelab mcp add|list|remove`. Агентская команда `/mcp` в REPL доступна по своему имени, а агентская `/config` — как `/agent:config`, потому что клиентская `/config` имеет приоритет (требование «Slash-меню и клиентские команды»).

#### Scenario: provider list
- **WHEN** `secrets.backend: file`, конфиг задаёт провайдера `gw` с `api_key_secret: codelab/gw`, секрет сохранён, и запускается `codelab provider list`
- **THEN** первая строка — `Secrets: file`, строка `gw` содержит `secret codelab/gw: found` и не содержит значения; вывод совпадает с `codelab-agent provider list`

#### Scenario: mcp add и remove
- **WHEN** запускается `codelab mcp add docs --type stdio --command docs-mcp --arg --stdio`, затем `codelab mcp list`, затем `codelab mcp remove docs`
- **THEN** первый — код `0` и элемент `docs` в конце `mcp.servers`, второй печатает `docs`, `stdio`, `user`, `enabled`, третий удаляет элемент; комментарии файла сохранены

#### Scenario: provider add без флагов
- **WHEN** запускается `codelab provider add gw` на TTY
- **THEN** код `64`, stderr называет недостающие флаги, файлы не изменены
