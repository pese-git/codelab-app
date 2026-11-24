# Начало работы с кодом MCP-клиента

Эта глава для разработчика, который впервые открыл `codelab_agent_mcp`. Она отвечает на практические вопросы: как прогнать тесты, как увидеть, что клиент и сервер говорят друг другу, как отладить сбой подключения и в какой файл идти с задачей. Устройство пакета объясняют следующие главы.

Что такое MCP и как сервер попадает в конфигурацию, здесь не повторяется. Пользовательская сторона — в разделе [«MCP-серверы»](../../../../docs/user/configuration.md#mcp-серверы). Как ядро агента вызывает коннектор и показывает инструменты модели — в [главе 06 руководства по ядру](../../codelab_agent_core/doc/06-tools.md#mcp).

## Подготовка

Пакет — чистый Dart без `dart:io`, Flutter и ACP. Для его тестов не нужны сгенерированные файлы: достаточно связанного workspace. Если репозиторий ещё не подготовлен, выполните шаги из [запуска из исходников](../../../../docs/user/run-from-source.md#1-подготовка) (`fvm install`, `fvm flutter pub get`, `fvm dart run melos bootstrap`). Все команды Dart идут через `fvm`.

## Прогнать тесты

Команды выполняются в каталоге пакета:

```bash
cd packages/dart/codelab_agent_mcp
fvm dart test
```

Весь набор идёт несколько секунд: в нём нет процессов, сети и реального времени. На ветке документа прогон закончился строкой `All tests passed!` (322 теста).

Один файл или один тест:

```bash
fvm dart test test/mcp_client_connect_test.dart
fvm dart test test/supervisor/mcp_reconnect_test.dart --name "delays"
```

Две проверки вне пакета относятся к его границам:

| Команда | Когда |
|---|---|
| `fvm dart analyze` в пакете | всегда перед сдачей |
| `melos run guard` | если менялись `pubspec.yaml` или импорты: сторож запрещает пакету `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, Flutter, ACP-пакеты, клиентские пакеты и `codelab_agent_io` |

Реальный stdio-сервер проверяет не этот пакет, а `apps/codelab_agent`: в каталоге приложения `fvm dart test test/mcp_stdio_process_test.dart` запускает агента, настоящий процесс MCP-сервера и один вызов `mcp__fake__echo`. Тест проходит за несколько секунд.

## Увидеть, что говорят клиент и сервер

Сетевого трафика в тестах нет, но есть два зеркала: `FakeMcpServer.requests` хранит каждое сообщение клиента, а `RecordingLogger` из `package:codelab_agent_core/testing.dart` хранит записи лога. Этого достаточно, чтобы увидеть рукопожатие целиком. Ниже — вывод временного теста (в пакет он не добавлен): он подключает клиента к `FakeMcpServer` с одним инструментом через `McpHarness` из `test/support/harness.dart`, а затем печатает `server.requests` и `logger.records`.

Сервер современной эпохи (`FakeMcpServer(tools: [FakeMcpTool('echo', …)], listChanged: true)`), запросы клиента:

```text
{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{},"io.modelcontextprotocol/clientInfo":{"name":"codelab-agent","version":"0.1.0"}}}}
{"jsonrpc":"2.0","id":2,"method":"subscriptions/listen","params":{"notifications":{"toolsListChanged":true},"_meta":{…}}}
{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{"_meta":{…}}}
```

Записи лога того же подключения:

```text
info mcp.server.era {"session_id":"s1","server":"fake","transport":"stdio","era":"modern","protocol_version":"2026-07-28","probe":"discover_result"}
info mcp.server.connect {"session_id":"s1","server":"fake","transport":"stdio","era":"modern","protocol_version":"2026-07-28","server_info":{"name":"fake-mcp-server","version":"1.0.0"},"tools":1,"duration_ms":0}
```

Тот же клиент против `FakeMcpServer(era: FakeMcpEra.legacy, …)`. Клиент пробует `server/discover`, не получает ответа modern и переходит на `initialize`:

```text
{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{…}}}
{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"codelab-agent","version":"0.1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":3,"method":"tools/list"}
```

```text
info mcp.server.era {"session_id":"s1","server":"fake","transport":"stdio","era":"legacy","protocol_version":"2025-11-25","probe":"fallback_error"}
```

Вывод усечён (`{…}` вместо повтора `_meta`). Почему сообщения именно такие — в [главе 02](02-client-protocol.md).

## Отладка настоящего агента

Тесты пакета не запускают процесс агента. Если нужно посмотреть MCP-события в настоящем `codelab-agent`, включите подробный лог — способы описаны в [главе 00 руководства по ядру](../../codelab_agent_core/doc/00-getting-started.md#подробный-лог). События MCP начинаются с `mcp.`; уровень `debug` добавляет `mcp.server.state` (переходы автомата) и `mcp.message.ignored` (что клиент отбросил и почему). Полный список событий — в [главе 04](04-connector-and-supervisor.md#события-лога) и [главе 05](05-extending-and-troubleshooting.md#события-и-тексты-ошибок).

Состояние серверов сессии видно командой `/mcp list` в клиенте (колонки `ID`, `SOURCE`, `TRANSPORT`, `STATE`, `TOOLS`, `LAST ERROR`); она берёт данные из `McpSessionTools.servers`.

## Что изменить — куда смотреть

Пути внутри `packages/dart/codelab_agent_mcp/lib/src/`.

| Я хочу изменить | Открой | Читай |
|---|---|---|
| рукопожатие, определение эпохи, `tools/list`, подписку | `mcp_client.dart` | [02](02-client-protocol.md) |
| вызов `tools/call`, таймаут, отмену, тексты ошибок для модели | `mcp_client.dart` (`callTool`) | [02](02-client-protocol.md#вызов-инструмента) |
| разбор JSON-RPC, исходящие `id`, `_meta` | `json_rpc.dart` | [02](02-client-protocol.md#кодек-json-rpc) |
| модели ответов MCP (`tools/list`, `tools/call`, `server/discover`) | `protocol.dart` | [02](02-client-protocol.md) |
| HTTP: заголовки, SSE, сессия, возобновление, лимиты | `streamable_http.dart` | [03](03-streamable-http.md) |
| заголовки `Mcp-Param-*` из `x-mcp-header` | `mirror_headers.dart` | [03](03-streamable-http.md#зеркальные-заголовки) |
| задержку повтора, автомат состояний, коллизии имён, `replaceServers` | `connector.dart` | [04](04-connector-and-supervisor.md) |
| имя, описание и схему инструмента для модели, проекцию результата | `mcp_tool.dart` | [01](01-overview.md#как-инструмент-mcp-попадает-к-модели) |
| поведение фейкового сервера в тестах | `fake_mcp_server.dart`, `fake_mcp_http.dart` | [05](05-extending-and-troubleshooting.md#тестирование) |
| порты транспорта и коннектора | ядро: `codelab_agent_core/lib/src/mcp/` | [01](01-overview.md#порты-ядра) |

## Смотрите также

- [Обзор пакета](01-overview.md) — модули, порты, путь вызова.
- [`AGENTS.md` пакета](../AGENTS.md) — обязательные правила.
- [README пакета](../README.md) — краткое описание и пример сборки коннектора.
