## 1. Bootstrap workspace

- [x] 1.1 Создать root `pubspec.yaml`, `melos.yaml` и `analysis_options.yaml` для Dart/Flutter/FVM/Melos monorepo
- [x] 1.2 Настроить `.fvm/fvm_config.json` как tracked config и убедиться, что SDK binaries не попадают в git
- [x] 1.3 Создать package structure: `packages/dart/acp_protocol`, `packages/dart/acp_transports`, `packages/dart/acp_client_core`, `packages/dart/acp_testing`, `packages/flutter/acp_ui`
- [x] 1.4 Создать `apps/codelab_app` как Flutter desktop app shell
- [x] 1.5 Добавить Melos scripts: `format`, `check-format`, `analyze`, `test`, `protocol-conformance`, `check`
- [x] 1.6 Добавить базовые package `pubspec.yaml` dependencies для `fluent_ui`, Bloc/Cubit, CherryPick v4.x.x, `fpdart`, `freezed`, `build_runner`
- [x] 1.7 Выполнить `fvm dart run melos bootstrap`

## 2. Implement ACP protocol package

- [x] 2.1 Создать public barrel `packages/dart/acp_protocol/lib/acp_protocol.dart`
- [x] 2.2 Реализовать typed JSON-RPC 2.0 request/response/notification models
- [x] 2.3 Реализовать ACP DTOs для `initialize`, capabilities, sessions, prompt turns, permissions, tool calls, content blocks и stop reasons
- [x] 2.4 Реализовать encode/decode codecs и runtime validation по `docs/acp/protocol/17-Schema.md`
- [x] 2.5 Реализовать typed protocol errors и mapping invalid JSON/invalid ACP shape
- [x] 2.6 Поддержать `_meta` extension data и запрет custom root fields вне ACP spec
- [x] 2.7 Добавить unit tests для round-trip, unknown fields, invalid messages и error mapping

## 3. Implement transports

- [x] 3.1 Создать common `AcpTransport` port для inbound stream, outbound send, lifecycle и close
- [x] 3.2 Реализовать fake transport для deterministic core/conformance tests
- [x] 3.3 Реализовать stdio transport через child process stdout/stderr separation
- [x] 3.4 Реализовать process lifecycle handling: start, graceful shutdown, process exit, invalid JSON, stderr diagnostics
- [x] 3.5 Добавить built-in editable profile `Codelab Agent` с command `codelab`, args `serve --stdio`, env `CODELAB_LOG_LEVEL=DEBUG`
- [ ] 3.6 Реализовать WebSocket transport для remote agents с token/header config
- [ ] 3.7 Добавить transport unit/integration tests, включая codelab-agent-compatible stdio flow

## 4. Implement core domain and application

- [ ] 4.1 Создать domain models для session, prompt turn, tool call, approval, connection state и diagnostics
- [ ] 4.2 Реализовать state machines для connection/session/prompt turn lifecycle
- [ ] 4.3 Реализовать use cases `CreateSession`, `LoadSession`, `SendPrompt`, `CancelTurn`, `RespondToPermission`, `Reconnect`
- [ ] 4.4 Реализовать idempotent handling для duplicate, late и interleaved `session/update`
- [ ] 4.5 Реализовать approval policy с risk levels `readOnly`, `localWrite`, `network`, `shell`, `destructive`
- [ ] 4.6 Реализовать permission modes `readOnly`, `ask`, `plan`, `autoEdits`
- [ ] 4.7 Реализовать cancellation behavior: `session/cancel`, pending permission outcome `cancelled`, late updates, final `stopReason: cancelled`
- [ ] 4.8 Реализовать structured logging/diagnostics с secret redaction
- [ ] 4.9 Добавить core tests для state transitions, approvals, cancellation, duplicate updates и failures

## 5. Configure dependency injection

- [ ] 5.1 Настроить CherryPick v4.x.x root scope в `apps/codelab_app`
- [ ] 5.2 Разделить DI modules по boundaries: protocol, transports, core/application, UI, platform services
- [ ] 5.3 Добавить explicit feature/session scopes, если lifecycle dependencies короче app lifecycle
- [ ] 5.4 Обеспечить, что domain/application classes получают dependencies через constructors/factories
- [ ] 5.5 Добавить test bindings для fake transport и mock services

## 6. Implement Fluent UI workbench

- [ ] 6.1 Создать `acp_ui` widget folders `atomics`, `molecules`, `organisms`
- [ ] 6.2 Реализовать Fluent atomics: buttons, badges, status indicators, text primitives, icons, progress indicators
- [ ] 6.3 Реализовать molecules: prompt composer, tool call summary, connection status row, approval option group
- [ ] 6.4 Реализовать organisms: transcript panel, approval panel, session sidebar, debug log panel, connection screen
- [ ] 6.5 Реализовать desktop layout: command bar, sessions pane, transcript/prompt area, inspector
- [ ] 6.6 Реализовать responsive collapse для sessions pane и inspector без горизонтального скролла composer
- [ ] 6.7 Реализовать view modes `summary`, `normal`, `verbose`
- [ ] 6.8 Реализовать command palette/slash commands для `/new`, `/plan`, `/permissions`, `/logs`, `/compact`, `/reconnect`
- [ ] 6.9 Реализовать keyboard shortcuts для prompt submit, cancel, approve/reject и inspector navigation
- [ ] 6.10 Добавить Flutter widget tests для connection states, transcript, approvals, errors и layout behavior

## 7. Integrate app shell

- [ ] 7.1 Создать `codelab_app` bootstrap с CherryPick DI, Bloc/Cubit presentation state и Fluent app shell
- [ ] 7.2 Подключить transport selection UI для stdio/WebSocket
- [ ] 7.3 Подключить `Codelab Agent` default stdio profile в connection setup
- [ ] 7.4 Подключить session/task sidebar и current session context indicators
- [ ] 7.5 Подключить prompt composer к `SendPrompt` use case
- [ ] 7.6 Подключить inspector для approvals, tool call details, diffs, raw input/output, diagnostics и protocol log
- [ ] 7.7 Подключить cancel/reconnect actions к core use cases

## 8. Verify quality and conformance

- [ ] 8.1 Добавить protocol conformance tests для initialize, session creation, prompt streaming, permissions, cancellation, version mismatch, invalid messages
- [ ] 8.2 Добавить stdio integration test с `codelab-agent` или compatible test double using `codelab serve --stdio` semantics
- [ ] 8.3 Проверить secret redaction в logs, diagnostics и inspector
- [ ] 8.4 Запустить `fvm dart run melos run format`
- [ ] 8.5 Запустить `fvm dart run melos run analyze`
- [ ] 8.6 Запустить `fvm dart run melos run test`
- [ ] 8.7 Запустить `fvm dart run melos run protocol-conformance`
- [ ] 8.8 Запустить полный `fvm dart run melos run check`
- [ ] 8.9 Обновить документацию, если implementation behavior отличается от `docs/codelab-spec.md` или OpenSpec specs
