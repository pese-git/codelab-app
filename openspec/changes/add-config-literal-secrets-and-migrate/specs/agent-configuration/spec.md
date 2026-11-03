## MODIFIED Requirements

### Requirement: Ключи редакции секретов
Ключи `redact.enabled`, `redact.layers`, `redact.allowlist.builtin`, `redact.allowlist.patterns` и `redact.exempt_tools` SHALL читаться и проверяться (§12.4.3):
- имя слоя вне `exact`, `credential_files`, `formats`, `pem`, `connection_strings`, `key_values`, `entropy` — проблема;
- запись `builtin` вне `git_sha`, `uuid` — проблема;
- некомпилируемое регулярное выражение в `allowlist.patterns` — проблема с путём ключа.

Проверенные значения SHALL попадать в `CoreConfig.redact`. Правила доверия проектного слоя SHALL соблюдаться: без доверия проект может только включить редакцию, добавить слои и убрать записи `allowlist`. До change редакции секретов (P-10, после 1.0; решение пользователя 2026-11-04 R8-1, design.md change `add-config-literal-secrets-and-migrate`, D2) явно заданный ключ `redact.*` SHALL давать `config.key.not_applied`.

#### Scenario: Невалидное выражение
- **WHEN** `redact.allowlist.patterns` содержит `"[a-"`
- **THEN** проблема называет ключ `redact.allowlist.patterns[0]`, `CoreConfig` не построен

#### Scenario: Проект выключает редакцию без доверия
- **WHEN** недоверенный проект задаёт `redact.enabled: false` и новый `allowlist.patterns`
- **THEN** оба ключа отброшены с `config.project.untrusted_key`, `CoreConfig.redact.enabled` — `true`

### Requirement: Секреты только ссылками
Запись конфигурации (`ConfigWriter`, подкоманды CLI, страницы настроек клиентов) НЕ SHALL сохранять секрет значением (CFG-2; design.md change `add-config-literal-secrets-and-migrate`, D5). Литеральный секрет в **файле** конфига SHALL давать предупреждение, а не проблему (решение пользователя 2026-11-04 R8-4; требование «Литеральные секреты в файле конфига»): ключи `api_key`, `apiKey`, `token`, `secret`, `password` в `providers.*` и в элементах `mcp.servers` файловых слоёв SHALL давать предупреждение `config.secret.in_file` с путём ключа и текстом по шаблону `<key>: a secret is stored in the config file; move it to the secret store: <command>` требования «Литеральные секреты в файле конфига». Литеральный `providers.<id>.api_key` SHALL использоваться как ключ провайдера; остальные из этих ключей НЕ SHALL применяться. **R8-6:** `api_key` вместе с `api_key_env` или `api_key_secret` у одного провайдера после слияния слоёв SHALL быть проблемой загрузки `value` с ключом `providers.<id>.api_key` и текстом `api_key, api_key_env and api_key_secret are mutually exclusive` — это конфликт источников, а не «секрет в файле». Проблема `inlineSecret` и `ConfigInlineSecretException` SHALL оставаться у писателя и у предконфигурации из окружения (требование «Предконфигурация провайдера из окружения»), включая файл флага `--provider-config @путь`: это значение флага, а не слой конфига. Текст проблемы `inlineSecret` НЕ SHALL содержать значение и SHALL называть команду `codelab secret set <suggestedSecretName>` (`SecretNames.suggestFor(путь)`, capability `agent-secrets`, «Имена секретов»):
- у провайдера — и ссылку `api_key_secret: <suggestedSecretName>`;
- у элемента `mcp.servers` — и подстановку `${secret:<suggestedSecretName>}` в `env` или `headers`;

`api_key_env` и `api_key_secret` вместе SHALL быть проблемой с ключом `providers.<id>.api_key_secret`. Значение `api_key_env` SHALL быть именем переменной (`[A-Za-z_][A-Za-z0-9_]*`, иначе `expected an environment variable name`). Значение `api_key_secret` и имя в `${secret:<name>}` SHALL проходить правило `SecretNames` (иначе `expected a secret name: lowercase letters, digits and . _ / -, up to 128 characters`). Неверный формат — проблема `value` с путём ключа без значения в тексте. Литералы по шаблонам §12.4 (пункты 2–3 CFG-9) SHALL распознаваться по требованию «Литеральные секреты в файле конфига»; распознавание идёт до проверки формата имени.

