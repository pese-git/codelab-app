# agent-acp-server Specification

## Purpose
ACP-сервер Dart-агента: пакет `codelab_agent_acp` проецирует `AgentRuntime` в Agent Client Protocol поверх любого `AcpTransport`. Соединение с фоновым ходом и единой исходящей очередью, методы `initialize`, `session/new`, `session/load` с реплеем, `session/list`, `session/prompt`, `session/cancel`, `session/set_mode` и `session/set_config_option`, проекция событий ядра в `session/update`, файлы, команды и разрешения через запросы агента к клиенту, правила протокольного уровня и переподключение. Через эту границу любой ACP-клиент — codelab-app, CLI, Zed — получает агента без прямого API ядра (`agent-core-architecture` §13). Известные отклонения от `docs/acp/protocol/` — MCP-серверы по stdio не подключаются до этапа 8, `cwd` принимается только POSIX-путём — записаны в §13.15 документа ядра.
## Requirements
### Requirement: Соединение ACP-сервера
`AcpAgentServer.serve(AcpTransport)` SHALL обслуживать одно соединение до его закрытия; один сервер МОЖЕТ обслуживать несколько транспортов (§13.1 документа ядра). Соединение SHALL состоять из маршрутизатора входящих кадров, единой исходящей очереди и реестра исходящих запросов агента (design.md, D6):
- запрос клиента обрабатывается в отдельной задаче, чтение кадров не блокируется;
- каждый исходящий кадр проходит кодек `acp_protocol` и уходит в порядке постановки (ACP-1);
- ответ на `session/prompt` ставится после последнего `session/update` хода, ответ на `session/load` — после последнего уведомления реплея (ACP-3);
- id исходящих запросов агента — строки `perm-<n>`, `fs-<n>`, `term-<n>` со счётчиком на соединение (§13.9).

Пакет `codelab_agent_acp` НЕ SHALL импортировать `dart:io` и `package:flutter/` (PKG-3); транспорты и локальный листинг передаёт хост.

#### Scenario: Ответ хода последним
- **WHEN** транспорт медленно принимает кадры, а модель отдаёт 1 000 дельт текста
- **THEN** ответ на `session/prompt` — последний кадр хода, после всех `agent_message_chunk`

#### Scenario: Отмена во время хода
- **WHEN** ход ждёт ответа модели, а клиент присылает `session/cancel`
- **THEN** соединение принимает уведомление во время хода, и ход завершается ответом `stopReason: cancelled`

### Requirement: initialize
Ответ на `initialize` SHALL содержать ровно поля и значения §13.2 документа ядра: `protocolVersion: 1`; `agentCapabilities` с `loadSession` (`true` при capability `sessionPersistence`, иначе `false`), `promptCapabilities` (`image: true`, `audio: false`, `embeddedContext: true`), `mcpCapabilities` (`http` по capability `mcp`, `sse: false`), `sessionCapabilities.list: {}` при `sessionPersistence`; `agentInfo`; `authMethods: []`.

`clientCapabilities` SHALL сохраняться на соединение и определять env сессий этого соединения; отсутствие поля SHALL логироваться `acp.client_capabilities.absent`. Повторный `initialize` SHALL давать `-32600` «already initialized», любой метод `session/*` до `initialize` — `-32600` «initialize required». Метод `authenticate` SHALL давать `-32601` (§13.3).

#### Scenario: Ответ codelab-app
- **WHEN** клиент присылает `initialize` с `protocolVersion: 1` и `fs`/`terminal` capabilities
- **THEN** ответ совпадает с фикстурой `acp/initialize-capabilities`

#### Scenario: Сессия до initialize
- **WHEN** первым кадром соединения приходит `session/new`
- **THEN** ответ — `-32600` «initialize required», соединение живо

### Requirement: session/new
`session/new` SHALL выполнять алгоритм §13.4 в объёме этапа 4:
1. `cwd` не абсолютный → `-32602`; при локальном листинге несуществующий каталог → `-32602` (design.md, D5);
2. `mcpServers` декодируются; каждый сервер пропускается с логом `mcp.server.skipped` (MCP — этап 8);
3. сессия создаётся через `AgentRuntime.createSession` с env и `AcpPermissionGate` соединения и хуком `markInProgress`;
4. ответ `NewSessionResponse(sessionId, modes, configOptions)`;
5. после ответа — `available_commands_update` с `availableCommands: []`.

До ответа на `session/new` уведомления этой сессии НЕ SHALL отправляться (ACP-8).

#### Scenario: Режимы и опции новой сессии
- **WHEN** клиент создаёт сессию с абсолютным `cwd`
- **THEN** ответ содержит `modes` с пятью режимами и `configOptions` `mode` и `model`, а следующий кадр — `available_commands_update` с пустым списком

#### Scenario: Относительный cwd
- **WHEN** `session/new` приходит с `cwd: "work/demo"`
- **THEN** ответ — `-32602`, сессия не создана

