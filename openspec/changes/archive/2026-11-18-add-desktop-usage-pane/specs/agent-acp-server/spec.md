## ADDED Requirements

### Requirement: Бюджет хода в уведомлении `_codelab/session/usage`
Снимки `_codelab/session/usage` с поводом `step` и `turn` SHALL нести необязательное поле `budget`, если у хода задан хотя бы один из лимитов `budget.max_tokens`, `budget.max_cost`, `budget.max_duration` (design.md change `add-desktop-usage-pane`, D7, Q5; правило совместимости D2 change `add-usage-extension`: новое необязательное поле — без смены версии `usage`). Без таких лимитов поля НЕ SHALL быть; в снимках `compaction`, `compactionDiscarded` (change `fix-discarded-compaction-usage`) и `load` его НЕ SHALL быть.

Состав (значения — из прогресса бюджета `StepEnded` и `TurnEnded`, требование agent-loop «Прогресс бюджета хода в событиях шага и хода»):
- `steps` — `{"used": <целое>, "limit": <целое>}`, всегда при наличии поля;
- `tokens` — `{"used": <целое>, "limit": <целое>}`, только при заданном `max_tokens`;
- `cost` — `{"used": "<десятичная строка>", "limit": "<десятичная строка>"}`, только при заданном `max_cost`; строки — по правилу денег D9 change `add-usage-extension` из целых микродолларов (`limit` — `round(max_cost × 10⁶)`); `used` отсутствует, если у текущей модели нет цен; при наличии `budget.cost` снимок SHALL нести `currency`;
- `duration` — `{"usedMs": <целое>, "limitMs": <целое>}`, только при заданном `max_duration`.

Невалидный `max_cost` — NaN, бесконечность, отрицательное число или сумма, не представимая целыми микродолларами, — SHALL давать `budget` без подполя `cost`; если других необязательных лимитов (`tokens`, `duration`) нет, поля `budget` НЕ SHALL быть. Снимок при этом SHALL уходить.

Объявление `usage: {"version": 1}`, правила `seq`, порядка и адресатов уведомления (требование «Уведомление `_codelab/session/usage`») НЕ SHALL меняться. Клиент, не знающий поля, его игнорирует.

#### Scenario: Бюджет в снимках хода
- **WHEN** клиент объявил `usage`, конфигурация задаёт `budget.max_tokens: 200000` и `budget.max_cost: 0.5`, и ход идёт два шага на модели с ценами
- **THEN** оба снимка `step` и снимок `turn` несут `budget` с `steps`, `tokens` и `cost`, без `duration`; `steps.used` — 1, 2 и 2 (фикстура `acp/prompt-usage-budget`)

#### Scenario: Без лимитов кроме шагов
- **WHEN** конфигурация задаёт только `budget.max_steps`
- **THEN** снимки `step` и `turn` не несут `budget` (фикстуры `acp/prompt-usage-steps` и другие usage-фикстуры не меняются)

#### Scenario: Лимит стоимости на модели без цен
- **WHEN** задан `budget.max_cost: 0.5`, а модель без цен
- **THEN** `budget.cost` — `{"limit": "0.5"}` без `used`, снимок несёт `currency` `USD`

#### Scenario: Снимок сжатия
- **WHEN** после хода с лимитами идёт фоновое сжатие, или проход сжатия отброшен после оплаченного вызова суммаризатора
- **THEN** снимок `compaction` или `compactionDiscarded` не несёт `budget`

#### Scenario: Невалидный лимит стоимости
- **WHEN** `max_cost` — NaN, а `max_tokens` задан
- **THEN** снимки `step` и `turn` несут `budget` с `steps` и `tokens` без `cost`; при одном NaN `max_cost` без других необязательных лимитов поля `budget` нет
