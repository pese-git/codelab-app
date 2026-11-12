## ADDED Requirements

### Requirement: Строка статуса сессии под композером
Workbench SHALL показывать под композером активной сессии строку статуса слева направо: модель · режим · заполнение контекста · токены хода (`<вход> → <выход>`, вход — `input + cacheRead + cacheWrite`) · стоимость хода · `session <стоимость сессии>` (design.md change `add-usage-extension`, D11; `dart-agent-and-clients` §12.3, A7). Источник — `SessionView.usage` и опции сессии; app ничего не суммирует и не оценивает сам. Виджет из `codelab_ui` получает готовые подписи и тон и не содержит логики.

Правила показа (DSK-11, VIEW-6):
- `usage.support == unknown` — вместо сегментов usage подпись `usage: —` с подсказкой `agent does not report usage`; нули НЕ SHALL показываться;
- `awaiting` — сегментов usage нет; во время хода рядом с местом токенов хода — индикатор выполнения;
- неполная сумма — префикс `~` перед токенами при причинах `noUsage` или `beforeLoad` и перед стоимостью при любой причине;
- стоимость отсутствует при известных токенах — `—` с подсказкой `price unknown`;
- контекст без размера окна скрыт, `0 %` не показывается; тон ≥ 80 % — `warning`, ≥ 95 % — `danger`; подпись `compaction soon` — только при `context.compactionSoon` (известный `compactAt` и `used ≥ 0.9 × compactAt`; design.md, D11);
- деньги форматируются из целых микроединиц без `double`;
- подсказка токенов показывает `input`, `output`, `cacheRead`, `cacheWrite` и `reasoning` (если известен).

Ключи: `status-bar-usage`, `status-bar-cost`, `status-bar-context`. Клик по строке в этом change ничего не делает.

#### Scenario: Агент без расширения
- **WHEN** активная сессия у агента, который не объявил `usage`
- **THEN** `status-bar-usage` показывает `usage: —`, `status-bar-cost` и `status-bar-context` отсутствуют, на строке нет `0`

#### Scenario: Два хода
- **WHEN** агент прислал снимки двух ходов
- **THEN** поле хода показывает второй ход, поле сессии — сумму сессии из снимка, подсказка содержит пять счётчиков

#### Scenario: Контекст близко к пределу
- **WHEN** `context.used = 170000`, `context.size = 200000`
- **THEN** `status-bar-context` показывает `85%` в тоне `warning`

#### Scenario: Скоро сжатие
- **WHEN** `context.used = 168000`, `size = 200000`, `compactAt = 183616`
- **THEN** `status-bar-context` показывает `84% context · compaction soon` в тоне `warning`; без `compactAt` — `84% context` без подписи

#### Scenario: Неполная сумма после загрузки
- **WHEN** `session.partial` содержит `beforeLoad`
- **THEN** стоимость сессии показана с префиксом `~`

#### Scenario: Цена неизвестна
- **WHEN** снимок несёт токены хода без `cost`
- **THEN** `status-bar-cost` показывает `—` с подсказкой `price unknown`, а не `$0`
