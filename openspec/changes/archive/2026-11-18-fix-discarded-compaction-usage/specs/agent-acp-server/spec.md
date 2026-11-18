## ADDED Requirements

### Requirement: Отброшенный проход сжатия в сумме сессии
На событие `CompactionDiscarded` адаптер SHALL добавлять его `usage` в сумму сессии сервера (не в ход) по тому же правилу цены, что для `ContextCompacted.usage`: `noPrice` — модель ответа без цен в каталоге сессии при ненулевых токенах (требование «Уведомление `_codelab/session/usage`» change `add-usage-ledger`; design.md change `fix-discarded-compaction-usage`, D5).

Соединениям, объявившим `usage`, адаптер SHALL отправлять снимок `_codelab/session/usage` с `trigger: "compactionDiscarded"` (решение пользователя Q4 (а)). Снимок:
- без `turnId`, `step` и `turn`;
- с `session`, включающим вызов;
- с `context`, если мосту известно заполнение: `used` — `tokensBefore` события, `size` и `compactAt` — последнего `StepEnded`;
- с `seq` по общему правилу;
- с debug-записью `acp.usage.sent`.

Снимок SHALL отправляться и при нулевом usage вызова; сумма тогда не растёт, причины `noUsage` у суммаризатора нет — как у записанного сжатия (design.md, R8). Снимок и сообщение агента `/compact` идут в любом порядке, оба SHALL предшествовать ответу на `session/prompt`. Стандартные типы ACP новых полей и значений НЕ SHALL получать. Кадров `session/update` событие НЕ SHALL давать.

В ответе `_codelab/session/usage/ledger` объект `summaries` SHALL содержать целое `discarded` — число отброшенных вызовов, только при ненулевом значении. `usageLedger.version` остаётся `1` (правило совместимости D6 change `add-usage-ledger`; решение пользователя Q2 (а)). Засев на `session/load` SHALL включать отброшенные вызовы из свёртки, и инвариант «сразу после засева `session` равен `total` ответа журнала» (требование «Полная сумма сессии после session/load» change `add-usage-ledger`) SHALL сохраняться.

#### Scenario: /compact без выигрыша в живой сумме
- **WHEN** клиент объявил `usage`, после хода с одним шагом приходит `/compact`, и проход отброшен по CMP-10 с usage суммаризатора на модели с ценами
- **THEN** приходит `_codelab/session/usage` с `trigger: "compactionDiscarded"`, `session` с токенами и стоимостью суммаризатора сверх итога хода, прежними `session.turns` и `session.steps` и `context.used`, равным `used` последнего снимка хода; снимок и `agent_message_chunk` `Nothing to compact.` — в любом порядке, затем ответ `end_turn` (фикстура `acp/compact-no-gain-usage`; `usage_bridge_test.dart`)

#### Scenario: Журнал после отброшенного прохода
- **WHEN** после этого клиент запрашивает `_codelab/session/usage/ledger`
- **THEN** `summaries.count` — 1, `summaries.discarded` — 1, а `total` по `tokens`, `cost` и `partial` совпадает с `session` последнего снимка (фикстура `acp/compact-no-gain-usage`)

#### Scenario: Сумма после session/load
- **WHEN** сессию с ходом и отброшенным проходом загружают в новом сервере, клиент объявил `usage`
- **THEN** снимок `trigger: "load"` несёт `session` с usage суммаризатора, равный `total` ответа журнала; сумма не меньше той, что была в живой сессии до перезапуска (`usage_projection_test.dart`)

#### Scenario: Клиент без объявления
- **WHEN** проход отброшен, а клиент не объявил `usage`
- **THEN** кадров `_codelab/session/usage` нет, остальные кадры `/compact` не меняются

#### Scenario: Записанное сжатие без изменений
- **WHEN** проход сжатия записан
- **THEN** снимок — `trigger: "compaction"`, как до change, снимка `compactionDiscarded` нет

