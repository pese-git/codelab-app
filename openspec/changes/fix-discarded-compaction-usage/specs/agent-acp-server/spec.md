## ADDED Requirements

### Requirement: Отброшенный проход сжатия в сумме сессии
На событие `CompactionDiscarded` адаптер SHALL добавлять его `usage` в сумму сессии сервера (не в ход) по тому же правилу цены, что для `ContextCompacted.usage`: `noPrice` — модель ответа без цен в каталоге сессии при ненулевых токенах (требование «Уведомление `_codelab/session/usage`» change `add-usage-ledger`; design.md change `fix-discarded-compaction-usage`, D5).

Соединениям, объявившим `usage`, адаптер SHALL отправлять снимок `_codelab/session/usage` с `trigger: "compactionDiscarded"` (решение пользователя Q4 (а)). Снимок:
- без `turnId`, `step` и `turn`;
- с `session`, включающим вызов;
- с `context`, если мосту известно заполнение: `used` — `tokensBefore` события, `size` и `compactAt` — последнего `StepEnded`;
- с `seq` по общему правилу;
- с debug-записью `acp.usage.sent`.

Снимок SHALL отправляться и при нулевом usage вызова; сумма тогда не растёт, причины `noUsage` у суммаризатора нет — как у записанного сжатия (design.md, R8). Снимок и сообщение агента `/compact` идут в любом порядке, оба SHALL предшествовать ответу на `session/prompt`. Стандартные типы ACP новых полей и значений НЕ SHALL получать. Кадров `session/update` событие НЕ SHALL давать.

В ответе `_codelab/session/usage/ledger` объект `summaries` SHALL содержать целое `discarded` — число отброшенных вызовов, только при ненулевом значении. `usageLedger.version` остаётся `1` (правило совместимости D6 change `add-usage-ledger`; решение пользователя Q2 (а)). Засев на `session/load` SHALL включать отброшенные вызовы из свёртки, и инвариант «сразу после засева `session` равен `total` ответа журнала» (требование «Полная сумма сессии после session/load» change `add-usage-ledger`) SHALL сохраняться.

#### Scenario: /compact без выигрыша в живой сумме
- **WHEN** клиент объявил `usage`, после хода с одним шагом приходит `/compact`, и проход отброшен по CMP-10 с usage суммаризатора на модели с ценами
- **THEN** приходит `_codelab/session/usage` с `trigger: "compactionDiscarded"`, `session` с токенами и стоимостью суммаризатора сверх итога хода, прежними `session.turns` и `session.steps` и `context.used`, равным `used` последнего снимка хода; снимок и `agent_message_chunk` `Nothing to compact.` — в любом порядке, затем ответ `end_turn` (фикстура `acp/compact-no-gain-usage`; `usage_bridge_test.dart`)

#### Scenario: Журнал после отброшенного прохода
- **WHEN** после этого клиент запрашивает `_codelab/session/usage/ledger`
- **THEN** `summaries.count` — 1, `summaries.discarded` — 1, а `total` по `tokens`, `cost` и `partial` совпадает с `session` последнего снимка (фикстура `acp/compact-no-gain-usage`)

#### Scenario: Сумма после session/load
- **WHEN** сессию с ходом и отброшенным проходом загружают в новом сервере, клиент объявил `usage`
- **THEN** снимок `trigger: "load"` несёт `session` с usage суммаризатора, равный `total` ответа журнала; сумма не меньше той, что была в живой сессии до перезапуска (`usage_projection_test.dart`)

#### Scenario: Клиент без объявления
- **WHEN** проход отброшен, а клиент не объявил `usage`
- **THEN** кадров `_codelab/session/usage` нет, остальные кадры `/compact` не меняются

#### Scenario: Записанное сжатие без изменений
- **WHEN** проход сжатия записан
- **THEN** снимок — `trigger: "compaction"`, как до change, снимка `compactionDiscarded` нет
