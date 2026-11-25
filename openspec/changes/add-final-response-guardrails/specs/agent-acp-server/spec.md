## ADDED Requirements

### Requirement: Удержанный финальный ответ в итоге хода
Если ход закончился `TurnEnded(completed)` без `budgetExceeded` и с `held` (финальный гейт вернул `Hold`), ответ на `session/prompt` SHALL быть `{"stopReason": "end_turn", "_meta": {"codelab": {"held": "<reason>"}}}`, где `<reason>` — строка `TurnEnded.held` (design.md change `add-final-response-guardrails`, D6). Без `held` ответ SHALL оставаться прежним `end_turn` без `_meta`. Отмена, запрошенная клиентом, SHALL по-прежнему давать `cancelled`, а исчерпание бюджета — `max_turn_requests` с `_meta.codelab.budgetExceeded`. Сбой хода SHALL по-прежнему давать JSON-RPC `-32603` (ACP-7).

Новых значений `stopReason`, методов и полей вне `_meta` сервер НЕ SHALL вводить. `_meta.codelab.turnEnded` после переподключения `held` НЕ SHALL нести (design.md, R4).

#### Scenario: Ответ удержан
- **WHEN** конфиг сессии задаёт `loop.final_response: {checks: [unverified_success], max_revisions: 0}`, а scripted модель отвечает `All tests pass.` без вызовов
- **THEN** ответ на `session/prompt` — `stopReason: end_turn` с `_meta.codelab.held`, равным `revision limit reached: [unverified_success] The answer says that tests or the build pass, but no command ran in this turn. Run the check with exec, or say plainly that it was not verified.`, как в фикстуре `acp/prompt-response-held` (точное сравнение строки)

#### Scenario: Ответ принят
- **WHEN** тот же конфиг, а модель сначала вызывает `exec`, затем отвечает `All tests pass.`
- **THEN** ответ на `session/prompt` — `end_turn` без `_meta`, как в фикстуре `acp/prompt-response-accepted`

## MODIFIED Requirements

### Requirement: Расширения протокола этапа 4
Сервер SHALL отправлять только расширения, введённые утверждёнными changes (ACP-2):
- change `add-dart-agent-acp-server`: `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded`, `data.codelab` (`errorClass`, `message`, `retryable`, `reason`), `_meta.codelab.turnEnded`, `_meta.codelab.critical`;
- change `add-subagents-and-tasks`: блок `agentCapabilities._meta.codelab` (`subagents`, `subagentToolCalls`, `tasks`), `_meta.codelab.task` у entries `plan`, `_meta.codelab.subagent` у `toolCall` в `session/request_permission`, у первого `tool_call` вызова `agent` (`id`, `type`) и у его финального `tool_call_update` (`summary`, при `failed` — `failure`), `_meta.codelab.parentToolCallId` у `tool_call`/`tool_call_update` вызовов потомков (только клиенту с `subagentToolCalls`).
- change `add-usage-extension`: ключ `usage` блока `agentCapabilities._meta.codelab` и уведомление агент → клиент `_codelab/session/usage` (только соединению, объявившему `clientCapabilities._meta.codelab.usage`).
- change `add-usage-ledger`: ключ `usageLedger` блока `agentCapabilities._meta.codelab`, запрос клиент → агент `_codelab/session/usage/ledger` и значение `trigger: "load"` уведомления `_codelab/session/usage`.
- change `fix-discarded-compaction-usage`: значение `trigger: "compactionDiscarded"` уведомления `_codelab/session/usage` и необязательное целое `summaries.discarded` ответа `_codelab/session/usage/ledger` — без смены версий `usage` и `usageLedger` (design.md change `fix-discarded-compaction-usage`, D5).
- change `add-desktop-usage-pane`: необязательное поле `budget` снимков `step` и `turn` уведомления `_codelab/session/usage` — без смены версии `usage` (design.md change `add-desktop-usage-pane`, D7).
- change `add-final-response-guardrails`: `_meta.codelab.held` (строка причины) в ответе `session/prompt` со `stopReason: end_turn` (design.md change `add-final-response-guardrails`, D6).

Каждое расширение SHALL быть перечислено в §13.12 документа ядра со ссылкой на свой change. Новых методов и корневых полей ACP сервер НЕ SHALL вводить (`15-Extensibility.md`).

Уточнение change `add-usage-extension` (D17): запрет новых методов относится к методам вне пространства `_codelab/*`. Уведомление `_codelab/session/usage` введено по разделам «Extension Methods» и «Custom Notifications» `15-Extensibility.md` (имя с `_`, без `id`), перечислено выше и не вводит ни корневых полей, ни значений `sessionUpdate`. Запрос `_codelab/session/usage/ledger` (change `add-usage-ledger`, D6) введён по разделу «Custom Requests» того же документа: имя с `_`, ответ с тем же `id`, поддержка объявляется ключом `usageLedger`; агент без этого ключа отвечает на метод `-32601`.

#### Scenario: Бюджет хода
- **WHEN** ход исчерпал лимит шагов
- **THEN** ответ на `session/prompt` — `stopReason: max_turn_requests` с `_meta.codelab.budgetExceeded: "steps"`

#### Scenario: Запрос журнала у агента без ключа
- **WHEN** клиент шлёт `_codelab/session/usage/ledger` агенту, в ответе `initialize` которого нет ключа `usageLedger` (сторонний агент или CodeLab до change `add-usage-ledger`)
- **THEN** ответ — `-32601` «Method not found» по `15-Extensibility.md`; соединение живо

#### Scenario: Удержанный ответ
- **WHEN** финальный гейт корня вернул `Hold("revision limit reached: [open_tasks] …")`
- **THEN** ответ на `session/prompt` — `stopReason: end_turn` с `_meta.codelab.held`, равным этой строке
