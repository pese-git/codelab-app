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

Единственное исключение из «ровно этих полей» — блок объявлений расширений CodeLab `agentCapabilities._meta.codelab` (design.md change `add-subagents-and-tasks`, D9). Правила блока:
- он SHALL отправляться, только если клиент прислал объект `clientCapabilities._meta.codelab` (в том числе пустой);
- значение каждого ключа — объект с целым `version`: всегда — `tasks: {"version": 1}`; `subagents: {"version": 1, "maxDepth": <subagents.max_depth>}` — только если у ядра включены субагенты (инструмент `agent` при `subagents.enabled`, с итерации 2 change `add-subagents-and-tasks`); `enabled` и эффективная глубина SHALL браться из применённого конфига в момент `initialize` (геттер `AgentRuntime.subagents`; design.md, D37): `maxDepth` — это `subagents.max_depth`, ограниченная глубиной, которую реализует агент (до итерации 4 change — 1); порог окна контекста D40 объявления не меняет, поэтому перезагрузка конфига меняет блок для следующих `initialize` без перезапуска; `subagentToolCalls: {"version": 1}` — при том же условии и только когда адаптер умеет проецировать вызовы потомков (требование «Шаги потомков деревом», с итерации 5 change `add-subagents-and-tasks`, задача 5.2). Агент НЕ SHALL объявлять расширение, которого у него нет. Состав блока не зависит от того, какие ключи и версии объявил клиент;
- `usage: {"version": 1}` — всегда, когда блок отправляется (design.md change `add-usage-extension`, D3; с итерации 1 этого change): usage ядро считает всегда, а неизвестную цену выражают поля `cost` и `partial` уведомления. Как и остальной состав блока, ключ не зависит от того, какие ключи и версии объявил клиент;
- `usageLedger: {"version": 1}` — всегда, когда блок отправляется (design.md change `add-usage-ledger`, D7; с итерации 2 того change): агент принимает запрос `_codelab/session/usage/ledger` (требование «Запрос `_codelab/session/usage/ledger`»). Клиент этот ключ не объявляет; ключ `usageLedger` в `clientCapabilities._meta.codelab` SHALL игнорироваться, как любой неизвестный ключ;
- неизвестные ключи и значения в `clientCapabilities._meta.codelab` SHALL игнорироваться без ошибки;
- стандартные поля и их значения блок не меняет.

`clientCapabilities` SHALL сохраняться на соединение и определять env сессий этого соединения; отсутствие поля SHALL логироваться `acp.client_capabilities.absent`. Повторный `initialize` SHALL давать `-32600` «already initialized», любой метод `session/*` до `initialize` — `-32600` «initialize required». Метод `authenticate` SHALL давать `-32601` (§13.3).

Объявление клиентом `clientCapabilities._meta.codelab.usage` SHALL сохраняться на соединение и определять, получает ли оно `_codelab/session/usage` (требование «Уведомление `_codelab/session/usage`»; design.md change `add-usage-extension`, D3). Объявление считается сделанным, только если значение ключа `usage` — объект, где `version` — целое JSON-число `1` (не `1.0`, не строка `"1"`, не другое число), — по тому же правилу, по которому клиент CodeLab согласует расширения из ответа агента (design.md change `add-subagents-and-tasks`, D9). Иное значение SHALL давать «не объявлено» без ошибки `initialize`.

Блоки `agentCapabilities._meta.codelab` в сценариях change `add-subagents-and-tasks` ниже (с пометками итераций, «Субагенты выключены перезагрузкой конфига», «Неизвестные ключи и версии клиента», «Субагенты выключены») описывают ответ до итерации 1 change `add-usage-extension`; после неё каждый такой блок дополнительно содержит `"usage": {"version": 1}`, остальное в них не меняется. Сценарии change `add-usage-extension` помечены «(usage)». После итерации 2 change `add-usage-ledger` каждый блок `agentCapabilities._meta.codelab` в сценариях ниже, включая сценарии «(usage)», дополнительно содержит `"usageLedger": {"version": 1}`, остальное в них не меняется; сценарии этого change помечены «(usageLedger)».

#### Scenario: Ответ codelab-app
- **WHEN** клиент присылает `initialize` с `protocolVersion: 1` и `fs`/`terminal` capabilities без `_meta` (так ведёт себя сторонний клиент; в любой итерации change)
- **THEN** ответ совпадает с фикстурой `acp/initialize-capabilities`, где `mcpCapabilities` — `{"http": true, "sse": false}`, а `_meta` у `agentCapabilities` нет

#### Scenario: Клиент CodeLab объявил расширения, субагентов ещё нет (итерация 1)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}}`, а ядро собрано без инструмента `agent`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции итерации 1: `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}}`, остальные поля — как в `acp/initialize-capabilities`

#### Scenario: Клиент CodeLab объявил расширения, субагенты включены (итерации 2–3)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}}`, ядро собрано с `subagents.enabled: true` и `max_depth: 3`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции итерации 2: `agentCapabilities._meta.codelab` — `{"subagents": {"version": 1, "maxDepth": 1}, "tasks": {"version": 1}}`: вложенности до итерации 4 нет, поэтому объявляется эффективная глубина 1, а не `max_depth: 3`; ключа `subagentToolCalls` нет: вызовы потомков адаптер ещё не проецирует

#### Scenario: Клиент CodeLab объявил расширения, вложенность (итерация 4)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}}`, ядро собрано с `subagents.enabled: true` и `max_depth: 3`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции итерации 4: `agentCapabilities._meta.codelab` — `{"subagents": {"version": 1, "maxDepth": 3}, "tasks": {"version": 1}}`: потомки запускают своих детей до `max_depth`, поэтому объявляется `max_depth`; ключа `subagentToolCalls` нет (design.md, D45 Т9)

#### Scenario: Клиент CodeLab объявил расширения, дерево вызовов (итерация 5)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}}`, ядро собрано с `subagents.enabled: true` и `max_depth: 3`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции итерации 5: `agentCapabilities._meta.codelab` — `{"subagents": {"version": 1, "maxDepth": 3}, "subagentToolCalls": {"version": 1}, "tasks": {"version": 1}}`

#### Scenario: Субагенты выключены перезагрузкой конфига
- **WHEN** агент запущен с `subagents.enabled: true`, затем перезагрузка конфига ставит `subagents.enabled: false`, и новое соединение присылает `initialize` с `clientCapabilities._meta.codelab: {}`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}}`; ответ `initialize`, полученный соединением до перезагрузки, не меняется (`initialize_test.dart`; D37)

#### Scenario: Неизвестные ключи и версии клиента
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 2, "x": 1}, "future": true, "board": "yes"}`
- **THEN** ошибки нет, блок ответа — тот же, что при известном объявлении (в итерации 1 — `{"tasks": {"version": 1}}`); проверяет unit-тест `initialize_test.dart` агента, а не фикстура

#### Scenario: Клиентский _meta без codelab
- **WHEN** клиент присылает `clientCapabilities._meta: {"traceparent": "…"}` без ключа `codelab`
- **THEN** у `agentCapabilities` нет `_meta` (`initialize_test.dart`)

#### Scenario: Субагенты выключены
- **WHEN** `subagents.enabled: false`, клиент объявил `clientCapabilities._meta.codelab: {}`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}}`

#### Scenario: Сессия до initialize
- **WHEN** первым кадром соединения приходит `session/new`
- **THEN** ответ — `-32600` «initialize required», соединение живо

#### Scenario: Ядро без MCP
- **WHEN** хост собрал ядро без `AgentCoreServices.mcp`
- **THEN** `mcpCapabilities` в ответе — `{"http": false, "sse": false}`

#### Scenario: Клиент CodeLab объявил расширения (usage)
- **WHEN** после итерации 1 change `add-usage-extension` клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}, "usage": {"version": 1}, "future": true}`, ядро собрано с `subagents.enabled: true` и `max_depth: 3`
- **THEN** ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в текущей редакции: блок редакции change `add-subagents-and-tasks` с добавленным `"usage": {"version": 1}` — в итерации 2 того change `{"subagents": {"version": 1, "maxDepth": 1}, "tasks": {"version": 1}, "usage": {"version": 1}}`, после его итерации 5 — `{"subagents": {"version": 1, "maxDepth": 3}, "subagentToolCalls": {"version": 1}, "tasks": {"version": 1}, "usage": {"version": 1}}`; остальные поля — как в `acp/initialize-capabilities`

#### Scenario: Субагенты выключены (usage)
- **WHEN** после итерации 1 change `add-usage-extension` ядро собрано с `subagents.enabled: false`, а клиент объявил `clientCapabilities._meta.codelab: {}`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}, "usage": {"version": 1}}`

#### Scenario: Объявление usage не той версии (usage)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"usage": {"version": 2}}` (или `{"version": 1.0}`, `{"version": "1"}`, `usage: true`)
- **THEN** `initialize` успешен, блок ответа содержит `"usage": {"version": 1}`, но соединение не считается объявившим `usage` и кадров `_codelab/session/usage` не получает (`initialize_test.dart`)

