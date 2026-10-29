# 9.13. Этап 8 — MCP, конфигурация, AGENTS.md

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.12. Этап 7 — Встроенный режим в обоих клиентах](09-12-stage-7-embedded.md) · [Оглавление](../dart-agent-and-clients.md) · [9.14. Этап 9 — Цели Must и переключение по умолчанию](09-14-stage-9-switch-default.md) →

**Цель.** Внешние инструменты через MCP проходят ту же точку проверки разрешений, что и
встроенные; конфигурация полная и проверяемая; агент учитывает инструкции проекта.

**Задачи.**

1. **8.1. Пакет `packages/dart/codelab_agent_mcp`:** `lib/src/json_rpc.dart` (кодек JSON-RPC),
   `lib/src/protocol.dart` (`server/discover`, `initialize`, `tools/list`, `tools/call`,
   `subscriptions/listen`, `notifications/tools/list_changed`; клиент dual-era: modern `2026-07-28`
   и legacy `initialize`), `lib/src/mcp_client.dart`, `lib/src/streamable_http.dart`,
   `lib/src/connector.dart` (`McpClientConnector`). **Порт транспорта** (`McpTransport`,
   `McpTransportFactory`) и порт подключения серверов сессии (`McpConnector`) лежат не в
   `protocol.dart`, а в ядре — `codelab_agent_core/lib/src/mcp/` (agent-core-architecture §1.3,
   §10.3): `codelab_agent_io` реализует порты ядра и не зависит от MCP-пакета, а MCP-клиента ядро
   создать не может. Решения — [`design.md`](../../../../openspec/changes/archive/2026-10-29-add-agent-mcp-client/design.md)
   change `add-agent-mcp-client` (D3).
2. **8.2. stdio-транспорт MCP** в `packages/dart/codelab_agent_io/lib/src/mcp/stdio_process_transport.dart`
   (процесс с `env` по allowlist, остановка при завершении сессии).
3. **8.3. Проекция в инструменты:** `packages/dart/codelab_agent_mcp/lib/src/mcp_tool.dart` — `AgentTool` с именем
   `mcp__<сервер>__<инструмент>` (длиннее 64 символов — первые 56 + `_` + 7 hex SHA-256 полного
   имени), схема параметров из `inputSchema`, вид инструмента из аннотаций (`readOnlyHint: true` →
   `read`; `destructiveHint: true` → `edit` при `openWorldHint: false`, иначе `execute`; без
   аннотаций — `other`); уровень доступа всегда `exec` — аннотациям сервера не доверяем
   (agent-core-architecture §6.4, «MCP-инструменты»; ограда вывода — §6.3.6);
   там же — проекция содержимого (`text`, `image`, `resource`, `resource_link`).
   Регистрация — только через `ToolRegistry` и `buildAgentCore` (capability `mcp`).
4. **8.4. ACP:** параметр `mcpServers` из `session/new` и `session/load` передаётся в сессию;
   `agentCapabilities.mcpCapabilities` объявляет поддерживаемые транспорты.

   **Итог 8.1–8.4.** Сделано change `add-agent-mcp-client` (итерации 0–4): свой клиент dual-era
   в `codelab_agent_mcp` (D1, D2), stdio-транспорт в `codelab_agent_io` (D9), streamable HTTP
   обеих эпох (D10), проекция в `AgentTool` (D7), подключение `mcpServers` в ACP-адаптере (D11).
   Отступление: в `codelab-agent serve --ws` MCP выключен (D3, §13.15 документа ядра). Серверы
   из конфигурации ядро принимает, но читает их только change `add-agent-configuration` (8.5).
   Отметки DoD — ниже.
