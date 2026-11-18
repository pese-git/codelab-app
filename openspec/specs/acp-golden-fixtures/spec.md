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
- агент поднимается фабрикой теста на агентском конце пары транспортов в памяти (`InProcessAcpLink` из основного бареля `codelab_acp_transports`; design.md change `add-in-process-acp-transport`, D5) с `ScriptedStreamFunction` из блока `llm`, `FakeClock` и `SequentialIdGenerator`;
- файлы и команды агент получает через ACP: кадры `fs/*` и `terminal/*` — часть фикстуры, ответы клиента берутся из её кадров `c2a`; `setup.files` пишутся во временный `cwd` только для локального листинга;
- кадры `c2a` отправляются агенту, кадры `a2c` ожидаются (таймаут 5 с) и сравниваются после нормализации с матчерами `repeat`, `optional`, `unordered`;
- после последнего кадра 200 мс тишины: лишний кадр или лишний запрос агента — провал;
- все шаги scripted-модели использованы, лишних запросов нет; `after.files` сверяются с последним `fs/write_text_file`.

Драйвер НЕ SHALL зависеть от пакетов агента и НЕ SHALL содержать собственную реализацию пары транспортов в памяти. Фикстура без роли `agent` и фикстура с `setup.transport` SHALL пропускаться с указанием причины: транспортные фикстуры играет транспортный драйвер. Скрипт `melos run conformance:agent` SHALL входить в `melos run check`.

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

#### Scenario: Пара транспортов из codelab_acp_transports
- **WHEN** агентский драйвер поднимает агента для фикстуры
- **THEN** агентский конец — `InProcessAcpLink().agent` из `package:codelab_acp_transports/codelab_acp_transports.dart`, а в `packages/dart/codelab_acp_testing/lib/` нет определения классов `InProcessAcpLink` и `InProcessAcpTransport`

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
- `acp/prompt-template-command` (E-07) — шаблон `.codelab/prompts/review.md` доверенного проекта; `available_commands_update` после `session/new` содержит встроенные `compact`, `mode`, `model`, `status`, `mcp`, `help` (capability `compaction` и `mcp` агентского прогона включены; design.md change `add-config-writer-and-reload`, D12; design.md change `add-agent-builtin-slash-commands`, D2), затем `review` с `input.hint`; `session/prompt` с `/review lib/parser "error handling"` — scripted-модель получает развёрнутый текст; после `session/load` реплей содержит `user_message_chunk` с исходной командой;
- `acp/available-commands-no-tools` (R-07, часть шаблонов и встроенных команд) — встроенные инструменты, fake MCP-сервер с `echo` и один шаблон; список команд — встроенные `compact`, `mode`, `model`, `status`, `mcp`, `help` и шаблон, без инструментов (design.md change `add-config-writer-and-reload`, D12; design.md change `add-agent-builtin-slash-commands`, D2);
- `acp/set-config-option-agent` (R-15) — `.codelab/agents/reviewer.md` с многострочным `tools`; `configOptions` содержит `agent`; `session/set_config_option` с `agent: reviewer` даёт `current_mode_update`, ответ с согласованными `agent`, `model`, `mode`; следующий запрос к модели содержит только схемы из списка;
- `acp/slash-mcp-list` (E-13, агентская часть; E-04) — `session/new` с одним сервером клиента и конфигом с двумя серверами, один из которых `enabled: false`:
  - `/mcp list` — один `agent_message_chunk` с таблицей `agent-core-architecture` §17.5.7 побайтово, `stopReason: end_turn`, запросов к scripted-модели нет;
  - `/mcp disable <id>` — строка сервера в состоянии `disabled`;
  - `/mcp frob` — текст `Usage: …`;
  - после `session/load` реплей не содержит ни одной из этих команд.

Файлы сценария SHALL задаваться `setup.files`; формат фикстур НЕ SHALL меняться. Фабрика агентского прогона `codelab_agent_acp` SHALL подключать `ProjectFilesLoader` с временным `CODELAB_HOME` и принимать в `setup.config` ключи `trusted_projects` (с подстановкой `${cwd}`) и `mcp.servers`. Сервер `mcp.servers` с `type: stdio` и `command`, равным имени fake-сервера фабрики, подключается к этому fake-серверу; любой другой `command` — громкий провал. Другой неизвестный ключ — по-прежнему громкий провал. Фабрика НЕ SHALL передавать ядру `ConfigSource`: перезагрузка проверяется тестами хоста.

