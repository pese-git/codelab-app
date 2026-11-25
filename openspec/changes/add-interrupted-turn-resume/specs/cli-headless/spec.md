## ADDED Requirements

### Requirement: Продолжение хода в headless
Headless `-p` НЕ SHALL печатать подсказку о незавершённом ходе: stdout содержит только ответ хода (design.md change `add-interrupted-turn-resume`, D8). Промпт `/continue` с `--resume <id>` или `--continue` SHALL отправляться как любой промпт; ответ агента `Nothing to continue: the last turn finished.` или ход продолжения выводятся по общим правилам вывода и кодов выхода. Вопрос о повторе прерванного вызова приходит с `_meta.codelab.critical: true` (capability `agent-permissions`, «Повтор прерванного вызова») и поэтому SHALL получать `reject_once` при любой политике `--approve`, в том числе `allow-all` (требование «Политика одобрений headless»).

#### Scenario: Headless продолжение
- **WHEN** `codelab -p "/continue" --resume <id>` запускается для сессии с незавершённым ходом
- **THEN** stdout содержит ответ хода продолжения без строки-подсказки, код выхода — по итогу хода

#### Scenario: Повтор прерванного вызова отклоняется
- **WHEN** `codelab -p "/continue" --resume <id> --approve allow-all`, и модель повторяет прерванный `exec`
- **THEN** агент получает `reject_once`, строка stderr называет причину `critical`, команда не исполняется
