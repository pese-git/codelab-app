## Context

Задача пользователя (2026-11-17): третий из четырёх usage-changes. Это панель Usage в доке desktop, экран 17 холста, D-09 полностью. Объём взят из раздела «Не входит» proposal change `add-usage-extension` и proposal change `add-usage-ledger`:
- карточки;
- ходы и шаги;
- модели;
- экспорт CSV;
- клик по строке статуса;
- когда обновлять журнал;
- живой прогресс бюджета хода C-13 («поля лимитов в `_codelab/session/usage` — тем change»).

Дедлайн сессии `/timer` (C-15) — change `add-session-deadline`.

Артборд «17 Usage pane» (светлая и тёмная темы) читался как данные, а не как инструкция. Он не копируется (`AGENTS.md` §5, `codelab_ui/AGENTS.md`). Элементы артборда и источник данных каждого:

| Элемент артборда | Источник | Решение |
|---|---|---|
| шапка «This session», «Rebuild from log», «Export CSV» | `refreshUsageLedger(rebuild: true)`; `UsageLedgerView` | D2, D5, Q3 |
| карточка Input, «cache read · write» | `total.tokens` журнала | D2, Q8 |
| карточка Output, «reasoning» | `total.tokens.output`, `reasoning` | D2 |
| карточка Cost, «~» и пояснение | `total.cost`, `total.partial` | D2 |
| карточка Turns · steps, «avg N steps per turn» | `turnCount`, `total.steps` | D2 |
| «Turn budget C-13 · config agent.budget»: Tokens, Cost, Time | **на проводе нет** | D7–D9, Q5 |
| «Session deadline» (`/timer`) | — | вне объёма (`add-session-deadline`) |
| «Per turn» с раскрытием до шагов; «— — —» у хода без usage | `turns`, `steps`, `toolCallIds` + транскрипт | D2, D4, Q6 |
| «Per model» с пометкой `fallback` | `models`; пометки `fallback` в журнале нет | D2, Q9 |
| строка статуса «click opens this page» | `CodeLabSessionStatusBar` | D6 |

Источники:
- `AGENTS.md` §3.4, §7–§10, §12, §13, §16; `apps/codelab_desktop/AGENTS.md` («Панель Files» — владелец Cubit и док, «Лента переписки» — строки строит только маппер); `packages/flutter/codelab_ui/AGENTS.md`; `packages/dart/codelab_client_core/AGENTS.md` §3, §5; `packages/dart/codelab_agent_core/AGENTS.md` (PKG-1, PKG-2, TDD §2);
- `docs/protocols/acp/protocol/15-Extensibility.md` («Custom Notifications», «Advertising Custom Capabilities»);
- change `add-usage-extension`: D2 (поля и правила совместимости — «новое необязательное поле добавляется без смены версии (например, лимиты бюджета для панели)»), D4, D6, D7, D8, D10, D11, D17, D24;
- change `add-usage-ledger`: D1 (свёртка, номера ходов и шагов), D2 (цена групп), D6 (ответ журнала), D10 (клиент; «когда обновлять, решает хост»), R4, R5, R8;
- `dart-agent-and-clients/12-3-desktop-display.md`: A7 (строка статуса), A13 (док панелей, экран 17 «клик по статус-бару, переключатель Usage», шаг 6 «панель без данных не предлагается»), A15 (панель Agents — образец);
- `12-1-view-model.md` §12.1.5 (п. 3a, 4b); `agent-parity-goals.md` D-09, C-13, L-29; `delivery-roadmap.md` §4.6, §6.2;
- `agent-core/05-agent-loop.md` §5.2 (`TurnBudget`), `15-configuration.md` («`budget`»), `13-acp-adapter.md` §13.8, §13.12.

Что есть в коде (`develop` 1c033fd4, проверено):
- **Kit.** `SessionView.usage` (`UsageView`: `support`, `lastTurn`, `session`, `context`, `lastSeq`; у `UsageTotals` нет числа ходов). `SessionView.usageLedger` — `unavailable | idle | loading(previous?) | loaded(view) | failed(reason, previous?)`. `ClientWorkspace.refreshUsageLedger(id, {rebuild})` сливает вызовы и отбрасывает поздние ответы. `UsageLedgerView`: `seq`, `total`, `turnCount`, `status`, `reason`, `records`, `turns` (номер с 1, `title`, `running`, `total`, `steps` с номером с 0, `model`, `toolCallIds`, `subagents`), `models`, `subagents`, `summaries`. Форматирование — `usage_format.dart`: `formatUsageMoney`, `formatUsageTokens`, `usageInputTokens`, `usageTokensPartial`, `usageCostPartial`. Точной печати денег (микроединицы → десятичная строка) нет. `SessionView.transcript` — `TranscriptItem.toolCall` с `toolCallId` и `title`; `ToolRowFormatter.format` даёт подпись `label` и `detail`. `SessionView.pendingApprovals` есть.
- **Desktop.** `ToolPane.usage('Usage', FluentIcons.chart)` уже есть в `codelab_ui`, но не передаётся доку (`CodeLabShell._availablePanesOf`: files, plan, agents, protocol, terminal). Образец панели с данными сессии — Agents: данные (`AgentsPaneData`) собирает `ActiveSessionCubit` из `SessionView`, предикат доступности — `CodeLabShellState.agentsAvailable`, тик времени живёт в виджете панели (`WorkbenchAgentsPane`, `Timer.periodic`), палитра — `_agentsAction`. `ActiveSessionCubit` держит одну подписку на `SessionHandle.view` показываемой сессии (`_watchView`, D23 Т1 change `add-usage-extension`) и пересчитывает только `statusBar`. `CodeLabSessionStatusBar` клика не принимает. `file_selector` уже в зависимостях (`ProjectFolderPicker` в `lib/core/platform/`); сохранения файла и экспорта в app нет.
- **Агент.** `TurnBudget` (`maxSteps` = 50 по умолчанию, `maxTokens`, `maxCost` в USD, `maxDuration`) из ключей `budget.*` (`schema.dart`, `resolve.dart`). `AgentLoop._budgetExceeded` проверяет бюджет на границе шага:
  - шаги — `_step` корня;
  - токены — `input + output` своих шагов и детей (`_usage + _childUsage`), без кэша;
  - стоимость — та же сумма, только если у текущей модели есть цены;
  - время — от начала хода по часам хоста минус ожидание одобрения.
  
  Наружу уходит только `TurnEnded.budgetExceeded`. Лимиты сессии меняются «со следующего хода» (CFG-16). Живой агрегат хода в снимке `step` не включает детей до конца хода (D4 п. 3, R3 change `add-usage-extension`), поэтому клиент по снимкам не может посчитать то же, что проверяет цикл.
- **Фикстуры.** Сравнение кадров точное (`acp-golden-fixtures`, «Нормализация и сравнение кадров»): лишний ключ в `_codelab/session/usage` — расхождение. Шесть фикстур с `extensions: ["usage"]` идут с конфигурацией без `max_tokens`, `max_cost`, `max_duration`.

## Goals / Non-Goals

**Goals:**
- Показать историю расхода сессии в доке по артборду: карточки, ходы с шагами, модели. Не показывать неизвестное нулём (DSK-11, VIEW-6).
- Обновлять журнал без опроса и без второго учёта на клиенте: правило по `seq`, один владелец, защита от поздних ответов (её даёт kit).
- Экспорт CSV, который точно воспроизводит числа журнала и безопасен при открытии в табличном редакторе.
- Живой прогресс бюджета хода C-13 по тем же числам, по которым его проверяет цикл, без новых методов ACP.

**Non-Goals:** дедлайн C-15, пометка `fallback`, Timeline, CLI, настройка лимитов из app, бюджеты субагентов (proposal, «Не входит»).

## Decisions

