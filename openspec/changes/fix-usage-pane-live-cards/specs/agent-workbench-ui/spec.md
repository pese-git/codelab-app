## MODIFIED Requirements

### Requirement: Панель Usage
CodeLab SHALL предлагать в доке панель Usage (`ToolPane.usage`) с расходом сессии в фокусе (D-09, экран 17; design.md change `add-desktop-usage-pane`, D1, D2, Q1). Источники — `SessionView.usageLedger` (журнал агента, change `add-usage-ledger`) и `SessionView.usage` (живые снимки, change `add-usage-extension`). App НЕ SHALL суммировать ходы, шаги или модели сам. Числа, деньги и «~» SHALL форматироваться функциями kit (`usage_format.dart`). Неизвестное SHALL показываться как `—`, а не как `0` (DSK-11, VIEW-6).

Предикат доступности панели (требование «Tool dock with closable pane tabs»): у сессии в фокусе `usageLedger` не `unavailable` или `usage.support` не `unknown` (D10, Q7). Недоступная панель не имеет переключателя, вкладки и пункта палитры и остаётся в сохранённой раскладке. Панель SHALL быть доступна из палитры пунктом хоста `Usage` с командой `/usage-pane`; имя `/usage` остаётся у команды агента (D11).

Панель SHALL показывать:
- шапку `This session` с кнопками `Rebuild from log` (`usage-rebuild`; есть при `usageLedger` не `unavailable`, недоступна во время `loading`) и `Export CSV` (`usage-export`; есть, когда есть журнал для показа) и строку состояния журнала (`usage-ledger-status`) (Q3; design.md change `fix-usage-pane-live-cards`, D7, Q5 (а)):
  - `upToDate` — `Ledger: up to date · N records`;
  - `rebuilt` с причиной `stale` или `missing` — штатное обновление ленивого кэша `usage.json` — тоже `Ledger: up to date · N records`, а подсказка строки — `refreshed from the session journal (<reason>)`;
  - `rebuilt` с иной причиной (`invalid`, `explicit`, незнакомая) или без причины — `rebuilt from journal (<reason>) · N records`;
  - `inMemory` — `in memory`, `notSaved` — `not saved`;
- карточки Input, Output, Cost и Turns · steps (`usage-card-input`, `usage-card-output`, `usage-card-cost`, `usage-card-turns`) из одного агрегата (design.md change `fix-usage-pane-live-cards`, D1, Q1 (в)): из `total` журнала, если журнал для показа есть (`loaded` или прежний журнал в `loading` и `failed`) и его `seq` не меньше `usage.lastSeq`; иначе из `usage.session`, если он есть; иначе из `total` журнала, если журнал для показа есть. Одна карточка НЕ SHALL складывать или смешивать журнал и живые снимки:
  - Input — `input + cacheRead + cacheWrite` (Q8) и вторая строка `cache read N · write N`;
  - Output — `output` и `reasoning N`, если `reasoning` известен;
  - Cost — стоимость с «~» при любой причине неполноты. При непустом `partial` вторая строка — тексты причин строки статуса. При неизвестной цене — `—` и `price unknown`. Исключение — агрегат без шагов, со всеми счётчиками токенов, равными нулю, и без причин неполноты: `—` и `no usage yet` (D8, Q6 (а)). `$0.00` НЕ SHALL показываться, если в агрегате нет `cost`;
  - Turns · steps — `<ходы> · <шаги>` и `avg N.N steps per turn`. Ходы — `turnCount` журнала или `turns` агрегата `usage.session` (D2). Если число ходов в источнике неизвестно — только шаги, без среднего; при нуле ходов среднего нет;
  - карточка, значение которой показано с «~», SHALL иметь тон `warning`; карточка со значением `—` тона НЕ SHALL получать; тон решает application, виджет получает его из данных;
- таблицу `Per turn` (`usage-turn-<index>`): ходы от нового к старому, подпись `N · “<title>”` (без `title` — `N`), столбцы Input, Output, Cost, пометка `running` у идущего хода; ход раскрывается до шагов (`usage-step-<turn>-<index>`) с подписью `step <index + 1> · <подпись шага>` (требование «Подпись шага в панели Usage») и моделью шага в подсказке; у хода с субагентами в раскрытом виде после его шагов — строка `subagents · N runs`;
- таблицу `Per model` (`usage-model-<n>`): модели журнала с подписью `<provider> / <id>`, ниже — строки `Subagents` и `Summaries`, если в журнале есть эти группы (Q9);
- строку без usage (все счётчики нулевые и причина `noUsage`) как `—` во всех числовых столбцах; строку без цены — `—` в столбце Cost.

