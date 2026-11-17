## ADDED Requirements

### Requirement: Фикстура бюджета хода в usage
Корпус SHALL содержать фикстуру `acp/prompt-usage-budget` с ролями `agent` и `client`, метками `usage` в `extensions` и ссылками `spec` на `15-Extensibility.md` (design.md change `add-desktop-usage-pane`, D7): клиент объявил `usage`; конфигурация агента (`setup.config`) задаёт `budget.max_tokens` и `budget.max_cost`; ход из двух шагов модели с ценами; снимки `step` и `turn` несут `budget` с `steps`, `tokens` и `cost`. Агентская роль сверяет форму и значения поля; клиентская — что `UsageView.budget` после снимка `turn` равен итогу из кадра. Существующие фикстуры с меткой `usage` НЕ SHALL меняться: в их конфигурации нет лимитов, кроме шагов.

#### Scenario: Агентский прогон
- **WHEN** `conformance:agent` проигрывает `acp/prompt-usage-budget`
- **THEN** каждый снимок `step` и `turn` содержит `budget` с ожидаемыми `used` и `limit`, и снимков без `budget` в ходе нет

#### Scenario: Клиентский прогон
- **WHEN** `conformance:client` проигрывает `acp/prompt-usage-budget`
- **THEN** после кадра снимка `turn` `SessionView.usage.budget` несёт `tokens.used`, `tokens.limit`, `cost.used` и `cost.limit` из кадра

#### Scenario: Существующие фикстуры
- **WHEN** агентский драйвер проигрывает `acp/prompt-usage-steps`
- **THEN** кадры совпадают без правки фикстуры: поля `budget` нет
