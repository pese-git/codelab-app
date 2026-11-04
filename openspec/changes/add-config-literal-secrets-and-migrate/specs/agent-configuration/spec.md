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
Запись конфигурации (`ConfigWriter`, подкоманды CLI, страницы настроек клиентов) НЕ SHALL сохранять секрет значением (CFG-2; design.md change `add-config-literal-secrets-and-migrate`, D5). Литеральный секрет в **файле** конфига SHALL давать предупреждение, а не проблему (решение пользователя 2026-11-04 R8-4; требование «Литеральные секреты в файле конфига»): ключи `api_key`, `apiKey`, `token`, `secret`, `password` в `providers.*` и в элементах `mcp.servers` файловых слоёв SHALL давать предупреждение `config.secret.in_file` с путём ключа и текстом по шаблону `<key>: a secret is stored in the config file; move it to the secret store: <command>` требования «Литеральные секреты в файле конфига». Литеральный `providers.<id>.api_key` SHALL использоваться как ключ провайдера; значение `api_key` из одной подстановки `${VAR}` или `${secret:x}` SHALL быть ссылкой, а не литералом (R8-8): раскрывается как в заголовках, предупреждения не даёт, `secret migrate` его не трогает. Литерал `api_key` с управляющими или не-ASCII символами SHALL быть проблемой загрузки `value` с текстом `api_key must be printable ASCII`, литерал секретно названного заголовка провайдера — `<Header> must be printable ASCII`, смесь литерала и `${secret:…}` в `api_key` — `api_key may use ${secret:…} only as the whole value`; значение в тексты НЕ SHALL попадать; остальные из этих ключей НЕ SHALL применяться. **R8-6:** `api_key` вместе с `api_key_env` или `api_key_secret` у одного провайдера после слияния слоёв SHALL быть проблемой загрузки `value` с ключом `providers.<id>.api_key` и текстом `api_key, api_key_env and api_key_secret are mutually exclusive` — это конфликт источников, а не «секрет в файле». Проблема `inlineSecret` и `ConfigInlineSecretException` SHALL оставаться у писателя и у предконфигурации из окружения (требование «Предконфигурация провайдера из окружения»), включая файл флага `--provider-config @путь`: это значение флага, а не слой конфига. Текст проблемы `inlineSecret` НЕ SHALL содержать значение и SHALL называть команду `codelab secret set <suggestedSecretName>` (`SecretNames.suggestFor(путь)`, capability `agent-secrets`, «Имена секретов»):
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
- **`provider list`** SHALL первой строкой печатать `Secrets: <backend>`, затем по строке на провайдера итогового конфига `<id>  kind: …  base_url: …  models: a, b  key: <source>` (без `base_url` — `(default)`); источник ключа без значения (`secret <name>: found|not set|unavailable`, `env <VAR>: set|not set`, `literal in config file`; у `api_key: ${VAR}` — `env <VAR>: set|not set`, у `api_key: ${secret:x}` — `secret x: found|not set|unavailable`; у ссылки-значения п. 3 — `unusable reference (looks like a secret value)` без поиска в хранилище).
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

### Requirement: Запись конфига ConfigWriter
Программная запись конфигурации SHALL выполняться только `ConfigWriter` (`codelab_agent_io/lib/src/config/config_writer.dart`) над правками ядра `ConfigEdit` (`SetValue`, `UnsetValue`, `UpsertMcpServer`, `RemoveMcpServer`, `RemoveTable`) и целью `ConfigTarget` (`user`, `project`, `projectLocal`). Алгоритм — `agent-core-architecture` §17.5.5 с уточнениями design.md, D5. `ConfigWriter.apply(base, edits)` SHALL:
- **Реестр.** Отклонять `SetValue` и `UpsertMcpServer` с ключом вне `SettingsRegistry` и ключ, чей дескриптор не разрешает слой цели. `UnsetValue` SHALL принимать и ключ вне реестра, если он есть в файле.
- **Доверие.** Отклонять правку проектного слоя, которую правило доверия §15.3 проигнорировало бы. Текст SHALL подсказывать `--local` или `trusted_projects`. Доверие SHALL проверяться только при записи в проектный слой (`project`, `projectLocal`).
- **Секреты.** Отклонять `ConfigInlineSecretException` (с `suggestedSecretName`):
  - значение-секрет по правилу CFG-9, п. 1;
  - по итоговому поддереву документа после всех правок на любой глубине, независимо от типа правки (`SetValue`, `UpsertMcpServer`) и от того, записан лист или значение-отображение целиком: каждое изменённое значение в `providers.*.headers`, `mcp.servers[*].headers`, `mcp.servers[*].env`, `exec.env`, чьё имя после нормализации (нижний регистр, без `-` и `_`) содержит `token`, `secret`, `password`, `apikey`, `auth`, `cookie`, `key` или `privatetoken`, — если в значении нет ни `${secret:…}`, ни `${VAR}`;
  - в поддеревьях непрозрачных узлов схемы (`providers.*.auth`, `providers.*.key_rotation`, `tools.web`, `llm`, `hooks` и прочие разделы после MVP) — по тому же нормализованному правилу имён для любого листа;
  - лист с именем из `inlineSecretKeys` на любой глубине; имя SHALL сравниваться после той же нормализации (`API_KEY`, `Api-Key` — как `api_key`);
  - нестроковый скаляр (число, `bool`) под секретным именем SHALL считаться литералом;
  - изменённость элемента `mcp.servers` SHALL определяться по его номеру в списке, а не по `name`: при дублях `name` каждый элемент проверяется сам.
