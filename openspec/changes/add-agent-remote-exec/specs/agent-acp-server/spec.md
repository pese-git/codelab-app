## ADDED Requirements

### Requirement: Корни рабочих папок сервера
`AcpServerConfig` SHALL иметь необязательное поле `workspaceRoots` — непустой список значений `WorkspaceRoot {path, resolved}`, где `path` — корень, заданный оператором, нормализованный и приведённый к виду путей ядра, а `resolved` — тот же корень после раскрытия символических ссылок (design.md change `add-agent-remote-exec`, D2). `null` — проверки корней нет, поведение прежнее. При создании сервера SHALL бросаться `HostWiringException`, если:
- `workspaceRoots` задан без `localEnv`;
- `localEnv('/')` не реализует `PathResolver` (по образцу проверки `DirectoryListing`);
- список корней пуст.

Внутри корня — значит, путь равен корню или лежит под ним по сегментам (`isInside` ядра).

Если корни заданы, `session/new` и `session/load` SHALL до создания сессии и до переподключения открытого моста проверять `cwd` запроса так:
1. `cwd` не абсолютный → `-32602` (как раньше);
2. нормализованный `cwd` не лежит внутри ни одного корня ни в форме `path`, ни в форме `resolved` → `-32602` с текстом `cwd is outside the workspace roots of the agent` и `data.codelab.reason: "cwdOutsideWorkspaceRoots"`; на этом шаге файловая система НЕ SHALL трогаться;
3. `realpath` через `PathResolver` окружения `localEnv(cwd)` вернул ошибку → `-32602` `cwd does not exist: <cwd>`; нераскрытый путь при заданных корнях НЕ SHALL использоваться (fail closed);
4. раскрытый путь не каталог → `-32602` `cwd does not exist: <cwd>`;
5. раскрытый путь не лежит внутри ни одного `resolved` → тот же ответ, что на шаге 2.

`session/load` сессии, которой нет в памяти сервера, SHALL дополнительно проверять `cwd` из заголовка её журнала (agent-runtime «Допуск папки журнала при загрузке»). Заголовок проверяется лексически по шагу 2, а если каталог существует — ещё по шагу 5. Если `cwd` заголовка вне корней, ответ тот же `cwdOutsideWorkspaceRoots`, даже когда `cwd` запроса внутри корня: иначе клиент получил бы реплей сессии чужой папки.

Ответ НЕ SHALL перечислять корни. Каждый отказ по корням SHALL писать событие `acp.session.cwd_rejected` уровня warning с полями `cwd` (до 256 символов по рунам), `session_id` (у `session/load`) и `reason` (`outside_workspace_roots` или `journal_outside_workspace_roots`). Новых кодов ошибок не вводится: `reason` — значение существующего расширения `data.codelab.reason`.

#### Scenario: cwd внутри корня
- **WHEN** сервер создан с `localEnv` и корнем `/w`, а клиент вызывает `session/new` с `cwd: "/w/proj"`, который существует
- **THEN** сессия создаётся, как без корней

#### Scenario: cwd вне корней
- **WHEN** сервер создан с корнем `/w`, а клиент вызывает `session/new` с `cwd: "/etc"` или `cwd: "/w/../etc"`
- **THEN** ответ — `-32602` с `data.codelab.reason: "cwdOutsideWorkspaceRoots"`, текст не содержит `/w`, окружение `localEnv` не получало `stat` и `realpath`, сессия не создана, лог содержит `acp.session.cwd_rejected`

#### Scenario: Корень за символической ссылкой
- **WHEN** корень задан как `/tmp/w`, а его раскрытая форма — `/private/tmp/w`; клиент вызывает `session/new` с `cwd: "/tmp/w/proj"`, а затем с `cwd: "/private/tmp/w/proj"`
- **THEN** обе сессии создаются

#### Scenario: Символическая ссылка наружу
- **WHEN** `/w/link` — символическая ссылка на `/outside`, а клиент вызывает `session/new` с `cwd: "/w/link"`
- **THEN** ответ — `-32602` с `data.codelab.reason: "cwdOutsideWorkspaceRoots"`, сессия не создана

#### Scenario: Ошибка realpath при заданных корнях
- **WHEN** `PathResolver` окружения возвращает ошибку для `cwd: "/w/proj"`, а `stat` того же пути успешен
- **THEN** ответ — `-32602`, сессия не создана

