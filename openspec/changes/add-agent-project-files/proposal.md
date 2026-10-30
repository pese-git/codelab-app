## Why

Dart-агент не учитывает файлы, которые пользователь и проект кладут рядом с кодом: правила `AGENTS.md`/`CLAUDE.md` не попадают в системный промпт (E-01, Must), шаблоны промптов не становятся slash-командами (E-07), а определения агентов в Markdown не читаются вовсе (R-15, Must). `available_commands_update` после `session/new` всегда пуст (`agent-acp-server`, «session/new», шаг 5), и критерий R-07 (`acp/available-commands-no-tools`) открыт. Python-агент CodeLab определения агентов поддерживал, а `codelab.toml` с `[agents.definitions.*]` новым агентом не читается (change `add-agent-configuration`, D12): без этого change пользователь теряет специализированных агентов при переходе.

Change закрывает задачи 8.6–8.8 этапа 8 (`09-13-stage-8-mcp-config.md`). Конфигурация (8.5) уже даёт всё, что нужно: доверие к проекту (`trusted_projects`, CFG-3), строгий профиль YAML (`readYamlTree`, CFG-21) и каталог моделей.

## What Changes

- **Инструкции проекта (8.6, E-01).** При создании и загрузке сессии агент читает `AGENTS.md` от `cwd` вверх до корня git-репозитория (без репозитория — только `cwd`) и `$CODELAB_HOME/AGENTS.md`. На уровне без `AGENTS.md` читается `CLAUDE.md` (алиас, решение пользователя 2026-10-30). Файлы идут в новую секцию системного промпта `project_context` от общего к частному. Общий бюджет — `tools.project_context.max_bytes` (по умолчанию 32 КиБ) — раздаётся от ближнего файла к дальнему; файл, который не поместился, усекается по границе строки с пометкой `[file truncated: showing N of M bytes]`. Файлы читаются и для недоверенного проекта (D4).
- **Slash-команды из шаблонов (8.7, E-07).** Шаблоны `$CODELAB_HOME/prompts/*.md` читаются всегда, `<cwd>/.codelab/prompts/*.md` — только для проекта из `trusted_projects`. Frontmatter необязателен: `description`, `argument-hint`. Тело — шаблон с `$ARGUMENTS`, `$1`…`$9`, `$$`. Список уходит в `available_commands_update` после ответа `session/new` и в реплее `session/load`; инструментов модели в нём нет (R-07). Промпт `/<имя> <аргументы>` разворачивается в ядре в сообщение пользователя. Запись журнала получает поле `command`, и реплей показывает исходный текст команды.
- **Определения агентов в Markdown (8.8, R-15).** Файлы `$CODELAB_HOME/agents/*.md` и `<cwd>/.codelab/agents/*.md` (второй каталог — только для доверенного проекта, CFG-6). YAML-frontmatter разбирается пакетом `yaml` в `codelab_agent_io` в том же строгом профиле, что `config.yaml`; поля: `name`, `description`, `model`, `mode`, `tools`, `scope`. В ACP появляется опция конфигурации `agent` (`default` и определения). Выбор агента:
  - добавляет секцию промпта `agent_profile` с телом файла; правила безопасности и ограды базового промпта остаются (CFG-8);
  - меняет модель;
  - меняет режим, но только если это не смягчает режим конфига (D11; решение пользователя 2026-10-30);
  - сужает набор инструментов (CFG-7).

  Выбор пишется в журнал (`config_change {optionId: "agent"}`) и восстанавливается при `session/load`. Определения `[agents.definitions.*]` из `codelab.toml` пользователь переносит вручную (§15.7).
- **Общий загрузчик файлов проекта.** В ядре появляется порт `ProjectFilesSource` (`AgentCoreServices.projectFiles`); реализация `ProjectFilesLoader` живёт в `codelab_agent_io`. Чтение идёт через локальный `ExecutionEnv` хоста под `BoundedEnv` корня своей области (D2): путь или symlink наружу отклоняется. В `serve --ws` загрузчик не подключается: клиент WebSocket выбирает `cwd`, а читать пришлось бы файлы машины агента (решение пользователя 2026-10-30; D2, D16). Лимиты размера и числа файлов, ошибки кодировки и битый frontmatter дают диагностику, а не исключение; загрузка ограничена таймаутом 5 с: сессия создаётся всегда (D6).
- **Конфигурация.** Ключ `tools.project_context.max_bytes` получает потребителя: диапазон `0..262144`, `0` выключает секцию. Из недоверенного проекта значение принимается только на уменьшение. В `CoreConfig` появляется список `trustedProjects` (канонические корни).
- **`config check`** печатает диагностику определений агентов и шаблонов команд для `--cwd` строками `warning:`. Коды выхода не меняются (D13).
- **Наблюдаемость:** события `project_context.loaded`, `commands.loaded`, `agents.loaded`, `project_files.diagnostic`, `project_files.skipped`, `command.expanded`, `agent.selected`, `agent.mode.not_applied`, `agent.definition.missing` (D14). Содержимое файлов и аргументы команд в лог не попадают.

