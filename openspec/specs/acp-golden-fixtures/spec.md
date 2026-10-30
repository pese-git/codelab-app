# acp-golden-fixtures Specification

## Purpose
Корпус golden-фикстур ACP закрепляет прочтение спецификации ACP в исполняемом виде: одна фикстура — один сценарий кадров с направлением и ссылкой на раздел `docs/protocols/acp/protocol/*`. Один корпус проверяет и клиентов CodeLab (драйвер играет роль агента), и Dart-агента (с этапа 4). Формат и алгоритмы — `docs/architecture/proposals/agent-core/14-golden-fixtures.md`.
## Requirements
### Requirement: Формат golden-фикстуры ACP
Golden-фикстура ACP SHALL быть JSON-файлом `packages/dart/codelab_acp_testing/fixtures/acp/<имя>.json` (каталог плоский, без подкаталогов групп) с id `acp/<имя>`. Фикстура SHALL содержать `id`, непустой `spec`, `description`, `setup` и `frames` и МОЖЕТ содержать `goals`, `extensions`, `roles`, `llm`, `normalize`, `after`. Кадр SHALL иметь направление `dir` (`c2a` или `a2c`) и `frame` либо `unordered`; МОЖЕТ иметь `note`, `optional`, `repeat` и `match`. Поле `roles` SHALL принимать подмножество `["agent", "client"]` и по умолчанию равно обоим. Формат SHALL быть описан в `fixtures/acp/_schema.json` (JSON Schema draft 2020-12, без дополнительных свойств на верхнем уровне, в `setup` и в кадре).

`setup.sessions` МОЖЕТ задавать журналы сессий до сценария (id сессии → записи журнала, первая — заголовок `session`, §8.2) — состояние, которого не получить кадрами, например прерванный ход; его читает только агентский прогон, а `${cwd}` в записях подставляется. Шаг scripted-модели с `waitForCancel` и `reply` SHALL сначала отдавать блоки ответа, затем ждать отмены — так фикстура выражает отмену посреди стрима (design.md change `add-dart-agent-acp-server`, D15).

`setup.transport` МОЖЕТ задавать транспорт сценария (design.md change `add-codelab-agent-binary`, D8): `{"kind": "stdio"}` или `{"kind": "ws", "attempts": [...]}`, где попытка — `{"authorization": "none" | "wrong" | "valid", "expectStatus": <HTTP-код>}`; попытки играются по порядку до основного подключения, основное — с верным токеном. Значение `{"$repeat": {"text": "<s>", "times": <n>}}` в кадре SHALL означать строку `<s>`, повторённую `<n>` раз: в кадре `c2a` она материализуется до отправки, в кадре `a2c` сравнивается как точная строка.

`setup.mcp` МОЖЕТ задавать fake MCP-серверы сценария (design.md change `add-agent-mcp-client`, D15): имя сервера → `{"era"?: "modern" | "legacy", "tools": [...], "results": {"<инструмент>": <CallToolResult>}}`, эпоха по умолчанию `modern`. Fake-сервер для элемента `mcpServers` кадра SHALL выбираться строго, без отката на единственный сервер: stdio — по `name` (`command` игнорируется); http — по первой метке хоста `url` вида `https://<имя>.mcp.test/mcp`. `after.mcpCalls` МОЖЕТ задавать точный список полученных сервером вызовов: имя сервера → `[{"name", "arguments"}]`, пустой список означает «сервер вызова не получил». Оба ключа читает только агентский прогон: драйвер отдаёт их фабрике агента, а `after.mcpCalls` проверяет `AgentUnderTest.verify()`.

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

### Requirement: Нормализация и сравнение кадров
Перед сравнением ожидаемый и фактический кадры SHALL проходить одинаковую нормализацию: подстановку `${cwd}`, `${sessionId}` и переменных `$capture`, замену времени на `<ts>` там, где он ожидается, замену префикса `cwd` на `${cwd}` и разделителей путей на `/`, правила `normalize` фикстуры. Сравнение SHALL быть точным: лишний ключ в фактическом кадре — расхождение, порядок ключей не важен, порядок массивов важен, кроме `unordered`. Матчеры `$any`, `$absent`, `$capture`, `$regex`, `$contains`, `$partial`, `$oneOf`, `$text` SHALL ослаблять сравнение только в своём месте; `_meta` SHALL сравниваться как `$partial`. Расхождение SHALL сообщаться с путём JSON, ожидаемым и фактическим значением.

