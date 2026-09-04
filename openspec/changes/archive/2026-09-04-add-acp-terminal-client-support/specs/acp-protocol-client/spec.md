## ADDED Requirements

### Requirement: Заявление реальной поддержки terminal при initialize
CodeLab SHALL отправлять в `InitializeRequest.clientCapabilities.terminal` значение `true` только если все методы `terminal/create`, `terminal/output`, `terminal/wait_for_exit`, `terminal/kill`, `terminal/release` реализованы и зарегистрированы в `acpMethodRegistry`, и SHALL отправлять `false`, если поддержана лишь часть методов.

#### Scenario: Клиент поддерживает все terminal-методы
- **WHEN** CodeLab выполняет `initialize`, и все пять `terminal/*` методов реализованы и зарегистрированы
- **THEN** `InitializeRequest.clientCapabilities.terminal` отправляется как `true`

#### Scenario: Реализована лишь часть terminal-методов
- **WHEN** CodeLab выполняет `initialize`, и хотя бы один из пяти `terminal/*` методов не реализован
- **THEN** `InitializeRequest.clientCapabilities.terminal` отправляется как `false`, и агент не должен вызывать ни один из `terminal/*` методов
