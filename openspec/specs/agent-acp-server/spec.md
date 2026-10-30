# agent-acp-server Specification

## Purpose
ACP-сервер Dart-агента: пакет `codelab_agent_acp` проецирует `AgentRuntime` в Agent Client Protocol поверх любого `AcpTransport`. Соединение с фоновым ходом и единой исходящей очередью, методы `initialize`, `session/new`, `session/load` с реплеем, `session/list`, `session/prompt`, `session/cancel`, `session/set_mode` и `session/set_config_option`, проекция событий ядра в `session/update`, подключение MCP-серверов `mcpServers` сессии через ядро, файлы, команды и разрешения через запросы агента к клиенту, правила протокольного уровня и переподключение. Через эту границу любой ACP-клиент — codelab-app, CLI, Zed — получает агента без прямого API ядра (`agent-core-architecture` §13). Известные отклонения от `docs/protocols/acp/protocol/` — в `codelab-agent serve --ws` capability `mcp` выключена и MCP-серверы клиента пропускаются с `mcp.server.skipped`, профиль без транспорта `stdio` (`mobile`) пропускает stdio-серверы, `cwd` принимается только POSIX-путём — записаны в §13.15 документа ядра.
## Requirements
### Requirement: Соединение ACP-сервера
`AcpAgentServer.serve(AcpTransport)` SHALL обслуживать одно соединение до его закрытия; один сервер МОЖЕТ обслуживать несколько транспортов (§13.1 документа ядра). Соединение SHALL состоять из маршрутизатора входящих кадров, единой исходящей очереди и реестра исходящих запросов агента (design.md, D6):
- запрос клиента обрабатывается в отдельной задаче, чтение кадров не блокируется;
- каждый исходящий кадр проходит кодек `codelab_acp_protocol` и уходит в порядке постановки (ACP-1);
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
Ответ на `initialize` SHALL содержать ровно поля и значения §13.2 документа ядра: `protocolVersion: 1`; `agentCapabilities` с `loadSession` (`true` при capability `sessionPersistence`, иначе `false`), `promptCapabilities` (`image: true`, `audio: false`, `embeddedContext: true`), `mcpCapabilities` (`http: true`, если в плане ядра capability `mcp` включена с транспортом `http`, иначе `false`; `sse: false` всегда), `sessionCapabilities.list: {}` при `sessionPersistence`; `agentInfo`; `authMethods: []`. Флага stdio в `mcpCapabilities` нет: stdio обязателен для каждого агента (`03-Session Setup.md`, «MCP Servers»); профиль без stdio (`mobile`) и WS-профиль бинаря, где capability `mcp` выключена (design.md change `add-agent-mcp-client`, D3), — отклонения §13.15 документа ядра.

`clientCapabilities` SHALL сохраняться на соединение и определять env сессий этого соединения; отсутствие поля SHALL логироваться `acp.client_capabilities.absent`. Повторный `initialize` SHALL давать `-32600` «already initialized», любой метод `session/*` до `initialize` — `-32600` «initialize required». Метод `authenticate` SHALL давать `-32601` (§13.3).

#### Scenario: Ответ codelab-app
- **WHEN** клиент присылает `initialize` с `protocolVersion: 1` и `fs`/`terminal` capabilities
- **THEN** ответ совпадает с фикстурой `acp/initialize-capabilities`, где `mcpCapabilities` — `{"http": true, "sse": false}`

#### Scenario: Сессия до initialize
- **WHEN** первым кадром соединения приходит `session/new`
- **THEN** ответ — `-32600` «initialize required», соединение живо

#### Scenario: Ядро без MCP
- **WHEN** хост собрал ядро без `AgentCoreServices.mcp`
- **THEN** `mcpCapabilities` в ответе — `{"http": false, "sse": false}`

