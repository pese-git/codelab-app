## MODIFIED Requirements

### Requirement: Инкрементальная проекция транскрипта
`TranscriptProjector` SHALL строить `TranscriptItem` сессии инкрементально по новым `session/update`: дельты `agent_message_chunk` и `agent_thought_chunk` подряд дописываются в один элемент того же вида, любое другое обновление закрывает отрезок; `tool_call` с известным `toolCallId` обновляет существующий элемент, а не добавляет второй; статус и одобрение вызова берутся из read-модели хода ядра клиента; запрос разрешения привязывается к `ToolCallItem` по `toolCallId`, а для вызова без `tool_call` — к элементу вызова в конце хода; сорвавшийся ход добавляет `NoticeItem` вида `error` с типизированным сбоем хода (`PromptFailure`), завершённый ход без вывода агента — `NoticeItem` вида `emptyTurn`; ход, завершённый с `stopReason` `max_tokens`, `max_turn_requests` или `refusal`, — `NoticeItem` вида `turnStopped` всегда, даже при выводе агента, и вместо `emptyTurn` у хода без вывода (решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q33, D27); ход, завершённый с `stopReason` `end_turn` и причиной удержания ответа (acp-protocol-client «Удержанный ответ в итоге хода»), — тоже `NoticeItem` вида `turnStopped` с текстом `The answer did not pass the final checks: <reason>` (design.md change `add-final-response-guardrails`, D7). Заметка `turnStopped` SHALL строиться только по `stopReason` ответа на `session/prompt`: у ходов реплея `session/load` его нет, и заметки у них нет (Q36). Тексты `turnStopped`: `max_tokens` — `The model reached its token limit, so the turn ended.`; `max_turn_requests` — `The turn reached the limit of model requests.`; `refusal` — `The agent refused to continue.`. Если итог хода `max_turn_requests` несёт причину бюджета (acp-protocol-client «Причина остановки по бюджету») со значением `steps`, `tokens`, `cost`, `duration` или `deadline`, заметка `turnStopped` SHALL называть лимит: `The turn stopped: budget exceeded: <limit>.`; без причины или с незнакомой причиной SHALL оставаться текст `The turn reached the limit of model requests.` (design.md change `add-usage-extension`, D10, D21 Т6). Повторно обработанный снимок сессии SHALL быть no-op. Для любой последовательности обновлений результат инкрементальной проекции SHALL совпадать с проекцией с нуля по всем ходам сессии.

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
- **THEN** после `AgentTextItem` хода есть `NoticeItem` вида `turnStopped` с текстом `The agent refused to continue.`; ход `cancelled` и ход `end_turn` без причины удержания такой заметки не получают

#### Scenario: Реплей session/load без заметки исхода
- **WHEN** сессия загружена через `session/load`, и в реплее истории есть ход, который при живом выполнении завершился с `stopReason: max_tokens` (реплей ACP не передаёт `stopReason`, `03-Session Setup.md`, «Loading a Session»), а после загрузки новый ход той же сессии завершается с `stopReason: max_tokens`
- **THEN** ход реплея не получает `NoticeItem` вида `turnStopped`, а новый ход получает; исход хода клиент не хранит и не восстанавливает (решение пользователя 2026-11-09, design.md change `add-provider-setup-ui`, Q36)

#### Scenario: Лимит стоимости
- **WHEN** ход завершён `max_turn_requests` с причиной `cost`
- **THEN** в ленте заметка `turnStopped` с текстом `The turn stopped: budget exceeded: cost.`

#### Scenario: Причина неизвестна
- **WHEN** ход завершён `max_turn_requests` без причины или с причиной `energy`
- **THEN** в ленте заметка `turnStopped` с текстом `The turn reached the limit of model requests.`

#### Scenario: Удержанный ответ
- **WHEN** ход с ответом агента `All tests pass.` завершается `end_turn` с причиной удержания `revision limit reached: [unverified_success] …`
- **THEN** после `AgentTextItem` хода есть `NoticeItem` вида `turnStopped` с id `<turnId>/stopped` и текстом `The answer did not pass the final checks: revision limit reached: [unverified_success] …`; `emptyTurn` нет

#### Scenario: Удержанный ответ после session/load
- **WHEN** ход, который при живом выполнении завершился `end_turn` с причиной удержания, приходит в реплее `session/load` или после переподключения
- **THEN** ход реплея заметки `turnStopped` не получает: исход хода клиент не хранит, а реплей `stopReason` и `_meta.codelab.held` не передаёт

### Requirement: Типизированная причина заметки транскрипта
`NoticeItem` видов `emptyTurn`, `turnStopped`, `detached` и `reconnected` SHALL нести типизированную причину, по которой хост строит текст заметки на своём языке, не разбирая `text`:
- `emptyTurn` — `stopReason` хода (`null`, если его нет);
- `turnStopped` — `stopReason` хода и, для `max_turn_requests`, имя исчерпанного лимита бюджета, если оно входит в известный набор (`steps`, `tokens`, `cost`, `duration`, `deadline`); незнакомое имя SHALL давать причину без имени лимита, как и текст; для `end_turn` с причиной удержания ответа — `ResponseHeldReason` (подтип sealed `NoticeReason`) со строкой причины (design.md change `add-final-response-guardrails`, D7);
- `detached` и `reconnected` — закрытое перечисление причины: агент не умеет восстанавливать сессии; восстановить не удалось; для причины с сессией — её id.

Поле `text` и его значения SHALL не меняться: CLI и TUI по-прежнему показывают `text`. `NoticeItem` вида `error` SHALL по-прежнему нести типизированный сбой хода (`PromptFailure`). Новые поля SHALL быть аддитивными, ядро клиента SHALL оставаться web-безопасным и без зависимости от локали. Для любой последовательности обновлений инкрементальная проекция и проекция с нуля SHALL давать равные причины.

#### Scenario: Причина остановки по лимиту бюджета
- **WHEN** ход завершается с `stopReason: max_turn_requests` и `budgetExceeded: tokens`
- **THEN** `NoticeItem` вида `turnStopped` несёт причину с `stopReason` `maxTurnRequests` и лимитом `tokens`, а его `text` — `The turn stopped: budget exceeded: tokens.`

#### Scenario: Незнакомый лимит
- **WHEN** ход завершается с `stopReason: max_turn_requests` и `budgetExceeded: gpu_hours`
- **THEN** причина заметки не содержит имени лимита, а `text` — `The turn reached the limit of model requests.`

#### Scenario: Сессия не восстановлена после переподключения
- **WHEN** после переподключения сессия `s1` не загрузилась
- **THEN** `NoticeItem` вида `detached` несёт причину «восстановить не удалось» с id `s1`, а `text` совпадает с прежним

#### Scenario: CLI не меняется
- **WHEN** CLI показывает ленту хода, остановленного по `max_tokens`
- **THEN** строка заметки — `The model reached its token limit, so the turn ended.`, как до изменения

#### Scenario: Причина удержанного ответа
- **WHEN** ход завершается `end_turn` с причиной удержания `revision limit reached: [open_tasks] Tasks still in progress: #1. …`
- **THEN** `NoticeItem` вида `turnStopped` несёт `ResponseHeldReason` с этой строкой; инкрементальная проекция и проекция с нуля дают равные причины
