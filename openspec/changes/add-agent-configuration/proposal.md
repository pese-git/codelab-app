## Why

Бинарь `codelab-agent` до сих пор настраивается только флагами и переменными окружения этапа 4: один провайдер `cli`, ключ только в `CODELAB_API_KEY`, режим `--permission-mode`, остальное — значения по умолчанию §15.4 (`agent-core-architecture` §15.6, абзац «До этапа 8»). Файлов конфига агент не читает. Из-за этого:
- нельзя описать несколько провайдеров и модели с их окнами и ценами;
- MCP-серверы конфигурации не подключаются. Ядро уже принимает `CoreConfig.mcpServers` (`origin: config`) и правило «сервер клиента вытесняет сервер конфига», но загрузчика нет. Поэтому критерии Must-строк E-02 и E-03 закрыты только для серверов из `session/new` (`agent-parity-goals.md`, строки E-02, E-03);
- пользователь Python-агента, у которого есть только `codelab.toml`, не узнаёт, что новый агент этот файл не использует (R-16 в редакции решения пользователя 2026-10-29);
- опечатка в настройке нигде не проверяется (CFG-1).

Встроенный агент этапа 7 ждёт этот загрузчик: порядок D3 плана — `{6, 8} → 7` (`09-13-stage-8-mcp-config.md`, «Зависимости»; `09-12-stage-7-embedded.md`, задача 7.5). Change закрывает задачу 8.5 этапа 8.

## What Changes

- **Модель и проверка конфигурации в ядре** (`codelab_agent_core/lib/src/config/`, без `dart:io` и без разборщиков; CFG-5):
  - `ConfigTree` — разобранный слой с позициями узлов;
  - `ConfigPosition`, `ConfigIssue {key, source, line?, column?, message}`, `ConfigLoadResult`, `ConfigException`;
  - декларативная схема MVP-ключей §15.4 плюс ключ `mcp.servers[*].call_timeout`;
  - чистая функция `CoreConfig.fromLayers(...)`: строгая проверка ключей и типов с подсказкой ближайшего ключа, правила доверия к проектным слоям (§15.3), слияние (§15.2), подстановка `${ENV}` (§15.5), семантические проверки. Результат — `CoreConfig` или список `ConfigIssue`; поле `issues` и есть `validate()` плана.

  `CoreConfig`, `PermissionsConfig` и `CompactionOverrides` переезжают из `host/services.dart` в `config/core_config.dart` (§1.3); экспорт бареля не меняется. `CoreConfig` получает поля провайдеров (`List<CatalogProvider>`), журналов, логов, сужения профиля и `redact`.
- **Загрузчик в `codelab_agent_io`** (`lib/src/config/`):
  - `ConfigLoader` — порядок слоёв: умолчания < `$CODELAB_HOME/config.yaml` < `<cwd>/.codelab/config.yaml` < `<cwd>/.codelab/config.local.yaml` < `--config`/`CODELAB_CONFIG` < `CODELAB_*` < флаги (§15.2, §15.6);
  - `yaml_reader.dart` — разбор `package:yaml` в строгом профиле §15.5: один документ; без якорей, алиасов, `<<` и тегов; ключи — только строки, без повторов; логические значения — только `true`/`false`; `null` у ключа схемы — ошибка. Нарушение — ошибка с файлом, строкой и столбцом;
  - `legacy_notice.dart` — если `codelab.toml` Python-агента найден (места поиска Python-агента), а ни одного `config.yaml` нет, — одно предупреждение `config.legacy_found` с путями и ссылкой на таблицу ручного переноса §15.7. Файл не читается и не разбирается (решение пользователя 2026-10-29);
  - `cli/` — общая реализация подкоманды `config check`: тексты, коды выхода `0`/`1`/`64`.
- **Бинарь `codelab-agent`**:
  - `serve` собирает ядро из загруженного конфига. Несколько провайдеров маршрутизируются по `ModelRef.provider` новой фабрикой ядра `createRoutedStreamFunction`;
  - флаги и `CODELAB_*` становятся слоями 5–6: `--provider`/`--base-url`/`--model` по-прежнему дают провайдера `cli`; `--model <provider>/<model>` без `--provider` выбирает модель из конфига; новые флаги — `--config`, `--max-steps`;
  - неверный конфиг — код `64` с файлом, строкой и путём ключа, а не исключение на первом ходе (DoD этапа: `config_loader_test.dart: invalid config reports key path and line`);
  - новая подкоманда `codelab-agent config check`;
  - **изменение поведения:** ошибки «named providers come with the config of stage 8» и «no model source» заменяются проверкой `agent.default_model`.
