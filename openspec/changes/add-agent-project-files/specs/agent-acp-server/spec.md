## MODIFIED Requirements

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
- **WHEN** у сессии есть встроенные инструменты, fake MCP-сервер с инструментом `echo` и шаблон `$CODELAB_HOME/prompts/review.md` с `argument-hint: "<path> [focus]"`
- **THEN** кадр после ответа `session/new` — `available_commands_update` ровно с одной командой `{"name":"review","description":…,"input":{"hint":"<path> [focus]"}}`, без имён `read`, `exec` и `mcp__fake__echo` (фикстура `acp/available-commands-no-tools`, R-07)

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

### Requirement: Режимы и опции сессии
`configOptions` SHALL идти в порядке `mode`, `model`, `effort`, `agent` (§13.6): `mode` — пять режимов `ModeId`; `model` — модели каталога ядра в формате `provider/model`; `effort` (`low`, `medium`, `high`, категория `thought_level`) — только если у текущей модели `supportsReasoning` (ACP-10); `agent` — только если у сессии есть хотя бы одно определение агента: вариант `default` (имя `Default`), затем `AgentSession.agents` по имени с `description` определения, `currentValue` — `AgentSession.agent`, без поля `category` (зарезервированные категории ACP — только `mode`, `model`, `thought_level`; design.md change `add-agent-project-files`, D12). Устаревшие синонимы режимов (`architect`, `debug`, `acceptEdits`, `code`) SHALL приниматься на входе и не отправляться наружу.

`session/set_config_option` SHALL: неизвестная сессия → `-32002`; неизвестный `configId` или значение вне `options` → `-32602`; `mode` → `AgentSession.setMode` и `current_mode_update`; `model` → `AgentSession.setModel`; `effort` → `AgentSession.setEffort`; `agent` → `AgentSession.setAgent`, и если режим сессии изменился — `current_mode_update` до ответа. Ответ — полный список опций, в том числе изменённые `mode` и `model`; `config_option_update` в ответ на запрос клиента НЕ SHALL дублироваться (ACP-11).

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

#### Scenario: Без определений опции нет
- **WHEN** у сессии нет ни одного определения агента
- **THEN** `configOptions` — `mode`, `model` и, при рассуждении, `effort`, как в фикстуре `acp/session-new-modes-config`