Решения пользователя 2026-11-17 по Q1–Q10 — все вариант (а) (раздел «Решения пользователя 2026-11-17»); D-решения и дельты совпадают с ними без правок. Решения без пометки — технические, в рамках этих ответов.

### D1. Место панели — док (решение пользователя Q1 (а))

Панель — вкладка дока `ToolPane.usage` наравне с Files, Plan, Agents и Terminal. Так записано в A13 (`12-3-desktop-display.md`: таблица зон, экран 17 «клик по статус-бару, переключатель Usage», шаг 6 «бывшие вкладки инспектора стали панелями дока»). Панель показывает сессию в фокусе. Набор открытых панелей, активная панель и ширина дока сохраняются как у остальных панелей (`codelab.dock.*`).

Доступность — свой предикат панели (требование «Tool dock with closable pane tabs»): `CodeLabShellState.usageAvailable`. Правило — D10. Недоступная панель не имеет переключателя и вкладки, но остаётся в сохранённой раскладке.

Слои (как у Agents, а не как у Files: данные приходят из `SessionView`, своего порта нет):
- `codelab_ui` — организм `CodeLabUsagePane` и модели строк, только отображение (`codelab_ui/AGENTS.md`);
- `apps/codelab_desktop/lib/features/usage/application/`:
  - `UsagePaneData` — неизменяемый снимок для панели;
  - маппер `usagePaneDataOf(SessionView, {cwd})`;
  - правило обновления журнала (D3);
  - сборка CSV (D5).
  
  Без Flutter, по правилу «application не знает Flutter» терминала;
- `apps/codelab_desktop/lib/features/usage/presentation/` — слот дока `WorkbenchUsagePane`: подписка на фасад, тик таймера бюджета (D9), сигнал «панель показана» (D3);
- `lib/core/platform/` — порт сохранения файла (D5).

Данные панели собирает `ActiveSessionCubit` в уже существующей подписке `_onView`, вместе со `statusBar`. Вторая подписка на ту же сессию не нужна.

Кэш данных панели (решение итерации 1). Ревизии `SessionView` приходят на каждый фрагмент ответа, а `usage` и журнал при этом не меняются. Поэтому `ActiveSessionCubit` пересчитывает `usagePaneDataOf` только при смене входов: сессии, `cwd`, identity `usage` и `usageLedger` и ревизии транскрипта. Признак ревизии транскрипта — identity всех `ToolCallItem` ленты: подпись шага зависит от того, появился ли вызов в ленте и не сменил ли он `title` или `locations` через `tool_call_update` без новой записи (D4, «индекс на ревизию»). Автозапрос журнала из реакции на ревизию уходит микрозадачей: kit публикует `loading` в `view` синхронно, а публикация в broadcast-поток внутри доставки события запрещена. Иначе разбор журнала и индекс вызовов повторялись бы на каждый фрагмент.

*Альтернативы* — в Q1.

### D2. Состав панели и источники (решения пользователя Q8 (а), Q9 (а))

Все числа форматирует kit (`usage_format.dart`, D24 change `add-usage-extension`), app своих правил формата не держит.

1. **Шапка.** Слева «This session». Справа кнопки:
   - «Rebuild from log» (`usage-rebuild`) — только при `usageLedger` не `unavailable`, недоступна во время `loading`;
   - «Export CSV» (`usage-export`) — только при `loaded` или при `loading` и `failed` с предыдущим журналом.
   
   Под шапкой — строка состояния журнала (`usage-ledger-status`, Q3).
2. **Карточки** (`usage-card-input`, `-output`, `-cost`, `-turns`):
   - при журнале (`loaded`, или `loading` и `failed` с предыдущим) — из `total` журнала: числа совпадают с таблицами и CSV;
   - без журнала (агент без `usageLedger`, Q7) — из `usage.session` живых снимков, карточка «Turns · steps» показывает только шаги.

   Состав карточек:
   - Input — по Q8: `usageInputTokens` (`input + cacheRead + cacheWrite`, как строка статуса); вторая строка — `cache read N · write N`;
   - Output — `output`; вторая строка `reasoning N`, если `reasoning` известен;
   - Cost — `formatUsageMoney`, «~» по `usageCostPartial`, цена неизвестна — `—` и `price unknown`. Вторая строка при непустом `partial` — тексты причин строки статуса через запятую: `agent sent no usage for some steps`, `price unknown for some steps`, `before the session was loaded` (A7);
   - Turns · steps — `turnCount · total.steps`; вторая строка `avg N.N steps per turn` в целых, десятые с округлением половины вверх; при нуле ходов строки нет.

   Тон карточки (решение итерации 1). Карточка с неполной суммой (значение с «~») рисуется тоном `warning`. Решение принимает application: флаг `UsagePaneCard.approximate`, по тем же правилам, что «~» (`usageTokensPartial` для Input и Output, `usageCostPartial` для Cost). Виджет только рисует тон из данных. Карточка со значением `—` тона не получает: неизвестное не бывает «приблизительным».
3. **«Turn budget»** — D9.
4. **«Per turn»** (`usage-turn-<index>`, `usage-step-<turn>-<index>`):
   - ходы от нового к старому, как на артборде; номер хода — `index` журнала (с 1);
   - подпись — `N · “<title>”`, без `title` — `N`;
   - столбцы Input (то же правило, что карточка, Q8), Output, Cost; «~» перед числом по причинам строки (`usageTokensPartial` для токенов, `usageCostPartial` для стоимости);
   - у хода с `running` — пометка `running`;
   - строка хода раскрывается до шагов; раскрытие — UI-состояние панели по сессии, между запусками не хранится;
   - у хода с `subagents` — строка `subagents · N runs`; она видна в раскрытом ходе после его шагов.
   
   Шаг — `step <index + 1> · <подпись>` (D4); модель шага — в подсказке. «— — —» (три пустых столбца) — у строки, где все счётчики нулевые и есть `noUsage`, и у строки без цены — `—` в столбце Cost.
5. **«Per model»** (`usage-model-<n>`): модели журнала в его порядке. Подпись — `<provider> / <id>` по первому `/`; строка без usage — «— — —». Ниже, если они есть, — строки `Subagents` (`N runs`) и `Summaries` (`N`) из групп журнала: без них сумма строк не сходится с карточками (Q9). Пометки `fallback` нет: журнал её не несёт (proposal, «Не входит»; Q9).
6. **Состояния журнала:**
   - `idle` — запрос уходит сразу при показе (D3), до ответа — индикатор;
   - `loading(previous)` — прежний журнал и индикатор в шапке;
   - `failed(reason, previous)` — прежний журнал, если он есть, и заметка `Couldn't load usage history.` с «Retry» (`refreshUsageLedger()`); код ошибки — в подсказке;
   - `unavailable` — D10.

### D3. Когда обновлять журнал (решение пользователя Q4 (а))

Правило — чистая функция application `ledgerRefreshNeeded(...)`. Владелец — `ActiveSessionCubit`: он уже держит единственную подписку на `SessionHandle.view` показываемой сессии (D23 Т1 change `add-usage-extension`, `AGENTS.md` §9).

`ActiveSessionCubit` вызывает `refreshUsageLedger(id)` (без `rebuild`) только при одновременном выполнении условий:
1. панель показана: вкладка Usage активна и док виден. Сигнал даёт виджет панели — `usagePaneShown(true)` в `initState`, `usagePaneShown(false)` в `dispose`. Док монтирует только активную вкладку и строится, только когда виден, как у Agents (D49 Т9 change `add-subagents-and-tasks`);
2. сессия не занята (`status` не `running` и не `cancelling`): шаги во время хода журнал не перезапрашивают (R4 change `add-usage-ledger` — до мегабайт на большой сессии);
3. журнал `idle`, или `loaded` с `view.seq < usage.lastSeq`;
4. автоматический запрос ещё не уходил для этого значения `usage.lastSeq` **или** журнал вернулся в `idle` из другого состояния. Так `seq` журнала, который не догнал снимки, не даёт цикла запросов.

   Возврат в `idle` — это сброс журнала kit при переподключении или загрузке сессии. `lastSeq` при этом может не измениться, а без запроса панель осталась бы с индикатором до следующего хода. Поэтому возврат в `idle` открывает ровно один новый автозапрос при том же `lastSeq` (решение итерации 1).

   Учёт («для какого `lastSeq` запрос уже уходил» и прежнее состояние журнала) ведётся по сессии в фокусе. Смена сессии в фокусе его сбрасывает.

