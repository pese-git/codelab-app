## MODIFIED Requirements

### Requirement: Секреты только ссылками
Конфигурация НЕ SHALL хранить ключи API значением (CFG-2). Ключи `api_key`, `apiKey`, `token`, `secret`, `password` в `providers.*` и в элементах `mcp.servers` SHALL давать проблему `inlineSecret`; хост SHALL отказывать в старте исключением `ConfigInlineSecretException` с путём ключа и `suggestedSecretName` — именем `SecretNames.suggestFor(путь)` (capability `agent-secrets`, «Имена секретов»). Текст проблемы НЕ SHALL содержать значение и SHALL называть команду `codelab secret set <suggestedSecretName>`:
- у провайдера — и ссылку `api_key_secret: <suggestedSecretName>`;
- у элемента `mcp.servers` — и подстановку `${secret:<suggestedSecretName>}` в `env` или `headers`.

`api_key_env` и `api_key_secret` вместе SHALL быть проблемой с ключом `providers.<id>.api_key_secret`. Значение `api_key_env` SHALL быть именем переменной (`[A-Za-z_][A-Za-z0-9_]*`, иначе `expected an environment variable name`). Значение `api_key_secret` и имя в `${secret:<name>}` SHALL проходить правило `SecretNames` (иначе `expected a secret name: lowercase letters, digits and . _ / -, up to 128 characters`). Неверный формат — проблема `value` с путём ключа без значения в тексте. Проверка литералов по шаблонам §12.4 (пункты 2–3 CFG-9) — change `add-agent-core-secret-redaction`.

- `api_key_env` незаданной переменной SHALL давать предупреждение `config.provider.key_missing {provider, variable}` при загрузке и ошибку хода `API key variable <VAR> is not set` при выборе модели этого провайдера без HTTP-запроса. Значение переменной SHALL читаться при запросе через `SecretResolver.env`.
- `api_key_secret` и `${secret:<name>}` в `providers.*.headers.*`, `mcp.servers[*].env.*` и `mcp.servers[*].headers.*` SHALL разрешаться через `SecretResolver`: у провайдера — при запросе, у MCP-сервера — при подключении к сессии (capability `agent-secrets`, требования «Ключ провайдера при запросе» и «Секреты MCP-серверов конфигурации»). Загрузка НЕ SHALL читать хранилище секретов и НЕ SHALL пропускать MCP-сервер из-за ссылки на секрет.
- `${secret:…}` вне значений `env` и `headers` — в `mcp.servers[*].args[*]`, `mcp.servers[*].url` и `providers.*.base_url`, где `${ENV}` допустим, — SHALL давать проблему `value` с путём ключа и текстом `secret references ${secret:…} are allowed only in env and headers values`; конфиг невалиден. Ссылка там НЕ SHALL раскрываться и НЕ SHALL оставаться литералом: argv виден через `ps`, а URL попадает в логи и тексты ошибок (fail closed; design.md, D4).
- Ключ `secrets.backend` SHALL принимать `auto`, `keychain`, `env`, `file` (capability `agent-secrets`, «Выбор бэкенда secrets.backend»); он больше не даёт `config.key.not_applied`. `keychain` и незнакомое значение SHALL давать проблему `value` ядра. `file` на Windows SHALL давать проблему `value` от `ConfigLoader` (ядро платформу не знает) с источником и позицией слоя, где задан ключ, и текстом общей проверки `secretsBackendProblem`: `secrets.backend: file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`. Загрузка со `scripted` (`--llm-script`) эту проверку не выполняет: сценарий всегда использует `env` (design.md, D7, D11, D14).

#### Scenario: file на Windows при загрузке
- **WHEN** `ConfigLoader.load` с подменённой платформой `windows` читает пользовательский `config.yaml` с `secrets.backend: file`
- **THEN** результат без `config` и `host`, проблема `value` с ключом `secrets.backend`, источником этого файла и строкой ключа `backend`, `toString()` содержит `secrets.backend: file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`; `auto` и `env` на Windows проблем не дают

#### Scenario: Ключ значением
- **WHEN** `config.yaml` задаёт `providers.openai.api_key: sk-test-secret`
- **THEN** запуск отклонён с проблемой `providers.openai.api_key`, текст содержит `codelab secret set codelab/openai` и `api_key_secret: codelab/openai`, у исключения `suggestedSecretName == "codelab/openai"`, а stderr, лог и вывод `config check` не содержат `sk-test-secret` (`core/config-rejects-inline-api-key`)

