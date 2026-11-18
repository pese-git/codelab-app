## ADDED Requirements

### Requirement: Цены моделей конфигурации
Ключи цен модели `providers.<p>.models.<m>.cost_input`, `cost_output`, `cost_cache_read` и `cost_cache_write` (тип `float`, доллары за 10⁶ токенов) SHALL принимать только неотрицательные конечные числа; `0` допустим (бесплатная модель). Отрицательное значение и не конечное значение (`.nan`, `.inf`, `-.inf` YAML, число вне диапазона `double`) SHALL давать проблему этого ключа при проверке слоя (`CoreConfig.fromLayers`, требование «Схема и строгая проверка»), и `CoreConfig` НЕ SHALL строиться — так же, как у других семантических проверок §15.5, шаг 8. Текст проблемы SHALL называть путь ключа и ожидание `must be a finite number not less than 0` и НЕ SHALL содержать значения (требование «Наблюдаемость загрузки конфигурации»). Правило SHALL действовать для всех слоёв, включая окружение, флаги и хранилище приложения, и для `config check`, который печатает проблему и завершается кодом ошибки, как при любой другой проблеме (design.md change `add-usage-extension`, D20).

Почему: цены входят в стоимость хода (`calculateCost`, `agent-llm`), а стоимость — в уведомление `_codelab/session/usage`; бесконечная цена давала исключение при проекции события и ошибку `-32603` любому клиенту, а отрицательная печаталась как положительная строка стоимости (D20).

#### Scenario: Отрицательная цена
- **WHEN** `config.yaml` задаёт у модели `gw/m` `cost_input: -1`
- **THEN** загрузка даёт проблему с ключом `providers.gw.models.m.cost_input` и текстом `must be a finite number not less than 0` без значения `-1`, `CoreConfig` не построен, а `codelab-agent config check` печатает эту проблему и завершается кодом ошибки

#### Scenario: Бесконечная и неопределённая цена
- **WHEN** `config.yaml` задаёт у модели `gw/m` `cost_output: .inf` и `cost_cache_read: .nan`
- **THEN** загрузка даёт две проблемы — `providers.gw.models.m.cost_output` и `providers.gw.models.m.cost_cache_read`, `CoreConfig` не построен

#### Scenario: Нулевая и дробная цена
- **WHEN** `config.yaml` задаёт у модели `gw/m` `cost_input: 0`, `cost_output: 2` и `cost_cache_write: 0.3`
- **THEN** проблем нет, `ModelRef.cost` модели — `input` 0, `output` 2, `cacheWrite` 0.3 (целое `2` принимается как `float`)