#### Scenario: Заголовок журнала вне корня, запрос внутри
- **WHEN** журнал содержит сессию `s1`, созданную с `cwd: "/old"`, а клиент вызывает `session/load` с `sessionId: "s1"` и существующим `cwd: "/w/proj"` на сервере с корнем `/w`
- **THEN** ответ — `-32602` с `data.codelab.reason: "cwdOutsideWorkspaceRoots"`, реплея нет, сессия не открыта, лог содержит `acp.session.cwd_rejected` с `reason: "journal_outside_workspace_roots"`

#### Scenario: Нарушение проводки
- **WHEN** сервер создаётся с `workspaceRoots` без `localEnv`, с `localEnv`, окружение которого не реализует `PathResolver`, или с пустым списком корней
- **THEN** конструктор бросает `HostWiringException`

### Requirement: Сессия управляется соединением-владельцем
Владелец сессии — соединение, которое создало её `session/new` или последним загрузило `session/load` (design.md change `add-agent-remote-exec`, D4; дефект REV-35). Запросы `session/prompt`, `session/set_mode`, `session/set_config_option` и `_codelab/session/usage/ledger` к сессии, которая открыта в процессе, но принадлежит другому соединению (живому или отсоединённому), SHALL получать `-32002` `Session not found: <id>` с `data.codelab.reason: "sessionNotOwned"` и НЕ SHALL менять сессию. Уведомление `session/cancel` (и терпимый запрос `session/cancel`) от соединения, которое не владеет сессией, НЕ SHALL отменять её ход.

Каждый такой отказ SHALL писать событие `acp.session.not_owned` уровня warning с полями `session_id` и `method`; `method` обрезается до 64 символов по рунам.

Владелец SHALL проверяться синхронно при приёме запроса, до первого `await` обработчика. Запрос, принятый от владельца, доводится до конца, даже если за время его `await` сессию загрузило другое соединение: решение — по владельцу на момент приёма. Ответ уходит соединению, приславшему запрос. Уведомления о смене (`current_mode_update`, `config_option_update`) уходят текущему владельцу сессии.

`session/load` и `session/list` правилом не ограничиваются: загрузка передаёт владение (правила «session/load и реплей» и `sessionBusy` не меняются). Если `session/load` забирает сессию у другого соединения, сервер SHALL писать событие `acp.session.owner_changed` уровня warning с полем `session_id`.

#### Scenario: Промпт в чужую сессию
- **WHEN** соединение A по WebSocket создаёт сессию `s1`, а соединение B того же сервера присылает `session/prompt` с `sessionId: s1`
- **THEN** B получает `-32002` с `data.codelab.reason: "sessionNotOwned"`, ход в `s1` не начинается, A не получает ни `session/update`, ни `session/request_permission`

#### Scenario: Отмена из чужого соединения
- **WHEN** в сессии соединения A идёт ход, а соединение B присылает уведомление `session/cancel` с её id
- **THEN** ход продолжается и завершается своим `stopReason`, лог содержит `acp.session.not_owned` с `method: "session/cancel"`

#### Scenario: Загрузка передаёт владение
- **WHEN** соединение B загружает простаивающую сессию соединения A через `session/load`, затем A присылает `session/set_mode`
- **THEN** B получает реплей и управляет сессией, лог содержит `acp.session.owner_changed`, а A получает `-32002` с `data.codelab.reason: "sessionNotOwned"`

#### Scenario: Загрузка во время смены режима
- **WHEN** A присылает `session/set_mode`, и пока смена применяется, B загружает ту же сессию
- **THEN** A получает ответ `{}`, режим сессии — режим из запроса A, `current_mode_update` получает B; следующий запрос A к сессии получает `sessionNotOwned`

#### Scenario: Одно соединение не замечает правила
- **WHEN** клиент по stdio создаёт сессию и шлёт `session/prompt`, `session/set_mode` и `session/cancel`
- **THEN** все запросы обрабатываются, как раньше

### Requirement: Сторона исполнения сессии в журнале
После успешного `session/new` и после `session/load`, создавшего мост сессии, сервер SHALL писать событие `acp.session.execution` уровня info с полями `session_id`, `exec` и `listing` (design.md change `add-agent-remote-exec`, D10):
- `exec` — `local`, если env сессии дал `localEnv`; `client`, если файлы и команды идут через `AcpClientExecutionEnv`;
- `listing` — `local`, если `ls` и `search` идут по локальной ФС (`localEnv` или `localListing`); `none` в остальных случаях.

