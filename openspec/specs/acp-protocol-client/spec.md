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
CodeLab SHALL кодировать, декодировать и валидировать сообщения ACP как запросы, ответы и уведомления JSON-RPC 2.0. Незнакомые корневые поля в result-объектах ответов агента и в уведомлениях `session/update` (на любом уровне вложенности) SHALL игнорироваться при decode, а не приводить к отказу всего сообщения; игнорируемое поле CodeLab НЕ SHALL интерпретировать, использовать или сохранять.

#### Scenario: Валидное входящее сообщение
- **WHEN** получено валидное JSON-RPC сообщение ACP
- **THEN** `codelab_acp_protocol` декодирует его в типизированную модель

#### Scenario: Невалидное входящее сообщение
- **WHEN** получен невалидный JSON или невалидная форма ACP
- **THEN** CodeLab выдаёт типизированную протокольную ошибку и не падает

#### Scenario: Незнакомое поле в ответе агента
- **WHEN** result-объект ответа агента (например, `session/new`) содержит корневое поле, которого нет в типизированной модели CodeLab (например, `models`), на верхнем уровне или во вложенном объекте
- **THEN** CodeLab decode'ит остальную, известную часть ответа без ошибки, молча игнорируя незнакомое поле, и продолжает работу как с совместимым ответом

#### Scenario: Структурно невалидный ответ агента по-прежнему отвергается
- **WHEN** result-объект ответа агента не является JSON-объектом, не содержит обязательного поля, содержит поле известного имени неверного типа или значение неизвестного discriminator
- **THEN** CodeLab выдаёт типизированную протокольную ошибку, как и для любой другой невалидной формы ACP-сообщения

#### Scenario: Незнакомое поле в уведомлении session/update
- **WHEN** уведомление `session/update` известного вида (например, `agent_message_chunk`) содержит корневое поле, которого нет в типизированной модели CodeLab (например, `messageId`), на верхнем уровне или во вложенном объекте
- **THEN** CodeLab decode'ит остальную, известную часть обновления без ошибки, молча игнорируя незнакомое поле, и применяет обновление к состоянию сессии как совместимое

#### Scenario: Структурно невалидное уведомление session/update по-прежнему отвергается
- **WHEN** уведомление `session/update` известного вида не содержит обязательного поля, содержит поле известного имени неверного типа или значение неизвестного discriminator внутри известного вида (например, `type` content-блока)
- **THEN** CodeLab выдаёт типизированную протокольную ошибку и не применяет обновление к состоянию сессии

#### Scenario: Незнакомое поле вне ответов агента и session/update
- **WHEN** параметры запроса, который отправляет CodeLab, либо параметры запроса, присланного агентом (`session/request_permission`, `fs/*`, `terminal/*`), содержат незнакомое корневое поле
- **THEN** CodeLab продолжает выдавать типизированную протокольную ошибку

### Requirement: Неподдерживаемые запросы агента отклоняются как Method not found
CodeLab SHALL отвечать JSON-RPC ошибкой `-32601` «Method not found» с тем же `id` на каждый входящий запрос агента, метод которого CodeLab не обрабатывает, и SHALL оставаться работоспособным после такого запроса. CodeLab НЕ SHALL отвечать на входящие уведомления с неизвестным методом.

#### Scenario: Кастомный запрос агента
- **WHEN** агент присылает запрос с методом, начинающимся с `_` (например, `_vendor/feature`), которого CodeLab не поддерживает
- **THEN** CodeLab отправляет ответ с `error.code = -32601` и тем же `id`, не выполняя никаких действий по этому запросу

#### Scenario: Неизвестный стандартный метод
- **WHEN** агент присылает запрос с методом, которого нет среди обрабатываемых CodeLab
- **THEN** CodeLab отправляет ответ `-32601 Method not found` с тем же `id`

#### Scenario: Соединение продолжает работать
- **WHEN** CodeLab отклонил неподдерживаемый запрос агента
- **THEN** соединение остаётся в состоянии готовности, а последующие поддерживаемые сообщения обрабатываются как обычно

#### Scenario: Неизвестное уведомление не получает ответа
- **WHEN** агент присылает уведомление (сообщение без `id`) с неизвестным методом, например `_auth/status_update`
- **THEN** CodeLab ничего не отправляет в ответ и не считает это ошибкой

