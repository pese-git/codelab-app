# Руководство по пакету `codelab_agent_io`

Руководство для разработчика объясняет, как устроен `codelab_agent_io`: реализации портов ядра агента на `dart:io`, форматы файлов на диске, защита от чужих пользователей и ссылок, общие подкоманды `config`, `provider`, `mcp`, `secret`. Прочитав его, вы знаете, где пакет читает и пишет файлы, чем гарантируется атомарная запись и контейнмент, и понимаете, куда добавить переменную окружения, подкоманду, бэкенд секретов или защищаемый файл.

Руководство описывает код как он есть. Проектные документы в [`docs/architecture/proposals/`](../../../../docs/architecture/proposals/) объясняют, почему решения приняты так, но писались до кода и местами расходятся с ним: если они спорят, прав код. Нормы лежат в спецификациях [`openspec/specs/`](../../../../openspec/specs/) и в инвариантах [`AGENTS.md`](../AGENTS.md) пакета. Общий обзор пакета и быстрый старт — в [README пакета](../README.md).

Руководство **не повторяет** [руководство по ядру агента](../../codelab_agent_core/doc/README.md): сборку ядра и хосты, путь запроса, цикл хода, разрешения, схему конфигурации и семантику сессий читайте там. Здесь — только то, что делает io-сторона.

## Порядок чтения

Для первого знакомства читайте подряд:

0. [Начало работы](00-getting-started.md) — подготовка репозитория, тесты, подкоманды без модели, пример загрузчика и писателя, отладка, «что изменить — куда смотреть».
1. [Обзор](01-overview.md) — зачем пакет, порты ядра, карта `lib/src/`, общие правила кода, словарь.

Остальные главы читайте по нужной теме, в любом порядке.

## Главы

| Глава | О чём |
|---|---|
| [00. Начало работы](00-getting-started.md) | подготовка репозитория, тесты пакета, подкоманды в изолированном `CODELAB_HOME`, загрузчик и писатель из кода, отладка, карта «что изменить — куда смотреть» |
| [01. Обзор](01-overview.md) | назначение пакета, кто его вызывает, порты ядра и реализации, карта модулей, два барелья, зависимости, общие правила, словарь |
| [02. Файлы и процессы](02-environment-and-processes.md) | `LocalExecutionEnv`: пути ядра и хоста, ошибки как значения, жизненный цикл `exec`, окружение процесса, кольцевой буфер, завершение дерева процессов |
| [03. Загрузка конфигурации](03-config-loading.md) | `ConfigLoader`: слои и источники, `codelabHomeOf`, чтение файла, строгий профиль YAML, ссылки проектных слоёв, слой окружения, предконфигурация провайдера, `codelab.toml`, проверка кандидата |
| [04. Запись и перезагрузка](04-config-writing-and-reload.md) | `ConfigWriter`: блокировка, отпечаток, правка с сохранением формата, проверка перед записью; `ConfigWatcher` и `FileConfigSource`; `agentConfigPathsFor` (PERM-11) |
| [05. Секреты](05-secrets.md) | бэкенды `env` и `file`, защита `secrets.yaml`, `SecretProcessRunner`, `SecretAdmin`, `ClientSecretAccess`, `SecretMigrator` |
| [06. Сессии и состояние](06-sessions-and-state.md) | `JsonlSessionStore` (раскладка, очередь записи, `fsync`, карантин, isolate), `index.json`, журналы потомков, `JsonlUsageLedgerStore`, `FileLastModelStore` |
| [07. Файлы проекта](07-project-files.md) | `ProjectFilesLoader`: инструкции, шаблоны, агенты, навыки; граница `BoundedEnv`, лимиты, диагностика, frontmatter, корни навыков |
| [08. MCP stdio](08-mcp-stdio.md) | `StdioMcpTransportFactory` и `StdioProcessTransport`: запуск, кадры, stderr, закрытие дерева процессов |
| [09. Подкоманды](09-subcommands.md) | `ConfigCommands`, `ProviderCommands`, `McpServerCommands`, `SecretCommands`, `ConfigEditRunner`, коды выхода, маскирование, ввод секрета |
| [10. Сценарий модели](10-scripted-model.md) | барель `testing.dart`: `LlmScript`, `withScriptedProviders`, `CwdTrackingStore`, `rewriteUntil` |
| [11. Расширение](11-extending.md) | рецепты: переменная окружения, подкоманда записи, защищаемый файл, бэкенд секретов, каталог Markdown, файловое состояние, событие журнала |
| [12. Тестирование](12-testing.md) | уровни тестов, контракты ядра, изоляция, фейки и швы, как писать тест, какие проверки запускать |
| [13. Частые проблемы](13-troubleshooting.md) | симптомы, причины и что сделать; таблица событий журнала пакета |