#### Scenario: Ветка хоста
- **WHEN** сервер создан с `localEnv`, и клиент создаёт сессию
- **THEN** лог содержит `acp.session.execution` с `session_id` этой сессии, `exec: "local"` и `listing: "local"`

#### Scenario: Ветка клиента без листинга
- **WHEN** сервер создан без `localEnv` и без `localListing`, и клиент создаёт сессию
- **THEN** лог содержит `acp.session.execution` с `exec: "client"` и `listing: "none"`

## MODIFIED Requirements

### Requirement: session/list
`session/list` SHALL отдавать страницу `AgentRuntime.listSessions` (50 элементов): `sessionId`, `cwd`, `title`, `updatedAt` и `nextCursor`, если остались элементы. `cwd` не абсолютный или неразбираемый `cursor` → `-32602`; нет совпадений — пустой `sessions` без `nextCursor` (§13.5).

Если у сервера заданы `workspaceRoots` (requirement «Корни рабочих папок сервера»), из страницы SHALL исключаться сессии, чей `cwd` лексически не лежит внутри ни одного корня (ни в форме `path`, ни в форме `resolved`). Файловая система при этом не трогается. `nextCursor` SHALL оставаться курсором хранилища, поэтому страница МОЖЕТ быть короче 50 элементов и даже пустой при непустом `nextCursor` (design.md change `add-agent-remote-exec`, D2).

#### Scenario: Фильтр по папке
- **WHEN** в хранилище сессии двух папок, а клиент запрашивает `session/list` с `cwd` одной из них
- **THEN** ответ содержит только её сессии, новые первыми

#### Scenario: Сессии вне корней не видны
- **WHEN** у сервера корень `/w`, а в хранилище есть сессии с `cwd` `/w/a` и `/old`
- **THEN** `session/list` без `cwd` возвращает только сессию `/w/a`; ни `cwd`, ни `title` сессии `/old` в ответе нет

### Requirement: session/prompt, проекция и итог хода
`session/prompt` SHALL запускать ход в фоне (§13.7): неизвестная сессия → `-32002`; сессия другого соединения → `-32002` с `data.codelab.reason: "sessionNotOwned"` (requirement «Сессия управляется соединением-владельцем»); пустой `prompt` или блок `audio` → `-32602`; идущий ход → `-32602` с `data.codelab.reason: "turnActive"` и логом `acp.prompt.rejected`. Контент — по §13.4 (`resource` с `text` — текстовый блок с путём, `resource` с `blob` и `resource_link` — текстовые пометки).

События ядра SHALL проецироваться по таблице §13.7 исчерпывающим `switch` без `default` (ACP-6). Статусы вызова: `tool_call` уходит со `status: pending`, `in_progress` — из хука `markInProgress` после проверки разрешений, итог — `completed` или `failed`; `cancelled` и `rejected` — `failed` с `_meta.codelab.outcome` (ACP-1).

Итог хода SHALL отображаться по §13.8: `completed` → `end_turn`; бюджет → `max_turn_requests` с `_meta.codelab.budgetExceeded`; `maxTokens` → `max_tokens`; `refused` → `refusal`; `cancelled` → `cancelled`; `failed` → JSON-RPC `-32603` с `data.codelab` (`errorClass`, `message`, `retryable`). Сбой хода НЕ SHALL отображаться в `end_turn` (ACP-7).

#### Scenario: Каждое событие спроецировано
- **WHEN** тест перечисляет все подтипы `AgentEvent`
- **THEN** для каждого есть строка проекции или пометка «не передаётся»

#### Scenario: Ошибка провайдера
- **WHEN** провайдер отвечает ошибкой аутентификации
- **THEN** ответ на `session/prompt` — `-32603` с `data.codelab.errorClass: "auth"`, как в фикстуре `acp/prompt-failed-provider-auth`

#### Scenario: Отклонённый вызов
- **WHEN** пользователь отклоняет `edit`
- **THEN** `tool_call_update` уходит со `status: failed` и `_meta.codelab.outcome: "rejected"`, ход продолжается