Отсюда сами собой следуют поводы:
- показ панели;
- конец хода: снимок `turn` поднимает `lastSeq`, статус становится `idle`;
- фоновое сжатие после хода (снимок `compaction`);
- загрузка сессии: kit сбрасывает журнал в `idle`, снимок `load` поднимает `lastSeq`;
- переподключение: kit сбрасывает журнал в `idle`;
- смена сессии в фокусе.

`failed` автоматически не повторяется, только «Retry» или «Rebuild». «Rebuild from log» — `refreshUsageLedger(id, rebuild: true)` в любом состоянии, кроме `unavailable`; слияние с идущим запросом делает kit.

Kit отбрасывает ответ старого соединения или старой загрузки (`usage.ledger.stale`), поэтому смена фокуса во время запроса безопасна: панель показывает `SessionView` новой сессии в фокусе.

### D4. Подписи шагов (решение пользователя Q6 (а))

Подпись шага строит маппер app по `SessionView.transcript` сессии в фокусе:
- первый `toolCallId` шага, найденный среди `TranscriptItem.toolCall` корневого уровня, — `ToolRowFormatter.format(item, cwd: session.cwd)`, подпись `<label> <detail>` (`Read lib/acp_transcript_panel.dart`, `Run fvm flutter test`), как строка ленты; артборд пишет метку строчными (`read …`), а app берёт метку ленты без изменений, чтобы одно действие не называлось двумя способами;
- ещё вызовы шага — суффикс ` +N`;
- `toolCallIds` пуст — `reply`;
- вызов не найден в транскрипте (сессия без реплея, отсоединённая сессия) — `N tool calls` по длине `toolCallIds`;
- строки агента (`title` вызова) уже очищены kit (`ToolRowFormatter._clean`); подпись обрезает виджет многоточием.

Индекс `toolCallId → item` строится один раз на ревизию `SessionView`, а не на каждую строку.

### D5. Экспорт CSV (решение пользователя Q2 (а))

- **Где строится.** Чистая функция `buildUsageCsv(UsagePaneData)` в `features/usage/application/` возвращает строку. CSV нужен только desktop, поэтому функция в kit не выносится (`AGENTS.md` §13). Точную печать денег даёт kit: `formatUsageMoneyExact(Money)` — обратная функция к разбору `cost` из `usage_parsing.dart`, чтобы правило денег жило в одном месте (D9 change `add-usage-extension`).
- **Формат** — RFC 4180: разделитель `,`, перевод строки CRLF, UTF-8 без BOM, кавычки только у полей с `,`, `"`, CR или LF, кавычка внутри удваивается. Первая строка — заголовок. Столбцы:

  `kind,turn,step,title,model,input,output,cache_read,cache_write,reasoning,cost,currency,partial`

  Строки идут в хронологическом порядке:
  - `turn` — ход;
  - `step` — шаги хода сразу за ним;
  - `subagents` — субагенты хода, если есть;
  - `model` — по модели;
  - `subagents` с пустым `turn` и `summaries` — группы сессии;
  - последняя строка — `total`.
- **Значения:**
  - токены — целые без форматирования (`184200`, не `184.2k`);
  - `cost` — `formatUsageMoneyExact` (`2.26`, `0.000041`);
  - `currency` — код;
  - `partial` — причины через `;` в порядке `noUsage;noPrice;beforeLoad`;
  - неизвестное — пустая ячейка, никогда `0` (DSK-11);
  - «немая» строка — без usage: все счётчики нулевые и причина `noUsage`, в панели «— — —». Пустые у неё все числовые ячейки, в том числе `cost` и `currency`. Ноль у такой строки — не факт, а отсутствие данных. `partial` (`noUsage`) остаётся (решение итерации 1);
  - `step` — номер шага с 1, как в панели;
  - `title` — подпись хода у строки хода и подпись шага (D4) у строки шага.
- **Формульная инъекция.** Значение, которое начинается с `=`, `+`, `-`, `@`, TAB или CR, получает префикс `'`. Так защищены `title` (слова пользователя), подписи шагов и `model` (строка агента). Числа префикса не получают: отрицательных значений в журнале нет.
- **Сохранение.** Порт `UsageCsvSaver` в `lib/core/platform/` по образцу `ProjectFolderPicker`: `getSaveLocation` из `file_selector`, затем запись файла `dart:io`. Предложенное имя — `codelab-usage-<первые 8 символов sessionId>-<yyyyMMdd-HHmm>.csv`; символы id сессии вне `[A-Za-z0-9_-]` заменяются на `_` (id приходит от агента). Отказ в диалоге — без заметки. Сбой записи — заметка панели `Couldn't save the file.`. Путь и содержимое в журнал не попадают (D13).
- **Контракт порта** (решение итерации 1). Порт не бросает исключений, а возвращает исход `saved`, `cancelled` или `failed`. При `failed` исход несёт класс ошибки — `runtimeType` пойманного исключения, без текста и пути. Так событие D13 называет причину, а путь и текст ошибки ОС, в которых может быть путь, в журнал не попадают. Запись идёт во временный файл рядом с целевым, затем `rename` на целевое имя. Сбой посреди записи не оставляет на месте выбранного файла обрезанный CSV, а прежний файл с тем же именем остаётся целым. Временный файл после сбоя удаляется.
- Экспортируется то, что видно в панели: журнал (`loaded` или `previous`). Без журнала кнопки нет (D2 п. 1). Вызов экспорта без журнала (гонка со сменой сессии или сбросом журнала) даёт `cancelled` без диалога и без события D13.

### D6. Клик по строке статуса (решение пользователя Q10 (а))

`CodeLabSessionStatusBar` получает необязательный `onTap`. С ним вся строка кликабельна: курсор-рука, фокус клавиатуры, Enter и Space. Без `onTap` строка прежняя. Колбэк передаётся, только когда панель Usage доступна (`usageAvailable`). Клик открывает панель и делает её активной (`LayoutCubit.openPane(ToolPane.usage)` — та же операция, что у пункта палитры; в узком классе док выдвигается). Повторный клик панель не закрывает: строка статуса — вход, а не переключатель (переключатель — в app bar). Подсказки сегментов (`status-bar-usage` и другие) остаются.

### D7. Бюджет на проводе: поле `budget` в `_codelab/session/usage` (решение пользователя Q5 (а))

Новое необязательное поле в параметрах уведомления версии 1, без смены версии. Это правило совместимости D2 change `add-usage-extension` («новое необязательное поле добавляется без смены версии (например, лимиты бюджета для панели — Q5)»). Объявление `usage: {"version": 1}` не меняется. Нового метода, вида `sessionUpdate` и корневого поля типов ACP нет (D17 того change).

```json
"budget":{
  "steps":{"used":3,"limit":50},
  "tokens":{"used":92000,"limit":200000},
  "cost":{"used":"0.41","limit":"0.5"},
  "duration":{"usedMs":180000,"limitMs":600000}
}
```