#### Scenario: Команда шаблона
- **WHEN** агентский драйвер проигрывает `acp/prompt-template-command`
- **THEN** кадры совпадают с фикстурой, scripted-модель получила развёрнутый текст

#### Scenario: Таблица /mcp list
- **WHEN** агентский драйвер проигрывает `acp/slash-mcp-list`
- **THEN** кадры совпадают с фикстурой побайтово, scripted-модель не получила ни одного запроса, журнал сессии не содержит записей команд

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер получает одну из этих фикстур
- **THEN** он её пропускает с причиной «роль только agent»

### Requirement: Фикстура неизвестного вида вызова
Корпус SHALL содержать фикстуру `acp/tool-kind-unknown-tolerated` с ролью только `client` (Dart-агент таких видов не выдаёт) и ссылками `spec` на `08-Tool Calls.md#creating`, `08-Tool Calls.md#updating`, `08-Tool Calls.md#requesting-permission`, `12-Session Model.md#exiting-plan-modes`, `17-Schema.md#toolkind` и `05-Prompt Turn.md#4-check-for-completion`. В одном ходе агент SHALL присылать: `tool_call` с `kind: "future_kind"`, его `tool_call_update` с тем же видом и `status: "completed"`, `tool_call` с `kind: "switch_mode"` и `session/request_permission` на него с вариантами `allow_always`, `allow_once`, `reject_once` по образцу `12-Session Model.md`; ожидаемый кадр клиента — ответ `selected` с вариантом `reject_once`; затем `tool_call_update` `failed` и ответ `session/prompt` `end_turn` (design.md change `tolerate-unknown-tool-kind`, D8).

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер проигрывает `acp/tool-kind-unknown-tolerated`, а тест в хуке выбирает вариант `reject_once`
- **THEN** ответ клиента на `session/request_permission` — `selected` с `optionId` `reject`, а не `cancelled`, и ход завершается кадром ответа `session/prompt`

#### Scenario: Состояние после прогона
- **WHEN** клиентский прогон этой фикстуры завершён
- **THEN** вызов `call_future` в ходе имеет вид `other`, статус `completed` и риск `unknown`, вызов `call_switch_mode_001` — вид `switchMode` и риск `unknown`, а диагностик уровня error нет

#### Scenario: Агентский прогон пропускает фикстуру
- **WHEN** агентский драйвер получает `acp/tool-kind-unknown-tolerated`
- **THEN** он её пропускает и сообщает, что у фикстуры нет роли `agent`

### Requirement: Фикстуры встроенных команд агента
Корпус SHALL содержать фикстуры с ролью `agent` и ссылками `spec` на `14-Slash Commands.md`, `05-Prompt Turn.md` и, для режима, `13-Session Config Options.md` и `12-Session Model.md` (design.md change `add-agent-builtin-slash-commands`, D8; строки Must K-02, R-08):
- `acp/slash-compact` (K-02) — сессия с историей, достаточной для среза (`setup.config` с малым `compaction.keep_recent_tokens`), затем `session/prompt` с `/compact <указание>`: scripted-суммаризатор получает блок `<focus>` с указанием; ответ — один `agent_message_chunk` `Compacted: <X> → <Y> tokens.` и `stopReason: end_turn`; ни `tool_call`, ни `plan` в ходе нет;
- `acp/slash-help` (R-08) — `available_commands_update` после `session/new`, затем `/help`: один `agent_message_chunk` со списком команд в порядке объявления и `stopReason: end_turn`, запросов к scripted-модели нет;
- `acp/slash-mode-plan` (R-08, сценарий приёмки) — сессия в режиме `standard`: `/help`, затем `/mode plan` — `current_mode_update` с `plan`, `config_option_update` с полным снимком, `agent_message_chunk` `Mode: plan.`, `stopReason: end_turn`; затем `/nope` — `agent_message_chunk` `Unknown command: /nope. Run /help to list commands.` и `stopReason: end_turn`; запросов к scripted-модели нет.

Все уведомления хода SHALL идти до ответа на `session/prompt` (ACP-3).

