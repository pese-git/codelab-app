# AGENTS.md — codelab_acp_transports

Правила этого пакета дополняют корневой `AGENTS.md`.

Источники:
- корневой `AGENTS.md` — §5, §7, §9, §15, §16, §21;
- `docs/architecture/acp-boundary.md` — §4 (ответственность пакета);
- референс ACP — `docs/protocols/acp/protocol/16-Transports.md`; его НЕ ДОЛЖНЫ менять;
- `.claude/agents/acp-protocol-engineer.md` — «Правила зоны»;
- `packages/dart/codelab_architecture_tests/test/support/rules.dart` — правило пакета.

## 1. Назначение

Заменяемые ACP-транспорты (stdio, WebSocket, пара в памяти): передача сообщений и жизненный цикл соединения. Состав и API — в `README.md`.

## 2. Границы

* `package:codelab_acp_transports/codelab_acp_transports.dart` ДОЛЖЕН оставаться web-безопасным; `dart:io` и другие запрещённые URI в нём недопустимы (корневой `AGENTS.md` §5; сторож — `rules.dart`, `webUnsafe`, `exclude: lib/io.dart, lib/src/io/`).
* IO-транспорты (`StdioAcpTransport`, `WebSocketAcpTransport`) живут в `package:codelab_acp_transports/io.dart` и импортируются только composition root и тестами (§5).
* Пакет — чистый Dart, без Flutter (§5).
* `codelab_acp_testing` подключается только как `dev_dependency` (§5).

## 3. Правила

* Транспорт НЕ ДОЛЖЕН знать о Flutter UI, показывать dialogs и выполнять navigation (§7); не решает application semantics: событие «процесс завершился» — транспортное, решение о переподключении принимает прикладной слой (`acp-boundary.md` §4).
* Методы и semantics ACP НЕ ДОЛЖНЫ придумываться (§3.4); framing — по `16-Transports.md`.
* stdout stdio-транспорта — только протокол; логи — через единый logger проекта, `print` запрещён (§15, `acp-protocol-engineer.md`); секреты и токены не попадают в логи (§10, §16).
* Lifecycle: у долгоживущей подписки есть явный owner и она отменяется при его dispose; reconnect не создаёт дублирующих подписок; гонка cancellation и completion обрабатывается явно (§9). Переходы состояний описаны в `README.md`, «Жизненный цикл».
* После изменения freezed-моделей — `build_runner` в пакете.

## 4. Проверки

* `fvm dart test` в пакете (включая `test/web_safe_barrel_test.dart`).
* `melos run guard` — при смене импортов или `pubspec.yaml`; `melos run web-compile` — если затронут web-безопасный барель; `conformance:client`, `conformance:agent` — при смене транспортов (§21).
