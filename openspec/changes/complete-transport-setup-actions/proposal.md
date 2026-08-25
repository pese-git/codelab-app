## Why

При верификации `define-codelab-mvp` найдены два расхождения между чек-листом задач и кодом, объединённые общей темой "незавершённые действия в транспортной форме":

1. `agent-transports` требует, чтобы разрыв WebSocket-соединения переводил CodeLab в disconnected-состояние и предлагал reconnect (`openspec/changes/define-codelab-mvp/specs/agent-transports/spec.md`, сценарий "WebSocket disconnects"). По факту `CodeLabShellCubit.connect()`/`reconnect()` для WebSocket-транспорта — no-op с логом `'... is deferred'` (`shell_cubit.dart:365-371, 419-425`). Это уже осознанно задокументировано тестом `'reconnect leaves WebSocket startup deferred'` (`apps/codelab_app/test/widget_test.dart:815`), то есть команда знала о недоделке — но задача 7.7 в `define-codelab-mvp/tasks.md` была отмечена выполненной без этой оговорки.
2. Кнопка "Edit profile" в `AcpConnectionScreen` вызывает `CodeLabShellCubit.editProfile()`, который — заглушка (`shell_cubit.dart:472-473`), ссылающаяся на несуществующий скоуп "task 7.2".

Транспортный слой для WebSocket уже полностью готов на уровне пакета `acp_transports` (`WebSocketAcpTransport`/`WebSocketAcpTransportConfig` реализованы, задача 3.6 подтверждена как done) — не хватает только wiring на уровне `apps/codelab_app` (DI + cubit). Это доводка существующей архитектуры, а не новая фича с нуля.

## What Changes

- `CodeLabShellCubit` получает WebSocket transport factory (аналогично уже существующему `CodeLabStdioTransportFactory`) через DI.
- `connect()`/`reconnect()` реализуют реальную WebSocket-ветку: используют `WebSocketAcpTransportConfig` из полей `webSocketEndpoint`/`webSocketToken` формы, обрабатывают успех/ошибку так же, как stdio-ветка (typed failures, диагностика, `connectionStatus`).
- Существующий тест `'reconnect leaves WebSocket startup deferred'` заменяется тестами на реальное поведение (успешный reconnect, ошибка reconnect) — по аналогии со stdio-тестами в том же файле.
- `TransportSetupPanel` перестаёт быть безусловно видимым в основном потоке `WorkbenchMainPane` (сейчас отображается всегда — и в пустом, и в непустом состоянии транскрипта, `main_pane.dart:31,60`) и переезжает в модальный `ContentDialog` (Fluent UI), открываемый действием "Edit profile"/"Configure connection". Это не новый экран/route — модальный диалог не требует роутинга, приложение остаётся однооконным.
- `editProfile()` перестаёт быть заглушкой: открывает диалог с формой профиля (те же поля/те же методы кубита `updateStdioCommand` и т.д. — переиспользуются как есть, просто рендерятся внутри диалога, а не инлайн).
- В `WorkbenchCommandBar` добавляется постоянно видимая кнопка/иконка "Edit profile", открывающая тот же диалог — так действие доступно в любой момент (не только пока транскрипт пуст, как сейчас ограничено видимостью `AcpConnectionScreen`).
- В пустом/disconnected-состоянии `AcpConnectionScreen` вместо полной инлайн-формы показывает компактную карточку с кнопкой "Configure connection", открывающей тот же диалог — не открывается автоматически при первом запуске.
- **BREAKING**: нет — область видимости и контракты ACP не меняются, только внутреннее поведение `apps/codelab_app`.

## Capabilities

### New Capabilities

_(нет)_

### Modified Capabilities

- `agent-transports`: сценарий "WebSocket disconnects" — уточняется, что reconnect должен фактически переподключать WebSocket-транспорт, а не оставаться заглушкой.

Диалог настройки профиля оформляется как **ADDED Requirement** в `agent-workbench-ui` (ранее это поведение нигде не специфицировано отдельно).

## Impact

- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — `connect()`, `reconnect()`, `editProfile()`.
- `apps/codelab_app/lib/app/app_scope.dart` (или аналогичный DI-модуль) — регистрация WebSocket transport factory.
- `apps/codelab_app/lib/features/workbench/presentation/widgets/transport_setup_panel.dart` — оборачивается в новый `ConnectionSetupDialog` (или аналогичное имя), рендерится через `showDialog`/Fluent `ContentDialog`.
- `apps/codelab_app/lib/features/workbench/presentation/widgets/command_bar.dart` — добавление постоянной кнопки "Edit profile".
- `apps/codelab_app/lib/features/workbench/presentation/widgets/main_pane.dart` — удаление безусловного инлайн-рендера `TransportSetupPanel`.
- `packages/flutter/acp_ui/lib/src/organisms/acp_connection_screen.dart` — компактная карточка вместо (или в дополнение к) текущему полному описанию, если потребуется новый пропс/вариант.
- `apps/codelab_app/test/widget_test.dart` — замена теста deferred-поведения на тесты реального WebSocket connect/reconnect и открытия/закрытия диалога.
- `packages/dart/acp_transports` не меняется — переиспользуется существующий `WebSocketAcpTransport`.
