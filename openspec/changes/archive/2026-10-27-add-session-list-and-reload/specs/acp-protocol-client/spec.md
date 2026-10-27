## ADDED Requirements

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
