# 9.13. Этап 8 — MCP, конфигурация, AGENTS.md

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.12. Этап 7 — Встроенный режим в обоих клиентах](09-12-stage-7-embedded.md) · [Оглавление](../dart-agent-and-clients.md) · [9.14. Этап 9 — Цели Must и переключение по умолчанию](09-14-stage-9-switch-default.md) →

**Цель.** Внешние инструменты через MCP проходят ту же точку проверки разрешений, что и
встроенные; конфигурация полная и проверяемая; агент учитывает инструкции проекта.

**Задачи.**

1. **8.1. Пакет `packages/dart/codelab_agent_mcp`:** `lib/src/protocol.dart`
   (`initialize`, `tools/list`, `tools/call`, `notifications/tools/list_changed`, порт транспорта),
   `lib/src/mcp_client.dart`, `lib/src/streamable_http.dart`.
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
5. **8.5. Конфигурация:** модель и валидация — `packages/dart/codelab_agent_core/lib/src/config/core_config.dart` (agent-core-architecture §1.3)
   (`CoreConfig`, `validate()` → список `ConfigIssue(path, message)`); загрузка —
   `packages/dart/codelab_agent_io/lib/src/config/config_loader.dart`. Порядок слоёв: значения по
   умолчанию < `~/.codelab/config.yaml` < `<cwd>/.codelab/config.yaml` <
   `<cwd>/.codelab/config.local.yaml` < переменные `CODELAB_*` < флаги командной строки
   (agent-core-architecture §15.2). Формат — YAML в строгом профиле (§15.5): разбор
   `package:yaml` с позициями ошибок, запись `package:yaml_edit` (§17.5.5). Старый `codelab.toml`
   Python-агента читается только для чтения и только пока нет ни одного YAML-файла
   (`lib/src/config/legacy/`, `package:toml`); при любом YAML-файле он игнорируется с
   предупреждением `config.legacy_ignored`, а пока он активен, запись конфига отклоняется
   (`ConfigLegacyReadOnlyException`). Команда `codelab config migrate [путь]` (и
   `codelab-agent config migrate`) пишет `config.yaml` с YAML-комментарием о каждом
   отброшенном ключе, `--print` — только печатает; `codelab.toml` не удаляется
   (agent-core-architecture §15.7; см. также §7б). Команды `codelab-agent config check` и
   `codelab config check`. Тесты: `core/config-reads-legacy-codelab-toml`,
   `config_yaml_profile_test.dart`, `config_legacy_ignored_test.dart`.
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
9. **8.9. Настройка агента** (L-25, P-12, E-15, E-04, P-17; agent-core-architecture §17.5):
   `SecretResolver` и бэкенды секретов, предконфигурация провайдера из окружения, `ConfigWriter`
   и подкоманды `config`/`provider`/`mcp`/`secret`, `ConfigWatcher` и живая перезагрузка,
   `McpSupervisor` с переподключением, `SettingsRegistry` с тестом полноты; агентские команды
   `/config` и `/mcp`. Клиентская часть (мастер, страницы настроек) — §12.4.

**OpenSpec change.** `add-agent-mcp-client` (8.1–8.4; scope: протокол MCP, транспорты, имена и
виды MCP-инструментов, проверка разрешений), `add-agent-configuration` (8.5; scope: файлы,
порядок слоёв, формат YAML и его профиль, чтение `codelab.toml` только для чтения, новые
зависимости `yaml_edit` и `toml` как решение о технологии по `AGENTS.md` §4), `add-project-instructions-and-commands` (8.6–8.8).

**Что прочитать.** Документ ядра §6, §7, §10 (capability `mcp`), §11, §15; спецификация MCP
(стандарт протокола, раздел о транспортах); `docs/acp/protocol/03-Session Setup.md`,
`14-Slash Commands.md`.

**Definition of Done.**

* `packages/dart/codelab_agent_mcp/test/mcp_tool_goes_through_policy_test.dart: MCP tool is not executed without a permission decision` (закрывает F5.1).
* `packages/dart/codelab_agent_mcp/test/streamable_http_test.dart` на `MockClient`.
* `packages/dart/codelab_agent_io/test/config/config_loader_test.dart: invalid config reports key path and line` — битый конфиг даёт ошибку с путём ключа, а не исключение при первом ходе.
* Фикстуры `acp/session-new-with-mcp`, `acp/available-commands-no-tools` зелёные.
* `melos run guard`: `codelab_agent_mcp` без `dart:io`.

**Зависимости.** Этап 4; задачи 8.5–8.7 не зависят от MCP и идут параллельно.

**Риски.** Нет зрелого MCP SDK на Dart — свой клиент (протокол небольшой); готовые пакеты pub.dev
проверяются в начале этапа. MCP-серверы с побочными эффектами — вид инструмента по аннотациям,
неизвестный вид требует одобрения всегда.

---

← [9.12. Этап 7 — Встроенный режим в обоих клиентах](09-12-stage-7-embedded.md) · [Оглавление](../dart-agent-and-clients.md) · [9.14. Этап 9 — Цели Must и переключение по умолчанию](09-14-stage-9-switch-default.md) →
