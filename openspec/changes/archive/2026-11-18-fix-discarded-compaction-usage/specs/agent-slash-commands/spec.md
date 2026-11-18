## ADDED Requirements

### Requirement: Отброшенные вызовы в отчёте /usage
Строка суммаризатора команды `/usage` (требование «Команда /usage» change `add-usage-ledger`) SHALL иметь вид `Summaries: <count> (<n> discarded), <usage>`, где `<n>` — число отброшенных вызовов группы (требование `agent-sessions` «Отброшенные вызовы суммаризатора в журнале usage»; design.md change `fix-discarded-compaction-usage`, D4; решение пользователя Q2 (а)). Часть ` (<n> discarded)` SHALL выводиться только при ненулевом `<n>`. Без неё строка прежняя. Правило `<cost>` и `~` не меняется, отброшенные вызовы — части строки `Summaries` и `Total`. Ответ `/compact` на проход без выигрыша остаётся `Nothing to compact.`

#### Scenario: /usage после /compact без выигрыша
- **WHEN** в сессии один ход на модели с ценами, затем `/compact` отброшен по CMP-10 с usage суммаризатора `{input: 764, output: 171}` на модели с ценами, и приходит `/usage`
- **THEN** ответ содержит строку `Summaries: 1 (1 discarded), input 764, output 171, cache read 0, cache write 0, cost $x.xxxx`; строка `Total` включает вызов (`usage_report_text_test.dart`, `builtin_slash_commands_test.dart`)

#### Scenario: Без отброшенных вызовов
- **WHEN** в сессии одно записанное сжатие с usage и ни одного отброшенного
- **THEN** строка — `Summaries: 1, <usage>` без скобок, как до change

## MODIFIED Requirements

### Requirement: Команда /usage
`AgentSession` SHALL объявлять и исполнять встроенную команду `usage` всегда, независимо от capability профиля и наличия порта `UsageLedgerStore` (design.md change `add-usage-ledger`, D5). Объявление — `{"name":"usage","description":"Show token usage and cost of the session","input":{"hint":"[rebuild]"}}` (§13.4). Распознавание, события хода без шагов модели, журнал (ни промпт, ни ответ не пишутся; ACP-12), слот хода, отмена и доставка событий — по общим правилам требования «Встроенные команды config и mcp». Команда только читает: отмена до ответа даёт `TurnEnded` с `cancelled` без сообщения; запись `usage.json`, начатая до отмены, доводится до конца.

Аргумент: пустой — отчёт по журналу usage (capability `agent-sessions`, «Журнал usage сессии»: свежий файл или пересчёт); `rebuild` — пересчёт всегда; иной — ответ `Usage: /usage [rebuild]`, журнал usage не строится.

Текст — фиксированные английские строки §12.6.1 с правками change: строки соединяются `\n`, после последней `\n` нет; числа — целые без разделителей; стоимость — `$` и 4 знака после точки:
- первая строка — `Session usage: <turns> turns, <steps> steps`; сессия без шагов — одна строка `Session usage: no model requests yet`;
- `Total: <usage>`; `By model:` и по строке `  <provider>/<model>: <n> steps, <usage>` на модель в лексикографическом порядке; `Subagents: <runs> runs, <usage>` и `Summaries: <count>, <usage>` — только при ненулевом счётчике; при ненулевом числе отброшенных вызовов строка суммаризатора — `Summaries: <count> (<n> discarded), <usage>` (требование «Отброшенные вызовы в отчёте /usage»; change `fix-discarded-compaction-usage`, D4);
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
