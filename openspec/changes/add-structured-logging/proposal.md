## Why

CodeLab не имеет утверждённой технологии логирования: единственный существующий механизм — внутренний `DiagnosticEntry`/`_recordDiagnostic` в `AcpClientApplication` (`packages/dart/acp_client_core/lib/src/application/acp_client_application.dart`), который держит **неограниченный** список записей в памяти сессии только для UI-инспектора (`inspector_pane.dart`). У него нет типизированных correlation ID, нет разделения application logging / protocol tracing / debug diagnostics (§2 `observability.md`), нет release/debug различия и нет внешнего structured-вывода. Существующий `SecretRedactor` (`packages/dart/acp_client_core/lib/src/domain/secret_redaction.dart`) уже покрывает маскирование секретов для этого потока, но не переиспользуется нигде за пределами него.

`docs/architecture/observability.md` уже формулирует обязательные инварианты OBS-001..OBS-006, но без выбранной технологии и порта логирования их не с чем проверять, а последующие изменения (`add-integrated-terminal`, `add-file-preview-and-tree`) продолжают добавлять диагностику в этот же нецелостный механизм.

## What Changes

- Утвердить `structured_log` (pub.dev, автор — участник проекта) как технологию логирования в `docs/architecture/technology-stack.md` — pure Dart, 0 внешних зависимостей, JSON/structured output, processor pipeline, context binding.
- Ввести Logger-порт (domain/application-уровень, согласно уже действующему требованию `workspace-architecture` — "use case зависит от порта, а не от конкретного адаптера") и `structured_log`-адаптер, подключаемый в composition root `apps/codelab_app` через существующий CherryPick DI.
- Переиспользовать `SecretRedactor` как processor `structured_log` для маскирования (OBS-002) — не создавать новые правила редактирования секретов.
- Расширить context-binding API `structured_log` типизированными correlation-полями из §4 `observability.md`: `session_id`, `request_id`, `message_id`, `tool_call_id`, `connection_generation`, `operation_id` (OBS-003). Доработка выполняется в самом пакете `structured_log` силами его автора.
- Подключить логирование по слоям согласно ownership из §3 `observability.md` (OBS-006):
  - `acp_protocol` — parse failure, unsupported message, schema mismatch;
  - `acp_transports` — connect/disconnect, process lifecycle, stream closure (уже частично сигнализируется через существующие diagnostic-события транспорта — подключить их к Logger, а не только к `AcpClientApplication`);
  - `acp_client_core` — session transitions, request lifecycle, reconnect, cancellation, permission lifecycle, stale/duplicate events;
  - presentation — значимые user intents, UI-level failures.
- Добавить bounded ring buffer к текущему неограниченному `_diagnostics` в `AcpClientApplication` (OBS-004).
- Добавить отдельный, developer-only канал protocol tracing (полный ACP payload), выключенный по умолчанию в release-сборках и включаемый только явным debug/runtime действием (OBS-005).
- Структурированное логирование значимых lifecycle-переходов (connect → session created → request started → reconnect → cancellation → completion) со stable correlation ID (OBS-001).

Вне scope этого change: перестройка UI debug-логов панели (команда `/logs`, уже специфицирована в `agent-workbench-ui` и реализована через `inspector_pane.dart`) — этот change поставляет только Logger/структурированные события под неё; расширение содержимого панели — отдельный follow-up при необходимости.

## Capabilities

### New Capabilities
- `structured-logging`: Logger-порт + `structured_log`-адаптер, correlation ID контракт, интеграция маскирования через `SecretRedactor`, ownership логирования по слоям, bounded debug/trace, release/debug различие — покрывает OBS-001..OBS-006 из `observability.md`.

### Modified Capabilities
_(нет)_ — существующее требование "Редактирование секретов" в `approval-safety` и требование "/logs" в `agent-workbench-ui` не меняют формулировку или наблюдаемое поведение; этот change реализует инфраструктуру, которая их обслуживает, а не меняет их контракт.

## Impact

- Новая pub.dev-зависимость `structured_log` в `packages/dart/acp_client_core/pubspec.yaml` и `apps/codelab_app/pubspec.yaml` (composition root).
- `docs/architecture/technology-stack.md` — фиксирует утверждённую технологию логирования.
- `packages/dart/acp_client_core/lib/src/application/acp_client_application.dart` — `_recordDiagnostic`/`_diagnostics` получают bounding и correlation-обвязку через Logger, `SecretRedactor` переиспользуется как processor.
- `packages/dart/acp_transports`, `packages/dart/acp_protocol` — получают использование Logger-порта по правилам ownership (§3 `observability.md`); оба пакета остаются pure Dart (`structured_log` совместим с этим ограничением).
- `apps/codelab_app` — composition root wiring через CherryPick, presentation-логирование UI-failures/user intents.
- ACP wire protocol, публичные API и форма `DiagnosticEntry` не меняются — только внутренняя реализация записи/маскирования/ограничения объёма и добавление внешнего structured-вывода.
