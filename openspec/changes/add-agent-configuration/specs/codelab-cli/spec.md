## ADDED Requirements

### Requirement: Подкоманда codelab config
`codelab config check [--cwd <dir>]` SHALL работать без запуска агента и без подключения по ACP. Она вызывает общую реализацию `ConfigCommands` через `package:codelab_setup/io.dart` (design.md change `add-agent-configuration`, D13, D14), поэтому её вывод и коды выхода совпадают с `codelab-agent config` (capability `agent-configuration`). Корень состояния — `CODELAB_HOME` (по умолчанию `~/.codelab`); `config check` его не изменяет. `cwd` — `--cwd` подкоманды, иначе общий `-C`/`--cwd`, иначе текущий каталог; значение передаётся загрузчику как есть, без лексической нормализации, — канонизирует путь загрузчик, как у `codelab-agent`. Проверяется окружение процесса `codelab`; профиль подключения не учитывается, поэтому флаги подключения и запроса (`-a`/`--agent`, `-m`/`--model`, `--mode`, `-r`/`--resume`, `-c`/`--continue`, `-p`/`--print`, `-f`/`--prompt-file`, `--approve`, `--timeout`, `--ui`) вместе с `config` — ошибка использования с кодом `64`. `codelab config` без подкоманды — код `64` и `config needs a subcommand: codelab config check [--cwd <dir>]` в stderr. Остальные подкоманды `config` (`get`, `set`, `unset`, `path`, `migrate`) в этой сборке НЕ SHALL регистрироваться: код `64` и `Unknown command config <sub>` в stderr. Клиент НЕ SHALL импортировать `package:codelab_agent_*` напрямую.

#### Scenario: Проверка конфига из CLI
- **WHEN** `codelab config check --cwd <dir>` запускается для каталога, где глобальный `config.yaml` задаёт провайдера и `agent.default_model`, а `<dir>/.codelab/config.yaml` содержит `budget.max_steps: 0`
- **THEN** stdout содержит проблему `budget.max_steps` с файлом и строкой, последняя строка `Config: invalid (issues: 1)`, код `1`, ни один процесс агента не запущен (`cli/config-check-reports-issues`)

#### Scenario: Подкоманда записи ещё не зарегистрирована
- **WHEN** запускается `codelab config set budget.max_steps 10` или `codelab config migrate`
- **THEN** код `64`, в stderr — `Unknown command config set` (соответственно `Unknown command config migrate`), файлы конфига не изменены

#### Scenario: Неизвестная подкоманда config
- **WHEN** запускается `codelab config frobnicate`
- **THEN** код `64`, stdout пуст, stderr содержит `Unknown command config frobnicate`, процесс агента не запущен

#### Scenario: config без подкоманды
- **WHEN** запускается `codelab config`
- **THEN** код `64`, stdout пуст, stderr содержит `config needs a subcommand: codelab config check [--cwd <dir>]`

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
- **WHEN** запускается `codelab --agent <cmd> config check`, `codelab -p hi config check` или `codelab --prompt-file <f> config check`
- **THEN** код `64`, stdout пуст, в stderr — ошибка использования; процесс агента не запущен, конфиг не проверяется

#### Scenario: config check не меняет CODELAB_HOME
- **WHEN** `codelab config check` запускается с пустым временным `CODELAB_HOME`
- **THEN** после выхода в `CODELAB_HOME` нет `sessions/`, `profiles.json` и `cli_history`