- **Блокировка и отпечаток.** Брать эксклюзивный `<path>.lock` с содержимым `<pid> <nonce>`. Lock старше порога устаревания (10 с) снимается через `rename` в уникальное имя с повторной проверкой возраста и содержимого и `config.write.stale_lock`; свежий lock другого писателя возвращается на место, а запись получает `ConfigConflictException`. Занятый lock или отпечаток sha256 файла, отличный от `base.fingerprint`, дают `ConfigConflictException`. Брошенные `<path>.tmp-*` SHALL удаляться только после взятия lock. Таймаут смены прав (`chmod`, 5 s) SHALL быть строго меньше порога устаревания lock (10 s). Непосредственно перед `rename` писатель SHALL перечитывать свой lock (в нём его nonce) и отпечаток цели (совпадает с прочитанным под lock); иначе — `ConfigConflictException`, tmp удаляется, цель и чужой lock не трогаются.
- **Правка.** Применять правки к байтам файла через `YamlEditor` (`package:yaml_edit`). Комментарии, пустые строки, порядок ключей, flow-стиль и перевод строк (LF/CRLF) вне изменённых узлов SHALL сохраняться побайтово. Новый ключ SHALL вставляться по правилу `YamlEditor` (R3-2): в отображение, ключи которого отсортированы по алфавиту, — на своё место по алфавиту, иначе — в конец отображения; новый элемент списка (`mcp.servers`) — в конец списка; недостающие предки — в блочном стиле с отступом файла. Известная граница: при вставке по алфавиту комментарий над следующим ключом оказывается над новым ключом; байты комментария сохраняются. Строку, которая содержит `${`, SHALL писать в одинарных кавычках без экранирования `/` (`'Bearer ${secret:codelab/mcp/gh/x}'`): в двойных `yaml_edit` экранирует `/` как `\/`, и файл становится нечитаемым (design.md change `add-config-literal-secrets-and-migrate`, D5). Прочую строку, которая по профилю §15.5 прочиталась бы не строкой (`off`, `yes`), SHALL писать в двойных кавычках. Строку с управляющим символом (в том числе `\n`) SHALL писать в двойных кавычках: одинарные его не выражают. Отказ `YamlEditor` SHALL давать `ConfigException` с `cannot edit <key> automatically; edit the file manually`.
- **Проверка.** Проверять итог `ConfigLoader.validateCandidate` по всем слоям с заменой целевого. Незаданная `${VAR}` — предупреждение результата, а не ошибка. Незаданную `${VAR}` писатель SHALL узнавать по структурному признаку проблемы ядра, а не по тексту сообщения. Итог кандидата и исходный текст слоя проверять тем же методом в режиме полной проверки без обрыва ступеней (R3-3); если полную проверку кандидата не удалось довести до конца (вырезан предок вместо точного пути или весь слой, нет прогресса, исчерпан лимит кругов; правило доверия SHALL вычисляться по исходным слоям до вырезания), проверка SHALL давать служебную проблему `config.validation.incomplete`, и запись SHALL отклоняться (fail-closed), даже если такая проблема была и в базе; неполнота одной базы запись НЕ SHALL блокировать: база сравнения SHALL содержать проблемы всех ступеней, включая каскадные, а не только ступени, на которой оборвалась бы обычная загрузка; сравнивать проблемы до и после правки по сигнатуре `kind|key|source`, без значений и без позиции `line:column` (R3-1); сравнение SHALL учитывать число проблем каждой сигнатуры, поэтому проблемы с пустым ключом НЕ SHALL схлопываться в одну: проблема, которой не было до правки, SHALL давать `ConfigException` с новыми проблемами без записи; проблема, которая была и до правки, SHALL возвращаться в `ConfigWriteResult.warnings`, а запись — выполняться. Литеральный секрет, вносимый правкой, ключ вне реестра, слой, не разрешённый дескриптором, и ключ, отброшенный правилом доверия, SHALL отклоняться всегда, независимо от сравнения. Правка SHALL блокироваться, только если в кандидате есть проблема, которой нет в полном наборе базы; поэтому проблема поздней ступени, открывшаяся после исправления ранней ошибки, НЕ SHALL считаться новой. Обычная загрузка (`config check`, `serve`, перезагрузка) по поведению НЕ SHALL меняться: она по-прежнему останавливается на первой провалившейся ступени.
- **Замена.** Эксклюзивно создавать пустой `<path>.tmp-<pid>-<rand>` в каталоге цели, выставлять на него права исходного файла (кроме Windows) через `SecretProcessRunner` **до** записи содержимого, затем писать, сбрасывать на диск и атомарно переименовывать поверх цели. Сбой смены прав SHALL давать `ConfigException`, удалять tmp и не выполнять `rename`. Символическую ссылку SHALL раскрывать: правится цель, ссылка остаётся. Для слоя `user` ссылка MAY вести куда угодно (dotfiles). Для слоёв `project` и `projectLocal` раскрытая цель (и каталог `.codelab`, если он ссылка) SHALL лежать внутри канонического `<cwd>/.codelab`; иначе — `ConfigException` до взятия lock и до создания каталогов. Больше 32 переходов по ссылкам — `ConfigException` `too many symbolic links`. Каталог `$CODELAB_HOME`, созданный писателем, SHALL получать права `0700` (кроме Windows).
- **Итог.** Писать лог `config.write {path, keys}` и возвращать `ConfigWriteResult {path, fingerprint, warnings, restartRequiredKeys}`.