- **MCP-серверы из конфигурации** (закрывают оставшуюся часть E-02 и E-03):
  - `mcp.servers` с `type: stdio | http`, `${ENV}` в `args`, `env`, `url`, `headers`, `enabled: false`, `connect_timeout`;
  - новый ключ `call_timeout` — таймаут `tools/call`, по умолчанию 10 минут (D8 архива `add-agent-mcp-client`). Для него `McpServerConfig` получает поле `callTimeout`, а `McpClientConnector` берёт его вместо общей константы;
  - слои 2–4 сливаются по `name`; из недоверенного проектного слоя 3 серверы игнорируются с `config.project.untrusted_key` (CFG-3);
  - в `serve --ws` серверы конфига, как и серверы клиента, не запускаются: capability `mcp` выключена (D3 архива).
- **Ключи `redact.*`** читаются, проверяются (известные слои, компилируемые выражения) и подчиняются правилам доверия §12.4.3. В `CoreConfig.redact` они ждут редактора задачи 8.11; до него явно заданный ключ даёт предупреждение `config.key.not_applied`.
- **Секреты — только ссылками** (CFG-2):
  - ключ `api_key` и другие поля-секреты (`apiKey`, `token`, `secret`, `password`) в `providers.*` и `mcp.servers.*` — ошибка `ConfigInlineSecretException` без значения в тексте;
  - `api_key_env` разрешается из окружения;
  - `api_key_secret` и `${secret:<name>}` принимаются синтаксически. Значение их даёт хранилище секретов задачи 8.9 (change `add-agent-secret-store`), и до него провайдер с `api_key_secret` и MCP-сервер с `${secret:…}` недоступны с явной причиной;
  - проверка литеральных значений по шаблонам §12.4 — вместе с редактором 8.11 и хранилищем 8.9.
- **Технология** (`AGENTS.md` §4): `package:yaml` — единственная новая прямая зависимость `codelab_agent_io` (уже в allowlist §1.2). `package:yaml_edit` утверждается как писатель с сохранением форматирования, но в `pubspec.yaml` добавляется в change `add-config-writer-and-reload` (8.10), где появляется `ConfigWriter`. `toml` из allowlist `codelab_agent_io` убирается (D2).
- **CLI `codelab config check`** через минимальный мост `packages/dart/codelab_setup` (`lib/io.dart` реэкспортирует общие подкоманды `codelab_agent_io`): клиентам запрещено импортировать `codelab_agent_*` (PKG-4). Решение пользователя 2026-10-29 (OQ2, вариант (а)).
- **Сторож**:
  - `toml` убран из allowlist `codelab_agent_io`;
  - `codelab_agent_core` не импортирует `package:yaml`, `yaml_edit`, `toml`;
  - правило и allowlist `codelab_setup`;
  - `codelab_setup` в allowlist `apps/codelab_cli`.

Не входит:
- **совместимость с `codelab.toml` Python-агента** (решение пользователя 2026-10-29): чтение файла как слоя, перевод ключей, `config migrate [--print]`, `config.legacy_ignored`, `ConfigLegacyReadOnlyException`, зависимость `toml`, защита `codelab.toml` правилом PERM-11 (агент файл не читает, D15). Настройки переносятся вручную по таблице §15.7;
- запись конфига (`ConfigWriter`, `config set|unset`, `provider add|list|remove`, `mcp add|list|remove`), живая перезагрузка, `ConfigSource`/`ConfigWatcher`, `SettingsRegistry`, `McpSupervisor` и переподключение MCP, предконфигурация `CODELAB_PROVIDER_*` — change `add-config-writer-and-reload` (8.10, Should).;
- хранилище секретов, `SecretResolver`, `SecretNames`, `codelab secret set|delete|list`, разрешение `api_key_secret` и `${secret:…}` — change `add-agent-secret-store` (8.9);
- сама редакция секретов, применение `redact.*`, источники точных секретов — change `add-agent-core-secret-redaction` (8.11);
- инструкции проекта (`project_context.*`, `prompts.context_files`), slash-команды из шаблонов, определения агентов в Markdown — change `add-project-instructions-and-commands` (8.6–8.8);
- применение ключей без потребителя в коде этой сборки: `tools.*`, `loop.*`, `exec.*`, `prompts.*`, `model_catalog.*`, `agent.fallback`, `agent.summary_model`, `permissions.timeout`, `logging.trace*`. Они проверяются по схеме и дают `config.key.not_applied` (D6; решение OQ4 (а) 2026-10-29);
- endpoint `/models`, удалённый каталог и кэш каталога (L-15), роли моделей (L-10), `--tools` (T-26);
- снимок конфига на каждый корень сессии и перечитывание при `session/new` в другом `cwd` (§10.3, абзац о разных `cwd`) — 8.10 вместе с `ConfigSource`; здесь — D9 (решение OQ1 (а) 2026-10-29);
- `config check` с планом сборки встроенного агента (задача 7.6), мастер провайдера, страницы настроек клиентов (§12.4);
- `.env`-файлы и переменные `CODELAB_LLM_*` Python-агента: новый агент их не читает, неизвестные `CODELAB_*` дают предупреждение (§15.6);
- изменения ACP: новых методов, полей и `_meta` нет. Конфиг меняет только содержимое уже существующих ответов: модели опции `model` и серверы `mcpServers` сессии.

