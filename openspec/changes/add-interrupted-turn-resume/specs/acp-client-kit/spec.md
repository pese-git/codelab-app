## ADDED Requirements

### Requirement: Продолжение незавершённого хода
`SessionView` SHALL иметь `unfinishedTurn` — `UnfinishedTurnView?` со списком `interruptedToolCalls`, полученным из ответа `session/load` (capability `acp-protocol-client`, «Незавершённый ход в ответе session/load»; design.md change `add-interrupted-turn-resume`, D8). `SessionView.canContinue` SHALL быть истинным тогда и только тогда, когда выполнены все условия:

- `unfinishedTurn` не `null`;
- среди `SessionView.agentCommands` есть команда с именем `continue`;
- сессия связана с агентом (не `detached`) и соединение `Connected`;
- у сессии нет активного хода.

`SessionHandle.continueTurn()` SHALL отправлять промпт с единственным текстовым блоком `/continue` по обычному пути отправки (очередь промптов сессии, требование «Очередь промптов на сессию»). При ложном `canContinue` вызов SHALL отклоняться без запроса к агенту. Kit НЕ SHALL продолжать ход сам: ни загрузка, ни переподключение, ни восстановление после перезапуска не вызывают `continueTurn()`. `unfinishedTurn` SHALL становиться `null`, когда kit передал транспорту кадр `session/prompt` этой сессии — любого промпта, в том числе `/continue` (design.md change `add-interrupted-turn-resume`, D8):
- промпт в очереди сессии признак НЕ SHALL снимать;
- отказ агента на `session/prompt` (в том числе `turnActive`) признак НЕ SHALL возвращать: актуальное состояние даёт следующий `session/load`;
- обрыв транспорта до передачи кадра признак SHALL сохранять, а последующий `session/load` SHALL заменять его своим результатом.

#### Scenario: Можно продолжить
- **WHEN** сессия загружена с `_meta.codelab.unfinishedTurn`, агент объявил команду `continue`, соединение `Connected`, хода нет
- **THEN** `canContinue` истинно; `continueTurn()` отправляет `session/prompt` с текстом `/continue`, после отправки `unfinishedTurn` равно `null`

#### Scenario: Сторонний агент с командой continue
- **WHEN** агент объявил команду `continue`, но ответ `session/load` не несёт `_meta.codelab.unfinishedTurn`
- **THEN** `canContinue` ложно, `continueTurn()` не отправляет запрос

#### Scenario: Восстановление не продолжает ход
- **WHEN** при старте хоста kit восстанавливает активную сессию через `session/load`, и ответ несёт признак незавершённого хода
- **THEN** `unfinishedTurn` выставлен, промптов агенту не отправлено

#### Scenario: Обычный промпт снимает признак
- **WHEN** при выставленном `unfinishedTurn` пользователь отправляет обычный промпт
- **THEN** `unfinishedTurn` равно `null`, `canContinue` ложно

#### Scenario: Промпт в очереди не снимает признак
- **WHEN** у сессии выставлен `unfinishedTurn`, а промпт пользователя поставлен в очередь, потому что сессия ещё загружается
- **THEN** `unfinishedTurn` не `null`, пока кадр `session/prompt` не передан транспорту

#### Scenario: Отказ turnActive
- **WHEN** после отправки `/continue` агент отвечает `-32602` с `reason: "turnActive"`
- **THEN** `unfinishedTurn` остаётся `null`, `canContinue` ложно

#### Scenario: Обрыв до отправки
- **WHEN** транспорт обрывается до передачи кадра `session/prompt` с `/continue`
- **THEN** `unfinishedTurn` сохранён; после переподключения и `session/load` он заменён значением из ответа