При любой ошибке файл НЕ SHALL меняться, tmp и lock SHALL удаляться (CFG-13). Значения ключей НЕ SHALL попадать в лог и тексты ошибок. TOML писатель НЕ SHALL писать никогда.

#### Scenario: Сохранение формата
- **WHEN** файл содержит комментарий над `agent:`, хвостовой комментарий у `default_model`, flow-список `fallback: [a/b]` и переводы строк CRLF, и применяется `SetValue("agent.default_model", "anthropic/claude-sonnet-4")`
- **THEN** изменилась только строка `default_model`, её хвостовой комментарий на месте, остальные байты файла совпадают с исходными (`config_writer_test.dart`)

#### Scenario: Ключ модели с точкой
- **WHEN** применяется `SetValue` ключа `providers.local.models."qwen2.5-coder-32b".context_window`
- **THEN** в YAML появляется один ключ `qwen2.5-coder-32b`, а загрузка возвращает модель `local/qwen2.5-coder-32b` с этим окном

#### Scenario: Удаление таблицы провайдера
- **WHEN** применяется `RemoveTable("providers.local")`, а под ним есть модели и комментарии
- **THEN** поддерево и комментарии внутри удалены, комментарий над следующим ключом сохранён; `RemoveTable` несуществующего ключа — `ConfigException`

#### Scenario: Сервер MCP по имени
- **WHEN** применяется `UpsertMcpServer` с `name: github` при существующем элементе `github` и `UpsertMcpServer` с `name: docs` без него
- **THEN** элемент `github` изменён на месте, `docs` добавлен в конец списка `mcp.servers`

#### Scenario: Конфликт с ручной правкой
- **WHEN** файл изменён другим процессом между `read` и `apply`
- **THEN** `apply` бросает `ConfigConflictException`, содержимое файла — правка другого процесса

#### Scenario: Невалидный итог не пишется
- **WHEN** конфиг без проблем загрузки, и применяется `SetValue("budget.max_steps", 0)`
- **THEN** `ConfigException` с новой проблемой `budget.max_steps`, байты файла не изменены, tmp и lock отсутствуют

#### Scenario: Первая запись в пустой конфиг
- **WHEN** `$CODELAB_HOME` пуст, и применяется `SetValue("budget.max_steps", 40)` или правки `provider add` без `--default`
- **THEN** файл записан, `ConfigWriteResult.warnings` содержит проблему `agent.default_model` (`required`), исключения нет

