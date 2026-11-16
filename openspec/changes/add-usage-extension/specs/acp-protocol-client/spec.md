## MODIFIED Requirements

### Requirement: Объявление расширений CodeLab при initialize
CodeLab SHALL отправлять в `InitializeRequest.clientCapabilities._meta.codelab` объект только с теми расширениями, которые клиент уже поддерживает (design.md change `add-subagents-and-tasks`, D9, D21): `tasks: {"version": 1}` — с итерации 1; `subagents: {"version": 1}` — с итерации 2 (строка `agent`, запрос потомка); `subagentToolCalls: {"version": 1}` — с задачи 5.4 (дерево вызовов потомков), это согласие получать вызовы потомков. Расширение, которого клиент ещё не показывает, НЕ SHALL объявляться: иначе агент слал бы клиенту вызовы потомков, которые тот показал бы плоскими строками. Других полей вне `_meta` CodeLab для этого НЕ SHALL добавлять (`15-Extensibility.md`).

`usage: {"version": 1}` — с итерации 2 change `add-usage-extension` (design.md этого change, D3): согласие получать уведомление `_codelab/session/usage`; до неё клиент снимки не показывает и `usage` не объявляет.

Пометки итераций и задач в сценариях без «(usage)» ниже относятся к change `add-subagents-and-tasks`; после итерации 2 change `add-usage-extension` каждое такое объявление клиента дополнительно содержит `"usage": {"version": 1}`, остальное в них не меняется.

Блок `agentCapabilities._meta.codelab` в ответе SHALL разбираться терпимо:
- его отсутствие — «агент расширений CodeLab не объявил»;
- неизвестные ключи, нецелый или больший `version` и неверная форма значения SHALL игнорироваться без отказа `initialize`;
- известные значения (`subagents.maxDepth`, наличие `tasks`) SHALL быть доступны приложению как согласованные возможности соединения;
- расширение считается согласованным, только если значение его ключа — объект, где `version` — целое JSON-число `1` (не `1.0`, не строка `"1"`, не другое число). Ключ с другой версией или неверной формой SHALL давать «расширение не согласовано» (например `tasks: false`), а не ошибку.
- наличие согласованного `usage` SHALL быть доступно приложению так же, как `subagents.maxDepth` и наличие `tasks` (change `add-usage-extension`, D3, D8): оно определяет, что показывать до первого снимка — «ожидание» или «агент не сообщает».

Данные `_meta.codelab.task` и `_meta.codelab.subagent` SHALL приниматься и без объявления агента: клиент на объявление не полагается, чтобы показ не зависел от того, кто и как загрузил сессию.

Уведомление `_codelab/session/usage` SHALL так же приниматься и без объявления агента (change `add-usage-extension`, D3): объявление управляет только тем, что показывать до первого снимка.

#### Scenario: Запрос initialize клиента CodeLab (итерация 1)
- **WHEN** CodeLab выполняет `initialize` после итерации 1
- **THEN** `clientCapabilities._meta.codelab` равен `{"tasks": {"version": 1}}`, остальные поля `clientCapabilities` — как прежде (`initialize_codelab_request_test.dart`; фикстура `acp/initialize-codelab-extensions`, роль `client`, в редакции итерации 1)

#### Scenario: Запрос initialize клиента CodeLab (итерация 2)
- **WHEN** CodeLab выполняет `initialize` после итерации 2
- **THEN** `clientCapabilities._meta.codelab` равен `{"tasks": {"version": 1}, "subagents": {"version": 1}}`

#### Scenario: Запрос initialize клиента CodeLab (задача 5.4)
- **WHEN** CodeLab выполняет `initialize` после задачи 5.4
- **THEN** `clientCapabilities._meta.codelab` равен `{"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}}`

#### Scenario: Версия не целое 1
- **WHEN** агент отвечает `agentCapabilities._meta.codelab: {"tasks": {"version": 1.0}, "subagents": {"version": "1"}}`
- **THEN** `initialize` успешен, ни `tasks`, ни `subagents` не согласованы

