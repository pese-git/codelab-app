## Why

Сегодняшний debug-лог виджет (`AcpDebugLogPanel`/`AcpDebugLogEntry` в `acp_ui`) — самописный, минимальный (`id`/`severity`/`message`/`source`), без поиска и фильтрации, и не знает ни о чём из того, что `add-structured-logging` уже добавил в поток событий: `component` (transport/protocol/client/presentation), `category`, `connection_generation`, `session_id`/`request_id`/`tool_call_id`. Эти поля сейчас пишутся в structured-лог, но нигде не видны пользователю в приложении.

`structured_log_fluent` (вместе с headless `structured_log_flutter`) — тот же автор, что и уже принятый `structured_log`, специально построен как in-app viewer поверх `structured_log`'s `LogSink`: bounded buffer, live-обновление, поиск, фильтр по уровню/категории, master-detail с полным контекстом записи. Правильнее переиспользовать этот компонент, чем расширять самописный `AcpDebugLogPanel` вручную под те же возможности.

## What Changes

- Добавить `structured_log_flutter` и `structured_log_fluent` (`0.1.0-dev.2`, prerelease) как зависимости — точное размещение в dependency graph (`acp_ui` vs только `codelab_app`) решается в design.md.
- Расширить `configureCodeLabLogging()` (`packages/dart/acp_client_core/lib/src/infrastructure/structured_log_logger.dart`) опциональным третьим sink'ом для `LogBuffer.capture` — аддитивно, не меняя контракт двух существующих sink'ов (`application`/`protocol`).
- **BREAKING** (внутри monorepo, публичного pub.dev-пакета нет): удалить `AcpDebugLogPanel`/`AcpDebugLogEntry` из `acp_ui` — заменяются на `structured_log_fluent`'s `FluentLogViewerPage`/`LogEntryTile`/`LogEntryDetailPane`.
- Изменить поведение команды `/logs` (`agent-workbench-ui` spec, требование "Командная палитра открывается и выполняет доступные действия") — вместо раскрытия `AcpDebugLogPanel` внутри Inspector, открывает `FluentLogViewerPage` (точная форма — модал/route/полноэкранно — решается в design.md, т.к. `FluentLogViewerPage` рассчитан как full-screen page, а не докнутая панель).
- Убрать связанное с текущим debug-log ручное состояние в `CodeLabShellCubit` (`_recordDiagnostic`'s emission в `state.diagnostics`, подписка `_diagnosticSubscription`/`_handleApplicationDiagnostic` в части, обслуживающей панель) там, где оно становится избыточным относительно `LogBuffer` — с сохранением остального (Logger-эмиссия из `_recordDiagnostic`, добавленная в `add-structured-logging`, не трогается).

Вне scope: изменение технологии логирования самой по себе (уже сделано в `add-structured-logging`), изменение protocol-trace поведения (`category=protocol`, off by default) — новый viewer читает тот же structured-поток, но protocol-trace остаётся developer-only каналом с тем же default.

## Capabilities

### New Capabilities
_(нет)_ — это замена реализации существующей UI-возможности, не новая capability.

### Modified Capabilities
- `agent-workbench-ui`: требование "Командная палитра открывается и выполняет доступные действия", сценарий "Выбор /logs раскрывает панель debug-логов" — меняется наблюдаемое поведение (что именно открывает `/logs` и как это выглядит).

## Impact

- `packages/flutter/acp_ui` — удаление `AcpDebugLogPanel`/`AcpDebugLogEntry` (organisms), возможное появление прямой зависимости на `structured_log_fluent`/`structured_log_flutter` (или эта интеграция остаётся только в `codelab_app` — см. design.md).
- `packages/dart/acp_client_core/lib/src/infrastructure/structured_log_logger.dart` — `configureCodeLabLogging()` получает опциональный параметр для третьего sink'а.
- `apps/codelab_app` — `app/app_scope.dart` (`CodeLabLoggingModule` конфигурирует `LogBuffer`), `features/workbench/application/shell_cubit.dart` (упрощение diagnostics-состояния, обслуживающего старую панель), место обработки `/logs` в command palette, `pubspec.yaml` (+2 pub.dev-зависимости).
- `openspec/specs/agent-workbench-ui/spec.md` — delta для изменённого сценария.
- Новые pub.dev-зависимости: `structured_log_flutter`, `structured_log_fluent` — обе `0.1.0-dev.2`, тот же автор/риск-профиль, что и `structured_log` (см. `add-structured-logging/design.md` Risks).