### Requirement: session/load и реплей
`session/load` SHALL выполнять алгоритм §13.5 в объёме MVP: неизвестный `sessionId` → `-32002`; `cwd` запроса выигрывает у `cwd` заголовка с записью `custom` `codelab.cwd_changed`; сессия открывается `AgentRuntime.loadSession` с env, gate и хуками соединения. Реплей SHALL идти по активной ветке:
- слова пользователя → `user_message_chunk` на каждый блок; прочие user-записи пропускаются;
- ответ модели → `agent_thought_chunk` и `agent_message_chunk` по блокам; вызов → один `tool_call` с итоговым статусом, `title`, `kind`, `locations`, `rawInput`, `content` результата, `diff` и `_meta.codelab.outcome` для `cancelled`/`rejected`/`interrupted`;
- `compaction` не отправляется.

После истории — последний `plan`, `current_mode_update`, `config_option_update`, `available_commands_update`, `session_info_update`; затем ответ `LoadSessionResponse(modes, configOptions)`.

#### Scenario: Реплей двух ходов
- **WHEN** сессия с двумя ходами, вызовом `read` и заголовком загружается в новом соединении
- **THEN** кадры совпадают с фикстурой `acp/session-load-replay`, а ответ `session/load` — последний

#### Scenario: Прерванный ход
- **WHEN** журнал кончается вызовом без результата
- **THEN** реплей содержит `tool_call` со `status: failed` и `_meta.codelab.outcome: "interrupted"`, повторного вызова инструмента нет

### Requirement: session/list
`session/list` SHALL отдавать страницу `AgentRuntime.listSessions` (50 элементов): `sessionId`, `cwd`, `title`, `updatedAt` и `nextCursor`, если остались элементы. `cwd` не абсолютный или неразбираемый `cursor` → `-32602`; нет совпадений — пустой `sessions` без `nextCursor` (§13.5).

#### Scenario: Фильтр по папке
- **WHEN** в хранилище сессии двух папок, а клиент запрашивает `session/list` с `cwd` одной из них
- **THEN** ответ содержит только её сессии, новые первыми

### Requirement: session/prompt, проекция и итог хода
`session/prompt` SHALL запускать ход в фоне (§13.7): неизвестная сессия → `-32002`; пустой `prompt` или блок `audio` → `-32602`; идущий ход → `-32602` с `data.codelab.reason: "turnActive"` и логом `acp.prompt.rejected`. Контент — по §13.4 (`resource` с `text` — текстовый блок с путём, `resource` с `blob` и `resource_link` — текстовые пометки).

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
`session/cancel` SHALL отменять токен хода; ожидающие `session/request_permission` этой сессии завершаются `cancelled` (отказ), `fs/*` — ошибкой `aborted`, `terminal/wait_for_exit` — `terminal/kill`, `terminal/output`, `terminal/release`. Ответ на `session/prompt` SHALL быть `stopReason: cancelled`, даже если отмена вызвала ошибки провайдера или инструментов (ACP-5). Отмена без хода SHALL логироваться `acp.cancel.no_turn` и ничего не отправлять.

#### Scenario: Отмена посреди команды
- **WHEN** клиент отменяет ход, пока `exec` ждёт `terminal/wait_for_exit`
- **THEN** агент отправляет `terminal/kill`, `terminal/output`, `terminal/release`, затем `tool_call_update` `failed` с `outcome: "cancelled"` и ответ `stopReason: cancelled`

### Requirement: Режимы и опции сессии
`configOptions` SHALL идти в порядке `mode`, `model`, `effort` (§13.6): `mode` — пять режимов `ModeId`; `model` — модели каталога ядра в формате `provider/model`; `effort` (`low`, `medium`, `high`, категория `thought_level`) — только если у текущей модели `supportsReasoning` (ACP-10). Устаревшие синонимы режимов (`architect`, `debug`, `acceptEdits`, `code`) SHALL приниматься на входе и не отправляться наружу.

`session/set_config_option` SHALL: неизвестная сессия → `-32002`; неизвестный `configId` или значение вне `options` → `-32602`; `mode` → `AgentSession.setMode` и `current_mode_update`; `model` → `AgentSession.setModel`; `effort` → `AgentSession.setEffort`. Ответ — полный список опций; `config_option_update` в ответ на запрос клиента НЕ SHALL дублироваться (ACP-11).

`session/set_mode` SHALL обрабатываться той же функцией, что `configId: "mode"`: ответ `{}`, затем `current_mode_update`.

#### Scenario: Смена режима опцией
- **WHEN** клиент присылает `session/set_config_option` с `configId: "mode"` и `value: "plan"`
- **THEN** сначала уходит `current_mode_update` с `plan`, затем ответ с полным списком опций

#### Scenario: Опция effort у модели без рассуждения
- **WHEN** модель сессии сменена на модель без `supportsReasoning`, а клиент присылает `session/set_config_option` с `configId: "effort"`
- **THEN** ответ — `-32602`, а в списке опций `effort` нет до смены обратно