#### Scenario: /mode plan в корпусе
- **WHEN** агентский драйвер проигрывает `acp/slash-mode-plan`
- **THEN** кадры совпадают с фикстурой, scripted-модель не получила ни одного запроса

#### Scenario: /compact в корпусе
- **WHEN** агентский драйвер проигрывает `acp/slash-compact`
- **THEN** кадры совпадают с фикстурой, суммаризатор получил указание, основная модель после `/compact` запросов не получила

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер получает одну из этих фикстур
- **THEN** он её пропускает с причиной «роль только agent»

### Requirement: Фикстуры навыков
Корпус SHALL содержать фикстуры с ролью `agent`, целью `E-06` и ссылками `spec` на `14-Slash Commands.md`, `08-Tool Calls.md` и, для скрипта, `10-Terminal.md` (design.md change `add-agent-skills`, D7, D8; `agent-core-architecture` §17.2.12). Навыки задаются `setup.files` под `.codelab/skills/` доверенного проекта (`setup.config.trusted_projects: ["${cwd}"]`); агентский драйвер SHALL принимать ключ `skills` в `setup.config`:
- `acp/skill-command-listed` (критерий E-06) — два навыка, один с `user-invocable: false`, у другого `argument-hint`: `available_commands_update` после `session/new` содержит после встроенных команд `skill:<name>` только вызываемого навыка с `input.hint` из `argument-hint`; имени `skill` и других инструментов модели в списке нет (SKL-6, R-07);
- `acp/skill-invoke` — `session/prompt` с `/skill:release-notes v1.2 v1.3`: scripted-модель получает сообщение пользователя с блоком навыка и подставленными аргументами (фикстура сверяет тело после `dir="…/.codelab/skills/release-notes">`; преамбулу `invoked.md` и сообщение целиком проверяет тест ядра — матчер `$textContains` не подставляет `${cwd}`); затем `session/load` — реплей содержит `user_message_chunk` с `/skill:release-notes v1.2 v1.3`, а не обёртку; затем в загруженной сессии `/skill:nope` — один `agent_message_chunk` `Unknown skill: nope. Run /help to list commands.` и `stopReason: end_turn` без запроса к модели (design.md change `add-agent-skills`, D18: порядок проверяет ветку `skill:` после `session/load`; то, что ответ `Unknown skill` не пишется в журнал, проверяют тесты ядра);
- `acp/skill-tool-load` — модель вызывает `skill` с `{"name":"release-notes"}`: `tool_call` с `kind: read`, заголовком `Load skill release-notes` и `locations` с путём `SKILL.md` навыка; в режиме `standard` вызов уровня `read` выполняется без `session/request_permission`; `tool_call_update` `completed` содержит тело в блоке `<skill …>`; следующий запрос модели содержит этот результат; второй вызов `skill` с тем же именем завершается строкой повтора `Skill "release-notes" is already loaded in this conversation; follow the instructions above.` (решение Q10);
- `acp/skill-script-exec` (решения Q17, Q24 (а)) — навык проекта `.codelab/skills/pdf` со `scripts/extract.py`; модель вызывает `exec` с `python3 scripts/extract.py` и `cwd` — каталог навыка: `session/request_permission` с обычными вариантами уровня `exec`, включая `allow_always` (критического шаблона нет); после `allow_once` — `terminal/create` с `cwd` каталога навыка и `tool_call_update` `completed` с выводом; вторым шагом — рекомендованный путь (Q26): `exec` с `python3 <cwd>/.codelab/skills/pdf/scripts/extract.py` и `cwd` рабочей папки — тот же обычный вопрос уровня `exec` без критического шаблона (Q25) и `terminal/create` с `cwd` рабочей папки.

Все уведомления хода SHALL идти до ответа на `session/prompt` (ACP-3). Клиентский драйвер SHALL пропускать эти фикстуры с причиной «роль только agent»; драйверы встроенного агента и бинаря `codelab-agent` пропускают их с причиной `setup.config`, как прочие фикстуры с `setup.config`.

#### Scenario: Список команд с навыками в корпусе
- **WHEN** агентский драйвер проигрывает `acp/skill-command-listed`
- **THEN** кадры совпадают с фикстурой, список команд содержит ровно один элемент с префиксом `skill:`