## MODIFIED Requirements

### Requirement: Уведомление `_codelab/session/usage`
Сервер SHALL отправлять уведомление JSON-RPC `_codelab/session/usage` (без `id`) каждому соединению сессии, объявившему `clientCapabilities._meta.codelab.usage` (значение — объект с `version`, равным целому JSON-числу `1`; требование «initialize»), и НЕ SHALL отправлять его остальным соединениям (design.md change `add-usage-extension`, D1, D3). Расширение SHALL соблюдать `15-Extensibility.md` (D17): метод начинается с `_`, это уведомление без `id` (ответа и `-32601` нет), поддержка объявляется только в `_meta` capability-объектов, а стандартные типы ACP (`InitializeResponse`, `AgentCapabilities`, `PromptResponse`, `SessionNotification`) НЕ SHALL получать новых корневых полей и новых значений `sessionUpdate`. Поводы (`trigger`):
- `step` — после каждого `StepEnded` хода;
- `turn` — по `TurnEnded` хода, в котором был хотя бы один `StepEnded`, после последнего `session/update` хода и до ответа на `session/prompt`, при любой причине завершения, включая `cancelled` и сбой `-32603` (ACP-3, ACP-5, ACP-7); `session_info_update` с названием сессии, которое агент даёт после хода, идёт после снимка `turn` (design.md, D19 п. 5);
- `compaction` — после `ContextCompacted`;
- `compactionDiscarded` — после `CompactionDiscarded`: проход сжатия отброшен, но суммаризатор оплачен (требование «Отброшенный проход сжатия в сумме сессии»; change `fix-discarded-compaction-usage`, D5); полей `turnId`, `step` и `turn` у снимка нет;
- `load` — после ответа на `session/load` этому соединению, если в сумме сессии есть хотя бы один шаг (change `add-usage-ledger`, D8): снимок несёт `session` и, если мосту известно заполнение контекста, `context`; полей `turnId`, `step` и `turn` у него нет. То же — после повторного `session/load` уже открытой сессии (`reattach`).

Ход без шагов модели (встроенная команда, отмена до первого запроса) НЕ SHALL давать уведомлений.

Параметры SHALL иметь форму D2: `sessionId`; `seq` — целое, начиная с 1 и строго растущее на каждый снимок в пределах сессии сервера, общее для всех её соединений; `trigger`; `turnId` при `step` и `turn`; `step` (`index`, `model` в виде `<provider>/<id>`, `tokens`, `cost`, `partial`) только при `step`; агрегат `turn` при `step` и `turn`; агрегат `session` всегда; `currency: "USD"`, если в параметрах есть хоть одно `cost`; `context` с целыми `used` и `size` и целым `compactAt` (порог автосжатия; поле отсутствует, если автосжатие выключено), если ядро сообщило заполнение контекста. Агрегат SHALL содержать `tokens` (`input`, `output`, `cacheRead`, `cacheWrite`; `reasoning` — только если сообщён), `steps` (у сессии ещё `turns` — число ходов сессии в сервере, в которых был хотя бы один `StepEnded`, включая текущий), `cost` и `partial` по правилам ниже. `context` снимка `turn` SHALL совпадать с `context` последнего `StepEnded` хода (design.md, D19 п. 3–4).

