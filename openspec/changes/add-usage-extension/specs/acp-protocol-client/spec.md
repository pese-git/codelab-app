## MODIFIED Requirements

### Requirement: Объявление расширений CodeLab при initialize
CodeLab SHALL отправлять в `InitializeRequest.clientCapabilities._meta.codelab` объект с расширениями, данные которых клиент понимает (design.md change `add-subagents-and-tasks`, D9, D21; change `add-usage-extension`, D3): `{"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}, "usage": {"version": 1}}`; `subagentToolCalls` — согласие получать вызовы потомков деревом, `usage` — согласие получать уведомление `_codelab/session/usage`. Других полей вне `_meta` CodeLab для этого НЕ SHALL добавлять (`15-Extensibility.md`).

Блок `agentCapabilities._meta.codelab` в ответе SHALL разбираться терпимо:
- его отсутствие — «агент расширений CodeLab не объявил»;
- неизвестные ключи, нецелый или больший `version` и неверная форма значения SHALL игнорироваться без отказа `initialize`;
- известные значения (`subagents.maxDepth`, наличие `tasks`, наличие `usage`) SHALL быть доступны приложению как согласованные возможности соединения.

Данные `_meta.codelab.task` и `_meta.codelab.subagent` и уведомление `_codelab/session/usage` SHALL приниматься и без объявления агента: клиент на объявление не полагается, чтобы показ не зависел от того, кто и как загрузил сессию.

#### Scenario: Запрос initialize клиента CodeLab
- **WHEN** CodeLab выполняет `initialize`
- **THEN** `clientCapabilities._meta.codelab` равен `{"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}, "usage": {"version": 1}}`, остальные поля `clientCapabilities` — как прежде (фикстура `acp/initialize-codelab-extensions`, роль `client`)

#### Scenario: Агент без блока объявлений
- **WHEN** агент отвечает на `initialize` без `agentCapabilities._meta`
- **THEN** `initialize` успешен, согласованных расширений CodeLab нет, `plan` с `_meta.codelab.task` от такого агента всё равно разбирается

#### Scenario: Будущая версия расширения
- **WHEN** ответ содержит `agentCapabilities._meta.codelab.tasks: {"version": 2, "x": 1}` и ключ `board: true`
- **THEN** `initialize` успешен, неизвестное игнорируется без ошибки

#### Scenario: Запрос без новых корневых полей
- **WHEN** CodeLab выполняет `initialize`
- **THEN** `InitializeRequest` и `clientCapabilities` содержат только поля схемы `17-Schema.md`, а объявление `usage` лежит в `clientCapabilities._meta.codelab` (`15-Extensibility.md`)

#### Scenario: Агент объявил usage
- **WHEN** ответ содержит `agentCapabilities._meta.codelab.usage: {"version": 1}`
- **THEN** соединение считает usage согласованным, и сессии этого соединения до первого снимка находятся в состоянии «ожидание», а не «агент не сообщает» (acp-client-kit «Usage сессии»)

## ADDED Requirements

### Requirement: Приём уведомления `_codelab/session/usage`
CodeLab SHALL принимать уведомление агента `_codelab/session/usage` и передавать его `sessionId` и `params` ядру клиента вместе с поколением соединения, на котором оно пришло (design.md change `add-usage-extension`, D7, D8). Уведомление SHALL NOT менять автомат хода: не завершает, не оживляет и не отменяет prompt turn. Уведомление без строкового `params.sessionId` SHALL отбрасываться с записью уровня DEBUG без payload. Другие незнакомые уведомления SHALL по-прежнему отбрасываться без ответа.

#### Scenario: Снимок во время хода
- **WHEN** во время prompt turn приходит `_codelab/session/usage` для этой сессии
- **THEN** ядро клиента получает снимок, а prompt turn остаётся в прежнем статусе

#### Scenario: Снимок после ответа на prompt
- **WHEN** `_codelab/session/usage` приходит после ответа на `session/prompt`
- **THEN** завершённый turn не меняет статус, снимок передаётся ядру клиента

#### Scenario: Уведомление старого соединения
- **WHEN** после переподключения доставляется `_codelab/session/usage`, пришедшее по прежнему транспорту
- **THEN** оно помечено прежним поколением и не меняет состояние сессий нового соединения

### Requirement: Причина остановки по бюджету
Если ответ на `session/prompt` имеет `stopReason: max_turn_requests` и строковое `_meta.codelab.budgetExceeded`, CodeLab SHALL сохранять это значение в итоге prompt turn (design.md change `add-usage-extension`, D10). Значение SHALL приниматься как открытая строка (известны `steps`, `tokens`, `cost`, `duration`, `deadline`); не строка или отсутствие поля SHALL давать итог без причины без ошибки. При другом `stopReason` поле SHALL игнорироваться.

#### Scenario: Бюджет по стоимости
- **WHEN** агент отвечает `{"stopReason": "max_turn_requests", "_meta": {"codelab": {"budgetExceeded": "cost"}}}`
- **THEN** prompt turn завершён со `stopReason` `maxTurnRequests` и причиной `cost`

#### Scenario: Незнакомая причина
- **WHEN** агент отвечает `max_turn_requests` с `budgetExceeded: "energy"`
- **THEN** prompt turn завершён с причиной `energy` без ошибки разбора

#### Scenario: Сторонний агент без причины
- **WHEN** агент отвечает `max_turn_requests` без `_meta`
- **THEN** prompt turn завершён без причины, как прежде