#### Scenario: Агент без блока объявлений
- **WHEN** агент отвечает на `initialize` без `agentCapabilities._meta`
- **THEN** `initialize` успешен, согласованных расширений CodeLab нет, `plan` с `_meta.codelab.task` от такого агента всё равно разбирается

#### Scenario: Будущая версия расширения
- **WHEN** ответ содержит `agentCapabilities._meta.codelab.tasks: {"version": 2, "x": 1}` и ключ `board: true`
- **THEN** `initialize` успешен, неизвестное игнорируется без ошибки; расширение `tasks` не согласовано (`tasks: false`), ключ `board` не даёт возможностей

#### Scenario: Запрос initialize клиента CodeLab (usage)
- **WHEN** CodeLab выполняет `initialize` после итерации 2 change `add-usage-extension`
- **THEN** `clientCapabilities._meta.codelab` равен объявлению текущей итерации change `add-subagents-and-tasks` с добавленным `"usage": {"version": 1}` — после задачи 5.4 того change `{"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}, "usage": {"version": 1}}`; остальные поля `clientCapabilities` — как прежде (фикстура `acp/initialize-codelab-extensions`, роль `client`)

#### Scenario: Запрос без новых корневых полей
- **WHEN** CodeLab выполняет `initialize`
- **THEN** `InitializeRequest` и `clientCapabilities` содержат только поля схемы `17-Schema.md`, а объявление `usage` лежит в `clientCapabilities._meta.codelab` (`15-Extensibility.md`)

#### Scenario: Агент объявил usage
- **WHEN** ответ содержит `agentCapabilities._meta.codelab.usage: {"version": 1}`
- **THEN** соединение считает usage согласованным, и сессии этого соединения до первого снимка находятся в состоянии «ожидание», а не «агент не сообщает» (acp-client-kit «Usage сессии»)

#### Scenario: Версия usage не целое 1
- **WHEN** агент отвечает `agentCapabilities._meta.codelab: {"usage": {"version": "1"}}` (или `usage: true`, `{"version": 2}`)
- **THEN** `initialize` успешен, `usage` не согласован: сессии до первого снимка — «агент не сообщает», а пришедшее `_codelab/session/usage` всё равно принимается

## ADDED Requirements

### Requirement: Приём уведомления `_codelab/session/usage`
CodeLab SHALL принимать уведомление агента `_codelab/session/usage` и передавать его `sessionId` и `params` ядру клиента вместе с поколением соединения, на котором оно пришло (design.md change `add-usage-extension`, D7, D8, D21 Т2). Уведомление SHALL NOT менять автомат хода: не завершает, не оживляет и не отменяет prompt turn. Уведомление без строкового `params.sessionId` SHALL отбрасываться с записью уровня DEBUG без payload. Другие незнакомые уведомления SHALL по-прежнему отбрасываться без ответа.

#### Scenario: Снимок во время хода
- **WHEN** во время prompt turn приходит `_codelab/session/usage` для этой сессии
- **THEN** ядро клиента получает снимок, а prompt turn остаётся в прежнем статусе

#### Scenario: Снимок после ответа на prompt
- **WHEN** `_codelab/session/usage` приходит после ответа на `session/prompt`
- **THEN** завершённый turn не меняет статус, снимок передаётся ядру клиента

#### Scenario: Уведомление старого соединения
- **WHEN** после переподключения доставляется `_codelab/session/usage`, пришедшее по прежнему транспорту
- **THEN** оно отбрасывается до маршрутизации, как любое входящее сообщение прежнего поколения (запись DEBUG `event_ignored` с `reason: stale_generation`), не доходит до ядра клиента и не меняет состояние сессий нового соединения; уведомления текущего соединения передаются ядру клиента с номером его поколения (design.md, D21 Т2)

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
