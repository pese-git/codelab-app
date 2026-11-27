## MODIFIED Requirements

### Requirement: Protocol tracing выключен по умолчанию в release
CodeLab SHALL держать полный ACP payload tracing выключенным по умолчанию в release-сборке и SHALL включать его только явным debug/developer-действием, не автоматически при возникновении ошибки.

Полнота payload SHALL определяться политикой payload ядра клиента, которую задаёт хост (acp-protocol-client «Кадры ACP клиента»; design.md change `redesign-protocol-pane`, D3): desktop — `full` только в debug-сборке, CLI — `full` только с `--verbose`, по умолчанию — `metadataOnly`. При `metadataOnly` запись `protocol_message` SHALL нести направление, вид, метод, id, размер и корреляцию (`session_id`, `connection_generation`), но не `payload` — в любом sink, включая встроенный журнал app и файл `protocol.log`. Включение файла `protocol.log` SHALL оставаться отдельным явным действием и SHALL NOT менять политику payload. Это же правило SHALL действовать на диагностику ядра в ветках ошибок декодирования и обработки сообщений (сбой декодирования ответа или запроса, пропуск неподдерживаемого `sessionUpdate`): при `metadataOnly` такие записи SHALL нести только метаданные (метод, id, сессию, размер, класс ошибки) и SHALL NOT нести сырые `params`, `result` или `payload` (решение пользователя 2026-11-23). Текст ответа-ошибки агента (`error.message` и `error.data`) — тоже payload: при `metadataOnly` диагностика ядра клиента (`DiagnosticEntry`), диагностика kit (`WorkspaceDiagnostic`) и записи журнала app о сбое SHALL нести только метод, id, сессию, код ошибки, стандартное имя кода, класс ошибки и постоянный текст CodeLab и SHALL NOT нести `error.message`, `error.data` или текст исключения, в которое они вложены; текст для пользователя (сообщение хода в транскрипте, баннер соединения, вывод CLI) SHALL сохранять текст агента после маскирования секретов при любой политике (design.md change `redesign-protocol-pane`, D3, «Текст ошибки агента»). Поле `cause` записи журнала SHALL нести только причину диагностики, а вложенная причина — отдельный ключ `inner_cause`; ни одно значение SHALL NOT перекрываться. Режим Trace кадров (acp-protocol-client «Кадры ACP клиента») SHALL NOT менять запись `protocol_message`: полные payload в режиме Trace есть только в буфере кадров, а не в журнале и не в файле (design.md change `redesign-protocol-pane`, D17).

#### Scenario: Release-сборка не пишет полный payload по умолчанию
- **WHEN** CodeLab работает как release-сборка без явно включённого protocol tracing
- **THEN** structured-события lifecycle не содержат полного сырого ACP payload — только method/type, ids, размер и outcome

#### Scenario: Встроенный журнал release-сборки без payload
- **WHEN** release-сборка app отправляет `session/prompt` с текстом промпта
- **THEN** запись `protocol_message` во встроенном журнале (вид `Log` панели Protocol и полноэкранный просмотр) содержит `direction`, `method` `session/prompt`, `request_id` и `size`, но не содержит `payload` и текста промпта

#### Scenario: Явное включение раскрывает полный payload
- **WHEN** хост работает с политикой payload `full` (debug-сборка app или CLI с `--verbose`)
- **THEN** CodeLab включает в protocol-trace structured-события (отдельный канал полного трейсинга, помеченный как `protocol`) полный ACP payload после маскирования секретов

#### Scenario: Trace не пишет payload в журнал
- **WHEN** release-сборка app с включённым Trace отправляет `session/prompt`
- **THEN** кадр в панели Protocol несёт payload, а запись `protocol_message` во встроенном журнале и в `protocol.log` — нет

#### Scenario: Неподдерживаемый sessionUpdate в release
- **WHEN** release-сборка с политикой `metadataOnly` получает `session/update` с незнакомым значением `sessionUpdate` и пропускает его
- **THEN** запись журнала о пропуске несёт метод, `sessionUpdate`, `session_id` и размер, но не `payload` уведомления

#### Scenario: Сбой декодирования ответа в release
- **WHEN** release-сборка с политикой `metadataOnly` получает ответ, `result` которого не декодируется в ожидаемый тип
- **THEN** диагностика и запись журнала о сбое несут метод, `request_id`, размер и класс ошибки, но не `result` и не `params`

#### Scenario: Ошибка агента в release
- **WHEN** хост с политикой `metadataOnly` получает ответ-ошибку `-32603` на `session/prompt`, у которой `error.message` содержит путь к файлу, а `error.data` — фрагмент данных
- **THEN** диагностика ядра, диагностика kit и запись журнала о сбое несут метод, `request_id`, код `-32603` и имя `Internal error`, но не текст `error.message` и не `error.data`
- **AND** сообщение хода в транскрипте содержит текст `error.message` агента после маскирования секретов

#### Scenario: Ошибка агента при явном включении
- **WHEN** хост с политикой `full` получает тот же ответ-ошибку, `error.message` которой содержит токен
- **THEN** диагностика и запись журнала о сбое несут текст `error.message` и `error.data` агента, а токен замаскирован

#### Scenario: Ключ причины не перекрывается
- **WHEN** транспорт падает с ошибкой, у которой есть вложенная причина
- **THEN** запись журнала о сбое несёт и `cause` (причину диагностики), и `inner_cause` (вложенную причину)

### Requirement: Существующий контракт diagnostics-потока не меняется
CodeLab SHALL сохранять неизменной внешнюю форму существующего diagnostics-потока (`AcpClientApplication.diagnostics`) при добавлении structured-логирования — новый Logger-вывод является дополнительным output к тому же, уже отредактированному через `SecretRedactor`, набору полей, а не заменой этого потока.

#### Scenario: Diagnostics-поток сохраняет форму записей
- **WHEN** происходит diagnostic-событие после включения structured-логирования
- **THEN** подписчики `AcpClientApplication.diagnostics` получают запись той же формы (`DiagnosticEntry` с теми же полями), что и до этого change
