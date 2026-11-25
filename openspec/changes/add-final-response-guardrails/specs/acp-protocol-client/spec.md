## ADDED Requirements

### Requirement: Удержанный ответ в итоге хода
Если ответ на `session/prompt` имеет `stopReason: end_turn` и строковое непустое `_meta.codelab.held`, CodeLab SHALL сохранять это значение в итоге prompt turn как причину удержания ответа (design.md change `add-final-response-guardrails`, D7). Перед сохранением переводы строк SHALL заменяться пробелом, а строка длиннее 500 рун SHALL обрезаться до 500 рун с `…`. Не строка, пустая строка или отсутствие поля SHALL давать итог без причины без ошибки разбора. При другом `stopReason` поле SHALL игнорироваться. Статус хода и `stopReason` от `held` НЕ SHALL меняться: ход завершён штатно.

#### Scenario: Удержанный ответ
- **WHEN** агент отвечает `{"stopReason": "end_turn", "_meta": {"codelab": {"held": "revision limit reached: [open_tasks] Tasks still in progress: #1 Run the tests"}}}`
- **THEN** prompt turn завершён со `stopReason` `endTurn` и причиной удержания, равной строке `held`

#### Scenario: Многострочная причина
- **WHEN** `held` равен `"line one\nline two"`
- **THEN** причина удержания — `line one line two`

#### Scenario: Причина не строкой
- **WHEN** агент отвечает `end_turn` с `_meta.codelab.held: {"reason": "x"}`
- **THEN** prompt turn завершён без причины удержания, без ошибки разбора

#### Scenario: held при другом stopReason
- **WHEN** агент отвечает `max_turn_requests` с `_meta.codelab.held: "x"`
- **THEN** причина удержания не сохраняется

#### Scenario: Сторонний агент
- **WHEN** агент отвечает `end_turn` без `_meta`
- **THEN** prompt turn завершён без причины удержания, как прежде