- `api_key_env` незаданной переменной SHALL давать предупреждение `config.provider.key_missing {provider, variable}` при загрузке и ошибку хода `API key variable <VAR> is not set` при выборе модели этого провайдера без HTTP-запроса. Значение переменной SHALL читаться при запросе через `SecretResolver.env`.
- `api_key_secret` и `${secret:<name>}` в `providers.*.headers.*`, `mcp.servers[*].env.*` и `mcp.servers[*].headers.*` SHALL разрешаться через `SecretResolver`: у провайдера — при запросе, у MCP-сервера — при подключении к сессии (capability `agent-secrets`, требования «Ключ провайдера при запросе» и «Секреты MCP-серверов конфигурации»). Загрузка НЕ SHALL читать хранилище секретов и НЕ SHALL пропускать MCP-сервер из-за ссылки на секрет.
- `${secret:…}` вне значений `env` и `headers` — в `mcp.servers[*].args[*]`, `mcp.servers[*].url` и `providers.*.base_url`, где `${ENV}` допустим, — SHALL давать проблему `value` с путём ключа и текстом `secret references ${secret:…} are allowed only in env and headers values`; конфиг невалиден. Ссылка там НЕ SHALL раскрываться и НЕ SHALL оставаться литералом: argv виден через `ps`, а URL попадает в логи и тексты ошибок (fail closed; design.md, D4).
- Ключ `secrets.backend` SHALL принимать `auto`, `keychain`, `env`, `file` (capability `agent-secrets`, «Выбор бэкенда secrets.backend»); он больше не даёт `config.key.not_applied`. `keychain` и незнакомое значение SHALL давать проблему `value` ядра. `file` на Windows SHALL давать проблему `value` от `ConfigLoader` (ядро платформу не знает) с источником и позицией слоя, где задан ключ, и текстом общей проверки `secretsBackendProblem`: `secrets.backend: file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`. Загрузка со `scripted` (`--llm-script`) эту проверку не выполняет: сценарий всегда использует `env` (design.md, D7, D11, D14).

#### Scenario: file на Windows при загрузке
- **WHEN** `ConfigLoader.load` с подменённой платформой `windows` читает пользовательский `config.yaml` с `secrets.backend: file`
- **THEN** результат без `config` и `host`, проблема `value` с ключом `secrets.backend`, источником этого файла и строкой ключа `backend`, `toString()` содержит `secrets.backend: file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`; `auto` и `env` на Windows проблем не дают

#### Scenario: Ключ значением
- **WHEN** пользовательский `config.yaml` задаёт `providers.openai.api_key: sk-test-secret`, а сессия делает ход с моделью `openai`
- **THEN** загрузка успешна с предупреждением `config.secret.in_file` с текстом `providers.openai.api_key: a secret is stored in the config file; move it to the secret store: codelab secret migrate`, без `sk-test-secret`; запрос к провайдеру идёт с этим ключом; stderr, лог и вывод `config check` не содержат `sk-test-secret` (`core/config-warns-inline-api-key`, заменяет `core/config-rejects-inline-api-key`)

#### Scenario: Два источника ключа
- **WHEN** пользовательский слой задаёт `providers.openai.api_key: sk-x…`, а проектный (доверенный) — `providers.openai.api_key_secret: codelab/openai`
- **THEN** проблема `value` с ключом `providers.openai.api_key`, текст `api_key, api_key_env and api_key_secret are mutually exclusive` без значения; агент не стартует

#### Scenario: Токен значением у MCP-сервера
- **WHEN** элемент `mcp.servers` с `name: github` задаёт `token: ghp-test-secret`
- **THEN** загрузка успешна с предупреждением `mcp.servers[github].token: a secret is stored in the config file; move it to the secret store: codelab secret migrate` без `ghp-test-secret`; поле `token` не применяется

#### Scenario: Ключ вместо имени переменной
- **WHEN** провайдер `a` задаёт `api_key_env: sk-test-secret-123` (не совпадает с шаблоном `sk-…`: после префикса меньше 20 символов), а провайдер `b` — `api_key_env: sk-proj-AbCdEfGhIjKlMnOpQrStUvWx` (совпадает)
- **THEN** у `a` — проблема `providers.a.api_key_env` о формате имени без значения в тексте; у `b` — проблемы формата нет, есть предупреждение `config.secret.in_file` для `providers.b.api_key_env`, а ход с моделью `b` завершается ошибкой `API key reference providers.b.api_key_env looks like a secret value, not a name; run: codelab secret migrate`; текст и лог не содержат ни одного из значений

#### Scenario: Ключ вместо имени секрета
- **WHEN** провайдер `a` задаёт `api_key_secret: "sk-Test Secret"` (не совпадает с шаблоном), а провайдер `b` — `api_key_secret: ghp_abcdefghijklmnopqrstuvwxyz0123456789` (совпадает с шаблоном GitHub и при этом проходит правило `SecretNames`)
- **THEN** у `a` — проблема `providers.a.api_key_secret` с текстом правила имени; у `b` — предупреждение `config.secret.in_file`, ссылка не разрешается, хранилище не вызывается; текст и лог не содержат значений

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


