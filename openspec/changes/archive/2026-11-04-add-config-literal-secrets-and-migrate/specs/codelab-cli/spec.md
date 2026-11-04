## MODIFIED Requirements

### Requirement: Подкоманда codelab secret
`codelab secret set|delete|list|migrate` SHALL работать без запуска агента и без подключения по ACP. Подкоманда вызывает общую реализацию `SecretCommands` через `package:codelab_setup/io.dart`, поэтому её вывод и коды выхода совпадают с `codelab-agent secret` (capability `agent-secrets`, «Подкоманды secret»). Корень состояния — `CODELAB_HOME` по правилу `CodelabHome.resolve`. `package:codelab_setup/io.dart` SHALL импортироваться только из `lib/src/run.dart`.

Флаги подключения и запроса (`-a`/`--agent`, `-m`/`--model`, `--mode`, `-r`/`--resume`, `-c`/`--continue`, `-p`/`--print`, `-f`/`--prompt-file`, `--approve`, `--timeout`, `--ui`) вместе с `secret` SHALL быть ошибкой использования с кодом `64` и сообщением `codelab: --<flag> does not apply to secret` (то же для `-C`/`--cwd` верхнего уровня). Исключение — флаги подкоманды `secret migrate`: `--project`, `--local`, `--all`, `--cwd <dir>`, `--dry-run`, `--force` после слова `migrate` SHALL разбираться как её флаги (capability `agent-secrets`, «Подкоманда secret migrate»; design.md change `add-config-literal-secrets-and-migrate`, D7); `--all` вместе с `--project` или `--local` — код `64`. `codelab secret` без подкоманды или с неизвестной подкомандой — код `64` и `codelab: secret needs a subcommand: set, delete, list or migrate` в stderr; `set` без имени — `codelab: secret set needs the secret name`; `delete` не с одним именем — `codelab: secret delete needs exactly one name`; `list` с аргументами — `codelab: secret list takes no arguments`; `migrate` с позиционными аргументами — `codelab: secret migrate takes no arguments`; ошибка разбора argv — `codelab: invalid arguments for secret`, если `secret` есть в argv где угодно, в том числе при ошибке флага верхнего уровня до `secret`; текст исключения `package:args` НЕ SHALL печататься. Все эти ошибки дают код `64` и справку `secret` (`Usage: codelab secret set|delete|list|migrate`) в stderr. Ни одно из этих сообщений НЕ SHALL цитировать присланные слова: среди них может быть значение секрета (capability `agent-secrets`, «Подкоманды secret»). Справка `codelab --help` SHALL содержать строку `codelab secret set|delete|list|migrate   manage secrets (set reads the value on stdin)`. Справка `secret` и `codelab --help` SHALL содержать строку `Note: before 1.0, tool output, prompts and session logs are not redacted: secrets they contain reach the model provider and session files as is.` (решение пользователя 2026-11-04 R8-7; design.md change `add-config-literal-secrets-and-migrate`, D13).

Значение секрета НЕ SHALL попадать в stdout, `profiles.json`, `cli_history` и лог CLI. `codelab secret` НЕ SHALL создавать `sessions/`, `profiles.json` и `cli_history` в `CODELAB_HOME`.

#### Scenario: Совпадение с бинарём агента
- **WHEN** `codelab secret set codelab/x extra-arg` и `codelab-agent secret set codelab/x extra-arg` запускаются с одним окружением
- **THEN** у обоих код `64`, stderr содержит `pass the secret value on stdin, not as an argument`, stdout пуст и одинаков

#### Scenario: Флаги подключения с secret
- **WHEN** запускается `codelab -p hi secret list`
- **THEN** код `64`, stdout пуст, хранилище не вызывалось, агент не запущен

#### Scenario: --cwd с secret
- **WHEN** запускается `codelab -C /tmp secret list`
- **THEN** код `64`, stderr содержит `codelab: --cwd does not apply to secret` и справку `secret`, хранилище не вызывалось

#### Scenario: Ошибка верхнего парсера с secret
- **WHEN** запускается `codelab --no-such-flag secret list`
- **THEN** код `64`, stderr содержит `codelab: invalid arguments for secret` и справку `secret` и не содержит `no-such-flag` и текста `package:args` (`Could not find an option`)

#### Scenario: Подкоманда не меняет CODELAB_HOME
- **WHEN** `codelab secret list` запускается с пустым временным `CODELAB_HOME` и `secrets.backend: env` в `CODELAB_CONFIG`
- **THEN** после выхода в `CODELAB_HOME` нет `sessions/`, `profiles.json`и `cli_history`; `secrets.yaml` не создан

#### Scenario: migrate совпадает с бинарём агента
- **WHEN** `codelab secret migrate --all --dry-run --cwd <dir>` и `codelab-agent secret migrate --all --dry-run --cwd <dir>` запускаются с одним `CODELAB_HOME` и конфигом с литеральными секретами
- **THEN** stdout и коды выхода совпадают байт в байт, ни один вывод не содержит значений

#### Scenario: --cwd подкоманды migrate и -C верхнего уровня
- **WHEN** запускается `codelab secret migrate --project --cwd /tmp/p`, а отдельно — `codelab -C /tmp/p secret migrate`
- **THEN** первая команда работает со слоем проекта `/tmp/p`; вторая — код `64` с `codelab: --cwd does not apply to secret`

#### Scenario: Предупреждение о 1.0 в справке
- **WHEN** запускаются `codelab --help` и `codelab secret` без подкоманды
- **THEN** stderr или stdout каждой содержит строку `Note: before 1.0, tool output, prompts and session logs are not redacted: secrets they contain reach the model provider and session files as is.`

## ADDED Requirements

### Requirement: Флаги stdin у codelab mcp add
`codelab mcp add` SHALL разбирать флаги `--header-stdin <Name>`, `--header-scheme <Scheme>` и `--env-stdin <NAME>` и передавать их общей реализации `McpServerCommands` через `package:codelab_setup/io.dart` (capability `agent-configuration`, «Значение заголовка или переменной mcp add из stdin»; design.md change `add-config-literal-secrets-and-migrate`, D11). stdout, stderr и код выхода SHALL совпадать с `codelab-agent mcp add` при одном окружении и одном stdin. Справка `mcp` SHALL перечислять эти флаги. stdin SHALL читаться только при одном из флагов `-stdin`.

#### Scenario: Совпадение с бинарём агента
- **WHEN** `codelab mcp add gh --type http --url https://h --header-stdin Authorization --header-scheme Bearer` и та же команда `codelab-agent` запускаются с одним `CODELAB_HOME` (`secrets.backend: file`) и одним значением в stdin
- **THEN** коды `0`, stdout совпадает байт в байт, байты записанного `config.yaml` совпадают, значение не напечатано
