## MODIFIED Requirements

### Requirement: Список команд сессии
`AgentSession.commands` SHALL возвращать сначала встроенные команды сессии (требования «Встроенные команды MVP» и «Встроенные команды config и mcp») в порядке §13.4 — `compact`, `mode`, `model`, `status`, `usage`, `config`, `mcp`, `help` (`usage` — change `add-usage-ledger`, D5); отсутствующая команда пропускается, порядок остальных не меняется (design.md change `add-agent-builtin-slash-commands`, D2), — затем команды шаблонов `SlashCommand {name, description, inputHint, source: template}` в байтовом порядке имён, затем команды навыков `skill:<name>` (`source: skill`) для навыков с `user-invocable` в байтовом порядке имён навыков (capability `agent-skills`, «Команды навыков»; design.md change `add-agent-skills`, D8). `inputHint` шаблона SHALL быть `argument-hint`, иначе `"arguments"`, если тело содержит `$ARGUMENTS` или `$1`…`$9`, иначе `null`; `inputHint` навыка — `argument-hint`, иначе `"arguments"`. Список строится при открытии сессии и НЕ SHALL меняться до её закрытия, в том числе при перезагрузке конфигурации (design.md change `add-config-writer-and-reload`, D9). Инструменты модели, в том числе `skill`, в список НЕ SHALL попадать (R-07, SKL-6).

#### Scenario: Подсказка ввода
- **WHEN** у `review.md` нет `argument-hint`, а тело содержит `$1`, у `test.md` нет ни подсказки, ни плейсхолдеров
- **THEN** у `review` `inputHint == "arguments"`, у `test` — `null`

#### Scenario: Встроенные команды идут первыми
- **WHEN** ядро собрано с `ConfigSource`, capability `compaction` и capability `mcp`, а у сессии есть шаблон `review`
- **THEN** список — `compact`, `mode`, `model`, `status`, `usage`, `config`, `mcp`, `help`, `review`

#### Scenario: Без capability compaction и без конфига
- **WHEN** ядро собрано без `ConfigSource`, с выключенными capability `compaction` и `mcp`, шаблонов нет
- **THEN** список — `mode`, `model`, `status`, `usage`, `help`

#### Scenario: Навыки после шаблонов
- **WHEN** ядро собрано без `ConfigSource`, с выключенными capability `compaction` и `mcp`, у сессии есть шаблон `review`, навыки `release-notes` (с `argument-hint: "<from-tag> <to-tag>"`) и `flutter-golden` (без подсказки) и навык `internal` с `user-invocable: false`
- **THEN** список — `mode`, `model`, `status`, `usage`, `help`, `review`, `skill:flutter-golden` (`inputHint: "arguments"`), `skill:release-notes` (`inputHint: "<from-tag> <to-tag>"`); `skill:internal` и `skill` в списке нет

#### Scenario: Перезагрузка не меняет список
- **WHEN** после открытия сессии перезагрузка добавляет проект в `trusted_projects`, и у проекта есть `.codelab/prompts/fix.md`
- **THEN** список живой сессии не изменился; новая сессия того же `cwd` тоже без `fix` до перезапуска (доверие закреплено, R0-1); `/config reload` отвечает строкой `Restart required: trusted_projects`

## ADDED Requirements

### Requirement: Команда /usage
`AgentSession` SHALL объявлять и исполнять встроенную команду `usage` всегда, независимо от capability профиля и наличия порта `UsageLedgerStore` (design.md change `add-usage-ledger`, D5). Объявление — `{"name":"usage","description":"Show token usage and cost of the session","input":{"hint":"[rebuild]"}}` (§13.4). Распознавание, события хода без шагов модели, журнал (ни промпт, ни ответ не пишутся; ACP-12), слот хода, отмена и доставка событий — по общим правилам требования «Встроенные команды config и mcp». Команда только читает: отмена до ответа даёт `TurnEnded` с `cancelled` без сообщения; запись `usage.json`, начатая до отмены, доводится до конца.

Аргумент: пустой — отчёт по журналу usage (capability `agent-sessions`, «Журнал usage сессии»: свежий файл или пересчёт); `rebuild` — пересчёт всегда; иной — ответ `Usage: /usage [rebuild]`, журнал usage не строится.