#### Scenario: Клиент CodeLab объявил расширения (usageLedger)
- **WHEN** после итерации 2 change `add-usage-ledger` клиент присылает `clientCapabilities._meta.codelab: {"tasks": {"version": 1}, "usage": {"version": 1}}`, ядро собрано с `subagents.enabled: false`
- **THEN** `agentCapabilities._meta.codelab` — `{"tasks": {"version": 1}, "usage": {"version": 1}, "usageLedger": {"version": 1}}`; ответ совпадает с фикстурой `acp/initialize-codelab-extensions` в редакции этого change

#### Scenario: Клиент объявил usageLedger (usageLedger)
- **WHEN** клиент присылает `clientCapabilities._meta.codelab: {"usageLedger": {"version": 1}}`
- **THEN** `initialize` успешен, блок ответа тот же, что при `clientCapabilities._meta.codelab: {}`; ключ клиента ни на что не влияет (`initialize_test.dart`)

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
5. После ответа — `available_commands_update` с командами `AgentSession.commands` в их порядке: сначала встроенные команды сессии в порядке `compact`, `mode`, `model`, `status`, `config`, `mcp`, `help` (capability `agent-slash-commands`, «Встроенные команды MVP», «Встроенные команды config и mcp»; design.md change `add-agent-builtin-slash-commands`, D2), затем шаблоны. Элемент — `AvailableCommand {name, description, input: {hint}?}`, поле `input` — только при `inputHint` (`14-Slash Commands.md`; design.md change `add-agent-project-files`, D9; design.md change `add-config-writer-and-reload`, D12). Без команд список пуст. Инструменты модели в список НЕ SHALL попадать (R-07).

До ответа на `session/new` уведомления этой сессии НЕ SHALL отправляться (ACP-8). Инструменты подключённых серверов SHALL быть доступны модели с первого хода этой сессии (R-24). Это заменяет поведение этапа 4, в котором каждый сервер пропускался (R-02).

#### Scenario: Режимы и опции новой сессии
- **WHEN** клиент создаёт сессию с абсолютным `cwd`
- **THEN** ответ содержит `modes` с пятью режимами и `configOptions` `mode` и `model`, а следующий кадр — `available_commands_update`; в нём всегда есть встроенные `mode`, `model`, `status` и `help`

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
- **WHEN** у сессии есть встроенные инструменты, fake MCP-сервер с инструментом `echo` и шаблон `.codelab/prompts/review.md` доверенного проекта (`trusted_projects` с `${cwd}`) с `argument-hint: "<path> [focus]"`, а ядро собрано без `ConfigSource`
- **THEN** кадр после ответа `session/new` — `available_commands_update` ровно с командами `compact`, `mode`, `model`, `status`, `mcp`, `help` (встроенные; capability `compaction` и `mcp` агентского прогона включены, `config` нет — ядро без `ConfigSource`) и `{"name":"review","description":…,"input":{"hint":"<path> [focus]"}}` в этом порядке, без имён `read`, `exec` и `mcp__fake__echo` (фикстура `acp/available-commands-no-tools`, R-07)

Шаблон лежит в проекте, а не в `$CODELAB_HOME/prompts/`: формат фикстур пишет файлы только в `cwd` через `setup.files` (acp-golden-fixtures). Пользовательскую область (`$CODELAB_HOME/prompts/*.md`) покрывает тест хоста `apps/codelab_agent/test/agent_host_project_files_test.dart`.

### Requirement: session/load и реплей
`session/load` SHALL выполнять алгоритм §13.5 в объёме MVP: неизвестный `sessionId` → `-32002`; `cwd` запроса выигрывает у `cwd` заголовка с записью `custom` `codelab.cwd_changed`; сессия открывается `AgentRuntime.loadSession` с env, gate и хуками соединения и с `mcpServers` запроса, отображёнными так же, как в `session/new`. Id журнала субагента в базовом этапе SHALL давать `-32002`: хранилище дочерние журналы по id не ищет (design.md change `add-subagents-and-tasks`, D7). Если сессия уже открыта в этом процессе, `mcpServers` запроса SHALL заменять серверы сессии с `origin: session` через `AgentSession.setMcpServers` (design.md change `add-agent-mcp-client`, D11):
- совпавшие по `name` и параметрам остаются подключёнными;
- исчезнувшие закрываются, новые подключаются;
- серверы конфигурации не трогаются;
- без хода изменения применяются до ответа `session/load`, во время хода — после его окончания;
- проверка «сессия занята» и `reattach` SHALL быть атомарны относительно `setMcpServers`: ожидание замены не разделяет их;
- исключение `setMcpServers` НЕ SHALL ронять `session/load`: лог `mcp.servers.replace_failed` (warning, `session_id`, `error` — тип исключения), ответ отправляется как обычно.

Файлы проекта (agent-project-context) при повторном `session/load` уже открытой в процессе сессии НЕ SHALL перечитываться: адаптер переподключает открытую сессию (`reattach`) без вызова `AgentRuntime.loadSession`, поэтому `ProjectFilesSource.load` не вызывается, а команды и определения агентов сессии остаются прежними до её закрытия (design.md change `add-agent-project-files`, D6; §17.2.1 документа ядра: изменения файлов — со следующей сессии).

Описания серверов НЕ SHALL читаться из журнала. Реплей SHALL идти по активной ветке:
- слова пользователя → `user_message_chunk` на каждый блок; у записи с полем `command` первым блоком идёт исходный текст `/<name>[ <args>]` вместо развёрнутого (agent-slash-commands «Исходный текст команды в журнале»); прочие user-записи пропускаются;
- ответ модели → `agent_thought_chunk` и `agent_message_chunk` по блокам; вызов → один `tool_call` с итоговым статусом, `title`, `kind`, `locations`, `rawInput`, `content` результата, `diff` и `_meta.codelab.outcome` для `cancelled`/`rejected`/`interrupted`; вызов `agent` — так же, с телом отчёта в `content`;
- `compaction`, `task`, `subagent` и `plan` в ленту не отправляются; журналы детей не проигрываются.

После истории — `plan` из списка задач активной ветки (`buildTaskList`, agent-sessions «Список задач из журнала»; entries с `_meta.codelab.task`), если в ветке была хоть одна запись `task` или `plan`; затем `current_mode_update`, `config_option_update` (с опцией `agent` и восстановленным значением, если она есть), `available_commands_update` с `AgentSession.commands`, `session_info_update`; затем ответ `LoadSessionResponse(modes, configOptions)`.

#### Scenario: Реплей двух ходов
- **WHEN** сессия с двумя ходами, вызовом `read` и заголовком загружается в новом соединении
- **THEN** кадры совпадают с фикстурой `acp/session-load-replay`, а ответ `session/load` — последний

#### Scenario: Прерванный ход
- **WHEN** журнал кончается вызовом без результата
- **THEN** реплей содержит `tool_call` со `status: failed` и `_meta.codelab.outcome: "interrupted"`, повторного вызова инструмента нет

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

#### Scenario: Отмена /mode после применения
- **WHEN** сессия в режиме `standard`, приходит `session/prompt` с `/mode plan`, и `session/cancel` приходит после того, как запись `mode_change` дописана
- **THEN** кадры идут в порядке: `current_mode_update` с `plan`, `config_option_update`, `agent_message_chunk` с `Mode: plan.`, затем ответ на `session/prompt` со `stopReason: cancelled` (ACP-5, `05-Prompt Turn.md` «Cancellation»: уведомления — до ответа); после ответа кадров этого хода нет; режим сессии — `plan` (design.md change `add-agent-builtin-slash-commands`, D14)

#### Scenario: Отмена /mode до применения
- **WHEN** `session/cancel` для хода `/mode plan` приходит до применения смены
- **THEN** ни `current_mode_update`, ни `config_option_update`, ни `agent_message_chunk` нет, ответ — `stopReason: cancelled`, режим — `standard`

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
Конец входа соединения (EOF stdin, закрытый сокет) SHALL приводить к ответам на уже прочитанные запросы, отправке очереди и закрытию транспорта, и только затем `serve` SHALL завершаться: у stdio выход живёт дольше входа (design.md change `add-codelab-agent-binary`, D7). Закрытие транспорта SHALL переводить соединение в `detached` на `detachGrace` (по умолчанию 30 с, `Duration.zero` — без ожидания). Если за это время сессию загружают новым соединением — переподключение: каждый ожидающий `session/request_permission` (корня и потомка) SHALL отправляться новым запросом на новом соединении с тем же `toolCallId` (PERM-4); счётчик JSON-RPC id ведётся на соединение (§13.9), поэтому значение id нового запроса МОЖЕТ совпасть с id первого (design.md change `add-subagents-and-tasks`, D44); решение по вызову SHALL приниматься один раз. Итог хода новому соединению — `session_info_update` с `_meta.codelab.turnEnded`. Иначе ход отменяется, разрешения → `cancelled`. `session/load` сессии, ход которой идёт в другом живом соединении, SHALL давать `-32602` с `reason: "sessionBusy"`.