5. **8.5. Конфигурация** (change [`add-agent-configuration`](../../../../openspec/changes/add-agent-configuration/)):
   модель и валидация — `packages/dart/codelab_agent_core/lib/src/config/` (agent-core-architecture §1.3):
   `ConfigTree`, `ConfigIssue` (с `kind`), чистая функция `CoreConfig.fromLayers(List<ConfigTree>)` →
   `ConfigLoadResult` (проблемы с файлом, строкой, столбцом и путём ключа); загрузка —
   `packages/dart/codelab_agent_io/lib/src/config/config_loader.dart`. Порядок слоёв: значения по
   умолчанию < `~/.codelab/config.yaml` < `<cwd>/.codelab/config.yaml` <
   `<cwd>/.codelab/config.local.yaml` < `--config`/`CODELAB_CONFIG` < переменные `CODELAB_*` <
   флаги командной строки (agent-core-architecture §15.2). Формат — YAML в строгом профиле (§15.5):
   разбор `package:yaml` с позициями ошибок (единственная новая зависимость пакета; `yaml_edit`
   приходит с записью в 8.10). Старый `codelab.toml` Python-агента **не читается** (решение
   пользователя 2026-10-29): если нет ни одного YAML-файла слоёв 2–4 и не задан `--config`,
   загрузчик пишет одно предупреждение `config.legacy_found` с путями найденных файлов и ссылкой
   на таблицу ручного переноса (agent-core-architecture §15.7; см. также §7б); `toml`,
   `ConfigLegacyReadOnlyException` и `config migrate` не вводятся. Подключаются MCP-серверы
   конфигурации (`mcp.servers`, `call_timeout`) и несколько провайдеров
   (`createRoutedStreamFunction`). Подкоманды `codelab-agent config check` и
   `codelab config check [--cwd <dir>]` (через мост `codelab_setup`). Тесты:
   `core/config-legacy-found-warning`, `config_yaml_profile_test.dart`,
   `config_legacy_found_test.dart`. Здесь же читаются ключи `redact.*` редакции секретов
   (задача 8.11; agent-core-architecture §12.4.3, правило доверия проекту §15.3).
6. **8.6. Инструкции проекта** (agent-core-architecture §11.5): `ProjectContextLoader` хоста
   читает через `ExecutionEnv` (граница `BoundedEnv` соблюдается) файлы от `cwd` вверх до корня
   git-репозитория (без репозитория — только `cwd`), на каждом уровне `AGENTS.md` и `CLAUDE.md`,
   плюс `$CODELAB_HOME/AGENTS.md`; общий бюджет 32 КиБ (`project_context.max_bytes`), файл, не
   поместившийся целиком, усекается с пометкой; секция системного промпта `project-context`.
7. **8.7. Slash-команды агента:** шаблоны промптов `<cwd>/.codelab/prompts/*.md` (только для проекта в `trusted_projects`) и
   `$CODELAB_HOME/prompts/*.md` (agent-core-architecture §17.2.2; frontmatter: `description`, `argument-hint`; тело — шаблон
   промпта с `$ARGUMENTS`) → `available_commands_update` после `session/new`; вызов `/имя
   аргументы` разворачивается в промпт.
8. **8.8. Определения агентов в Markdown** (R-15, Must): загрузчик `$CODELAB_HOME/agents/*.md` и `<cwd>/.codelab/agents/*.md` (только для доверенного проекта), разбор YAML-frontmatter пакетом `yaml`, опция конфигурации `agent`, применение промпта, модели, режима и списка инструментов; `config migrate` переносит `[agents.definitions.*]` в Markdown-файлы. Спецификация — agent-core-architecture §15.8; тесты `agent_definition_parse_test.dart`, `agent_definition_trust_test.dart`, `agent_select_test.dart`, фикстура `acp/set-config-option-agent`.
9. **8.9. Хранилище секретов** (P-12, P-17; agent-core-architecture §17.5.4) — нужна MVP:
   встроенный агент этапа 7 берёт ключ провайдера отсюда. `SecretResolver` (порядок разрешения
   §17.5.4: кэш → переменная `CODELAB_SECRET_<…>` → хранилище ОС), бэкенды `keychain-macos`
   (`security`), `secret-service` (`secret-tool`), `wincred`; значение секрета передаётся утилите
   только через stdin, никогда в argv; подкоманды `codelab secret set|delete|list`;
   `--debug-secrets` / `CODELAB_DEBUG_SECRETS=1` пишет обращения без
   значений. Тесты (agent-core-architecture §17.5.13): `secret_resolver_test.dart`,
   `secret_store_backends_test.dart` (fake `ProcessRunner`), `debug_secrets_test.dart`
   (`core/debug-secrets-never-logs-value`); настоящие связки ключей — отдельный интеграционный
   тест на macOS и Linux (исключение (г) правила TDD).