Таблицы `Per turn`, `Per model` и экспорт CSV SHALL строиться только из журнала.

Состояния журнала: `idle` и `loading` без прежнего журнала — индикатор вместо таблиц; `loading` с прежним журналом — прежний журнал и индикатор в шапке; `failed` — прежний журнал, если он был, и заметка `Couldn't load usage history.` с действием `Retry` (код ошибки — в подсказке); `unavailable` при `usage.support` не `unknown` — карточки из живых снимков, без таблиц, `Export CSV` и `Rebuild from log`, заметка `This agent does not provide usage history.` (D10).

Журнал SHALL обновляться только вызовом `ClientWorkspace.refreshUsageLedger` и только по правилу (D3, Q4): автоматический запрос без `rebuild` уходит, когда панель показана (вкладка активна и док виден), сессия не `running` и не `cancelling`, журнал `idle` или `loaded` с `seq` меньше `usage.lastSeq`, и для этого значения `usage.lastSeq` автоматический запрос ещё не уходил **или** журнал вернулся в `idle` из другого состояния (kit сбросил его при переподключении или загрузке сессии) — тогда ровно один новый автоматический запрос уходит и при том же `usage.lastSeq`. Учёт автоматических запросов ведётся по сессии в фокусе; смена сессии в фокусе SHALL его сбрасывать. Состояние `failed` автоматически НЕ SHALL повторяться. `Rebuild from log` SHALL вызывать `refreshUsageLedger(id, rebuild: true)`, `Retry` — `refreshUsageLedger(id)`. Опроса по таймеру НЕ SHALL быть.

#### Scenario: Панель с журналом
- **WHEN** агент объявил `usage` и `usageLedger`, журнал сессии — два хода (второй — три шага с вызовами `read`, `edit`, `execute`), и пользователь открывает панель Usage
- **THEN** уходит один запрос журнала без `rebuild`; после ответа карточки показывают итог журнала, `Per turn` — ход 2 над ходом 1, раскрытие хода 2 показывает три строки шагов `step 1`, `step 2`, `step 3`

#### Scenario: Журнал после хода
- **WHEN** панель показана, журнал загружен с `seq` 7, и завершается ход, снимок `turn` которого поднимает `usage.lastSeq` до 10
- **THEN** после перехода сессии в `idle` уходит ровно один запрос журнала; во время хода запросов нет

#### Scenario: Журнал не догоняет снимки
- **WHEN** после автоматического запроса при `usage.lastSeq` 10 агент отвечает журналом с `seq` 9
- **THEN** второй автоматический запрос для `usage.lastSeq` 10 не уходит; следующий — только после нового снимка или по действию пользователя

#### Scenario: Переподключение при том же lastSeq
- **WHEN** панель показана, журнал загружен с `seq` 10 при `usage.lastSeq` 10, и после переподключения kit сбрасывает журнал в `idle`, а `usage.lastSeq` остаётся 10
- **THEN** уходит ровно один новый автоматический запрос журнала; следующие ревизии сессии с тем же `usage.lastSeq` и журналом `idle` новых запросов не дают

#### Scenario: Сбой загрузки журнала
- **WHEN** запрос журнала завершился ошибкой агента `-32603`
- **THEN** панель показывает `Couldn't load usage history.` и `Retry`, повторного запроса без действия пользователя нет

#### Scenario: Rebuild from log
- **WHEN** пользователь нажимает `Rebuild from log`
- **THEN** уходит запрос журнала с `rebuild: true`; после ответа строка состояния — `rebuilt from journal (explicit) · N records`

#### Scenario: Журнал пересобран после хода
- **WHEN** после хода автоматический запрос журнала получает ответ `ledger.status` `rebuilt` с причиной `stale` и 12 записями
- **THEN** строка состояния — `Ledger: up to date · 12 records`, её подсказка — `refreshed from the session journal (stale)`; при причине `invalid` строка — `rebuilt from journal (invalid) · 12 records`

#### Scenario: Карточки во время хода
- **WHEN** панель показана, журнал загружен с `seq` 0 и `total` без шагов, затем идёт ход, и снимок `step` с `seq` 1 несёт `session` с `steps` 1, `turns` 1 и `cost` `"0.00038"`
- **THEN** карточки показывают сумму снимка: Cost — `$0.00038`, Turns · steps — `1 · 1`; `price unknown` и `0` в карточках нет; таблица `Per turn` остаётся на журнале с `seq` 0

