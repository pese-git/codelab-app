## MODIFIED Requirements

### Requirement: Секреты только ссылками
Запись конфигурации (`ConfigWriter`, подкоманды CLI, страницы настроек клиентов) НЕ SHALL сохранять секрет значением (CFG-2; design.md change `add-config-literal-secrets-and-migrate`, D5). Литеральный секрет в **файле** конфига SHALL давать предупреждение, а не проблему (решение пользователя 2026-11-04 R8-4; требование «Литеральные секреты в файле конфига»): ключи `api_key`, `apiKey`, `token`, `secret`, `password` в `providers.*` и в элементах `mcp.servers` файловых слоёв SHALL давать предупреждение `config.secret.in_file` с путём ключа и текстом по шаблону `<key>: a secret is stored in the config file; move it to the secret store: <command>` требования «Литеральные секреты в файле конфига». Литеральный `providers.<id>.api_key` SHALL использоваться как ключ провайдера; значение `api_key` из одной подстановки `${VAR}` или `${secret:x}` SHALL быть ссылкой, а не литералом (R8-8): раскрывается как в заголовках, предупреждения не даёт, `secret migrate` его не трогает. Литерал `api_key` с управляющими или не-ASCII символами SHALL быть проблемой загрузки `value` с текстом `api_key must be printable ASCII`, литерал секретно названного заголовка провайдера — `<Header> must be printable ASCII`, смесь литерала и `${secret:…}` в `api_key` — `api_key may use ${secret:…} only as the whole value`; значение в тексты НЕ SHALL попадать; остальные из этих ключей НЕ SHALL применяться. **R8-6:** `api_key` вместе с `api_key_env` или `api_key_secret` у одного провайдера после слияния слоёв SHALL быть проблемой загрузки `value`. Слияние учитывает правило группы провайдера (capability `agent-secrets`, «Ключ проектного провайдера привязан к адресу», design.md change `require-project-folder`, D23): поля аутентификации слоёв ниже проектного к нему не наследуются, поэтому пара источников возникает только между глобальными слоями (`user`, `appStorage`, `--config`/`CODELAB_CONFIG`, окружение) или внутри одного слоя. Проблема с ключом `providers.<id>.api_key` и текстом `api_key, api_key_env and api_key_secret are mutually exclusive` — это конфликт источников, а не «секрет в файле». Проблема `inlineSecret` и `ConfigInlineSecretException` SHALL оставаться у писателя и у предконфигурации из окружения (требование «Предконфигурация провайдера из окружения»), включая файл флага `--provider-config @путь`: это значение флага, а не слой конфига. Текст проблемы `inlineSecret` НЕ SHALL содержать значение и SHALL называть команду `codelab secret set <suggestedSecretName>` (`SecretNames.suggestFor(путь)`, capability `agent-secrets`, «Имена секретов»):
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
- **WHEN** пользовательский слой задаёт `providers.openai.api_key: sk-x…`, а файл `--config` (или `CODELAB_CONFIG`) — `providers.openai.api_key_secret: codelab/openai`
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

#### Scenario: Ключ проектного слоя не образует пары с ключом пользователя
- **WHEN** пользовательский слой задаёт провайдера `openai` с литеральным `api_key: sk-x…`, а `config.local.yaml` доверенного проекта — только `providers.openai.api_key_secret: codelab/openai`
- **THEN** проблемы R8-6 нет, загрузка успешна; адрес `openai` — из пользовательского слоя, ключ — ссылка `codelab/openai` проектного слоя (правило D23, условие (a)), литерал пользователя к сессиям проекта не применяется
