## MODIFIED Requirements

### Requirement: WebSocket transport
CodeLab SHALL support remote ACP agents over WebSocket for MVP remote workflows, including user-initiated and automatic reconnect after disconnect.

`WebSocketAcpTransport` SHALL выполнять рукопожатие штатным `WebSocket.connect` из `dart:io`, без собственной реализации рукопожатия (design.md change `add-app-settings-shell`, D12, задача 3.3a). При отказе рукопожатия со статусом, отличным от 101, транспорт SHALL завершать открытие `AcpTransportException` с кодом `startFailed` и причиной `AcpWebSocketHandshakeRejected(statusCode)`, где `statusCode` берётся из типизированного поля `WebSocketException.httpStatusCode`. Текст `WebSocketException` НЕ SHALL разбираться. Если значение заголовка (например, токена) недопустимо для HTTP, ошибка открытия НЕ SHALL содержать это значение ни в тексте, ни в причине. Заголовок `Authorization` НЕ SHALL переноситься при редиректе на другой origin.

#### Scenario: Remote agent connects
- **WHEN** user configures a WebSocket endpoint and token/header if required
- **THEN** CodeLab opens the connection and performs ACP initialization over WebSocket

#### Scenario: WebSocket disconnects
- **WHEN** the WebSocket closes unexpectedly
- **THEN** CodeLab enters disconnected state and offers reconnect

#### Scenario: User reconnects a WebSocket transport
- **WHEN** user selects reconnect while the active transport is WebSocket
- **THEN** CodeLab opens a new WebSocket connection using the current endpoint/token configuration and performs ACP initialization, updating connection status and diagnostics on success or failure

#### Scenario: WebSocket reconnect fails
- **WHEN** a WebSocket reconnect attempt fails (network error, auth failure, or protocol mismatch)
- **THEN** CodeLab sets connection status to failed and records a user-readable diagnostic describing the failure, without leaving the UI in the connecting state indefinitely

#### Scenario: Отказ рукопожатия со статусом
- **WHEN** WebSocket-сервер на loopback отвечает на запрос обновления соединения статусом 401
- **THEN** открытие транспорта завершается `AcpTransportException(startFailed)` с причиной `AcpWebSocketHandshakeRejected` и `statusCode` 401

#### Scenario: Недопустимое значение заголовка
- **WHEN** транспорт открывается с токеном `sk-test-leak-0123456789\n`, содержащим перевод строки
- **THEN** открытие завершается `AcpTransportException(startFailed)`, а ни текст ошибки, ни её причина не содержат `sk-test-leak-0123456789`

#### Scenario: Редирект на другой origin
- **WHEN** сервер на loopback отвечает на рукопожатие с токеном редиректом на другой порт loopback
- **THEN** второй сервер не получает заголовок `Authorization`