Текст — фиксированные английские строки §12.6.1 с правками change: строки соединяются `\n`, после последней `\n` нет; числа — целые без разделителей; стоимость — `$` и 4 знака после точки:
- первая строка — `Session usage: <turns> turns, <steps> steps`; сессия без шагов — одна строка `Session usage: no model requests yet`;
- `Total: <usage>`; `By model:` и по строке `  <provider>/<model>: <n> steps, <usage>` на модель в лексикографическом порядке; `Subagents: <runs> runs, <usage>` и `Summaries: <count>, <usage>` — только при ненулевом счётчике;
- шаблон `<usage>` — `input <n>, output <n>, cache read <n>, cache write <n>[, reasoning <n>], cost <cost>`; `reasoning` — только если значение есть;
- `<cost>` — одно правило для строк `Total`, `By model`, `Subagents` и `Summaries`: `unknown`, если цены нет ни у одной части строки (решение Q7 (а)); иначе `$x.xxxx`, а при любой причине неполноты строки (`noUsage` или `noPrice`) — `~$x.xxxx`; части — шаги, прогоны субагентов и вызовы суммаризатора, цена прогона и вызова — по правилу «Журнал usage сессии»; вызов суммаризатора со всеми нулевыми счётчиками — `noUsage`, как шаг; прогон субагента `noUsage` не получает (у записи `subagent` нет `stopReason`, нулевой usage может означать ребёнка без обращения к модели), поэтому строка `Subagents` не получает `input ~`; при `noUsage` перед числом `input` ставится `~`;
- последняя строка — одна из `Ledger: up to date (<n> records)`, `Ledger: rebuilt from journal (<n> records)`, `Ledger: rebuilt in memory (<n> records)`, `Ledger: rebuilt, not saved (<причина ОС на английском>)`.

Блоков `By branch` и `Inherited from fork` в этой версии нет (design.md change `add-usage-ledger`, D1 п. 8).

#### Scenario: /usage после хода с двумя шагами
- **WHEN** в сессии один ход с двумя шагами на модели с ценами, ядро собрано с `UsageLedgerStore`, файла `usage.json` нет, и приходит `/usage`
- **THEN** ответ начинается строкой `Session usage: 1 turns, 2 steps`, строка `Total` равна сумме шагов, последняя строка — `Ledger: rebuilt from journal (<n> records)`; в каталоге сессии появился `usage.json`; модель не вызвана, журнал без новых записей, кадров `_codelab/session/usage` нет (фикстура `acp/slash-usage`)

#### Scenario: Повторный /usage
- **WHEN** сразу после предыдущего сценария снова приходит `/usage`
- **THEN** последняя строка — `Ledger: up to date (<n> records)`, текст выше неё тот же

#### Scenario: /usage rebuild
- **WHEN** приходит `/usage rebuild` при свежем файле
- **THEN** последняя строка — `Ledger: rebuilt from journal (<n> records)`, в логе `usage.ledger.rebuild` с `reason: explicit`

#### Scenario: Модель без цен
- **WHEN** все шаги сессии — на модели без цен в каталоге
- **THEN** у каждой строки usage — `cost unknown`; `$0.0000` в ответе нет

#### Scenario: Цена субагентов и суммаризатора
- **WHEN** в сессии два прогона субагентов, один с ненулевой стоимостью, другой с токенами и нулевой стоимостью, и одно сжатие, чья `summaryModel` в каталоге без цен
- **THEN** строка `Subagents` заканчивается `cost ~$x.xxxx`, строка `Summaries` — `cost unknown`; строка `Total` — `cost ~$x.xxxx`

#### Scenario: Суммаризатор без usage
- **WHEN** в сессии один шаг на модели с ценами и одно сжатие, чей вызов суммаризатора на модели с ценами вернул все нулевые счётчики
- **THEN** строка `Summaries` — `Summaries: 1, input ~0, output 0, cache read 0, cache write 0, cost ~$0.0000`; строка `Total` — с `input ~` и `cost ~$x.xxxx`

#### Scenario: Субагент без usage
- **WHEN** в сессии один прогон субагента со всеми нулевыми счётчиками (ребёнок отменён до обращения к модели)
- **THEN** строка `Subagents` — `Subagents: 1 runs, input 0, …` без `~` перед `input`

#### Scenario: Неверный аргумент
- **WHEN** приходит `/usage now`
- **THEN** ответ — ровно `Usage: /usage [rebuild]`, журнал usage не строился

#### Scenario: Ядро без порта
- **WHEN** ядро собрано без `UsageLedgerStore`, и приходит `/usage`
- **THEN** последняя строка — `Ledger: rebuilt in memory (<n> records)`
