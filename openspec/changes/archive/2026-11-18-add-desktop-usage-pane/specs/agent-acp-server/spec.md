## ADDED Requirements

### Requirement: Бюджет хода в уведомлении `_codelab/session/usage`
Снимки `_codelab/session/usage` с поводом `step` и `turn` SHALL нести необязательное поле `budget`, если у хода задан хотя бы один из лимитов `budget.max_tokens`, `budget.max_cost`, `budget.max_duration` (design.md change `add-desktop-usage-pane`, D7, Q5; правило совместимости D2 change `add-usage-extension`: новое необязательное поле — без смены версии `usage`). Без таких лимитов поля НЕ SHALL быть; в снимках `compaction`, `compactionDiscarded` (change `fix-discarded-compaction-usage`) и `load` его НЕ SHALL быть.

Состав (значения — из прогресса бюджета `StepEnded` и `TurnEnded`, требование agent-loop «Прогресс бюджета хода в событиях шага и хода»):
- `steps` — `{"used": <целое>, "limit": <целое>}`, всегда при наличии поля;
- `tokens` — `{"used": <целое>, "limit": <целое>}`, только при заданном `max_tokens`;
- `cost` — `{"used": "<десятичная строка>", "limit": "<десятичная строка>"}`, только при заданном `max_cost`; строки — по правилу денег D9 change `add-usage-extension` из целых микродолларов (`limit` — `round(max_cost × 10⁶)`); `used` отсутствует, если у текущей модели нет цен; при наличии `budget.cost` снимок SHALL нести `currency`;
- `duration` — `{"usedMs": <целое>, "limitMs": <целое>}`, только при заданном `max_duration`.

Невалидный `max_cost` — NaN, бесконечность, отрицательное число или сумма, не представимая целыми микродолларами, — SHALL давать `budget` без подполя `cost`; если других необязательных лимитов (`tokens`, `duration`) нет, поля `budget` НЕ SHALL быть. Снимок при этом SHALL уходить.

Объявление `usage: {"version": 1}`, правила `seq`, порядка и адресатов уведомления (требование «Уведомление `_codelab/session/usage`») НЕ SHALL меняться. Клиент, не знающий поля, его игнорирует.

#### Scenario: Бюджет в снимках хода
- **WHEN** клиент объявил `usage`, конфигурация задаёт `budget.max_tokens: 200000` и `budget.max_cost: 0.5`, и ход идёт два шага на модели с ценами
- **THEN** оба снимка `step` и снимок `turn` несут `budget` с `steps`, `tokens` и `cost`, без `duration`; `steps.used` — 1, 2 и 2 (фикстура `acp/prompt-usage-budget`)

#### Scenario: Без лимитов кроме шагов
- **WHEN** конфигурация задаёт только `budget.max_steps`
- **THEN** снимки `step` и `turn` не несут `budget` (фикстуры `acp/prompt-usage-steps` и другие usage-фикстуры не меняются)

#### Scenario: Лимит стоимости на модели без цен
- **WHEN** задан `budget.max_cost: 0.5`, а модель без цен
- **THEN** `budget.cost` — `{"limit": "0.5"}` без `used`, снимок несёт `currency` `USD`

#### Scenario: Снимок сжатия
- **WHEN** после хода с лимитами идёт фоновое сжатие, или проход сжатия отброшен после оплаченного вызова суммаризатора
- **THEN** снимок `compaction` или `compactionDiscarded` не несёт `budget`

#### Scenario: Невалидный лимит стоимости
- **WHEN** `max_cost` — NaN, а `max_tokens` задан
- **THEN** снимки `step` и `turn` несут `budget` с `steps` и `tokens` без `cost`; при одном NaN `max_cost` без других необязательных лимитов поля `budget` нет

## MODIFIED Requirements

### Requirement: Расширения протокола этапа 4
Сервер SHALL отправлять только расширения, введённые утверждёнными changes (ACP-2):
- change `add-dart-agent-acp-server`: `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded`, `data.codelab` (`errorClass`, `message`, `retryable`, `reason`), `_meta.codelab.turnEnded`, `_meta.codelab.critical`;
- change `add-subagents-and-tasks`: блок `agentCapabilities._meta.codelab` (`subagents`, `subagentToolCalls`, `tasks`), `_meta.codelab.task` у entries `plan`, `_meta.codelab.subagent` у `toolCall` в `session/request_permission`, у первого `tool_call` вызова `agent` (`id`, `type`) и у его финального `tool_call_update` (`summary`, при `failed` — `failure`), `_meta.codelab.parentToolCallId` у `tool_call`/`tool_call_update` вызовов потомков (только клиенту с `subagentToolCalls`).
- change `add-usage-extension`: ключ `usage` блока `agentCapabilities._meta.codelab` и уведомление агент → клиент `_codelab/session/usage` (только соединению, объявившему `clientCapabilities._meta.codelab.usage`).
- change `add-usage-ledger`: ключ `usageLedger` блока `agentCapabilities._meta.codelab`, запрос клиент → агент `_codelab/session/usage/ledger` и значение `trigger: "load"` уведомления `_codelab/session/usage`.
- change `fix-discarded-compaction-usage`: значение `trigger: "compactionDiscarded"` уведомления `_codelab/session/usage` и необязательное целое `summaries.discarded` ответа `_codelab/session/usage/ledger` — без смены версий `usage` и `usageLedger` (design.md change `fix-discarded-compaction-usage`, D5).
- change `add-desktop-usage-pane`: необязательное поле `budget` снимков `step` и `turn` уведомления `_codelab/session/usage` — без смены версии `usage` (design.md change `add-desktop-usage-pane`, D7).

Каждое расширение SHALL быть перечислено в §13.12 документа ядра со ссылкой на свой change. Новых методов и корневых полей ACP сервер НЕ SHALL вводить (`15-Extensibility.md`).

Уточнение change `add-usage-extension` (D17): запрет новых методов относится к методам вне пространства `_codelab/*`. Уведомление `_codelab/session/usage` введено по разделам «Extension Methods» и «Custom Notifications» `15-Extensibility.md` (имя с `_`, без `id`), перечислено выше и не вводит ни корневых полей, ни значений `sessionUpdate`. Запрос `_codelab/session/usage/ledger` (change `add-usage-ledger`, D6) введён по разделу «Custom Requests» того же документа: имя с `_`, ответ с тем же `id`, поддержка объявляется ключом `usageLedger`; агент без этого ключа отвечает на метод `-32601`.

#### Scenario: Бюджет хода
- **WHEN** ход исчерпал лимит шагов
- **THEN** ответ на `session/prompt` — `stopReason: max_turn_requests` с `_meta.codelab.budgetExceeded: "steps"`

#### Scenario: Запрос журнала у агента без ключа
- **WHEN** клиент шлёт `_codelab/session/usage/ledger` агенту, в ответе `initialize` которого нет ключа `usageLedger` (сторонний агент или CodeLab до change `add-usage-ledger`)
- **THEN** ответ — `-32601` «Method not found» по `15-Extensibility.md`; соединение живо
