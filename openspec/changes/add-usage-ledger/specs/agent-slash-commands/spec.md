## MODIFIED Requirements

### Requirement: Список команд сессии
`AgentSession.commands` SHALL возвращать сначала встроенные команды сессии (требования «Встроенные команды MVP» и «Встроенные команды config и mcp») в порядке §13.4 — `compact`, `mode`, `model`, `status`, `usage`, `config`, `mcp`, `help` (`usage` — change `add-usage-ledger`, D5); отсутствующая команда пропускается, порядок остальных не меняется (design.md change `add-agent-builtin-slash-commands`, D2), — затем команды шаблонов `SlashCommand {name, description, inputHint, source: template}` в байтовом порядке имён. `inputHint` шаблона SHALL быть `argument-hint`, иначе `"arguments"`, если тело содержит `$ARGUMENTS` или `$1`…`$9`, иначе `null`. Список строится при открытии сессии и НЕ SHALL меняться до её закрытия, в том числе при перезагрузке конфигурации (design.md change `add-config-writer-and-reload`, D9). Инструменты модели в список НЕ SHALL попадать (R-07).

#### Scenario: Подсказка ввода
- **WHEN** у `review.md` нет `argument-hint`, а тело содержит `$1`, у `test.md` нет ни подсказки, ни плейсхолдеров
- **THEN** у `review` `inputHint == "arguments"`, у `test` — `null`

#### Scenario: Встроенные команды идут первыми
- **WHEN** ядро собрано с `ConfigSource`, capability `compaction` и capability `mcp`, а у сессии есть шаблон `review`
- **THEN** список — `compact`, `mode`, `model`, `status`, `usage`, `config`, `mcp`, `help`, `review`

#### Scenario: Без capability compaction и без конфига
- **WHEN** ядро собрано без `ConfigSource`, с выключенными capability `compaction` и `mcp`, шаблонов нет
- **THEN** список — `mode`, `model`, `status`, `usage`, `help`

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
- `<cost>` — одно правило для строк `Total`, `By model`, `Subagents` и `Summaries`: `$x.xxxx`, если цена известна у всех частей строки с ненулевыми токенами; `~$x.xxxx`, если у части (`noPrice`); `unknown`, если ни у одной (решение Q7 (а)); части — шаги, прогоны субагентов и записи суммаризатора, цена прогона и записи — по правилу «Журнал usage сессии»; при `noUsage` перед числом `input` ставится `~`;
- последняя строка — одна из `Ledger: up to date (<n> records)`, `Ledger: rebuilt from journal (<n> records)`, `Ledger: rebuilt in memory (<n> records)`, `Ledger: rebuilt, not saved (<причина ОС на английском>)`.

Блоков `By branch` и `Inherited from fork` в этой версии нет (design.md change `add-usage-ledger`, D1 п. 8).

#### Scenario: /usage после двух ходов
- **WHEN** в сессии два хода по одному шагу на модели с ценами, файла `usage.json` нет, и приходит `/usage`
- **THEN** ответ начинается строкой `Session usage: 2 turns, 2 steps`, строка `Total` равна сумме шагов, последняя строка — `Ledger: rebuilt from journal (<n> records)`; в каталоге сессии появился `usage.json`; модель не вызвана, журнал без новых записей, кадров `_codelab/session/usage` нет (фикстура `acp/slash-usage`)

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

#### Scenario: Неверный аргумент
- **WHEN** приходит `/usage now`
- **THEN** ответ — ровно `Usage: /usage [rebuild]`, журнал usage не строился

#### Scenario: Ядро без порта
- **WHEN** ядро собрано без `UsageLedgerStore`, и приходит `/usage`
- **THEN** последняя строка — `Ledger: rebuilt in memory (<n> records)`
