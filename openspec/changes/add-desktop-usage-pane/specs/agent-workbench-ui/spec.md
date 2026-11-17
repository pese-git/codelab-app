## MODIFIED Requirements

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

Ключи: `status-bar-usage`, `status-bar-cost`, `status-bar-context`. Клик по строке SHALL открывать панель Usage дока и делать её активной (требование «Панель Usage»; design.md change `add-desktop-usage-pane`, D6, Q10): строка кликабельна (курсор-рука, фокус клавиатуры, Enter и Space), только когда панель Usage доступна для сессии в фокусе; повторный клик панель НЕ SHALL закрывать. Без доступной панели (агент не объявил ни `usage`, ни `usageLedger`) строка некликабельна. Подсказки сегментов клик не отменяет.

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

#### Scenario: Клик открывает панель Usage
- **WHEN** агент объявил `usage` и `usageLedger`, панель Usage закрыта, и пользователь кликает строку статуса
- **THEN** док показывает вкладку Usage активной; повторный клик оставляет её открытой и активной

#### Scenario: Строка без данных некликабельна
- **WHEN** агент не объявил ни `usage`, ни `usageLedger`
- **THEN** строка показывает `usage: —`, клик по ней ничего не открывает, переключателя Usage в app bar нет

## ADDED Requirements

### Requirement: Панель Usage
CodeLab SHALL предлагать в доке панель Usage (`ToolPane.usage`) с расходом сессии в фокусе (D-09, экран 17; design.md change `add-desktop-usage-pane`, D1, D2, Q1). Источники — `SessionView.usageLedger` (журнал агента, change `add-usage-ledger`) и `SessionView.usage` (живые снимки, change `add-usage-extension`). App НЕ SHALL суммировать ходы, шаги или модели сам. Числа, деньги и «~» SHALL форматироваться функциями kit (`usage_format.dart`). Неизвестное SHALL показываться как `—`, а не как `0` (DSK-11, VIEW-6).

Предикат доступности панели (требование «Tool dock with closable pane tabs»): у сессии в фокусе `usageLedger` не `unavailable` или `usage.support` не `unknown` (D10, Q7). Недоступная панель не имеет переключателя, вкладки и пункта палитры и остаётся в сохранённой раскладке. Панель SHALL быть доступна из палитры пунктом хоста `Usage` с командой `/usage-pane`; имя `/usage` остаётся у команды агента (D11).

Панель SHALL показывать:
- шапку `This session` с кнопками `Rebuild from log` (`usage-rebuild`; есть при `usageLedger` не `unavailable`, недоступна во время `loading`) и `Export CSV` (`usage-export`; есть, когда есть журнал для показа) и строку состояния журнала (`usage-ledger-status`): `Ledger: up to date · N records`, `rebuilt from journal (<reason>) · N records`, `in memory`, `not saved` (Q3);
- карточки Input, Output, Cost и Turns · steps (`usage-card-input`, `usage-card-output`, `usage-card-cost`, `usage-card-turns`) из `total` журнала, если журнал есть (`loaded` или прежний журнал в `loading` и `failed`), иначе из `usage.session`:
  - Input — `input + cacheRead + cacheWrite` (Q8) и вторая строка `cache read N · write N`;
  - Output — `output` и `reasoning N`, если `reasoning` известен;
  - Cost — стоимость с «~» при любой причине неполноты, `—` и `price unknown` при неизвестной цене; при непустом `partial` вторая строка — тексты причин строки статуса;
  - Turns · steps — `<ходы> · <шаги>` и `avg N.N steps per turn` (без журнала — только шаги, без среднего; при нуле ходов среднего нет);
  - карточка, значение которой показано с «~», SHALL иметь тон `warning`; карточка со значением `—` тона НЕ SHALL получать; тон решает application, виджет получает его из данных;
- таблицу `Per turn` (`usage-turn-<index>`): ходы от нового к старому, подпись `N · “<title>”` (без `title` — `N`), столбцы Input, Output, Cost, пометка `running` у идущего хода; ход раскрывается до шагов (`usage-step-<turn>-<index>`) с подписью `step <index + 1> · <подпись шага>` (требование «Подпись шага в панели Usage») и моделью шага в подсказке; у хода с субагентами в раскрытом виде после его шагов — строка `subagents · N runs`;
- таблицу `Per model` (`usage-model-<n>`): модели журнала с подписью `<provider> / <id>`, ниже — строки `Subagents` и `Summaries`, если в журнале есть эти группы (Q9);
- строку без usage (все счётчики нулевые и причина `noUsage`) как `—` во всех числовых столбцах; строку без цены — `—` в столбце Cost.

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