Правила:
- **Когда.** Поле есть только в снимках `step` и `turn` (у них есть `turnId`); в снимках `compaction`, `compactionDiscarded` (повод change `fix-discarded-compaction-usage`, D5) и `load` его нет. Условие: у хода задан хотя бы один из лимитов `budget.max_tokens`, `budget.max_cost`, `budget.max_duration`. Лимит шагов задан всегда (по умолчанию 50), поэтому одного его для поля мало. Иначе на каждом шаге каждой сессии уходило бы поле, а все шесть существующих usage-фикстур получили бы лишний ключ (точное сравнение).
- **Состав.** `steps` — всегда, когда поле есть. `tokens`, `cost`, `duration` — только заданные лимиты.
- **Числа** — те же, что проверяет цикл (`_budgetExceeded`, LOOP-12):
  - `steps.used` — завершённые шаги корня;
  - `tokens.used` — `input + output` своих шагов и детей, без кэша;
  - `cost.used` — стоимость своих шагов и детей десятичной строкой из микродолларов (D9 change `add-usage-extension`). `cost.used` отсутствует, если у текущей модели нет цен: цикл тогда лимит не проверяет;
  - `cost.limit` — `round(max_cost × 10⁶)` микродолларов той же строкой. Валюта — `currency` снимка: лимит — тоже сумма, поэтому при `budget.cost` поле `currency` есть всегда, даже без `cost.used` (правило «`currency` — если есть хоть одно `cost`», D2 того change). Без `currency` клиент отбрасывает `budget.cost` (D9);
  - невалидный `max_cost` (решение итерации 2): NaN, бесконечность, отрицательное число или сумма, не представимая целыми микродолларами (больше 2⁵³ − 1 микродолларов). Записать такой лимит строкой D9 нельзя, поэтому подполя `cost` нет, остальные подполя остаются. Если после этого не осталось ни одного необязательного лимита (`tokens`, `cost`, `duration`), поля `budget` нет: одного лимита шагов для поля мало (правило «Когда»). Адаптер при этом не бросает, снимок уходит. Проверку цикла по `cost` это не меняет: её решает ядро по своему `TurnBudget`. NaN и ±inf в `budget.max_cost` и `subagents.max_cost` ядро отклоняет уже при разборе конфигурации (ошибка `must be greater than 0`, как для `cost <= 0`): иначе сравнение с NaN молча отключало бы бюджет стоимости. Ветка адаптера остаётся защитной;
  - `duration.usedMs` — время хода без ожидания одобрения на момент снимка.
- **Момент.** Значения — на момент снимка. В снимке `step` — после `StepEnded`, то есть на границе, где цикл проверяет бюджет. В снимке `turn` — итог хода. Лимиты — хода, к которому относится снимок: смена конфигурации посреди хода применяется со следующего хода (CFG-16), поэтому поле её не отражает до следующего хода.
- **Совместимость.** Клиент v1 (`add-usage-extension`, `add-usage-ledger`) поле игнорирует: неизвестные поля обе стороны игнорируют (D2). Незнакомый ключ внутри `budget` (например, будущий `deadline` change `add-session-deadline`) клиент тоже игнорирует.

*Альтернативы* — в Q5.

### D8. Бюджет в ядре: прогресс в `StepEnded` и `TurnEnded`

Адаптер не повторяет правило бюджета: часов цикла и ожидания одобрения он не видит, а живой агрегат хода не включает детей. Поэтому прогресс считает цикл — так же, как заполнение контекста (D5 change `add-usage-extension`).
- `StepEnded` и `TurnEnded` получают необязательное поле `budget` (`BudgetProgress`; имя — исполнителю). В нём лимиты хода (`TurnBudget`) и израсходованное (`steps`, `tokens`, `cost` (`double?`; `null`, если у текущей модели нет цен), `active` (`Duration`)).
- Одна функция цикла считает и прогресс, и `_budgetExceeded`, поэтому показанное не расходится с проверкой.
- Вычисление не обращается к провайдеру, не меняет транскрипт, журнал и сам бюджет.
- Без лимитов `maxTokens`, `maxCost` и `maxDuration` поле остаётся заполненным. Решение «слать или нет» принимает адаптер (D7), ядро форму провода не знает.
- **Ветка сбоя модели** (решение итерации 2). Шаг, ответ модели которого — ошибка, всё равно отправляется в `StepEnded`, и ход завершается. Такой шаг считается завершённым: `TurnEnded.budget.steps` равно числу отправленных `StepEnded` хода. Иначе итог хода показал бы на шаг меньше, чем клиент видел в снимках `step`.

`codelab_agent_acp` проецирует поле в снимки `step` и `turn` (`UsageAccounting` / проекция `_codelab/session/usage`). Агрегаты и `seq` не меняются.

### D9. Бюджет в kit и в панели (решение пользователя Q5 (а))

Уточнено сверкой с кодом перед итерацией 3 (2026-11-18): проекция адаптера (`usage_accounting.dart`, `budgetJson`), `UsageDecoder`, `UsageFold`, `DefaultClientWorkspace`, кэш данных панели в `ActiveSessionCubit`, `WorkbenchAgentsPane`.

- **Kit.** `UsageView.budget` (`TurnBudgetView?`): подполя `steps` и `tokens` (`used`, `limit` — целые), `cost` (`Money? used`, `Money limit`), `duration` (`usedMs`, `limitMs` — целые), а также `turnId` снимка, `receivedAt` — момент применения снимка по часам рабочего пространства — и признак `ended` «итог хода»: бюджет взят из снимка с поводом `turn` (решение пользователя Q11 (а)). Каждое подполе необязательно: агент шлёт только заданные лимиты (D7), а неверное подполе отбрасывается. Имена типов подполей — исполнителю.
- **Часы.** `UsageFold` остаётся чистым и `DateTime.now` не зовёт. Момент применения передаёт вызывающий: `apply(snapshot, generation: …, receivedAt: …)`. `_SessionHandle.applyUsage` берёт его из своих часов — это `DefaultClientWorkspace.clock`, те же часы, что у времени строк Agents (D49 Т3); тесты внедряют их через `ClientWorkspace(clock: …)`. Снимок, отложенный до регистрации сессии во время `session/load` (`_pendingUsage`), получает `receivedAt` в момент применения, а не прихода. Снимков `load` с `budget` не бывает (D7), поэтому разницы на практике нет.
- **Разбор.** `UsageDecoder` разбирает `budget` по общим правилам снимка:
  - `steps`, `tokens`, `duration` — объект с обоими целыми ≥ 0 (`used` и `limit`, у `duration` — `usedMs` и `limitMs`);
  - `cost.limit` — обязательная строка денег, `cost.used` — необязательная строка денег. Строки разбираются правилом `cost` (`parseUsageMicros`: микроединицы без `double`, целая часть не длиннее 9 цифр). Отсутствующий `used` — цена неизвестна (D7). `used` или `limit` не по формату — подполя `cost` нет;
  - валюта — общая `UsageCurrency` снимка. `budget.cost` без `currency` отбрасывается с тем же предупреждением `currency` / `required_with_cost`, что и стоимость агрегата, — одно на снимок, нового вида записи нет;
  - неверное подполе — подполя нет, WARNING `usage.decode_failed` с `field: budget.<подполе>` (`budget.steps`, `budget.tokens`, `budget.cost`, `budget.duration`) и `reason: wrong_type` или `wrong_format`. `budget` не объект — поля нет, `field: budget`. Ограничение «не чаще раза на сессию и поле» (D14 change `add-usage-extension`) то же. Снимок в обоих случаях применяется;
  - незнакомые ключи внутри `budget` и внутри подполей игнорируются молча (будущий `deadline` change `add-session-deadline`);
  - если после разбора не осталось ни одного известного подполя (пустой объект, только незнакомые ключи, все подполя неверны), `budget` считается отсутствующим в снимке. Отдельного предупреждения нет, кроме предупреждений по подполям.
  
  Лимит стоимости от 10⁹ USD агент записать может (`_roundMicros` — до 2⁵³ − 1 микродолларов), а kit — нет (9 цифр целой части, D22 change `add-usage-extension`). Такой `budget.cost` клиент отбрасывает с `wrong_format`; остальные подполя остаются. Это сознательное следствие общего правила денег, а не новое правило.