#### Scenario: Правка не вносит новую ошибку
- **WHEN** `agent.default_model: gw/m`, провайдер `gw` — единственный, и применяется `RemoveTable("providers.gw")`
- **THEN** `ConfigException` с проблемой `agent.default_model`, файл не изменён; при этом прежняя проблема другого ключа, бывшая в файле до правки, отказа не вызывает и возвращается предупреждением

#### Scenario: Проблемы без ключа не схлопываются
- **WHEN** исходный текст слоя даёт одну проблему без ключа некоторого вида, а правка вносит ещё одну проблему того же вида без ключа в том же источнике
- **THEN** проблем с сигнатурой `kind||source` стало две вместо одной: лишняя считается новой, `ConfigException`, файл не изменён

#### Scenario: Прежняя ошибка ниже вставки — предупреждение
- **WHEN** в файле есть проблема ключа ниже места вставки (например, `budget.max_steps: 0`), и `SetValue` добавляет новый ключ выше неё, сдвигая её строку
- **THEN** сигнатура `kind|key|source` не изменилась: проблема возвращается в `ConfigWriteResult.warnings`, запись выполнена

#### Scenario: Ошибка ранней ступени
- **WHEN** файл содержит неизвестный ключ `bogus_key` и `budget.max_steps: 0`, и применяется `UnsetValue("bogus_key")`
- **THEN** запись выполнена, `bogus_key` удалён, проблема `budget.max_steps` возвращается в `ConfigWriteResult.warnings`: полная проверка исходного текста (R3-3) видит её в базе, хотя обычная загрузка исходного файла остановилась бы на `bogus_key`

#### Scenario: Ранняя ошибка скрывает поздние
- **GIVEN** `$CODELAB_HOME/config.yaml` с провайдером `lm`, в котором литеральный `api_key: sk-fake-1` и `base_url: "https://u:p@ss@host/v1"`, и `agent.default_model`, ссылающимся на модель `lm`; `codelab-agent config check` сообщает одну проблему (литеральный секрет `providers.lm.api_key`)
- **WHEN** выполняется `codelab-agent config unset providers.lm.api_key`
- **THEN** код выхода `0`, stdout — `Removed providers.lm.api_key from <home>/config.yaml`, затем строки `warning:` для `providers.lm.base_url` и для `agent.default_model` (модели нет в каталоге) как прежних проблем базы
- **AND** ключа `api_key` в файле больше нет, остальные строки и комментарии не изменены
- **AND** строка `sk-fake-1` не встречается ни в stdout, ни в stderr, ни в логе

#### Scenario: Новая ошибка поздней ступени при ранней
- **WHEN** файл содержит неизвестный ключ `bogus_key` и корректный `budget.max_steps: 40`, и применяется `SetValue("budget.max_steps", 0)` (`codelab-agent config set budget.max_steps 0`)
- **THEN** `ConfigException` с новой проблемой `budget.max_steps` (CLI — код `1`), байты файла не изменены, tmp и lock отсутствуют: проблемы `budget.max_steps` нет в полном наборе базы, а прежняя проблема `bogus_key` новой не считается

#### Scenario: Порча слоя не отключает правило доверия
- **WHEN** проектный слой недоверенного проекта содержит испорченные элементы `mcp.servers` (имя не строкой, ключ с кавычкой, больше восьми дубликатов имени), и в этот слой применяется `SetValue("permissions.mode", "bypass")`
- **THEN** запись отклоняется: либо проблемой правила доверия `trusted_projects`, либо служебной `config.validation.incomplete`; байты файла не изменены

#### Scenario: Неполная проверка базы не мешает удалить порчу
- **WHEN** полная проверка исходного слоя неполна, а правка удаляет испорченный элемент, и кандидат проверяется полностью
- **THEN** запись проходит

#### Scenario: Порядок нового ключа
- **WHEN** `SetValue` добавляет новый ключ в отображение с ключами `a`, `c` (по алфавиту) и в отображение с ключами `c`, `a`
- **THEN** в первом новый ключ `b` встаёт между `a` и `c`, во втором — в конец; комментарии и остальные строки не изменены
- **AND** если над `c` в первом отображении стоит комментарий `# про c`, он оказывается над новым ключом `b` (граница `YamlEditor`, design.md D5), а его байты не меняются

#### Scenario: Недоверенный проект
- **WHEN** проект не в `trusted_projects`, и применяется `UpsertMcpServer` к слою `project`
- **THEN** `ConfigException` с подсказкой `--local` или `trusted_projects`, файл не создан; `SetValue("trusted_projects", …)` в слой `project` — отказ по слоям ключа