10. **8.10. Запись конфига, живая перезагрузка, реестр настроек, переподключение MCP**
    (L-25, E-04, E-15; agent-core-architecture §17.5.3, §17.5.5–§17.5.8) — **Should — не блокирует
    MVP**: `ConfigWriter` (`yaml_edit`, атомарная запись) и подкоманды `codelab config set|unset`,
    `provider add|list|remove`, `mcp add|list|remove`; `ConfigWatcher` и живая перезагрузка;
    `McpSupervisor` с переподключением; `SettingsRegistry` с тестом полноты; предконфигурация
    провайдера из окружения (L-25); агентские команды `/config` и `/mcp`. Клиентская часть
    (мастер, страницы настроек) — §12.4. Без 8.10 конфиг правится вручную, а `config check`
    (8.5) его проверяет.
11. **8.11. Редакция секретов** (P-10, *Should — не блокирует MVP*; перенесена с этапа 3):
    вывод инструментов (`exec env`, `read .env`), промпт пользователя и лог не попадают в журнал
    сессии и к провайдеру с сырыми секретами. Состав:
    * `Redactor` в `codelab_agent_core` с послойным алгоритмом agent-core-architecture §12.4.1:
      слои `exact`, `credential_files`, `formats`, `pem`, `connection_strings`, `key_values`;
      `entropy` выключен; белый список `git_sha`, `uuid`; идемпотентность и сохранение числа строк;
    * признак `AgentTool.redactResult` — `false` у `write` и `edit` (§6.2);
    * точки применения §12.4.2 — `userInput`, `toolResult`, `providerRequest`, `journal`, `log`
      (точка `spill` — вместе с выносом результата, задача 3.8);
    * источники точных секретов (§12.4) — переменные окружения по шаблону имён, ключ провайдера,
      значения `SecretStore` (8.9) и токены MCP-серверов (8.1) через `addExactSecret`;
    * ключи `redact.*` из конфигурации (8.5) с правилом доверия проекту (§12.4.3, §15.3).

    Команда `/redact stats | layers` — после MVP (§13.4). До этой задачи журналы этапов 4–7
    хранят вывод инструментов как есть. Тесты: `core/redaction-before-journal`,
    `core/redaction-preserves-line-count`, `core/redaction-write-results-exempt`. Вынос
    результата (задача 3.8, change `add-agent-core-output-spill`) идёт после неё: файл выноса не
    должен содержать сырых секретов (SPL-3).

**OpenSpec change.** [`add-agent-mcp-client`](../../../../openspec/changes/archive/2026-10-29-add-agent-mcp-client/) (8.1–8.4; scope: протокол MCP, транспорты, имена и
виды MCP-инструментов, проверка разрешений; решение о библиотеке MCP — в его `design.md`),
`add-agent-configuration` (8.5; scope: файлы, порядок слоёв, формат YAML и его профиль,
предупреждение `config.legacy_found` вместо чтения `codelab.toml`, подкоманда `config check`,
минимальный `codelab_setup`; новая зависимость `yaml` как решение о технологии по
`AGENTS.md` §4; `toml` не добавляется, `yaml_edit` — в 8.10), `add-project-instructions-and-commands` (8.6–8.8),
`add-agent-secret-store` (8.9; scope: имена секретов, порядок разрешения, бэкенды ОС, команды
`secret`, диагностика без значений) и `add-config-writer-and-reload` (8.10, Should; scope:
запись конфига, наблюдатель и перезагрузка, реестр настроек, `McpSupervisor`, команды
`config`/`provider`/`mcp` на запись) и `add-agent-core-secret-redaction` (8.11, Should; scope:
слои и точки применения редакции, `AgentTool.redactResult`, источники точных секретов, ключи
`redact.*`). `tasks.md` — пары "тест → реализация" со ссылкой на
критерий (§9.0, правило 3).