#### Scenario: Токен значением у MCP-сервера
- **WHEN** элемент `mcp.servers` с `name: github` задаёт `token: ghp-test-secret`
- **THEN** проблема `mcp.servers[github].token`, текст содержит `codelab secret set codelab/mcp/github/token` и `${secret:codelab/mcp/github/token}` и не содержит `ghp-test-secret`

#### Scenario: Ключ вместо имени переменной
- **WHEN** провайдер задаёт `api_key_env: sk-test-secret-123`
- **THEN** проблема `providers.<id>.api_key_env` о формате имени, текст и лог не содержат `sk-test-secret-123`

#### Scenario: Ключ вместо имени секрета
- **WHEN** провайдер задаёт `api_key_secret: "sk-Test Secret"`
- **THEN** проблема `providers.<id>.api_key_secret` с текстом правила имени, текст и лог не содержат значения

#### Scenario: Ссылка на секрет в args MCP-сервера
- **WHEN** stdio-сервер `gh` задаёт `args: ["--token", "${secret:codelab/mcp/gh/token}"]`
- **THEN** проблема `value` `mcp.servers[gh].args[1]: secret references ${secret:…} are allowed only in env and headers values`, конфиг невалиден, хранилище не вызывалось

#### Scenario: Ссылка на секрет в base_url провайдера
- **WHEN** провайдер `gw` задаёт `base_url: "https://llm.internal/${secret:codelab/gw}/v1"`
- **THEN** проблема `value` `providers.gw.base_url: secret references ${secret:…} are allowed only in env and headers values`, конфиг невалиден, хранилище не вызывалось

#### Scenario: Переменная ключа не задана
- **WHEN** провайдер `openai` задаёт `api_key_env: OPENAI_API_KEY`, переменная не задана, а сессия выбирает модель `openai/gpt-4o`
- **THEN** загрузка успешна с предупреждением `config.provider.key_missing`, а ход завершается ошибкой `API key variable OPENAI_API_KEY is not set` без запроса к провайдеру

#### Scenario: Ссылки на секреты не читаются при загрузке
- **WHEN** провайдер задаёт `api_key_secret: codelab/anthropic`, а сервер `gh` — заголовок `${secret:codelab/mcp/gh/authorization}`; загрузка идёт с хранилищем, которое считает вызовы
- **THEN** загрузка успешна без предупреждений о секретах, хранилище не вызывалось, `CoreConfig.mcpServers` содержит `gh`, `providerProblems` не содержит `anthropic`