### Requirement: session/new
`session/new` SHALL выполнять алгоритм §13.4:
1. `cwd` не абсолютный → `-32602`; при локальном листинге несуществующий каталог → `-32602` (design.md change `add-dart-agent-acp-server`, D5).
2. `mcpServers` декодируются и отображаются в `McpServerConfig` с `origin: session` (design.md change `add-agent-mcp-client`, D11):
   - сервер `sse` пропускается с логом `mcp.server.skipped` и причиной `transport sse is not supported`;
   - сервер `http`, чей `url` не разбирается (`Uri.tryParse` → `null`), пропускается с логом `mcp.server.skipped` и причиной `invalid url`;
   - сервер неизвестного `type` (вариант `McpServer.unknown`) пропускается с логом `mcp.server.skipped` и причиной `unknown transport`;
   - `mcp.server.skipped` адаптера SHALL нести `session_id`, а строки клиента `type` и `name` в нём SHALL обрезаться до 64 символов по рунам;
   - остальные правила (capability, транспорт профиля, дубликаты, коллизии имён) применяет ядро;
   - сбой или пропуск сервера НЕ SHALL быть ошибкой запроса.
3. Сессия создаётся через `AgentRuntime.createSession` с env и `AcpPermissionGate` соединения, хуком `markInProgress` и серверами шага 2. Создание ждёт подключения серверов (параллельно, каждый — не дольше своего `connectTimeout`).
4. Ответ `NewSessionResponse(sessionId, modes, configOptions)`.
5. После ответа — `available_commands_update` с командами `AgentSession.commands` в их порядке: элемент `AvailableCommand {name, description, input: {hint}?}`, поле `input` — только при `inputHint` (`14-Slash Commands.md`; design.md change `add-agent-project-files`, D9). Без команд список пуст. Инструменты модели в список НЕ SHALL попадать (R-07).

До ответа на `session/new` уведомления этой сессии НЕ SHALL отправляться (ACP-8). Инструменты подключённых серверов SHALL быть доступны модели с первого хода этой сессии (R-24). Это заменяет поведение этапа 4, в котором каждый сервер пропускался (R-02).

#### Scenario: Режимы и опции новой сессии
- **WHEN** клиент создаёт сессию с абсолютным `cwd`
- **THEN** ответ содержит `modes` с пятью режимами и `configOptions` `mode` и `model`, а следующий кадр — `available_commands_update` с пустым списком, если у сессии нет шаблонов команд

#### Scenario: Относительный cwd
- **WHEN** `session/new` приходит с `cwd: "work/demo"`
- **THEN** ответ — `-32602`, сессия не создана

#### Scenario: Инструмент сервера доступен модели
- **WHEN** `session/new` содержит stdio-сервер `fake` эпохи modern и stdio-сервер `old` эпохи legacy, оба с инструментом `echo`, затем клиент присылает `session/prompt`
- **THEN** первый запрос к модели содержит схемы `mcp__fake__echo` и `mcp__old__echo` (фикстура `acp/session-new-with-mcp`, R-24)

#### Scenario: Сервер без общей версии протокола
- **WHEN** `session/new` содержит сервер, который на `server/discover` отвечает `-32022` без `2026-07-28` в `data.supported`
- **THEN** ответ `session/new` успешен, сервер пропущен с `mcp.server.failed` и списком его версий, остальные серверы подключены

#### Scenario: Сервер неподдерживаемого типа
- **WHEN** `session/new` содержит HTTP-сервер `web` и сервер `legacy` типа `sse`
- **THEN** ответ содержит `sessionId`, `legacy` пропущен с `mcp.server.skipped`, инструменты `web` доступны модели (фикстура `acp/mcp-http-tool-call`, E-03)

#### Scenario: Неразбираемый url HTTP-сервера
- **WHEN** `session/new` содержит сервер `type: "http"` с `url`, который `Uri.tryParse` не разбирает, и stdio-сервер `fake`
- **THEN** ответ успешен, первый сервер пропущен с `mcp.server.skipped` и причиной `invalid url`, `fake` подключён

#### Scenario: Сервер не подключился
- **WHEN** процесс stdio-сервера из `mcpServers` не запускается
- **THEN** ответ `session/new` успешен, лог `mcp.server.failed`, инструментов сервера в сессии нет

