## ADDED Requirements

### Requirement: Отброшенные вызовы суммаризатора в журнале usage
Свёртка журнала usage (требование «Журнал usage сессии» change `add-usage-ledger`) SHALL считать вызовом суммаризатора, кроме записи `compaction` с `details.usage`, ещё запись `custom` с `customType: "codelab.compaction_discarded"`, у которой `data` и `data.usage` — объекты (design.md change `fix-discarded-compaction-usage`, D3; решения пользователя Q1 (а), Q2 (а)). Такой вызов SHALL:
- входить в `summaries.count`, `summaries.usage`, `summaries.models` (по `data.summaryModel`) и в итог сессии;
- не входить ни в ход, ни в модели;
- получать цену и причины `noUsage` и `noPrice` по тем же правилам, что вызов из записи `compaction`; запись без `data.summaryModel` (ядро её так не пишет, но журнал могли править вручную) учитывается с моделью «неизвестна», как запись `compaction` без `summaryModel`.

Группа суммаризатора SHALL нести число отброшенных вызовов `discarded`. Запись с `data` или `data.usage` неверной формы SHALL пропускаться без причины неполноты.

Файл `usage.json` (требование «Файл usage.json и порт UsageLedgerStore» change `add-usage-ledger`) SHALL оставаться версии 1 (решение пользователя Q3 (а)). В блоке `summaries` ключ `discarded` SHALL идти сразу после `count` и только при ненулевом значении. Остальной формат, правила свежести и детерминизм (OBS-10) не меняются.

#### Scenario: Отброшенный вызов в свёртке
- **WHEN** в журнале ход с одним шагом, затем запись `custom` `codelab.compaction_discarded` с `data.usage` `{input: 764, output: 171}` и `data.summaryModel: "openai/gpt-4o-mini"`
- **THEN** `summaries.count` — 1, `summaries.discarded` — 1, `summaries.models` — `["openai/gpt-4o-mini"]`; итог равен сумме шага и вызова; итог хода — только шаг; в моделях вызова нет (`usage_ledger_test.dart`)

#### Scenario: Записанный и отброшенный проходы
- **WHEN** в журнале запись `compaction` с `details.usage` и за ней запись учёта отброшенного прохода
- **THEN** `summaries.count` — 2, `summaries.discarded` — 1, `summaries.usage` — сумма обоих вызовов

#### Scenario: Цена отброшенного вызова
- **WHEN** `data.summaryModel` записи учёта нет в каталоге сессии с ценами, а токены ненулевые
- **THEN** вызов — «без цены», и группа `summaries` и итог получают `noPrice`; при всех нулевых счётчиках вызов даёт `noUsage`

#### Scenario: Запись неверной формы
- **WHEN** у записи `custom` `codelab.compaction_discarded` `data.usage` — не объект
- **THEN** вызов не учитывается, причин неполноты от неё нет, свёртка строится без ошибки

#### Scenario: usage.json с отброшенным вызовом
- **WHEN** журнал содержит запись учёта, и `usage.json` пишется
- **THEN** файл версии 1, `summaries` содержит `"count":1,"discarded":1` в этом порядке; повторное построение даёт побайтово тот же файл; у журнала без записей учёта ключа `discarded` нет (`usage_ledger_store_test.dart`)
