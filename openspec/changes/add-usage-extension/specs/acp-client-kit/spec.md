## ADDED Requirements

### Requirement: Usage сессии
`SessionView` SHALL содержать `usage` (`UsageView`) — usage и стоимость последнего хода и сессии и заполнение контекста по уведомлениям `_codelab/session/usage` (design.md change `add-usage-extension`, D2, D6–D9). Разбор формы SHALL жить в одном месте пакета (`UsageDecoder`); остальная модель от формы на проводе не зависит. Kit SHALL NOT суммировать ходы и оценивать окно модели сам: все значения берутся из последнего применённого снимка.

Состояния `UsageView.support`:
- `unknown` — агент не объявил `usage` и снимков не было; клиенты показывают «неизвестно», а не нули (VIEW-6);
- `awaiting` — агент объявил `usage`, снимков ещё нет;
- `reported` — применён хотя бы один снимок.

Свёртка SHALL подчиняться правилам:
- снимок применяется, только если его `seq` больше последнего применённого для этой сессии в текущем поколении соединения; равный или меньший — отбрасывается с записью DEBUG `usage.stale` (`session_id`, `seq`, `last_seq`, `connection_generation`);
- смена поколения соединения (переподключение, перезапуск агента) и `session/load` SHALL сбрасывать `usage` сессии в `awaiting` или `unknown` по объявлению нового соединения;
- каждый снимок с `turnId` заменяет `lastTurn` агрегатом `turn` (тот же `turnId` — ход идёт); снимок без `turnId` (`compaction`) `lastTurn` не меняет и меняет только `session` и `context`; новый `turnId` без разобранного `turn` — `lastTurn` пуст;
- деньги SHALL храниться в целых микроединицах (`Money.micros`) с валютой; строка `cost` разбирается без `double`; целая часть — не более 9 цифр (не более `999999999.999999`), чтобы микроединицы оставались точным целым и на web; неверная строка, большее значение или `cost` без `currency` — стоимость отсутствует (цена неизвестна), предупреждение `usage.decode_failed` с `reason: wrong_format` для неверной строки и большего значения;
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

## MODIFIED Requirements

### Requirement: Инкрементальная проекция транскрипта
`TranscriptProjector` SHALL строить `TranscriptItem` сессии инкрементально по новым `session/update`: дельты `agent_message_chunk` и `agent_thought_chunk` подряд дописываются в один элемент того же вида, любое другое обновление закрывает отрезок; `tool_call` с известным `toolCallId` обновляет существующий элемент, а не добавляет второй; статус и одобрение вызова берутся из read-модели хода ядра клиента; запрос разрешения привязывается к `ToolCallItem` по `toolCallId`, а для вызова без `tool_call` — к элементу вызова в конце хода; сорвавшийся ход добавляет `NoticeItem` вида `error` с типизированным сбоем хода (`PromptFailure`), завершённый ход без вывода агента — `NoticeItem` вида `emptyTurn`; ход, завершённый с `stopReason` `max_tokens`, `max_turn_requests` или `refusal`, — `NoticeItem` вида `turnStopped` всегда, даже при выводе агента, и вместо `emptyTurn` у хода без вывода (решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q33, D27). Заметка `turnStopped` SHALL строиться только по `stopReason` ответа на `session/prompt`: у ходов реплея `session/load` его нет, и заметки у них нет (Q36). Тексты `turnStopped`: `max_tokens` — `The model reached its token limit, so the turn ended.`; `max_turn_requests` — `The turn reached the limit of model requests.`; `refusal` — `The agent refused to continue.`. Если итог хода `max_turn_requests` несёт причину бюджета (acp-protocol-client «Причина остановки по бюджету») со значением `steps`, `tokens`, `cost`, `duration` или `deadline`, заметка `turnStopped` SHALL называть лимит: `The turn stopped: budget exceeded: <limit>.`; без причины или с незнакомой причиной SHALL оставаться текст `The turn reached the limit of model requests.` (design.md change `add-usage-extension`, D10, D21 Т6). Повторно обработанный снимок сессии SHALL быть no-op. Для любой последовательности обновлений результат инкрементальной проекции SHALL совпадать с проекцией с нуля по всем ходам сессии.

#### Scenario: Свойство на корпусе фикстур
- **WHEN** выполняется `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture`
- **THEN** для каждой фикстуры корпуса с ролью `client` на каждом шаге инкрементальная проекция равна проекции с нуля

#### Scenario: Повторная доставка tool_call
- **WHEN** агент дважды присылает `tool_call` с одним `toolCallId`
- **THEN** транскрипт содержит один `ToolCallItem` на прежней позиции с полями второго кадра

#### Scenario: Заметка о сбое несёт причину агента
- **WHEN** ход срывается ответом агента, как в фикстуре `acp/prompt-failed-provider-auth`
- **THEN** `NoticeItem` вида `error` этого хода несёт `PromptFailure.agent` с `errorClass: "auth"`, сообщением агента и `retryable: false`

#### Scenario: Ход упёрся в лимит токенов после размышлений
- **WHEN** ход содержит только `agent_thought_chunk` и завершается ответом агента с `stopReason: max_tokens`
- **THEN** транскрипт хода содержит `ThoughtItem` и один `NoticeItem` вида `turnStopped` с текстом `The model reached its token limit, so the turn ended.`; `NoticeItem` вида `emptyTurn` нет

#### Scenario: Отказ агента после текста
- **WHEN** ход содержит `agent_message_chunk` и завершается с `stopReason: refusal`
- **THEN** после `AgentTextItem` хода есть `NoticeItem` вида `turnStopped` с текстом `The agent refused to continue.`; ход `end_turn` и `cancelled` такой заметки не получает

#### Scenario: Реплей session/load без заметки исхода
- **WHEN** сессия загружена через `session/load`, и в реплее истории есть ход, который при живом выполнении завершился с `stopReason: max_tokens` (реплей ACP не передаёт `stopReason`, `03-Session Setup.md`, «Loading a Session»), а после загрузки новый ход той же сессии завершается с `stopReason: max_tokens`
- **THEN** ход реплея не получает `NoticeItem` вида `turnStopped`, а новый ход получает; исход хода клиент не хранит и не восстанавливает (решение пользователя 2026-11-09, design.md change `add-provider-setup-ui`, Q36)

#### Scenario: Лимит стоимости
- **WHEN** ход завершён `max_turn_requests` с причиной `cost`
- **THEN** в ленте заметка `turnStopped` с текстом `The turn stopped: budget exceeded: cost.`

#### Scenario: Причина неизвестна
- **WHEN** ход завершён `max_turn_requests` без причины или с причиной `energy`
- **THEN** в ленте заметка `turnStopped` с текстом `The turn reached the limit of model requests.`
