## ADDED Requirements

### Requirement: Запись сжатия ложится на текущий лист
Компактор SHALL писать запись `compaction` через запись писателя по текущему снимку (`appendWith`, требование agent-sessions «Последовательная запись журнала»), а не по снимку начала прохода (design.md change `fix-config-change-during-background-compaction`, D2; CMP-12).

В очереди писателя, непосредственно перед записью, компактор SHALL:
1. при отменённом токене не писать запись и бросить `CancelledException` (CMP-3, CMP-4);
2. если между листом начала прохода и текущим листом на активной ветке лежат только записи `model_change`, `mode_change`, `config_change` и `session_info`, — записать `compaction` с `parentId` = текущий лист; `summary`, `firstKeptId`, `tokensBefore`, `tokensAfter`, `details` и `skills` SHALL оставаться посчитанными проходом; id записи SHALL быть уникален по текущему снимку;
3. иначе (лист начала прохода не на активной ветке, или между ними есть запись другого вида, в том числе неизвестного) — не писать запись, не вызывать `onCompacted`, не эмитить `ContextCompacted`, писать лог `compaction.skipped` (`info`) с `session_id`, `trigger`, `pass`, `reason: "stale"` и вернуть `Compacted` прошлого прохода или `NothingToCompact('stale')` (D3).

Правило SHALL действовать для всех триггеров: `afterTurn`, `manual`, `preflight`, `overflow`.

#### Scenario: Смена режима во время резюме
- **WHEN** пока суммаризатор отвечает, в журнал записан `mode_change`
- **THEN** запись `compaction` имеет `parentId` = id этого `mode_change`, лист — запись `compaction`, `pathToLeaf` содержит `mode_change`; `tokensBefore` и `tokensAfter` равны числам того же прохода без смены режима

#### Scenario: Сообщение во время резюме
- **WHEN** пока суммаризатор отвечает, в журнал записано сообщение
- **THEN** записи `compaction` нет, `ContextCompacted` нет, `onCompacted` не вызван, исход — `NothingToCompact('stale')`, лог `compaction.skipped` уровня `warning` с `reason: "stale"` и `blocking_type` (вид первой мешающей записи) и без текста резюме

#### Scenario: Отмена, пока запись ждёт очереди
- **WHEN** суммаризатор ответил, запись сжатия ждёт очереди писателя за другой записью, и в это время токен отменён
- **THEN** `compact` бросает `CancelledException`, записи `compaction` нет (CMP-3, CMP-4)