### Requirement: Подкоманды записи и чтения конфига
Общая реализация `codelab_agent_io/lib/src/cli/` SHALL предоставлять подкоманды (design.md, D6):
- `ConfigCommands`: `path`, `get`, `set`, `unset` (а также существующий `check`);
- `ProviderCommands`: `add`, `list`, `remove`;
- `McpServerCommands`: `add`, `list`, `remove`.

Результат каждой подкоманды — `{exitCode, stdout, stderr}`. Набор флагов и действия — таблица §17.5.5. Аргументы разбирает каждое приложение. Вывод и коды выхода SHALL быть общими для `codelab-agent` и `codelab`.

**Правила:**
- **Слой.** Подкоманды записи (`config set`, `config unset`, `provider add`, `provider remove`, `mcp add`, `mcp remove`) SHALL по умолчанию писать в слой `user`; `--project` и `--local` — слои 3 и 4 для `cwd`. `config get` без `--layer` SHALL читать `merged`.
- **`cwd`** — `--cwd` подкоманды (есть у `config path|get|set|unset|check`, `provider list`, `mcp list`), иначе каталог процесса; канонизирует его загрузчик.
- **`config get`** SHALL печатать сырое значение слоя-победителя (скаляр — одной строкой, отображение и список — JSON с отступом), затем строку `layer: <name>`, где `<name>` — `user`, `project`, `local`, `extra` (файл `CODELAB_CONFIG`/`--config`), `env` или `flags`. Победитель — старший слой, где ключ задан; его поддерево берётся целиком. Подстановки `${VAR}` и `${secret:…}` НЕ SHALL раскрываться ни при каком `--layer`, включая `merged`. Отсутствующий ключ — код `1`.
- **Удаление отсутствующей записи** (`config unset`, `provider remove`, `mcp remove`) SHALL завершаться кодом `0` без записи файла и печатать `<key> is not set in <path>`.
- **Наличие ключа** для `config get`, `config unset`, `provider remove` и `mcp remove` SHALL определяться по пути в документе слоя, а не по значению: ключ со значением `null` присутствует, и `config unset` SHALL его удалять.
- **`provider add <id>`** для существующего провайдера SHALL обновлять его (upsert): переданные флаги перезаписывают свои поля, остальные поля и модели сохраняются.
- **Источник ключа** (R4-4): `provider add` с любым из `--api-key-stdin`, `--api-key-secret`, `--api-key-env` SHALL заменять источник ключа целиком — поля другого источника (`api_key_secret`, `api_key_env`, литеральный `api_key`) удаляются той же записью. Пары `api_key_env` + `api_key_secret` у провайдера после команды НЕ SHALL быть. Без флага ключа источник не меняется.
- **Недостающие обязательные флаги** `provider add` (`--kind`, `--model`, `--context-window`) SHALL перечисляться все одной строкой stderr.
- **`provider remove`** при ссылке из `agent.*` SHALL завершаться кодом `1`, stderr SHALL содержать `change the model first: config set agent.default_model <provider>/<model>`.
- **`mcp add` и `mcp remove`** SHALL отклонять имя сервера с пробелом, `[`, `]` или `"` кодом `64`.
- **`mcp remove <name>`** SHALL искать сервер только по `name`, никогда по номеру элемента списка.
- **Ошибка разбора аргументов** `config set`, `config unset`, `provider` и `mcp` SHALL печатать фиксированную фразу (`invalid arguments for config set`, `invalid arguments for config unset`, `invalid arguments for provider`, `invalid arguments for mcp`) и справку, не цитируя слова argv.
- **Маскирование** (R0-2; design.md, D6) — в `config get` и `provider list`:
  - значение любого листа без дескриптора реестра и элемента отображения с произвольными ключами (`headers`, `env`), чьё имя — ключ из `inlineSecretKeys` или секретное по нормализованному правилу требования «Запись конфига ConfigWriter» (на любой глубине дерева), без `${secret:…}` и `${VAR}` SHALL печататься как `<redacted>`; значение со ссылкой — как есть; скалярный лист, описанный реестром (`api_key_secret`, `api_key_env`, `auth_header`), SHALL печататься как есть, **кроме** листа с находкой `literalSecretTag` (литеральный `api_key`, ссылка-значение п. 3 в `api_key_env`/`api_key_secret`) — он SHALL печататься `<redacted>` (design.md change `add-config-literal-secrets-and-migrate`, D5); значения с `${…}` тоже SHALL проходить `literalSecretTag` по литеральным частям;
  - непрозрачное поддерево схемы (`providers.*.auth`, `providers.*.key_rotation`, разделы после MVP и другие узлы без схемы листьев) SHALL печататься как `<opaque: edit the file>` без содержимого;
  - значение из слоя окружения SHALL заменяться именем источника: `<from env:CODELAB_PROVIDER_CONFIG>`, `<from env:CODELAB_MODEL>`;
  - URL (`base_url`, `url`) SHALL разбираться как URI и печататься без userinfo (R4-5); неразбираемый URL и URL с `@` без авторитета (`user:pass@host`) SHALL печататься как `<redacted>`; значение query-параметра или пары `имя=значение` во фрагменте с секретным именем (то же нормализованное правило имён) без ссылки `${…}` SHALL печататься как `<redacted>`, значение-ссылка — как есть;
  - отображения и списки маскируются поэлементно.
