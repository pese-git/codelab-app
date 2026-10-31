## Why

Конфигурация агента (change `add-agent-configuration`, 8.5) уже принимает ссылки на секреты — `api_key_secret: <имя>` у провайдера и `${secret:<имя>}` в `headers`/`env`, — но прочитать их нечем. Провайдер с `api_key_secret` отвечает ошибкой хода `the secret store is not available yet`, а MCP-сервер с `${secret:…}` пропускается с предупреждением `config.secret.unavailable` (D8 того change, «шов для 8.9»). Ключ остаётся только в переменной окружения (`api_key_env`), а её пользователь desktop-app или launchd-unit часто не может задать.

Встроенный агент этапа 7 берёт ключ провайдера из хранилища секретов, поэтому задача 8.9 нужна MVP (`09-13-stage-8-mcp-config.md`, пункт 9). **Объём сужен решением пользователя 2026-10-31:** бэкенды хранилищ ОС (`keychain-macos`, `secret-service`, `wincred`), индекс имён, разведка утилит, `ffi` в allowlist и ручной тест `os-keychain` перенесены в `openspec/changes/add-agent-os-secret-backends/` (черновик, после 1.0). Порт `SecretStore` не меняется, поэтому они подключатся без изменения вызывающих.

Цели матрицы — P-12 (секреты по имени; в этом change — частично: переменные и файл, хранилище ОС — после 1.0) и P-17 (`--debug-secrets`); алгоритм — `agent-core-architecture` §17.5.4, тесты — §17.5.13.

## What Changes

- **Имена секретов.** `SecretNames` в ядре: строгое правило имени `^[a-z0-9][a-z0-9._/-]{0,127}$` без `..` и без `/` в конце; имя переменной переопределения `CODELAB_SECRET_<…>` (`envOverride`); предлагаемое имя по пути ключа конфига (`suggestFor`, `forMcp`). Это правило заменяет временную проверку 8.5 («непустое, без пробелов»).
- **Порт хранилища и резолвер в ядре** (`codelab_agent_core/lib/src/secrets/`, чистый Dart): `SecretStore` (§10.3), `DescribedSecretStore` с `SecretBackendInfo`, `SecretStoreUnavailableException`, `MemorySecretStore` для тестов и `SecretResolver` — единственная дорога к значению секрета. Порядок разрешения: кэш процесса → переменная `CODELAB_SECRET_<…>` → хранилище. Найденное значение кэшируется до конца процесса, ненайденное — нет; одновременные запросы одного имени идут одним обращением к хранилищу.
- **Ленивое разрешение при запросе.** Ключ провайдера (`api_key_secret` и `api_key_env`) и `${secret:…}` в заголовках провайдера читаются через резолвер при первом запросе к провайдеру; `${secret:…}` в `env`/`headers` MCP-сервера конфига — при подключении сервера к сессии. Отсутствующий секрет даёт ошибку хода класса `auth` с текстом `API key secret <name> is not set. Run: codelab secret set <name>` без HTTP-запроса; MCP-сервер — `mcp.server.failed` с причиной `secret <name> is not set`. Предупреждение `config.secret.unavailable` и записи `providerProblems` о секретах снимаются.
- **Бэкенды** (`codelab_agent_io/lib/src/secrets/`):
  - `env`: только чтение `CODELAB_SECRET_*`;
  - `file`: открытый текст в `$CODELAB_HOME/secrets.yaml`, права `0600` проверяются перед каждым доступом (шире или символическая ссылка — отказ, как у ssh), атомарная запись (права до значения, через `/bin/chmod` порта `SecretProcessRunner`), файл создаёт только `secret set`; на Windows — проблема конфигурации.