#### Scenario: Неизвестный навык без модели
- **WHEN** агентский драйвер проигрывает `acp/skill-invoke`
- **THEN** на `/skill:nope` scripted-модель не получила запроса, ответ — `end_turn`

### Requirement: Фикстуры субагентов и списка задач
Корпус SHALL содержать фикстуры change `add-subagents-and-tasks` с объявленными `extensions` (FIX-4; имена по используемым данным: `capabilities` — блок `_meta.codelab` в `initialize`, `task` — `_meta.codelab.task`, `subagent` — `_meta.codelab.subagent`) и ссылками `spec` на `11-Agent Plan.md`, `15-Extensibility.md`, `08-Tool Calls.md` и `02-Initialization.md`:

| Фикстура | Роли | Цели |
|---|---|---|
| `acp/initialize-codelab-extensions` | `agent`, `client` | схема объявления |
| `acp/prompt-task-plan` | `agent`, `client` | C-20, C-05 |
| `acp/session-load-legacy-plan` | `agent` | C-05; журнал старого формата задаётся `setup.sessions` |
| `acp/prompt-subagent-tool-call` | `agent`, `client` | C-06 |
| `acp/prompt-subagent-permission` | `agent`, `client` | C-06, P-02 |
| `acp/prompt-subagent-nested-permission` | `agent` | C-06 |
| `acp/prompt-subagent-tool-tree` | `agent`, `client` | C-06, этап 2 (`extensions`: `capabilities`, `subagent`, `parentToolCallId`) |
| `acp/session-load-subagent-tool-tree` | `agent`, `client` | C-06, этап 2; журналы корня и ребёнка задаются `setup.sessions` |

Изменения существующих фикстур:
- `acp/prompt-update-plan` SHALL остаться в корпусе только с ролью `client`: клиент по-прежнему показывает план агента без `_meta`;
- `acp/initialize-capabilities` SHALL остаться вариантом «клиент без `_meta`» с ролью `agent`;
- клиентские фикстуры, в которых kit отправляет `initialize`, SHALL ожидать `clientCapabilities._meta.codelab` и объявлять `extensions`;
- фикстуры с ожидаемыми схемами запроса к модели SHALL ожидать `task_*` вместо `update_plan`;
- первый `tool_call` вызова `agent` в фикстурах субагентов (те же пять, включая реплей) SHALL ожидать `_meta.codelab.subagent` с `type` и `id` через `$capture` (D28);
- финальный `tool_call_update` вызова `agent` в фикстурах субагентов (`acp/prompt-subagent-tool-call`, `acp/prompt-subagent-permission`, `acp/prompt-subagent-nested-permission`, `acp/prompt-subagent-tool-tree`, реплей `acp/session-load-subagent-tool-tree`) SHALL ожидать `_meta.codelab.subagent.summary` с точными `toolCalls` и токенами scripted-модели; `durationMs` сравнивается через `$any` (время недетерминировано).

Scripted-модель субагента SHALL задаваться тем же блоком `llm.steps`, что и модель корня. Шаги ребёнка различаются проверкой `expect` по системному промпту или первому сообщению ребёнка; нового формата фикстуры не вводится.

#### Scenario: Расширение не объявлено
- **WHEN** фикстура `acp/prompt-task-plan` не перечисляет `task` в `extensions`
- **THEN** тест загрузки корпуса падает (FIX-4)

#### Scenario: Клиент показывает план стороннего агента
- **WHEN** клиентский драйвер проигрывает `acp/prompt-update-plan`
- **THEN** `SessionView.plan` дважды заменяется тремя пунктами без `taskId`

#### Scenario: Агентский прогон запроса ребёнка
- **WHEN** агентский драйвер проигрывает `acp/prompt-subagent-permission` против встроенного агента и `codelab-agent serve --stdio`
- **THEN** кадры совпадают в обоих режимах, включая `toolCallId` `call_1/call_1` и `_meta.codelab.subagent`

### Requirement: Фикстуры расширения usage
Корпус SHALL содержать фикстуры change `add-usage-extension`, у которых `extensions` содержит `usage` (FIX-4; фикстура с инструментом `task_create` несёт ещё `task`) и ссылками `spec` на `15-Extensibility.md` и `05-Prompt Turn.md` (design.md, D13):

