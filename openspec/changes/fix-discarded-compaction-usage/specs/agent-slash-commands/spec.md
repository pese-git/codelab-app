## ADDED Requirements

### Requirement: Отброшенные вызовы в отчёте /usage
Строка суммаризатора команды `/usage` (требование «Команда /usage» change `add-usage-ledger`) SHALL иметь вид `Summaries: <count> (<n> discarded), <usage>`, где `<n>` — число отброшенных вызовов группы (требование `agent-sessions` «Отброшенные вызовы суммаризатора в журнале usage»; design.md change `fix-discarded-compaction-usage`, D4; решение пользователя Q2 (а)). Часть ` (<n> discarded)` SHALL выводиться только при ненулевом `<n>`. Без неё строка прежняя. Правило `<cost>` и `~` не меняется, отброшенные вызовы — части строки `Summaries` и `Total`. Ответ `/compact` на проход без выигрыша остаётся `Nothing to compact.`

#### Scenario: /usage после /compact без выигрыша
- **WHEN** в сессии один ход на модели с ценами, затем `/compact` отброшен по CMP-10 с usage суммаризатора `{input: 764, output: 171}` на модели с ценами, и приходит `/usage`
- **THEN** ответ содержит строку `Summaries: 1 (1 discarded), input 764, output 171, cache read 0, cache write 0, cost $x.xxxx`; строка `Total` включает вызов (`usage_report_text_test.dart`, `builtin_slash_commands_test.dart`)

#### Scenario: Без отброшенных вызовов
- **WHEN** в сессии одно записанное сжатие с usage и ни одного отброшенного
- **THEN** строка — `Summaries: 1, <usage>` без скобок, как до change
