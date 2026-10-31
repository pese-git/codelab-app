## ADDED Requirements

### Requirement: Подкоманда codelab secret
`codelab secret set|delete|list` SHALL работать без запуска агента и без подключения по ACP. Подкоманда вызывает общую реализацию `SecretCommands` через `package:codelab_setup/io.dart`, поэтому её вывод и коды выхода совпадают с `codelab-agent secret` (capability `agent-secrets`, «Подкоманды secret»). Корень состояния — `CODELAB_HOME` по правилу `CodelabHome.resolve`. `package:codelab_setup/io.dart` SHALL импортироваться только из `lib/src/run.dart`.

Флаги подключения и запроса (`-a`/`--agent`, `-m`/`--model`, `--mode`, `-r`/`--resume`, `-c`/`--continue`, `-p`/`--print`, `-f`/`--prompt-file`, `--approve`, `--timeout`, `--ui`) вместе с `secret` SHALL быть ошибкой использования с кодом `64`. `codelab secret` без подкоманды — код `64` и `secret needs a subcommand: codelab secret set|delete|list` в stderr; неизвестная подкоманда — код `64` и `Unknown command secret <sub>`. Справка `codelab --help` SHALL называть `secret set|delete|list`.

Значение секрета НЕ SHALL попадать в stdout, `profiles.json`, `cli_history` и лог CLI. `codelab secret` НЕ SHALL создавать `sessions/`, `profiles.json` и `cli_history` в `CODELAB_HOME`.

#### Scenario: Совпадение с бинарём агента
- **WHEN** `codelab secret set codelab/x extra-arg` и `codelab-agent secret set codelab/x extra-arg` запускаются с одним окружением
- **THEN** у обоих код `64`, stderr содержит `pass the secret value on stdin, not as an argument`, stdout пуст и одинаков

#### Scenario: Флаги подключения с secret
- **WHEN** запускается `codelab -p hi secret list`
- **THEN** код `64`, stdout пуст, хранилище не вызывалось, агент не запущен

#### Scenario: Подкоманда не меняет CODELAB_HOME
- **WHEN** `codelab secret list` запускается с пустым временным `CODELAB_HOME` и `secrets.backend: env` в `CODELAB_CONFIG`
- **THEN** после выхода в `CODELAB_HOME` нет `sessions/`, `profiles.json`и `cli_history`; `secrets.yaml` не создан
