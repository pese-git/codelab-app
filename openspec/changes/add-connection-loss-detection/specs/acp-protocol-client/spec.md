## ADDED Requirements

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
