## ADDED Requirements

### Requirement: Подкоманда codelab secret
`codelab secret set|delete|list` SHALL работать без запуска агента и без подключения по ACP. Подкоманда вызывает общую реализацию `SecretCommands` через `package:codelab_setup/io.dart`, поэтому её вывод и коды выхода совпадают с `codelab-agent secret` (capability `agent-secrets`, «Подкоманды secret»). Корень состояния — `CODELAB_HOME` по правилу `CodelabHome.resolve`. `package:codelab_setup/io.dart` SHALL импортироваться только из `lib/src/run.dart`.

Флаги подключения и запроса (`-a`/`--agent`, `-m`/`--model`, `--mode`, `-r`/`--resume`, `-c`/`--continue`, `-p`/`--print`, `-f`/`--prompt-file`, `--approve`, `--timeout`, `--ui`) вместе с `secret` SHALL быть ошибкой использования с кодом `64` и сообщением `codelab: --<flag> does not apply to secret` (то же для `-C`/`--cwd`). `codelab secret` без подкоманды или с неизвестной подкомандой — код `64` и `codelab: secret needs a subcommand: set, delete or list` в stderr; `set` без имени — `codelab: secret set needs the secret name`; `delete` не с одним именем — `codelab: secret delete needs exactly one name`; `list` с аргументами — `codelab: secret list takes no arguments`; ошибка разбора argv — `codelab: invalid arguments for secret`, если `secret` есть в argv где угодно, в том числе при ошибке флага верхнего уровня до `secret`; текст исключения `package:args` НЕ SHALL печататься. Все эти ошибки дают код `64` и справку `secret` (`Usage: codelab secret set|delete|list`) в stderr. Ни одно из этих сообщений НЕ SHALL цитировать присланные слова: среди них может быть значение секрета (capability `agent-secrets`, «Подкоманды secret»). Справка `codelab --help` SHALL содержать строку `codelab secret set|delete|list      manage secrets (value on stdin)`.

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