## Capabilities

### New Capabilities
- `agent-configuration`: файлы и порядок слоёв, строгий профиль YAML, схема и проверка с позициями, доверие к проектному конфигу, подстановка `${ENV}`, секреты только ссылками, MCP-серверы и `redact.*` из конфига, предупреждение `config.legacy_found` о неиспользуемом `codelab.toml`, подкоманда `config check`, наблюдаемость загрузки.

### Modified Capabilities
- `agent-binary`: конфиг бинаря — файлы, окружение и флаги вместо «минимального конфига из флагов»; подкоманда `config`; `logging.file` из конфига; MCP-серверы конфигурации в бинаре.
- `agent-llm`: фабрика `createRoutedStreamFunction` — несколько провайдеров конфигурации, отказ провайдера без ключа при выборе модели.
- `agent-mcp-client`: таймаут `tools/call` берётся из `McpServerConfig.callTimeout` (ключ `call_timeout`), а не только из константы.
- `agent-runtime`: сессия, чей `cwd` вне корня запуска хоста, не получает проектных слоёв корня запуска (D9).
- `workspace-architecture`: ядро не импортирует `yaml`/`yaml_edit`/`toml`, `toml` убран из allowlist `codelab_agent_io`, правило и allowlist моста `codelab_setup`, `codelab_setup` в allowlist CLI.
- `codelab-cli`: подкоманда `codelab config check`.

## Impact

- **Пакеты:**
  - `codelab_agent_core`: новый каталог `lib/src/config/`; правки `mcp/mcp_server_config.dart`, `llm/provider_factory.dart`, `runtime/agent_runtime.dart`;
  - `codelab_agent_io`: `lib/src/config/`, `lib/src/cli/`, `pubspec.yaml` — `yaml`;
  - `codelab_agent_mcp`: `connector.dart`, `mcp_client.dart` — `callTimeout` сервера;
  - `apps/codelab_agent`: `serve_args.dart`, `agent_host.dart`, `run.dart`, новая подкоманда;
  - новый `packages/dart/codelab_setup` (только `io.dart` и реэкспорт чистых типов);
  - `apps/codelab_cli`: подкоманда `config`, зависимость `codelab_setup`;
  - `codelab_architecture_tests`: `rules.dart`, `pubspec_allowlist_test.dart`, `import_guard_test.dart`.
- **Public API ядра** — только добавления: `ConfigTree`, `ConfigIssue`, `ConfigLoadResult`, `ConfigException`, `ConfigInlineSecretException`, `CoreConfig.fromLayers`, новые поля `CoreConfig`, `McpServerConfig.callTimeout`, `createRoutedStreamFunction`. Используемые сигнатуры не меняются.
- **Зависимости:** `yaml` ^3.1.3 (`tools.dart.dev`, MIT) в `codelab_agent_io`; уже транзитивно в `pubspec.lock` (3.1.3). Ядро остаётся web-безопасным: разборщик только в `_io` (CFG-5, PKG-2 не расширяется).
- **Документы:**
  - `agent-core/15-configuration.md`: §15.1, §15.2 (без строки о `codelab.toml`), §15.4 (`call_timeout`), §15.5 (ключи без потребителя), §15.6, §15.7 — «Перенос настроек Python-агента»: таблица ручного переноса и `config.legacy_found` вместо чтения и `migrate`; §15.10 (CFG-20), §15.11, §15.12;
  - `agent-core/01-layers-and-packages.md` §1.2–§1.3 (allowlist `_io` без `toml`), `agent-core/10-core-assembly-and-profiles.md` §10.3, `agent-core/12-observability-and-errors.md` §12.2, `agent-core/17-5-agent-setup.md` (без `ConfigLegacyReadOnlyException`, `config migrate` и `legacy` в `ConfigLoadResult`);
  - `09-13-stage-8-mcp-config.md`, задача 8.5; `09-11-stage-6-cli-mvp.md`;
  - `agent-parity-goals.md`: R-16 (решение пользователя 2026-10-29), DF-12, DF-15 (для YAML), E-02, E-03, критерий вывода Python-агента §6 (п. 5 — ручной перенос настроек);
  - `09-14-stage-9-switch-default.md` (задачи 9.7, 9.10), ADR-0001 п. 11, `16-non-mvp-and-open-questions.md`;
  - README (граф пакетов: `codelab_setup`).
- **Матрица целей:** R-16 меняется решением пользователя 2026-10-29 («`codelab.toml` не читается; `config.legacy_found` с подсказкой») и закрывается `config_legacy_found_test.dart`; DF-12 (`core/config-rejects-yaml-agent-definitions`) и DF-15 (`core/config-unknown-provider-error`) — для YAML; серверы конфигурации в E-02 и E-03; DoD `config_loader_test.dart`.