#### Scenario: Литеральный токен MCP
- **WHEN** `UpsertMcpServer` задаёт заголовок `Authorization: "Bearer ghp_abc"` серверу `github`
- **THEN** `ConfigInlineSecretException` с `suggestedSecretName` `codelab/mcp/github/authorization`, текст не содержит `ghp_abc`, файл не изменён

#### Scenario: Литеральный токен через config set
- **WHEN** применяется `SetValue("mcp.servers", [{"name":"gh","type":"http","url":"https://h","headers":{"X-Api-Key":"k-1"}}])` или `SetValue("providers.p.headers", {"Cookie":"s=1"})`
- **THEN** `ConfigInlineSecretException`, текст не содержит `k-1` и `s=1`, файл не изменён

#### Scenario: Литеральный секрет во вложенном значении
- **WHEN** применяется `SetValue("exec", {"env":{"GITHUB_TOKEN":"ghp_x"}})` или `SetValue` значения-отображения с вложенным листом `token: "t-1"`
- **THEN** `ConfigInlineSecretException`, текст не содержит `ghp_x` и `t-1`, файл не изменён

#### Scenario: Литеральный секрет в непрозрачном поддереве
- **WHEN** правка записывает в `providers.p.auth` лист `client_secret: "cs-1"`, или лист `API_KEY: "k-2"` на любой глубине, или `token: 123456` (число)
- **THEN** каждая правка даёт `ConfigInlineSecretException`, текст не содержит значений, файл не изменён

#### Scenario: Дубли имени сервера MCP
- **WHEN** в `mcp.servers` уже есть элемент `name: gh` без заголовков, и правка добавляет второй элемент `name: gh` с заголовком `Authorization: "Bearer ghp_y"`
- **THEN** `ConfigInlineSecretException`: второй элемент сравнивается со своим прежним по номеру, а не с первым по `name`; файл не изменён

#### Scenario: Сбой смены прав
- **WHEN** фейковый `SecretProcessRunner` возвращает ненулевой код на `chmod` tmp
- **THEN** `ConfigException` с `cannot set permissions`, исходный файл не изменён, tmp удалён, содержимое в tmp не записывалось

#### Scenario: Сбой между tmp и переименованием
- **WHEN** запись прерывается после записи tmp и до `rename` (тестовый шов)
- **THEN** исходный файл цел, а следующая запись удаляет брошенный tmp (`config_writer_atomic_test.dart`)

#### Scenario: Символическая ссылка и права
- **WHEN** `$CODELAB_HOME/config.yaml` — символическая ссылка на файл с правами `0600`
- **THEN** после записи ссылка осталась ссылкой, изменена цель, права цели — `0600`

#### Scenario: Ссылка проектного слоя наружу
- **WHEN** `<cwd>/.codelab/config.local.yaml` — ссылка на `$CODELAB_HOME/config.yaml` (или `<cwd>/.codelab` — ссылка на каталог вне `<cwd>`), и применяется правка слоя `projectLocal`
- **THEN** `ConfigException` с путём, цель ссылки не изменена, lock, tmp и новые каталоги не созданы

#### Scenario: Цепочка ссылок и новый CODELAB_HOME
- **WHEN** путь цели проходит больше 32 символических ссылок (в том числе цикл), а в другом случае `$CODELAB_HOME` не существует
- **THEN** в первом случае `ConfigException` `too many symbolic links`, ничего не создано; во втором писатель создаёт `$CODELAB_HOME` с правами `0700` (кроме Windows) и записывает файл

#### Scenario: Lock снят во время записи
- **WHEN** после записи tmp и до `rename` (тестовый шов) lock писателя удалён или заменён lock другого писателя, либо файл цели изменён в обход lock
- **THEN** `ConfigConflictException`, правки писателя в цели нет (байты — исходные или чужой правки), tmp удалён, чужой lock на месте

#### Scenario: Брошенный tmp и занятый lock
- **WHEN** рядом с целью лежит `<path>.tmp-*` старше 10 с, а lock занят другим живым писателем
- **THEN** запись получает `ConfigConflictException`, и брошенный tmp этой записью не удаляется: чистка идёт только под lock