### Requirement: Запросы агента к клиенту
`AcpClientExecutionEnv` SHALL исполнять файлы и команды через клиента по §4.7 и §13.9:
- `readText` → `fs/read_text_file`, `writeText` → `fs/write_text_file`, `stat` → `fs/read_text_file` с `limit: 1`; таймаут 30 с;
- `exec` → `terminal/create` (`command: "/bin/sh"`, `args: ["-c", <команда>]`, `cwd`, `env`, `outputByteLimit`) → `terminal/wait_for_exit` → `terminal/output` → `terminal/release`; `terminal/release` — всегда, включая ошибки, отмену и таймаут (ACP-9, ENV-7);
- метод, для которого клиент не объявил capability, → `Err(unsupported)` без запроса (`exec` — `ExecErrorCode.shellUnavailable`);
- ошибка JSON-RPC `-32002` → `notFound`, прочие → `io` с текстом клиента, таймаут → `io` «… (timed out)», разрыв соединения → `io` «client connection lost».

`AcpPermissionGate` SHALL запрашивать решение через `session/request_permission` по §7.8: `toolCall` с `rawInput`, `locations` и `diff`, варианты `allow_once`, `allow_always` (только если предложен), `reject_once`, `reject_always`; критическая команда — `_meta.codelab.critical`. Неизвестный `optionId`, ошибка JSON-RPC и разрыв → отказ с логом; `cancelled` и отмена хода → `cancelled`.

#### Scenario: Ошибка ожидания терминала
- **WHEN** клиент отвечает ошибкой на `terminal/wait_for_exit`
- **THEN** агент всё равно отправляет `terminal/release`, а результат `exec` — ошибка

#### Scenario: Клиент без терминала
- **WHEN** клиент не объявил `terminal`, а модель зовёт `exec`
- **THEN** ни одного кадра `terminal/*` не уходит, вызов завершается ошибкой

### Requirement: Правила протокольного уровня
Соединение SHALL выдерживать плохие кадры (ACP-4): неразбираемый JSON → `-32700` с `id: null` и не JSON-RPC 2.0 → `-32600` — их разбирает и отвечает серверный транспорт (design.md, D12); сервер на сообщения отвечает: неизвестный метод запроса → `-32601`; неизвестное уведомление → лог и игнор; параметры не декодируются → `-32602`; исключение обработчика → `-32603` со стеком в логе; ответ на неизвестный id → лог `acp.frame.bad`. Ни одна из этих ошибок НЕ SHALL закрывать соединение или прерывать идущие ходы. Свои коды в диапазоне `-32000…-32099` НЕ SHALL вводиться; причина уточняется `data.codelab.reason`.

#### Scenario: Мусор посреди хода
- **WHEN** во время хода приходят неполный JSON, массив вместо объекта и неизвестный метод
- **THEN** каждый получает свою ошибку, ход продолжается и завершается ответом `end_turn`

### Requirement: Отсоединение, переподключение и завершение
Конец входа соединения (EOF stdin, закрытый сокет) SHALL приводить к ответам на уже прочитанные запросы, отправке очереди и закрытию транспорта, и только затем `serve` SHALL завершаться: у stdio выход живёт дольше входа (design.md change `add-codelab-agent-binary`, D7). Закрытие транспорта SHALL переводить соединение в `detached` на `detachGrace` (по умолчанию 30 с, `Duration.zero` — без ожидания). Если за это время сессию загружают новым соединением — переподключение: ожидающие `session/request_permission` отправляются заново с новым id и тем же `toolCallId` (PERM-4), итог хода новому соединению — `session_info_update` с `_meta.codelab.turnEnded`. Иначе ход отменяется, разрешения → `cancelled`. `session/load` сессии, ход которой идёт в другом живом соединении, SHALL давать `-32602` с `reason: "sessionBusy"`.

`shutdown({grace})` SHALL отвечать на новые запросы `-32603` «shutting down», завершать ожидающие разрешения `cancelled`, отменять ходы и ждать `TurnEnded` не дольше `grace`, затем закрывать транспорты (§13.10).

#### Scenario: Переподключение во время разрешения
- **WHEN** соединение закрывается, пока ход ждёт `session/request_permission`, а новое соединение загружает сессию до истечения grace
- **THEN** новое соединение получает реплей и новый `session/request_permission` с тем же `toolCallId`

#### Scenario: Grace истёк
- **WHEN** соединение закрывается во время хода и за 30 с никто не загружает сессию
- **THEN** ход завершается `cancelled`, журнал содержит итоговые записи хода

#### Scenario: Ответ после EOF входа
- **WHEN** клиент пишет `initialize` и сразу закрывает вход соединения, а выход ещё принимает кадры
- **THEN** ответ на `initialize` отправляется, транспорт закрывается, и `serve` завершается

### Requirement: Расширения протокола этапа 4
Сервер SHALL отправлять только расширения, введённые этим change (ACP-2): `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded`, `data.codelab` (`errorClass`, `message`, `retryable`, `reason`), `_meta.codelab.turnEnded`, `_meta.codelab.critical`. Каждое расширение SHALL быть перечислено в §13.12 документа ядра со ссылкой на этот change.

#### Scenario: Бюджет хода
- **WHEN** ход исчерпал лимит шагов
- **THEN** ответ на `session/prompt` — `stopReason: max_turn_requests` с `_meta.codelab.budgetExceeded: "steps"`