#### Scenario: Карточки после ответа журнала
- **WHEN** после хода `usage.lastSeq` — 3, журнал в `loading` с прежним журналом `seq` 0, затем приходит журнал с `seq` 3
- **THEN** пока журнал `loading`, карточки показывают сумму снимка, а не прежний журнал; после ответа — `total` журнала с `seq` 3

#### Scenario: Журнал отстал после сбоя
- **WHEN** `usageLedger` — `failed` с прежним журналом `seq` 5, а `usage.lastSeq` — 9
- **THEN** карточки показывают `usage.session`, таблицы — прежний журнал, заметка `Couldn't load usage history.`

#### Scenario: Пустая сессия
- **WHEN** журнал новой сессии без ходов загружен: `total` без шагов, с нулевыми токенами, без `cost` и без `partial`, снимков `usage` нет
- **THEN** карточка Cost показывает `—` и `no usage yet` без тона; `price unknown` и `$0.00` нет; Input и Output — `0`, Turns · steps — `0 · 0` без среднего

#### Scenario: Неизвестная цена и ход без usage
- **WHEN** журнал содержит ход, у которого все счётчики нулевые и `partial` — `["noUsage"]`, и модель без цен
- **THEN** строка хода показывает `—` в столбцах Input, Output и Cost, строка модели — `—` в столбце Cost; `0` и `$0.00` нет

#### Scenario: Неполная стоимость сессии
- **WHEN** `total.partial` журнала — `["noUsage"]`, `total.cost` — `2.26`
- **THEN** карточка Cost показывает `~$2.26` в тоне `warning` и строку `agent sent no usage for some steps`; при неизвестной `total.cost` карточка показывает `—` без тона

#### Scenario: Агент без журнала
- **WHEN** агент объявил `usage`, не объявил `usageLedger` и прислал снимок с суммой сессии, в которой `turns` 2 и `steps` 5
- **THEN** панель доступна, карточки показывают сумму снимка, Turns · steps — `2 · 5` и `avg 2.5 steps per turn`, таблиц, `Export CSV` и `Rebuild from log` нет, показана заметка `This agent does not provide usage history.`; без `turns` в снимке карточка показывает только шаги

#### Scenario: Агент без usage
- **WHEN** агент не объявил ни `usage`, ни `usageLedger`, а панель Usage сохранена открытой в раскладке
- **THEN** переключателя, вкладки и пункта палитры Usage нет, раскладка не меняется

#### Scenario: Смена сессии в фокусе
- **WHEN** запрос журнала сессии A в полёте, и фокус переходит на сессию B
- **THEN** панель показывает данные сессии B; ответ для A применяется только к `SessionView` сессии A

### Requirement: Бюджет хода в панели Usage
Панель Usage SHALL показывать блок `Turn budget` по `SessionView.usage.budget` сессии в фокусе (C-13; design.md change `add-desktop-usage-pane`, D9, Q5). Блок стоит между карточками и `Per turn`. Его источник — `usage`, а не журнал, поэтому он SHALL показываться и у агента без журнала (D10). Заголовок блока — `This turn`, пока сессия `running` или `cancelling` и `budget` не итоговый (не из снимка `turn`), иначе `Last turn` (решение пользователя Q11 (а)): от начала нового хода до его первого снимка `step` блок SHALL показывать `Last turn` прошлого хода с его числами.

Строки идут в порядке Steps, Tokens, Cost, Time и есть только для подполей, присутствующих в `budget` (`usage-budget-steps`, `usage-budget-tokens`, `usage-budget-cost`, `usage-budget-time`). У каждой строки полоса и подпись `<израсходовано> / <лимит>`:
- Steps — целые: `3 / 50`;
- Tokens — функцией kit `formatUsageTokens`: `92.0k / 200.0k`; подсказка строки SHALL называть правило `input + output, including subagents`;
- Cost — функцией kit `formatUsageMoney`: `$0.41 / $0.50`; без израсходованной стоимости (у модели нет цен) строка SHALL показывать `— / <лимит>` и `not checked: price unknown` без тона;
- Time — `m:ss`, от часа — `h:mm:ss`, секунды отбрасываются: `3:00 / 10:00`.

Тон полосы — `warning` от 80 % и `danger` от 100 %. Больше 100 % SHALL показываться в подписи как есть, а заполнение полосы ограничено 100 %. Под блоком — `When a limit is hit, the turn stops at the next step boundary.`