#### Scenario: Неизвестная цена и ход без usage
- **WHEN** журнал содержит ход, у которого все счётчики нулевые и `partial` — `["noUsage"]`, и модель без цен
- **THEN** строка хода показывает `—` в столбцах Input, Output и Cost, строка модели — `—` в столбце Cost; `0` и `$0.00` нет

#### Scenario: Неполная стоимость сессии
- **WHEN** `total.partial` журнала — `["noUsage"]`, `total.cost` — `2.26`
- **THEN** карточка Cost показывает `~$2.26` в тоне `warning` и строку `agent sent no usage for some steps`; при неизвестной `total.cost` карточка показывает `—` без тона

#### Scenario: Агент без журнала
- **WHEN** агент объявил `usage`, не объявил `usageLedger` и прислал снимок с суммой сессии
- **THEN** панель доступна, карточки показывают сумму снимка, таблиц, `Export CSV` и `Rebuild from log` нет, показана заметка `This agent does not provide usage history.`

#### Scenario: Агент без usage
- **WHEN** агент не объявил ни `usage`, ни `usageLedger`, а панель Usage сохранена открытой в раскладке
- **THEN** переключателя, вкладки и пункта палитры Usage нет, раскладка не меняется

#### Scenario: Смена сессии в фокусе
- **WHEN** запрос журнала сессии A в полёте, и фокус переходит на сессию B
- **THEN** панель показывает данные сессии B; ответ для A применяется только к `SessionView` сессии A

### Requirement: Подпись шага в панели Usage
Подпись шага журнала SHALL строиться по транскрипту клиента (design.md change `add-desktop-usage-pane`, D4, Q6): первый `toolCallId` шага, найденный среди вызовов корневого уровня `SessionView.transcript`, подписывается по правилу строки ленты (`ToolRowFormatter`: `<label> <detail>`); остальные вызовы шага — суффикс ` +N`. Шаг без вызовов SHALL подписываться `reply`, шаг, вызовы которого не найдены в транскрипте, — `N tool calls`. Подпись НЕ SHALL браться из ответа журнала: он не несёт заголовков вызовов (D1 п. 4 change `add-usage-ledger`).

#### Scenario: Шаг с одним вызовом
- **WHEN** шаг журнала несёт `toolCallIds` `["call_1"]`, а в транскрипте вызов `call_1` вида `read` с путём `<cwd сессии>/lib/acp_transcript_panel.dart`
- **THEN** подпись — `Read lib/acp_transcript_panel.dart`, как метка и деталь строки этого вызова в ленте

#### Scenario: Шаг с несколькими вызовами
- **WHEN** шаг несёт три `toolCallIds`, первый из которых найден в транскрипте
- **THEN** подпись — подпись первого вызова и ` +2`

#### Scenario: Ответ без вызовов и вызовы вне транскрипта
- **WHEN** один шаг несёт пустой `toolCallIds`, другой — два id, которых нет в транскрипте
- **THEN** подписи — `reply` и `2 tool calls`

### Requirement: Экспорт usage в CSV
`Export CSV` SHALL сохранять журнал, показанный в панели Usage, одним файлом CSV в место, выбранное пользователем в системном диалоге сохранения (design.md change `add-desktop-usage-pane`, D5, Q2). Формат SHALL соответствовать RFC 4180: разделитель `,`, перевод строки CRLF, UTF-8 без BOM; поле с `,`, `"`, CR или LF заключается в кавычки, кавычка внутри удваивается. Первая строка — заголовок:

`kind,turn,step,title,model,input,output,cache_read,cache_write,reasoning,cost,currency,partial`

Строки — в хронологическом порядке: строка хода (`turn`), за ней строки его шагов (`step`) и строка субагентов хода (`subagents`), затем строки моделей (`model`), группы сессии (`subagents` с пустым `turn`, `summaries`) и последней — `total`. Токены SHALL записываться целыми без форматирования; стоимость — точной десятичной строкой из микроединиц (`formatUsageMoneyExact` kit); `partial` — причины через `;` в порядке `noUsage`, `noPrice`, `beforeLoad`; номер шага — с 1; неизвестное значение — пустой ячейкой, НЕ SHALL `0`. У строки без usage (все счётчики нулевые и причина `noUsage`) пусты все числовые ячейки, включая `cost` и `currency`; `partial` — `noUsage`. Значение текстовой ячейки, начинающееся с `=`, `+`, `-`, `@`, TAB или CR, SHALL получать префикс `'`.