#### Scenario: Ссылка на секрет в одинарных кавычках
- **WHEN** применяется `UpsertMcpServer` stdio-сервера `gh` с `env.GH_TOKEN` = `Bearer ${secret:codelab/mcp/gh/x}` и `env.DEBUG` = строкой `off`
- **THEN** файл содержит `GH_TOKEN: 'Bearer ${secret:codelab/mcp/gh/x}'` без `\/` и `DEBUG: "off"`; загрузка возвращает те же строки

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
- `api_key_env`, `api_key_secret` или имя в `${secret:<name>}`, совпавшие с шаблоном (п. 3), — проблемы формата имени НЕ SHALL быть; значение SHALL попадать в `CoreConfig` маркером, а не ссылкой: `UnusableKeyRef` у ключа провайдера, `UnusableSecretReference` в шаблоне заголовка или `env`. Токен вместо имени переменной в `${…}` (`${ghp_…}`) SHALL давать ту же находку (`referenceName`): переменная не читается, тексты проблемы и предупреждения имени не содержат. Шаблон `sk-…` к именам п. 3 SHALL применяться только в начале значения. Маркер НЕ SHALL участвовать в поиске в хранилище в `config check`, в `config.provider.key_missing`, `providerProblems` и `secrets.lookup`. Такая ссылка НЕ SHALL разрешаться: ход провайдера SHALL завершаться ошибкой `auth` без HTTP-запроса с текстом `API key reference providers.<id>.<key> looks like a secret value, not a name; run: codelab secret migrate`, а MCP-сервер — состоянием `failed` с тем же текстом для своего ключа; значение НЕ SHALL попадать ни в текст, ни в `secrets.lookup`.

Для ключей недоверенного проектного слоя, которые правило доверия §15.3 отбрасывает (`providers.*`, `mcp.servers`), предупреждения `config.secret.in_file` НЕ SHALL быть: остаётся `config.project.untrusted_key`. Предконфигурация из окружения этим требованием не меняется. `url` и `base_url` на пароль в userinfo НЕ SHALL проверяться (`config get` печатает их без userinfo, R4-5).

`ConfigWriter` SHALL применять `literalSecretTag` к изменённым значениям `headers` и `env` и к элементам `mcp.servers[*].args` (R4-6, OQ3) и отклонять запись `ConfigInlineSecretException` (R8-5); у элемента `args` подсказка SHALL называть `--env <NAME>='${secret:<suggestedSecretName>}'`. Прежний литерал файла SHALL переходить в предупреждения записи. Загрузка элементы `args` НЕ SHALL проверять.

Дескриптор `providers.*.api_key` реестра настроек SHALL быть `fileOnly` с признаком `secret: true` (тест полноты CFG-19). `provider add` с любым из `--api-key-stdin`, `--api-key-secret`, `--api-key-env` SHALL удалять и литеральный `api_key` той же правкой (R4-4). `provider list` SHALL показывать источник ключа `key: literal in config file` без значения.

#### Scenario: Ссылка в api_key
- **WHEN** провайдер `p` задаёт `api_key: "${P_KEY}"` (переменная задана), а провайдер `q` — `api_key: "${secret:codelab/q}"`
- **THEN** предупреждений `config.secret.in_file` нет; `p` получает значение переменной, `q` — секрет через резолвер; `api_key: "${P_KEY}"` вместе с `api_key_env` — проблема R8-6

#### Scenario: Токен вместо имени переменной в подстановке
- **WHEN** заголовок сервера `gh` — `Authorization: "Bearer ${ghp_abcdefghijklmnopqrstuvwxyz0123456789}"`, а заголовок провайдера `p` — `X-Api-Key: "${ghp_abcdefghijklmnopqrstuvwxyz0123456789}"`
- **THEN** проблем загрузки нет, есть предупреждения `config.secret.in_file` для обоих ключей; в шаблонах — маркер `UnusableSecretReference`, окружение не читается; сервер `gh` — `failed`, ход провайдера `p` — ошибка `auth` без HTTP-запроса; ни текст, ни лог не содержат `ghp_`

#### Scenario: Смесь литерала и ссылки в api_key
- **WHEN** провайдер задаёт `api_key: "sk-lit ${secret:codelab/p}"`
- **THEN** проблема `value` с ключом `providers.<id>.api_key` и текстом `api_key may use ${secret:…} only as the whole value`, без значения

#### Scenario: Управляющий символ в заголовке провайдера
- **WHEN** литеральный `providers.p.headers.X-Api-Key` содержит символ табуляции
- **THEN** проблема `value` с текстом `X-Api-Key must be printable ASCII`, без значения; у MCP-сервера та же строка проблемы не даёт

#### Scenario: Токен в URL в выводе config get
- **WHEN** `providers.p.base_url: "https://h/v1/ghp_abcdefghijklmnopqrstuvwxyz0123456789?region=eu"`, выполняется `codelab config get providers.p.base_url`
- **THEN** выводится `<redacted>`, токена в выводе нет

