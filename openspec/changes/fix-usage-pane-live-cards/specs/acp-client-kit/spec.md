## MODIFIED Requirements

### Requirement: Usage сессии
`SessionView` SHALL содержать `usage` (`UsageView`) — usage и стоимость последнего хода и сессии и заполнение контекста по уведомлениям `_codelab/session/usage` (design.md change `add-usage-extension`, D2, D6–D9). Разбор формы SHALL жить в одном месте пакета (`UsageDecoder`); остальная модель от формы на проводе не зависит. Kit SHALL NOT суммировать ходы и оценивать окно модели сам: все значения берутся из последнего применённого снимка.

Состояния `UsageView.support`:
- `unknown` — агент не объявил `usage` и снимков не было; клиенты показывают «неизвестно», а не нули (VIEW-6);
- `awaiting` — агент объявил `usage`, снимков ещё нет;
- `reported` — применён хотя бы один снимок.

Свёртка SHALL подчиняться правилам:
- снимок применяется, только если его `seq` больше последнего применённого для этой сессии в текущем поколении соединения; равный или меньший — отбрасывается с записью DEBUG `usage.stale` (`session_id`, `seq`, `last_seq`, `connection_generation`);
- смена поколения соединения (переподключение, перезапуск агента) и `session/load` SHALL сбрасывать `usage` сессии в `awaiting` или `unknown` по объявлению нового соединения; сброс при `session/load` SHALL происходить в начале загрузки, до отправки запроса, а не по ответу: снимок `trigger: "load"`, который агент шлёт после ответа (change `add-usage-ledger`, D8, D10), не стирается, в каком бы порядке kit ни обработал ответ и уведомление;
- снимок для сессии, загрузка которой идёт, но которой ещё нет в рабочем пространстве, SHALL ждать её регистрации: kit хранит последний по `seq` такой снимок и применяет его при регистрации сессии, а при сбое загрузки отбрасывает с записью DEBUG `usage.unknown_session`;
- `trigger` `load` SHALL разбираться как известный повод (`UsageTrigger.load`): снимок без `turnId`, меняет `session` и `context`, `lastTurn` не меняет;
- каждый снимок с `turnId` заменяет `lastTurn` агрегатом `turn` (тот же `turnId` — ход идёт); снимок без `turnId` (`compaction`) `lastTurn` не меняет и меняет только `session` и `context`; новый `turnId` без разобранного `turn` — `lastTurn` пуст;
- деньги SHALL храниться в целых микроединицах (`Money.micros`) с валютой; строка `cost` разбирается без `double`; целая часть — не более 9 цифр (не более `999999999.999999`), чтобы микроединицы оставались точным целым и на web; неверная строка, большее значение или `cost` без `currency` — стоимость отсутствует (цена неизвестна), предупреждение `usage.decode_failed` с `reason: wrong_format` для неверной строки и большего значения;
- `currency` SHALL приниматься только как код ISO 4217 вида `^[A-Z]{3}$`; иная строка — поле неверно: стоимостей снимка нет, как у `cost` без `currency`, предупреждение `usage.decode_failed` с `field: currency`, `reason: wrong_format`; токены и контекст снимка применяются (решение пользователя 2026-11-16 по ревью итерации 3, design.md, D9, D23 Т9 п. 5);
- причины `partial` переводятся в множество известных значений (`noUsage`, `noPrice`, `beforeLoad`); незнакомые строки отбрасываются;
- число ходов агрегата `turns` SHALL сохраняться в `UsageTotals.turns` (design.md change `fix-usage-pane-live-cards`, D2): целое ≥ 0 — значение; иной тип или отрицательное число — `turns` отсутствует (`null`) с предупреждением `usage.decode_failed` (`field: <агрегат>.turns`, `reason: wrong_type`), снимок применяется; без поля — `null`. Kit НЕ SHALL выводить число ходов сам и НЕ SHALL брать его из журнала;
- `context.fraction` SHALL быть `null` без `size` или при `size == 0`; `context.compactionSoon` SHALL быть `true` только при известном `compactAt` и `used ≥ 0.9 × compactAt` (design.md, D11; решение пользователя Q3 (б)) и SHALL считаться без переполнения при больших значениях (D22);
- не разобрались обязательные поля (`sessionId`, `seq`, `trigger`, `session.tokens`) — снимок отбрасывается целиком; необязательное поле неверного типа — поле отсутствует; в обоих случаях — предупреждение `usage.decode_failed` (`session_id`, `field`, `reason`, `connection_generation`; не чаще раза на сессию и поле) без payload, исключения нет;
- снимок для сессии, которой нет в рабочем пространстве, отбрасывается с записью DEBUG `usage.unknown_session` (`session_id`, `connection_generation`).

Публикация `SessionView` с новым `usage` SHALL идти тем же путём, что и другие изменения сессии (одно изменение — одна ревизия).

#### Scenario: Агент без расширения
- **WHEN** агент не объявил `usage` и не прислал `_codelab/session/usage`
- **THEN** `SessionView.usage.support` — `unknown`, `lastTurn`, `session` и `context` — `null`

#### Scenario: Два хода
- **WHEN** агент присылает снимки двух ходов (`turnId` A, затем B) с суммой сессии в каждом
- **THEN** `lastTurn` — итог хода B, `session` — сумма из последнего снимка, `support` — `reported`

#### Scenario: Дубль и опоздание
- **WHEN** приходят снимки с `seq` 3, 5, затем 4 и снова 5
- **THEN** применены только 3 и 5, `lastSeq` — 5

#### Scenario: Деньги без накопления ошибки
- **WHEN** 1 000 снимков подряд несут `session.cost`, растущую на `"0.000001"`
- **THEN** `session.cost.micros` последнего снимка равно значению из его строки точно

