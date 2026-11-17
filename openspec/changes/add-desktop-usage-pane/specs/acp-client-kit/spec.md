## ADDED Requirements

### Requirement: Бюджет хода в usage сессии
`UsageView` SHALL содержать `budget` — прогресс бюджета хода из поля `budget` снимков `_codelab/session/usage` (design.md change `add-desktop-usage-pane`, D9). В нём необязательные подполя `steps`, `tokens` (`used`, `limit` — целые), `cost` (израсходованное — `Money?`, лимит — `Money`) и `duration` (`usedMs`, `limitMs` — целые), а также `turnId` снимка, `receivedAt` — момент применения снимка по часам рабочего пространства (`ClientWorkspace(clock: …)`) — и признак `ended` «итог хода»: бюджет взят из снимка с поводом `turn` (решение пользователя Q11 (а)). Свёртка SHALL оставаться чистой: момент применения передаёт вызывающий, а kit НЕ SHALL вызывать `DateTime.now` в проекции.

Разбор SHALL жить в `UsageDecoder` по общим правилам снимка:
- `steps`, `tokens`, `duration` — объект с обоими целыми ≥ 0;
- `cost.limit` обязателен, `cost.used` необязателен; оба разбираются правилом `cost` (микроединицы без `double`, целая часть не длиннее 9 цифр). Отсутствующий `used` — цена неизвестна, `used` или `limit` не по формату — подполя `cost` нет;
- `budget.cost` без `currency` SHALL отсутствовать с общим предупреждением `currency` (`required_with_cost`);
- неверное подполе — подполя нет, WARNING `usage.decode_failed` с `field: budget.<подполе>`; `budget` не объект — поля нет, `field: budget`. Предупреждения подчиняются правилу «не чаще раза на сессию и поле», снимок применяется;
- незнакомые ключи внутри `budget` и его подполей SHALL игнорироваться без предупреждения;
- `budget` без единого разобранного известного подполя SHALL считаться отсутствующим в снимке.

Свёртка: снимок с `turnId` и `budget` SHALL заменять `budget`, `ended` SHALL быть истинен только у снимка с поводом `turn`; снимок с тем же `turnId` без `budget` его не меняет, кроме снимка `turn`, который SHALL ставить `ended` при прежних числах; снимок с новым `turnId` без `budget` SHALL делать его `null`; снимок без `turnId` (`compaction`, `compactionDiscarded`, `load`, незнакомый повод) его не меняет. Правила `seq`, поколения соединения, сброса при переподключении и `session/load` — те же, что у остального `usage` (требование «Usage сессии»): сброс SHALL делать `budget` равным `null`. Kit НЕ SHALL досчитывать время сам: оценку между снимками делает хост по `receivedAt`.

#### Scenario: Бюджет из снимка шага
- **WHEN** снимок `step` хода A несёт `budget` с `tokens {used 92000, limit 200000}` и `cost {used "0.41", limit "0.5"}` при `currency` `USD`, а часы рабочего пространства показывают T
- **THEN** `usage.budget.tokens` — 92000 из 200000, `cost.used.micros` — 410000, `cost.limit.micros` — 500000, `turnId` — A, `receivedAt` — T, `ended` ложен, а `steps` и `duration` отсутствуют

#### Scenario: Итог хода
- **WHEN** после снимков `step` хода A с `budget` приходит снимок `turn` хода A с `budget`
- **THEN** `usage.budget` — числа снимка `turn`, `ended` истинен; следующий снимок `step` хода B с `budget` делает `ended` ложным

#### Scenario: Цена неизвестна
- **WHEN** `budget.cost` — `{"limit": "0.5"}` без `used`, `currency` — `USD`
- **THEN** `usage.budget.cost.used` — `null`, `cost.limit.micros` — 500000, предупреждений нет

#### Scenario: Тот же ход без бюджета
- **WHEN** после снимка `step` хода A с `budget` приходит снимок хода A без `budget`
- **THEN** `usage.budget` и его `receivedAt` не меняются

#### Scenario: Новый ход без лимитов
- **WHEN** после хода A с `budget` приходит снимок `step` хода B без `budget`
- **THEN** `usage.budget` — `null`

#### Scenario: Снимки без хода
- **WHEN** после снимка `turn` хода A с `budget` приходят снимки `compaction` и `compactionDiscarded`
- **THEN** `usage.budget` не меняется

#### Scenario: Неверное подполе
- **WHEN** `budget.tokens` — `{"used": "many", "limit": 200000}`
- **THEN** снимок применён, `usage.budget.tokens` — `null`, остальные подполя разобраны, записано одно предупреждение `usage.decode_failed` с `field: budget.tokens`

#### Scenario: Бюджет не объект
- **WHEN** `budget` — строка
- **THEN** снимок применён как снимок без `budget`, записано одно предупреждение `usage.decode_failed` с `field: budget`

#### Scenario: Сброс при переподключении и загрузке
- **WHEN** у сессии есть `usage.budget`, и рабочее пространство переподключается к агенту или начинает `session/load` этой сессии
- **THEN** `usage.budget` — `null` вместе со сбросом остального `usage`

### Requirement: Точная запись суммы usage
Kit SHALL предоставлять `formatUsageMoneyExact(Money)` — точную десятичную строку суммы для экспорта (design.md change `add-desktop-usage-pane`, D5): целая часть, точка и до 6 знаков без хвостовых нулей, ноль — `0`, без символа и кода валюты, без `double`. Строка SHALL совпадать с формой `cost` на проводе (D9 change `add-usage-extension`), так что разбор строки даёт исходные микроединицы.

#### Scenario: Обратимость
- **WHEN** `Money.micros` — 2260000, 41, 0 и 999999999999999
- **THEN** строки — `2.26`, `0.000041`, `0` и `999999999.999999`, и разбор каждой строки правилом `cost` даёт исходные микроединицы