Значения SHALL считаться так (D4, D6, D9):
- шаг — usage и модель `StepEnded`; ход во время хода — сумма его шагов; ход в конце — `TurnEnded.usage`; сессия — засев из свёртки журнала при загрузке (требование «Полная сумма сессии после session/load»), плюс итоги завершённых ходов этой сессии в сервере, плюс текущий ход, плюс usage суммаризатора из `ContextCompacted.usage` и `CompactionDiscarded.usage` (в агрегат хода он не входит; change `add-usage-ledger`, D4; change `fix-discarded-compaction-usage`, D5);
- стоимость — в целых микродолларах (`round(cost.total × 10⁶)` шага и итога хода, сумма ходов для сессии), на проводе — десятичная строка без хвостовых нулей с не более чем 6 знаками после точки (`"0"` для нуля); `cost` шага SHALL присутствовать всегда, когда у модели шага есть цены (`ModelRef.cost != null`), в том числе при нулевых токенах — тогда `"0"` (причина `noUsage` при этом остаётся); `cost` хода и сессии SHALL присутствовать, если цены есть хотя бы у одной модели их шагов, и отсутствовать, только если цен нет ни у одной (design.md, D6, D20);
- стоимость шага или итога хода, которая не является конечным неотрицательным числом или в микроединицах превышает `2^53 − 1`, SHALL считаться неизвестной ценой: она даёт 0 микроединиц и причину `noPrice` (у шага `cost` нет; у хода с таким итогом `TurnEnded.usage` `cost` нет: итог берётся из ядра и включает детей, поэтому невалидному итогу нельзя доверять ни целиком, ни частично), а ход SHALL продолжаться без ошибки и без исключения в проекции (защита адаптера; цены конфигурации проверяет `agent-configuration` «Цены моделей конфигурации», D20);
- `partial`: `noUsage` — у ответа модели со `stopReason`, отличным от `error`, у которого все счётчики `input`, `output`, `cacheRead` и `cacheWrite` равны нулю; шаг только с кэш-токенами — сообщённый расход, `noUsage` у него нет. В том числе у шага, прерванного отменой (`aborted`), по которому провайдер не сообщил usage. У шага с ошибкой (`error`, в том числе `overflow` проверки перед запросом) `noUsage` не ставится (design.md, D26); `noPrice` — у модели шага нет цен при ненулевых токенах, а у итога хода ещё и когда `TurnEnded.subagentUsage` имеет ненулевые токены при нулевой стоимости (эвристика: цены моделей детей адаптеру не видны); `beforeLoad` агент CodeLab НЕ SHALL ставить: после change `add-usage-ledger` сумма сессии после загрузки полная (D8); значение остаётся в протоколе v1 для других агентов, и клиент его по-прежнему понимает; у суммаризатора `noPrice` — модель ответа без цен в каталоге при ненулевых токенах; у хода и сессии — объединение причин их шагов; у шага `noUsage` и `noPrice` вместе не бывают (`noPrice` требует ненулевых токенов); причины в массиве SHALL идти в порядке `noUsage`, `noPrice`, `beforeLoad`; пустой массив не отправляется (design.md, D19 п. 2).

Уведомление НЕ SHALL нести секретов, текстов сообщений и аргументов инструментов. Каждая отправка SHALL давать debug-запись `acp.usage.sent {session_id, seq, trigger, turn_id?}` без токенов и денег; `turn_id` — при `trigger` `step` и `turn`, у `compaction`, `compactionDiscarded` и `load` его нет (design.md, D14, D20).

#### Scenario: Два шага с ценами
- **WHEN** клиент объявил `usage`, а ход делает два запроса к модели с ценами и заканчивается `end_turn`
- **THEN** кадры совпадают с фикстурой `acp/prompt-usage-steps`: после первого и второго шага — `_codelab/session/usage` с `trigger: "step"` и `seq` 1 и 2 (уже в первом `session.turns` — 1), затем `trigger: "turn"` с `seq` 3, суммой двух шагов в `turn` и `session` и `context` второго шага, затем ответ `stopReason: end_turn`

#### Scenario: Модель без цен и шаг без usage
- **WHEN** у модели сессии нет цен, а scripted-модель отвечает без usage
- **THEN** в снимках нет `cost` и `currency`; `partial` шага с токенами — `["noPrice"]`, шага без usage — `["noUsage"]`, а хода и сессии после обоих шагов — `["noUsage", "noPrice"]` (фикстура `acp/prompt-usage-unpriced`)