- **Свёртка** (`UsageFold.apply`, после проверки `seq` и поколения):
  - снимок с `turnId` и разобранным `budget` заменяет `budget` (вместе с `turnId` и `receivedAt`); `ended` — повод снимка `turn`;
  - снимок с тем же `turnId` без `budget` его не меняет; исключение — снимок `turn` того же хода без `budget` ставит `ended` (ход закончился, числа прежние). У агента CodeLab так не бывает: `TurnEnded` цикла всегда несёт прогресс (D8);
  - снимок с новым `turnId` без `budget` его стирает (`null`);
  - снимок без `turnId` его не меняет: `compaction`, `compactionDiscarded` (decoder сводит его к `UsageTrigger.unknown`, change `fix-discarded-compaction-usage`, R7), `load` и любой незнакомый повод без `turnId`.
  
  Сравнение «тот же или новый `turnId`» идёт с `UsageFold.turnId`: пока `budget` не `null`, его `turnId` с ним совпадает. Сброс при переподключении и `session/load` — тот же `UsageFold.initial`, что у остального `usage`, поэтому `budget` становится `null` без отдельного правила. Дубль и опоздание по `seq` `budget` не трогают (снимок не применяется целиком).
- **Панель** («Turn budget», `usage-budget-<limit>`):
  - блок стоит между карточками и `Per turn` (D2 п. 3). Его источник — `usage`, а не журнал, поэтому он есть и у агента без журнала (D10, вторая строка таблицы);
  - заголовок `This turn`, пока сессия `running` или `cancelling` и `budget` не итоговый (`ended` ложен), иначе `Last turn` (решение пользователя Q11 (а)). Номера идущего хода у клиента нет: `turnId` приходит только в снимках usage. Поэтому от начала нового хода до его первого снимка `step` блок показывает `Last turn` прошлого хода с его итогом, а первый `step` нового хода переключает блок на `This turn`;
  - строки в порядке Steps, Tokens, Cost, Time — только для подполей, которые есть в `budget`; подпись `<израсходовано> / <лимит>`:
    - Steps — целые как есть: `3 / 50`;
    - Tokens — `formatUsageTokens` kit: `92.0k / 200.0k`. Подсказка строки — `input + output, including subagents` (R2);
    - Cost — `formatUsageMoney` kit: `$0.41 / $0.50`. Без `cost.used` — `— / $0.50`, подпись `not checked: price unknown`, тон нейтральный (R8);
    - Time — `m:ss`, от часа — `h:mm:ss`, секунды отбрасываются вниз: `3:00 / 10:00`. Формат времени держит маппер desktop (`features/usage/application/`). В kit функции формата длительности для usage нет, а кроме панели время бюджета никто не показывает. Новый публичный API kit ради одного потребителя не нужен (`AGENTS.md` §13);
  - тон полосы по доле `used / limit` в целых, без `double`: `used·5 ≥ limit·4` — `warning`, `used ≥ limit` — `danger`. Больше 100 % возможно: бюджет проверяется на границе шага, а `exceeded` ядра — по `≥` (`BudgetProgress.exceeded`). Подпись показывает настоящие числа, заполнение полосы ограничено 100 %. Лимит 0 (`max_cost` меньше половины микродоллара округляется адаптером в `"0"`) — полоса полная, тон `danger`, деления на ноль нет;
  - под блоком — `When a limit is hit, the turn stops at the next step boundary.`;
  - **Время между снимками.** Пока сессия `running`, у неё нет ожидающих одобрений (`pendingApprovals` пуст) и `budget` не итоговый, строка Time показывает `usedMs + (now − receivedAt)`. Отрицательная разность (часы виджета позади часов kit в тесте) считается нулём. В остальных случаях (`cancelling`, ожидание одобрения, сессия свободна, итоговый `budget`) строка показывает `usedMs` снимка. Следующий снимок поправляет значение (R3);
  - **Тик.** Таймер — в виджете `WorkbenchUsagePane`, как у Agents (D49 Т9): `Timer.periodic` раз в секунду перестраивает блок. Он идёт, только пока панель смонтирована (то есть показана), сессия `running`, одобрений нет, `budget` не итоговый и в нём есть `duration`. При смене условия и в `dispose` таймер отменяется. Решение «тикать ли» принимает application (признак в данных блока), виджет только следует ему. Часы виджета внедряются параметром `clock`, как у `WorkbenchAgentsPane`. В тестах часы kit (`receivedAt`) и часы виджета (`now`) ведёт один поддельный источник;
  - **Данные.** Блок — часть `UsagePaneData` (`budget`, `null` — блока нет). В нём заголовок, строки Steps, Tokens, Cost с готовыми подписями и тоном, исходные `usedMs`, `limitMs` и `receivedAt` для Time и признак тика. Подпись и тон Time на момент `now` считает чистая функция application, её зовёт виджет в `build`. Кэш данных панели в `ActiveSessionCubit` (D1) сейчас пересчитывается только по identity `usage`, `usageLedger` и ревизии транскрипта. Для блока ключ кэша расширяется статусом сессии и признаком «есть ожидающие одобрения»: иначе заголовок и тик застревали бы до следующего снимка;
  - нет `budget` — блока нет (агент без поля или ход без лимитов, кроме шагов, Q5);
  - показывается только сессия в фокусе.

### D10. Агент без журнала и без usage (решение пользователя Q7 (а))

| `usage.support` | `usageLedger` | Панель | Строка статуса |
|---|---|---|---|
| любое | не `unavailable` | доступна, полная | кликабельна |
| `awaiting` или `reported` | `unavailable` | доступна: карточки из `usage.session` и блок «Turn budget» при `usage.budget` (D9), без «Turns», таблиц, CSV и «Rebuild»; заметка `This agent does not provide usage history.` | кликабельна |
| `unknown` | `unavailable` | недоступна (нет переключателя, вкладки, пункта палитры) | «usage: —», некликабельна |

`usageAvailable` считается по сессии в фокусе. Без сессии в фокусе панель недоступна.

### D11. Палитра

Пункт хоста «Usage»: id `usage-pane`, `slashCommand` `/usage-pane`, описание `Go to the usage panel.`, иконка `FluentIcons.chart`. Пункт открывает панель (`openPane`), пока `usageAvailable`. Имя не `usage`: у агента CodeLab есть своя команда `/usage` (change `add-usage-ledger`, D5), а каталог показывает доступную команду хоста рядом с одноимённой командой агента (D3 `CommandCatalog`). Набор `_paletteHostCommandsWith…` для трёх необязательных пунктов (Files, Agents, Usage) собирается одним построителем списка, а не перебором сочетаний.

### D12. Пакеты, зависимости, сторож

| Пакет (ADR-0002) | Что | Исполнитель |
|---|---|---|
| `codelab_agent_core` | `BudgetProgress` в `StepEnded` и `TurnEnded` (D8) | `[agent]` |
| `codelab_agent_acp` | поле `budget` в проекции (D7) | `[protocol]` |
| `codelab_acp_testing` | фикстура `acp/prompt-usage-budget`; режим scripted-агента `withUsageBudget` (`with_usage_budget`) | `[protocol]` |
| `codelab_acp_protocol`, `codelab_client_acp` | без изменений: уведомление проходит сырыми `params` | — |
| `codelab_client_core` | `UsageView.budget`, разбор и свёртка (D9); `formatUsageMoneyExact` (D5) | `[client]` |
| `codelab_ui` | `CodeLabUsagePane` и модели строк; `onTap` у строки статуса | `[desktop]` |
| `apps/codelab_desktop` | feature `usage`, данные в `ActiveSessionCubit`, доступность, слот дока, палитра, порт сохранения | `[desktop]` |

- Направление зависимостей прежнее:
  - `codelab_agent_acp → codelab_agent_core`;
  - `codelab_client_core → codelab_client_acp → codelab_acp_protocol`;
  - `codelab_desktop → codelab_client_core, codelab_ui`;
  - `codelab_ui` не знает kit: получает готовые подписи и тон.