Бинарь (`add-agent-mcp-client`, итерация 3) собирает `McpClientConnector` со
`StdioMcpTransportFactory` и `StreamableHttpTransportFactory` на одном `http.Client` процесса
(общем с LLM-провайдером, закрывается при завершении хоста); профиль `agent-serve` даёт `mcp:
{stdio, http}`, и `initialize` по `--stdio` объявляет `mcpCapabilities.http: true`. В `serve --ws` capability `mcp` выключена
совсем (решение пользователя по ревью PR #158, D3 change): держатель токена WebSocket иначе
запускал бы произвольные команды на машине агента; это отступление от ACP (`03-Session Setup.md`,
stdio MUST) записано в §13.15, включение явным флагом хоста — отдельный change.

**Решение о библиотеке MCP** — чек-лист, который заполняется в `design.md` change
`add-agent-mcp-client` в начале этапа, до кода (разведка не дольше двух дней, исключение (д)
правила TDD). Пакет pub.dev берётся, только если отмечены все пункты; хотя бы один «нет» — свой
минимальный клиент в `codelab_agent_mcp` (протокол небольшой: `initialize`, `tools/list`,
`tools/call`, `notifications/tools/list_changed`, `notifications/cancelled`):

- [ ] чистый Dart без Flutter; протокольная часть без `dart:io` (сторож: `codelab_agent_mcp`
  без `dart:io`), транспорты отделимы;
- [ ] клиент stdio и streamable HTTP; legacy SSE не требуется (E-03);
- [ ] транспорт и `http.Client` подставляются снаружи: нужен свой
  `stdio_process_transport.dart` с `env` по allowlist (8.2) и `MockClient` в тестах;
- [ ] отмена вызова (`notifications/cancelled`) и таймауты управляются вызывающим кодом;
- [ ] лицензия MIT, BSD или Apache-2.0;
- [ ] выпуск за последние 6 месяцев, нет открытых критических ошибок протокола;
- [ ] зависимости не конфликтуют с `pubspec.lock` и не тянут второй фреймворк (`AGENTS.md` §4).

В `design.md` записываются: кандидаты, отметки по каждому пункту, решение и версия пакета (если
выбран).

**Что прочитать.** Документ ядра §6, §7, §10 (capability `mcp`), §11, §12.4 (редакция, 8.11), §15; спецификация MCP
(стандарт протокола, раздел о транспортах); `docs/protocols/acp/protocol/03-Session Setup.md`,
`14-Slash Commands.md`.

**Definition of Done.**

* `packages/dart/codelab_agent_mcp/test/mcp_tool_goes_through_policy_test.dart: MCP tool is not executed without a permission decision` (закрывает F5.1). **Выполнено** (8.3, change `add-agent-mcp-client`).
* `packages/dart/codelab_agent_mcp/test/streamable_http_test.dart` на `MockClient`. **Выполнено** (8.1, обе эпохи MCP; change `add-agent-mcp-client`).
* `packages/dart/codelab_agent_io/test/config/config_loader_test.dart: invalid config reports key path and line` — битый конфиг даёт ошибку с путём ключа, а не исключение при первом ходе (8.5, change `add-agent-configuration`).
* Фикстуры `acp/session-new-with-mcp`, `acp/available-commands-no-tools` зелёные. `acp/session-new-with-mcp` — **выполнено** (8.4, change `add-agent-mcp-client`); `acp/available-commands-no-tools` — задачи 8.6–8.8.
* `melos run guard`: `codelab_agent_mcp` без `dart:io`. **Выполнено**: правило пакета в `packages/dart/codelab_architecture_tests/test/support/rules.dart`, allowlist — `pubspec_allowlist_test.dart` (D14 change `add-agent-mcp-client`).
* Чек-лист библиотеки MCP заполнен в `design.md`, решение записано. **Выполнено**: D1 change `add-agent-mcp-client` — у каждого кандидата есть «нет», свой минимальный клиент; `THIRD_PARTY_NOTICES.md` не меняется.
* Все Must-строки матрицы этапа 8 зелёные; критерий — сценарий строки в матрице. Строки P-01,
  P-16, E-02, E-03, E-05, R-24 закрыты change `add-agent-mcp-client` (файлы тестов и фикстур —
  в колонке «Критерий приёмки» матрицы; серверы конфигурации в E-02 и E-03 — после 8.5):

  | Строка | Проверка | Критерий (кратко) |
  |---|---|---|
  | P-01 | `core/no-tool-bypasses-gate`, `acp/mcp-tool-permission` | `session/request_permission` приходит до обращения к MCP-серверу; после отказа сервер вызова не получил |
  | P-16 | `acp/mcp-result-fenced`, `core/mcp-tool-cannot-declare-trusted` | весь результат MCP-инструмента внутри одной ограды, поддельный маркер экранирован; «доверенный» MCP-инструмент регистрируется как недоверенный |
  | E-01 | `core/project-context-agents-md-leaf-first` | системный промпт содержит правила `AGENTS.md` от корня репозитория к `cwd` |
  | E-02 | `acp/mcp-stdio-tool-call` | вызов `mcp__fake__echo` после одобрения — `completed` с «hi»; после закрытия сессии процесс сервера завершён |
  | E-03 | `acp/mcp-http-tool-call` | HTTP-инструмент вызывается; сервер неподдерживаемого типа пропущен с `mcp.server.skipped`, сессия создана |
  | E-05 | `core/mcp-tool-name-sanitized` | `mcp__my_srv__get_issue`; длинное имя — ровно 64 символа и уникально; коллизия имён отключает сервер с причиной, называющей оба источника, сессия создаётся (HOST-5; `mcp.server.failed`) |
  | K-02 | `acp/slash-compact` | `/compact` даёт отчёт «сжато: X → Y токенов» и запись сжатия в журнале (сценарий палитры app — R-20, этап 5) |
  | R-07 | `acp/available-commands-no-tools` | в `available_commands_update` только команды, без инструментов модели |
  | R-08 | `acp/slash-help`, `acp/slash-mode-plan`, `acp/mcp-prompt-command` | встроенные команды агента и команды из MCP-промптов выполняются |
  | R-14 | `core/litellm-proxy-base-url` | LiteLLM Proxy как OpenAI-совместимый `baseUrl` из конфигурации |
  | R-15 | `core/agent-definition-markdown-frontmatter`, `acp/set-config-option-agent` | опция `agent` содержит определение из `.codelab/agents/*.md`, многострочный `tools` разобран, битый YAML — диагностика с именем файла |
  | R-16 | `core/config-legacy-found-warning` | `codelab.toml` не читается: без `config.yaml` — одно предупреждение `config.legacy_found` с путём и ссылкой на таблицу ручного переноса §15.7; при `config.yaml` предупреждения нет. Изменено решением пользователя 2026-10-29 (change `add-agent-configuration`); строки DF-12 и DF-15 — `core/config-rejects-yaml-agent-definitions`, `core/config-unknown-provider-error` |
  | R-24 | `acp/session-new-with-mcp` | сервер из `session/new.mcpServers` подключается, его инструмент доступен модели в этой сессии; на этапе 4 такие серверы только пропускались с `mcp.server.skipped` (R-02) |
* 8.9 (MVP): `secret_resolver_test.dart`, `secret_store_backends_test.dart`,
  `debug_secrets_test.dart` зелёные; `codelab secret set codelab/openai` с ключом из stdin, затем
  `codelab -p` во встроенном режиме (этап 7) использует ключ; значение секрета не встречается в
  логах, trace и argv дочерних процессов.
* Если сделано (8.10, Should — не блокирует MVP): `config_writer_test.dart`,
  `config_writer_atomic_test.dart`, `config_watcher_test.dart`, `config_reload_test.dart`,
  `mcp_reconnect_test.dart` (`core/mcp-reconnect-after-crash`, E-04), `mcp_apply_config_test.dart`,
  `settings_registry_complete_test.dart` (`core/settings-registry-complete`, E-15),
  `provider_preconfig_env_test.dart` (`core/provider-preconfig-from-env`, L-25),
  `cli_config_commands_test.dart` и фикстура `acp/slash-mcp-list` зелёные.
* Если сделано (8.11, Should — не блокирует MVP): `core/redaction-before-journal`,
  `core/redaction-preserves-line-count`, `core/redaction-write-results-exempt` зелёные; журнал
  сессии с выводом `exec env` и `read .env` не содержит значений секретов.

**Зависимости.** Этап 4; задачи 8.5–8.9 не зависят от MCP и идут параллельно; 8.11 — после
8.5 и 8.9 (ключи `redact.*` и источник `SecretStore`). Этап 7 ждёт
8.5 и 8.9 (порядок D3: `{6, 8} → 7`); 8.10 его не блокирует.

**Риски.** Нет зрелого MCP SDK на Dart — свой клиент (протокол небольшой); готовые пакеты pub.dev
проверяются в начале этапа по чек-листу выше. MCP-серверы с побочными эффектами — вид инструмента по аннотациям,
неизвестный вид требует одобрения всегда.

---

← [9.12. Этап 7 — Встроенный режим в обоих клиентах](09-12-stage-7-embedded.md) · [Оглавление](../dart-agent-and-clients.md) · [9.14. Этап 9 — Цели Must и переключение по умолчанию](09-14-stage-9-switch-default.md) →
