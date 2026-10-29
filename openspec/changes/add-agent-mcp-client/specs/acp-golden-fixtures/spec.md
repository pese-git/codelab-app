## MODIFIED Requirements

### Requirement: Формат golden-фикстуры ACP
Golden-фикстура ACP SHALL быть JSON-файлом `packages/dart/codelab_acp_testing/fixtures/acp/<имя>.json` (каталог плоский, без подкаталогов групп) с id `acp/<имя>`. Фикстура SHALL содержать `id`, непустой `spec`, `description`, `setup` и `frames` и МОЖЕТ содержать `goals`, `extensions`, `roles`, `llm`, `normalize`, `after`. Кадр SHALL иметь направление `dir` (`c2a` или `a2c`) и `frame` либо `unordered`; МОЖЕТ иметь `note`, `optional`, `repeat` и `match`. Поле `roles` SHALL принимать подмножество `["agent", "client"]` и по умолчанию равно обоим. Формат SHALL быть описан в `fixtures/acp/_schema.json` (JSON Schema draft 2020-12, без дополнительных свойств на верхнем уровне, в `setup` и в кадре).

`setup.sessions` МОЖЕТ задавать журналы сессий до сценария (id сессии → записи журнала, первая — заголовок `session`, §8.2) — состояние, которого не получить кадрами, например прерванный ход; его читает только агентский прогон, а `${cwd}` в записях подставляется. Шаг scripted-модели с `waitForCancel` и `reply` SHALL сначала отдавать блоки ответа, затем ждать отмены — так фикстура выражает отмену посреди стрима (design.md change `add-dart-agent-acp-server`, D15).

`setup.transport` МОЖЕТ задавать транспорт сценария (design.md change `add-codelab-agent-binary`, D8): `{"kind": "stdio"}` или `{"kind": "ws", "attempts": [...]}`, где попытка — `{"authorization": "none" | "wrong" | "valid", "expectStatus": <HTTP-код>}`; попытки играются по порядку до основного подключения, основное — с верным токеном. Значение `{"$repeat": {"text": "<s>", "times": <n>}}` в кадре SHALL означать строку `<s>`, повторённую `<n>` раз: в кадре `c2a` она материализуется до отправки, в кадре `a2c` сравнивается как точная строка.

`setup.mcp` МОЖЕТ задавать fake MCP-серверы сценария (design.md change `add-agent-mcp-client`, D15): имя сервера → `{"era"?: "modern" | "legacy", "tools": [...], "results": {"<инструмент>": <CallToolResult>}}`, по умолчанию `modern`. Сервер выбирается по `name` из `mcpServers` кадра; `command` и `url` кадра игнорируются. `after.mcpCalls` МОЖЕТ задавать точный список полученных сервером вызовов: имя сервера → `[{"name", "arguments"}]`, пустой список означает «сервер вызова не получил». Оба ключа читает только агентский прогон: драйвер отдаёт их фабрике агента, а `after.mcpCalls` проверяет `AgentUnderTest.verify()`.

#### Scenario: Полная фикстура загружается
- **WHEN** загрузчик читает фикстуру со всеми обязательными полями
- **THEN** он возвращает типизированную модель с `roles` по умолчанию `["agent", "client"]`

#### Scenario: Неполная фикстура падает громко
- **WHEN** у фикстуры нет обязательного поля, `id` не совпадает с именем файла, есть неизвестный ключ или недопустимое значение `dir`
- **THEN** загрузка падает с сообщением, где указаны файл и путь поля

#### Scenario: Схема и загрузчик согласованы
- **WHEN** запускается тест согласованности
- **THEN** множества ключей, которые принимает загрузчик, совпадают со свойствами `_schema.json`, включая `setup.mcp` и `after.mcpCalls`

#### Scenario: Журнал до сценария
- **WHEN** фикстура `acp/session-load-interrupted-turn` задаёт в `setup.sessions` журнал, который кончается вызовом без результата
- **THEN** агентский прогон кладёт журнал в хранилище агента до первого кадра, а `session/load` показывает вызов `failed` с `outcome: "interrupted"`

#### Scenario: Генератор длинной строки
- **WHEN** кадр `c2a` содержит `{"$repeat": {"text": "x", "times": 2097152}}` в тексте промпта
- **THEN** драйвер отправляет строку из 2 097 152 символов `x`, а фикстура остаётся читаемой

#### Scenario: Лишний вызов MCP-сервера
- **WHEN** фикстура задаёт `after.mcpCalls: {"fake": []}`, а агент вызвал `tools/call` сервера `fake`
- **THEN** проверка `verify()` падает и называет сервер и вызов

## ADDED Requirements

### Requirement: MCP-фикстуры этапа 8
Корпус SHALL содержать фикстуры MCP с ролью `agent`, каждая со ссылкой `spec` на `03-Session Setup.md#mcp-servers` и, где есть вызов, на `08-Tool Calls.md` (design.md change `add-agent-mcp-client`, D15):
- `acp/session-new-with-mcp` (R-24);
- `acp/mcp-tool-permission` (P-01);
- `acp/mcp-stdio-tool-call` (E-02);
- `acp/mcp-http-tool-call` (E-03);
- `acp/mcp-result-fenced` (P-16);
- `acp/set-mode-plan-rejects-mcp-write` (P-01).

Ожидаемый кадр `acp/initialize-capabilities` SHALL содержать `mcpCapabilities: {"http": true, "sse": false}` со ссылкой `02-Initialization.md#mcp-capabilities`. Агентский прогон этих фикстур SHALL проходить HTTP-сервер через настоящий `StreamableHttpTransport` на `MockClient`.

#### Scenario: Разрешение до сервера
- **WHEN** агентский драйвер проигрывает `acp/mcp-tool-permission`
- **THEN** `session/request_permission` приходит до любого вызова fake-сервера, после `reject_once` `after.mcpCalls.fake` пуст, ход заканчивается `end_turn`

#### Scenario: Вызов stdio-сервера
- **WHEN** агентский драйвер проигрывает `acp/mcp-stdio-tool-call`
- **THEN** после одобрения `tool_call_update` — `completed` с текстом `hi` внутри ограды `source="mcp__fake__echo"`, `after.mcpCalls.fake` — один вызов `echo {"text":"hi"}`

#### Scenario: HTTP-сервер и пропуск SSE
- **WHEN** агентский драйвер проигрывает `acp/mcp-http-tool-call`
- **THEN** сессия создана, серверы `sse` и неизвестного типа пропущены, вызов `mcp__web__search` — `completed`

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер получает MCP-фикстуру
- **THEN** он её пропускает с причиной «роль только agent»
