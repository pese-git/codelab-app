## ADDED Requirements

### Requirement: Хранилище секретов в бинаре
`AgentHost.build` SHALL создавать одно хранилище по `secrets.backend` загруженного конфига и окружению процесса, а над ним — один `SecretResolver` на процесс. Резолвер SHALL передаваться в функцию модели (`createRoutedStreamFunction`) и в `AgentCoreServices.secrets` (design.md, D11).
- **`--debug-secrets`** — флаг `serve` без значения; он и `CODELAB_DEBUG_SECRETS=1` включают режим отладки резолвера (capability `agent-secrets`, «Диагностика обращений к секретам»). Режим НЕ SHALL менять уровень лога.
- **`secrets.backend: keychain`** — проблема конфигурации «not supported yet» (capability `agent-secrets`): `serve` завершается кодом `64` до старта транспорта.
- **`--llm-script`** SHALL использовать бэкенд `env` независимо от `secrets.backend`: `secrets.yaml` не читается, событие выбора — `secrets.backend.selected {backend: env, reason: forced by --llm-script}`.
- **`secrets.backend: file`** SHALL давать при каждом старте предупреждение `secrets.backend.plaintext {path}` в лог и stderr.
- **`serve --ws`** SHALL разрешать ключи провайдеров так же, как `--stdio`.

Значения секретов НЕ SHALL попадать в stdout, stderr, лог, журнал сессии и кадры ACP.

#### Scenario: Ключ провайдера из переменной переопределения
- **WHEN** `codelab-agent serve --stdio` запускается с конфигом `providers.p.api_key_secret: codelab/p`, `CODELAB_SECRET_CODELAB_P=sk-test-0123456789abcdef` и локальным HTTP-сервером провайдера в тесте
- **THEN** запрос к серверу несёт ключ, а stdout, stderr и файл лога не содержат `sk-test-0123456789abcdef`

#### Scenario: Секрет не задан — ошибка хода
- **WHEN** тот же конфиг без переменной, `secrets.backend: env`, клиент выполняет `session/prompt` с моделью `p/<model>`
- **THEN** ответ `session/prompt` — JSON-RPC ошибка, текст которой содержит `API key secret codelab/p is not set. Run: codelab secret set codelab/p`; процесс продолжает работать

#### Scenario: Режим отладки секретов
- **WHEN** тот же запуск с `--debug-secrets` и переменной `CODELAB_SECRET_CODELAB_P`
- **THEN** лог содержит `secrets.lookup` с `name: codelab/p`, `source: env`, `found: true` и не содержит значения

#### Scenario: Бэкенд file при старте
- **WHEN** `serve --stdio` запускается с глобальным `secrets.backend: file` во временном `CODELAB_HOME`
- **THEN** лог содержит `secrets.backend.plaintext` с путём `<CODELAB_HOME>/secrets.yaml`, файл не создан, процесс работает

#### Scenario: Сценарий не читает secrets.yaml
- **WHEN** `serve --stdio --llm-script <file>` запускается с `--config`, где `secrets.backend: file`, а в `CODELAB_HOME` лежит `secrets.yaml`
- **THEN** процесс стартует, ход сценария выполняется, файл не открывается, лог содержит `secrets.backend.selected` с `backend: env` и `reason: forced by --llm-script`

### Requirement: Подкоманда secret бинаря
`codelab-agent secret set|delete|list` SHALL работать без запуска сервера и без открытия транспорта. Тексты, правила и коды выхода даёт общая реализация `SecretCommands` (capability `agent-secrets`, «Подкоманды secret»). Разбор аргументов — `apps/codelab_agent/lib/src/cli/secret_cli.dart`. `codelab-agent secret` без подкоманды или с неизвестной подкомандой SHALL завершаться кодом `64`, сообщением `codelab-agent: secret needs a subcommand: set, delete or list` и справкой `secret` в stderr; ошибка разбора argv — кодом `64`, сообщением `codelab-agent: invalid arguments for secret` без присланных слов и справкой `secret`. Ошибки использования из `SecretCommands` (неверное имя, значение аргументом) бинарь SHALL дополнять справкой `secret`, ошибки значения — нет. Справка `secret` называет `codelab-agent`. Общая справка бинаря SHALL упоминать `secret set|delete|list`. stdin SHALL читаться только подкомандой `set`.

#### Scenario: Неизвестная подкоманда
- **WHEN** запускается `codelab-agent secret show codelab/openai`
- **THEN** код `64`, stderr содержит `secret needs a subcommand` и справку `secret`, не содержит `codelab/openai`, stdout пуст, хранилище не вызывалось

#### Scenario: list с бэкендом env
- **WHEN** запускается `codelab-agent secret list` с `secrets.backend: env` во временном `CODELAB_HOME`
- **THEN** первая строка stdout — `Backend: env`, код `0`