### Requirement: session/cancel
`session/cancel` от соединения-владельца сессии SHALL отменять токен хода; ожидающие `session/request_permission` этой сессии завершаются `cancelled` (отказ), `fs/*` — ошибкой `aborted`, `terminal/wait_for_exit` — `terminal/kill`, `terminal/output`, `terminal/release`. Ответ на `session/prompt` SHALL быть `stopReason: cancelled`, даже если отмена вызвала ошибки провайдера или инструментов (ACP-5). Отмена без хода SHALL логироваться `acp.cancel.no_turn` и ничего не отправлять. `session/cancel` от соединения, которое не владеет сессией, НЕ SHALL отменять ход и SHALL логироваться `acp.session.not_owned` (requirement «Сессия управляется соединением-владельцем»).

#### Scenario: Отмена посреди команды
- **WHEN** клиент отменяет ход, пока `exec` ждёт `terminal/wait_for_exit`
- **THEN** агент отправляет `terminal/kill`, `terminal/output`, `terminal/release`, затем `tool_call_update` `failed` с `outcome: "cancelled"` и ответ `stopReason: cancelled`

#### Scenario: Отмена /mode после применения
- **WHEN** сессия в режиме `standard`, приходит `session/prompt` с `/mode plan`, и `session/cancel` приходит после того, как запись `mode_change` дописана
- **THEN** кадры идут в порядке: `current_mode_update` с `plan`, `config_option_update`, `agent_message_chunk` с `Mode: plan.`, затем ответ на `session/prompt` со `stopReason: cancelled` (ACP-5, `05-Prompt Turn.md` «Cancellation»: уведомления — до ответа); после ответа кадров этого хода нет; режим сессии — `plan` (design.md change `add-agent-builtin-slash-commands`, D14)

#### Scenario: Отмена /mode до применения
- **WHEN** `session/cancel` для хода `/mode plan` приходит до применения смены
- **THEN** ни `current_mode_update`, ни `config_option_update`, ни `agent_message_chunk` нет, ответ — `stopReason: cancelled`, режим — `standard`

### Requirement: Режимы и опции сессии
`configOptions` SHALL идти в порядке `mode`, `model`, `effort`, `agent` (§13.6): `mode` — пять режимов `ModeId`; `model` — модели каталога ядра в формате `provider/model`; `effort` (`low`, `medium`, `high`, категория `thought_level`) — только если у текущей модели `supportsReasoning` (ACP-10); `agent` — только если у сессии есть хотя бы одно определение агента: вариант `default` (имя `Default`), затем `AgentSession.agents` по имени с `description` определения, `currentValue` — `AgentSession.agent`, без поля `category` (зарезервированные категории ACP — только `mode`, `model`, `thought_level`; design.md change `add-agent-project-files`, D12). Устаревшие синонимы режимов (`architect`, `debug`, `acceptEdits`, `code`) SHALL приниматься на входе и не отправляться наружу.

`session/set_config_option` SHALL: неизвестная сессия → `-32002`; сессия другого соединения → `-32002` с `data.codelab.reason: "sessionNotOwned"` (requirement «Сессия управляется соединением-владельцем»); неизвестный `configId` или значение вне `options` → `-32602`; `mode` → `AgentSession.setMode` и `current_mode_update`; `model` → `AgentSession.setModel`; `effort` → `AgentSession.setEffort`; `agent` → `AgentSession.setAgent`, и если режим сессии изменился — `current_mode_update` до ответа. Ответ — полный список опций, в том числе изменённые `mode` и `model`; `config_option_update` в ответ на запрос клиента НЕ SHALL дублироваться (ACP-11). Смена модели через `agent` (выбор агента или возврат к `default`) SHALL ставить ту же заметку §2.12.3, что `configId: "model"`: переход на модель без `supportsReasoning` — заметка первым `agent_message_chunk` следующего хода, переход на модель с рассуждением — заметка снимается.

`session/set_config_option` и `session/set_mode` одной сессии SHALL обрабатываться мостом строго по очереди в порядке прихода (design.md change `add-agent-project-files`, D12). Эхо `ModeChanged` SHALL относиться к запросу, чья смена его породила: оно проецируется только в `current_mode_update`, ответ на этот запрос уходит после него. На каждый запрос SHALL уходить ровно один ответ со снимком опций после своей смены; итоговое состояние сессии — результат последнего запроса. Ошибка одного запроса НЕ SHALL останавливать очередь.

`session/set_mode` SHALL обрабатываться той же функцией, что `configId: "mode"`: ответ `{}`, затем `current_mode_update`; сессия другого соединения → `-32002` с `data.codelab.reason: "sessionNotOwned"`.

