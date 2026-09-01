## Context

`CodeLabShellCubit` уже реализует полный stdio-флоу: `connect()`/`reconnect()` строят `StdioAcpTransportConfig` через `_stdioConfigFromState()`, вызывают `_application.connect(transport)`/`_reconnectUseCase(ReconnectCommand(...))`, маппят результат в `connectionStatus`/диагностику через `_connectionStatusForConnection`/`_failureMessage`. Для WebSocket этот же путь просто не реализован — обе ветки рано выходят с `_recordPendingAction('... is deferred: ...')`. Транспорт `WebSocketAcpTransport`/`WebSocketAcpTransportConfig` (`packages/dart/acp_transports/lib/src/websocket_acp_transport.dart`) уже существует и не требует изменений. Конструктор `CodeLabShellCubit` принимает только `CodeLabStdioTransportFactory` — WebSocket-фабрики транспорта нет вовсе.

Кнопка "Edit profile" в `AcpConnectionScreen` (`onEditProfile: cubit.editProfile`) сейчас не имеет собственного полезного действия, потому что `TransportSetupPanel` с редактируемыми полями уже безусловно рендерится над `AcpConnectionScreen`/`AcpTranscriptPanel` в обеих ветках `WorkbenchMainPane.build()` (`main_pane.dart:31` и `:60`) — форма никогда не скрыта, редактировать нечего "открывать". Обсуждение с пользователем перевело это в отдельное решение: не просто дать кнопке какой-то эффект, а убрать форму из постоянно видимого потока и перенести её в модальный диалог — это же решает и проблему постоянно занимающей место формы, отмеченную в общем UX-анализе как отдельный код-смелл.

## Goals / Non-Goals

**Goals:**
- `connect()`/`reconnect()` для WebSocket-транспорта выполняют реальное подключение/переподключение по тому же паттерну обработки ошибок/диагностики, что и stdio-ветка.
- `TransportSetupPanel` рендерится только внутри модального `ContentDialog` (Fluent UI), а не безусловно в основном потоке `WorkbenchMainPane`.
- Диалог открывается из двух мест, обе точки входа используют один и тот же лейбл кнопки — "Configure connection" (не два разных названия для одного действия): (1) постоянная кнопка в `WorkbenchCommandBar` — доступна независимо от состояния транскрипта/сессии (переименование текущей "Edit profile" в `acp_connection_screen.dart:88`); (2) компактная карточка в `AcpConnectionScreen` для пустого/disconnected состояния.
- Диалог не открывается автоматически при первом запуске приложения — только по явному действию пользователя.
- Тест `'reconnect leaves WebSocket startup deferred'` заменяется тестами реального поведения.

**Non-Goals:**
- Не меняется `WebSocketAcpTransport`/`WebSocketAcpTransportConfig` в `acp_transports`.
- Не решается вопрос с открытым текстовым полем токена (уже отдельно отмечен как отдельная UX-находка — маскировка поля Token не входит в этот change).
- Не вводится роутинг — модальный диалог рендерится через `showDialog`/`ContentDialog` поверх текущего единственного экрана, Navigator/route не задействуются.
- Не меняется сама форма (набор полей, их layout внутри `TransportSetupPanel`) — меняется только то, где она рендерится.

## Decisions

- **WebSocket transport factory добавляется как отдельный typedef** `CodeLabWebSocketTransportFactory = AcpTransport Function(WebSocketAcpTransportConfig config)`, по аналогии с `CodeLabStdioTransportFactory`, и передаётся в конструктор `CodeLabShellCubit` вторым обязательным параметром. Регистрируется в DI (`app_scope.dart`) рядом с существующей регистрацией stdio-фабрики — переиспользуется тот же DI-модуль/boundary, новый не создаётся.
- **`_webSocketConfigFromState()` зеркалит `_stdioConfigFromState()`**: строит `WebSocketAcpTransportConfig` из `state.webSocketEndpoint`/`state.webSocketToken` (trim, `null` при пустом endpoint — аналогично проверке пустой stdio-команды).
- **`connect()`/`reconnect()` получают WebSocket-ветку, зеркальную stdio-ветке** (тот же порядок: валидация конфигурации → `connectionStatus.connecting/reconnecting` → вызов → `_connectionStatusForConnection`/`_failureMessage` → диагностика), вместо текущего раннего `return` с `_recordPendingAction`. `connect()` вызывает `_application.connect(transport)` напрямую (как и для stdio), `reconnect()` — через `_reconnectUseCase(ReconnectCommand(...))` (как и для stdio) — сохраняется существующая асимметрия connect/reconnect, а не унифицируется заново.
- **Диалог — чисто presentation-level ephemeral UI state, не поле в `CodeLabShellState`.** Открытие/закрытие управляется локально виджетом (`showDialog(context: ..., builder: ...)`), а не через кубит: видимость модалки — не session-state и не требует state machine по правилам `docs/architecture/state-management.md` §13 ("не следует создавать repository/state entry для простого ephemeral UI state"). `editProfile()` в кубите как отдельный метод **не нужен** — кнопки в `command_bar.dart`/`acp_connection_screen.dart` вызывают `showDialog` напрямую; сам диалог внутри читает/пишет состояние через уже существующие методы кубита (`selectTransport`, `updateStdioCommand`, `updateWebSocketEndpoint` и т.д.) — то есть `TransportSetupPanel` переиспользуется как есть, только меняется его родитель (`ContentDialog` вместо `Column` в `main_pane.dart`).
- **`AcpConnectionScreen` получает компактный режим** для пустого состояния: вместо full-width формы — карточка с кнопкой "Configure connection", открывающей тот же диалог. Требует либо нового параметра в `AcpConnectionScreen` (`acp_ui`), либо отдельного компактного виджета в `apps/codelab_app` — выбор делается на этапе задач, по месту (`acp_ui` предпочтительнее, если карточка достаточно общая, чтобы не тянуть app-specific логику в пакет).
- **Закрытие диалога** — стандартное поведение `ContentDialog` (кнопка Close/Cancel, `Esc`); поля продолжают писать в `CodeLabShellState` по мере ввода (как сейчас), явного "Save"/"Cancel с откатом" не вводится — сохраняется текущая семантика "изменения применяются сразу", просто в новом контейнере.

## Risks / Trade-offs

- [WebSocket connect/reconnect ошибки (сетевые, auth) могут требовать иной классификации, чем `UnsupportedProtocolVersionException`/generic `Object` из stdio-ветки] → переиспользовать тот же `catch`-паттерн; если `WebSocketAcpTransport` бросает специфичные типы ошибок, добавить для них отдельный `on`-блок с понятным сообщением, не расширяя это на надуманные сценарии.
- [Замена теста `'reconnect leaves WebSocket startup deferred'` — этот тест сейчас единственное, что фиксирует текущее поведение] → не удалять тест до того, как новый тест на реальный reconnect зелёный, чтобы не потерять покрытие между коммитами.
- [Убирая инлайн-форму, легко случайно сломать первый запуск — пользователю не с чем взаимодействовать, если диалог не открыт] → компактная карточка в `AcpConnectionScreen` должна быть достаточно заметной (заголовок + одна явная кнопка), проверить это отдельным widget-тестом на пустое состояние.
- [`ContentDialog` — первый модальный диалог в кодовой базе, прецедента нет] → не изобретать общий `AcpDialog`-обёртку заранее "на будущее" (`AGENTS.md` §13 — abstraction должна быть оправдана, не по умолчанию); использовать `ContentDialog` напрямую, обобщать только если появится второй диалог.
