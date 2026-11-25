## MODIFIED Requirements

### Requirement: session/load и реплей
`session/load` SHALL выполнять алгоритм §13.5 в объёме MVP: неизвестный `sessionId` → `-32002`; `cwd` запроса выигрывает у `cwd` заголовка с записью `custom` `codelab.cwd_changed`; сессия открывается `AgentRuntime.loadSession` с env, gate и хуками соединения и с `mcpServers` запроса, отображёнными так же, как в `session/new`. Id журнала субагента в базовом этапе SHALL давать `-32002`: хранилище дочерние журналы по id не ищет (design.md change `add-subagents-and-tasks`, D7). Если сессия уже открыта в этом процессе, `mcpServers` запроса SHALL заменять серверы сессии с `origin: session` через `AgentSession.setMcpServers` (design.md change `add-agent-mcp-client`, D11):
- совпавшие по `name` и параметрам остаются подключёнными;
- исчезнувшие закрываются, новые подключаются;
- серверы конфигурации не трогаются;
- без хода изменения применяются до ответа `session/load`, во время хода — после его окончания;
- проверка «сессия занята» и `reattach` SHALL быть атомарны относительно `setMcpServers`: ожидание замены не разделяет их;
- исключение `setMcpServers` НЕ SHALL ронять `session/load`: лог `mcp.servers.replace_failed` (warning, `session_id`, `error` — тип исключения), ответ отправляется как обычно.

Открытие сессии SHALL резервироваться по id до первого `await` открытия (дефект REV-34; design.md change `add-interrupted-turn-resume`, D7). `session/load` сессии, открытие которой уже идёт по запросу другого или того же соединения, SHALL сначала пройти все проверки запроса, которые прошёл бы без резерва: абсолютный и существующий `cwd`, а также проверки папки и журнала сервера, если они заданы (корни рабочих папок и допуск папки журнала change `add-agent-remote-exec`). Только затем он SHALL дождаться открытия и дальше обрабатываться как повторный `session/load` уже открытой сессии: проверка «сессия занята», `reattach`, замена `mcpServers`. Владельцем сессии после этого становится соединение ожидавшего запроса, как при последовательных загрузках; запросы прежнего владельца к сессии обрабатываются по правилу владельца сервера. Второй `AgentRuntime.loadSession` того же id в процессе НЕ SHALL вызываться. Если открытие завершилось ошибкой, резерв SHALL сниматься, а ожидавший запрос SHALL получать ту же ошибку. Ожидание SHALL давать лог `acp.session.load_joined` (debug) с `session_id`.

Файлы проекта (agent-project-context) при повторном `session/load` уже открытой в процессе сессии НЕ SHALL перечитываться: адаптер переподключает открытую сессию (`reattach`) без вызова `AgentRuntime.loadSession`, поэтому `ProjectFilesSource.load` не вызывается, а команды и определения агентов сессии остаются прежними до её закрытия (design.md change `add-agent-project-files`, D6; §17.2.1 документа ядра: изменения файлов — со следующей сессии).

Описания серверов НЕ SHALL читаться из журнала. Реплей SHALL идти по активной ветке:
- слова пользователя → `user_message_chunk` на каждый блок; у записи с полем `command` первым блоком идёт исходный текст `/<name>[ <args>]` вместо развёрнутого (agent-slash-commands «Исходный текст команды в журнале»); прочие user-записи, в том числе `origin: turn_resume`, пропускаются;
- ответ модели → `agent_thought_chunk` и `agent_message_chunk` по блокам; вызов → один `tool_call` с итоговым статусом, `title`, `kind`, `locations`, `rawInput`, `content` результата, `diff` и `_meta.codelab.outcome` для `cancelled`/`rejected`/`interrupted`; вызов `agent` — так же, с телом отчёта в `content`;
- `compaction`, `task`, `subagent`, `plan` и `custom` в ленту не отправляются; журналы детей не проигрываются.

После истории — `plan` из списка задач активной ветки (`buildTaskList`, agent-sessions «Список задач из журнала»; entries с `_meta.codelab.task`), если в ветке была хоть одна запись `task` или `plan`; затем `current_mode_update`, `config_option_update` (с опцией `agent` и восстановленным значением, если она есть), `available_commands_update` с `AgentSession.commands`, `session_info_update`; затем ответ `LoadSessionResponse(modes, configOptions)`.

