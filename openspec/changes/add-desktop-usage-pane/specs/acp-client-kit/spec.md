## ADDED Requirements

### Requirement: Бюджет хода в usage сессии
`UsageView` SHALL содержать `budget` — прогресс бюджета хода из поля `budget` снимков `_codelab/session/usage` (design.md change `add-desktop-usage-pane`, D9): `steps`, `tokens`, `cost` (израсходованное — `Money?`, лимит — `Money`), `duration` (`usedMs`, `limitMs`), `turnId` снимка и `receivedAt` — момент применения снимка по часам рабочего пространства. Разбор SHALL жить в `UsageDecoder` по общим правилам: целые ≥ 0; деньги — правилом разбора `cost` (микроединицы без `double`, `currency` по `^[A-Z]{3}$`); `budget.cost` без `currency` или с неверным лимитом отсутствует. Неверное подполе — подполя нет; `budget` не объект — поля нет; в обоих случаях WARNING `usage.decode_failed` с `field: budget.<подполе>` по правилу «не чаще раза на сессию и поле», снимок применяется. Незнакомые ключи внутри `budget` SHALL игнорироваться.

Свёртка: снимок с `turnId` и `budget` SHALL заменять `budget`; снимок с тем же `turnId` без `budget` его не меняет; снимок с новым `turnId` без `budget` SHALL делать его `null`; снимок без `turnId` его не меняет. Правила `seq`, сброса при переподключении и `session/load` — те же, что у остального `usage` (требование «Usage сессии»). Kit НЕ SHALL досчитывать время сам: оценку между снимками делает хост по `receivedAt`.

#### Scenario: Бюджет из снимка шага
- **WHEN** снимок `step` хода A несёт `budget` с `tokens {used 92000, limit 200000}` и `cost {used "0.41", limit "0.5"}` при `currency` `USD`
- **THEN** `usage.budget.tokens` — 92000 из 200000, `cost.used.micros` — 410000, `cost.limit.micros` — 500000, `turnId` — A

#### Scenario: Новый ход без лимитов
- **WHEN** после хода A с `budget` приходит снимок `step` хода B без `budget`
- **THEN** `usage.budget` — `null`

#### Scenario: Снимок сжатия
- **WHEN** после снимка `turn` хода A с `budget` приходит снимок `compaction`
- **THEN** `usage.budget` не меняется

#### Scenario: Неверное подполе
- **WHEN** `budget.tokens` — `{"used": "many", "limit": 200000}`
- **THEN** снимок применён, `usage.budget.tokens` — `null`, остальные подполя разобраны, записано одно предупреждение `usage.decode_failed` с `field: budget.tokens`

### Requirement: Точная запись суммы usage
Kit SHALL предоставлять `formatUsageMoneyExact(Money)` — точную десятичную строку суммы для экспорта (design.md change `add-desktop-usage-pane`, D5): целая часть, точка и до 6 знаков без хвостовых нулей, ноль — `0`, без символа и кода валюты, без `double`. Строка SHALL совпадать с формой `cost` на проводе (D9 change `add-usage-extension`), так что разбор строки даёт исходные микроединицы.

#### Scenario: Обратимость
- **WHEN** `Money.micros` — 2260000, 41, 0 и 999999999999999
- **THEN** строки — `2.26`, `0.000041`, `0` и `999999999.999999`, и разбор каждой строки правилом `cost` даёт исходные микроединицы