#### Scenario: Команды шаблонов после session/new
- **WHEN** у сессии есть встроенные инструменты, fake MCP-сервер с инструментом `echo` и шаблон `.codelab/prompts/review.md` доверенного проекта (`trusted_projects` с `${cwd}`) с `argument-hint: "<path> [focus]"`
- **THEN** кадр после ответа `session/new` — `available_commands_update` ровно с одной командой `{"name":"review","description":…,"input":{"hint":"<path> [focus]"}}`, без имён `read`, `exec` и `mcp__fake__echo` (фикстура `acp/available-commands-no-tools`, R-07)

Шаблон лежит в проекте, а не в `$CODELAB_HOME/prompts/`: формат фикстур пишет файлы только в `cwd` через `setup.files` (acp-golden-fixtures). Пользовательскую область (`$CODELAB_HOME/prompts/*.md`) покрывает тест хоста `apps/codelab_agent/test/agent_host_project_files_test.dart`.

### Requirement: session/load и реплей
`session/load` SHALL выполнять алгоритм §13.5 в объёме MVP: неизвестный `sessionId` → `-32002`; `cwd` запроса выигрывает у `cwd` заголовка с записью `custom` `codelab.cwd_changed`; сессия открывается `AgentRuntime.loadSession` с env, gate и хуками соединения и с `mcpServers` запроса, отображёнными так же, как в `session/new`. Если сессия уже открыта в этом процессе, `mcpServers` запроса SHALL заменять серверы сессии с `origin: session` через `AgentSession.setMcpServers` (design.md change `add-agent-mcp-client`, D11):
- совпавшие по `name` и параметрам остаются подключёнными;
- исчезнувшие закрываются, новые подключаются;
- серверы конфигурации не трогаются;
- без хода изменения применяются до ответа `session/load`, во время хода — после его окончания;
- проверка «сессия занята» и `reattach` SHALL быть атомарны относительно `setMcpServers`: ожидание замены не разделяет их;
- исключение `setMcpServers` НЕ SHALL ронять `session/load`: лог `mcp.servers.replace_failed` (warning, `session_id`, `error` — тип исключения), ответ отправляется как обычно.

Файлы проекта (agent-project-context) при повторном `session/load` уже открытой в процессе сессии НЕ SHALL перечитываться: адаптер переподключает открытую сессию (`reattach`) без вызова `AgentRuntime.loadSession`, поэтому `ProjectFilesSource.load` не вызывается, а команды и определения агентов сессии остаются прежними до её закрытия (design.md change `add-agent-project-files`, D6; §17.2.1 документа ядра: изменения файлов — со следующей сессии).

Описания серверов НЕ SHALL читаться из журнала. Реплей SHALL идти по активной ветке:
- слова пользователя → `user_message_chunk` на каждый блок; у записи с полем `command` первым блоком идёт исходный текст `/<name>[ <args>]` вместо развёрнутого (agent-slash-commands «Исходный текст команды в журнале»); прочие user-записи пропускаются;
- ответ модели → `agent_thought_chunk` и `agent_message_chunk` по блокам; вызов → один `tool_call` с итоговым статусом, `title`, `kind`, `locations`, `rawInput`, `content` результата, `diff` и `_meta.codelab.outcome` для `cancelled`/`rejected`/`interrupted`;
- `compaction` не отправляется.

После истории — последний `plan`, `current_mode_update`, `config_option_update` (с опцией `agent` и восстановленным значением, если она есть), `available_commands_update` с `AgentSession.commands`, `session_info_update`; затем ответ `LoadSessionResponse(modes, configOptions)`.

#### Scenario: Реплей двух ходов
- **WHEN** сессия с двумя ходами, вызовом `read` и заголовком загружается в новом соединении
- **THEN** кадры совпадают с фикстурой `acp/session-load-replay`, а ответ `session/load` — последний