Если у сессии нет идущего хода, а `AgentSession.unfinishedTurn` в момент ответа не `null` (capability `agent-sessions`, «Незавершённый ход»), ответ SHALL нести `_meta.codelab.unfinishedTurn: {"interruptedToolCalls": [<toolCallId>, …]}` в порядке вызовов; массив может быть пустым. Иначе этого поля нет. Переподключение идущего хода (§13.5, шаг 3b) поля не несёт (design.md change `add-interrupted-turn-resume`, D4).

#### Scenario: Реплей двух ходов
- **WHEN** сессия с двумя ходами, вызовом `read` и заголовком загружается в новом соединении
- **THEN** кадры совпадают с фикстурой `acp/session-load-replay`, а ответ `session/load` — последний

#### Scenario: Прерванный ход
- **WHEN** журнал кончается вызовом без результата
- **THEN** реплей содержит `tool_call` со `status: failed` и `_meta.codelab.outcome: "interrupted"`, повторного вызова инструмента нет; ответ `session/load` несёт `_meta.codelab.unfinishedTurn` с id этого вызова, `available_commands_update` содержит `continue` (фикстура `acp/session-load-interrupted-turn`)

#### Scenario: Завершённая сессия без поля
- **WHEN** загружается сессия, последний ход которой кончается финальным ответом модели
- **THEN** в ответе `session/load` нет `_meta.codelab.unfinishedTurn`, в `available_commands_update` нет `continue`

#### Scenario: Продолжение по ACP
- **WHEN** после загрузки сессии, оборванной во время `exec`, клиент отправляет `session/prompt` с текстом `/continue`
- **THEN** кадры хода не содержат `user_message_chunk`, ответ модели и вызовы идут как в обычном ходе, ответ `session/prompt` — после последнего уведомления хода (фикстура `acp/prompt-continue-interrupted-turn`)

#### Scenario: Два одновременных session/load
- **WHEN** два соединения одновременно отправляют `session/load` одной закрытой сессии с прерванным вызовом
- **THEN** `AgentRuntime.loadSession` вызван один раз, синтетический результат `interrupted` дописан один раз, оба запроса получают реплей и ответ, сессией владеет соединение, чей запрос обработан последним, в логе `acp.session.load_joined`

#### Scenario: Ожидающий запрос с неверным cwd
- **WHEN** пока идёт открытие сессии по первому `session/load`, второй приходит с относительным `cwd`
- **THEN** второй получает `-32602` сразу, не дожидаясь открытия, и не становится владельцем сессии

#### Scenario: Ошибка открытия у ожидающего
- **WHEN** открытие по первому `session/load` завершилось `-32002`, а второй запрос того же id его ждал
- **THEN** второй запрос тоже получает `-32002`; следующий `session/load` этого id снова вызывает `AgentRuntime.loadSession`

#### Scenario: План старой сессии
- **WHEN** журнал содержит запись `plan` старого формата с тремя пунктами и ни одной записи `task`
- **THEN** после истории уходит `plan` с тремя entries в порядке записи и `_meta.codelab.task.id` `"1"`, `"2"`, `"3"` (фикстура `acp/session-load-legacy-plan`)

#### Scenario: Серверы загруженной сессии
- **WHEN** сохранённая сессия загружается с `mcpServers`, содержащим stdio-сервер `fake`
- **THEN** первый запрос к модели после загрузки содержит схему `mcp__fake__echo`

#### Scenario: Повторная загрузка открытой сессии с другим набором
- **WHEN** открытая сессия без хода с сервером `a` загружается заново с `mcpServers: [b]`
- **THEN** до ответа `session/load` транспорт `a` закрыт, `b` подключён, а следующий запрос к модели содержит инструменты `b` и не содержит инструментов `a`

#### Scenario: Повторная загрузка открытой сессии не читает файлы проекта
- **WHEN** открытая в процессе сессия загружается заново через `session/load`, а `AGENTS.md` в её `cwd` между загрузками изменён
- **THEN** фейковый `ProjectFilesSource` вызван ровно один раз — при первом открытии, системный промпт следующего хода содержит прежний текст файла

