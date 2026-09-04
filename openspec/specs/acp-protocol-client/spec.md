## Purpose

Реализация CodeLab самого Agent Client Protocol (ACP) — обработка сообщений JSON-RPC 2.0, handshake `initialize`, настройка сессии и жизненный цикл prompt turn, а также идемпотентная обработка получаемого потока событий. Эта capability — граница wire-протокола между CodeLab и любым ACP-совместимым агентом; её нормативный источник — `docs/acp/protocol/`.
## Requirements
### Requirement: Официальный источник истины ACP
CodeLab SHALL реализовывать поведение ACP в соответствии с `docs/acp/protocol/` и `docs/acp/protocol/17-Schema.md`.

#### Scenario: Изменение протокольного контракта
- **WHEN** реализуются модели или методы сообщений ACP
- **THEN** они соответствуют официальной документации протокола и файлам схемы

#### Scenario: Требуется собственное расширение
- **WHEN** CodeLab добавляет собственные протокольные данные или методы
- **THEN** собственные данные используют `_meta`, а имена собственных методов начинаются с `_`

### Requirement: Обработка сообщений JSON-RPC 2.0
CodeLab SHALL кодировать, декодировать и валидировать сообщения ACP как запросы, ответы и уведомления JSON-RPC 2.0.

#### Scenario: Валидное входящее сообщение
- **WHEN** получено валидное JSON-RPC сообщение ACP
- **THEN** `acp_protocol` декодирует его в типизированную модель

#### Scenario: Невалидное входящее сообщение
- **WHEN** получен невалидный JSON или невалидная форма ACP
- **THEN** CodeLab выдаёт типизированную протокольную ошибку и не падает

### Requirement: Инициализация и capabilities
CodeLab SHALL выполнять `initialize` перед настройкой сессии и SHALL учитывать согласованную версию протокола и capabilities.

#### Scenario: Совместимая версия протокола
- **WHEN** агент отвечает на `initialize` поддерживаемой `protocolVersion`
- **THEN** CodeLab сохраняет информацию об агенте, capabilities и переходит в состояние готовности к созданию сессии

#### Scenario: Неподдерживаемая версия протокола
- **WHEN** агент отвечает неподдерживаемой `protocolVersion`
- **THEN** CodeLab закрывает соединение и показывает пользователю понятную ошибку несовместимости

### Requirement: Настройка сессии
CodeLab SHALL поддерживать `session/new` и SHALL вызывать `session/load` только когда доступен `agentCapabilities.loadSession`.

#### Scenario: Создаётся новая сессия
- **WHEN** пользователь создаёт сессию
- **THEN** CodeLab отправляет `session/new` с абсолютным `cwd` и сохраняет полученный `sessionId`

#### Scenario: Load session не поддерживается
- **WHEN** агент не заявляет `loadSession`
- **THEN** CodeLab не предлагает и не вызывает `session/load`

### Requirement: Жизненный цикл prompt turn
CodeLab SHALL поддерживать `session/prompt`, потоковые `session/update`, `session/request_permission`, `session/cancel` и финальный ответ `session/prompt` со `stopReason`.

#### Scenario: Prompt стримит обновления
- **WHEN** пользователь отправляет prompt
- **THEN** CodeLab отправляет `session/prompt` и рендерит входящие уведомления `session/update` как типизированные события таймлайна

#### Scenario: Prompt завершается
- **WHEN** агент отвечает на `session/prompt` со `stopReason`
- **THEN** CodeLab помечает активный prompt turn как completed, failed, refused, maxed или cancelled в соответствии со stop reason

### Requirement: Идемпотентные переходы состояния
CodeLab SHALL обрабатывать дублирующиеся, запоздавшие или чередующиеся события потока, не повреждая видимое состояние сессии.

#### Scenario: Приходит дублирующееся обновление
- **WHEN** одно и то же обновление сессии доставлено более одного раза
- **THEN** CodeLab не дублирует видимые сообщения, approvals или записи tool call

#### Scenario: Запоздавшее обновление после cancel
- **WHEN** запоздавший `session/update` приходит после `session/cancel`, но до ответа на prompt
- **THEN** CodeLab принимает его, не выводя turn из потока отмены

### Requirement: Исходящий session/set_config_option
CodeLab SHALL поддерживать исходящий метод `session/set_config_option` (request: `sessionId`, `configId`, `value`; response: полный обновлённый список `configOptions`) для изменения ранее объявленного агентом `SessionConfigOption`.

#### Scenario: Пользователь меняет значение опции
- **WHEN** активная сессия имеет `SessionConfigOption` с `id`, и пользователь выбирает новое значение из его `options`
- **THEN** CodeLab отправляет `session/set_config_option` с этим `configId` и выбранным `value`, и по ответу заменяет весь список `configOptions` сессии присланным агентом

#### Scenario: Агент отклоняет значение
- **WHEN** агент отвечает на `session/set_config_option` ошибкой JSON-RPC
- **THEN** CodeLab не изменяет `configOptions` сессии и показывает диагностику ошибки, не оставляя UI в неопределённом состоянии