- **`config set`** SHALL разбирать значение через `SettingsRegistry.parseCliValue`.
- **`config path`** без флага слоя SHALL печатать строки `user: <path> (exists|missing)`, `project: …`, `local: …` и при заданной `CODELAB_CONFIG` — `CODELAB_CONFIG: …`; с `--project`/`--local` — только путь.
- **`provider list`** SHALL первой строкой печатать `Secrets: <backend>`, затем по строке на провайдера итогового конфига `<id>  kind: …  base_url: …  models: a, b  key: <source>` (без `base_url` — `(default)`); источник ключа без значения (`secret <name>: found|not set|unavailable`, `env <VAR>: set|not set`, `literal in config file`; у ссылки-значения п. 3 — `unusable reference (looks like a secret value)` без поиска в хранилище).
- **`mcp list`** SHALL печатать серверы файлов по слоям строками `<name>  type: …  layer: …  enabled: true|false` без подключения к ним.
- **`provider add --api-key-stdin`**:
  1. проверить кандидат конфига без записи;
  2. проверить хранилище `SecretAdmin.checkStore("codelab/<id>")`;
  3. прочитать ключ через `SecretInput`;
  4. сохранить ключ `SecretAdmin.store`;
  5. записать `api_key_secret: codelab/<id>`.

  В конфиг SHALL попадать только имя секрета. Ошибка записи конфига после сохранения ключа SHALL называть сохранённый секрет в stderr. Если секрет `codelab/<id>` уже был, stdout SHALL содержать `warning: replaced the existing secret codelab/<id>`.
- **Конфликт.** При `ConfigConflictException` подкоманда SHALL один раз перечитать файл и повторить правки; второй конфликт — код `1` с текстом `config file changed during the edit; run the command again`.
- **Коды выхода:**
  - `0` — успех;
  - `1` — новая ошибка загрузки итога (R3-1), отказ доверия, `inlineSecret`, конфликт, хранилище секретов только для чтения или недоступно;
  - `64` — ошибка использования: неизвестный ключ `set`, неверное значение, недостающий обязательный флаг `provider add` (`--kind`, `--model`, `--context-window`), несовместимые флаги, лишние аргументы, недопустимое имя MCP-сервера.
- **Вывод успешной записи** SHALL содержать строку `Updated <key> in <path>` (`Updated providers.<id> in <path>`, `Updated mcp.servers[<name>] in <path>`) или `Removed <key> from <path>`, строки `warning:` предупреждений писателя и `note: restart the agent to apply: <keys>` для ключей `restartRequired`.

Значения секретов и раскрытые подстановки НЕ SHALL попадать в stdout, stderr и лог.

#### Scenario: config set и get
- **WHEN** в пустом `$CODELAB_HOME` вызывается `config set budget.max_steps 40`, затем `config get budget.max_steps`
- **THEN** первый — код `0`, `Updated budget.max_steps in <home>/config.yaml` и строка `warning: agent.default_model: required` (прежняя проблема конфига, R3-1), второй — `40` и слой `user`

#### Scenario: get не раскрывает переменную
- **WHEN** `providers.gw.headers.X-Token` в файле равен `"${GW_TOKEN}"`, окружение содержит `GW_TOKEN=t-123`, и вызывается `config get providers.gw.headers --layer merged`
- **THEN** stdout содержит `${GW_TOKEN}` и не содержит `t-123`

#### Scenario: get маскирует секреты
- **WHEN** файл содержит `providers.p.api_key: sk-1`, `providers.p.base_url: https://u:pw@h/v1`, `mcp.servers[gh].headers.Authorization: "Bearer lit"` и `mcp.servers[gh].env.GITHUB_TOKEN: "${GH}"`, а окружение — `CODELAB_MODEL=p/m`; вызываются `config get providers.p`, `config get mcp.servers --layer merged`, `config get agent.default_model`
- **THEN** вывод содержит `<redacted>` вместо `sk-1` и `Bearer lit`, `https://h/v1` без `u:pw`, `${GH}` как есть и `<from env:CODELAB_MODEL>`; ни `sk-1`, ни `pw`, ни `lit` в выводе нет (`config_output_test.dart`)

#### Scenario: Маскирование URL
- **WHEN** файл содержит `providers.p.base_url: "https://u:p@ss@host/v1?api_key=X&v=2"`, и вызываются `config get providers.p.base_url` и `provider list`
- **THEN** вывод не содержит `p@ss` и `X`, содержит `host/v1` и `v=2`