### Requirement: Подкоманда config check
`codelab-agent config check [--cwd <dir>]` и `codelab config check [--cwd <dir>]` SHALL выполнять полную загрузку для `cwd` (по умолчанию — текущий каталог процесса) без запуска агента. Загрузка SHALL учитывать окружение процесса целиком, включая `CODELAB_CONFIG` и прочие `CODELAB_*`; флагов `serve` (`--config`, `--provider`, `--model` и других) у подкоманды нет: проверяется то, что увидит `serve` без флагов. Вывод в stdout по строкам:
- первая строка — `Sources: <источники через ", ">`, где источники — `ConfigLoadResult.sources` как есть, по порядку слоёв: `defaults`, затем канонические абсолютные пути прочитанных файлов, затем `env`, если есть переменные-ключи (например `Sources: defaults, /home/u/.codelab/config.yaml, /work/demo/.codelab/config.yaml`);
- каждая проблема — строка `ConfigIssue.toString()`: `<location>: <key>: <message>`, без `<key>: `, если ключ пустой; `<location>` — `<source>:<line>:<column>` или `<source>`, если позиции нет; подсказка (`did you mean max_steps?`) — часть `<message>`;
- каждое предупреждение — строка `warning: <location>: [<key>: ]<message>` в той же форме, включая `config.legacy_found` и `config.env.unknown`. Текст `config.legacy_found` НЕ SHALL повторять путь, уже стоящий в `<location>`. Неизвестные `CODELAB_*` SHALL распознаваться в `ConfigLoader` (`codelab_agent_io`), а не в каждом бинаре: правило одно для `serve` и обеих подкоманд. `CODELAB_TEST_SECRET_STORE` SHALL считаться известной только в сборке с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`; в обычной сборке она SHALL давать `config.env.unknown`, как любая неизвестная `CODELAB_*`, и НЕ SHALL читаться (agent-core §15.6);
- последняя строка — `Config: valid` или `Config: invalid (issues: <n>)`, где `<n>` — число проблем; предупреждения проблемами не считаются.

Код выхода SHALL быть `0` при валидном конфиге (с предупреждениями тоже), `1` при проблемах, `64` при ошибке использования. Ошибка использования — несуществующий каталог `--cwd` и `ConfigUsageException` загрузчика (`CODELAB_CONFIG` с расширением `.toml` или относительный): текст ошибки идёт в stderr, stdout SHALL быть пустым. Подкоманда НЕ SHALL писать файлы и печатать значения секретов. Обе подкоманды SHALL использовать одну реализацию `ConfigCommands` из `codelab_agent_io`.

#### Scenario: Битый конфиг
- **WHEN** `config.yaml` задаёт провайдера и `agent.default_model`, содержит одну опечатку ключа, а `config check` запускается в этом `cwd`
- **THEN** первая строка stdout начинается с `Sources: defaults, ` и называет канонический абсолютный путь `config.yaml`, строка проблемы содержит файл, строку, столбец, путь ключа и подсказку `did you mean …?`, последняя строка `Config: invalid (issues: 1)`, код `1`

#### Scenario: Предупреждения не делают конфиг невалидным
- **WHEN** `config.yaml` валиден, окружение содержит неизвестную переменную `CODELAB_UNKNOWN_X=1`, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку `warning: …` предупреждения `config.env.unknown`, называющую `CODELAB_UNKNOWN_X`, но не её значение; последняя строка `Config: valid`, код `0`

#### Scenario: Подсказка о codelab.toml
- **WHEN** `CODELAB_HOME` пуст, в `cwd` есть только `codelab.toml`, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку `warning: <cwd>/codelab.toml: codelab.toml is not used by the Dart agent…`, в тексте после локации путь `<cwd>/codelab.toml` не повторяется; единственная проблема — `agent.default_model: required`, последняя строка `Config: invalid (issues: 1)`, код `1`

#### Scenario: CODELAB_CONFIG учитывается
- **WHEN** `CODELAB_CONFIG=<tmp>/extra.yaml` (абсолютный путь), файл содержит неизвестный ключ, а `config check` запускается без флагов
- **THEN** строка `Sources:` содержит `<tmp>/extra.yaml`, stdout содержит проблему этого файла, код `1`

#### Scenario: Несуществующий каталог
- **WHEN** запускается `config check --cwd <tmp>/missing`, а каталога нет
- **THEN** код `64`, stderr называет каталог, stdout пуст

#### Scenario: Ошибка использования из окружения
- **WHEN** `CODELAB_CONFIG` равна `<tmp>/c.toml` или относительному пути `.codelab/extra.yaml`
- **THEN** код `64`, stderr содержит текст `ConfigUsageException` с именем `CODELAB_CONFIG`, stdout пуст, файл не читается

#### Scenario: Одинаковый вывод у двух бинарей
- **WHEN** `codelab-agent config check` и `codelab config check` запускаются с одним окружением и `cwd`
- **THEN** их stdout и коды выхода совпадают

#### Scenario: Тестовое хранилище в обычной сборке
- **WHEN** агент собран без `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`, `config.yaml` валиден, окружение содержит `CODELAB_TEST_SECRET_STORE=<tmp>/test-secrets`, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку `warning: …` предупреждения `config.env.unknown`, называющую `CODELAB_TEST_SECRET_STORE`, но не её значение; каталог `<tmp>/test-secrets` не читается и не создаётся; последняя строка `Config: valid`, код `0`

### Requirement: Наблюдаемость загрузки конфигурации
Успешная загрузка SHALL писать `host.config.loaded {sources, warnings, project_root, transport, models}` (`transport` — `stdio` или `ws`, `models` — id моделей каталога). Каждое предупреждение загрузки SHALL писаться отдельным событием своего имени (`config.env.unknown`, `config.project.untrusted_key`, `config.key.not_applied`, `config.provider.key_missing`, `config.file.ignored`, `config.legacy_found`, `mcp.server.skipped`) и SHALL нести поле `message` — английский текст `ConfigIssue.message` без значений. Событие `config.secret.unavailable` НЕ SHALL писаться: ссылки на секреты разрешаются при запросе и подключении (requirement «Секреты только ссылками»). Значения ключей конфигурации, переменных и секретов НЕ SHALL попадать в эти события и в текст проблем: только пути ключей, имена переменных и секретов, источники.

#### Scenario: Ни одного значения в логе
- **WHEN** конфиг содержит `headers.Authorization: "Bearer ${TOKEN}"` с `TOKEN=tok-test-secret` и ключ без потребителя, а агент стартует с `--log-level trace`
- **THEN** лог содержит `host.config.loaded` с полями `transport` и `models` и `config.key.not_applied` с полями `key`, `source`, `message`, но не содержит `tok-test-secret`

#### Scenario: Нет предупреждения о недоступном хранилище
- **WHEN** конфиг содержит `api_key_secret` и `${secret:…}` в MCP-сервере
- **THEN** лог загрузки не содержит `config.secret.unavailable`

## ADDED Requirements

### Requirement: config check показывает состояние секретов
Если загрузка валидна, а конфиг ссылается на секреты (`api_key_secret`, `${secret:…}` у провайдеров и MCP-серверов), `config check` SHALL проверять каждое имя (без повторов) резолвером без режима отладки, с тем же хранилищем, что у подкоманд `secret`. Перед последней строкой `Config: …` SHALL печататься:
- `note: secrets backend: <id>` (или `note: secrets backend: env (<reason>)`);
- на каждый ненайденный секрет — `warning: <location>: <key>: secret <name> is not set; run: codelab secret set <name>`; при бэкенде `env` (в том числе `auto`) текст SHALL вместо этого подсказывать `set <envOverride(name)> or add 'secrets.backend: file' and run: codelab secret set <name>` (на Windows — только переменную);
- при недоступном хранилище — одна строка `warning: secrets: <backend> is unavailable (<reason>)`.

`<location>` — `файл:строка:столбец` слоя, который последним задал ключ ссылки (слой без позиций — имя источника).

При `secrets.backend: file` SHALL всегда, даже без ссылок на секреты, печататься `warning: secrets: file backend stores secrets unencrypted in <path>`. Отказ бэкенда `file` SHALL давать ровно одну строку: при правах шире `0600` — `warning: secrets: <path> has permissions <mode>; run: chmod 600 <path>`, при любой другой причине — `warning: secrets: file is unavailable (<reason>)`. При отказе бэкенда строки по отдельным именам НЕ SHALL печататься.

Найденный секрет строки НЕ SHALL давать. Значения секретов НЕ SHALL печататься и логироваться. Без ссылок на секреты хранилище НЕ SHALL вызываться, и вывод НЕ SHALL меняться, кроме строк бэкенда `file`. Строки секретов НЕ SHALL влиять на код выхода. Обе подкоманды `config check` SHALL печатать одно и то же.

#### Scenario: Секрет не задан при auto
- **WHEN** валидный конфиг на macOS или Linux задаёт `providers.openai.api_key_secret: codelab/openai` без `secrets.backend`, переменной `CODELAB_SECRET_CODELAB_OPENAI` нет
- **THEN** stdout содержит `note: secrets backend: env (…)` и `warning: …: providers.openai.api_key_secret: secret codelab/openai is not set; set CODELAB_SECRET_CODELAB_OPENAI or add 'secrets.backend: file' and run: codelab secret set codelab/openai`, последняя строка `Config: valid`, код `0`

#### Scenario: Секрет не задан в file
- **WHEN** тот же конфиг с `secrets.backend: file`, `secrets.yaml` с правами `0600` без `codelab/openai`
- **THEN** строка `warning: …: secret codelab/openai is not set; run: codelab secret set codelab/openai`, код `0`

#### Scenario: Секрет задан переменной
- **WHEN** тот же конфиг, а `CODELAB_SECRET_CODELAB_OPENAI=sk-test-0123456789abcdef`
- **THEN** строки `warning:` про `codelab/openai` нет, stdout не содержит `sk-test-0123456789abcdef`

#### Scenario: Предупреждение об открытом тексте
- **WHEN** валидный глобальный конфиг задаёт `secrets.backend: file` и не ссылается на секреты, `secrets.yaml` имеет права `0644`
- **THEN** stdout содержит `warning: secrets: file backend stores secrets unencrypted in <path>` и строку о правах с `chmod 600`, последняя строка `Config: valid`, код `0`

#### Scenario: Отказ file без строк по именам
- **WHEN** валидный конфиг с `secrets.backend: file` ссылается на `codelab/openai` и `codelab/mcp/github/authorization`, `secrets.yaml` имеет права `0644`
- **THEN** stdout содержит `warning: secrets: <path> has permissions 0644; run: chmod 600 <path>` ровно один раз и не содержит строк `is not set` и `is unavailable`, последняя строка `Config: valid`, код `0`

#### Scenario: Отказ file по другой причине
- **WHEN** валидный конфиг с `secrets.backend: file` ссылается на `codelab/openai`, а `secrets.yaml` — символическая ссылка
- **THEN** stdout содержит одну строку `warning: secrets: file is unavailable (…)` и не содержит строки `is not set`, код `0`

#### Scenario: Без ссылок вывод прежний
- **WHEN** конфиг использует только `api_key_env`
- **THEN** строк `note: secrets` и `warning: secrets` нет, хранилище не вызывалось
