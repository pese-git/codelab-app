# AGENTS.md — codelab_agent_io

Правила этого пакета дополняют корневой `AGENTS.md` и `packages/dart/codelab_agent_core/AGENTS.md`.

Источник архитектуры — `docs/architecture/proposals/agent-core-architecture.md`:
- §1 — пакеты и allowlist зависимостей;
- §4 — `ExecutionEnv`, `LocalExecutionEnv`;
- §8 — журналы сессий, `JsonlSessionStore`.

Код пишется по этим документам и `design.md` OpenSpec change этапа. Если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Назначение

`codelab_agent_io` — реализации портов ядра на `dart:io` для настольных хостов: сейчас — `apps/codelab_agent`, с этапа 7 — `codelab_embedded` (ещё не создан), через который агента встраивают клиенты:
- `LocalExecutionEnv` — файлы и процессы (с этапа 2);
- `JsonlSessionStore` — журналы сессий в JSONL (этап 3);
- конфигурация и хранилища секретов (этапы 4 и 8).
- `lib/src/cli/` — общая реализация подкоманд `config` (`ConfigCommands.check` для `config check`): тексты, правила и коды выхода для `codelab-agent` и `codelab` в одном месте; аргументы разбирает каждое приложение своим `package:args` (design.md change `add-agent-configuration`, D13).

Ядро от пакета не зависит. Хост передаёт реализации в `AgentCoreServices`.

## 2. Границы

* Пакет НЕ ДОЛЖЕН импортировать `package:flutter/`, `package:codelab_acp_*` и `package:codelab_client_*`: правило `packages/dart/codelab_architecture_tests/test/support/rules.dart`, проверка — `melos run guard`.
* `dependencies` — только подмножество allowlist §1.2 документа ядра: `codelab_agent_core`, `path`, `meta`, `async`, `yaml`, `yaml_edit` (`toml` убран: `codelab.toml` не читается, design.md change `add-agent-configuration`, D12). Расширение — только через OpenSpec change. Проверка — `pubspec_allowlist_test.dart`.
* Из ядра используется только публичный барель `package:codelab_agent_core/codelab_agent_core.dart`. Тест может импортировать `src/` ядра только с `// ignore: implementation_imports` и причиной в комментарии.
* Пути ядра — POSIX. Пути Windows приводятся к виду ядра и обратно функциями `toCorePath` / `toHostPath` (design.md change `add-agent-core-loop-and-tools`, D3).

## 3. Тесты

* TDD — по `packages/dart/codelab_agent_core/AGENTS.md` §2.
* `LocalExecutionEnv` проверяется на реальных файлах во временном каталоге и на реальных процессах `/bin/sh`. Это интеграционные тесты на Dart VM, они входят в `melos run check` и в локальную проверку затронутого, если изменён пакет (корневой `AGENTS.md` §21). В ветках `feature/*` и `hotfix/*` другие прогоны не нужны (корневой `AGENTS.md` §21).
* Общий контракт env — `packages/dart/codelab_agent_core/test/env/execution_env_contract.dart`; тесты пакета прогоняют его на `LocalExecutionEnv`.
* Общий контракт хранилища сессий — `packages/dart/codelab_agent_core/test/session/session_store_contract.dart`; его проходит `JsonlSessionStore` во временном каталоге. Тест сбоя (`jsonl_crash_recovery_test.dart`) запускает дочерний процесс `test/session/crash_child.dart` и завершает его `SIGKILL`.
* Тесты времени (таймаут, завершение дерева процессов) задают пределы с запасом («не позже N с»), а не точное время. CI работает на Linux; ветка Windows (`taskkill`) проверяется вручную.