- Новых пакетов и внешних зависимостей нет: `file_selector` уже в `apps/codelab_desktop`. Граф в `README.md` не меняется. Allowlist ядра (PKG-2) и kit не меняются.
- Новое правило сторожа: `apps/codelab_desktop/lib/features/usage/application` без `package:flutter/` и без `dart:io` — по образцу правила терминала (`rules.dart`, «Application терминала не знает Flutter»). CSV и правило обновления остаются чистыми, а запись файла — только в порте `lib/core/platform/`. Правило добавляется в `codelab_architecture_tests/test/support/rules.dart` вместе с каталогом (задача 1.1).
- **Web-безопасность.** Правки kit и ядра — чистый Dart, `melos run web-compile` — в итерациях 2 и 3.
- **Scripted-агент** (решение итерации 2). Бюджет для приёмки app даёт отдельный режим `withUsageBudget` (`with_usage_budget`), а не правка `withUsage`. Числа `withUsage` закреплены тестами CLI и app (`usage_agent_test.dart`, PTY-e2e CLI, `usage_display_flow_test.dart`), и лишнее поле в снимках изменило бы их ожидания. Новый режим — `withUsage` плюс поле `budget` в снимках `step` и `turn`: лимиты `max_tokens` 200000, `max_cost` `0.5`, `max_duration` 600000 мс, `max_steps` 50. Тест — `codelab_acp_testing/test/usage_budget_agent_test.dart`.

### D13. Наблюдаемость

- **Desktop** (логгер `codelab_desktop.usage`):
  - debug `usage_pane.refresh {session_id, rebuild, reason}`, где `reason` — `shown | seq | manual | retry`;
  - info `usage_pane.export {outcome, turns, steps}`, где `outcome` — `saved | cancelled | failed`; при сбое — ещё `error_class`: класс исключения, пойманного портом (D5, «Контракт порта»), а если порт не привязан или сам вызов порта бросил — класс этого исключения. Экспорт без журнала (`cancelled` до порта, D5) события не пишет;
  - пути файла, подписей ходов и шагов, токенов и денег в записях нет (`AGENTS.md` §16). Запрос и ответ журнала уже пишет kit (`usage.ledger.*`).
- **Агент.** Новых событий нет: `acp.usage.sent` без изменений. Лимиты и расход бюджета в лог не пишутся: причину остановки уже несёт ответ `session/prompt` (`budgetExceeded`).
- **Kit.** `usage.decode_failed` с `field: budget` и `budget.<подполе>` (D9); без `currency` у `budget.cost` — общее `currency` / `required_with_cost`.

### D14. Безопасность и данные

- Разрешения не затрагиваются: панель только читает, «Rebuild» — запрос только для чтения (D6 change `add-usage-ledger`).
- Containment: путь CSV выбирает пользователь в системном диалоге. Путь от агента или модели в запись не попадает, поэтому рабочей папкой сессии путь не ограничивается — это экспорт пользователя, а не операция агента (`AGENTS.md` §10 касается действий агента).
- В CSV — подписи ходов (64 руны слов пользователя), подписи вызовов, модели и числа. Секретов там нет: те же данные пользователь уже видит в ленте. Защита от формульной инъекции — D5.
- Строки агента (`title`, `model`, `toolCallIds`) kit уже очищает от C0/C1 (D10 change `add-usage-ledger`). Виджет показывает их как текст, без markdown.

### D15. Итерации

PR в `develop`: итерации 1 и 2 — одним PR (решение при реализации), итерация 3 — отдельным, итерация 4 — своим. Итерации 1 и 2 независимы и готовы одновременно. Два PR на одну ветку `feature/add-desktop-usage-pane` дали бы лишний цикл ревью и CI без выигрыша. Итерация 3 зависит от обеих и идёт после их слияния. Красные тесты коммитятся до кода, и только по просьбе пользователя.
- **0 — документы.** Этот change; ответы на Q1–Q10; правка документов архитектуры (задачи 0.3–0.6).
- **1 — панель без бюджета** (`[desktop]`, `[client]`). Kit: `formatUsageMoneyExact`. `codelab_ui`: организм панели и `onTap` строки статуса. Desktop:
  - feature `usage`, данные и доступность;
  - правило обновления журнала;
  - подписи шагов;
  - CSV и порт сохранения;
  - клик по строке статуса, палитра, правило сторожа.
  
  Зависит только от уже влитого kit.
- **2 — бюджет в агенте** (`[agent]`, `[protocol]`). `BudgetProgress` ядра, поле `budget` в проекции, фикстура `acp/prompt-usage-budget` с ролью `agent`, бюджет в режиме usage scripted-агента.
- **3 — бюджет в клиенте и панели** (`[client]`, `[desktop]`). `UsageView.budget`, клиентская роль фикстуры, блок «Turn budget», интеграционный тест app.
- **4 — закрытие.** Ручная проверка, закрытие D-09 и C-13 в матрице, сверка документов с кодом.

Зависимости: 1 ← 0; 2 ← 0 (ответ на Q5); 3 ← 1, 2; 4 ← 3. Итерации 1 и 2 независимы, идут параллельно и сливаются одним PR.

## Risks / Trade-offs

- **R1. Дельты поверх неархивированных changes.** Требование «Строка статуса сессии под композером» существует пока только в дельте change `add-usage-extension`. MODIFIED этого change пересобран из её текущего текста: все строки сохранены, изменён только последний абзац (клик) и добавлен сценарий. Change архивируется после `add-usage-extension` и `add-usage-ledger`. Повод `compactionDiscarded` (D7, D9) введён change `fix-discarded-compaction-usage`, который тоже ещё не архивирован; дельты этого change упоминают повод, но его требований не меняют, поэтому порядок архивации он не задаёт. Если тот change снова изменит требование, дельту надо пересобрать (задача 0.2). Остальные дельты — ADDED, они на чужой текст не опираются.
- **R2. Токены бюджета не равны токенам хода.** Бюджет считает `input + output` своих шагов и детей без кэша, а «Input» хода — `input + cacheRead + cacheWrite` без детей до конца хода. Полоса Tokens и строка хода показывают разные числа. Это не ошибка: так устроена проверка C-13 (`15-configuration.md`, `max_tokens` — «сумма input + output за ход»). Подсказка полосы называет правило: `input + output, including subagents`.
- **R3. Время между снимками — оценка.** Таймер панели досчитывает время от момента применения снимка. Если одобрение было и закончилось между двумя снимками, оценка до следующего снимка включит время ожидания. Снимок `step` поправит значение. Цикл останавливает ход по своим часам, а не по показу.
- **R4. Журнал после каждого хода на большой сессии.** Ответ журнала до 5–8 МБ (R4 change `add-usage-ledger`), разбор идёт в UI-изоляте. Запрос уходит, только пока панель показана и сессия свободна (D3), — один на ход, без опроса. Если замер покажет рывки кадра, разбор выносится в изолят отдельной задачей kit.
- **R5. Округление.** Шаги хода в таблице и в CSV могут не сложиться в строку хода на единицы микродолларов (R5 change `add-usage-ledger`). Панель показывает числа журнала как есть.
- **R6. Подписи без транскрипта.** У сессии, транскрипт которой не проигран (отсоединённая сессия, агент без `session/load`), шаги подписываются `N tool calls` (D4). Подписи из журнала нет: это решение D1 п. 4 change `add-usage-ledger` (журнал не дублирует заголовки).
- **R7. Устаревшая таблица во время хода.** Пока ход идёт, строка хода `running` показывает журнал на момент запроса, а карточки — тоже журнал. Живые числа хода — в строке статуса и в «Turn budget». После хода журнал обновляется (D3). Альтернатива — запрос на каждый шаг (Q4 (б)).
- **R8. Лимит стоимости без цены.** У модели без цен цикл лимит стоимости не проверяет. Полоса показывает `not checked: price unknown`, а не `$0`, чтобы пользователь не считал лимит работающим.
- **R9. Клик по строке статуса и фокус.** Кликабельная строка получает фокус клавиатуры. Порядок Tab после композера меняется, это проверяет widget-тест (задача 1.6).