#### Scenario: Имя секрета с sk- не в начале
- **WHEN** провайдер задаёт `api_key_secret: codelab/sk-test-provider-key-name`
- **THEN** находки нет, ссылка разрешается как обычное имя

#### Scenario: Управляющий символ в ключе
- **WHEN** `api_key` содержит символ табуляции
- **THEN** проблема `value` с ключом `providers.<id>.api_key`, текст без значения

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
Значения `url` и `base_url` в `config get` после удаления userinfo (R4-5) SHALL проверяться `hasInlineSecret`; находка (токен в пути или под несекретным именем query-параметра) SHALL давать `<redacted>`. Маскер `config get` и `provider list` SHALL прогонять через `literalSecretTag` все листья, включая листья, описанные реестром, и значения с `${…}`; лист с находкой SHALL печататься `<redacted>`, даже если это лист реестра (`api_key`, `api_key_env`, `api_key_secret`). `config get` SHALL маскировать элементы `mcp.servers[*].args` (R4-6; design.md change `add-config-literal-secrets-and-migrate`, D5):
- элемент с `literalSecretTag != null` → `<redacted>`;
- элемент после флага, чьё имя без ведущих `-` секретное по нормализованному правилу имён, → `<redacted>`;
- `--<секретное имя>=<значение>` → `--<имя>=<redacted>`;
- элемент, состоящий только из ссылок `${…}`, — как есть; литеральная часть рядом со ссылкой после секретного флага или в `--<секретное имя>=…` → `<redacted>` (fail closed);
- элемент-список или элемент-отображение (невалидный конфиг ручной правки) — маска целиком.

Маскирование SHALL действовать при любом `--layer`.

#### Scenario: Токены в args ручной правки
- **WHEN** файл задаёт `args: ["--token", "plain-value-1", "--api-key=plain-value-2", "--verbose", "ghp_<36 символов>", "${TOKEN}"]`, и выполняется `codelab config get mcp.servers`
- **THEN** вывод содержит `"--token"`, `"<redacted>"`, `"--api-key=<redacted>"`, `"--verbose"`, `"<redacted>"`, `"${TOKEN}"` и не содержит ни одного из трёх значений; код `0`; вывод `codelab-agent config get` совпадает байт в байт

