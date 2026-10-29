# AGENTS.md — codelab_agent_mcp

Правила этого пакета дополняют корневой `AGENTS.md` и `packages/dart/codelab_agent_core/AGENTS.md`.

Источники:
- `docs/architecture/proposals/agent-core-architecture.md` — §1.2 (пакеты и allowlist), §6.4 (MCP-инструменты), §10.3 (`AgentCoreServices.mcp`), §11.5 (секция `mcp`), §12.2 (события);
- `openspec/changes/add-agent-mcp-client/design.md` — решения D1–D15;
- нормативный текст MCP — `docs/protocols/mcp/specification/` (ревизия `2026-07-28`, modern) и `docs/protocols/mcp/specification/2025-11-25/` (legacy). Методы, поля, коды и `_meta`-ключи, которых там нет, не вводятся (по аналогии с корневым `AGENTS.md` §3.4).

Если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Назначение

`codelab_agent_mcp` — свой минимальный dual-era MCP-клиент (design.md, D1, D2): кодек JSON-RPC (D4), `McpClient` (D5, D8), `McpTool` (D7), `McpClientConnector` (D6) и streamable HTTP на `package:http` (D10). Ядро знает только порты `McpConnector` / `McpTransport` (`lib/src/mcp/` ядра); протокол MCP живёт здесь.

## 2. Границы

* Пакет НЕ ДОЛЖЕН импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_*`, `package:codelab_client_*` и `package:codelab_agent_io/` — в том числе `lib/testing.dart` (PKG-3): правило `rules.dart` сторожа, проверка — `melos run guard`.
* `dependencies` — только `codelab_agent_core`, `http`, `meta`, `async`. Расширение — только через OpenSpec change. Проверка — `pubspec_allowlist_test.dart`. Второй фреймворк JSON-RPC (`json_rpc_2`) и кодек ACP не подключаются (D4).
* Из ядра используется публичный барель `package:codelab_agent_core/codelab_agent_core.dart`.
* `http.Client`, часы и id приходят от хоста (PKG-6); в тестах — `MockClient`, `FakeClock`.
* Сторонний код, тексты и фикстуры не копируются (корневой `AGENTS.md` §5): клиент пишется по тексту спецификации MCP.

## 3. Тесты

* TDD — по `packages/dart/codelab_agent_core/AGENTS.md` §2.
* Сервер в тестах — `FakeMcpServer` из `lib/testing.dart` (D15): эпохи `modern`, `legacy`, `dualEra`, запись вызовов и отмен. Реального процесса и сети нет; stdio-процесс проверяет `apps/codelab_agent`.
* Время — `FakeClock`; синхронизация — события и completer-ы, не `Future.delayed`.
* Секреты (`env`, `headers`) не попадают в логи: `mcp_logs_no_secrets_test.dart`.
