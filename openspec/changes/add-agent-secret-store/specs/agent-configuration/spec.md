## MODIFIED Requirements

### Requirement: Секреты только ссылками
Конфигурация НЕ SHALL хранить ключи API значением (CFG-2). Ключи `api_key`, `apiKey`, `token`, `secret`, `password` в `providers.*` и в элементах `mcp.servers` SHALL давать проблему `inlineSecret`; хост SHALL отказывать в старте исключением `ConfigInlineSecretException` с путём ключа и `suggestedSecretName` — именем `SecretNames.suggestFor(путь)` (capability `agent-secrets`, «Имена секретов»). Текст проблемы НЕ SHALL содержать значение и SHALL называть команду `codelab secret set <suggestedSecretName>`:
- у провайдера — и ссылку `api_key_secret: <suggestedSecretName>`;
- у элемента `mcp.servers` — и подстановку `${secret:<suggestedSecretName>}` в `env` или `headers`.

`api_key_env` и `api_key_secret` вместе SHALL быть проблемой с ключом `providers.<id>.api_key_secret`. Значение `api_key_env` SHALL быть именем переменной (`[A-Za-z_][A-Za-z0-9_]*`, иначе `expected an environment variable name`). Значение `api_key_secret` и имя в `${secret:<name>}` SHALL проходить правило `SecretNames` (иначе `expected a secret name: lowercase letters, digits and . _ / -, up to 128 characters`). Неверный формат — проблема `value` с путём ключа без значения в тексте. Проверка литералов по шаблонам §12.4 (пункты 2–3 CFG-9) — change `add-agent-core-secret-redaction`.

- `api_key_env` незаданной переменной SHALL давать предупреждение `config.provider.key_missing {provider, variable}` при загрузке и ошибку хода `API key variable <VAR> is not set` при выборе модели этого провайдера без HTTP-запроса. Значение переменной SHALL читаться при запросе через `SecretResolver.env`.
- `api_key_secret` и `${secret:<name>}` в `providers.*.headers.*`, `mcp.servers[*].env.*` и `mcp.servers[*].headers.*` SHALL разрешаться через `SecretResolver`: у провайдера — при запросе, у MCP-сервера — при подключении к сессии (capability `agent-secrets`, требования «Ключ провайдера при запросе» и «Секреты MCP-серверов конфигурации»). Загрузка НЕ SHALL читать хранилище секретов и НЕ SHALL пропускать MCP-сервер из-за ссылки на секрет.
- Ключ `secrets.backend` SHALL принимать `auto`, `keychain`, `env`, `file` (capability `agent-secrets`, «Выбор бэкенда secrets.backend»); он больше не даёт `config.key.not_applied`.

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

#### Scenario: Переменная ключа не задана
- **WHEN** провайдер `openai` задаёт `api_key_env: OPENAI_API_KEY`, переменная не задана, а сессия выбирает модель `openai/gpt-4o`
- **THEN** загрузка успешна с предупреждением `config.provider.key_missing`, а ход завершается ошибкой `API key variable OPENAI_API_KEY is not set` без запроса к провайдеру

#### Scenario: Ссылки на секреты не читаются при загрузке
- **WHEN** провайдер задаёт `api_key_secret: codelab/anthropic`, а сервер `gh` — заголовок `${secret:codelab/mcp/gh/authorization}`; загрузка идёт с хранилищем, которое считает вызовы
- **THEN** загрузка успешна без предупреждений о секретах, хранилище не вызывалось, `CoreConfig.mcpServers` содержит `gh`, `providerProblems` не содержит `anthropic`

## ADDED Requirements

### Requirement: config check показывает состояние секретов
Если загрузка валидна, а конфиг ссылается на секреты (`api_key_secret`, `${secret:…}` у провайдеров и MCP-серверов), `config check` SHALL проверять каждое имя (без повторов) резолвером без режима отладки, с тем же хранилищем, что у подкоманд `secret`. Перед последней строкой `Config: …` SHALL печататься:
- `note: secrets backend: <id>` (или `note: secrets backend: env (<reason>)`);
- на каждый ненайденный секрет — `warning: <location>: <key>: secret <name> is not set; run: codelab secret set <name>`; при бэкенде `env` (в том числе `auto`) текст SHALL вместо этого подсказывать `set <envOverride(name)> or add 'secrets.backend: file' and run: codelab secret set <name>` (на Windows — только переменную);
- при недоступном хранилище — одна строка `warning: secrets: <backend> is unavailable (<reason>)`.

При `secrets.backend: file` SHALL всегда, даже без ссылок на секреты, печататься `warning: secrets: file backend stores secrets unencrypted in <path>`, а при правах шире `0600` — ещё `warning: secrets: <path> has permissions <mode>; run: chmod 600 <path>`.

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

#### Scenario: Без ссылок вывод прежний
- **WHEN** конфиг использует только `api_key_env`
- **THEN** строк `note: secrets` и `warning: secrets` нет, хранилище не вызывалось

### Requirement: Наблюдаемость загрузки конфигурации
Успешная загрузка SHALL писать `host.config.loaded {sources, warnings, project_root, transport, models}` (`transport` — `stdio` или `ws`, `models` — id моделей каталога). Каждое предупреждение загрузки SHALL писаться отдельным событием своего имени (`config.env.unknown`, `config.project.untrusted_key`, `config.key.not_applied`, `config.provider.key_missing`, `config.file.ignored`, `config.legacy_found`, `mcp.server.skipped`) и SHALL нести поле `message` — английский текст `ConfigIssue.message` без значений. Событие `config.secret.unavailable` НЕ SHALL писаться: ссылки на секреты разрешаются при запросе и подключении (requirement «Секреты только ссылками»). Значения ключей конфигурации, переменных и секретов НЕ SHALL попадать в эти события и в текст проблем: только пути ключей, имена переменных и секретов, источники.

#### Scenario: Ни одного значения в логе
- **WHEN** конфиг содержит `headers.Authorization: "Bearer ${TOKEN}"` с `TOKEN=tok-test-secret` и ключ без потребителя, а агент стартует с `--log-level trace`
- **THEN** лог содержит `host.config.loaded` с полями `transport` и `models` и `config.key.not_applied` с полями `key`, `source`, `message`, но не содержит `tok-test-secret`

#### Scenario: Нет предупреждения о недоступном хранилище
- **WHEN** конфиг содержит `api_key_secret` и `${secret:…}` в MCP-сервере
- **THEN** лог загрузки не содержит `config.secret.unavailable`
