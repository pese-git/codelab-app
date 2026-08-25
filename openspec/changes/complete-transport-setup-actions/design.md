## Context

`CodeLabShellCubit` уже реализует полный stdio-флоу: `connect()`/`reconnect()` строят `StdioAcpTransportConfig` через `_stdioConfigFromState()`, вызывают `_application.connect(transport)`/`_reconnectUseCase(ReconnectCommand(...))`, маппят результат в `connectionStatus`/диагностику через `_connectionStatusForConnection`/`_failureMessage`. Для WebSocket этот же путь просто не реализован — обе ветки рано выходят с `_recordPendingAction('... is deferred: ...')`. Транспорт `WebSocketAcpTransport`/`WebSocketAcpTransportConfig` (`packages/dart/acp_transports/lib/src/websocket_acp_transport.dart`) уже существует и не требует изменений. Конструктор `CodeLabShellCubit` принимает только `CodeLabStdioTransportFactory` — WebSocket-фабрики транспорта нет вовсе.

Кнопка "Edit profile" в `AcpConnectionScreen` (`onEditProfile: cubit.editProfile`) сейчас не имеет собственного полезного действия, потому что `TransportSetupPanel` с редактируемыми полями уже безусловно рендерится над `AcpConnectionScreen`/`AcpTranscriptPanel` в обеих ветках `WorkbenchMainPane.build()` (`main_pane.dart:31` и `:60`) — форма никогда не скрыта, редактировать нечего "открывать".

## Goals / Non-Goals

**Goals:**
- `connect()`/`reconnect()` для WebSocket-транспорта выполняют реальное подключение/переподключение по тому же паттерну обработки ошибок/диагностики, что и stdio-ветка.
- `editProfile()` даёт реальный, не фиктивный эффект: переносит фокус и скроллит `WorkbenchMainPane` к первому полю активного профиля (Command — для stdio, Endpoint — для WebSocket) в `TransportSetupPanel`.
- Тест `'reconnect leaves WebSocket startup deferred'` заменяется тестами реального поведения.

**Non-Goals:**
- Не меняется layout `WorkbenchMainPane`/`TransportSetupPanel` (например, сворачивание формы после подключения) — это отдельный, более крупный UX-вопрос из общего анализа, не входит сюда.
- Не меняется `WebSocketAcpTransport`/`WebSocketAcpTransportConfig` в `acp_transports`.
- Не решается вопрос с открытым текстовым полем токена (уже отдельно отмечен как отдельная UX-находка — маскировка поля Token не входит в этот change).

## Decisions

- **WebSocket transport factory добавляется как отдельный typedef** `CodeLabWebSocketTransportFactory = AcpTransport Function(WebSocketAcpTransportConfig config)`, по аналогии с `CodeLabStdioTransportFactory`, и передаётся в конструктор `CodeLabShellCubit` вторым обязательным параметром. Регистрируется в DI (`app_scope.dart`) рядом с существующей регистрацией stdio-фабрики — переиспользуется тот же DI-модуль/boundary, новый не создаётся.
- **`_webSocketConfigFromState()` зеркалит `_stdioConfigFromState()`**: строит `WebSocketAcpTransportConfig` из `state.webSocketEndpoint`/`state.webSocketToken` (trim, `null` при пустом endpoint — аналогично проверке пустой stdio-команды).
- **`connect()`/`reconnect()` получают WebSocket-ветку, зеркальную stdio-ветке** (тот же порядок: валидация конфигурации → `connectionStatus.connecting/reconnecting` → вызов → `_connectionStatusForConnection`/`_failureMessage` → диагностика), вместо текущего раннего `return` с `_recordPendingAction`. `connect()` вызывает `_application.connect(transport)` напрямую (как и для stdio), `reconnect()` — через `_reconnectUseCase(ReconnectCommand(...))` (как и для stdio) — сохраняется существующая асимметрия connect/reconnect, а не унифицируется заново.
- **`editProfile()` не открывает новый экран/route** (в приложении нет роутинга) — только запрашивает фокус на `FocusNode`, привязанный к нужному полю `_TransportTextField` в `TransportSetupPanel`, и скроллит `SingleChildScrollView` в `WorkbenchMainPane` наверх через `GlobalKey`/`Scrollable.ensureVisible`. Выбор поля (Command vs Endpoint) зависит от `state.transportType`.

## Risks / Trade-offs

- [WebSocket connect/reconnect ошибки (сетевые, auth) могут требовать иной классификации, чем `UnsupportedProtocolVersionException`/generic `Object` из stdio-ветки] → переиспользовать тот же `catch`-паттерн; если `WebSocketAcpTransport` бросает специфичные типы ошибок, добавить для них отдельный `on`-блок с понятным сообщением, не расширяя это на надуманные сценарии.
- [Замена теста `'reconnect leaves WebSocket startup deferred'` — этот тест сейчас единственное, что фиксирует текущее поведение] → не удалять тест до того, как новый тест на реальный reconnect зелёный, чтобы не потерять покрытие между коммитами.
- [`editProfile()`-фокус может конфликтовать с уже занятым фокусом (например, если открыт `AcpApprovalPanel`)] → ограничиться простым `requestFocus`/`ensureVisible`, без принудительного снятия фокуса с других виджетов; если это создаёт конфликт в тестах — задокументировать как известное ограничение, не решать здесь.