### Requirement: Инициализация и capabilities
CodeLab SHALL выполнять `initialize` перед настройкой сессии и SHALL учитывать согласованную версию протокола и capabilities. Незнакомые поля в ответе агента на `initialize` — как внутри capability-объектов (`agentCapabilities` и всё, что вложено под ним — `sessionCapabilities`, `mcpCapabilities`, `promptCapabilities` и их дочерние объекты), так и на корневом уровне ответа — SHALL игнорироваться при decode, а не приводить к отказу всего `initialize`.

#### Scenario: Совместимая версия протокола
- **WHEN** агент отвечает на `initialize` поддерживаемой `protocolVersion`
- **THEN** CodeLab сохраняет информацию об агенте, capabilities и переходит в состояние готовности к созданию сессии

#### Scenario: Неподдерживаемая версия протокола
- **WHEN** агент отвечает неподдерживаемой `protocolVersion`
- **THEN** CodeLab закрывает соединение и показывает пользователю понятную ошибку несовместимости

#### Scenario: Незнакомое поле внутри capability-объекта
- **WHEN** ответ на `initialize` содержит внутри `agentCapabilities` (включая вложенные `sessionCapabilities`/`mcpCapabilities`/`promptCapabilities`) поле, которого нет в типизированной модели CodeLab
- **THEN** CodeLab decode'ит остальную, понятную часть `agentCapabilities` без ошибки, молча игнорируя незнакомое поле, и продолжает handshake как при совместимой версии протокола

#### Scenario: Незнакомое поле на корневом уровне ответа initialize
- **WHEN** ответ на `initialize` содержит вне `agentCapabilities` корневое поле, которого нет в типизированной модели CodeLab
- **THEN** CodeLab decode'ит остальную часть ответа без ошибки, игнорируя незнакомое поле

#### Scenario: Незнакомое поле в параметрах запроса initialize
- **WHEN** параметры запроса `initialize` (а не ответа на него) содержат незнакомое корневое поле
- **THEN** CodeLab продолжает выдавать типизированную протокольную ошибку

### Requirement: Настройка сессии
CodeLab SHALL поддерживать `session/new` и SHALL вызывать `session/load` только когда доступен `agentCapabilities.loadSession`. При `session/load` CodeLab SHALL восстанавливать историю, которую агент повторяет уведомлениями `session/update` до ответа на запрос, и SHALL NOT считать сессию загруженной до ответа.

#### Scenario: Создаётся новая сессия
- **WHEN** пользователь создаёт сессию
- **THEN** CodeLab отправляет `session/new` с абсолютным `cwd` и сохраняет полученный `sessionId`

#### Scenario: Load session не поддерживается
- **WHEN** агент не заявляет `loadSession`
- **THEN** CodeLab не предлагает и не вызывает `session/load`

#### Scenario: Загруженная сессия показывает повторённую историю
- **WHEN** агент в ответ на `session/load` присылает до ответа `user_message_chunk`, `tool_call` с итоговым статусом и `agent_message_chunk`, а затем отвечает на запрос
- **THEN** после ответа сессия содержит завершённый ход с репликой пользователя в prompt, вызовом инструмента с его статусом и ответом агента, и ни один ход реплея не показан выполняющимся

#### Scenario: Границы ходов в реплее
- **WHEN** в реплее `user_message_chunk` следует за ответом агента
- **THEN** CodeLab начинает новый ход, а подряд идущие `user_message_chunk` объединяет в одну реплику пользователя

#### Scenario: Сессионные обновления реплея
- **WHEN** в реплее приходят `current_mode_update`, `config_option_update`, `available_commands_update` и `session_info_update`
- **THEN** CodeLab применяет их к сессии (текущий режим, опции, команды, заголовок), а режимы и опции из ответа на `session/load` имеют приоритет

#### Scenario: Ошибка session/load
- **WHEN** агент отвечает на `session/load` ошибкой после части реплея
- **THEN** CodeLab не создаёт сессию и отбрасывает накопленные обновления реплея

#### Scenario: Режим и заголовок вне хода
- **WHEN** агент присылает `current_mode_update` или `session_info_update` при отсутствии активного хода
- **THEN** CodeLab обновляет текущий режим или заголовок сессии; `session_info_update` без `title` заголовок не меняет

