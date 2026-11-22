# AGENTS.md — codelab_client_acp

Правила этого пакета дополняют корневой `AGENTS.md`; здесь только ссылки на уже действующие требования. Роль в проекте — `.claude/agents/client-engineer.md`.

## 1. Назначение

Протокольный клиент `AcpClientApplication`: соединение, сессии, ходы, ответы на `fs/*`, `terminal/*`, `session/request_permission`. API и схема зависимостей — `README.md` пакета.

## 2. Границы

* `lib/**` НЕ ДОЛЖЕН импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `package:flutter/`, `package:codelab_acp_transports/io.dart`, `package:intl/`, `package:flutter_localizations/` и остальное из `webUnsafe` (`codelab_architecture_tests/test/support/rules.dart`, `webUnsafe` и `uiLanguageForbidden`). Файлы и процессы приходят портами (`TextFileReader`, `TextFileWriter`, `TerminalProcessRunner`); их `dart:io`-реализации — в `codelab_client_io` (корневой `AGENTS.md` §5).
* `codelab_acp_testing` — только `dev_dependency` (корневой `AGENTS.md` §5).

## 3. Правила

* Соединение, сессия и ход — явные state machines (`state_machines.dart`), не набор boolean-флагов (корневой `AGENTS.md` §8; `docs/architecture/session-lifecycle.md`).
* Late events и результаты старого соединения отбрасываются по поколению соединения; reconnect не создаёт дублирующих подписок; у долгой подписки есть owner, `dispose` её отменяет (корневой `AGENTS.md` §9; `session-lifecycle.md` §15).
* `fs/*` и `terminal/*`: собственного approval-гейта нет, но `path`/`cwd` ДОЛЖНЫ быть внутри рабочей папки сессии; выход наружу отклоняется до выполнения операции (корневой `AGENTS.md` §10; `docs/architecture/permissions.md`; `openspec/changes/archive/2026-09-04-add-acp-fs-client-support/design.md`, `openspec/changes/archive/2026-09-04-add-acp-terminal-client-support/design.md`).
* Permission request связан со своей сессией и `toolCallId`; решение для одного tool call не применяется к другому (корневой `AGENTS.md` §10).
* Ошибки типизированные (`PromptFailure`, `FsAccessFailure`), не `String` и не общий `Exception` (корневой `AGENTS.md` §15; `docs/architecture/error-handling.md`).
* Секреты не попадают в журнал: маскирование — `secret_redaction.dart` (корневой `AGENTS.md` §10, §16).

## 4. Проверки

По корневому `AGENTS.md` §21: `fvm dart analyze` и `fvm dart test packages/dart/codelab_client_acp`; при изменении клиентского ACP-слоя — `fvm dart run melos run conformance:client`; при изменении импортов или `pubspec.yaml` — `fvm dart run melos run guard`. Красный тест на `FakeAcpTransport`, гонки — forced ordering без `Future.delayed` (`.claude/agents/client-engineer.md`).
