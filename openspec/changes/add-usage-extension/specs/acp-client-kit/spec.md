## ADDED Requirements

### Requirement: Usage сессии
`SessionView` SHALL содержать `usage` (`UsageView`) — usage и стоимость последнего хода и сессии и заполнение контекста по уведомлениям `_codelab/session/usage` (design.md change `add-usage-extension`, D2, D6–D9). Разбор формы SHALL жить в одном месте пакета (`UsageDecoder`); остальная модель от формы на проводе не зависит. Kit SHALL NOT суммировать ходы и оценивать окно модели сам: все значения берутся из последнего применённого снимка.

Состояния `UsageView.support`:
- `unknown` — агент не объявил `usage` и снимков не было; клиенты показывают «неизвестно», а не нули (VIEW-6);
- `awaiting` — агент объявил `usage`, снимков ещё нет;
- `reported` — применён хотя бы один снимок.

Свёртка SHALL подчиняться правилам:
- снимок применяется, только если его `seq` больше последнего применённого для этой сессии в текущем поколении соединения; равный или меньший — отбрасывается с записью DEBUG `usage.stale`;
- смена поколения соединения (переподключение, перезапуск агента) и `session/load` SHALL сбрасывать `usage` сессии в `awaiting` или `unknown` по объявлению нового соединения;
- `lastTurn` заменяется снимком с другим `turnId`; снимок без `turnId` (`compaction`) меняет только `session` и `context`;
- деньги SHALL храниться в целых микроединицах (`Money.micros`) с валютой; строка `cost` разбирается без `double`; неверная строка или `cost` без `currency` — стоимость отсутствует;
- причины `partial` переводятся в множество известных значений (`noUsage`, `noPrice`, `beforeLoad`); незнакомые строки отбрасываются;
- `context.fraction` SHALL быть `null` без `size` или при `size == 0`; `context.compactionSoon` SHALL быть `true` только при известном `compactAt` и `used ≥ 0.9 × compactAt` (design.md, D11; решение пользователя Q3 (б));
- не разобрались обязательные поля (`sessionId`, `seq`, `trigger`, `session.tokens`) — снимок отбрасывается целиком; необязательное поле неверного типа — поле отсутствует; в обоих случаях — предупреждение `usage.decode_failed` (не чаще раза на сессию и поле) без payload, исключения нет;
- снимок для сессии, которой нет в рабочем пространстве, отбрасывается с записью DEBUG.

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

### Requirement: Заметка остановки по бюджету
Если итог хода — `max_turn_requests` с причиной бюджета (acp-protocol-client «Причина остановки по бюджету»), заметка хода `turnStopped` SHALL называть лимит: `The turn stopped: budget exceeded: <limit>.` для `steps`, `tokens`, `cost`, `duration`, `deadline`. Без причины или с незнакомой причиной SHALL оставаться текст `The turn reached the limit of model requests.` (design.md change `add-usage-extension`, D10).

#### Scenario: Лимит стоимости
- **WHEN** ход завершён `max_turn_requests` с причиной `cost`
- **THEN** в ленте заметка `The turn stopped: budget exceeded: cost.`

#### Scenario: Причина неизвестна
- **WHEN** ход завершён `max_turn_requests` без причины или с причиной `energy`
- **THEN** в ленте заметка `The turn reached the limit of model requests.`