- **Выбор бэкенда.** Ключ `secrets.backend: auto | keychain | env | file` (только глобальный конфиг и `--config`, §15.3). В этой версии `auto` = `env` на всех ОС; `auto` никогда не выбирает `file`. `keychain` — проблема конфигурации `not supported yet`. `file` — только явно, с предупреждением `secrets.backend.plaintext` при каждом старте и строкой `warning:` в `config check`. На Windows доступен только `env`. `secret set` при `env` (в том числе `auto`) отвечает кодом `1` и подсказывает `secrets.backend: file` или переменную `CODELAB_SECRET_<…>`; так же подсказывает `config check` для незаданного ссылочного секрета.
- **Подкоманды `secret set|delete|list`** у `codelab` и у `codelab-agent`. Обе вызывают одну реализацию `SecretCommands` (`codelab_agent_io`); `codelab` — через `package:codelab_setup/io.dart`. `set` читает значение только из stdin: с TTY — без эха, без TTY — весь поток. Значение аргументом командной строки — ошибка использования, код `64`. `list` печатает бэкенд и имена, без значений и длин.
- **Настольные хосты и встроенные профили.** Одна фабрика `openHostSecrets` (`codelab_agent_io`) строит резолвер у `codelab-agent` и у встроенного агента этапа 7, в том числе внутри isolate ядра. Desktop использует те же бэкенды, что CLI (те же переменные и `secrets.yaml`); программная запись для страницы настроек — `SecretAdmin`, реэкспорт из `codelab_setup/io.dart`. Замена уже прочитанного секрета видна работающему агенту только после перезапуска (до 8.10). Готовые библиотеки (`flutter_secure_storage`, `keyring`, `keybay`) не берутся; мобильный и web-профили решают хранение своими адаптерами (design.md, D15, D16).
- **Диагностика без значений.** Флаг `serve --debug-secrets` и переменная `CODELAB_DEBUG_SECRETS=1` пишут событие `secrets.lookup {name, purpose, source, found}` на каждое обращение. Значение, его длина, префикс и хеш не пишутся никогда (CFG-10). `config check` печатает бэкенд и строку `warning:` на каждый ссылочный секрет, который не задан; на код выхода это не влияет.
- **Подсказка встроенного ключа.** `ConfigInlineSecretException` получает `suggestedSecretName`. Текст проблемы `inlineSecret` называет команду `codelab secret set <name>` и ссылку, которую нужно вписать вместо ключа.

## Не входит

- чтение переменной `CODELAB_TEST_SECRET_STORE` и её ограничение тестовой сборкой — этап 7 (задача 7.7); он переиспользует бэкенд `file` этого change (design.md, D14);
- бэкенды хранилищ ОС `keychain-macos`, `secret-service`, `wincred`, индекс имён `secret-names.json`, `ffi` и правило сторожа FFI, тест `os-keychain`, условие macOS App Sandbox — `openspec/changes/add-agent-os-secret-backends/` (черновик, после 1.0);
- проверка владельца файла `secrets.yaml` и ACL Windows: `dart:io` их не даёт;
- `Redactor`, точки применения редакции и проверка литералов по шаблонам §12.4 (пункты 2–3 CFG-9) — change `add-agent-core-secret-redaction` (8.11). Что 8.9 передаёт ему — D10;
- `exec.secrets` (секреты в окружении команд) — ключ остаётся без потребителя (`config.key.not_applied`);
- запись конфига (`config set`, `provider add --api-key-stdin`), живая перезагрузка и `SecretResolver.invalidate` по перезагрузке — 8.10;
- пул ключей `<name>_2…` (§17.10.4), токены OAuth `codelab/oauth/<id>` (§17.10.6);
- мастер провайдера и страница настроек клиентов (§12.4), реэкспорт типов секретов в основном бареле `codelab_setup`;
- перенос ключей Python-агента: `auth.toml` не читается (§15.7, CFG-2);
- изменения ACP: новых методов, полей, `_meta` и значений перечислений нет. Ошибка хода уходит существующим путём (`AgentError` → JSON-RPC ошибка `session/prompt`, §13.8).

## Capabilities

### New Capabilities
- `agent-secrets`: имена секретов, порт хранилища и резолвер, порядок разрешения и кэш, бэкенды `env` и `file` и выбор бэкенда, подкоманды `secret`, диагностика `--debug-secrets`.

### Modified Capabilities
- `agent-configuration`: строгое правило имени секрета; разрешение `api_key_secret`, `api_key_env` и `${secret:…}` при запросе и подключении вместо заглушки D8; ключ `secrets.backend`; подсказка `inlineSecret` с именем секрета; `config check` показывает состояние секретов; событие `config.secret.unavailable` снимается.
- `agent-runtime`: шаг 3 требования «MCP-серверы сессии» — раскрытие `${secret:…}` серверов конфига перед `connect` (в том числе при `loadSession` и `setMcpServers`) и новый вид сбоя `mcp.server.failed` для ненайденного или недоступного секрета.
- `agent-binary`: хранилище секретов в `serve`; флаг `--debug-secrets`; сценарий `--llm-script` использует только бэкенд `env`; подкоманда `codelab-agent secret`.
- `codelab-cli`: подкоманда `codelab secret set|delete|list` через `codelab_setup/io.dart`.