## Кому что читать

| Задача | Главы |
|---|---|
| понять, что делает пакет и где его границы | 01 |
| начать работу с кодом, запустить и отладить | 00, 12, 13 |
| изменить чтение конфигурации или слоёв | 03, 11 |
| изменить запись конфигурации, блокировку, наблюдателя | 04 |
| добавить подкоманду или изменить её вывод | 09, 11 |
| добавить переменную окружения | 03, 11 |
| изменить хранилище секретов или перенос | 05, 11 |
| разобраться в журнале сессии на диске | 06 |
| изменить чтение `AGENTS.md`, шаблонов, агентов, навыков | 07 |
| запуск MCP-серверов | 08 |
| как инструменты запускают команды | 02 |
| сценарий модели в тестах | 10, 12 |
| диагностировать отказ в проде | 13 и [для администратора](../../../../docs/ops/codelab-home.md) |

## Смежные документы

- Ядро: [руководство по ядру агента](../../codelab_agent_core/doc/README.md) — [сборка и хосты](../../codelab_agent_core/doc/02-assembly-and-hosts.md), [инструменты и `ExecutionEnv`](../../codelab_agent_core/doc/06-tools.md), [сессии](../../codelab_agent_core/doc/08-sessions-and-compaction.md), [конфигурация, файлы проекта, секреты](../../codelab_agent_core/doc/09-config-prompts-commands.md), [тестирование ядра](../../codelab_agent_core/doc/12-testing.md).
- Пакеты агентской стороны: [`codelab_agent_core`](../../codelab_agent_core/README.md), [`codelab_agent_mcp`](../../codelab_agent_mcp/README.md), [`codelab_embedded`](../../codelab_embedded/README.md), [`codelab_setup`](../../codelab_setup/README.md), [`apps/codelab_agent`](../../../../apps/codelab_agent/README.md).
- Для пользователя и администратора: [настройка агента](../../../../docs/user/configuration.md), [запуск из исходников](../../../../docs/user/run-from-source.md), [каталог `CODELAB_HOME`](../../../../docs/ops/codelab-home.md), [переменные окружения](../../../../docs/ops/environment.md), [эксплуатация агента](../../../../apps/codelab_agent/doc/operations.md).
- Архитектура: [`agent-core-architecture`](../../../../docs/architecture/proposals/agent-core-architecture.md), [слои и зависимости](../../../../docs/architecture/layers-and-dependencies.md), [тестирование](../../../../docs/architecture/testing.md).

## Спецификации и нормы

Источник истины о поведении — спецификации в [`openspec/specs/`](../../../../openspec/specs/):

| Тема | Спецификация |
|---|---|
| конфигурация (слои, строгий профиль, запись, перезагрузка) | [`agent-configuration`](../../../../openspec/specs/agent-configuration/spec.md) |
| секреты (бэкенды, `secret`, перенос) | [`agent-secrets`](../../../../openspec/specs/agent-secrets/spec.md) |
| сессии и журнал | [`agent-sessions`](../../../../openspec/specs/agent-sessions/spec.md) |
| окружение исполнения | [`agent-execution-env`](../../../../openspec/specs/agent-execution-env/spec.md) |
| файлы проекта и инструкции | [`agent-project-context`](../../../../openspec/specs/agent-project-context/spec.md) |
| определения агентов | [`agent-definitions`](../../../../openspec/specs/agent-definitions/spec.md) |
| навыки | [`agent-skills`](../../../../openspec/specs/agent-skills/spec.md) |
| MCP-клиент (stdio-транспорт) | [`agent-mcp-client`](../../../../openspec/specs/agent-mcp-client/spec.md) |
| разрешения (PERM-11) | [`agent-permissions`](../../../../openspec/specs/agent-permissions/spec.md) |
| порты ядра | [`agent-core-ports`](../../../../openspec/specs/agent-core-ports/spec.md) |
| встроенный агент и сценарий модели | [`embedded-agent`](../../../../openspec/specs/embedded-agent/spec.md) |
| настройка агента клиентами | [`client-agent-setup`](../../../../openspec/specs/client-agent-setup/spec.md) |
| тестирование и качество | [`testing-quality`](../../../../openspec/specs/testing-quality/spec.md) |

Правила пакета — в [`AGENTS.md`](../AGENTS.md) (границы, allowlist зависимостей, тесты) и в [`AGENTS.md` ядра](../../codelab_agent_core/AGENTS.md).