#### Scenario: Смена режима опцией
- **WHEN** клиент присылает `session/set_config_option` с `configId: "mode"` и `value: "plan"`
- **THEN** сначала уходит `current_mode_update` с `plan`, затем ответ с полным списком опций

#### Scenario: Опция effort у модели без рассуждения
- **WHEN** модель сессии сменена на модель без `supportsReasoning`, а клиент присылает `session/set_config_option` с `configId: "effort"`
- **THEN** ответ — `-32602`, а в списке опций `effort` нет до смены обратно

#### Scenario: Выбор агента опцией
- **WHEN** у доверенного проекта есть `.codelab/agents/reviewer.md` с `mode: plan` и моделью каталога, а клиент присылает `session/set_config_option` с `configId: "agent"` и `value: "reviewer"`
- **THEN** сначала уходит `current_mode_update` с `plan`, затем ответ с согласованными `agent: reviewer`, `model` из файла и `mode: plan`; `config_option_update` не отправляется (фикстура `acp/set-config-option-agent`, R-15)

#### Scenario: Параллельные выбор агента и set_mode
- **WHEN** режим конфигурации `standard`, у доверенного проекта есть `reviewer.md` с `mode: plan`, а клиент без ожидания ответов присылает `session/set_config_option` с `configId: "agent"`, `value: "reviewer"` и сразу `session/set_mode` с `modeId: "bypass"`
- **THEN** кадры идут в порядке: `current_mode_update` с `plan`, ответ на первый запрос с `agent: reviewer` и `mode: plan`, `current_mode_update` с `bypass`, ответ `{}` на второй; `config_option_update` не отправляется ни разу; ход следующего `session/prompt` идёт в режиме `bypass` с профилем `reviewer`

#### Scenario: Смена модели агентом и заметка effort
- **WHEN** модель сессии поддерживает рассуждение, а клиент выбирает опцией `agent` определение, чья `model` без `supportsReasoning`, затем присылает `session/prompt`
- **THEN** ответ на `set_config_option` не содержит опции `effort`, а первый `agent_message_chunk` хода — заметка `Reasoning effort is not supported by <provider/model>; …`, как при смене опцией `model`

#### Scenario: Без определений опции нет
- **WHEN** у сессии нет ни одного определения агента
- **THEN** `configOptions` — `mode`, `model` и, при рассуждении, `effort`, как в фикстуре `acp/session-new-modes-config`

### Requirement: Запрос `_codelab/session/usage/ledger`
Сервер SHALL принимать запрос JSON-RPC `_codelab/session/usage/ledger` (клиент → агент, с `id`) с параметрами `sessionId` (строка) и необязательным `rebuild` (логическое, по умолчанию `false`); неизвестные поля параметров SHALL игнорироваться (design.md change `add-usage-ledger`, D6). Расширение SHALL соблюдать раздел «Custom Requests» `15-Extensibility.md`: имя с `_`, ответ с тем же `id`, поддержка объявлена ключом `usageLedger` блока `initialize`.

Сессия ищется среди открытых в сервере тем же способом, что у `session/prompt`; незнакомый `sessionId` SHALL давать `-32002` «Session not found»; сессия другого соединения — `-32002` с `data.codelab.reason: "sessionNotOwned"` (requirement «Сессия управляется соединением-владельцем»); неверные типы параметров — `-32602`. Путь к файлам журнала из параметров НЕ SHALL строиться.

Ответ SHALL строиться из отчёта журнала usage ядра (capability `agent-sessions`, «Журнал usage сессии»): без `rebuild` — свежий `usage.json` или пересчёт, если файла нет, он битый или устарел; с `rebuild` — пересчёт всегда. Результат SHALL иметь поля:
- `sessionId`; `seq` — последний `seq`, потраченный на снимки `_codelab/session/usage` этой сессии сервера к моменту построения, `0` — снимков не было;
- `ledger` — `status` (`upToDate`, `rebuilt`, `inMemory`, `notSaved`), `reason` только при `rebuilt` (`missing`, `invalid`, `stale`, `explicit`; у остальных статусов поля нет), `records`;
- `total` — агрегат формы D2 change `add-usage-extension` (`turns`, `steps`, `tokens`, `cost`, `partial`) по всем записям журнала: шаги, субагенты и суммаризатор;
- `turns` — ходы с шагами по пути до активного листа: `index` (с 1), `title` (если есть), `total` (агрегат хода с шагами и субагентами хода), `steps` (каждый — `index` с 0 в ходе, `model` в виде `<provider>/<id>`, `tokens`, `cost`, `partial`, `toolCallIds` — всегда, у шага без вызовов инструментов пустой список `[]`), `subagents` (`runs` и агрегат без `steps`; только при ненулевом `runs`), `running: true` у последнего хода, если ход сессии идёт;
- `models` — `model`, `steps` и агрегат шагов этой модели, в лексикографическом порядке `model`;
- `subagents` и `summaries` — `runs` или `count` с агрегатом, только при ненулевом счётчике;
- `currency: "USD"`, если в результате есть хоть одно `cost`.