## Impact

- **Пакеты:**
  - `codelab_agent_core`: новый `lib/src/secrets/` — `secret_names.dart`, `secret_store.dart`, `secret_resolver.dart`, `memory_secret_store.dart`. Правки:
    - `config/` — правило имени, `secrets.backend`, шаблоны `${secret:…}`, `suggestedSecretName`, снятие D8;
    - `llm/provider_factory.dart` — ленивый ключ в `createRoutedStreamFunction`;
    - `runtime/agent_runtime.dart` — раскрытие шаблонов перед `connect`;
    - `host/services.dart` — поле `AgentCoreServices.secrets`.
  - `codelab_agent_io`: новый `lib/src/secrets/` — `SecretProcessRunner`, `EnvSecretStore`, `FileSecretStore`, `openSecretStore`, `openHostSecrets`, `SecretAdmin`. Также `lib/src/cli/secret_commands.dart`, `secret_input.dart` и правка `config_commands.dart` (секреты в `config check`); `config_loader.dart` — проблема `file` на Windows. `pubspec.yaml` не меняется.
  - `apps/codelab_agent`: `AgentHost` создаёт резолвер; флаг `--debug-secrets`; `lib/src/cli/secret_cli.dart`.
  - `codelab_setup`: `lib/io.dart` реэкспортирует `SecretCommands`, `SecretInput`, `StdinSecretInput`, `SecretAdmin`, `openSecretStore`.
  - `apps/codelab_cli`: подкоманда `secret` в `cli_args.dart` и `run.dart`.
- **Зависимости и сторож не меняются** (design.md, D1): новых зависимостей нет; PKG-2, `ioAllowlist`, `setupAllowlist`, `cliAllowlist` и `rules.dart` прежние. Ядро остаётся web-безопасным: `lib/src/secrets/` без `dart:io`, проверка — `web-compile`.
- **Public API ядра** — только добавления. `createRoutedStreamFunction` получает необязательный параметр `secrets`; используемые сигнатуры не меняются.
- **Совместимость конфигов.** Имя секрета с заглавными буквами, пробелом или `..`, принятое в 8.5, становится проблемой загрузки. В 8.5 такое имя не работало (секрет было нечем прочитать), поэтому рабочих конфигов это не ломает (D2).
- **Пользовательские данные.** Секреты пишутся только по явной команде `secret set` (или `SecretAdmin`) и только при явном `secrets.backend: file` — в `$CODELAB_HOME/secrets.yaml` (`0600`, открытый текст). Конфиг, журналы и `profiles.json` значений не получают.
- **Документы:**
  - `agent-core/17-5-agent-setup.md` §17.5.2, §17.5.4, §17.5.9, §17.5.13;
  - `agent-core/10-core-assembly-and-profiles.md` §10.3;
  - `agent-core/15-configuration.md` §15.4, §15.5 (п. 7), §15.6;
  - `agent-core/12-observability-and-errors.md` §12.2 (примеры ошибок), §12.3 (события), §12.4 (абзац «До 8.11»);
  - `09-13-stage-8-mcp-config.md`, пункт 9;
  - `09-11-stage-6-cli-mvp.md`, абзац о подкомандах;
  - `12-4-first-run-and-settings.md` §12.4.2;
  - `09-12-stage-7-embedded.md` (встроенный профиль в 1.0 — `env` и `file`);
  - `agent-parity-goals.md` (P-12 — частично);
  - вложенные `AGENTS.md` `codelab_agent_io`, `codelab_setup`, `apps/codelab_agent`, `apps/codelab_cli`.
- **Матрица целей:** P-12 — частично: `env` и `file`, хранилище ОС после 1.0 (`core/config-rejects-inline-api-key`, в части пункта 1 CFG-9; пункты 2–3 — 8.11) и P-17 (`core/debug-secrets-never-logs-value`).