`shutdown({grace})` SHALL отвечать на новые запросы `-32603` «shutting down», завершать ожидающие разрешения `cancelled`, отменять ходы и ждать `TurnEnded` не дольше `grace`, затем закрывать транспорты (§13.10).

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

### Requirement: Расширения протокола этапа 4
Сервер SHALL отправлять только расширения, введённые утверждёнными changes (ACP-2):
- change `add-dart-agent-acp-server`: `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded`, `data.codelab` (`errorClass`, `message`, `retryable`, `reason`), `_meta.codelab.turnEnded`, `_meta.codelab.critical`;
- change `add-subagents-and-tasks`: блок `agentCapabilities._meta.codelab` (`subagents`, `subagentToolCalls`, `tasks`), `_meta.codelab.task` у entries `plan`, `_meta.codelab.subagent` у `toolCall` в `session/request_permission`, у первого `tool_call` вызова `agent` (`id`, `type`) и у его финального `tool_call_update` (`summary`, при `failed` — `failure`), `_meta.codelab.parentToolCallId` у `tool_call`/`tool_call_update` вызовов потомков (только клиенту с `subagentToolCalls`).
- change `add-usage-extension`: ключ `usage` блока `agentCapabilities._meta.codelab` и уведомление агент → клиент `_codelab/session/usage` (только соединению, объявившему `clientCapabilities._meta.codelab.usage`).
- change `add-usage-ledger`: ключ `usageLedger` блока `agentCapabilities._meta.codelab`, запрос клиент → агент `_codelab/session/usage/ledger` и значение `trigger: "load"` уведомления `_codelab/session/usage`.

Каждое расширение SHALL быть перечислено в §13.12 документа ядра со ссылкой на свой change. Новых методов и корневых полей ACP сервер НЕ SHALL вводить (`15-Extensibility.md`).

Уточнение change `add-usage-extension` (D17): запрет новых методов относится к методам вне пространства `_codelab/*`. Уведомление `_codelab/session/usage` введено по разделам «Extension Methods» и «Custom Notifications» `15-Extensibility.md` (имя с `_`, без `id`), перечислено выше и не вводит ни корневых полей, ни значений `sessionUpdate`. Запрос `_codelab/session/usage/ledger` (change `add-usage-ledger`, D6) введён по разделу «Custom Requests» того же документа: имя с `_`, ответ с тем же `id`, поддержка объявляется ключом `usageLedger`; агент без этого ключа отвечает на метод `-32601`.

#### Scenario: Бюджет хода
- **WHEN** ход исчерпал лимит шагов
- **THEN** ответ на `session/prompt` — `stopReason: max_turn_requests` с `_meta.codelab.budgetExceeded: "steps"`

#### Scenario: Запрос журнала у агента без ключа
- **WHEN** клиент шлёт `_codelab/session/usage/ledger` агенту, в ответе `initialize` которого нет ключа `usageLedger` (сторонний агент или CodeLab до change `add-usage-ledger`)
- **THEN** ответ — `-32601` «Method not found» по `15-Extensibility.md`; соединение живо

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

### Requirement: Локальное окружение сессии от хоста
`AcpServerConfig` SHALL иметь необязательное поле `localEnv` — фабрику `ExecutionEnv` по `cwd` сессии (`agent-core-architecture` §13.1; design.md change `add-embedded-agent-mode`, D4). Если хост его задал, `session/new` и `session/load` SHALL ставить env сессии `localEnv(cwd)`. Файлы, команды и листинг тогда исполняет хост: запросы `fs/*` и `terminal/*` клиенту НЕ SHALL отправляться, даже если клиент объявил `fs` и `terminal` в `initialize`. Без `localEnv` поведение прежнее: файлы и команды — через клиента (`AcpClientExecutionEnv`), листинг — через `localListing`. Gate сессии в обоих случаях SHALL оставаться `AcpPermissionGate`: вопрос одобрения идёт клиенту `session/request_permission`. `localEnv` НЕ SHALL менять ответ `initialize` и не добавляет методов, полей и состояний ACP. Сервер с включённой `fileListing` SHALL принимать `localEnv` вместо `localListing`: окружение `localEnv` обязано реализовывать листинг каталога, иначе — `HostWiringException` при создании сервера. Для этой проверки сервер SHALL один раз вызывать фабрику `localEnv` с `cwd` `/` при создании; поэтому фабрика SHALL быть без побочных эффектов и без обращения к файловой системе. При заданном `localEnv` `session/new` и `session/load` SHALL проверять существование `cwd` листингом окружения `localEnv(cwd)`: несуществующий каталог SHALL давать ошибку `-32602` (invalid params) до создания сессии, так же как при `localListing`.

#### Scenario: Хост исполняет файлы сам
- **WHEN** сервер создан с `localEnv`, клиент объявил `fs.readTextFile` и `terminal`, а сценарий модели в режиме `bypass` зовёт `read` и `exec`
- **THEN** клиент не получает ни `fs/read_text_file`, ни `terminal/create`; результаты вызовов приходят в `tool_call_update`

#### Scenario: Одобрение по-прежнему у клиента
- **WHEN** сервер создан с `localEnv`, а сценарий модели в режиме `standard` зовёт `write`
- **THEN** клиент получает `session/request_permission` с `toolCallId` вызова, и запись выполняется только после `allow_once`

#### Scenario: Команда в standard спрашивает клиента
- **WHEN** сервер создан с `localEnv`, а сценарий модели в режиме `standard` зовёт `exec`
- **THEN** клиент получает `session/request_permission` с `toolCallId` вызова, `terminal/create` не отправляется, и процесс запускается только после `allow_once`

#### Scenario: Несуществующий cwd при localEnv
- **WHEN** сервер создан с `localEnv`, и клиент вызывает `session/new` или `session/load` с абсолютным `cwd`, которого нет на диске
- **THEN** ответ — ошибка `-32602`, сессия не создаётся, фабрика `localEnv` для этого `cwd` не оставляет побочных эффектов

#### Scenario: Без localEnv поведение прежнее
- **WHEN** сервер создан без `localEnv`, клиент объявил `fs.readTextFile`, а модель зовёт `read`
- **THEN** агент отправляет клиенту `fs/read_text_file`

### Requirement: Уведомления после перезагрузки конфигурации
Событие сессии `ModelOptionsChanged` (capability `agent-runtime`, «Живая перезагрузка конфигурации») адаптер SHALL отображать в `config_option_update` с полным снимком опций сессии (`13-Session Config Options.md`; design.md change `add-config-writer-and-reload`, D8). `switch` проекции событий SHALL оставаться исчерпывающим.

Правила отправки:
- **Порядок.** Уведомление НЕ SHALL отправляться сессии до ответа на её `session/new` или `session/load` (ACP-8).
- **Неудача.** Неудачная перезагрузка НЕ SHALL порождать ни одного кадра.
- **Ход.** Во время хода уведомление SHALL идти в общем порядке событий сессии.
- **Опция `model`.** Текущее значение — модель сессии, даже если её больше нет в каталоге: такая модель SHALL оставаться в `options`.

Ответ встроенной команды SHALL уходить кадрами `agent_message_chunk` с текстом и ответом `session/prompt` со `stopReason: end_turn` (или `cancelled`), без `tool_call`, `plan` и `usage_update`. Новых методов, полей и `_meta` адаптер НЕ SHALL вводить.

#### Scenario: Список моделей изменился
- **WHEN** у соединения две живые сессии, и перезагрузка добавляет модель в каталог
- **THEN** каждая сессия получает ровно одно `config_option_update`, опция `model` содержит новую модель, `currentValue` сессии прежний (`config_reload_notifications_test.dart`)

#### Scenario: Неудачная перезагрузка
- **WHEN** перезагрузка завершается итогом `failed`
- **THEN** клиент не получает ни одного кадра

#### Scenario: Модель сессии удалена
- **WHEN** перезагрузка удаляет из каталога текущую модель сессии
- **THEN** `config_option_update` содержит её как `currentValue` и в `options`, следующий ход идёт на неё

#### Scenario: Ответ встроенной команды
- **WHEN** клиент присылает `session/prompt` с текстом `/mcp list`
- **THEN** кадры — `agent_message_chunk` с таблицей, затем ответ `{"stopReason":"end_turn"}`

