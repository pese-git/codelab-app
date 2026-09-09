## ADDED Requirements

### Requirement: Logger-абстракция вместо print/debugPrint
CodeLab SHALL предоставлять единую Logger-абстракцию (порт), реализованную поверх `structured_log`, и SHALL использовать её вместо `print`/`debugPrint` для любого значимого lifecycle/diagnostic-события production-кода.

#### Scenario: Значимое событие эмитится как structured-запись
- **WHEN** происходит значимое lifecycle-событие (например, установлено соединение)
- **THEN** CodeLab записывает structured-событие через Logger с machine-readable полями (как минимум `event`, `outcome`), а не произвольной строкой через `print`/`debugPrint`

### Requirement: Correlation-идентификаторы на значимых событиях
CodeLab SHALL включать в structured-события стабильные correlation-идентификаторы — `session_id`, `request_id`, `connection_generation`, а где применимо `tool_call_id` — переиспользуя уже существующие в приложении значения (session-scoping, `AcpClientApplication.generation`, request/tool-call identifiers), не создавая параллельной схемы идентификаторов.

#### Scenario: Reconnect логируется с connection_generation
- **WHEN** CodeLab выполняет reconnect транспорта
- **THEN** structured-событие reconnect содержит `connection_generation`, значение которого совпадает с текущим `AcpClientApplication.generation` после реконнекта

#### Scenario: Stale-событие логируется с correlation исходного запроса
- **WHEN** приходит событие, относящееся к операции из предыдущего `connection_generation`
- **THEN** CodeLab логирует его как проигнорированное (`reason=stale_generation` или эквивалент) вместе с `connection_generation` этого устаревшего события, не применяя его к текущему state

### Requirement: Маскирование секретов в structured-выводе
CodeLab SHALL маскировать секреты (токены, пароли, API-ключи, авторизационные заголовки, приватные ключи) в каждом structured-событии до того, как оно достигнет log sink, переиспользуя существующий `SecretRedactor`, а не отдельный набор правил редактирования.

#### Scenario: Секрет в context-поле маскируется
- **WHEN** структурное событие содержит в context-поле значение с ключом, распознаваемым как секрет (например, `token`, `password`, `api_key`)
- **THEN** значение этого поля в итоговом structured-выводе заменено на редактированное значение (например, `<redacted>`), а не показано в открытом виде

#### Scenario: Секрет внутри свободного текста сообщения маскируется
- **WHEN** текст сообщения события содержит authorization-подобное значение (например, `Bearer <token>`) или блок приватного ключа
- **THEN** это значение замаскировано в итоговом structured-выводе тем же способом, что и в существующем UI debug-логе (inspector)

### Requirement: Логирование по слоям согласно ownership
CodeLab SHALL помечать structured-события компонентом-источником согласно ownership-модели (`acp_protocol` → protocol-ошибки, `acp_transports` → transport lifecycle, `acp_client_core` → session/request lifecycle, presentation → user intents/UI failures), и presentation-слой SHALL NOT дублировать полный protocol-trace, который уже логируется на уровне ниже.

#### Scenario: Transport diagnostic-событие помечено своим компонентом
- **WHEN** `acp_transports` эмитит `AcpTransportEvent.diagnostic`
- **THEN** соответствующее structured-событие помечено источником transport-слоя (например, `component=transport`), а не общим/безымянным источником

#### Scenario: Protocol-ошибка помечена своим компонентом
- **WHEN** `acp_protocol` выбрасывает типизированную ошибку разбора сообщения, и она перехвачена вышестоящим слоем
- **THEN** соответствующее structured-событие помечено источником protocol-слоя (например, `component=protocol`)

### Requirement: Ограниченная (bounded) история diagnostic-событий
CodeLab SHALL хранить in-memory историю diagnostic-событий (используемую UI debug-панелью/инспектором) в ограниченном по размеру буфере, а не в неограниченно растущем списке.

#### Scenario: Превышение лимита вытесняет старые записи
- **WHEN** число diagnostic-записей в рамках одной сессии превышает установленный лимит буфера
- **THEN** CodeLab отбрасывает самые старые записи, сохраняя лимит, и не продолжает неограниченно расходовать память на историю

### Requirement: Protocol tracing выключен по умолчанию в release
CodeLab SHALL держать полный ACP payload tracing выключенным по умолчанию в release-сборке и SHALL включать его только явным debug/developer-действием, не автоматически при возникновении ошибки.

#### Scenario: Release-сборка не пишет полный payload по умолчанию
- **WHEN** CodeLab работает как release-сборка без явно включённого protocol tracing
- **THEN** structured-события lifecycle не содержат полного сырого ACP payload — только method/type, ids, размер и outcome

#### Scenario: Явное включение раскрывает полный payload
- **WHEN** пользователь или разработчик явно включает protocol tracing (debug/runtime-настройка)
- **THEN** CodeLab начинает включать полный ACP payload в trace-уровневые structured-события, пока настройка не выключена явно

### Requirement: Существующий контракт diagnostics-потока не меняется
CodeLab SHALL сохранять неизменной внешнюю форму существующего diagnostics-потока (`AcpClientApplication.diagnostics`, используемого `inspector_pane.dart`) при добавлении structured-логирования — новый Logger-вывод является дополнительным output к тому же, уже отредактированному через `SecretRedactor`, набору полей, а не заменой этого потока.

#### Scenario: Inspector продолжает получать diagnostic-записи в прежней форме
- **WHEN** происходит diagnostic-событие после включения structured-логирования
- **THEN** `AcpClientApplication.diagnostics`/`inspector_pane.dart` получают запись той же формы (`DiagnosticEntry` с теми же полями), что и до этого change
