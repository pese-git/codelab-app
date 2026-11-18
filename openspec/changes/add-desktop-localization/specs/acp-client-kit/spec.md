## ADDED Requirements

### Requirement: Типизированная причина заметки транскрипта
`NoticeItem` видов `emptyTurn`, `turnStopped`, `detached` и `reconnected` SHALL нести типизированную причину, по которой хост строит текст заметки на своём языке, не разбирая `text`:
- `emptyTurn` — `stopReason` хода (`null`, если его нет);
- `turnStopped` — `stopReason` хода и, для `max_turn_requests`, имя исчерпанного лимита бюджета, если оно входит в известный набор (`steps`, `tokens`, `cost`, `duration`, `deadline`); незнакомое имя SHALL давать причину без имени лимита, как и текст;
- `detached` и `reconnected` — закрытое перечисление причины: агент не умеет восстанавливать сессии; восстановить не удалось; для причины с сессией — её id.

Поле `text` и его значения SHALL не меняться: CLI и TUI по-прежнему показывают `text`. `NoticeItem` вида `error` SHALL по-прежнему нести типизированный сбой хода (`PromptFailure`). Новые поля SHALL быть аддитивными, ядро клиента SHALL оставаться web-безопасным и без зависимости от локали. Для любой последовательности обновлений инкрементальная проекция и проекция с нуля SHALL давать равные причины.

#### Scenario: Причина остановки по лимиту бюджета
- **WHEN** ход завершается с `stopReason: max_turn_requests` и `budgetExceeded: tokens`
- **THEN** `NoticeItem` вида `turnStopped` несёт причину с `stopReason` `maxTurnRequests` и лимитом `tokens`, а его `text` — `The turn stopped: budget exceeded: tokens.`

#### Scenario: Незнакомый лимит
- **WHEN** ход завершается с `stopReason: max_turn_requests` и `budgetExceeded: gpu_hours`
- **THEN** причина заметки не содержит имени лимита, а `text` — `The turn reached the limit of model requests.`

#### Scenario: Сессия не восстановлена после переподключения
- **WHEN** после переподключения сессия `s1` не загрузилась
- **THEN** `NoticeItem` вида `detached` несёт причину «восстановить не удалось» с id `s1`, а `text` совпадает с прежним

#### Scenario: CLI не меняется
- **WHEN** CLI показывает ленту хода, остановленного по `max_tokens`
- **THEN** строка заметки — `The model reached its token limit, so the turn ended.`, как до изменения