### Requirement: Ошибка проектного конфига сессии
Если `AgentRuntime` отказывает в `session/new` или `session/load` из-за `ProjectConfigException`, сервер SHALL отвечать ошибкой JSON-RPC `-32603` с `data.codelab.reason: "projectConfigInvalid"`. Сообщение ошибки SHALL быть одной строкой: все проблемы через `; ` в форме `<source>:<line>:<column>: <key>: <message>`, без значений секретов; других полей в `data`, кроме `codelab.reason`, нет. Новых кодов ошибок сервер НЕ SHALL вводить, причину уточняет `data.codelab.reason`, как у остальных ошибок сервера. При `session/new` сессия НЕ SHALL создаваться и НЕ SHALL попадать в `session/list`; при `session/load` журнал сессии НЕ SHALL меняться, сессия остаётся незагруженной (design.md change `require-project-folder`, D21).

#### Scenario: session/new в папке с битым конфигом
- **WHEN** клиент отправляет `session/new` с `cwd`, чей `.codelab/config.yaml` не разбирается
- **THEN** ответ — `-32603` с `data.codelab.reason: "projectConfigInvalid"` и однострочным `message` с проблемой и путём файла; соединение и другие сессии продолжают работать

### Requirement: Модели сессии по её каталогу
`configOptions` `model` сессии SHALL перечислять модели каталога этой сессии: для сессии вне корня процесса — каталога, построенного из конфигурации её папки (spec agent-runtime «Конфигурация сессии вне корня запуска»). Источник — `AgentSession.models`, а не каталог рантайма. `session/set_config_option` с `configId: "model"` SHALL проверять значение по тому же каталогу: модель вне каталога сессии — `-32602`. Опции разных сессий одного соединения МОГУТ различаться (design.md change `require-project-folder`, D21). `config_option_update` после перезагрузки конфигурации корня (требование «Уведомления после перезагрузки конфигурации») SHALL уходить только сессиям, которые получили `ModelOptionsChanged`; сессиям других папок он не уходит (spec agent-runtime «Сессии других папок при перезагрузке корня»).

#### Scenario: Две сессии разных папок
- **WHEN** в одном соединении открыты сессия `/A` (каталог без `local`) и сессия `/B` (каталог с `local/m`)
- **THEN** `configOptions` `model` сессии `/B` содержит `local/m`, сессии `/A` — нет; `session/set_config_option` с `local/m` для сессии `/A` даёт `-32602`

#### Scenario: Перезагрузка корня и сессия другой папки
- **WHEN** в одном соединении открыты сессии `/A` (корень) и `/B`, и перезагрузка конфигурации корня добавляет модель в каталог
- **THEN** `config_option_update` получает только сессия `/A`

### Requirement: Проекция субагентов и списка задач
События субагентов и списка задач SHALL проецироваться по таблицам §13.7 и §17.3.7 исчерпывающим `switch` (ACP-6):

| Событие ядра | Кадр |
|---|---|
| `TaskListChanged` | `session/update` `plan` со всем списком в порядке создания; у entry `content` = `subject`, `priority`, `status` и `_meta: {"codelab": {"task": {"id", "owner", "blockedBy"}}}`; пустой список — `entries: []` (TSK-5); так же — при `change.op == restore` (список новой ветки, D29). У самого `plan` — `_meta: {"codelab": {"taskChange": {"op", "actor", "toolCallId"?, "changed", "deleted"}}}` из `TaskChange` (D35): `toolCallId` — только у операции вызова `task_*` (у потомка — цепочка D8), у `restore` и `assign` его нет; ключ уходит независимо от объявления клиента |
| `ToolCallStarted(agent)` | `tool_call` с `kind: think`, `title` `Subagent <agent>: <description>` (без непустого после обрезки `description` — `Subagent <agent>`, без двоеточия; design.md, D41, п. 3) и `_meta.codelab.subagent: {"id", "type"}` (D28); то же — у `tool_call` вызова `agent` при реплее, где `id` и `type` берутся из записи `subagent` с тем же `toolCallId`; у отклонённого вызова записи нет — при реплее `_meta.codelab.subagent: {"type"}` с `type` из аргументов вызова (`general` по умолчанию) и без `id` (D28; design.md, D36, Т15) |
| `ToolCallProgress(agent)` | `tool_call_update` с одним текстовым блоком строки прогресса, заменяющим предыдущий |
| `ToolCallFinished(agent)` | `tool_call_update` со `status` и телом отчёта без обёртки `<subagent-report>` и без ограды; у отменённого вызова с итогом ребёнка (`_meta.codelab.outcome: "cancelled"`) и у вызова без отчёта — `content: []`, который снимает строку прогресса; частичный отчёт отменённого ребёнка клиенту не уходит; так же — в реплее `session/load` и у вложенного вызова `agent`, закрытого вместе с поддеревом (design.md, D52 п. 1, D53); всегда — `_meta.codelab.subagent: {"id", "summary": {"toolCalls", "tokens": {"input", "output"}, "durationMs"}}` из `SubagentReport` (с потомками, D24); при `failed` — ещё `failure` (`budget_exceeded:<limit>`, `invalid_output`, `error`, `refused`, `interrupted`, `max_tokens` — design.md D41 п. 6; клиент неизвестные значения терпит) |
| `SubagentStarted`, `SubagentProgress`, `SubagentFinished` | не отправляются; логи `subagent.start`, `subagent.end` |
| `SubagentActivity` | клиенту без `subagentToolCalls` — не отправляется (SUB-12); клиенту с ним — требование «Шаги потомков деревом» |

`AcpPermissionGate` для запроса потомка SHALL отправлять `session/request_permission` с `sessionId` корневой сессии, `toolCall.toolCallId` — цепочкой, `title` с префиксом и `toolCall._meta.codelab.subagent` с полями `id`, `type`, `description`, `depth`, `path`, `parentToolCallId`. Пометка `critical` сохраняется в том же `_meta.codelab`.

Данные `_meta.codelab.task` и `_meta.codelab.subagent` SHALL отправляться независимо от объявления клиента в `initialize`.

#### Scenario: Список задач в ходе
- **WHEN** модель вызывает `task_create` три раза, затем `task_update` первого пункта в `completed`, затем `task_list`
- **THEN** клиент получает четыре `plan`, каждый со всем списком на момент операции и `_meta.codelab.task.id` у каждой entry; у каждого `plan` — `_meta.codelab.taskChange` с `op` (`create` трижды, затем `update`), `actor: "main"`, `toolCallId` своего вызова и `changed`; после `task_list` нового `plan` нет (фикстура `acp/prompt-task-plan`)

#### Scenario: Список новой ветки без toolCallId
- **WHEN** после смены ветки ядро эмитит `TaskListChanged` с `op: restore`
- **THEN** `plan` несёт `_meta.codelab.taskChange: {"op": "restore", "actor": "main", "changed": […], "deleted": […]}` без `toolCallId` (`acp_projection_exhaustive_test.dart`)

#### Scenario: Реплей плана без taskChange
- **WHEN** `session/load` сессии с тремя вызовами `task_create`
- **THEN** вызовы проигрываются завершёнными `tool_call`, после истории — один `plan` со списком и без `_meta.codelab.taskChange`

#### Scenario: Список новой ветки
- **WHEN** ядро публикует `TaskListChanged` с `op: restore` и пустым списком, затем — с `op: restore` и пунктами `#1`, `#4`
- **THEN** клиент получает `plan` с `entries: []`, затем `plan` с двумя entries и `_meta.codelab.task.id` `"1"`, `"4"` (`acp_projection_exhaustive_test.dart`)

#### Scenario: Реплей отклонённого вызова agent
- **WHEN** загружается сессия, где вызов `agent` с `type: "review"` был отклонён проверкой (`description` из двух символов) и записи `subagent` нет
- **THEN** `tool_call` этого вызова при реплее несёт `_meta.codelab.subagent: {"type": "review"}` без `id`, статус — `failed` с текстом ошибки (`acp_projection_exhaustive_test.dart`)

#### Scenario: Вызов agent
- **WHEN** модель вызывает `agent` с типом `explore`, ребёнок делает три вызова и сдаёт отчёт
- **THEN** клиент получает `tool_call` с `kind: think`, title `Subagent explore: …` и `_meta.codelab.subagent` с `id` вида `sub_…` и `type: "explore"`, `in_progress`, хотя бы одну строку прогресса и `completed` с телом отчёта; ни одного `tool_call` с id вызова ребёнка (фикстура `acp/prompt-subagent-tool-call`)

#### Scenario: Итог субагента
- **WHEN** ребёнок `explore` сделал 4 вызова, потратил 15 200 входных и 3 000 выходных токенов за 48 с, затем завершился; во втором варианте ход отменён во время работы ребёнка
- **THEN** финальный `tool_call_update` вызова `agent` содержит `_meta.codelab.subagent.summary` `{"toolCalls": 4, "tokens": {"input": 15200, "output": 3000}, "durationMs": 48000}`; во втором варианте — `status: failed`, `_meta.codelab.outcome: "cancelled"` и `summary` с фактическими значениями; при `session/load` реплей вызова `agent` несёт тот же `summary` из итоговой записи `subagent`