### Requirement: Жизненный цикл prompt turn
CodeLab SHALL поддерживать `session/prompt`, потоковые `session/update`, `session/request_permission`, `session/cancel` и финальный ответ `session/prompt` со `stopReason`. Уведомление `session/update` с незнакомым видом обновления (`sessionUpdate`) SHALL пропускаться без ошибки и без изменения состояния сессии.

#### Scenario: Prompt стримит обновления
- **WHEN** пользователь отправляет prompt
- **THEN** CodeLab отправляет `session/prompt` и рендерит входящие уведомления `session/update` как типизированные события таймлайна

#### Scenario: Prompt завершается
- **WHEN** агент отвечает на `session/prompt` со `stopReason`
- **THEN** CodeLab помечает активный prompt turn как completed, failed, refused, maxed или cancelled в соответствии со stop reason

#### Scenario: Ответ агента с дополнительным полем доходит до таймлайна
- **WHEN** агент во время prompt turn присылает `agent_message_chunk` с корневым полем, которого нет в типизированной модели (например, `messageId`)
- **THEN** CodeLab добавляет текст чанка в ответ агента в таймлайне так же, как для чанка без этого поля

#### Scenario: Незнакомый вид обновления пропускается
- **WHEN** агент присылает `session/update`, чей `sessionUpdate` не входит в виды, известные CodeLab (например, `usage_update`)
- **THEN** CodeLab не меняет состояние сессии, не создаёт диагностику уровня error, записывает в application-журнал одну запись уровня DEBUG с видом обновления и идентификатором сессии без содержимого, и продолжает обрабатывать последующие обновления и ответ на `session/prompt`

#### Scenario: Payload пропущенного обновления доступен только в protocol-трассировке
- **WHEN** CodeLab пропускает `session/update` незнакомого вида
- **THEN** CodeLab дополнительно записывает в developer-only журнал `category=protocol` событие с тем же текстом, видом обновления, идентификатором сессии и полным payload уведомления с маскированием секретов, а application-журнал (console, `application.log`, сервер логов) payload не получает

### Requirement: Идемпотентные переходы состояния
CodeLab SHALL обрабатывать дублирующиеся, запоздавшие или чередующиеся события потока, не повреждая видимое состояние сессии. Чанки содержимого (`agent_message_chunk`, `agent_thought_chunk`, `user_message_chunk`) SHALL считаться приращениями и SHALL NOT дедуплицироваться по равенству: ACP не даёт им ключа, по которому повторную доставку можно отличить от следующей дельты с тем же текстом. Обновление-снимок SHALL считаться дублем, только если оно равно последнему полученному в ходе обновлению того же вида.

#### Scenario: Приходит дублирующееся обновление
- **WHEN** одно и то же обновление-снимок сессии (`tool_call`, `tool_call_update`, `plan`, `current_mode_update` и другие обновления, не являющиеся чанками) доставлено более одного раза
- **THEN** CodeLab не дублирует видимые сообщения, approvals или записи tool call

#### Scenario: Снимок возвращается к прежнему значению
- **WHEN** в одном ходе агент присылает `plan` A, затем `plan` B, затем снова `plan` A (или так же `current_mode_update`)
- **THEN** CodeLab применяет третье обновление, и текущим становится A, а не B

#### Scenario: Повторяющиеся одинаковые чанки
- **WHEN** агент присылает несколько `agent_message_chunk` (или `agent_thought_chunk`, `user_message_chunk`) с одинаковым текстом, подряд или вперемешку с другими обновлениями
- **THEN** CodeLab сохраняет каждую дельту, и видимый текст равен склейке всех присланных дельт

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

### Requirement: Отмена prompt turn
CodeLab SHALL после отправки `session/cancel` держать prompt turn в нетерминальном состоянии «отменяется» до ответа агента на `session/prompt` этого хода (`05-Prompt Turn.md#cancellation`). В этом состоянии CodeLab SHALL применять к ходу входящие `session/update`, SHALL NOT начинать в сессии новый prompt turn и SHALL отвечать `cancelled` на `session/request_permission`. Незавершённые вызовы инструментов хода (`pending`, `in_progress`) CodeLab SHALL пометить отменёнными в момент отправки `session/cancel`; так как в ACP `ToolCallStatus` нет значения `cancelled`, отменённый вызов хранится со статусом `failed` и признаком отмены клиентом.