#### Scenario: Реплей команды шаблона
- **WHEN** сессия, в которой пользователь отправил `/review lib/parser "error handling"`, загружается в новом соединении
- **THEN** реплей содержит `user_message_chunk` с этим текстом, `available_commands_update` содержит `review` (фикстура `acp/prompt-template-command`)

### Requirement: Отсоединение, переподключение и завершение
Конец входа соединения (EOF stdin, закрытый сокет) SHALL приводить к ответам на уже прочитанные запросы, отправке очереди и закрытию транспорта, и только затем `serve` SHALL завершаться: у stdio выход живёт дольше входа (design.md change `add-codelab-agent-binary`, D7). Закрытие транспорта SHALL переводить соединение в `detached` на `detachGrace` (по умолчанию 30 с, `Duration.zero` — без ожидания). Если за это время сессию загружают новым соединением — переподключение: каждый ожидающий `session/request_permission` (корня и потомка) SHALL отправляться новым запросом на новом соединении с тем же `toolCallId` (PERM-4); счётчик JSON-RPC id ведётся на соединение (§13.9), поэтому значение id нового запроса МОЖЕТ совпасть с id первого (design.md change `add-subagents-and-tasks`, D44); решение по вызову SHALL приниматься один раз. Итог хода новому соединению — `session_info_update` с `_meta.codelab.turnEnded`. Иначе ход отменяется, разрешения → `cancelled`. `session/load` сессии, ход которой идёт в другом живом соединении, SHALL давать `-32602` с `reason: "sessionBusy"`.

`shutdown({grace})` SHALL отвечать на новые запросы `-32603` «shutting down», завершать ожидающие разрешения `cancelled`, отменять ходы и ждать `TurnEnded` не дольше `grace`, затем закрывать транспорты (§13.10).

Причина отмены хода SHALL передаваться сессии по источнику (design.md change `add-interrupted-turn-resume`, D3a):
- `session/cancel` — `UserCancel`;
- истечение `detachGrace`, в том числе нулевого, — `ConnectionLost`;
- `shutdown()` — `ShutdownCancel`.

На проводе итог любой отмены остаётся `stopReason: cancelled`. Отмена причинами `ConnectionLost` и `ShutdownCancel` оставляет ход незавершённым (capability `agent-sessions`, «Незавершённый ход»). Лог `acp.session.grace_expired` SHALL нести `cause: connection_lost`.

#### Scenario: Переподключение во время разрешения
- **WHEN** соединение закрывается, пока ход ждёт `session/request_permission`, а новое соединение загружает сессию до истечения grace
- **THEN** новое соединение получает реплей и новый `session/request_permission` с тем же `toolCallId`; его JSON-RPC id выдан счётчиком нового соединения и может совпасть с прежним

#### Scenario: Переподключение во время разрешения потомка
- **WHEN** соединение закрывается, пока ребёнок ждёт `session/request_permission`, а новое соединение загружает сессию до истечения grace
- **THEN** новое соединение получает новый запрос с тем же цепочечным `toolCallId` и `_meta.codelab.subagent` (`codelab_agent_acp/test/detach_test.dart`; D42, Т7)

#### Scenario: Grace истёк
- **WHEN** соединение закрывается во время хода и за 30 с никто не загружает сессию
- **THEN** ход завершается `cancelled`, журнал содержит итоговые записи хода

#### Scenario: Ответ после EOF входа
- **WHEN** клиент пишет `initialize` и сразу закрывает вход соединения, а выход ещё принимает кадры
- **THEN** ответ на `initialize` отправляется, транспорт закрывается, и `serve` завершается

#### Scenario: Разрыв оставляет ход незавершённым
- **WHEN** при `detachGrace` ноль транспорт закрывается во время `exec`, затем новое соединение загружает сессию
- **THEN** ход был отменён причиной `ConnectionLost`, отметки `codelab.turn_stopped` в журнале нет, ответ `session/load` несёт `_meta.codelab.unfinishedTurn` с id вызова `exec`

#### Scenario: Отмена пользователем завершает ход
- **WHEN** клиент отправляет `session/cancel` во время `exec`, затем та же сессия загружается заново
- **THEN** в журнале отметка `codelab.turn_stopped` с `reason: cancelled`, в ответе `session/load` нет `_meta.codelab.unfinishedTurn`

