# AGENTS.md — codelab_agent_acp

Правила этого пакета дополняют корневой `AGENTS.md` и `packages/dart/codelab_agent_core/AGENTS.md`.

Источник архитектуры — `docs/architecture/proposals/agent-core-architecture.md`:
- §13 — ACP-адаптер (`agent-core/13-acp-adapter.md`);
- §4.7 — `AcpClientExecutionEnv`, §7.8 — `AcpPermissionGate`;
- §14.9 — агентский прогон golden-фикстур.

Код пишется по этим документам и `design.md` OpenSpec change `add-dart-agent-acp-server`. Если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Назначение

`codelab_agent_acp` — проекция `AgentRuntime` в ACP: `AcpAgentServer` обслуживает соединения по любому `AcpTransport`, проецирует события ядра в `session/update` и исполняет файлы, команды и запросы разрешений через клиента. Транспорты (stdio, WebSocket) и локальный листинг передаёт хост — бинарь `apps/codelab_agent`, а с этапа 7 и `codelab_embedded` (ещё не создан). Файлы проекта адаптер не читает: их загружает ядро через порт хоста, а адаптер публикует результат — `AgentSession.commands` в `available_commands_update` после `session/new` и в реплее, `AgentSession.agents` как опцию `agent` (design.md change `add-agent-project-files`, D9, D12).

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