#### Scenario: Отменённый субагент без строки прогресса
- **WHEN** ход отменён, пока ребёнок `explore` работает и клиент уже получил строку прогресса вызова `agent`
- **THEN** финальный `tool_call_update` вызова `agent` содержит `status: failed`, `_meta.codelab.outcome: "cancelled"`, `_meta.codelab.subagent.summary` и `content: []`; отменённый вызов другого инструмента по-прежнему приходит без `content` (design.md, D52 п. 1)

#### Scenario: Реплей отменённого субагента с частичным отчётом
- **WHEN** загружается сессия, где ход был отменён во время работы ребёнка `explore`, и итоговая запись `subagent` ребёнка (`status: cancelled`) несёт частичный отчёт
- **THEN** `tool_call` вызова `agent` при реплее содержит `status: failed`, `_meta.codelab.outcome: "cancelled"`, `_meta.codelab.subagent.summary` и `content: []`, без текста частичного отчёта — как живой кадр (design.md, D53; `codelab_agent_acp`, `session_load_subagent_test.dart`)

#### Scenario: Запрос разрешения ребёнка
- **WHEN** ребёнок `review` просит `exec git diff --stat`, клиент отвечает `reject_once`
- **THEN** кадр `session/request_permission` содержит `sessionId` корня, `toolCallId` `call_1/call_1`, title `[review: …] …` и `_meta.codelab.subagent` с `depth: 1` и `parentToolCallId: "call_1"`; ребёнок продолжает и сдаёт отчёт (фикстура `acp/prompt-subagent-permission`)

#### Scenario: Запрос разрешения внука
- **WHEN** внук глубины 2 просит `exec`
- **THEN** `toolCallId` состоит из трёх сегментов, `_meta.codelab.subagent.depth` — 2, `path` — id ребёнка, `parentToolCallId` — вызов `agent` корня (фикстура `acp/prompt-subagent-nested-permission`)

### Requirement: Шаги потомков деревом
Клиенту, объявившему `clientCapabilities._meta.codelab.subagentToolCalls`, адаптер SHALL отправлять вызовы потомков любой глубины (этап 2, решение пользователя 2026-11-10; design.md change `add-subagents-and-tasks`, D21; §17.3.7):
- `SubagentActivity` с `ToolCallStarted` → `tool_call`; с `ToolCallProgress` → `tool_call_update` с `content`; с `ToolCallFinished` → `tool_call_update` с итоговым `status`, `content`, `diff` и `_meta.codelab.outcome` — по тем же правилам, что у вызовов корня;
- `toolCallId` — цепочка через `/` от вызова `agent` корня (тот же id, что у запроса разрешения этого вызова, SUB-3);
- каждый такой кадр SHALL нести `_meta.codelab.parentToolCallId` — `toolCallId` на проводе вызова `agent`, запустившего потомка;
- финальный `tool_call_update` вложенного вызова `agent` SHALL нести `_meta.codelab.subagent` с `id`, `summary` и, при `failed`, `failure` — как у вызова `agent` корня (D24);
- статус `in_progress` вызова потомка SHALL отправлять тот же хук `markInProgress`, что у корня: ядро передаёт его потомкам с цепочкой (agent-subagents «Сборка ребёнка», D48 п. 1); переход `pending → in_progress → итог` — как у вызова корня (§13.7);
- текст, мысли и прочие события потомков НЕ SHALL отправляться.

Согласием SHALL считаться только значение `clientCapabilities._meta.codelab.subagentToolCalls` — объект с целым `version: 1` (D9). Оно читается у соединения, которое сейчас владеет сессией: после переподключения действует объявление нового соединения (design.md, D47 Т3). Цепочка SHALL строиться из адреса `SubagentActivity` без разбора строк id: у ребёнка префикс — `parentToolCallId` события, у потомка глубже — префикс его родителя, `/` и `parentToolCallId` события (D47 Т2).

Команда потомка через терминал клиента (`terminal/*`) SHALL исполняться так же, как команда корня, независимо от согласия: ожидание показа терминала в вызове не должно зависеть от того, ушёл ли этот вызов клиенту (D47 Т4).

Когда вызов `agent` любого уровня становится терминальным, адаптер SHALL отправить `tool_call_update` со `status: failed` и `_meta.codelab.outcome: "cancelled"` для каждого ещё не завершённого вызова его поддерева, до `tool_call_update` самого вызова `agent`. Кадр закрытия вложенного вызова `agent` SHALL нести `content: []`, который снимает его строку прогресса, как у отменённого вызова `agent` корня (D52 п. 1, D53); кадры прочих закрываемых вызовов `content` НЕ SHALL нести. После этого кадры закрытых вызовов НЕ SHALL отправляться.

При `session/load` такому клиенту реплей SHALL сразу после кадра `tool_call` вызова `agent` проигрывать вызовы потомков из их журналов (по записям `subagent`, рекурсивно) с итоговыми статусами и теми же `toolCallId` и `_meta.codelab.parentToolCallId`. Журналы потомков SHALL читаться без записи на диск и без lease ребёнка (D47 Т5). Вызов потомка без результата в журнале (потомок пережил `cancel_grace`) SHALL проигрываться `failed` с `_meta.codelab.outcome: "cancelled"`, как его закрыл адаптер вживую. Журнал потомка, который не открывается, SHALL давать лог `subagent.replay_failed` и реплей без потомков этого вызова, а не отказ `session/load`. Кадры идущего хода, пришедшие во время реплея, SHALL отправляться после кадров реплея (ACP-3). Клиенту без `subagentToolCalls` ни вживую, ни при реплее вызовы потомков НЕ SHALL отправляться (SUB-12).

#### Scenario: Вызовы ребёнка и внука
- **WHEN** клиент объявил `subagentToolCalls`, ребёнок `general` вызывает `read`, затем запускает внука, внук вызывает `ls`
- **THEN** клиент получает `tool_call` `call_1/call_1` (`read`) с `parentToolCallId: "call_1"`, `tool_call` `call_1/call_2` (`agent`) с `parentToolCallId: "call_1"` и `_meta.codelab.subagent` `{id, type}` внука (как у вызова `agent` корня, D28; Q16) и `tool_call` `call_1/call_2/call_1` (`ls`) с `parentToolCallId: "call_1/call_2"`; финальный `tool_call_update` `call_1/call_2` несёт `_meta.codelab.subagent.summary` внука; текстов потомков нет (фикстура `acp/prompt-subagent-tool-tree`)

#### Scenario: Команда потомка через терминал клиента
- **WHEN** клиент объявил `terminal: true`, ребёнок вызывает `exec`, пользователь отвечает `allow_once`; в первом варианте клиент объявил `subagentToolCalls`, во втором — нет
- **THEN** в обоих вариантах команда исполняется через `terminal/create` и `terminal/wait_for_exit`, ребёнок получает результат и сдаёт отчёт; в первом варианте `tool_call_update` `call_1/call_1` несёт терминал (`{"type": "terminal"}`), во втором кадров вызова ребёнка нет (`codelab_agent_acp`, тест на `server_harness`)

#### Scenario: Позднее событие закрытого вызова
- **WHEN** клиент объявил `subagentToolCalls`, вызов `exec` ребёнка закрыт адаптером при завершении вызова `agent`, после чего мост получает событие этого вызова
- **THEN** кадр для него не отправляется (`codelab_agent_acp`, тест моста)

#### Scenario: Статусы вызова потомка
- **WHEN** клиент объявил `subagentToolCalls`, ребёнок вызывает `read`, не требующий вопроса, затем `exec`, который пользователь разрешает
- **THEN** у `call_1/call_1` кадры `tool_call` (`pending`), `tool_call_update` `in_progress`, итог; у `exec` — `tool_call` (`pending`), `session/request_permission`, после ответа `in_progress`, итог; клиент без согласия кадров `in_progress` с цепочкой не получает (фикстура `acp/prompt-subagent-tool-tree`)

#### Scenario: Запрос разрешения в строке своего вызова
- **WHEN** клиент объявил `subagentToolCalls`, ребёнок вызывает `exec`, требующий вопроса
- **THEN** `tool_call` с id `call_1/call_1` приходит раньше `session/request_permission` с тем же `toolCall.toolCallId`

#### Scenario: Клиент без согласия
- **WHEN** тот же сценарий проигрывается клиенту без `clientCapabilities._meta.codelab.subagentToolCalls`
- **THEN** кадров `tool_call` с id потомков нет, кадры совпадают с `acp/prompt-subagent-tool-call`