#### Scenario: Неразбираемый URL
- **WHEN** `providers.p.base_url` содержит строку, которую нельзя разобрать как URI, и вызывается `config get providers.p.base_url`
- **THEN** stdout содержит `<redacted>` вместо значения, код `0`

#### Scenario: Непрозрачные поддеревья
- **WHEN** файл содержит `providers.p.auth: {client_secret: s-1}` и `providers.p.key_rotation: {keys: [k-1]}`, и вызывается `config get providers.p`
- **THEN** оба поддерева выведены как `<opaque: edit the file>`, вывод не содержит `s-1` и `k-1`

#### Scenario: unset удаляет запрещённый ключ
- **WHEN** файл содержит `providers.openai.api_key: sk-1` (конфиг невалиден), и вызывается `config unset providers.openai.api_key`
- **THEN** ключ удалён, итог валиден, код `0`; stdout и stderr не содержат `sk-1`

#### Scenario: provider add с ключом из stdin
- **WHEN** `secrets.backend: file`, вызывается `provider add gw --kind openai-compatible --base-url https://x/v1 --model m --context-window 8192 --api-key-stdin --default`, ключ подаётся в stdin
- **THEN** `secrets.yaml` содержит `codelab/gw`, `config.yaml` — `api_key_secret: codelab/gw` и `agent.default_model: gw/m`, а ни один файл конфига и ни один вывод не содержат значения ключа (`cli_config_commands_test.dart`)

#### Scenario: provider add при бэкенде env
- **WHEN** `secrets.backend` не задан (`auto` = `env`), вызывается `provider add … --api-key-stdin`
- **THEN** код `1`, подсказка `secrets.backend: file` или переменной `CODELAB_SECRET_CODELAB_GW`; ключ не запрашивается, `config.yaml` не изменён

#### Scenario: provider remove со ссылкой
- **WHEN** `agent.default_model: gw/m`, вызывается `provider remove gw`
- **THEN** код `1`, проблема `agent.default_model` и строка `change the model first: config set agent.default_model <provider>/<model>` в stderr, файл не изменён

#### Scenario: get без --layer читает итог
- **WHEN** `budget.max_steps: 10` в `config.yaml`, `budget.max_steps: 20` в `.codelab/config.yaml` проекта, и вызывается `config get budget.max_steps --cwd <project>`
- **THEN** код `0`, stdout — `20` и `layer: project`

#### Scenario: get отсутствующего ключа
- **WHEN** ключ `budget.max_steps` не задан ни в одном слое, и вызывается `config get budget.max_steps`
- **THEN** код `1`, stdout пуст

#### Scenario: config unset отсутствующего ключа
- **WHEN** `config.yaml` не содержит `budget.max_steps`, и вызывается `config unset budget.max_steps`
- **THEN** код `0`, stdout — `budget.max_steps is not set in <home>/config.yaml`, файл не изменён

#### Scenario: provider remove отсутствующего провайдера
- **WHEN** `config.yaml` не содержит `providers.gw`, и вызывается `provider remove gw`
- **THEN** код `0`, stdout — `providers.gw is not set in <home>/config.yaml`, файл не изменён

#### Scenario: mcp remove отсутствующего сервера
- **WHEN** `config.yaml` не содержит сервера `github`, и вызывается `mcp remove github`
- **THEN** код `0`, stdout — `mcp.servers[github] is not set in <home>/config.yaml`, файл не изменён

#### Scenario: unset ключа со значением null
- **WHEN** `config.yaml` содержит `budget:` с вложенным `max_steps:` без значения, и вызывается `config unset budget.max_steps`
- **THEN** код `0`, stdout — `Removed budget.max_steps from <home>/config.yaml`, строки `max_steps:` в файле нет

#### Scenario: Флаг ключа заменяет источник ключа
- **WHEN** `secrets.backend: file`, `config.yaml` содержит `providers.gw` с `api_key_env: GW_KEY`, и вызывается `provider add gw --kind openai-compatible --model m --context-window 8192 --api-key-stdin` с ключом в stdin
- **THEN** код `0`, `providers.gw` содержит `api_key_secret: codelab/gw` и не содержит `api_key_env`

#### Scenario: provider add без обязательных флагов
- **WHEN** вызывается `provider add gw` без `--kind`, `--model` и `--context-window`
- **THEN** код `64`, одна строка stderr называет `--kind`, `--model` и `--context-window`; файлы не изменены

#### Scenario: mcp remove не ищет по номеру
- **WHEN** `mcp.servers` содержит один сервер `github`, и вызывается `mcp remove 0`
- **THEN** код `0`, stdout — `mcp.servers[0] is not set in <home>/config.yaml`, сервер `github` на месте, файл не изменён

#### Scenario: Недопустимое имя в mcp remove
- **WHEN** вызывается `mcp remove "my server"`
- **THEN** код `64`, файл не изменён