Деньги, причины и их порядок SHALL следовать правилам уведомления `_codelab/session/usage` (D2, D6, D9 change `add-usage-extension`): микродоллары десятичной строкой; `cost` шага — при цене модели шага в каталоге сессии, стоимость хода — округлённая сумма usage его шагов и детей, сессии — сумма ходов и суммаризатора; `noUsage` — по записи журнала; `noPrice` — по каталогу моделей сессии в момент ответа; у суммаризатора — по `details.summaryModel`, у субагентов — эвристика «ненулевые токены при нулевой стоимости» (design.md change `add-usage-ledger`, D2, Q4). Ответ НЕ SHALL нести текстов сообщений, аргументов инструментов и секретов, кроме подписи хода `title` (не более 64 рун слов пользователя).

Запрос SHALL обслуживаться и во время хода; `session/cancel` его не отменяет. Сбой записи `usage.json` ошибкой запроса НЕ SHALL быть (статус `notSaved`); исключение свёртки SHALL давать `-32603` с `data.codelab.reason: "usageLedgerFailed"` и warning в лог. Каждый ответ SHALL давать debug-запись `acp.usage.ledger {session_id, rebuild, status, turns, steps, duration_ms}` без токенов, денег и подписей.

#### Scenario: Журнал после хода
- **WHEN** клиент объявил `usage`, ход сделал два шага с ценами, первый — с вызовом `read` (`toolCallId` `call_1`), и после ответа клиент шлёт `_codelab/session/usage/ledger`
- **THEN** результат совпадает с фикстурой `acp/usage-ledger-request`: `seq` равен `seq` снимка `turn`, `total.turns: 1`, `total.steps: 2`, `total` равен `session` последнего снимка по токенам и стоимости, у хода `title` — начало промпта, у первого шага `toolCallIds: ["call_1"]`, одна строка `models`

#### Scenario: Пересчёт по требованию
- **WHEN** клиент шлёт запрос с `rebuild: true`
- **THEN** `ledger.status` — `rebuilt`, `ledger.reason` — `explicit`, итоги те же, что без `rebuild` (фикстура `acp/usage-ledger-rebuild`)

#### Scenario: Незнакомая сессия
- **WHEN** `sessionId` не открыт в сервере
- **THEN** ответ — `-32002`, файлы не читаются и не пишутся

#### Scenario: Журнал чужой сессии
- **WHEN** `sessionId` открыт в сервере другим соединением
- **THEN** ответ — `-32002` с `data.codelab.reason: "sessionNotOwned"`, файлы не читаются и не пишутся

#### Scenario: Запрос во время хода
- **WHEN** запрос приходит, пока ход сессии идёт, и в журнале уже есть первый шаг хода
- **THEN** ответ приходит без ожидания конца хода, у последнего хода `running: true`, ход продолжается без изменений

#### Scenario: Модель без цен в истории
- **WHEN** в журнале есть шаги модели, которой в каталоге сессии нет цен
- **THEN** у этих шагов нет `cost`, `partial` — `["noPrice"]`; у хода, модели и `total` — `noPrice`; ноль за цену не выдаётся

#### Scenario: Сбой записи файла
- **WHEN** хранилище не может записать `usage.json`
- **THEN** ответ успешный, `ledger.status: "notSaved"`, в логе warning `usage.ledger.write_failed`

#### Scenario: Стандартные типы без новых полей (usageLedger)
- **WHEN** клиент запрашивает журнал
- **THEN** ни один стандартный тип ACP не получает новых полей; журнал приходит только в результате `_codelab/session/usage/ledger`
