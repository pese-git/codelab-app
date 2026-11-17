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

#### Scenario: Загрузка сорвалась
- **WHEN** снимок пришёл для загружаемой сессии, а `session/load` завершился ошибкой
- **THEN** снимок отброшен с записью DEBUG `usage.unknown_session`, состояние рабочего пространства не меняется

## ADDED Requirements

### Requirement: Журнал usage сессии в клиенте
`SessionView` SHALL содержать `usageLedger` — состояние журнала usage сессии, полученного запросом `_codelab/session/usage/ledger` (design.md change `add-usage-ledger`, D6, D10). Состояние — закрытая иерархия: `unavailable` (агент не объявил `usageLedger`), `idle` (объявил, журнал не запрашивали), `loading` (с предыдущим журналом, если был), `loaded` (журнал), `failed` (причина `UsageLedgerFailure(kind, code)` с видами `agentError`, `decode`, `request` и предыдущий журнал, если был). Модель журнала — `UsageLedgerView` с `seq` (может быть `0` — снимков не было), `turns`, `turnCount` и `total` типа `UsageTotals`.

`ClientWorkspace.refreshUsageLedger(sessionId, {rebuild = false})` SHALL:
- без объявленного `usageLedger` не отправлять запрос и оставлять `unavailable`;
- держать на сессию не больше одного запроса в полёте; вызовы во время полёта сливаются в один следующий запрос, `rebuild` в слиянии побеждает;
- применять ответ, только если с момента отправки не сменились поколение соединения и поколение загрузки сессии; иначе отбрасывать с записью DEBUG `usage.ledger.stale` — в том числе ошибку, которой ядро завершило запрос при замене транспорта: состояние тогда `idle`, а не `failed`;
- при ошибке JSON-RPC переходить в `failed` с кодом ошибки и записью WARNING `usage.ledger.failed {session_id, code}`.

Переподключение и `session/load` SHALL сбрасывать `usageLedger` в `idle` или `unavailable` по объявлению соединения. Kit НЕ SHALL складывать журнал со снимками `_codelab/session/usage` и сам ничего не суммирует; решение, когда обновлять журнал, принимает хост, сравнивая `usageLedger.seq` с `usage.lastSeq`.

Разбор ответа SHALL жить в одном месте пакета (`UsageLedgerDecoder`) и SHALL использовать те же правила денег, валюты и причин, что `UsageDecoder` (требование «Usage сессии»): микроединицы без `double`, `currency` по `^[A-Z]{3}$`, незнакомые причины отбрасываются. Не разобрались `sessionId`, `seq` или `total.tokens` — ответ отбрасывается, состояние `failed` с причиной `decode`; ход или шаг без обязательных полей пропускается; необязательное поле неверного типа отсутствует; в каждом случае — WARNING `usage.ledger.decode_failed {session_id, field, reason}` (`reason`: `required` для обязательных полей, `wrong_format` для денег и валюты) не чаще раза на сессию и поле (ограничение держит `ClientWorkspace`), без payload, исключения нет. Шаг SHALL сохранять `toolCallIds`, чтобы хост подписывал шаг по транскрипту.

#### Scenario: Агент без журнала
- **WHEN** агент не объявил `usageLedger`, и хост вызывает `refreshUsageLedger`
- **THEN** запрос не отправлен, `usageLedger` — `unavailable`

#### Scenario: Журнал загружен
- **WHEN** агент объявил `usageLedger` и отвечает журналом с двумя ходами
- **THEN** `usageLedger` — `loaded`, у журнала `seq` ответа, два хода с шагами, `toolCallIds` шагов, суммы в микроединицах (фикстура `acp/usage-ledger-request`, клиентская роль)

#### Scenario: Слияние вызовов
- **WHEN** во время запроса хост вызывает `refreshUsageLedger` дважды, второй раз с `rebuild: true`
- **THEN** после ответа на первый уходит ровно один запрос с `rebuild: true`

#### Scenario: Ответ старого соединения
- **WHEN** запрос ушёл, соединение переподключилось, затем пришёл ответ
- **THEN** ответ не применён, записан DEBUG `usage.ledger.stale`, `usageLedger` — `idle`

#### Scenario: Ошибка агента
- **WHEN** агент отвечает `-32002`
- **THEN** `usageLedger` — `failed` с кодом `-32002` и предыдущим журналом, если он был