#### Scenario: Лишний ключ в кадре
- **WHEN** фактический кадр содержит ключ, которого нет в ожидаемом, вне `_meta` и вне `$partial`
- **THEN** сравнение сообщает расхождение с путём этого ключа

#### Scenario: Захват id запроса агента
- **WHEN** ожидаемый кадр `session/request_permission` содержит `"id": {"$capture": "permId"}`, а следующий кадр ответа — `"id": "${permId}"`
- **THEN** ответ клиента сравнивается с фактическим id запроса, а не с литералом

#### Scenario: Мутация кадра ловится
- **WHEN** в фактическом кадре меняется значение статуса, порядок элементов массива или добавляется ключ
- **THEN** каждая мутация даёт провал с понятным diff

### Requirement: Инварианты корпуса фикстур
Корпус SHALL соблюдать инварианты: каждая ссылка `spec` указывает на существующий файл и якорь в `docs/protocols/acp/protocol/` (FIX-1); фикстура без `extensions` не содержит `_meta.codelab`, `data.codelab` и методов `_codelab/*` (FIX-4); каждый вид `sessionUpdate` из `codelab_acp_protocol` и каждый метод из `acp_method_codec.dart` встречается хотя бы в одной фикстуре с ролью `client`, кроме элементов явного списка ожидаемого покрытия (FIX-2, клиентская часть); каждый метод клиент → агент и каждый вид `sessionUpdate`, который отправляет агент, встречается хотя бы в одной фикстуре с ролью `agent`, кроме элементов отдельного списка ожидаемого покрытия агента (FIX-2, агентская часть; design.md change `add-dart-agent-acp-server`, D8). Оба списка ожидаемого покрытия SHALL только сокращаться.

#### Scenario: Битая ссылка на спецификацию
- **WHEN** `spec` фикстуры ссылается на несуществующий файл или якорь
- **THEN** тест загрузки корпуса падает и называет фикстуру и ссылку

#### Scenario: Расширение без объявления
- **WHEN** фикстура без `extensions` содержит `_meta.codelab`
- **THEN** тест загрузки корпуса падает

#### Scenario: Покрытие расширилось
- **WHEN** элемент из списка ожидаемого покрытия начинает встречаться в фикстуре с ролью `client`
- **THEN** тест покрытия падает и требует убрать элемент из списка

#### Scenario: Метод без агентской фикстуры
- **WHEN** в `acp_method_codec.dart` есть метод клиент → агент, которого нет ни в одной фикстуре с ролью `agent` и в списке ожидаемого покрытия агента
- **THEN** тест покрытия падает и называет метод

### Requirement: Клиентский драйвер фикстур
`codelab_acp_testing` SHALL предоставлять драйвер, который проигрывает фикстуру с ролью `client` против клиента на `FakeAcpTransport`: кадры `a2c` подаются клиенту, кадры `c2a` ожидаются в отправленных клиентом сообщениях (таймаут 5 с) и сравниваются после нормализации. Действия пользователя, которые порождают кадры `c2a`, SHALL выполняться тестом через хук до ожидания кадра. Запросы `fs/*` клиент SHALL обслуживать из файлов `setup.files`, запросы `terminal/*` — по сценарию `setup.terminal` через fake-порты клиента. Фикстура без роли `client` SHALL пропускаться с указанием причины.

#### Scenario: Сценарий разрешения
- **WHEN** драйвер проигрывает `acp/prompt-tool-permission-allow`, а тест в хуке выбирает «разрешить один раз»
- **THEN** ответ клиента на `session/request_permission` совпадает с ожидаемым кадром, и ход завершается кадром ответа `session/prompt`

#### Scenario: Чтение файла клиентом
- **WHEN** драйвер проигрывает `acp/tool-read-range` с файлом в `setup.files`
- **THEN** ответ клиента на `fs/read_text_file` содержит запрошенный диапазон строк этого файла

#### Scenario: Фикстура только для агента
- **WHEN** у фикстуры `roles` равно `["agent"]`
- **THEN** клиентский драйвер её пропускает и сообщает причину

### Requirement: Правила изменения фикстур
Новая фикстура и изменение ожидаемых кадров SHALL сопровождаться ссылкой `spec` на раздел спецификации ACP, который обосновывает кадр. Изменение ожидаемого кадра под поведение реализации без такой ссылки НЕ SHALL допускаться. Расхождение клиента со спецификацией, найденное фикстурой, SHALL исправляться в клиенте отдельным change, а не в фикстуре.