| Фикстура | Роли | Режимы агентского прогона |
|---|---|---|
| `acp/prompt-usage-steps` | `agent`, `client` | все |
| `acp/prompt-usage-unpriced` | `agent` | все |
| `acp/prompt-usage-cancelled` | `agent` | все |
| `acp/compact-usage-context` | `agent` | только `conformance:agent` |
| `acp/prompt-usage-compaction-off` | `agent` | только `conformance:agent` |
| `acp/session-load-usage-partial` | `agent` | только `conformance:agent` |

Фикстуры «все» SHALL обходиться без `setup.config` и `setup.sessions`, чтобы их проигрывали и встроенный агент, и `codelab-agent serve --stdio`. `acp/compact-usage-context` SHALL задавать `setup.config.compaction.keep_recent_tokens: 512` (как `acp/slash-compact`): с порогом по умолчанию короткая история не сжимается (design.md, D19 п. 1).

В каждой из них кадр `initialize` клиента SHALL объявлять `clientCapabilities._meta.codelab.usage`. Значения `turnId` SHALL сравниваться через `$capture`, `seq`, токены, стоимость и порядок причин `partial` — точно; `context.used` после шага с инструментом и после сжатия МОЖЕТ сверяться матчером `$any`; scripted-модель SHALL задавать usage шагов в `llm.steps` и цены модели в `llm.model.cost` (объект формата `llmModelCost`: `input`, `output`, необязательные `cacheRead`, `cacheWrite`, доллары за 10⁶ токенов; design.md, D18 Т8, D19 п. 6). Значения `llmModelCost` SHALL быть неотрицательными конечными числами: неизвестный ключ, не число или отрицательное число SHALL давать `FixtureFormatException` с путём поля (`$.llm.model.cost.<ключ>`) при загрузке корпуса; число, которое разбор JSON превращает в бесконечность (`1e999`), отсекает раньше разбора полей канонизация `AcpFixture.fromJson` — `FixtureFormatException` с путём `$` («is not JSON»). Тот же формат читает `--llm-script` (`LlmScript`, требование `agent-binary` «Сценарий --llm-script»): неверное значение SHALL быть ошибкой загрузки сценария с путём поля, а не молчаливым «цен нет» (design.md, D20).

Изменения существующих фикстур:
- `acp/initialize-codelab-extensions` SHALL ожидать `usage: {"version": 1}` в `clientCapabilities._meta.codelab` и в `agentCapabilities._meta.codelab` и объявлять расширение `usage`;
- фикстуры с ролью `client` и явным кадром `initialize` клиента (`acp/initialize-codelab-extensions`, `acp/session-load-interrupted-turn`, `acp/session-new-modes-config`, `acp/set-config-option-model`) SHALL ожидать полное объявление клиента с `usage` в `clientCapabilities._meta.codelab`;
- клиентский драйвер в стандартном handshake SHALL сверять `_meta.codelab` из `setup.clientCapabilities` как подмножество объявления клиента: каждый указанный ключ — точно, лишние ключи клиента допустимы; агентский драйвер по-прежнему отправляет `setup.clientCapabilities` как есть (design.md, Q15 (б), D21 Т7);
- `acp/prompt-turn-budget-exceeded` SHALL проигрываться и клиентским драйвером;
- фикстуры, где клиент не объявляет `usage`, НЕ SHALL получать кадров `_codelab/session/usage`.

#### Scenario: Расширение не объявлено
- **WHEN** фикстура `acp/prompt-usage-steps` не перечисляет `usage` в `extensions`
- **THEN** тест загрузки корпуса падает (FIX-4)

#### Scenario: Неверная цена модели в фикстуре
- **WHEN** фикстура задаёт `llm.model.cost: {"input": -1, "output": 2}`, другая — `{"input": "1", "output": 2}`, третья — `{"input": 1e999, "output": 2}`
- **THEN** загрузка каждой падает с `FixtureFormatException`: у первых двух путь — `$.llm.model.cost.input`, у третьей — `$` («is not JSON»: канонизация `AcpFixture.fromJson` отсекает не конечное число раньше разбора полей)