### Requirement: Расширения протокола этапа 4
Сервер SHALL отправлять только расширения, введённые утверждёнными changes (ACP-2):
- change `add-dart-agent-acp-server`: `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded`, `data.codelab` (`errorClass`, `message`, `retryable`, `reason`), `_meta.codelab.turnEnded`, `_meta.codelab.critical`;
- change `add-subagents-and-tasks`: блок `agentCapabilities._meta.codelab` (`subagents`, `subagentToolCalls`, `tasks`), `_meta.codelab.task` у entries `plan`, `_meta.codelab.subagent` у `toolCall` в `session/request_permission`, у первого `tool_call` вызова `agent` (`id`, `type`) и у его финального `tool_call_update` (`summary`, при `failed` — `failure`), `_meta.codelab.parentToolCallId` у `tool_call`/`tool_call_update` вызовов потомков (только клиенту с `subagentToolCalls`).
- change `add-usage-extension`: ключ `usage` блока `agentCapabilities._meta.codelab` и уведомление агент → клиент `_codelab/session/usage` (только соединению, объявившему `clientCapabilities._meta.codelab.usage`).
- change `add-usage-ledger`: ключ `usageLedger` блока `agentCapabilities._meta.codelab`, запрос клиент → агент `_codelab/session/usage/ledger` и значение `trigger: "load"` уведомления `_codelab/session/usage`.
- change `fix-discarded-compaction-usage`: значение `trigger: "compactionDiscarded"` уведомления `_codelab/session/usage` и необязательное целое `summaries.discarded` ответа `_codelab/session/usage/ledger` — без смены версий `usage` и `usageLedger` (design.md change `fix-discarded-compaction-usage`, D5).
- change `add-desktop-usage-pane`: необязательное поле `budget` снимков `step` и `turn` уведомления `_codelab/session/usage` — без смены версии `usage` (design.md change `add-desktop-usage-pane`, D7).
- change `add-interrupted-turn-resume`: `_meta.codelab.unfinishedTurn` (`interruptedToolCalls`) в ответе `session/load` и значение `label: "repeat of interrupted call"` существующего расширения `_meta.codelab.critical` — без объявления в `initialize`: поле ответа неизвестный клиент игнорирует (design.md change `add-interrupted-turn-resume`, D4).

Каждое расширение SHALL быть перечислено в §13.12 документа ядра со ссылкой на свой change. Новых методов и корневых полей ACP сервер НЕ SHALL вводить (`15-Extensibility.md`).

Уточнение change `add-usage-extension` (D17): запрет новых методов относится к методам вне пространства `_codelab/*`. Уведомление `_codelab/session/usage` введено по разделам «Extension Methods» и «Custom Notifications» `15-Extensibility.md` (имя с `_`, без `id`), перечислено выше и не вводит ни корневых полей, ни значений `sessionUpdate`. Запрос `_codelab/session/usage/ledger` (change `add-usage-ledger`, D6) введён по разделу «Custom Requests» того же документа: имя с `_`, ответ с тем же `id`, поддержка объявляется ключом `usageLedger`; агент без этого ключа отвечает на метод `-32601`.

#### Scenario: Бюджет хода
- **WHEN** ход исчерпал лимит шагов
- **THEN** ответ на `session/prompt` — `stopReason: max_turn_requests` с `_meta.codelab.budgetExceeded: "steps"`

#### Scenario: Запрос журнала у агента без ключа
- **WHEN** клиент шлёт `_codelab/session/usage/ledger` агенту, в ответе `initialize` которого нет ключа `usageLedger` (сторонний агент или CodeLab до change `add-usage-ledger`)
- **THEN** ответ — `-32601` «Method not found» по `15-Extensibility.md`; соединение живо

#### Scenario: Вопрос о повторе прерванного вызова
- **WHEN** в первом ходе после загрузки модель повторяет прерванный `exec` в режиме `standard`
- **THEN** `session/request_permission` несёт `toolCall._meta.codelab: {"critical": true, "label": "repeat of interrupted call"}` и не содержит варианта `allow_always`