Время между снимками (design.md change `fix-usage-pane-live-cards`, D3, D4, Q2 (б), Q4 (а)). Бюджет живой, пока сессия `running` или `cancelling` и `budget` не итоговый. У живого бюджета строка Time SHALL показывать `usedMs + max(0, (now − receivedAt) − W)`. Здесь `W` — длительность объединения интервалов ожидания одобрений корня текущего хода (`SessionView` из kit, требование `acp-client-kit` «Ожидания одобрений корня хода»), обрезанных отрезком от `receivedAt` до `now`. Ожидающее одобрение даёт интервал до `now`. Сложение насыщающее. Иначе Time показывает `usedMs` последнего снимка. Отсюда:
- пока ждёт одобрение корня, значение Time НЕ SHALL меняться и НЕ SHALL уменьшаться;
- после ответа на одобрение Time НЕ SHALL включать время ожидания;
- одобрение субагента Time НЕ SHALL останавливать: цикл корня это время считает.

Строка Time SHALL обновляться раз в секунду, пока бюджет живой, в нём есть `duration` и нет ожидающего одобрения корня. Таймер SHALL идти только пока панель показана и SHALL отменяться при скрытии панели и при смене условия. Без `budget` блока НЕ SHALL быть.

#### Scenario: Прогресс во время хода
- **WHEN** идёт ход, и последний снимок `step` несёт `budget` с `tokens {used 92000, limit 200000}`, `cost {used "0.41", limit "0.5"}`, `duration {usedMs 180000, limitMs 600000}`, `steps {used 3, limit 50}`
- **THEN** блок `This turn` показывает `3 / 50`, `92.0k / 200.0k`, `$0.41 / $0.50` (тон `warning`) и `3:00 / 10:00`

#### Scenario: Время идёт между шагами
- **WHEN** снимок применён с `duration.usedMs` 180000, сессия `running`, одобрений нет, прошло 5 с
- **THEN** строка Time показывает `3:05 / 10:00`

#### Scenario: Одобрение не откатывает время
- **WHEN** снимок применён с `duration.usedMs` 3000 в момент T, сессия `running`, в T + 2 с агент запрашивает одобрение корня, и до ответа проходит 60 с
- **THEN** до запроса Time растёт до `0:05`; с T + 2 с до ответа Time стоит на `0:05` и не возвращается к `0:03`, тика нет; через 3 с после ответа Time — `0:08`, а не `1:08`

#### Scenario: Два одобрения одновременно
- **WHEN** после снимка с `duration.usedMs` 0 в момент T агент запрашивает два одобрения корня в T + 1 с и T + 2 с, оба получают ответ в T + 61 с, сейчас T + 64 с
- **THEN** Time — `0:04`: ожидание с T + 1 с по T + 61 с вычтено один раз

#### Scenario: Одобрение субагента
- **WHEN** снимок применён с `duration.usedMs` 180000, сессия `running`, ожидает только одобрение субагента, прошло 5 с
- **THEN** Time показывает `3:05 / 10:00` и тикает

#### Scenario: Отмена хода
- **WHEN** снимок применён с `duration.usedMs` 180000, через 5 с пользователь отменяет ход, сессия `cancelling`, прошло ещё 2 с
- **THEN** Time показывает `3:07 / 10:00`, а не `3:00`; после снимка `turn` — его `usedMs` с заголовком `Last turn`

#### Scenario: Таймер только при показанной панели
- **WHEN** идёт ход с `duration` в `budget`, и пользователь переключает док на другую вкладку или ход завершается
- **THEN** таймер панели отменён, перестроений раз в секунду нет

#### Scenario: Начало нового хода
- **WHEN** ход A завершился снимком `turn` с `budget` (`duration.usedMs` 90000), пользователь отправил новый промпт, сессия `running`, а снимков хода B ещё нет
- **THEN** блок `Last turn` показывает итог хода A (`1:30 / 10:00`) без тика; после первого снимка `step` хода B с `budget` блок — `This turn` с числами хода B, и Time тикает

#### Scenario: Цена неизвестна
- **WHEN** `budget.cost` несёт `limit` `"0.5"` без `used`
- **THEN** строка Cost показывает `— / $0.50` и `not checked: price unknown`, не `$0.00 / $0.50`

#### Scenario: После хода
- **WHEN** ход завершился снимком `turn` с `budget`, где `cost.used` `"0.52"` при `limit` `"0.5"`
- **THEN** блок `Last turn` показывает `$0.52 / $0.50` в тоне `danger`, полоса заполнена полностью

#### Scenario: Бюджет у агента без журнала
- **WHEN** агент объявил `usage`, не объявил `usageLedger`, и снимок `turn` несёт `budget`
- **THEN** панель показывает карточки, заметку `This agent does not provide usage history.` и блок `Turn budget`

#### Scenario: Без лимитов
- **WHEN** снимки сессии не несут `budget`
- **THEN** блока `Turn budget` нет