#### Scenario: provider add обновляет провайдера
- **WHEN** `config.yaml` содержит `providers.gw` с `base_url: https://x/v1` и `api_key_secret: codelab/gw`, хранилище `file` уже содержит секрет `codelab/gw`, и вызывается `provider add gw --kind openai-compatible --model m --context-window 8192 --api-key-stdin` с новым ключом в stdin
- **THEN** код `0`, секрет `codelab/gw` заменён новым значением, `base_url` сохранён; stdout содержит `warning: replaced the existing secret codelab/gw` и `Updated providers.gw in <home>/config.yaml`, ни старого, ни нового значения ключа в выводе нет

#### Scenario: Недопустимое имя MCP-сервера
- **WHEN** вызывается `mcp add "my server" --type http --url https://h`
- **THEN** код `64`, файл не изменён

#### Scenario: Ошибка разбора аргументов не цитирует argv
- **WHEN** вызывается `provider add gw --api-key sk-1`
- **THEN** код `64`, stderr содержит `invalid arguments for provider` и справку, не содержит `sk-1`

#### Scenario: Ошибка разбора аргументов config set не цитирует argv
- **WHEN** вызывается `config set budget.max_steps --sk-1`
- **THEN** код `64`, stderr содержит `invalid arguments for config set` и справку, не содержит `sk-1`

#### Scenario: mcp add с литеральным токеном
- **WHEN** вызывается `mcp add github --type http --url https://h --header Authorization="Bearer ghp_x"`
- **THEN** код `1`, stderr подсказывает `${secret:codelab/mcp/github/authorization}` и `codelab secret set codelab/mcp/github/authorization`, не содержит `ghp_x`; файл не изменён

#### Scenario: Неизвестный ключ set
- **WHEN** вызывается `config set budget.max_stepz 10`
- **THEN** код `64`, stderr подсказывает `budget.max_steps`, файл не изменён

## ADDED Requirements

### Requirement: Литеральные секреты в файле конфига
Публичные функции ядра (`config/inline_secrets.dart`; design.md change `add-config-literal-secrets-and-migrate`, D3) SHALL быть одним источником находок для загрузки, писателя, маскирования и `secret migrate`:
- `literalSecretTag(value)` — тег первого совпадения шаблонов §12.4 (`sk-…`, GitHub, AWS, Google, Slack, JWT, Bearer, PEM, присваивание секрета, URL с паролем) в **литеральных частях** значения (между подстановками `${…}`), с учётом встроенного белого списка `git_sha`, `uuid`, или `null`;
- `findInlineSecrets(ConfigTree)` — список `InlineSecretFinding {keyPath, kind, tag, suggestedSecretName, spans}` для пунктов 1–3 CFG-9.

Ни тег, ни находка НЕ SHALL содержать значение или его часть. Выражения с `(?i)` SHALL компилироваться с `caseSensitive: false`; части имени шаблона «присваивание секрета» SHALL быть ограничены 64 символами. Значение с URL-авторитетом, чей пароль userinfo не состоит целиком из одной подстановки `${…}`, SHALL давать находку `connection-string`, в том числе если подстановка разрезает пароль (`postgres://u:lit${X}@h/db`).

Находка в файловом слое (`user`, `project`, `projectLocal`, `CODELAB_CONFIG`/`--config`) SHALL давать предупреждение `config.secret.in_file {key, source}` с файлом, строкой и столбцом и текстом по одному шаблону `<key>: a secret is stored in the config file; move it to the secret store: <command>`, где `<command>`:
- `codelab secret migrate` — для слоя `user`;
- `codelab secret migrate --project` / `--local` — для проектных слоёв;
- `codelab secret set <suggestedSecretName>` — для `CODELAB_CONFIG`/`--config`.

Загрузка НЕ SHALL прерываться (R8-4; D4). Находки SHALL считаться по слою независимо от `enabled` элемента. `config check` SHALL печатать его строкой `warning:` без изменения кода выхода. Что применяется:
- литеральные части `providers.*.headers.*`, `mcp.servers[*].headers.*`, `mcp.servers[*].env.*` (п. 2, R1-1) — применяются как есть;
- `api_key_env`, `api_key_secret` или имя в `${secret:<name>}`, совпавшие с шаблоном (п. 3), — проблемы формата имени НЕ SHALL быть; значение SHALL попадать в `CoreConfig` маркером `UnusableKeyRef`, а не ссылкой. Маркер НЕ SHALL участвовать в поиске в хранилище в `config check`, в `config.provider.key_missing`, `providerProblems` и `secrets.lookup`. Такая ссылка НЕ SHALL разрешаться: ход провайдера SHALL завершаться ошибкой `auth` без HTTP-запроса с текстом `API key reference providers.<id>.<key> looks like a secret value, not a name; run: codelab secret migrate`, а MCP-сервер — состоянием `failed` с тем же текстом для своего ключа; значение НЕ SHALL попадать ни в текст, ни в `secrets.lookup`.