#### Scenario: Прерванный ход
- **WHEN** журнал кончается вызовом без результата
- **THEN** реплей содержит `tool_call` со `status: failed` и `_meta.codelab.outcome: "interrupted"`, повторного вызова инструмента нет

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
`configOptions` SHALL идти в порядке `mode`, `model`, `effort`, `agent` (§13.6): `mode` — пять режимов `ModeId`; `model` — модели каталога ядра в формате `provider/model`; `effort` (`low`, `medium`, `high`, категория `thought_level`) — только если у текущей модели `supportsReasoning` (ACP-10); `agent` — только если у сессии есть хотя бы одно определение агента: вариант `default` (имя `Default`), затем `AgentSession.agents` по имени с `description` определения, `currentValue` — `AgentSession.agent`, без поля `category` (зарезервированные категории ACP — только `mode`, `model`, `thought_level`; design.md change `add-agent-project-files`, D12). Устаревшие синонимы режимов (`architect`, `debug`, `acceptEdits`, `code`) SHALL приниматься на входе и не отправляться наружу.

`session/set_config_option` SHALL: неизвестная сессия → `-32002`; неизвестный `configId` или значение вне `options` → `-32602`; `mode` → `AgentSession.setMode` и `current_mode_update`; `model` → `AgentSession.setModel`; `effort` → `AgentSession.setEffort`; `agent` → `AgentSession.setAgent`, и если режим сессии изменился — `current_mode_update` до ответа. Ответ — полный список опций, в том числе изменённые `mode` и `model`; `config_option_update` в ответ на запрос клиента НЕ SHALL дублироваться (ACP-11). Смена модели через `agent` (выбор агента или возврат к `default`) SHALL ставить ту же заметку §2.12.3, что `configId: "model"`: переход на модель без `supportsReasoning` — заметка первым `agent_message_chunk` следующего хода, переход на модель с рассуждением — заметка снимается.

`session/set_config_option` и `session/set_mode` одной сессии SHALL обрабатываться мостом строго по очереди в порядке прихода (design.md change `add-agent-project-files`, D12). Эхо `ModeChanged` SHALL относиться к запросу, чья смена его породила: оно проецируется только в `current_mode_update`, ответ на этот запрос уходит после него. На каждый запрос SHALL уходить ровно один ответ со снимком опций после своей смены; итоговое состояние сессии — результат последнего запроса. Ошибка одного запроса НЕ SHALL останавливать очередь.

`session/set_mode` SHALL обрабатываться той же функцией, что `configId: "mode"`: ответ `{}`, затем `current_mode_update`.

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

### Requirement: Неизвестный транспорт MCP-сервера
Модель `McpServer` пакета `codelab_acp_protocol` SHALL разбирать элемент `mcpServers` с неизвестным строковым `type` в вариант `McpServer.unknown({type, name?, raw})` (design.md change `add-agent-mcp-client`, D11; `AGENTS.md` §7, совместимость вперёд):
- проверка допустимых ключей к такому элементу не применяется;
- `raw` хранит объект целиком, `toJson()` возвращает его без изменений;
- известные типы (`stdio` без `type` или с `"stdio"`, `http`, `sse`) SHALL проверяться строго, как раньше: неизвестный ключ, отсутствующее обязательное поле и нестроковый `type` дают `-32602`.

ACP-сервер агента SHALL пропускать такой сервер с `mcp.server.skipped {server, transport: <type>, reason: "unknown transport"}`. `session/new` и `session/load` SHALL при этом создавать сессию с остальными серверами.

#### Scenario: Сервер будущего транспорта
- **WHEN** `session/new` содержит `{"type": "websocket", "name": "future", "url": "wss://x"}` и stdio-сервер `fake`
- **THEN** ответ успешен, `future` пропущен с `mcp.server.skipped` и `reason: unknown transport`, инструменты `fake` доступны модели

#### Scenario: Известный тип по-прежнему строг
- **WHEN** элемент `mcpServers` имеет `type: "http"` без `url`
- **THEN** `session/new` получает `-32602`, сессия не создана

#### Scenario: Модель сохраняет неизвестный сервер
- **WHEN** `McpServer.fromJson` получает `{"type": "websocket", "name": "future", "extra": 1}`
- **THEN** результат — `McpServerUnknown` с `type: "websocket"`, `name: "future"`, а `toJson()` равен исходному объекту