#### Scenario: Незавершённые вызовы помечаются при отправке cancel
- **WHEN** пользователь отменяет ход, в котором есть вызов инструмента в статусе `in_progress` и вызов в статусе `completed`
- **THEN** CodeLab отправляет `session/cancel`, переводит ход в «отменяется», вызов `in_progress` получает статус `failed` с признаком отмены клиентом, а вызов `completed` не меняется

#### Scenario: Поздний tool_call_update того же хода принимается
- **WHEN** после `session/cancel`, но до ответа на `session/prompt` агент присылает `tool_call_update` для вызова этого хода с новым содержимым и статусом `failed`
- **THEN** CodeLab применяет содержимое и статус к вызову, вызов остаётся отменённым

#### Scenario: Нетерминальный статус не возвращает отменённый вызов в работу
- **WHEN** после `session/cancel` агент присылает для отменённого вызова `tool_call_update` со статусом `in_progress`
- **THEN** CodeLab применяет остальные поля обновления, но статус вызова остаётся `failed` с признаком отмены клиентом

#### Scenario: Вызов успел завершиться
- **WHEN** после `session/cancel` агент присылает для отменённого вызова `tool_call_update` со статусом `completed`
- **THEN** CodeLab переводит вызов в `completed` и снимает признак отмены клиентом

#### Scenario: Ответ на session/prompt завершает отмену
- **WHEN** агент отвечает на `session/prompt` отменяемого хода со `stopReason`
- **THEN** CodeLab переводит ход в терминальный статус по `stopReason` (`cancelled` для `cancelled`), а сессия снова может начать новый ход

#### Scenario: Обновление после ответа на session/prompt отбрасывается
- **WHEN** `session/update` приходит после ответа на `session/prompt` отменённого хода, и новый ход ещё не начат
- **THEN** CodeLab не меняет состояние завершённого хода

#### Scenario: Новый ход не начинается до ответа агента
- **WHEN** ход в сессии отменяется и ответ на его `session/prompt` ещё не пришёл, а клиент пытается начать новый prompt turn в этой сессии
- **THEN** CodeLab отклоняет начало хода без отправки `session/prompt`

#### Scenario: Повторная отмена идемпотентна
- **WHEN** пользователь повторно отменяет ход, который уже «отменяется»
- **THEN** CodeLab не отправляет повторный `session/cancel` и возвращает тот же ход

#### Scenario: Запрос разрешения во время отмены
- **WHEN** агент присылает `session/request_permission`, пока ход «отменяется»
- **THEN** CodeLab сразу отвечает исходом `cancelled` и не создаёт approval

### Requirement: Ход, прерванный заменой транспорта
Если замена транспорта (`Reconnect`, повторное подключение) прервала идущий ход сессии, CodeLab SHALL после успешного `session/load` этой сессии показывать последний ход реплея отменённым: статус `cancelled`, `stopReason` `cancelled`. Отметка о прерывании SHALL применяться один раз, SHALL сохраняться после неудачного `session/load` и SHALL сниматься новым `session/prompt` этой сессии. Обновления хода, пришедшие после ответа на `session/load` при отсутствии активного хода, SHALL отбрасываться, как прежде.

#### Scenario: Прерванный ход после загрузки
- **WHEN** во время хода транспорт заменяется, а затем сессия загружается через `session/load` с реплеем реплики пользователя
- **THEN** последний ход сессии содержит реплику пользователя и имеет статус `cancelled` со `stopReason` `cancelled`, активного хода нет

#### Scenario: Загрузка без прерванного хода
- **WHEN** загружается сессия, ход которой не прерывался заменой транспорта
- **THEN** ходы реплея завершены без `stopReason`, как в «Загруженная сессия показывает повторённую историю»

#### Scenario: Позднее обновление не открывает ход
- **WHEN** после `session/load` прерванной сессии агент присылает `agent_message_chunk`
- **THEN** обновление отбрасывается, последний ход остаётся `cancelled`

#### Scenario: Отметка переживает неудачную загрузку
- **WHEN** первый `session/load` прерванной сессии завершается ошибкой, а второй — успешно
- **THEN** после второго последний ход реплея показан `cancelled`

### Requirement: Исходящий session/list
CodeLab SHALL запрашивать список сессий агента методом `session/list` только после `initialize` и только если агент объявил `agentCapabilities.sessionCapabilities.list`; без этой capability CodeLab НЕ SHALL отправлять `session/list` и SHALL возвращать вызывающему типизированную ошибку. Параметры `cwd` (абсолютный путь) и `cursor` SHALL быть необязательными. Результат SHALL быть страницей сессий (`sessionId`, `cwd`, `title`, `updatedAt`) и `nextCursor`; курсор CodeLab SHALL передавать обратно без разбора и изменения и НЕ SHALL сохранять между запусками; отсутствие `nextCursor` SHALL означать конец списка.