Для ключей недоверенного проектного слоя, которые правило доверия §15.3 отбрасывает (`providers.*`, `mcp.servers`), предупреждения `config.secret.in_file` НЕ SHALL быть: остаётся `config.project.untrusted_key`. Предконфигурация из окружения этим требованием не меняется. `url` и `base_url` на пароль в userinfo НЕ SHALL проверяться (`config get` печатает их без userinfo, R4-5).

`ConfigWriter` SHALL применять `literalSecretTag` к изменённым значениям `headers` и `env` и к элементам `mcp.servers[*].args` (R4-6, OQ3) и отклонять запись `ConfigInlineSecretException` (R8-5); у элемента `args` подсказка SHALL называть `--env <NAME>='${secret:<suggestedSecretName>}'`. Прежний литерал файла SHALL переходить в предупреждения записи. Загрузка элементы `args` НЕ SHALL проверять.

Дескриптор `providers.*.api_key` реестра настроек SHALL быть `fileOnly` с признаком `secret: true` (тест полноты CFG-19). `provider add` с любым из `--api-key-stdin`, `--api-key-secret`, `--api-key-env` SHALL удалять и литеральный `api_key` той же правкой (R4-4). `provider list` SHALL показывать источник ключа `key: literal in config file` без значения.

#### Scenario: Литерал в файле CODELAB_CONFIG
- **WHEN** файл `CODELAB_CONFIG` задаёт `providers.p.api_key: sk-<30 символов>`
- **THEN** предупреждение с текстом `providers.p.api_key: a secret is stored in the config file; move it to the secret store: codelab secret set codelab/p`

#### Scenario: Выключенный сервер
- **WHEN** сервер `gh` с `enabled: false` содержит литеральный заголовок по шаблону
- **THEN** предупреждение `config.secret.in_file` есть

#### Scenario: config get не печатает литеральный ключ
- **WHEN** файл задаёт `providers.p.api_key: sk-<30 символов>` и `providers.q.api_key_env: ghp_<36 символов>`, выполняются `codelab config get providers` и `codelab provider list`
- **THEN** оба листа выведены как `<redacted>`, `provider list` показывает `key: literal in config file` у `p`; ни одно значение не напечатано

#### Scenario: Смешанное значение заголовка
- **WHEN** пользовательский `config.yaml` задаёт у MCP-сервера `gh` заголовок `Authorization: "Bearer ghp_<36 символов> ${X}"`
- **THEN** загрузка успешна с предупреждением `mcp.servers[gh].headers.Authorization: a secret is stored in the config file; move it to the secret store: codelab secret migrate` без `ghp_`; заголовок применяется

#### Scenario: Ссылка рядом с префиксом схемы
- **WHEN** заголовок `Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`
- **THEN** предупреждений нет

#### Scenario: Токен вместо имени переменной
- **WHEN** провайдер `p` задаёт `api_key_env: ghp_<36 символов>`, и сессия делает ход с его моделью
- **THEN** загрузка успешна с предупреждением; ход завершается ошибкой `auth` `API key reference providers.p.api_key_env looks like a secret value, not a name; run: codelab secret migrate` без HTTP-запроса; ни текст, ни лог не содержат значения

#### Scenario: DSN, разрезанный подстановкой
- **WHEN** сервер `db` задаёт `env.DATABASE_URL: "postgres://app:pw-lit${SUFFIX}@localhost/db"`, а `db2` — `env.DATABASE_URL: "postgres://app:${PW}@localhost/db"`
- **THEN** предупреждение только у `mcp.servers[db].env.DATABASE_URL`, без `pw-lit` в тексте

#### Scenario: Недоверенный проект
- **WHEN** проект вне `trusted_projects` задаёт в `.codelab/config.yaml` `providers.p.api_key: sk-<30 символов>`
- **THEN** загрузка успешна, есть `config.project.untrusted_key` для `providers`, предупреждения `config.secret.in_file` нет

#### Scenario: Литеральный токен в args через mcp add
- **WHEN** `codelab-agent mcp add gh --type stdio --command gh-mcp --arg --token --arg ghp_<36 символов>`
- **THEN** код `1`, файл не тронут, stderr называет `--env` и `${secret:…}` и не содержит значения

### Requirement: Маскирование args MCP-серверов в выводе
Маскер `config get` и `provider list` SHALL прогонять через `literalSecretTag` все листья, включая листья, описанные реестром, и значения с `${…}`; лист с находкой SHALL печататься `<redacted>`, даже если это лист реестра (`api_key`, `api_key_env`, `api_key_secret`). `config get` SHALL маскировать элементы `mcp.servers[*].args` (R4-6; design.md change `add-config-literal-secrets-and-migrate`, D5):
- элемент с `literalSecretTag != null` → `<redacted>`;
- элемент после флага, чьё имя без ведущих `-` секретное по нормализованному правилу имён, → `<redacted>`;
- `--<секретное имя>=<значение>` → `--<имя>=<redacted>`;
- элемент со ссылкой `${…}` — как есть.