#### Scenario: Шаг без usage на модели с ценами
- **WHEN** у модели сессии есть цены, а scripted-модель отвечает успешно без usage
- **THEN** у снимка `step` `cost` — `"0"`, `partial` — `["noUsage"]`, `currency` — `"USD"`; у `turn` и `session` — `cost` `"0"` с `noUsage` (`usage_bridge_test.dart`; design.md, D20 п. 1, п. 9)

#### Scenario: Не конечная стоимость
- **WHEN** usage шага на модели с ценами несёт стоимость `Infinity` (или отрицательную)
- **THEN** снимок `step` уходит без `cost` с `partial: ["noPrice"]`; если невалиден итог `TurnEnded.usage`, у агрегата `turn` снимка `trigger: "turn"` нет `cost`, а `partial` содержит `noPrice`; ход завершается тем же `stopReason`, что без этой стоимости, ошибки `-32603` нет; то же при стоимости `NaN` и при стоимости больше `2^53 − 1` микроединиц (переполнение) (`usage_bridge_test.dart` — `Infinity`, `NaN`, переполнение; `usage_projection_test.dart` — отрицательная цена через ядро; design.md, D20 п. 3, п. 9)

#### Scenario: Отмена посреди инструмента
- **WHEN** клиент отменяет ход, пока `exec` ждёт `terminal/wait_for_exit`
- **THEN** снимок `trigger: "turn"` идёт после `tool_call_update` `failed` с `outcome: "cancelled"` и до ответа `stopReason: cancelled`. Снимок `step` шага, ответ модели которого получен целиком (`stopReason: toolUse` с usage), несёт этот usage без причины `noUsage` (фикстура `acp/prompt-usage-cancelled`; design.md, D19 п. 9, D26)

#### Scenario: Отмена посреди потока без usage провайдера
- **WHEN** клиент объявил `usage`, у модели сессии есть цены, а клиент отменяет ход, пока модель ещё отвечает, и провайдер не прислал usage оборванного потока (шаг `stopReason: aborted`, все счётчики usage нулевые)
- **THEN** у снимка `step` этого шага `partial` — `["noUsage"]`, `cost` — `"0"`; снимок `turn` идёт до ответа `stopReason: cancelled`, и у агрегатов `turn` и `session` `partial` содержит `noUsage` (design.md, D26)

#### Scenario: Отмена посреди потока с частичным usage провайдера
- **WHEN** шаг прерван отменой (`stopReason: aborted`), но провайдер успел сообщить usage с `input > 0`
- **THEN** у снимка `step` нет причины `noUsage`, а токены и стоимость шага берутся из сообщённого usage (design.md, D26)

#### Scenario: Ошибка модели без usage
- **WHEN** запрос к модели завершился ошибкой (`stopReason: error`) с нулевым usage
- **THEN** у снимка `step` этого шага нет причины `noUsage` (design.md, D6, D26)

#### Scenario: Клиент без объявления
- **WHEN** клиент не прислал `clientCapabilities._meta.codelab.usage`
- **THEN** кадров `_codelab/session/usage` нет, остальные кадры совпадают с существующими фикстурами хода (например, `acp/prompt-text-end-turn`)

#### Scenario: Стандартные типы без новых полей
- **WHEN** клиент объявил `usage`, и проходит ход с двумя шагами
- **THEN** ответ `initialize` отличается от фикстуры `acp/initialize-capabilities` только блоком `agentCapabilities._meta.codelab`, кадры `session/update` и ответ `session/prompt` не содержат полей вне схемы `17-Schema.md`, кроме `_meta.codelab.*`, а usage приходит только в `_codelab/session/usage`

#### Scenario: Автосжатие выключено
- **WHEN** у сессии `compaction.enabled: false`, клиент объявил `usage`
- **THEN** `context` в снимках содержит `used` и `size` без `compactAt` (фикстура `acp/prompt-usage-compaction-off`)

