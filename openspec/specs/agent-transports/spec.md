## Purpose

Заменяемый транспортный слой, соединяющий CodeLab с процессом или endpoint'ом ACP-агента — общий порт transport, конкретные реализации stdio и WebSocket, встроенный референсный профиль `Codelab Agent`, а также fake/test-двойники, используемые для проверки остального приложения без реального агента.
## Requirements
### Requirement: Общий порт transport
CodeLab SHALL предоставлять общую абстракцию transport для входящих сообщений, исходящей отправки, событий жизненного цикла, штатного завершения и типизированных ошибок.

#### Scenario: Transport заменяем
- **WHEN** core-логика отправляет или получает сообщения ACP
- **THEN** она работает через порт transport, а не через конкретные классы stdio/WebSocket

#### Scenario: Transport падает
- **WHEN** соединение transport падает
- **THEN** CodeLab отображает сбой в типизированное состояние transport и понятную пользователю диагностику

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