### Requirement: Значение заголовка или переменной mcp add из stdin
`mcp add` (`McpServerCommands`, оба бинаря) SHALL принимать флаги `--header-stdin <Name>` с необязательным `--header-scheme <Scheme>` и `--env-stdin <NAME>` (R8-5; design.md change `add-config-literal-secrets-and-migrate`, D11):
- значение SHALL читаться из stdin через `SecretInput`, как у `secret set` и `provider add --api-key-stdin` (с TTY — скрытый ввод, без TTY — поток без одного завершающего перевода строки); пустое, многострочное или не UTF-8 значение — ошибка значения с кодом `64`;
- значение SHALL сохраняться в хранилище секретов под `SecretNames.forMcp(<server>, <Name|NAME>)` (`codelab/mcp/<server>/<key>`), а в файл SHALL записываться значение `${secret:<имя>}` в `headers.<Name>` (с `--header-scheme S` — `S ${secret:<имя>}`) или в `env.<NAME>`; строка со ссылкой SHALL записываться в YAML в одинарных кавычках без экранирования `/` (`'Bearer ${secret:codelab/mcp/gh/x}'`; design.md, D5);
- на вызов допускается ровно один флаг `--header-stdin` или `--env-stdin`; два и больше — код `64` с `only one of --header-stdin, --env-stdin can be used per call`;
- `--header-stdin` при `--type stdio` — код `64` с `mcp add: --header-stdin is for --type http`; `--env-stdin` при `--type http` — код `64` с `mcp add: --env-stdin is for --type stdio`;
- `--header-scheme` без `--header-stdin` — код `64` с `mcp add: --header-scheme requires --header-stdin`; схема SHALL быть token по RFC 9110 (непустая, только буквы, цифры и ``!#%&'*+.^_`|~-``; `$` и пробелы не допускаются), иначе код `64` с текстом ``mcp add: --header-scheme must be a token of letters, digits and !#%&'*+.^_`|~- (RFC 9110)``;
- флаг `-stdin` с именем, уже заданным в том же вызове, — код `64`: `mcp add: --header-stdin name is also set by --header` (имена заголовков сравниваются без учёта регистра), `mcp add: --env-stdin name is also set by --env` (имена переменных сравниваются с учётом регистра, как в POSIX);
- имя в `--header-stdin`/`--env-stdin` с `literalSecretTag(Name) != null` — код `64` с текстом `mcp add: <флаг> expects a header or variable name, not a secret value`; имя НЕ SHALL печататься;
- порядок: кандидат конфига без записи; проверка коллизии имени секрета (ниже); `SecretAdmin.checkStore`; чтение stdin; сохранение секрета; одна атомарная запись. Коллизия SHALL проверяться раньше хранилища. Бэкенд только для чтения — код `1`, stdin не читается, подсказка `secrets.backend: file` или переменной `CODELAB_SECRET_<…>`; существующий собственный секрет этого сервера заменяется со строкой `warning: replaced the existing secret <имя>`; сбой записи конфига после сохранения — код `1`, stderr `the secret <имя> was stored; the config was not changed: <причина>`;
- коллизия, до чтения stdin и до хранилища, кодом `1`: целевое имя секрета упомянуто в загруженном конфиге другим сервером или провайдером (`${secret:<имя>}` или `api_key_secret`), или `forMcp` другого сервера конфига даёт то же имя (`GH`/`gh`, `my server`/`my-server`). Текст: `secret <имя> is already used by <ключ>; store the value with codelab secret set <another name> and reference it with --header/--env`; `<ключ>` — путь ссылки (`mcp.servers[GH].headers.Authorization`), а при совпадении только по `forMcp` — элемент сервера (`mcp.servers[GH]`);
- значение НЕ SHALL попадать в stdout, stderr, лог и argv; `--header Name='${…}'` и `--env K='${…}'` SHALL работать как прежде.

#### Scenario: Токен заголовка из stdin
- **WHEN** `secrets.backend: file`, вызывается `codelab-agent mcp add gh --type http --url https://h --header-stdin Authorization --header-scheme Bearer`, в stdin — `ghp-test-value-1\n`
- **THEN** код `0`; хранилище содержит `codelab/mcp/gh/authorization` со значением `ghp-test-value-1`; файл содержит `Authorization: 'Bearer ${secret:codelab/mcp/gh/authorization}'`; ни stdout, ни stderr не содержат значения

#### Scenario: Два флага stdin
- **WHEN** вызывается `mcp add gh --type stdio --command x --env-stdin A --env-stdin B`
- **THEN** код `64`, stdin не читается, файл и хранилище не изменены

#### Scenario: Бэкенд env
- **WHEN** `secrets.backend` не задан, вызывается `mcp add gh --type stdio --command x --env-stdin GITHUB_TOKEN`
- **THEN** код `1`, подсказка `secrets.backend: file` или `CODELAB_SECRET_CODELAB_MCP_GH_GITHUB_TOKEN`; stdin не читается; файл не изменён

#### Scenario: Имя секрета занято другим сервером
- **WHEN** конфиг содержит сервер `GH` со ссылкой `${secret:codelab/mcp/gh/authorization}`, вызывается `mcp add gh --type http --url https://h --header-stdin Authorization`
- **THEN** код `1`, stdin не читается, stderr — `secret codelab/mcp/gh/authorization is already used by mcp.servers[GH].headers.Authorization; store the value with codelab secret set <another name> and reference it with --header/--env`; файл и хранилище не изменены

#### Scenario: Имя секрета совпало по forMcp
- **WHEN** конфиг содержит сервер `GH` без ссылок на секреты, `secrets.backend` не задан (`env`), вызывается `mcp add gh --type http --url https://h --header-stdin Authorization`
- **THEN** код `1`, stderr — `secret codelab/mcp/gh/authorization is already used by mcp.servers[GH]; …` без подсказки про `secrets.backend`; stdin не читается; файл не изменён

#### Scenario: Флаг stdin не для этого типа
- **WHEN** вызывается `mcp add gh --type stdio --command x --header-stdin Authorization` или `mcp add gh --type http --url https://h --env-stdin TOKEN`
- **THEN** код `64` с `mcp add: --header-stdin is for --type http` или `mcp add: --env-stdin is for --type stdio`; stdin не читается, файл и хранилище не изменены

#### Scenario: Имя stdin повторяет --header
- **WHEN** вызывается `mcp add gh --type http --url https://h --header 'authorization=${X}' --header-stdin Authorization`
- **THEN** код `64` с `mcp add: --header-stdin name is also set by --header`; stdin не читается

#### Scenario: Имя заголовка похоже на токен
- **WHEN** вызывается `mcp add gh --type http --url https://h --header-stdin ghp_<36 символов>`
- **THEN** код `64`, stderr содержит `expects a header or variable name, not a secret value` и не содержит `ghp_`; stdin не читается