Отказ в диалоге SHALL ничего не записывать и не показывать ошибку. Сбой записи SHALL показывать в панели заметку `Couldn't save the file.`. Журнал событий SHALL получать `usage_pane.export` с исходом и числом ходов и шагов, без пути, подписей, токенов и денег.

#### Scenario: Точные числа
- **WHEN** журнал содержит ход с `input` 184200, стоимостью `0.000041` USD и `partial` `["noUsage"]`
- **THEN** строка хода содержит `184200`, `0.000041`, `USD` и `noUsage`, а не `184.2k` и `$0.000041`

#### Scenario: Неизвестная цена
- **WHEN** у шага нет `cost`
- **THEN** ячейки `cost` и `currency` строки шага пустые

#### Scenario: Строка без usage
- **WHEN** у шага все счётчики нулевые, `partial` — `["noUsage"]`
- **THEN** ячейки `input`, `output`, `cache_read`, `cache_write`, `reasoning`, `cost` и `currency` строки шага пустые, `partial` — `noUsage`

#### Scenario: Формула в подписи хода
- **WHEN** подпись хода — `=HYPERLINK("http://x")`
- **THEN** ячейка `title` — `"'=HYPERLINK(""http://x"")"`

#### Scenario: Отказ в диалоге
- **WHEN** пользователь закрывает диалог сохранения без выбора
- **THEN** файл не записан, заметки нет, в журнале событий — `usage_pane.export` с исходом `cancelled`

### Requirement: Бюджет хода в панели Usage
Панель Usage SHALL показывать блок `Turn budget` по `SessionView.usage.budget` сессии в фокусе (C-13; design.md change `add-desktop-usage-pane`, D9, Q5). Заголовок блока — `This turn`, пока сессия `running` или `cancelling`, иначе `Last turn`. Строки — Steps, Tokens, Cost и Time для лимитов, присутствующих в `budget` (`usage-budget-steps`, `usage-budget-tokens`, `usage-budget-cost`, `usage-budget-time`), с полосой и подписью `<израсходовано> / <лимит>` (`92k / 200k`, `$0.41 / $0.50`, `3:00 / 10:00`; время — `m:ss`, от часа — `h:mm:ss`). Тон полосы — `warning` от 80 % и `danger` от 100 %; больше 100 % SHALL показываться как есть. Без израсходованной стоимости (у модели нет цен) строка Cost SHALL показывать `— / <лимит>` и `not checked: price unknown`. Подсказка строки Tokens SHALL называть правило `input + output, including subagents`.

Пока сессия `running`, у неё нет ожидающих одобрений и в `budget` есть `duration`, строка Time SHALL обновляться раз в секунду как `usedMs + (now − receivedAt)`; иначе она показывает `usedMs` последнего снимка. Таймер SHALL идти только пока панель показана и SHALL отменяться при скрытии панели. Без `budget` блока НЕ SHALL быть.

#### Scenario: Прогресс во время хода
- **WHEN** идёт ход, и последний снимок `step` несёт `budget` с `tokens {used 92000, limit 200000}`, `cost {used "0.41", limit "0.5"}`, `duration {usedMs 180000, limitMs 600000}`, `steps {used 3, limit 50}`
- **THEN** блок `This turn` показывает `92k / 200k`, `$0.41 / $0.50` (тон `warning`), `3:00 / 10:00` и `3 / 50`

#### Scenario: Время идёт между шагами
- **WHEN** снимок применён с `duration.usedMs` 180000, сессия `running`, одобрений нет, прошло 5 с
- **THEN** строка Time показывает `3:05 / 10:00`; при ожидающем одобрении — `3:00 / 10:00`

#### Scenario: Цена неизвестна
- **WHEN** `budget.cost` несёт `limit` `"0.5"` без `used`
- **THEN** строка Cost показывает `— / $0.50` и `not checked: price unknown`, не `$0.00 / $0.50`

#### Scenario: После хода
- **WHEN** ход завершился снимком `turn` с `budget`, где `cost.used` `"0.52"` при `limit` `"0.5"`
- **THEN** блок `Last turn` показывает `$0.52 / $0.50` в тоне `danger`

#### Scenario: Без лимитов
- **WHEN** снимки сессии не несут `budget`
- **THEN** блока `Turn budget` нет