#### Scenario: Висящие вызовы при отмене
- **WHEN** ход отменён, а ребёнок не завершил `exec` в пределах `cancel_grace`
- **THEN** до `tool_call_update` вызова `agent` клиент получает `tool_call_update` вызова `exec` ребёнка со `status: failed` и `_meta.codelab.outcome: "cancelled"`; поздних кадров этого вызова после него нет

#### Scenario: Закрытие вложенного agent после строки прогресса
- **WHEN** клиент объявил `subagentToolCalls`, ребёнок вызывает `read` и запускает внука (`call_1/call_2`), внук вызывает `ls`, клиент получил строку прогресса `call_1/call_2`, затем вызов `agent` корня отменяется, пока потомки не завершены
- **THEN** до `tool_call_update` `call_1` клиент получает кадры закрытия со `status: failed` и `_meta.codelab.outcome: "cancelled"`: у `call_1/call_2` — с `content: []`, у `call_1/call_1` и `call_1/call_2/call_1` — без `content` (design.md, D53; `codelab_agent_acp`, `subagent_tool_tree_bridge_test.dart`)

#### Scenario: Реплей дерева
- **WHEN** сессия с вызовом `agent`, у ребёнка которого два вызова, загружается клиентом с `subagentToolCalls`
- **THEN** после `tool_call` вызова `agent` идут два `tool_call` ребёнка с итоговыми статусами и `parentToolCallId` (фикстура `acp/session-load-subagent-tool-tree`: живой ход и `session/load` в том же соединении, D47 Т7; чтение журналов с диска новым процессом — тест ядра на `JsonlSessionStore`); клиент без согласия их не получает

### Requirement: Уведомление `_codelab/session/usage`
Сервер SHALL отправлять уведомление JSON-RPC `_codelab/session/usage` (без `id`) каждому соединению сессии, объявившему `clientCapabilities._meta.codelab.usage` (значение — объект с `version`, равным целому JSON-числу `1`; требование «initialize»), и НЕ SHALL отправлять его остальным соединениям (design.md change `add-usage-extension`, D1, D3). Расширение SHALL соблюдать `15-Extensibility.md` (D17): метод начинается с `_`, это уведомление без `id` (ответа и `-32601` нет), поддержка объявляется только в `_meta` capability-объектов, а стандартные типы ACP (`InitializeResponse`, `AgentCapabilities`, `PromptResponse`, `SessionNotification`) НЕ SHALL получать новых корневых полей и новых значений `sessionUpdate`. Поводы (`trigger`):
- `step` — после каждого `StepEnded` хода;
- `turn` — по `TurnEnded` хода, в котором был хотя бы один `StepEnded`, после последнего `session/update` хода и до ответа на `session/prompt`, при любой причине завершения, включая `cancelled` и сбой `-32603` (ACP-3, ACP-5, ACP-7); `session_info_update` с названием сессии, которое агент даёт после хода, идёт после снимка `turn` (design.md, D19 п. 5);
- `compaction` — после `ContextCompacted`;
- `compactionDiscarded` — после `CompactionDiscarded`: проход сжатия отброшен, но суммаризатор оплачен (требование «Отброшенный проход сжатия в сумме сессии»; change `fix-discarded-compaction-usage`, D5); полей `turnId`, `step` и `turn` у снимка нет;
- `load` — после ответа на `session/load` этому соединению, если в сумме сессии есть хотя бы один шаг (change `add-usage-ledger`, D8): снимок несёт `session` и, если мосту известно заполнение контекста, `context`; полей `turnId`, `step` и `turn` у него нет. То же — после повторного `session/load` уже открытой сессии (`reattach`).

Ход без шагов модели (встроенная команда, отмена до первого запроса) НЕ SHALL давать уведомлений.

Параметры SHALL иметь форму D2: `sessionId`; `seq` — целое, начиная с 1 и строго растущее на каждый снимок в пределах сессии сервера, общее для всех её соединений; `trigger`; `turnId` при `step` и `turn`; `step` (`index`, `model` в виде `<provider>/<id>`, `tokens`, `cost`, `partial`) только при `step`; агрегат `turn` при `step` и `turn`; агрегат `session` всегда; `currency: "USD"`, если в параметрах есть хоть одно `cost`; `context` с целыми `used` и `size` и целым `compactAt` (порог автосжатия; поле отсутствует, если автосжатие выключено), если ядро сообщило заполнение контекста. Агрегат SHALL содержать `tokens` (`input`, `output`, `cacheRead`, `cacheWrite`; `reasoning` — только если сообщён), `steps` (у сессии ещё `turns` — число ходов сессии в сервере, в которых был хотя бы один `StepEnded`, включая текущий), `cost` и `partial` по правилам ниже. `context` снимка `turn` SHALL совпадать с `context` последнего `StepEnded` хода (design.md, D19 п. 3–4).

Значения SHALL считаться так (D4, D6, D9):
- шаг — usage и модель `StepEnded`; ход во время хода — сумма его шагов; ход в конце — `TurnEnded.usage`; сессия — засев из свёртки журнала при загрузке (требование «Полная сумма сессии после session/load»), плюс итоги завершённых ходов этой сессии в сервере, плюс текущий ход, плюс usage суммаризатора из `ContextCompacted.usage` и `CompactionDiscarded.usage` (в агрегат хода он не входит; change `add-usage-ledger`, D4; change `fix-discarded-compaction-usage`, D5);
- стоимость — в целых микродолларах (`round(cost.total × 10⁶)` шага и итога хода, сумма ходов для сессии), на проводе — десятичная строка без хвостовых нулей с не более чем 6 знаками после точки (`"0"` для нуля); `cost` шага SHALL присутствовать всегда, когда у модели шага есть цены (`ModelRef.cost != null`), в том числе при нулевых токенах — тогда `"0"` (причина `noUsage` при этом остаётся); `cost` хода и сессии SHALL присутствовать, если цены есть хотя бы у одной модели их шагов, и отсутствовать, только если цен нет ни у одной (design.md, D6, D20);
- стоимость шага или итога хода, которая не является конечным неотрицательным числом или в микроединицах превышает `2^53 − 1`, SHALL считаться неизвестной ценой: она даёт 0 микроединиц и причину `noPrice` (у шага `cost` нет; у хода с таким итогом `TurnEnded.usage` `cost` нет: итог берётся из ядра и включает детей, поэтому невалидному итогу нельзя доверять ни целиком, ни частично), а ход SHALL продолжаться без ошибки и без исключения в проекции (защита адаптера; цены конфигурации проверяет `agent-configuration` «Цены моделей конфигурации», D20);
- `partial`: `noUsage` — у ответа модели со `stopReason`, отличным от `error`, у которого все счётчики `input`, `output`, `cacheRead` и `cacheWrite` равны нулю; шаг только с кэш-токенами — сообщённый расход, `noUsage` у него нет. В том числе у шага, прерванного отменой (`aborted`), по которому провайдер не сообщил usage. У шага с ошибкой (`error`, в том числе `overflow` проверки перед запросом) `noUsage` не ставится (design.md, D26); `noPrice` — у модели шага нет цен при ненулевых токенах, а у итога хода ещё и когда `TurnEnded.subagentUsage` имеет ненулевые токены при нулевой стоимости (эвристика: цены моделей детей адаптеру не видны); `beforeLoad` агент CodeLab НЕ SHALL ставить: после change `add-usage-ledger` сумма сессии после загрузки полная (D8); значение остаётся в протоколе v1 для других агентов, и клиент его по-прежнему понимает; у суммаризатора `noPrice` — модель ответа без цен в каталоге при ненулевых токенах; у хода и сессии — объединение причин их шагов; у шага `noUsage` и `noPrice` вместе не бывают (`noPrice` требует ненулевых токенов); причины в массиве SHALL идти в порядке `noUsage`, `noPrice`, `beforeLoad`; пустой массив не отправляется (design.md, D19 п. 2).

Уведомление НЕ SHALL нести секретов, текстов сообщений и аргументов инструментов. Каждая отправка SHALL давать debug-запись `acp.usage.sent {session_id, seq, trigger, turn_id?}` без токенов и денег; `turn_id` — при `trigger` `step` и `turn`, у `compaction`, `compactionDiscarded` и `load` его нет (design.md, D14, D20).

#### Scenario: Два шага с ценами
- **WHEN** клиент объявил `usage`, а ход делает два запроса к модели с ценами и заканчивается `end_turn`
- **THEN** кадры совпадают с фикстурой `acp/prompt-usage-steps`: после первого и второго шага — `_codelab/session/usage` с `trigger: "step"` и `seq` 1 и 2 (уже в первом `session.turns` — 1), затем `trigger: "turn"` с `seq` 3, суммой двух шагов в `turn` и `session` и `context` второго шага, затем ответ `stopReason: end_turn`

