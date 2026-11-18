# Порты и сборка ядра хостом

Документ для разработчика хоста: того, кто собирает ядро в своём процессе. Обзор пакета — в [README](../README.md).

Ядро не создаёт ничего внешнего (PKG-6): файлы, процессы, HTTP-клиент, время, случайность, хранилища и вопрос пользователю приходят от хоста. Всё это передаётся одним объектом `AgentCoreServices` (`lib/src/host/services.dart`) в `buildAgentCore` (`lib/src/host/build_agent_core.dart`).

## Поля `AgentCoreServices`

Обязательные поля:

| Поле | Тип порта | Для чего |
|---|---|---|
| `baseEnv` | `ExecutionEnv` | файлы и процессы; сессия оборачивает его в `BoundedEnv` с корнем `cwd` |
| `logger` | `Logger` | журнал диагностики; значения секретов в него не попадают |
| `clock` | `Clock` | время и таймеры; в тестах — `FakeClock` |
| `ids` | `IdGenerator` | идентификаторы сессий и записей журнала |
| `sessions` | `SessionStore` | хранилище журнала; обязательно, журнал пишется всегда |

Необязательные поля. Значение `null` выключает соответствующую возможность или оставляет поведение по умолчанию.

| Поле | Что даёт, если задано |
|---|---|
| `gate` (`PermissionGate`) | интерактивные вопросы пользователю; без него capability `interactiveApproval` выключена, любой вопрос — отказ |
| `platform` | строка (`linux`, `macos`, `windows`, `web`) для системного промпта |
| `models` (`ModelCatalog`) | каталог моделей; иначе каталог из одной `CoreConfig.defaultModel` |
| `mcp` (`McpConnector`) | подключение MCP-серверов; без него capability `mcp` выключена |
| `projectFiles`, `skillFiles` | `AGENTS.md`/`CLAUDE.md`, шаблоны команд, определения агентов и навыки |
| `hostFiles` | файловая система процесса агента для корней навыков вне рабочей папки (только чтение) |
| `secrets` (`SecretResolver`) | разбор ссылок `${secret:…}` в `env` и заголовках MCP-серверов |
| `config` (`ConfigSource`), `projectConfig` (`ProjectConfigLoader`) | перезагрузка конфигурации и своя конфигурация для папки сессии |
| `agentConfigPaths` | пути конфигурации агента, которые модель не правит без человека (PERM-11) |
| `lastModel` (`LastModelStore`) | память последней выбранной модели |
| `usageLedger` (`UsageLedgerStore`) | файл журнала расхода; без него отчёт `usage` строится в памяти |

## Профиль и capabilities

`HostProfile.of(name)` знает три встроенных профиля: `agent-serve`, `embedded-cli`, `embedded-app-desktop` (`lib/src/host/host_profile.dart`). Профиль задаёт состояние каждой `HostCapability`: `shellExec`, `fileListing`, `interactiveApproval`, `compaction`, `sessionPersistence`, `mcp`, `skills`. Состояние — `CapabilityOn`, `CapabilityOff(reason)` или `CapabilityTransport` (допустимые транспорты). Режим по умолчанию у всех трёх профилей — `ModeId.standard`.

`buildAgentCore` сужает профиль по переданным портам и конфигурации (`profile.narrowed`) и пишет в лог запись `host.plan` с включёнными инструментами и причинами выключенного. Сужать можно только вниз: включить выключенное нельзя. Результат — `BuiltAgentCore.plan` (`CorePlan`: `toolNames`, `promptSections`, `offReasons`).

Ошибки связки (`HostWiringException`) бросаются при сборке:

- `AgentCoreServices.config` или `projectConfig` без `modelsFor`;
- `sessionPersistence` включена, а `sessions` — `MemorySessionStore`;
- `shellExec` включена, а `baseEnv` — `MemoryExecutionEnv`;
- `McpConnector` не умеет транспорт, который требует профиль.

Нет листинга каталога у `baseEnv` (не `DirectoryListing`) — инструменты `ls` и `search` не регистрируются, это не ошибка.

## Реализации в монорепо

| Порт | Реализация | Пакет |
|---|---|---|
| `ExecutionEnv` | `LocalExecutionEnv` | `codelab_agent_io` |
| `ExecutionEnv` | `AcpClientExecutionEnv` | `codelab_agent_acp` |
| `SessionStore` | `JsonlSessionStore` | `codelab_agent_io` |
| `PermissionGate` | `AcpPermissionGate` | `codelab_agent_acp` |
| `ConfigSource`, `ProjectConfigLoader` | `FileConfigSource` | `codelab_agent_io` |
| `ProjectFilesSource`, `SkillFilesSource` | `ProjectFilesLoader` | `codelab_agent_io` |
| `McpConnector` | `McpClientConnector` | `codelab_agent_mcp` |
| `SecretStore` | `FileSecretStore`, `EnvSecretStore` | `codelab_agent_io` |
| `UsageLedgerStore` | `JsonlUsageLedgerStore` | `codelab_agent_io` |
| `LastModelStore` | `FileLastModelStore` | `codelab_agent_io` |

Встроенный агент собирает те же порты в `codelab_embedded`: основной барель web-безопасен, `lib/io.dart` — настольный открыватель, `lib/testing.dart` — сценарный (AGENTS.md репозитория §5).

## Модель

Функцию модели хост передаёт в `buildAgentCore(streamFunction: …)`. Контракт `StreamFunction` (`lib/src/llm/stream_function.dart`): вернуть поток синхронно и не бросать исключений, любой сбой — событие `ErrorEvent`; у потока ровно одно завершающее событие; отмена даёт `ErrorEvent` с `stopReason: aborted`. Для настоящих провайдеров хост вызывает `createStreamFunction(config, services)` или `createRoutedStreamFunction` для нескольких провайдеров; `http.Client` создаёт хост. Адаптеры провайдеров наружу не экспортируются (PKG-5).

В тестах функцию модели заменяет `ScriptedStreamFunction` из `package:codelab_agent_core/testing.dart`: n-й запрос получает n-й шаг сценария, расхождения копятся, `verify()` бросает `ScriptedLlmFailure` со всеми.