### Requirement: Config option update применяется независимо от активного turn
CodeLab SHALL применять `SessionUpdate.configOptionUpdate` к `configOptions` сессии независимо от того, есть ли у сессии активный prompt turn — по ACP-спеке агент может прислать это обновление в любой момент сессии, а не только во время turn.

#### Scenario: Обновление приходит без активного turn
- **WHEN** сессия не имеет активного prompt turn, и агент присылает `SessionUpdate.configOptionUpdate`
- **THEN** CodeLab заменяет `configOptions` сессии присланным списком

#### Scenario: Обновление приходит во время активного turn
- **WHEN** у сессии есть активный prompt turn, и агент присылает `SessionUpdate.configOptionUpdate`
- **THEN** CodeLab заменяет `configOptions` сессии присланным списком и дополнительно записывает обновление в историю активного turn (для инспектора), не завершая и не изменяя статус самого turn

### Requirement: Устаревший канал session modes не используется при наличии config options
CodeLab SHALL игнорировать `SessionModeState`/`SessionUpdate.currentModeUpdate`, если та же сессия предоставляет `configOptions` — по ACP-спеке эти два канала взаимоисключающие для клиентов, поддерживающих config options.

#### Scenario: Агент присылает оба канала одновременно
- **WHEN** ответ `session/new` содержит одновременно непустые `modes` и `configOptions`
- **THEN** CodeLab отображает и использует только `configOptions`, не показывая никакого UI на основе `modes`

### Requirement: Неожиданный отказ транспорта транслируется в состояние соединения
CodeLab SHALL транслировать `AcpTransportEvent.failure` от активного транспорта в переход `ClientConnectionState` к `failed`, если соединение на момент отказа не находится в состоянии `disconnected`.

#### Scenario: Транспорт падает во время активного соединения
- **WHEN** соединение находится в состоянии `ready` (или `connecting`/`initializing`), и транспорт эмитит `AcpTransportEvent.failure`
- **THEN** CodeLab переводит `ClientConnectionState` в `failed` с причиной, соответствующей коду ошибки транспорта, и это изменение доступно через `AcpClientApplication.connectionStateChanges`

#### Scenario: Транспорт падает во время намеренного отключения
- **WHEN** соединение уже переведено в `disconnected` (например, в рамках намеренного `disconnect()` перед новым `connect()`), и старый транспорт после этого эмитит `AcpTransportEvent.failure`
- **THEN** CodeLab не пытается выполнить недопустимый переход `disconnected → failed` и не бросает исключение

#### Scenario: Событие от заменённого транспорта не влияет на текущее соединение
- **WHEN** транспорт был заменён (например, в рамках `reconnect()`), и старый (уже отвязанный) транспорт присылает запоздавшее `AcpTransportEvent.failure`
- **THEN** CodeLab не изменяет текущее состояние соединения, установленное новым транспортом

### Requirement: Заявление реальных client capabilities при initialize
CodeLab SHALL отправлять в `InitializeRequest.clientCapabilities.fs` значения `readTextFile`/`writeTextFile`, соответствующие фактически реализованным и зарегистрированным в `acpMethodRegistry` обработчикам `fs/read_text_file`/`fs/write_text_file`, вместо неявного значения по умолчанию `false`.

#### Scenario: Клиент поддерживает fs-методы
- **WHEN** CodeLab выполняет `initialize`, и обработчики `fs/read_text_file`/`fs/write_text_file` реализованы и зарегистрированы
- **THEN** `InitializeRequest.clientCapabilities.fs.readTextFile` и `writeTextFile` отправляются как `true`

#### Scenario: Метод не реализован
- **WHEN** CodeLab выполняет `initialize`, и обработчик `fs/write_text_file` (или `fs/read_text_file`) не зарегистрирован в `acpMethodRegistry`
- **THEN** соответствующее поле `clientCapabilities.fs` отправляется как `false`, и агент не должен вызывать этот метод

### Requirement: Заявление реальной поддержки terminal при initialize
CodeLab SHALL отправлять в `InitializeRequest.clientCapabilities.terminal` значение `true` только если все методы `terminal/create`, `terminal/output`, `terminal/wait_for_exit`, `terminal/kill`, `terminal/release` реализованы и зарегистрированы в `acpMethodRegistry`, и SHALL отправлять `false`, если поддержана лишь часть методов.

#### Scenario: Клиент поддерживает все terminal-методы
- **WHEN** CodeLab выполняет `initialize`, и все пять `terminal/*` методов реализованы и зарегистрированы
- **THEN** `InitializeRequest.clientCapabilities.terminal` отправляется как `true`

#### Scenario: Реализована лишь часть terminal-методов
- **WHEN** CodeLab выполняет `initialize`, и хотя бы один из пяти `terminal/*` методов не реализован
- **THEN** `InitializeRequest.clientCapabilities.terminal` отправляется как `false`, и агент не должен вызывать ни один из `terminal/*` методов