#### Scenario: Модель без цен и шаг без usage
- **WHEN** у модели сессии нет цен, а scripted-модель отвечает без usage
- **THEN** в снимках нет `cost` и `currency`; `partial` шага с токенами — `["noPrice"]`, шага без usage — `["noUsage"]`, а хода и сессии после обоих шагов — `["noUsage", "noPrice"]` (фикстура `acp/prompt-usage-unpriced`)

#### Scenario: Шаг без usage на модели с ценами
- **WHEN** у модели сессии есть цены, а scripted-модель отвечает успешно без usage
- **THEN** у снимка `step` `cost` — `"0"`, `partial` — `["noUsage"]`, `currency` — `"USD"`; у `turn` и `session` — `cost` `"0"` с `noUsage` (`usage_bridge_test.dart`; design.md, D20 п. 1, п. 9)

#### Scenario: Не конечная стоимость
- **WHEN** usage шага на модели с ценами несёт стоимость `Infinity` (или отрицательную)
- **THEN** снимок `step` уходит без `cost` с `partial: ["noPrice"]`; если невалиден итог `TurnEnded.usage`, у агрегата `turn` снимка `trigger: "turn"` нет `cost`, а `partial` содержит `noPrice`; ход завершается тем же `stopReason`, что без этой стоимости, ошибки `-32603` нет; то же при стоимости `NaN` и при стоимости больше `2^53 − 1` микроединиц (переполнение) (`usage_bridge_test.dart` — `Infinity`, `NaN`, переполнение; `usage_projection_test.dart` — отрицательная цена через ядро; design.md, D20 п. 3, п. 9)

#### Scenario: Отмена посреди инструмента
- **WHEN** клиент отменяет ход, пока `exec` ждёт `terminal/wait_for_exit`
- **THEN** снимок `trigger: "turn"` идёт после `tool_call_update` `failed` с `outcome: "cancelled"` и до ответа `stopReason: cancelled`. Снимок `step` шага, ответ модели которого получен целиком (`stopReason: toolUse` с usage), несёт этот usage без причины `noUsage` (фикстура `acp/prompt-usage-cancelled`; design.md, D19 п. 9, D26)

#### Scenario: Отмена посреди потока без usage провайдера
- **WHEN** клиент объявил `usage`, у модели сессии есть цены, а клиент отменяет ход, пока модель ещё отвечает, и провайдер не прислал usage оборванного потока (шаг `stopReason: aborted`, все счётчики usage нулевые)
- **THEN** у снимка `step` этого шага `partial` — `["noUsage"]`, `cost` — `"0"`; снимок `turn` идёт до ответа `stopReason: cancelled`, и у агрегатов `turn` и `session` `partial` содержит `noUsage` (design.md, D26)

#### Scenario: Отмена посреди потока с частичным usage провайдера
- **WHEN** шаг прерван отменой (`stopReason: aborted`), но провайдер успел сообщить usage с `input > 0`
- **THEN** у снимка `step` нет причины `noUsage`, а токены и стоимость шага берутся из сообщённого usage (design.md, D26)

#### Scenario: Ошибка модели без usage
- **WHEN** запрос к модели завершился ошибкой (`stopReason: error`) с нулевым usage
- **THEN** у снимка `step` этого шага нет причины `noUsage` (design.md, D6, D26)

#### Scenario: Клиент без объявления
- **WHEN** клиент не прислал `clientCapabilities._meta.codelab.usage`
- **THEN** кадров `_codelab/session/usage` нет, остальные кадры совпадают с существующими фикстурами хода (например, `acp/prompt-text-end-turn`)

#### Scenario: Стандартные типы без новых полей
- **WHEN** клиент объявил `usage`, и проходит ход с двумя шагами
- **THEN** ответ `initialize` отличается от фикстуры `acp/initialize-capabilities` только блоком `agentCapabilities._meta.codelab`, кадры `session/update` и ответ `session/prompt` не содержат полей вне схемы `17-Schema.md`, кроме `_meta.codelab.*`, а usage приходит только в `_codelab/session/usage`

#### Scenario: Автосжатие выключено
- **WHEN** у сессии `compaction.enabled: false`, клиент объявил `usage`
- **THEN** `context` в снимках содержит `used` и `size` без `compactAt` (фикстура `acp/prompt-usage-compaction-off`)

#### Scenario: Сессия перешла к новому соединению
- **WHEN** после хода со снимками до `seq` 3 сессию без идущего хода загружает другое соединение, объявившее `usage` (`reattach`: у сессии один владелец, веер кадров на все соединения — после MVP, SESM-15), и отправляет промпт
- **THEN** после ответа на `session/load` новое соединение получает снимок `trigger: "load"` с `seq` 4 и суммой ходов до перехода (change `add-usage-ledger`, D8); снимки нового хода получает только новое соединение, `seq` продолжает счёт сессии сервера без сброса (первый снимок хода — `seq` 5), агрегат `session` включает ходы до перехода, `partial` не содержит `beforeLoad`; прежнее соединение снимков не получает

#### Scenario: Придержанный снимок и соединение без согласия
- **WHEN** соединение, объявившее `usage`, загружает сессию, снимок `_codelab/session/usage` придержан в буфере реплея, соединение рвётся до выпуска буфера, и ту же сессию загружает (`reattach`) соединение без объявления `usage`
- **THEN** новое соединение не получает придержанный кадр `_codelab/session/usage` ни при выпуске буфера, ни позже; придержанные `session/update` реплея оно получает в прежнем порядке (`usage_bridge_test.dart`; design.md, D20 п. 8)

#### Scenario: Субагент на модели без цен
- **WHEN** в ходе вызов `agent` запустил ребёнка, `TurnEnded.subagentUsage` содержит ненулевые токены, а его стоимость равна нулю
- **THEN** у агрегатов `turn` и `session` снимка `trigger: "turn"` `partial` содержит `noPrice` (стоимость детей не оценена)

#### Scenario: Встроенная команда без модели
- **WHEN** клиент, объявивший `usage`, отправляет встроенную команду `/status`
- **THEN** кадров `_codelab/session/usage` нет: модель не вызывалась (`usage_projection_test.dart`); то же для `/usage` и `/usage rebuild` (фикстура `acp/slash-usage`; change `add-usage-ledger`, D5)

#### Scenario: Сжатие контекста
- **WHEN** после хода клиент отправляет `/compact`, и сжатие записано
- **THEN** приходит `_codelab/session/usage` с `trigger: "compaction"`, без `turnId`, `step` и `turn`, с `context.used`, меньшим, чем в последнем снимке хода (`usage_projection_test.dart`), и `size`, `compactAt` последнего `StepEnded`; относительно чанка отчёта «Compacted…» порядок не фиксирован (фикстура `acp/compact-usage-context`)

#### Scenario: Сессия после загрузки
- **WHEN** сессию с двумя ходами с ответами модели в журнале загружают через `session/load` в новом сервере, клиент объявил `usage`, затем отправляет промпт
- **THEN** после реплея и ответа на `session/load` приходит снимок `trigger: "load"` с `session.turns: 2`, суммой токенов и стоимости двух ходов журнала и без `beforeLoad`; снимки нового хода продолжают эту сумму (`session.turns: 3`) (фикстура `acp/session-load-usage-full`; change `add-usage-ledger`, D8)

#### Scenario: Загрузка сессии без шагов
- **WHEN** загружают сессию, в журнале которой нет ни одного ответа модели
- **THEN** снимка `trigger: "load"` нет (`usage_projection_test.dart`)

#### Scenario: Загрузка соединением без объявления
- **WHEN** сессию с ответами модели загружает соединение без `clientCapabilities._meta.codelab.usage`
- **THEN** кадров `_codelab/session/usage` нет, ответ `session/load` и реплей не меняются

#### Scenario: Суммаризатор в сумме сессии
- **WHEN** клиент объявил `usage`, после хода приходит `/compact`, и суммаризатор ответил с usage на модели с ценами
- **THEN** снимок `trigger: "compaction"` несёт `session` с токенами и стоимостью суммаризатора сверх итогов ходов, `session.steps` и `session.turns` не меняются (фикстура `acp/compact-usage-summary`; change `add-usage-ledger`, D4)

### Requirement: Запрос `_codelab/session/usage/ledger`
Сервер SHALL принимать запрос JSON-RPC `_codelab/session/usage/ledger` (клиент → агент, с `id`) с параметрами `sessionId` (строка) и необязательным `rebuild` (логическое, по умолчанию `false`); неизвестные поля параметров SHALL игнорироваться (design.md change `add-usage-ledger`, D6). Расширение SHALL соблюдать раздел «Custom Requests» `15-Extensibility.md`: имя с `_`, ответ с тем же `id`, поддержка объявлена ключом `usageLedger` блока `initialize`.