#### Scenario: Валюта не ISO 4217
- **WHEN** снимок несёт `session.cost` `"1.2"` и `currency` `"usd"`, `"US$"` или `"\u001b[31m"`
- **THEN** снимок применён с токенами и контекстом, `session.cost` — `null`, записано одно предупреждение `usage.decode_failed` с `field: currency` и `reason: wrong_format`; с `currency` `"EUR"` — `session.cost.micros` `1200000` и `currency` `EUR`

#### Scenario: Неверный тип поля
- **WHEN** снимок содержит `context: {"used": "many", "size": 200000}`
- **THEN** снимок применён без `context`, записано одно предупреждение `usage.decode_failed`, исключения нет

#### Scenario: Скорое сжатие
- **WHEN** снимок несёт `context: {"used": 168000, "size": 200000, "compactAt": 183616}`, затем `context: {"used": 168000, "size": 200000}`
- **THEN** `compactionSoon` сначала `true`, затем `false`

#### Scenario: Причины неполноты
- **WHEN** `session.partial` — `["beforeLoad", "future"]`
- **THEN** `session.partial` в `UsageView` — `{beforeLoad}`

#### Scenario: Переподключение
- **WHEN** после применённого снимка с `seq` 9 соединение переподключается, и новый агент присылает снимок с `seq` 1
- **THEN** снимок с `seq` 1 применён

#### Scenario: Снимок load после загрузки
- **WHEN** открытую в рабочем пространстве сессию загружают заново, агент отвечает на `session/load` и сразу присылает снимок `trigger: "load"` с суммой сессии, а kit обрабатывает уведомление раньше обновления сессии по ответу
- **THEN** после загрузки `support` — `reported`, `session` — сумма снимка, `lastTurn` — `null`; снимок не стёрт сбросом загрузки (`session_usage_test.dart`; change `add-usage-ledger`, D10)

#### Scenario: Снимок load до регистрации сессии
- **WHEN** сессию из списка (её нет среди открытых) загружают впервые, и снимок `trigger: "load"` обработан до регистрации сессии в рабочем пространстве
- **THEN** после регистрации `session` — сумма этого снимка; записи `usage.unknown_session` нет

#### Scenario: Сорвавшаяся загрузка открытой сессии
- **WHEN** у открытой сессии `usage` — `reported`, и её повторный `session/load` завершился ошибкой
- **THEN** `usage` остаётся сброшенным (`awaiting` или `unknown`) до следующего снимка; прежние числа не восстанавливаются

#### Scenario: Загрузка сорвалась
- **WHEN** снимок пришёл для загружаемой сессии, а `session/load` завершился ошибкой
- **THEN** снимок отброшен с записью DEBUG `usage.unknown_session`, состояние рабочего пространства не меняется

#### Scenario: Число ходов сессии
- **WHEN** снимок несёт `session` с `turns` 3 и `steps` 7, затем снимок с `session.turns` — строкой `"3"`
- **THEN** после первого снимка `usage.session.turns` — 3; после второго — `null`, снимок применён, записано одно предупреждение `usage.decode_failed` с `field: session.turns`; у агрегата `turn` без поля `turns` — `null`

## ADDED Requirements

### Requirement: Ожидания одобрений корня хода
`SessionView` SHALL содержать ожидания одобрений корня текущего хода (design.md change `fix-usage-pane-live-cards`, D3; имена — исполнителю, далее `approvalWaits`). Это список интервалов с `requestedAt` и необязательным `resolvedAt`, упорядоченный по `requestedAt`. Источник — одобрения последнего хода сессии в домене (`AcpSession.turns.last.approvals`), у которых известен `requestedAt`. Метки времени ставит домен `codelab_client_acp` при приходе `session/request_permission`, ответе и отмене. Kit НЕ SHALL ставить свои метки и вызывать `DateTime.now` для этого списка.

В список SHALL входить только одобрения корня: запрос, у которого `subagentRequester` разбирается как спрашивающий потомок (то же правило, что у `PendingApprovalView.subagent`), НЕ SHALL входить. Ожидающее одобрение SHALL иметь `resolvedAt`, равный `null`. Решённое одобрение (ответ пользователя, отмена хода, потеря соединения) SHALL иметь `resolvedAt` домена. Решённое одобрение без `resolvedAt` в список НЕ SHALL входить: иначе хост принял бы его за ожидающее. Список и его элементы SHALL сравниваться по значению, чтобы хост мог не пересчитывать данные на ревизиях, где ожидания не изменились. Список нужен хосту для оценки времени бюджета между снимками (требование `agent-workbench-ui` «Бюджет хода в панели Usage»). Решение о разрешении и привязка одобрения к вызову от него не зависят (требование «Одобрения привязаны к вызову»).

#### Scenario: Ожидающее и решённое одобрения корня
- **WHEN** в идущем ходе агент запросил одобрение вызова `call_1`, пользователь ответил, затем агент запросил одобрение `call_2`
- **THEN** `approvalWaits` — два интервала по порядку прихода: у первого `requestedAt` и `resolvedAt` равны меткам домена, у второго `resolvedAt` — `null`

#### Scenario: Одобрение субагента
- **WHEN** в идущем ходе ожидает только запрос с `_meta.codelab.subagent` потомка
- **THEN** `approvalWaits` пуст, а `pendingApprovals` содержит этот запрос

#### Scenario: Новый ход
- **WHEN** в прошлом ходе было решённое одобрение корня, и начался новый ход без запросов
- **THEN** `approvalWaits` пуст

#### Scenario: Ревизия без изменения ожиданий
- **WHEN** после запроса одобрения приходят фрагменты ответа агента, а одобрения не меняются
- **THEN** `approvalWaits` каждой новой ревизии `SessionView` равен прежнему по значению
