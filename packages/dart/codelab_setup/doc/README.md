# Руководство по `codelab_setup`

Руководство для разработчика объясняет, как устроен мост настроек `codelab_setup`: что в нём лежит, почему он вырос в девять тысяч строк, как клиенты читают и пишут конфигурацию Dart-агента через его порты и виды и куда добавлять новое. Прочитав его, вы понимаете путь от снимка конфига до записи провайдера или MCP-сервера и знаете, где менять код под свою задачу.

Руководство описывает код как он есть. Нормы лежат в спецификации [`client-agent-setup`](../../../../openspec/specs/client-agent-setup/spec.md) и в правилах [`AGENTS.md`](../AGENTS.md) пакета; проектные документы в `docs/architecture/proposals/` писались до кода и могут с ним расходиться — прав код. Общий обзор пакета и быстрый старт — в [README пакета](../README.md).

Семантику конфигурации ядра (слои, слияние, доверие, перезагрузка) руководство не повторяет: её описывает [глава ядра о конфигурации](../../codelab_agent_core/doc/09-config-prompts-commands.md). Чтение файлов, подкоманды и хранилища секретов — в [`codelab_agent_io`](../../codelab_agent_io/README.md).

## Порядок чтения

Для первого знакомства читайте подряд:

0. [Начало работы](00-getting-started.md) — подготовка, тесты, проверка кода без настоящего провайдера, карта «что изменить — куда смотреть».
1. [Обзор](01-overview.md) — почему пакет большой, карта модулей, два барелья, web-безопасность, потребители, инварианты, словарь.
2. [Хранилище конфигурации](02-config-store.md) — доступ к настройкам, снимок, порт `AgentConfigStore`, исходы записи.

Остальные главы читайте по нужной теме, в любом порядке.

## Главы

| Глава | О чём |
|---|---|
| [00. Начало работы](00-getting-started.md) | подготовка репозитория, запуск тестов, пример мастера на фейках, подробный лог, «что изменить — куда смотреть» |
| [01. Обзор](01-overview.md) | зачем и из чего состоит пакет, карта `lib/src/`, барели `codelab_setup.dart` и `io.dart`, правила сторожа, кто использует мост |
| [02. Хранилище конфигурации](02-config-store.md) | `resolveSettingsAccess`, `AgentConfigSnapshot`, источники ключей, `AgentConfigStore`, `FileAgentConfigStore`, исходы записи |
| [03. Мастер провайдера](03-provider-wizard.md) | автомат `ProviderSetupFlow`, шаги и события, план записи, проверка `/models`, порядок «секрет, конфиг», удаление, готовность |
| [04. MCP-серверы](04-mcp-servers.md) | форма `McpServerDraft`, запись и откат, удаление и очистка секретов, «Disable here», перезапуск агента |
| [05. Расширения агента](05-agent-extensions.md) | вид навыков, цепочка `AGENTS.md`, шаблоны, правило записи списков навыков, таблица определений агентов |
| [06. Представления](06-views.md) | `ProviderEntryView`, `KeyStatusView`, `SettingFieldView`, правила правки, умолчания сессии, строка MCP-сервера |
| [07. Тестирование](07-testing.md) | уровни тестов, фейки и `RealHome`, приёмы, web-smoke, сторож |
| [08. Рецепты расширения](08-extending.md) | новый ключ, пресет, код ошибки, шаг мастера, поле MCP-формы, вид провайдера, реэкспорт |
| [09. Частые проблемы](09-troubleshooting.md) | симптомы, причины, что сделать; события журнала |

## Кому что читать

| Задача | Главы |
|---|---|
| понять, зачем нужен пакет и как он связан с клиентами | 01, 02 |
| подключить мост к новому клиенту | 01, 02, 03, 06 |
| изменить мастер провайдера | 03, 07, 08 |
| изменить проверку `/models` | 03, 07, 08 |
| изменить запись или удаление MCP-сервера | 04, 07 |
| изменить страницу навыков или таблицу агентов | 05, 06 |
| показать новое поле в таблице настроек | 06, 08 |
| начать работу с кодом и запустить тесты | 00, 07, 09 |
| диагностировать сбой записи или проверки | 02, 03, 09 |

## Смежные документы

- Сквозной разбор настроек: [сторона агента](../../codelab_agent_core/doc/algorithms/settings.md) (слои, перезагрузка, ACP, подключение) и [сторона клиента](../../codelab_client_core/doc/settings-on-client.md).
- Пакеты агентской стороны: [`codelab_agent_core`](../../codelab_agent_core/README.md) и его [руководство](../../codelab_agent_core/doc/README.md), [`codelab_agent_io`](../../codelab_agent_io/README.md), [`codelab_embedded`](../../codelab_embedded/README.md).
- Клиенты, использующие мост: [`apps/codelab_cli`](../../../../apps/codelab_cli/README.md) ([разработка](../../../../apps/codelab_cli/doc/01-overview.md)) и [`apps/codelab_desktop`](../../../../apps/codelab_desktop/README.md) ([разработка](../../../../apps/codelab_desktop/doc/01-overview.md)).
- Для пользователя и эксплуатации: [настройка агента](../../../../docs/user/configuration.md), [`CODELAB_HOME`](../../../../docs/ops/codelab-home.md).
- Архитектура: [слои и зависимости](../../../../docs/architecture/layers-and-dependencies.md), [тестирование](../../../../docs/architecture/testing.md), [ADR-0002 об именах пакетов](../../../../docs/architecture/adr/0002-name-packages-codelab-side-layer.md), [состав моста](../../../../docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md).
- Спецификации: [`client-agent-setup`](../../../../openspec/specs/client-agent-setup/spec.md), [`agent-configuration`](../../../../openspec/specs/agent-configuration/spec.md), [`agent-secrets`](../../../../openspec/specs/agent-secrets/spec.md), [`app-settings`](../../../../openspec/specs/app-settings/spec.md), [`workspace-architecture`](../../../../openspec/specs/workspace-architecture/spec.md).