Сессия ищется среди открытых в сервере тем же способом, что у `session/prompt`; незнакомый `sessionId` SHALL давать `-32002` «Session not found»; неверные типы параметров — `-32602`. Путь к файлам журнала из параметров НЕ SHALL строиться.

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

### Requirement: Полная сумма сессии после session/load
Когда `session/load` открывает сессию в сервере (моста сессии ещё нет), адаптер SHALL засевать агрегаты usage сессии сервера отчётом журнала usage, построенным в памяти без чтения и записи `usage.json` (design.md change `add-usage-ledger`, D8): итоги ходов, число ходов и шагов, причины `noUsage` и `noPrice`, usage субагентов и суммаризатора. Сразу после засева агрегат `session` снимка SHALL совпадать с `total` ответа `_codelab/session/usage/ledger` по `tokens`, `cost`, `turns`, `steps` и `partial`. Засев SHALL давать debug-запись `acp.usage.seeded {session_id, turns, steps, duration_ms}`. Повторный `session/load` открытой сессии (`reattach`) агрегаты НЕ SHALL пересевать.

#### Scenario: Засев равен журналу
- **WHEN** сессию с тремя ходами, субагентом и сжатием с usage суммаризатора загружают в новом сервере, а клиент сразу запрашивает журнал
- **THEN** `session` снимка `trigger: "load"` и `total` ответа журнала равны по токенам, стоимости, `turns`, `steps` и `partial` (`usage_ledger_seed_test.dart`)

#### Scenario: Reattach без пересева
- **WHEN** открытую сессию загружает другое соединение
- **THEN** сумма и `seq` продолжаются, ходы не удваиваются

### Requirement: Отброшенный проход сжатия в сумме сессии
На событие `CompactionDiscarded` адаптер SHALL добавлять его `usage` в сумму сессии сервера (не в ход) по тому же правилу цены, что для `ContextCompacted.usage`: `noPrice` — модель ответа без цен в каталоге сессии при ненулевых токенах (требование «Уведомление `_codelab/session/usage`» change `add-usage-ledger`; design.md change `fix-discarded-compaction-usage`, D5).

Соединениям, объявившим `usage`, адаптер SHALL отправлять снимок `_codelab/session/usage` с `trigger: "compactionDiscarded"` (решение пользователя Q4 (а)). Снимок:
- без `turnId`, `step` и `turn`;
- с `session`, включающим вызов;
- с `context`, если мосту известно заполнение: `used` — `tokensBefore` события, `size` и `compactAt` — последнего `StepEnded`;
- с `seq` по общему правилу;
- с debug-записью `acp.usage.sent`.

Снимок SHALL отправляться и при нулевом usage вызова; сумма тогда не растёт, причины `noUsage` у суммаризатора нет — как у записанного сжатия (design.md, R8). Снимок и сообщение агента `/compact` идут в любом порядке, оба SHALL предшествовать ответу на `session/prompt`. Стандартные типы ACP новых полей и значений НЕ SHALL получать. Кадров `session/update` событие НЕ SHALL давать.

В ответе `_codelab/session/usage/ledger` объект `summaries` SHALL содержать целое `discarded` — число отброшенных вызовов, только при ненулевом значении. `usageLedger.version` остаётся `1` (правило совместимости D6 change `add-usage-ledger`; решение пользователя Q2 (а)). Засев на `session/load` SHALL включать отброшенные вызовы из свёртки, и инвариант «сразу после засева `session` равен `total` ответа журнала» (требование «Полная сумма сессии после session/load» change `add-usage-ledger`) SHALL сохраняться.

#### Scenario: /compact без выигрыша в живой сумме
- **WHEN** клиент объявил `usage`, после хода с одним шагом приходит `/compact`, и проход отброшен по CMP-10 с usage суммаризатора на модели с ценами
- **THEN** приходит `_codelab/session/usage` с `trigger: "compactionDiscarded"`, `session` с токенами и стоимостью суммаризатора сверх итога хода, прежними `session.turns` и `session.steps` и `context.used`, равным `used` последнего снимка хода; снимок и `agent_message_chunk` `Nothing to compact.` — в любом порядке, затем ответ `end_turn` (фикстура `acp/compact-no-gain-usage`; `usage_bridge_test.dart`)

#### Scenario: Журнал после отброшенного прохода
- **WHEN** после этого клиент запрашивает `_codelab/session/usage/ledger`
- **THEN** `summaries.count` — 1, `summaries.discarded` — 1, а `total` по `tokens`, `cost` и `partial` совпадает с `session` последнего снимка (фикстура `acp/compact-no-gain-usage`)

#### Scenario: Сумма после session/load
- **WHEN** сессию с ходом и отброшенным проходом загружают в новом сервере, клиент объявил `usage`
- **THEN** снимок `trigger: "load"` несёт `session` с usage суммаризатора, равный `total` ответа журнала; сумма не меньше той, что была в живой сессии до перезапуска (`usage_projection_test.dart`)

#### Scenario: Клиент без объявления
- **WHEN** проход отброшен, а клиент не объявил `usage`
- **THEN** кадров `_codelab/session/usage` нет, остальные кадры `/compact` не меняются

#### Scenario: Записанное сжатие без изменений
- **WHEN** проход сжатия записан
- **THEN** снимок — `trigger: "compaction"`, как до change, снимка `compactionDiscarded` нет

### Requirement: Бюджет хода в уведомлении `_codelab/session/usage`
Снимки `_codelab/session/usage` с поводом `step` и `turn` SHALL нести необязательное поле `budget`, если у хода задан хотя бы один из лимитов `budget.max_tokens`, `budget.max_cost`, `budget.max_duration` (design.md change `add-desktop-usage-pane`, D7, Q5; правило совместимости D2 change `add-usage-extension`: новое необязательное поле — без смены версии `usage`). Без таких лимитов поля НЕ SHALL быть; в снимках `compaction`, `compactionDiscarded` (change `fix-discarded-compaction-usage`) и `load` его НЕ SHALL быть.

Состав (значения — из прогресса бюджета `StepEnded` и `TurnEnded`, требование agent-loop «Прогресс бюджета хода в событиях шага и хода»):
- `steps` — `{"used": <целое>, "limit": <целое>}`, всегда при наличии поля;
- `tokens` — `{"used": <целое>, "limit": <целое>}`, только при заданном `max_tokens`;
- `cost` — `{"used": "<десятичная строка>", "limit": "<десятичная строка>"}`, только при заданном `max_cost`; строки — по правилу денег D9 change `add-usage-extension` из целых микродолларов (`limit` — `round(max_cost × 10⁶)`); `used` отсутствует, если у текущей модели нет цен; при наличии `budget.cost` снимок SHALL нести `currency`;
- `duration` — `{"usedMs": <целое>, "limitMs": <целое>}`, только при заданном `max_duration`.

Невалидный `max_cost` — NaN, бесконечность, отрицательное число или сумма, не представимая целыми микродолларами, — SHALL давать `budget` без подполя `cost`; если других необязательных лимитов (`tokens`, `duration`) нет, поля `budget` НЕ SHALL быть. Снимок при этом SHALL уходить.

Объявление `usage: {"version": 1}`, правила `seq`, порядка и адресатов уведомления (требование «Уведомление `_codelab/session/usage`») НЕ SHALL меняться. Клиент, не знающий поля, его игнорирует.

#### Scenario: Бюджет в снимках хода
- **WHEN** клиент объявил `usage`, конфигурация задаёт `budget.max_tokens: 200000` и `budget.max_cost: 0.5`, и ход идёт два шага на модели с ценами
- **THEN** оба снимка `step` и снимок `turn` несут `budget` с `steps`, `tokens` и `cost`, без `duration`; `steps.used` — 1, 2 и 2 (фикстура `acp/prompt-usage-budget`)

#### Scenario: Без лимитов кроме шагов
- **WHEN** конфигурация задаёт только `budget.max_steps`
- **THEN** снимки `step` и `turn` не несут `budget` (фикстуры `acp/prompt-usage-steps` и другие usage-фикстуры не меняются)

#### Scenario: Лимит стоимости на модели без цен
- **WHEN** задан `budget.max_cost: 0.5`, а модель без цен
- **THEN** `budget.cost` — `{"limit": "0.5"}` без `used`, снимок несёт `currency` `USD`

#### Scenario: Снимок сжатия
- **WHEN** после хода с лимитами идёт фоновое сжатие, или проход сжатия отброшен после оплаченного вызова суммаризатора
- **THEN** снимок `compaction` или `compactionDiscarded` не несёт `budget`

#### Scenario: Невалидный лимит стоимости
- **WHEN** `max_cost` — NaN, а `max_tokens` задан
- **THEN** снимки `step` и `turn` несут `budget` с `steps` и `tokens` без `cost`; при одном NaN `max_cost` без других необязательных лимитов поля `budget` нет

