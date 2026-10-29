## ADDED Requirements

### Requirement: Подкоманда codelab config
`codelab config check [--cwd <dir>]` SHALL работать без запуска агента и без подключения по ACP. Она вызывает общую реализацию `ConfigCommands` через `package:codelab_setup/io.dart` (design.md change `add-agent-configuration`, D13, D14), поэтому её вывод и коды выхода совпадают с `codelab-agent config` (capability `agent-configuration`). Корень состояния — `CODELAB_HOME` (по умолчанию `~/.codelab`), `cwd` — `--cwd` или текущий каталог. Остальные подкоманды `config` (`get`, `set`, `unset`, `path`, `migrate`) в этой сборке НЕ SHALL регистрироваться: код `64` и `Unknown command` в stderr. Клиент НЕ SHALL импортировать `package:codelab_agent_*` напрямую.

#### Scenario: Проверка конфига из CLI
- **WHEN** `codelab config check --cwd <dir>` запускается для каталога, где глобальный `config.yaml` задаёт провайдера и `agent.default_model`, а `<dir>/.codelab/config.yaml` содержит `budget.max_steps: 0`
- **THEN** stdout содержит проблему `budget.max_steps` с файлом и строкой, последняя строка `Config: invalid (issues: 1)`, код `1`, ни один процесс агента не запущен (`cli/config-check-reports-issues`)

#### Scenario: Подкоманда записи ещё не зарегистрирована
- **WHEN** запускается `codelab config set budget.max_steps 10` или `codelab config migrate`
- **THEN** код `64`, в stderr — `Unknown command`, файлы конфига не изменены