## Migration Plan

- Данных для миграции нет: app ничего не сохраняет, кроме раскладки дока. `usage` в `codelab.dock.open` уже допустим (`ToolPane.values.asNameMap()`).
- Новый app со старым агентом CodeLab (без `budget`) — панель без блока бюджета. Со сторонним агентом — D10.
- Старый app с новым агентом — поле `budget` игнорируется (D7).
- Откат: убрать слот `ToolPane.usage` из `_availablePanesOf` (панель пропадает, раскладка не ломается). Отдельно — перестать проецировать `budget` в адаптере.

## Решения пользователя 2026-11-17

Пользователь выбрал вариант (а) во всех вопросах Q1–Q10:
- **Q1 — (а):** вкладка дока `ToolPane.usage` (D1).
- **Q2 — (а):** одна таблица CSV со столбцом `kind`; RFC 4180, CRLF, UTF-8 без BOM, разделитель всегда `,`, префикс `'` против формул (D5).
- **Q3 — (а):** «Rebuild from log» — `refreshUsageLedger(rebuild: true)` без подтверждения, со строкой состояния журнала (D2 п. 1, D3).
- **Q4 — (а):** автообновление по событиям, пока панель показана и сессия свободна; не больше одного автоматического запроса на значение `usage.lastSeq`; после `failed` без автоповтора (D3).
- **Q5 — (а):** поле `budget` от агента только при заданных `max_tokens`, `max_cost` или `max_duration`; в панели Steps, Tokens, Cost, Time, блок `Last turn` между ходами, тик времени раз в секунду, без лимитов блока нет (D7–D9).
- **Q6 — (а):** подпись первого вызова шага и ` +N`, `reply`, `N tool calls` (D4).
- **Q7 — (а):** без `usageLedger` — карточки из живых снимков и заметка «no history»; без `usage` и журнала панели нет (D10).
- **Q8 — (а):** Input везде `input + cacheRead + cacheWrite` (D2).
- **Q9 — (а):** отступления от артборда приняты (D2).
- **Q10 — (а):** клик по строке статуса открывает и активирует панель, повторный клик не закрывает (D6).

Ниже — вопросы в том виде, в котором они предлагались, с отклонёнными вариантами.

### Q1. Где живёт панель

- **(а) Вкладка дока `ToolPane.usage`** — рекомендуется. Так записано в A13 (экран 17, «переключатель Usage»), переключатель уже есть в `ToolPane`, образец — Agents. Панель видна рядом с лентой, данные — сессии в фокусе. Последствия: ширина дока 400 px по умолчанию, поэтому таблица ходов узкая. Столбцов три (Input, Output, Cost), подпись хода переносится — как на артборде.
- (б) Отдельная страница (ветка `AppDestination`, как настройки). Шире, но уводит с рабочего места: ленту и строку статуса во время хода не видно. Требует ветки `NavigationCubit` и Esc/«Back».
- (в) Раздел панели Protocol. Смешивает диагностику протокола с расходом. Панель пропадает при закрытии Protocol.

### Q2. Формат CSV

- **(а) Одна таблица с типом строки** (`kind`: `turn`, `step`, `subagents`, `model`, `summaries`, `total`) и точными числами, RFC 4180, CRLF, UTF-8 без BOM, пустая ячейка для неизвестного, защита от формул — рекомендуется (D5). Один файл воспроизводит всё, что видно в панели, включая группы без шагов. Последствия: для сводной таблицы пользователь фильтрует по `kind`.
- (б) Только шаги, одна строка на шаг с повторёнными столбцами хода. «Плоские» данные удобны для сводных таблиц, но строки субагентов, суммаризатора и итога в файл не попадают, и сумма файла не равна карточкам.
- (в) Два файла (ходы и шаги, модели) или архив. Точнее по структуре, но два диалога сохранения или новая зависимость для архива.

Подвопросы при (а): BOM для Excel на Windows (рекомендация — без BOM: Excel 365 открывает UTF-8 через импорт; с BOM ломаются `cut` и `awk`); разделитель всегда `,`, без учёта локали (рекомендация — да).

### Q3. Что делает «Rebuild from log»

- **(а) `refreshUsageLedger(rebuild: true)`**: агент пересчитывает свёртку из журнала сессии и перезаписывает `usage.json` (D3 change `add-usage-ledger`). Под шапкой — строка состояния журнала: `Ledger: up to date · N records`, `rebuilt from journal (<причина>) · N records`, `in memory`, `not saved` — рекомендуется. Без подтверждения: файл производный, пересчёт только читает журнал.
- (б) Обычное обновление без `rebuild`. Кнопка тогда — «Refresh», а починка файла — только `/usage rebuild`.
- (в) Убрать кнопку: журнал обновляется сам (Q4). Пользователь теряет способ починить расхождение после сбоя.

### Q4. Когда обновлять журнал

- **(а) При показе панели, после каждого хода и сжатия, после загрузки и переподключения — пока панель показана и сессия свободна; вручную — «Rebuild» и «Retry»** — рекомендуется (D3). Правило — по `seq`: не больше одного автоматического запроса на значение `usage.lastSeq`. Последствия: во время хода таблица стоит на месте (R7), живые числа — в строке статуса и в «Turn budget».
- (б) То же плюс после каждого снимка `step`, не чаще раза в N секунд. Таблица живая, но на больших сессиях это мегабайты на шаг (R4 change `add-usage-ledger`).
- (в) Только при показе и вручную. Проще всего, но после хода таблица устаревает, пока панель не переоткрыть.

### Q5. Бюджет хода C-13: показ и источник лимитов