Маскирование SHALL действовать при любом `--layer`.

#### Scenario: Токены в args ручной правки
- **WHEN** файл задаёт `args: ["--token", "plain-value-1", "--api-key=plain-value-2", "--verbose", "ghp_<36 символов>", "${TOKEN}"]`, и выполняется `codelab config get mcp.servers`
- **THEN** вывод содержит `"--token"`, `"<redacted>"`, `"--api-key=<redacted>"`, `"--verbose"`, `"<redacted>"`, `"${TOKEN}"` и не содержит ни одного из трёх значений; код `0`; вывод `codelab-agent config get` совпадает байт в байт

### Requirement: Значение заголовка или переменной mcp add из stdin
`mcp add` (`McpServerCommands`, оба бинаря) SHALL принимать флаги `--header-stdin <Name>` с необязательным `--header-scheme <Scheme>` и `--env-stdin <NAME>` (R8-5; design.md change `add-config-literal-secrets-and-migrate`, D11):
- значение SHALL читаться из stdin через `SecretInput`, как у `secret set` и `provider add --api-key-stdin` (с TTY — скрытый ввод, без TTY — поток без одного завершающего перевода строки); пустое, многострочное или не UTF-8 значение — ошибка значения с кодом `64`;
- значение SHALL сохраняться в хранилище секретов под `SecretNames.forMcp(<server>, <Name|NAME>)` (`codelab/mcp/<server>/<key>`), а в файл SHALL записываться `headers.<Name>: "${secret:<имя>}"` (с `--header-scheme S` — `"S ${secret:<имя>}"`) или `env.<NAME>: "${secret:<имя>}"`;
- на вызов допускается ровно один флаг `--header-stdin` или `--env-stdin`; два и больше — код `64` с `only one of --header-stdin, --env-stdin can be used per call`; `--header-scheme` без `--header-stdin` и флаг `-stdin` с именем, уже заданным в `--header`/`--env` того же вызова, — код `64`;
- порядок — как у `provider add --api-key-stdin`: кандидат конфига без записи, `SecretAdmin.checkStore`, чтение stdin, сохранение секрета, одна атомарная запись; бэкенд только для чтения — код `1`, stdin не читается, подсказка `secrets.backend: file` или переменной `CODELAB_SECRET_<…>`; существующий секрет заменяется со строкой `warning: replaced the existing secret <имя>`; сбой записи конфига после сохранения — код `1`, stderr называет сохранённое имя;
- имя в `--header-stdin`/`--env-stdin` с `literalSecretTag(Name) != null` — код `64`, имя не печатается; совпадение имени с `--header` того же вызова SHALL проверяться без учёта регистра;
- до чтения stdin, кодом `1`: целевое имя секрета упомянуто в загруженном конфиге другим сервером или провайдером, или `forMcp` другого сервера конфига даёт то же имя (`GH`/`gh`, `my server`/`my-server`) — текст называет ключ, который уже использует имя, и предлагает `codelab secret set <другое имя>`;
- значение НЕ SHALL попадать в stdout, stderr, лог и argv; `--header Name='${…}'` и `--env K='${…}'` SHALL работать как прежде.

#### Scenario: Токен заголовка из stdin
- **WHEN** `secrets.backend: file`, вызывается `codelab-agent mcp add gh --type http --url https://h --header-stdin Authorization --header-scheme Bearer`, в stdin — `ghp-test-value-1\n`
- **THEN** код `0`; хранилище содержит `codelab/mcp/gh/authorization` со значением `ghp-test-value-1`; файл содержит `Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`; ни stdout, ни stderr не содержат значения

#### Scenario: Два флага stdin
- **WHEN** вызывается `mcp add gh --type stdio --command x --env-stdin A --env-stdin B`
- **THEN** код `64`, stdin не читается, файл и хранилище не изменены

#### Scenario: Бэкенд env
- **WHEN** `secrets.backend` не задан, вызывается `mcp add gh --type stdio --command x --env-stdin GITHUB_TOKEN`
- **THEN** код `1`, подсказка `secrets.backend: file` или `CODELAB_SECRET_CODELAB_MCP_GH_GITHUB_TOKEN`; stdin не читается; файл не изменён

#### Scenario: Имя секрета занято другим сервером
- **WHEN** конфиг содержит сервер `GH` со ссылкой `${secret:codelab/mcp/gh/authorization}`, вызывается `mcp add gh --type http --url https://h --header-stdin Authorization`
- **THEN** код `1`, stdin не читается, stderr называет `mcp.servers[GH].headers.Authorization`; файл и хранилище не изменены