#### Scenario: Неверная цена в --llm-script
- **WHEN** `codelab-agent serve --stdio --llm-script` получает файл с `llm.model.cost.output: -0.5`
- **THEN** процесс завершается ошибкой использования (код `64`) с путём `llm.model.cost.output`; запуска без цен нет

#### Scenario: Агентский прогон во всех режимах
- **WHEN** агентский драйвер проигрывает `acp/prompt-usage-steps` против встроенного агента и `codelab-agent serve --stdio`
- **THEN** кадры совпадают в обоих режимах, включая `seq` и десятичные строки `cost`

#### Scenario: Сжатие только в агентском прогоне
- **WHEN** встроенный агент или `codelab-agent serve --stdio` проигрывают корпус
- **THEN** `acp/compact-usage-context` пропускается как фикстура с `setup.config`, а в `conformance:agent` снимок `compaction` и чанк «Compacted…» сверяются без фиксированного порядка

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер проигрывает `acp/prompt-usage-steps`
- **THEN** `SessionView.usage` после хода — `reported`, `lastTurn` и `session` равны значениям последнего снимка, клиент не отправляет кадров в ответ на уведомления (проверка `SessionView` — тестом `codelab_client_core` на том же драйвере, доставка снимков ядром клиента — `conformance:client`; design.md, D21 Т7)

#### Scenario: Причина бюджета у клиента
- **WHEN** клиентский драйвер проигрывает `acp/prompt-turn-budget-exceeded`
- **THEN** итог prompt turn ядра клиента несёт причину `tokens`, а заметка хода в транскрипте kit — `The turn stopped: budget exceeded: tokens.` (design.md, D21 Т7)

#### Scenario: Объявление клиента в handshake — подмножество
- **WHEN** клиентский драйвер проигрывает фикстуру без `skipInitialize` с `setup.clientCapabilities._meta.codelab: {"usage": {"version": 1}}`, а клиент объявляет `tasks`, `subagents`, `subagentToolCalls` и `usage`
- **THEN** кадр `initialize` клиента совпадает; если клиент не объявил `usage` или объявил его с другим значением, кадр не совпадает

### Requirement: Фикстуры журнала usage
Корпус SHALL содержать фикстуры design.md change `add-usage-ledger`, D11, с метками `usage` и `usageLedger` в `extensions` (FIX-4) и ссылками `spec` на `15-Extensibility.md`:
- `acp/slash-usage` (`agent`) — `usage` в `available_commands_update` сразу после `status`; `/usage` после хода с двумя шагами — текст отчёта с `end_turn` без `_codelab/session/usage`; `/usage x` — `Usage: /usage [rebuild]`;
- `acp/usage-ledger-request` (`agent`, `client`) — ход с двумя шагами и вызовом инструмента, затем `_codelab/session/usage/ledger` и его результат;
- `acp/usage-ledger-rebuild` (`agent`) — запрос с `rebuild: true`, `ledger.status: "rebuilt"`, `reason: "explicit"`;
- `acp/session-load-usage-full` (`agent`) — `session/load` журнала с двумя ходами: реплей, ответ, затем снимок `trigger: "load"` с полной суммой без `beforeLoad`, затем ход; заменяет `acp/session-load-usage-partial`;
- `acp/compact-usage-summary` (`agent`) — `/compact` со сценарным ответом суммаризатора с usage: снимок `compaction` с суммой сессии, включающей суммаризатор; затем запрос журнала с `summaries.count: 1`; только агентский прогон, как `acp/compact-usage-context`.

`acp/initialize-codelab-extensions` SHALL ожидать `usageLedger` в ответе агента; `acp/session-load-interrupted-turn` SHALL ожидать после ответа на `session/load` кадр `_codelab/session/usage` с `trigger: "load"` и нести метку `usage` (design.md, D15 п. 8); фикстуры с `available_commands_update` агента SHALL ожидать `usage` в списке команд после `status`. Правка этих ожиданий ссылается на change `add-usage-ledger` (требование «Правила изменения фикстур»). Фикстуры без меток `usage` и `usageLedger` НЕ SHALL содержать `_codelab/session/usage/ledger`.

#### Scenario: Агентский прогон журнала
- **WHEN** `conformance:agent` проигрывает `acp/usage-ledger-request`
- **THEN** результат запроса совпадает с фикстурой, включая `seq`, `toolCallIds` и строки стоимости

