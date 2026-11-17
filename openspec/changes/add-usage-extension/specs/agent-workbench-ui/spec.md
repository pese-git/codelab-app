## ADDED Requirements

### Requirement: Строка статуса сессии под композером
Workbench SHALL показывать под композером активной сессии строку статуса слева направо: модель · режим · заполнение контекста · токены хода (`<вход> → <выход>`, вход — `input + cacheRead + cacheWrite`) · стоимость хода и `session <стоимость сессии>` (design.md change `add-usage-extension`, D11; `dart-agent-and-clients` §12.3, A7). Источник — `SessionView.usage` и опции сессии; app ничего не суммирует и не оценивает сам. Виджет из `codelab_ui` получает готовые подписи и тон и не содержит логики.

Правила показа (DSK-11, VIEW-6):
- `usage.support == unknown` — вместо сегментов usage подпись `usage: —` с подсказкой `agent does not report usage`; нули НЕ SHALL показываться;
- `awaiting` — сегментов usage нет; во время хода — при статусе сессии `running` или `cancelling` — рядом с местом токенов хода индикатор выполнения; при `unknown` и `reported` индикатора нет (решение пользователя 2026-11-16 по ревью итерации 3, design.md, D23 Т9 п. 2);
- неполная сумма — префикс `~` перед токенами при причинах `noUsage` или `beforeLoad` и перед стоимостью при любой причине;
- токены хода с `input + cacheRead + cacheWrite = 0` и `output = 0` — `status-bar-usage` отсутствует, `0 → 0` НЕ SHALL показываться; один ненулевой счётчик сохраняет сегмент (D23 Т9 п. 4);
- стоимость: `status-bar-cost` показывает `<стоимость хода> · session <стоимость сессии>` (`$0.0041 · session $1.20`); неизвестная цена хода при известной цене сессии — `— · session $1.20`, в том числе когда снимка хода нет, а итог сессии есть (`lastTurn` пуст; тогда и `status-bar-usage` отсутствует, D23 Т9 п. 3); обе неизвестны при известных токенах — `—` с подсказкой `price unknown`; цена сессии неизвестна — только стоимость хода (решение пользователя 2026-11-16, Q19 (а));
- контекст без размера окна или с `used = 0` скрыт; процент — целый, вниз (`⌊used × 100 / size⌋`), процент 0 при `used > 0` — `<1%`; тон по тому же целому проценту: ≥ 80 — `warning`, ≥ 95 — `danger` (Q17 (а)); подпись `compaction soon` — только при `context.compactionSoon` (известный `compactAt` и `used ≥ 0.9 × compactAt`; design.md, D11);
- деньги форматируются из целых микроединиц без `double`, разделитель — точка: от 0,01 — два знака с округлением половины вверх (`1.2` → `$1.20`, `0.125` → `$0.13`); больше 0 и меньше 0,01 — две значащие цифры с округлением половины вверх без хвостовых нулей (`0.0041` → `$0.0041`, `0.004` → `$0.004`, `0.004567` → `$0.0046`); известный ноль — `$0.00`; валюта `USD` — префикс `$`, иная — суффикс (`12.34 EUR`);
- токены: меньше 1000 — как есть, далее тысячи и миллионы с одним знаком и округлением половины вверх (`94049` → `94.0k`, `999950` → `1.0M`, `1234567` → `1.2M`);
- деньги, токены и процент форматирует одна функция `codelab_client_core`, общая с CLI (design.md change `add-usage-extension`, D24; Q16 (а));
- подсказка `status-bar-usage` — строка счётчиков хода точными числами `input N · output N · cache read N · cache write N` и ` · reasoning N`, если `reasoning` известен; при непустом `partial` хода — вторая строка `approximate: <причины через ", ">` в порядке `noUsage`, `noPrice`, `beforeLoad` с текстами `agent sent no usage for some steps`, `price unknown for some steps`, `before the session was loaded`; у `status-bar-cost` подсказки причин нет (решение пользователя 2026-11-16 по ревью итерации 3 — принять реализацию как есть, D23 Т9 п. 1).

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

#### Scenario: Процент вниз
- **WHEN** `context.used = 159200`, `context.size = 200000` (79,6 %)
- **THEN** `status-bar-context` показывает `79%` без тона `warning`

#### Scenario: Меньше одного процента
- **WHEN** `context.used = 500`, `context.size = 200000`
- **THEN** `status-bar-context` показывает `<1%`; при `context.used = 0` `status-bar-context` отсутствует

#### Scenario: Формат денег
- **WHEN** стоимость хода `0.0041`, стоимость сессии `1.2`, валюта `USD`
- **THEN** `status-bar-cost` показывает `$0.0041 · session $1.20`

#### Scenario: Цена хода неизвестна, сессии известна
- **WHEN** снимок несёт `turn` без `cost` и `session.cost` `1.2`
- **THEN** `status-bar-cost` показывает `— · session $1.20`

#### Scenario: Неполная сумма после загрузки
- **WHEN** `session.partial` содержит `beforeLoad`
- **THEN** стоимость сессии показана с префиксом `~`

#### Scenario: Цена неизвестна
- **WHEN** снимок несёт токены хода и сессии без `cost`
- **THEN** `status-bar-cost` показывает `—` с подсказкой `price unknown`, а не `$0`

#### Scenario: Подсказка причин неполноты
- **WHEN** снимок несёт ход с `input 1200`, `output 300`, `cacheRead 0`, `cacheWrite 0` без `reasoning` и `partial` хода `["noUsage", "beforeLoad"]`
- **THEN** `status-bar-usage` показывает `~1.2k → 300` с подсказкой из двух строк: `input 1200 · output 300 · cache read 0 · cache write 0` и `approximate: agent sent no usage for some steps, before the session was loaded`

#### Scenario: Причина noPrice в подсказке токенов
- **WHEN** `partial` хода — `["noPrice"]`
- **THEN** токены `status-bar-usage` без `~`, а подсказка содержит строку `approximate: price unknown for some steps`

#### Scenario: Индикатор при отмене до первого снимка
- **WHEN** агент объявил `usage`, снимков ещё нет, и пользователь отменяет первый ход (статус сессии `cancelling`)
- **THEN** индикатор выполнения показан, сегментов usage нет; после исхода хода без снимков (статус `idle`) индикатора нет

#### Scenario: Индикатор при reported
- **WHEN** хотя бы один снимок применён и идёт следующий ход
- **THEN** индикатора выполнения нет, показаны значения последнего снимка

#### Scenario: Итог сессии без снимка хода
- **WHEN** после `session/load` первым приходит снимок `compaction` без `turnId` с `session.cost` `1.2` и `session.partial` `["beforeLoad"]`
- **THEN** `status-bar-usage` отсутствует, `status-bar-cost` показывает `— · session ~$1.20`; без `session.cost` сегмента стоимости нет

#### Scenario: Нулевые токены хода
- **WHEN** снимок несёт ход с нулями во всех счётчиках, стоимостью хода `0.0041` и стоимостью сессии `1.2`
- **THEN** `status-bar-usage` отсутствует, `status-bar-cost` показывает `$0.0041 · session $1.20`; при ненулевом `output` сегмент токенов показан