#### Scenario: Расхождение клиента
- **WHEN** клиентский прогон фикстуры падает, а кадр фикстуры соответствует разделу спецификации из `spec`
- **THEN** фикстура не меняется, а исправление клиента оформляется отдельным OpenSpec change

### Requirement: Агентский драйвер фикстур
`codelab_acp_testing` SHALL предоставлять драйвер `runAgentFixture(fixture, startAgent)`, который проигрывает фикстуру с ролью `agent` против агента по алгоритму §14.9 документа ядра:
- агент поднимается фабрикой теста на агентском конце пары транспортов в памяти (`InProcessAcpLink`, тестовая копия в `codelab_acp_testing`, design.md change `add-dart-agent-acp-server`, D9) с `ScriptedStreamFunction` из блока `llm`, `FakeClock` и `SequentialIdGenerator`;
- файлы и команды агент получает через ACP: кадры `fs/*` и `terminal/*` — часть фикстуры, ответы клиента берутся из её кадров `c2a`; `setup.files` пишутся во временный `cwd` только для локального листинга;
- кадры `c2a` отправляются агенту, кадры `a2c` ожидаются (таймаут 5 с) и сравниваются после нормализации с матчерами `repeat`, `optional`, `unordered`;
- после последнего кадра 200 мс тишины: лишний кадр или лишний запрос агента — провал;
- все шаги scripted-модели использованы, лишних запросов нет; `after.files` сверяются с последним `fs/write_text_file`.

Драйвер НЕ SHALL зависеть от пакетов агента. Фикстура без роли `agent` и фикстура с `setup.transport` SHALL пропускаться с указанием причины: транспортные фикстуры играет транспортный драйвер. Скрипт `melos run conformance:agent` SHALL входить в `melos run check`.

#### Scenario: Ход с разрешением
- **WHEN** драйвер проигрывает `acp/prompt-tool-permission-allow` против `AcpAgentServer`
- **THEN** запрос `session/request_permission` агента совпадает с ожидаемым кадром, ответ клиента из фикстуры приводит к `tool_call_update` `completed` и ответу `end_turn`

#### Scenario: Лишний кадр агента
- **WHEN** агент после последнего ожидаемого кадра отправляет ещё одно уведомление
- **THEN** драйвер падает и показывает лишний кадр

#### Scenario: Фикстура только для клиента
- **WHEN** у фикстуры `roles` равно `["client"]`
- **THEN** агентский драйвер её пропускает и сообщает причину

#### Scenario: Транспортная фикстура в памяти
- **WHEN** агентский драйвер получает `acp/stdio-framing-large-line`
- **THEN** он её пропускает и сообщает, что её играет транспортный драйвер

### Requirement: Транспортный драйвер фикстур
Фикстуры с `setup.transport` SHALL проигрываться транспортным драйвером `apps/codelab_agent/test/transport_conformance_test.dart` против процесса бинаря: `dart run bin/codelab_agent.dart serve --stdio` или `serve --ws --port 0` со сценарием из блока `llm` фикстуры. Кадры SHALL идти через настоящий stdio или WebSocket и сравниваться тем же алгоритмом, что у агентского драйвера (нормализация, матчеры, 200 мс тишины). Для `ws` попытки `attempts` SHALL проверять HTTP-статус отказа до основного подключения. Корпус этапа 4 SHALL содержать транспортные фикстуры `acp/stdio-framing-large-line` и `acp/ws-auth-bearer-required` с ролью `agent`.

#### Scenario: Большая строка по stdio
- **WHEN** транспортный драйвер проигрывает `acp/stdio-framing-large-line`
- **THEN** промпт из 2 МиБ одной строкой доходит до агента целиком, а `tool_call` с 2 МиБ в `rawInput`, `fs/write_text_file` и `diff` той же длины приходят каждый одной строкой stdout

#### Scenario: Bearer обязателен
- **WHEN** транспортный драйвер проигрывает `acp/ws-auth-bearer-required`
- **THEN** попытки без токена и с неверным токеном получают `401`, а подключение с верным токеном проходит `initialize`