Источник:
- **(а) Необязательное поле `budget` в снимках `step` и `turn` уведомления `_codelab/session/usage` v1** — лимиты и израсходованное, как считает цикл (D7, D8) — рекомендуется. Числа совпадают с проверкой: дети, кэш, ожидание одобрения, модель без цен. Поле — только при заданном `max_tokens`, `max_cost` или `max_duration`, поэтому существующие фикстуры не меняются. Последствия: правки ядра (`StepEnded`, `TurnEnded`) и адаптера, новая фикстура, итерация 2.
- (а') То же, но поле всегда (и с одним лимитом шагов). Steps видны всегда, но правятся шесть usage-фикстур и растёт трафик каждого шага.
- (б) Только лимиты в снимке; израсходованное клиент считает сам из `lastTurn` и своего таймера. Меньше правок ядра, но числа расходятся с проверкой: детей в живом ходе нет (R3 change `add-usage-extension`), кэш входит в Input, ожидание одобрения не вычитается. Получается второй учёт на клиенте вопреки D8 того change.
- (в) Лимиты из конфигурации на стороне клиента (мост `codelab_setup`). Работает только для встроенного и локального агента, не видит флагов (`--max-steps`), слоя проекта и смены «со следующего хода». Для внешнего агента неверно.
- (г) Отдельное уведомление `_codelab/session/budget` со своим ключом объявления. Чище по смыслу, но это новый метод и ключ ради четырёх чисел, которые и так идут вместе со снимком шага.
- (д) Не показывать прогресс в этом change, оставить только заметку `budget exceeded: <limit>`. C-13 в клиенте остаётся частичным.

Показ при (а):
- строки — Tokens, Cost, Time по артборду **и Steps** (рекомендуется: `budget exceeded: steps` — самая частая остановка) или только три строки артборда;
- между ходами — блок `Last turn` с итогом последнего хода (рекомендуется) или блок скрыт;
- время между снимками — тик раз в секунду с оценкой (рекомендуется, R3) или только на границах шагов;
- без лимитов (кроме шагов) — блока нет (рекомендуется) или заметка `No turn budget configured`.

### Q6. Подписи шагов

- **(а) По транскрипту: подпись первого вызова шага по правилу строки ленты (`Read lib/acp_transcript_panel.dart`) и ` +N` за остальные; без вызовов — `reply`; вызова нет в транскрипте — `N tool calls`** — рекомендуется (D4). Совпадает с артбордом и с лентой.
- (б) Все вызовы шага через запятую с обрезкой. Полнее, но строка в доке 400 px нечитаема.
- (в) Только модель шага (`step 2 · claude-sonnet-5-5`). Не нужен транскрипт, но артборд подписывает шаг действием.

### Q7. Агент без `usageLedger`

- **(а) Таблица D10:** есть `usage` без журнала — панель с карточками из живых снимков и заметкой `This agent does not provide usage history.`; нет ни `usage`, ни журнала — панель не предлагается, строка статуса «usage: —» некликабельна — рекомендуется. Следует A13 шаг 6 («панель без данных не предлагается») и DSK-11.
- (б) Панель только при `usageLedger`; без журнала — не предлагается, даже если живые снимки есть. Проще, но сторонний агент с `usage` (будущий) теряет карточки.
- (в) Панель всегда; без данных — пустое состояние `This agent does not report usage.` Переключатель есть всегда, но это противоречит правилу «панель без данных не предлагается».

### Q8. Что значит «Input» в панели

На артборде карточка `Input 184.2k` и `cache read 121.0k · write 18.4k`, а строка хода `41.0k` совпадает со строкой статуса (`input + cacheRead + cacheWrite`).
- **(а) Везде `input + cacheRead + cacheWrite`** (`usageInputTokens`), как строка статуса и CLI (D11, D24 change `add-usage-extension`); кэш — вторая строка карточки — рекомендуется. Числа панели и строки статуса совпадают.
- (б) Карточка — только `input` без кэша, строки ходов — с кэшем. Совпадает с буквой артборда, но одно слово значит два разных числа.
- (в) Везде только `input`. Расходится со строкой статуса.

В CSV при любом ответе — четыре отдельных столбца без сложения.

### Q9. Отступления от артборда

- **(а) Принять** — рекомендуется:
  - нет пометки `fallback` у модели (нет данных; отдельный change, если нужна);
  - есть строки `Subagents` и `Summaries` под «Per model», иначе сумма моделей не равна карточкам;
  - строка состояния журнала под шапкой (Q3);
  - ходы от нового к старому (как на артборде), а в CSV — хронологически.
- (б) Не показывать `Subagents` и `Summaries` в панели (только в CSV). Ближе к артборду, но сумма строк расходится с карточкой Cost без объяснения.
- (в) Добавить пометку `fallback`: в ответ журнала нужен признак «модель отличается от основной модели хода» — правка формы `_codelab/session/usage/ledger` и свёртки ядра. Расширяет этот change.

### Q10. Клик по строке статуса

- **(а) Открывает панель и делает её активной, повторный клик не закрывает; без доступной панели строка некликабельна** — рекомендуется (D6). Строка — вход, переключатель — в app bar.
- (б) Переключатель: повторный клик закрывает панель. Совпадает с app bar, но клик по строке ради подсказки сегмента закрыл бы панель.
- (в) Кликабелен только сегмент стоимости. Меньше случайных открытий, но меньше цель клика.

## Решения пользователя 2026-11-18

Вопросы итерации 3 возникли при сверке документов с кодом 2026-11-18. Пользователь выбрал вариант (а) в обоих:
- **Q11 — (а):** признак «итог хода» `ended` в `TurnBudgetView` (снимок с поводом `turn`); `This turn` и тик — только для неитогового бюджета; до первого снимка `step` нового хода блок показывает `Last turn` прошлого хода (D9).
- **Q12 — (а):** `usage_pane_flow_test.dart` разделён по агентам. Scripted `withUsageBudget` — клик по строке статуса и блок `Last turn` (`1 / 50`, `12.8k / 200.0k`, `$0.04 / $0.50`, `0:01 / 10:00`). Dart и встроенный с `withUsage` — раскрытие хода, «Rebuild from log», CSV. `This turn` и тик — только widget-тесты задачи 3.3.

Формат токенов в блоке — функция kit `formatUsageTokens` (`92.0k / 200.0k`), как у остальной панели (D9).

Ниже — вопросы в том виде, в котором они предлагались, с отклонёнными вариантами.

### Q11. Заголовок и тик «Turn budget» в начале нового хода

Свёртка D9 оставляет `budget` прошлого хода A, пока не придёт снимок `step` нового хода B (у снимка `turn` хода A тот же `turnId`, а у хода B снимков ещё нет). По тексту D9 и спецификации, как только сессия снова `running`, блок называется `This turn` и Time тикает как `usedMs(A) + (now − receivedAt(A))`. В Time попадает всё время простоя между ходами, а Steps, Tokens и Cost показывают итог A как текущий ход. Номера хода у клиента нет: `turnId` приходит только в снимках usage, ACP его не несёт.
- **(а) Признак «итог хода» в `TurnBudgetView`** (снимок с поводом `turn`). `This turn` и тик — только при `running` или `cancelling` и `budget` не итоговом; иначе `Last turn` со значениями снимка. От начала хода B до его первого снимка `step` блок показывает `Last turn` хода A, первый `step` хода B переключает блок на `This turn`. Рекомендуется: числа всегда верны, правка — одно поле kit и условие маппера.
- (б) То же определение, но итоговый `budget` при `running` скрывается до первого снимка `step` нового хода. Блок исчезает и появляется в начале каждого хода.
- (в) Оставить как написано: в начале хода `This turn` с числами прошлого хода и заведомо неверным временем до первого шага.

### Q12. Объём интеграционного теста `usage_pane_flow_test.dart` (задача 3.5)

Задача 3.5 требует «scripted-агент с usage, журналом и бюджетом». Scripted-агент (`codelab_compatible_stdio_agent.dart`) объявляет только `usage`, `usageLedger` у него нет. Значит, в режиме `withUsageBudget` панель — «без журнала» (D10): нет раскрытия хода, «Rebuild», CSV. Dart-агент и встроенный журнал дают, но лимитов `budget.*` в их режимах e2e нет: `_ModeSettings` не пишет конфигурацию, а флага кроме `--max-steps` у бинаря нет. Кроме того, ход scripted-агента мгновенный (`step` и `turn` подряд), поэтому `This turn` во время хода на нём не увидеть.
- **(а) Разделить сценарии по вариантам агента без новой инфраструктуры.** Scripted (`withUsageBudget`, `skip: !e2e.isScripted`): клик по строке статуса открывает панель без журнала, после хода блок `Last turn` с числами режима (`1 / 50`, `12.8k / 200.0k`, `$0.04 / $0.50`, `0:01 / 10:00`). Dart и embedded (`withUsage`, `llm_scripts/with_usage.json`, настоящий журнал): раскрытие хода, «Rebuild from log», экспорт CSV через шов порта. `This turn` и тик проверяют только widget-тесты задачи 3.3. Рекомендуется: тест укладывается в итерацию 3, и каждый вариант проверяет то, что умеет.
- (б) Научить scripted-агента журналу: `usageLedger` и ответ `_codelab/session/usage/ledger` (с `rebuild`) в режиме `with_usage_budget`, плюс тест в `codelab_acp_testing`. Тогда один сценарий на scripted-варианте покрывает журнал и бюджет. Это новая работа `[protocol]`, а `This turn` всё равно не наблюдаем без задержки шага.
- (в) Бюджет для dart и embedded: `_ModeSettings` пишет `budget.*` в конфигурацию временного `CODELAB_HOME` (параметр открывателя для встроенного агента), новый сценарий модели с медленным шагом. Это полное покрытие, включая `This turn`, на настоящем агенте, но самая большая правка тестовой инфраструктуры.

## Open Questions

Нет.
