## Purpose

Заменяемый транспортный слой, соединяющий CodeLab с процессом или endpoint'ом ACP-агента — общий порт transport, конкретные реализации stdio и WebSocket, встроенный референсный профиль `Codelab Agent`, а также fake/test-двойники, используемые для проверки остального приложения без реального агента.
## Requirements
### Requirement: Общий порт transport
CodeLab SHALL предоставлять общую абстракцию transport для входящих сообщений, исходящей отправки, событий жизненного цикла, штатного завершения и типизированных ошибок. Порт общий для клиентской и агентской стороны: `inbound` несёт сообщения другой стороны соединения, `send` — сообщения этой стороны (design.md change `add-codelab-agent-binary`, D2).

#### Scenario: Transport заменяем
- **WHEN** core-логика отправляет или получает сообщения ACP
- **THEN** она работает через порт transport, а не через конкретные классы stdio/WebSocket

#### Scenario: Transport падает
- **WHEN** соединение transport падает
- **THEN** CodeLab отображает сбой в типизированное состояние transport и понятную пользователю диагностику

#### Scenario: Один порт у клиента и агента
- **WHEN** `AcpAgentServer` обслуживает соединение через серверный транспорт
- **THEN** он использует тот же интерфейс `AcpTransport`, что и клиент, а `inbound` отдаёт ему сообщения клиента

### Requirement: Stdio transport
CodeLab SHALL поддерживать локальных ACP-агентов через JSON-RPC 2.0 поверх stdio.

#### Scenario: Дочерний процесс запускается
- **WHEN** пользователь подключается через stdio
- **THEN** CodeLab запускает настроенную команду как дочерний процесс с настроенными args, cwd и env

#### Scenario: Потоки протокола и диагностики разделены
- **WHEN** дочерний процесс пишет в stdout и stderr
- **THEN** stdout разбирается как протокольный поток ACP, а stderr показывается как поток диагностики/логов

### Requirement: Референсный профиль codelab-agent
CodeLab SHALL предоставлять встроенный редактируемый stdio-профиль для `https://github.com/pese-git/codelab-agent`.

#### Scenario: Показан профиль по умолчанию
- **WHEN** пользователь открывает настройку соединения
- **THEN** CodeLab предлагает `Codelab Agent` с командой `codelab`, аргументами `serve --stdio` и env `CODELAB_LOG_LEVEL=DEBUG`

#### Scenario: Профиль по умолчанию подключается
- **WHEN** пользователь запускает профиль по умолчанию в окружении, где доступен `codelab`
- **THEN** CodeLab запускает `codelab serve --stdio` и выполняет `initialize` ACP

### Requirement: WebSocket transport
CodeLab SHALL support remote ACP agents over WebSocket for MVP remote workflows, including user-initiated and automatic reconnect after disconnect.

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

### Requirement: Тестирование transport
CodeLab SHALL включать fake transport и интеграционные тесты для stdio и совместимости с codelab-agent.

#### Scenario: Fake transport управляет core-тестами
- **WHEN** запускаются тесты state machine ядра
- **THEN** fake transport может детерминированно эмитировать входящие сообщения и перехватывать исходящие

#### Scenario: Stdio-интеграция обрабатывает ошибки процесса
- **WHEN** codelab-agent завершается, эмитирует невалидный JSON или пишет диагностику в stderr
- **THEN** CodeLab фиксирует типизированные состояния и диагностику, не падая

### Requirement: Web-безопасный публичный барель transport
Основная точка входа `package:acp_transports/acp_transports.dart` SHALL экспортировать порт transport и классы конфигурации (`StdioAcpTransportConfig`, `StdioAcpAgentProfile`, `WebSocketAcpTransportConfig`) без транзитивного импорта `dart:io`. Реализации `StdioAcpTransport` и `WebSocketAcpTransport` SHALL экспортироваться только из отдельной точки входа `package:acp_transports/io.dart`. Файлы основного бареля НЕ SHALL ссылаться на файлы IO-точки входа.

#### Scenario: Основной барель не тянет dart:io
- **WHEN** сторож архитектуры проверяет `packages/dart/acp_transports/lib/` по правилу web-безопасного пакета с исключением IO-точки входа
- **THEN** нарушений нет, а `grep -rn "dart:io"` по `lib/acp_transports.dart` и `lib/src/transport_configs.dart` ничего не находит

#### Scenario: Код создания транспорта импортирует io.dart
- **WHEN** composition root приложения создаёт `StdioAcpTransport` или `WebSocketAcpTransport`
- **THEN** он импортирует `package:acp_transports/io.dart`, а поведение подключения по stdio и WebSocket не меняется — интеграционные тесты stdio проходят

### Requirement: Серверные транспорты ACP
`package:acp_transports/io.dart` SHALL экспортировать серверные транспорты агента:
- `StdioServerAcpTransport` — stdin/stdout процесса (параметры потоков для тестов): одна строка UTF-8 — одно сообщение, длина строки не ограничена, запись сообщений не перемешивается, пустые строки пропускаются, EOF входа закрывает `inbound`;
- `WebSocketServerAcpTransport` — обёртка над принятым `WebSocket` из `dart:io`: один текстовый кадр — одно сообщение, закрытие сокета закрывает `inbound`.

Плохой сырой кадр транспорт SHALL обрабатывать сам и не закрывать соединение (ACP-4): неразбираемый JSON — ответ `-32700` с `id: null`; JSON не JSON-RPC 2.0 — `-32600` с `id` кадра, если он читается, иначе `null`; бинарный кадр WebSocket — `-32600`. О каждом таком кадре транспорт SHALL сообщать событием `diagnostic` уровня `warning`. Серверные транспорты НЕ SHALL экспортироваться из web-безопасного бареля.

#### Scenario: Мегабайтная строка
- **WHEN** во вход `StdioServerAcpTransport` записана одна строка с сообщением размером 2 МиБ
- **THEN** `inbound` отдаёт одно сообщение целиком

#### Scenario: Неразбираемый JSON
- **WHEN** во вход серверного транспорта приходит строка `{"jsonrpc": "2.0", "id": 1,`
- **THEN** транспорт отправляет `{"jsonrpc":"2.0","id":null,"error":{"code":-32700,…}}`, а следующий корректный запрос доходит до `inbound`

#### Scenario: Не JSON-RPC
- **WHEN** приходит `{"id": 7, "method": "initialize"}` без `jsonrpc`
- **THEN** транспорт отвечает `-32600` с `id: 7`, соединение живёт

#### Scenario: Порядок записи
- **WHEN** сервер отправляет 1 000 сообщений подряд без ожидания
- **THEN** выход содержит 1 000 строк в порядке отправки, каждая — целое сообщение

