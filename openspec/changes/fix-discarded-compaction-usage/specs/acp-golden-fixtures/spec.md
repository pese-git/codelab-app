## ADDED Requirements

### Requirement: Фикстура отброшенного прохода сжатия
Корпус SHALL содержать фикстуру `acp/compact-no-gain-usage` с ролью `agent`, метками `usage` и `usageLedger` в `extensions` и ссылкой `spec` на `15-Extensibility.md` (design.md change `fix-discarded-compaction-usage`, D7). Сценарий фикстуры:
1. клиент объявил `usage`;
2. ход с одним шагом на модели с ценами;
3. `/compact` со сценарным ответом суммаризатора длиннее региона и с usage.

Ожидаемые кадры SHALL быть такими:
- `agent_message_chunk` `Nothing to compact.`;
- `_codelab/session/usage` с `trigger: "compactionDiscarded"` и суммой сессии, включающей суммаризатор;
- ответ `end_turn`;
- ответ на запрос `_codelab/session/usage/ledger` с `summaries.count: 1` и `summaries.discarded: 1`.

Фикстура SHALL проигрываться только в `conformance:agent`, как `acp/compact-usage-summary`. Существующие фикстуры SHALL оставаться без изменений.

#### Scenario: Агентский прогон
- **WHEN** `melos run conformance:agent` проигрывает `acp/compact-no-gain-usage` против настоящего ядра со scripted-моделью
- **THEN** кадры совпадают с фикстурой после нормализации, включая порядок «сообщение агента → снимок `compactionDiscarded` → ответ `session/prompt`»

#### Scenario: Корпус не меняется
- **WHEN** прогоняются существующие фикстуры сжатия (`acp/slash-compact`, `acp/compact-usage-context`, `acp/compact-usage-summary`, `acp/compaction-long-session-continues`)
- **THEN** они зелёные без правок: ни в одной проход не отбрасывается