#### Scenario: Сессия перешла к новому соединению
- **WHEN** после хода со снимками до `seq` 3 сессию без идущего хода загружает другое соединение, объявившее `usage` (`reattach`: у сессии один владелец, веер кадров на все соединения — после MVP, SESM-15), и отправляет промпт
- **THEN** после ответа на `session/load` новое соединение получает снимок `trigger: "load"` с `seq` 4 и суммой ходов до перехода (change `add-usage-ledger`, D8); снимки нового хода получает только новое соединение, `seq` продолжает счёт сессии сервера без сброса (первый снимок хода — `seq` 5), агрегат `session` включает ходы до перехода, `partial` не содержит `beforeLoad`; прежнее соединение снимков не получает

#### Scenario: Придержанный снимок и соединение без согласия
- **WHEN** соединение, объявившее `usage`, загружает сессию, снимок `_codelab/session/usage` придержан в буфере реплея, соединение рвётся до выпуска буфера, и ту же сессию загружает (`reattach`) соединение без объявления `usage`
- **THEN** новое соединение не получает придержанный кадр `_codelab/session/usage` ни при выпуске буфера, ни позже; придержанные `session/update` реплея оно получает в прежнем порядке (`usage_bridge_test.dart`; design.md, D20 п. 8)

#### Scenario: Субагент на модели без цен
- **WHEN** в ходе вызов `agent` запустил ребёнка, `TurnEnded.subagentUsage` содержит ненулевые токены, а его стоимость равна нулю
- **THEN** у агрегатов `turn` и `session` снимка `trigger: "turn"` `partial` содержит `noPrice` (стоимость детей не оценена)

#### Scenario: Встроенная команда без модели
- **WHEN** клиент, объявивший `usage`, отправляет встроенную команду `/status`
- **THEN** кадров `_codelab/session/usage` нет: модель не вызывалась (`usage_projection_test.dart`); то же для `/usage` и `/usage rebuild` (фикстура `acp/slash-usage`; change `add-usage-ledger`, D5)

#### Scenario: Сжатие контекста
- **WHEN** после хода клиент отправляет `/compact`, и сжатие записано
- **THEN** приходит `_codelab/session/usage` с `trigger: "compaction"`, без `turnId`, `step` и `turn`, с `context.used`, меньшим, чем в последнем снимке хода (`usage_projection_test.dart`), и `size`, `compactAt` последнего `StepEnded`; относительно чанка отчёта «Compacted…» порядок не фиксирован (фикстура `acp/compact-usage-context`)

#### Scenario: Сессия после загрузки
- **WHEN** сессию с двумя ходами с ответами модели в журнале загружают через `session/load` в новом сервере, клиент объявил `usage`, затем отправляет промпт
- **THEN** после реплея и ответа на `session/load` приходит снимок `trigger: "load"` с `session.turns: 2`, суммой токенов и стоимости двух ходов журнала и без `beforeLoad`; снимки нового хода продолжают эту сумму (`session.turns: 3`) (фикстура `acp/session-load-usage-full`; change `add-usage-ledger`, D8)

#### Scenario: Загрузка сессии без шагов
- **WHEN** загружают сессию, в журнале которой нет ни одного ответа модели
- **THEN** снимка `trigger: "load"` нет (`usage_projection_test.dart`)

#### Scenario: Загрузка соединением без объявления
- **WHEN** сессию с ответами модели загружает соединение без `clientCapabilities._meta.codelab.usage`
- **THEN** кадров `_codelab/session/usage` нет, ответ `session/load` и реплей не меняются

#### Scenario: Суммаризатор в сумме сессии
- **WHEN** клиент объявил `usage`, после хода приходит `/compact`, и суммаризатор ответил с usage на модели с ценами
- **THEN** снимок `trigger: "compaction"` несёт `session` с токенами и стоимостью суммаризатора сверх итогов ходов, `session.steps` и `session.turns` не меняются (фикстура `acp/compact-usage-summary`; change `add-usage-ledger`, D4)