Не входит:
- встроенные команды агента `/help`, `/status`, `/mode`, `/model`, `/compact`, MCP prompts как команды и ответ «Unknown command» без вызова модели (R-08, K-02): по решению пользователя 2026-10-30 (OQ1) — отдельный change. До него промпт `/x` без шаблона `x` уходит модели как раньше;
- skills, инструмент `skill`, `/skill:<name>`, закреплённые строки operative (§17.2, E-06, K-06 — после MVP);
- `prompts.templates`, `prompts.templates_dirs`, каталоги шаблонов других агентов (§17.2.8, после MVP);
- дополнительные файлы контекста `prompts.context_files` — `GEMINI.md`, `.github/copilot-instructions.md` (E-17, Should): ключ по-прежнему даёт `config.key.not_applied`;
- импорт `@path` внутри `CLAUDE.md`/`AGENTS.md`: такая строка остаётся текстом;
- встроенные профили `architect` и `review` (§17.12.2), определения для субагентов (`scope: subagent` загружается, но в опцию `agent` не попадает; инструмент `task` — §17.3);
- перечитывание файлов посреди сессии, наблюдатель файлов, `/config reload` (8.10);
- изменения ACP: новых методов, полей, `_meta` и значений перечислений нет. Используются `available_commands_update` (`14-Slash Commands.md`) и опция `select` (`13-Session Config Options.md`), уже типизированные в `codelab_acp_protocol`.

## Capabilities

### New Capabilities
- `agent-project-context`: поиск и чтение `AGENTS.md`/`CLAUDE.md`, бюджет и усечение, граница чтения, секция `project_context`, ключ `tools.project_context.max_bytes`.
- `agent-slash-commands`: шаблоны промптов как slash-команды — каталоги и доверие, формат и имена, резервные имена, разбор и подстановка аргументов, разворачивание в ядре, поле журнала `command`.
- `agent-definitions`: определения агентов в Markdown — каталоги и доверие, строгий frontmatter, проверка полей, выбор агента (промпт, модель, режим, инструменты), журнал и восстановление.

### Modified Capabilities
- `agent-prompts`: в порядок сборки системного промпта добавляются секции `project_context` и `agent_profile`.
- `agent-runtime`: порт `ProjectFilesSource`; файлы проекта читаются при создании и загрузке сессии; новые члены `AgentSession` — `commands`, `agents`, `agent`, `setAgent`.
- `agent-acp-server`: `available_commands_update` несёт команды сессии; реплей команды показывает исходный текст; опция `agent` и её обработка в `session/set_config_option`.
- `agent-configuration`: потребитель и правило доверия ключа `tools.project_context.max_bytes`; `CoreConfig.trustedProjects`; `config check` показывает диагностику файлов проекта.
- `agent-sessions`: поле записи `command` у сообщения пользователя, полученного из шаблона.
- `agent-binary`: `serve --stdio` передаёт ядру `ProjectFilesLoader` с `$CODELAB_HOME` процесса; `serve --ws` файлы проекта не читает.
- `acp-golden-fixtures`: фикстуры `acp/prompt-template-command`, `acp/available-commands-no-tools`, `acp/set-config-option-agent`; агентский драйвер принимает `trusted_projects` с `${cwd}`.

## Impact

- **Пакеты:**
  - `codelab_agent_core`: `lib/src/project/` (порт, `ProjectContext`, диагностика), `lib/src/commands/`, `lib/src/agents/`; правки `prompts/compose.dart`, `runtime/agent_runtime.dart`, `runtime/agent_session.dart`, `session/records.dart`, `config/` (ключ, `trustedProjects`); новые промпты `prompts/project_context.md`, `prompts/project_context_file.md`, `prompts/agent_profile.md`;
  - `codelab_agent_io`: `lib/src/project/` (`ProjectFilesLoader`, отделение frontmatter); `cli/config_commands.dart`;
  - `codelab_agent_acp`: `agent_server.dart`, `session_bridge.dart`, `config_options.dart`, `replay.dart`; тест-фабрика conformance;
  - `apps/codelab_agent`: `host/agent_host.dart`;
  - `codelab_acp_testing`: три фикстуры;
  - `apps/codelab_cli`: только тест вывода `codelab config check`.
- **Клиенты** (app, CLI) не меняются. Они уже показывают команды из `available_commands_update` (`CommandCatalog`, change `add-command-palette-agent-commands`). Опцию `agent` desktop выводит общим селектором `configOptions`, CLI — командой `/config agent <имя>`.
- **Public API ядра** — только добавления; используемые сигнатуры не меняются.
- **Зависимости** не добавляются: `yaml` уже в `codelab_agent_io` (change `add-agent-configuration`, D2). PKG-2 не расширяется, ядро остаётся web-безопасным. Новое правило сторожа не нужно: новые каталоги лежат в существующих пакетах, и их уже покрывают PKG-1 и CFG-5.
- **Журнал:** новое необязательное поле записи `command`. Старые журналы читаются без изменений; старое ядро сохраняет поле в `extra` (совместимость вперёд, §8).
- **Документы:** `agent-core/11-prompts.md` §11.2, §11.5, §11.7; `15-configuration.md` §15.4, §15.8; `17-2-skills-and-templates.md` §17.2.2, §17.2.6; `08-sessions.md` §8.2.3; `12-observability-and-errors.md` §12.2; `05-agent-loop.md` §5.3; `09-13-stage-8-mcp-config.md` (пункты 6–8, имя change, DoD); `agent-parity-goals.md` (E-01, E-07, R-07, R-15).
- **Матрица целей:** E-01 (`core/project-context-agents-md-leaf-first`), E-07 (`acp/prompt-template-command`), R-15 (`core/agent-definition-markdown-frontmatter`, `acp/set-config-option-agent`). R-07 закрывается частично (`acp/available-commands-no-tools`): встроенные команды и MCP prompts в списке добавит change встроенных команд (решение пользователя 2026-10-30, OQ1).
