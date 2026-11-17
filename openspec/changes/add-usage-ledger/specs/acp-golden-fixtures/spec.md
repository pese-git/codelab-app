## ADDED Requirements

### Requirement: Фикстуры журнала usage
Корпус SHALL содержать фикстуры design.md change `add-usage-ledger`, D11, с метками `usage` и `usageLedger` в `extensions` (FIX-4) и ссылками `spec` на `15-Extensibility.md`:
- `acp/slash-usage` (`agent`) — `usage` в `available_commands_update` сразу после `status`; `/usage` после хода с двумя шагами — текст отчёта с `end_turn` без `_codelab/session/usage`; `/usage x` — `Usage: /usage [rebuild]`;
- `acp/usage-ledger-request` (`agent`, `client`) — ход с двумя шагами и вызовом инструмента, затем `_codelab/session/usage/ledger` и его результат;
- `acp/usage-ledger-rebuild` (`agent`) — запрос с `rebuild: true`, `ledger.status: "rebuilt"`, `reason: "explicit"`;
- `acp/session-load-usage-full` (`agent`) — `session/load` журнала с двумя ходами: реплей, ответ, затем снимок `trigger: "load"` с полной суммой без `beforeLoad`, затем ход; заменяет `acp/session-load-usage-partial`;
- `acp/compact-usage-summary` (`agent`) — `/compact` со сценарным ответом суммаризатора с usage: снимок `compaction` с суммой сессии, включающей суммаризатор; затем запрос журнала с `summaries.count: 1`; только агентский прогон, как `acp/compact-usage-context`.

`acp/initialize-codelab-extensions` SHALL ожидать `usageLedger` в ответе агента; `acp/session-load-interrupted-turn` SHALL ожидать после ответа на `session/load` кадр `_codelab/session/usage` с `trigger: "load"` и нести метку `usage` (design.md, D15 п. 8); фикстуры с `available_commands_update` агента SHALL ожидать `usage` в списке команд после `status`. Правка этих ожиданий ссылается на change `add-usage-ledger` (требование «Правила изменения фикстур»). Фикстуры без меток `usage` и `usageLedger` НЕ SHALL содержать `_codelab/session/usage/ledger`.

#### Scenario: Агентский прогон журнала
- **WHEN** `conformance:agent` проигрывает `acp/usage-ledger-request`
- **THEN** результат запроса совпадает с фикстурой, включая `seq`, `toolCallIds` и строки стоимости

#### Scenario: Клиентский прогон журнала
- **WHEN** `conformance:client` проигрывает `acp/usage-ledger-request`
- **THEN** клиент отправляет запрос с теми же параметрами, а `SessionView.usageLedger` после ответа — `loaded` с одним ходом и двумя шагами

#### Scenario: Полная сумма после загрузки
- **WHEN** `conformance:agent` проигрывает `acp/session-load-usage-full`
- **THEN** снимок `trigger: "load"` идёт после ответа на `session/load`, `session.partial` не содержит `beforeLoad`