### Requirement: Агент-повторитель фикстуры
`codelab_acp_testing` SHALL предоставлять `FixtureReplayAgent` — агента для проверки драйверов фикстур без настоящего агента. Для фикстуры он SHALL отвечать на кадры клиента ожидаемыми кадрами агента самой фикстуры в порядке корпуса, подставляя значения, захваченные из кадров клиента (id запросов), и SHALL быть доступен в процессе (`AcpTransport`) и как stdio-процесс (`dart <файл>` из сгенерированного исходника, как scripted stdio-агент). Кадр клиента, которого фикстура не ожидает, SHALL давать JSON-RPC ошибку `-32600` с текстом расхождения. `FixtureReplayAgent` используется только тестами.

#### Scenario: Фикстура проходит против повторителя
- **WHEN** агентский драйвер проигрывает фикстуру с ролью `agent` против `FixtureReplayAgent` той же фикстуры
- **THEN** результат — `PASS`

#### Scenario: Испорченная фикстура
- **WHEN** у копии фикстуры, которую проигрывает драйвер, изменён ожидаемый кадр агента, а повторитель играет исходную фикстуру
- **THEN** драйвер сообщает расхождение с диффом кадров

### Requirement: MCP-фикстуры этапа 8
Корпус SHALL содержать фикстуры MCP с ролью `agent`, каждая со ссылкой `spec` на `03-Session Setup.md#mcp-servers` и, где есть вызов, на `08-Tool Calls.md` (design.md change `add-agent-mcp-client`, D15):
- `acp/session-new-with-mcp` (R-24);
- `acp/mcp-tool-permission` (P-01);
- `acp/mcp-stdio-tool-call` (E-02);
- `acp/mcp-http-tool-call` (E-03);
- `acp/mcp-result-fenced` (P-16);
- `acp/set-mode-plan-rejects-mcp-write` (P-01).

Ожидаемые кадры `initialize` в `acp/initialize-capabilities`, `acp/session-new-modes-config` и `acp/set-config-option-model` SHALL содержать ссылку `02-Initialization.md#mcp-capabilities` и `mcpCapabilities: {"http": true, "sse": false}`: фабрика агентского прогона собирает ядро с транспортами `stdio` и `http`, как бинарь `serve --stdio`. Агентский прогон этих фикстур SHALL проходить HTTP-сервер через настоящий `StreamableHttpTransport` на `MockClient` (dev-зависимость `http` у `codelab_agent_acp`). `acp/mcp-http-tool-call` — шестая MCP-фикстура: сервер `web` типа `http` (modern, `url` `https://web.mcp.test/mcp`), `old` типа `sse` и `future` неизвестного типа `websocket`.

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

### Requirement: Фикстуры файлов проекта этапа 8
Корпус SHALL содержать фикстуры с ролью `agent` и ссылками `spec` на `14-Slash Commands.md` и `13-Session Config Options.md` (design.md change `add-agent-project-files`, D15):
- `acp/prompt-template-command` (E-07) — шаблон `.codelab/prompts/review.md` доверенного проекта; `available_commands_update` после `session/new` содержит `review` с `input.hint`; `session/prompt` с `/review lib/parser "error handling"` — scripted-модель получает развёрнутый текст; после `session/load` реплей содержит `user_message_chunk` с исходной командой;
- `acp/available-commands-no-tools` (R-07, часть шаблонов) — встроенные инструменты, fake MCP-сервер с `echo` и один шаблон; список команд — только шаблон;
- `acp/set-config-option-agent` (R-15) — `.codelab/agents/reviewer.md` с многострочным `tools`; `configOptions` содержит `agent`; `session/set_config_option` с `agent: reviewer` даёт `current_mode_update`, ответ с согласованными `agent`, `model`, `mode`; следующий запрос к модели содержит только схемы из списка.

Файлы сценария SHALL задаваться `setup.files`; формат фикстур НЕ SHALL меняться. Фабрика агентского прогона `codelab_agent_acp` SHALL подключать `ProjectFilesLoader` с временным `CODELAB_HOME` и принимать в `setup.config` ключ `trusted_projects` с подстановкой `${cwd}`; другой неизвестный ключ — по-прежнему громкий провал.

#### Scenario: Команда шаблона
- **WHEN** агентский драйвер проигрывает `acp/prompt-template-command`
- **THEN** кадры совпадают с фикстурой, scripted-модель получила развёрнутый текст

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер получает одну из этих фикстур
- **THEN** он её пропускает с причиной «роль только agent»

