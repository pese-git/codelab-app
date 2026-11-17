# AGENTS.md — codelab_agent_acp

Правила этого пакета дополняют корневой `AGENTS.md` и `packages/dart/codelab_agent_core/AGENTS.md`.

Источник архитектуры — `docs/architecture/proposals/agent-core-architecture.md`:
- §13 — ACP-адаптер (`agent-core/13-acp-adapter.md`);
- §4.7 — `AcpClientExecutionEnv`, §7.8 — `AcpPermissionGate`;
- §14.9 — агентский прогон golden-фикстур.

Код пишется по этим документам и `design.md` OpenSpec change `add-dart-agent-acp-server`. Если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Назначение

`codelab_agent_acp` — проекция `AgentRuntime` в ACP: `AcpAgentServer` обслуживает соединения по любому `AcpTransport`, проецирует события ядра в `session/update` и исполняет файлы, команды и запросы разрешений через клиента. Транспорты (stdio, WebSocket) и локальный листинг передаёт хост (встроенный агент вместо клиентских `fs/*`/`terminal/*` передаёт `AcpServerConfig.localEnv`, change `add-embedded-agent-mode`, D4) — бинарь `apps/codelab_agent` и мост `codelab_embedded` (хост встроенного агента). Файлы проекта адаптер не читает: их загружает ядро через порт хоста, а адаптер публикует результат — `AgentSession.commands` в `available_commands_update` после `session/new` и в реплее, `AgentSession.agents` как опцию `agent` (design.md change `add-agent-project-files`, D9, D12).

Расширения change `add-subagents-and-tasks` (design.md D9, D24, D35, D47; `agent-core/13-acp-adapter.md` §13.2, §13.7, §13.12):

* Объявление в `initialize` — `agentCapabilities._meta.codelab` (`subagents`, `subagentToolCalls`, `tasks`) — только клиенту, приславшему `clientCapabilities._meta.codelab`. Согласие `subagentToolCalls` читается из `ClientLink.capabilities` в момент события или запроса, а не при создании моста: после переподключения оно может смениться (`subagentToolCallsConsent`).
* Вызовы потомков (`SubagentActivity`) проецируются цепочкой `toolCallId` и `_meta.codelab.parentToolCallId` (`subagent_chain.dart`) — только клиенту с согласием; остальным цепочка не уходит (SUB-12).
* `AcpPermissionGate` перед `session/request_permission` ждёт `tool_call` своей цепочки (клиент без согласия — вызов `agent` корня); ожидание гоняется с отменой.
* Реплей дерева (`session.replayTree()`) придерживает кадры живого хода и отпускает их после кадров реплея (`SessionBridge.replayInto`, D47 Т6).
* `_meta.codelab.subagent`: у первого `tool_call` вызова `agent` — `{id, type}`; у финального `tool_call_update` — `{id, summary}`, при `failed` ещё `failure`. Отменённый `agent` с итогом ребёнка получает `content: []`, отменённый вызов другого инструмента — без `content` (D52 п. 1); так же — в реплее `session/load` и у вложенного `agent`, закрытого вместе с поддеревом (D53).
* `_meta.codelab.task` у entries `plan` и `_meta.codelab.taskChange` (только вживую, не при реплее) — проекция `TaskListChanged`.

## 2. Границы

* Пакет НЕ ДОЛЖЕН импортировать `dart:io`, `package:flutter/` и `package:codelab_acp_transports/io.dart` (PKG-3): правило `packages/dart/codelab_architecture_tests/test/support/rules.dart`, проверка — `melos run guard`.
* `dependencies` — только `codelab_agent_core`, `codelab_acp_protocol`, `codelab_acp_transports`, `meta`, `async` (§1.2 документа ядра). Расширение — только через OpenSpec change. Проверка — `pubspec_allowlist_test.dart`.
* Методы, поля и значения перечислений ACP берутся только из `codelab_acp_protocol` и `docs/protocols/acp/protocol/`. Всё сверх них — `_meta.codelab.*`, `data.codelab` или методы `_codelab/*`, и каждое расширение вводит OpenSpec change (`AGENTS.md` §3.4, ACP-2).
* Из ядра используется публичный барель `package:codelab_agent_core/codelab_agent_core.dart`.

## 3. Тесты

* TDD — по `packages/dart/codelab_agent_core/AGENTS.md` §2.
* Сервер проверяется через пару транспортов в памяти `InProcessAcpLink` из `codelab_acp_transports`: кадры идут тем же кодеком, что на проводе, но без процессов и сокетов.
* Модель — `ScriptedStreamFunction`, время — `FakeClock`, id — `SequentialIdGenerator`: тесты детерминированы.
* Фабрика агентского прогона фикстур (`test/conformance_test.dart`) подключает `ProjectFilesLoader` (`codelab_agent_io`, только `dev_dependency`) с временным `CODELAB_HOME` и принимает в `setup.config` ключ `trusted_projects` с `${cwd}`; другой неизвестный ключ — провал (design.md change `add-agent-project-files`, D15).
