## MODIFIED Requirements

### Requirement: Подкоманда secret бинаря
`codelab-agent secret set|delete|list|migrate` SHALL работать без запуска сервера и без открытия транспорта. Тексты, правила и коды выхода даёт общая реализация `SecretCommands` (capability `agent-secrets`, «Подкоманды secret»). Разбор аргументов — `apps/codelab_agent/lib/src/cli/secret_cli.dart`. `codelab-agent secret` без подкоманды или с неизвестной подкомандой SHALL завершаться кодом `64`, сообщением `codelab-agent: secret needs a subcommand: set, delete, list or migrate` и справкой `secret` в stderr; ошибка разбора argv — кодом `64`, сообщением `codelab-agent: invalid arguments for secret` без присланных слов и справкой `secret`. Ошибки использования из `SecretCommands` (неверное имя, значение аргументом) бинарь SHALL дополнять справкой `secret`, ошибки значения — нет. Справка `secret` называет `codelab-agent`. Общая справка бинаря SHALL упоминать `secret set|delete|list|migrate`. Справка `secret` и справка `serve` (отдельного флага `--help` у `serve` нет: справка печатается в stderr при ошибке использования) SHALL содержать строку `Note: before 1.0, tool output, prompts and session logs are not redacted: secrets they contain reach the model provider and session files as is.` (решение пользователя 2026-11-04 R8-7; design.md change `add-config-literal-secrets-and-migrate`, D13). `secret migrate [--all | [--project] [--local]] [--cwd <dir>] [--dry-run] [--force]` SHALL разбираться в `secret_cli.dart` и вызывать `SecretCommands.migrate` (capability `agent-secrets`, «Подкоманда secret migrate»; design.md change `add-config-literal-secrets-and-migrate`, D7); `--project` и `--local` вместе допустимы; позиционные аргументы и `--all` вместе с любым из `--project`, `--local` — код `64`. stdin SHALL читаться только подкомандой `set`.

#### Scenario: Неизвестная подкоманда
- **WHEN** запускается `codelab-agent secret show codelab/openai`
- **THEN** код `64`, stderr содержит `secret needs a subcommand` и справку `secret`, не содержит `codelab/openai`, stdout пуст, хранилище не вызывалось

#### Scenario: list с бэкендом env
- **WHEN** запускается `codelab-agent secret list` с `secrets.backend: env` во временном `CODELAB_HOME`
- **THEN** первая строка stdout — `Backend: env`, код `0`

#### Scenario: Секрет из файла переносится
- **WHEN** `codelab-agent serve --stdio` с литеральным `providers.lm.api_key` стартует, а лог содержит `config.secret.in_file` с текстом `codelab secret migrate` без значения; затем выполняется `codelab-agent secret migrate` с `secrets.backend: file` и `serve` перезапускается
- **THEN** миграция — код `0`; после перезапуска предупреждения нет, а ход провайдера `lm` получает ключ из хранилища

#### Scenario: Предупреждение о 1.0 в справке
- **WHEN** запускаются `codelab-agent serve` без аргументов и `codelab-agent secret` без подкоманды
- **THEN** обе завершаются кодом `64`; stderr каждой со справкой содержит строку `Note: before 1.0, tool output, prompts and session logs are not redacted: secrets they contain reach the model provider and session files as is.`

## ADDED Requirements

### Requirement: Флаги stdin у mcp add бинаря
`codelab-agent mcp add` SHALL разбирать флаги `--header-stdin <Name>`, `--header-scheme <Scheme>` и `--env-stdin <NAME>` и вызывать `McpServerCommands` (capability `agent-configuration`, «Значение заголовка или переменной mcp add из stdin»; design.md change `add-config-literal-secrets-and-migrate`, D11). Справка `mcp` SHALL перечислять эти флаги; stdin SHALL читаться только при одном из флагов `-stdin`. Ошибка разбора argv НЕ SHALL цитировать присланные слова.

#### Scenario: Переменная из stdin
- **WHEN** `secrets.backend: file`, вызывается `codelab-agent mcp add gh --type stdio --command gh-mcp --env-stdin GITHUB_TOKEN`, в stdin — значение токена
- **THEN** код `0`; хранилище содержит `codelab/mcp/gh/github_token`; файл содержит `GITHUB_TOKEN: '${secret:codelab/mcp/gh/github_token}'`; значение не напечатано
