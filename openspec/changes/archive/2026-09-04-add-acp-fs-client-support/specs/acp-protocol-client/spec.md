## ADDED Requirements

### Requirement: Заявление реальных client capabilities при initialize
CodeLab SHALL отправлять в `InitializeRequest.clientCapabilities.fs` значения `readTextFile`/`writeTextFile`, соответствующие фактически реализованным и зарегистрированным в `acpMethodRegistry` обработчикам `fs/read_text_file`/`fs/write_text_file`, вместо неявного значения по умолчанию `false`.

#### Scenario: Клиент поддерживает fs-методы
- **WHEN** CodeLab выполняет `initialize`, и обработчики `fs/read_text_file`/`fs/write_text_file` реализованы и зарегистрированы
- **THEN** `InitializeRequest.clientCapabilities.fs.readTextFile` и `writeTextFile` отправляются как `true`

#### Scenario: Метод не реализован
- **WHEN** CodeLab выполняет `initialize`, и обработчик `fs/write_text_file` (или `fs/read_text_file`) не зарегистрирован в `acpMethodRegistry`
- **THEN** соответствующее поле `clientCapabilities.fs` отправляется как `false`, и агент не должен вызывать этот метод