#### Scenario: Клиентский прогон журнала
- **WHEN** `conformance:client` проигрывает `acp/usage-ledger-request`
- **THEN** клиент отправляет запрос с теми же параметрами, а `SessionView.usageLedger` после ответа — `loaded` с одним ходом и двумя шагами

#### Scenario: Полная сумма после загрузки
- **WHEN** `conformance:agent` проигрывает `acp/session-load-usage-full`
- **THEN** снимок `trigger: "load"` идёт после ответа на `session/load`, `session.partial` не содержит `beforeLoad`

### Requirement: Фикстура отброшенного прохода сжатия
Корпус SHALL содержать фикстуру `acp/compact-no-gain-usage` с ролью `agent`, метками `usage` и `usageLedger` в `extensions` и ссылкой `spec` на `15-Extensibility.md` (design.md change `fix-discarded-compaction-usage`, D7). Сценарий фикстуры:
1. клиент объявил `usage`;
2. ход с одним шагом на модели с ценами;
3. `/compact` со сценарным ответом суммаризатора длиннее региона и с usage.

Ожидаемые кадры SHALL быть такими:
- `agent_message_chunk` `Nothing to compact.` и `_codelab/session/usage` с `trigger: "compactionDiscarded"` и суммой сессии, включающей суммаризатор, — в любом порядке (блок `unordered`, как в `acp/compact-usage-summary`);
- затем ответ `end_turn`;
- ответ на запрос `_codelab/session/usage/ledger` с `summaries.count: 1` и `summaries.discarded: 1`.

Фикстура SHALL проигрываться только в `conformance:agent`, как `acp/compact-usage-summary`. Существующие фикстуры SHALL оставаться без изменений.

#### Scenario: Агентский прогон
- **WHEN** `melos run conformance:agent` проигрывает `acp/compact-no-gain-usage` против настоящего ядра со scripted-моделью
- **THEN** кадры совпадают с фикстурой после нормализации, включая то, что сообщение агента и снимок `compactionDiscarded` (в любом порядке) предшествуют ответу `session/prompt`

#### Scenario: Корпус не меняется
- **WHEN** прогоняются существующие фикстуры сжатия (`acp/slash-compact`, `acp/compact-usage-context`, `acp/compact-usage-summary`, `acp/compaction-long-session-continues`)
- **THEN** они зелёные без правок: ни в одной проход не отбрасывается

### Requirement: Фикстура бюджета хода в usage
Корпус SHALL содержать фикстуру `acp/prompt-usage-budget` с ролями `agent` и `client`, метками `usage` в `extensions` и ссылками `spec` на `15-Extensibility.md` (design.md change `add-desktop-usage-pane`, D7): клиент объявил `usage`; конфигурация агента (`setup.config`) задаёт `budget.max_tokens` и `budget.max_cost`; ход из двух шагов модели с ценами; снимки `step` и `turn` несут `budget` с `steps`, `tokens` и `cost`. Агентская роль сверяет форму и значения поля; клиентская — что `UsageView.budget` после снимка `turn` равен итогу из кадра. Существующие фикстуры с меткой `usage` НЕ SHALL меняться: в их конфигурации нет лимитов, кроме шагов.

#### Scenario: Агентский прогон
- **WHEN** `conformance:agent` проигрывает `acp/prompt-usage-budget`
- **THEN** каждый снимок `step` и `turn` содержит `budget` с ожидаемыми `used` и `limit`, и снимков без `budget` в ходе нет

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер проигрывает `acp/prompt-usage-budget`
- **THEN** после кадра снимка `turn` `SessionView.usage.budget` несёт `steps`, `tokens.used`, `tokens.limit`, `cost.used` и `cost.limit` из кадра и не несёт `duration`, а клиент не отправляет кадров в ответ на уведомления (проверка `SessionView` — тестом `codelab_client_core` на том же драйвере, `test/usage/usage_fixture_test.dart`; доставка снимков ядром клиента — `conformance:client`; как у `acp/prompt-usage-steps`, D21 Т7 change `add-usage-extension`)

#### Scenario: Существующие фикстуры
- **WHEN** агентский драйвер проигрывает `acp/prompt-usage-steps`
- **THEN** кадры совпадают без правки фикстуры: поля `budget` нет