#### Scenario: Агент объявил список сессий
- **WHEN** агент объявил `sessionCapabilities.list`, и клиент запрашивает список с `cwd: "/work/app"`
- **THEN** CodeLab отправляет `session/list` с `cwd`, возвращает страницу сессий агента и `nextCursor` из ответа

#### Scenario: Следующая страница
- **WHEN** клиент запрашивает список с курсором из предыдущего `nextCursor`
- **THEN** CodeLab отправляет тот же курсор без изменений, а ответ без `nextCursor` считает последней страницей

#### Scenario: Агент не объявил список сессий
- **WHEN** в ответе `initialize` нет `sessionCapabilities.list`, и клиент запрашивает список
- **THEN** CodeLab не отправляет `session/list` и возвращает типизированную ошибку

### Requirement: Таймаут исходящих запросов
Каждый исходящий JSON-RPC запрос CodeLab, кроме `session/prompt`, SHALL ограничиваться таймаутом `requestTimeout` (по умолчанию 60 секунд). По истечении таймаута CodeLab SHALL снимать ожидание ответа и завершать запрос типизированной ошибкой таймаута с именем метода; поздний ответ на снятый запрос НЕ SHALL менять состояние клиента. Запрос `session/prompt` таймаутом НЕ SHALL ограничиваться: ход прерывается `session/cancel`.

#### Scenario: Агент не отвечает на запрос
- **WHEN** агент не отвечает на `session/new` дольше `requestTimeout`
- **THEN** вызов завершается типизированной ошибкой таймаута с методом `session/new`, а сессия не создаётся

#### Scenario: Поздний ответ после таймаута
- **WHEN** ответ на запрос приходит после истечения его таймаута
- **THEN** CodeLab записывает его в журнал как ответ без ожидающего запроса и не меняет состояние сессий

#### Scenario: Долгий ход не прерывается таймаутом
- **WHEN** ход `session/prompt` длится дольше `requestTimeout`
- **THEN** CodeLab продолжает ждать ответ на `session/prompt`

### Requirement: Типизированный сбой prompt turn
Когда `session/prompt` завершается ошибкой, CodeLab SHALL сохранять в сорвавшемся ходе типизированный `PromptFailure` наряду с текстом для диагностики:

- `agent` — JSON-RPC ошибка, у которой `data.codelab` — объект; несёт `errorClass` (строка или нет), `message` и `retryable` (`bool` или нет);
- `request` — JSON-RPC ошибка без объекта `data.codelab`; несёт `code` и `message`;
- `connectionLost` — ход прерван неожиданным отказом транспорта текущего соединения;
- `unknown` — любой другой сбой.

Разбор `data.codelab` SHALL выполняться в протокольном клиенте. Незнакомое значение `errorClass` SHALL сохраняться как есть. Поле неожиданного типа SHALL считаться отсутствующим, не ломая разбор ответа.

#### Scenario: Сбой провайдера у агента CodeLab
- **WHEN** агент отвечает на `session/prompt` ошибкой `-32603` с `data.codelab: {"errorClass": "auth", "message": "401 Unauthorized from openai: check api_key_env", "retryable": false}`
- **THEN** ход имеет статус `failed` и `PromptFailure.agent` с `errorClass: "auth"`, этим сообщением и `retryable: false`

#### Scenario: Ошибка без расширения CodeLab
- **WHEN** агент отвечает на `session/prompt` ошибкой `-32603` без поля `data`
- **THEN** ход имеет статус `failed` и `PromptFailure.request` с кодом `-32603` и сообщением JSON-RPC

#### Scenario: Незнакомый класс сбоя
- **WHEN** `data.codelab.errorClass` — строка, не известная CodeLab, а `retryable` — не `bool`
- **THEN** ход имеет `PromptFailure.agent` с этой строкой в `errorClass` и `retryable: null`

#### Scenario: Ход прерван обрывом соединения
- **WHEN** во время хода транспорт текущего соединения неожиданно отказывает
- **THEN** ход имеет статус `failed` и `PromptFailure.connectionLost`

