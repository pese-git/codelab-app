Задачи идут парами «тест → реализация» (dart-agent-and-clients §9.0, правило 3; `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование спецификации этого change, строка матрицы или решение design.md. Красный тест коммитится отдельно до кода (коммит — только по просьбе пользователя).

Метки исполнителей:
- `[agent]` — `codelab_agent_mcp`, `codelab_agent_core`, `codelab_agent_io`, `apps/codelab_agent`, сторож агентских пакетов и документы ядра;
- `[protocol]` — `codelab_agent_acp`, фикстуры и драйвер `codelab_acp_testing`, документы §13–§14.

Задач `[client]` и `[desktop]` нет (proposal, «Не входит»).

Итерации — тонкие сквозные срезы, каждая отдельным PR (или 2–3 PR) в `develop`:
- итерация 0 — группа 0: нормативный текст MCP и правки документов, без кода;
- итерация 1 — группы 1–4: пакет, порты ядра, клиент и проекция в памяти — MCP-инструмент через политику на `FakeMcpServer`;
- итерация 1б — группа 4б: соответствие спецификации MCP по итогам аудита итерации 1 (запросы сервера, снятие подписки, недоверенная схема, причины пробы, отмена по таймауту служебных запросов);
- итерация 2 — группы 5–8: stdio-транспорт, ACP, фикстуры, бинарь — реальный stdio-сервер из `session/new`;
- итерация 3 — группа 9: streamable HTTP и `tools/list_changed`, фикстура HTTP;
- итерация 4 — группа 10: матрица, документы и Definition of Done.

## 0. Источник истины и документы (без кода)

- [x] 0.1 `[agent]` Сверить D2–D10 с нормативными текстами в ветке, без скачивания нового: modern `2026-07-28` (`docs/protocols/mcp/specification/`: `basic/index.md`, `basic/versioning.md`, `basic/transports/{stdio,streamable-http}.md`, `basic/patterns/{cancellation,subscriptions,mrtr}.md`, `server/{discover,tools}.md`, `server/utilities/pagination.md`, `schema.md`) и legacy `2025-11-25` (`docs/protocols/mcp/specification/2025-11-25/`: `basic/lifecycle.md`, `basic/transports.md`, `basic/utilities/{cancellation,ping}.md`, `server/tools.md`, `server/utilities/pagination.md`, `schema.md`, `changelog.md`). Расхождения — правкой design.md до кода групп 3 и 9.
- [x] 0.2 `[agent]` Точечные правки документа ядра:
  - `agent-core/01-layers-and-packages.md` §1.2–§1.3 — каталог `codelab_agent_core/lib/src/mcp/`, порт транспорта в ядре, раскладка `codelab_agent_mcp` (D3);
  - `06-tools.md` §6.4 — одна ограда, правило префикса `mcp__` в точке исполнения, проекция содержимого, обрезка описания до 2048 символов, тексты ошибок, коллизия по порядку списка (D6–D8);
  - `10-core-assembly-and-profiles.md` §10.3, §10.8 — `AgentCoreServices.mcp: McpConnector?` вместо `McpTransportFactory?` (D3);
  - `11-prompts.md` — полный текст `mcp.md` (D12);
  - `12-observability-and-errors.md` §12.2 — события D13.
- [x] 0.3 `[protocol]` Точечные правки:
  - `agent-core/13-acp-adapter.md`:
    - §13.2 — `mcpCapabilities.http` по плану;
    - §13.4, шаги 2–4 — отображение, `sse` и неизвестный `type` (`unknown transport`, D11);
    - §13.5 — `setMcpServers` открытой сессии (D11);
    - §13.15 — отклонение сужается до профиля без stdio;
  - `14-golden-fixtures.md` — `setup.mcp`, `after.mcpCalls`, состав MCP-фикстур (D15).
- [x] 0.4 `[agent]` `09-13-stage-8-mcp-config.md`:
  - задача 8.1 — порт транспорта в ядре (D3);
  - DoD этапа и критерий E-05 — «коллизия имени отключает сервер с причиной, называющей оба источника, сессия создаётся» вместо «ошибка сборки» (D6, решение пользователя 2026-10-29);
  - ссылка на этот change.

## 1. Пакет `codelab_agent_mcp` и сторож (D14)

- [x] 1.1 `[agent]` Тест (workspace-architecture «Автоматический сторож границ пакетов», сценарии «MCP-клиент импортирует dart:io», «Зависимость MCP-клиента вне allowlist»):
  - `pubspec_allowlist_test.dart` — `mcpAllowlist = {codelab_agent_core, http, meta, async}` и `codelab_agent_mcp` в `binaryAllowlist`;
  - `import_guard_test.dart` — правило пакета на временном пакете с `import 'dart:io'` и `package:codelab_acp_protocol/` даёт два нарушения.

  Красный: пакета и правила нет.
- [x] 1.2 `[agent]` Пакет `packages/dart/codelab_agent_mcp`:
  - `pubspec.yaml` с allowlist и комментарием `# allowlist §1.2; расширение — только через OpenSpec`;
  - барель, `lib/testing.dart`, вложенный `AGENTS.md`;
  - `workspace:` корневого `pubspec.yaml`;
  - правило в `rules.dart` вместо заготовки `// stage 8`;
  - `README.md` — таблица и граф (D14).

  1.1 зелёный, `fvm dart run melos run guard` зелёный.

## 2. Порты ядра, имена и capability (D3, D6, D7)

- [x] 2.1 `[agent]` Тест `codelab_agent_core/test/mcp/mcp_tool_name_test.dart` — критерий `core/mcp-tool-name-sanitized` (E-05; agent-tools «MCP-инструменты», сценарии «Замена символов», «Длинное имя»):
  - `my.srv` + `get issue` → `mcp__my_srv__get_issue`;
  - 100 символов → ровно 64 = 56 + `_` + 7 hex SHA-256 полного имени;
  - два имени с общими 56 символами различаются;
  - `a.b` и `a_b` дают разные хэши.

  Красный.
- [x] 2.2 `[agent]` `lib/src/mcp/mcp_tool_name.dart` и зависимость `crypto` в `pubspec.yaml` ядра (в allowlist PKG-2) — 2.1 зелёный.
- [x] 2.3 `[agent]` Тесты (agent-runtime «Профили хостов и сужение», сценарий «Сужение транспортов MCP»; «Минимальная сборка buildAgentCore», сценарии «Матрица профиля», «Коннектор без нужного транспорта»):
  - `agent-serve` и `embedded-cli` имеют `mcp: {stdio, http}`;
  - расширение до `{http, stdio}` из `{http}` — `HostWiringException`;
  - без `services.mcp` — `offReasons[mcp]`;
  - коннектор только со `stdio` — исключение, называющее `http`;
  - golden профилей обновлён.

  Красный.
- [x] 2.4 `[agent]` Реализация, экспорт из бареля — 2.3 зелёный:
  - `HostCapability.mcp` и состояния профилей;
  - `lib/src/mcp/`: `McpServerConfig`, `McpServerOrigin`, `McpTransport`, `McpTransportFactory`, `McpTransportClosed`, `McpConnector`, `McpConnectRequest`, `McpSessionTools`, `McpToolsUpdate`, `McpServerSummary`;
  - `AgentCoreServices.mcp`, `CoreConfig.mcpServers`, шаги 1–2 `buildAgentCore`.

## 3. Кодек JSON-RPC и `McpClient` (D2, D4, D5, D8)

- [x] 3.1 `[agent]` Тест `codelab_agent_mcp/test/json_rpc_test.dart`:
  - запрос, уведомление, ответ, ошибка — туда и обратно;
  - modern `_meta` (`protocolVersion`, `clientCapabilities`, `clientInfo`) добавляется к каждому modern-запросу и не добавляется к legacy;
  - распознавание modern-ошибок `-32020`, `-32021`, `-32022` с `data.supported`;
  - `resultType`: нет → `complete`, неизвестный → ошибка схемы;
  - массив → последовательность (`2025-03-26`);
  - `id: null` и не-JSON → ошибка разбора без исключения наружу;
  - исходящие id растут без повторов.

  Красный.
- [x] 3.2 `[agent]` `lib/src/json_rpc.dart` и модели `lib/src/protocol.dart` (`server/discover`, `DiscoverResult`, `initialize`, `tools/list`, `tools/call`, `CallToolResult`, `resultType`, `Tool`, аннотации, `x-mcp-header`, `subscriptions/listen`, уведомления, эпохи и наборы версий) — 3.1 зелёный.
- [x] 3.3 `[agent]` Тест `test/mcp_client_connect_test.dart` на `FakeMcpServer` в памяти обеих эпох (agent-mcp-client «Эпоха сервера и версия протокола», все сценарии):
  - **modern:** без `initialize`, `_meta` на каждом запросе, `subscriptions/listen` при `listChanged`, две страницы `tools/list`;
  - **legacy со stdio-откатом** по ошибке `-32601` и по молчанию (таймаут пробы на `FakeClock`): `initialize` `2025-11-25`, `initialized` после ответа, поздний ответ на пробу → `mcp.message.ignored`;
  - **legacy-версии:** ответ `2025-06-18` и `2025-03-26` принимается, `2024-11-05` → `mcp.server.failed`;
  - **нет общей версии:** `-32022` с `data.supported: ["2027-01-01"]` → без отката на `initialize`;
  - таймаут `initialize` без `notifications/cancelled`; 100 страниц; legacy-`ping`; другой запрос сервера → `-32601`;
  - пустая строка как `nextCursor` — следующая страница, а не конец; legacy-инструмент с `execution.taskSupport: "required"` при `tasks.requests.tools.call` пропущен с `mcp.tool.invalid`;
  - логи `mcp.server.era` с `probe` каждого исхода;
  - кэш эпохи HTTP по `origin`: `cached` только у legacy, modern-сервер получает `server/discover` всегда; повторная проба после неподтверждённого кэша;
  - подписка (D5): ошибка, успешный ответ или обрыв ответа на `subscriptions/listen` до подтверждения и молчание дольше `min(5 с, connectTimeout / 2)` → сервер подключён без обновлений, `mcp.message.ignored` `subscription_failed`;
  - `list_changed` во время подключения → одно перечитывание после рукопожатия; сбой перечитывания → `mcp.tools.refresh_failed`, прежний набор (D6, п. 1);
  - ошибка потока `incoming` → `disconnected: transport error` (D3); нестроковые `title`/`description` инструмента игнорируются (D7);
  - `reason` без текстов и значений сервера (D13).

  Красный.
- [x] 3.4 `[agent]` `McpClient.connect` (проба эпохи, modern и legacy ветки, кэш эпохи в `McpClientConnector`) и `FakeMcpServer` эпох `modern`/`legacy`/`dualEra` (`lib/testing.dart`, вход в памяти; свой код, D15) — 3.3 зелёный.
- [x] 3.5 `[agent]` Тест `test/mcp_client_call_test.dart` (agent-mcp-client «Вызов инструмента, отмена и таймаут»):
  - результат;
  - отмена на stdio (обе эпохи) → одно `notifications/cancelled` и `CancelledException`; на транспорте `kind: http` modern → только `abandon(id)`, legacy → уведомление и `abandon(id)` (fake-транспорт записывает вызовы);
  - ответ после отмены → `mcp.message.ignored` `late_response`, итог `cancelled`;
  - таймаут на `FakeClock` → уведомление и текст D8;
  - закрытие транспорта во время вызова → `disconnected during the call`;
  - вызов после падения → `is not connected`;
  - `-32602` → текст с кодом;
  - ответ не по схеме и неизвестный `resultType` → `invalid tools/call result`;
  - `resultType: input_required` → `asked for client input`, повтора нет;
  - обрыв транспорта и обрыв потока ответа (`abortedRequests`) на `tools/call` → `disconnected during the call` без повтора; оборванный `tools/list` повторён один раз с новым id; `abandon(id)` не даёт события в `abortedRequests`;
  - таймаут — константа 10 минут (`McpClientOptions.callTimeout` без ключа конфига).

  Красный.
- [x] 3.6 `[agent]` `McpClient.callTool`, `McpClientOptions.callTimeout` (10 мин) — 3.5 зелёный.

## 4. Проекция в `AgentTool`, реестр сессии, политика, промпт (D6, D7, D12, D13)

- [x] 4.1 `[agent]` Тест `codelab_agent_mcp/test/mcp_tool_adapter_test.dart` (agent-tools «MCP-инструменты», сценарии «Вид по аннотациям», «Длинное описание обрезается»; agent-mcp-client «Проекция результата MCP-инструмента»; §6.7 документа ядра):
  - `kind` по аннотациям, `tier == exec`, `outputTrust == untrusted` при любых аннотациях;
  - `present().title` — полное имя;
  - `permissionPattern` — канонический JSON;
  - `mcp.tool.invalid` для `inputSchema` не-объекта;
  - таблица проекции D7 построчно, `isError`, картинка с поддержкой и без, `structuredContent`.
  - описание 5 000 символов → 2048 символов + `[Description truncated: 2952 characters omitted.]` и лог `mcp.tool.description_truncated`; ровно 2048 — без изменений; эмодзи на границе не разрывается;

  Красный.
- [x] 4.2 `[agent]` `lib/src/mcp_tool.dart` — 4.1 зелёный.
- [x] 4.3 `[agent]` Тесты ядра и коннектора (agent-runtime «MCP-серверы сессии», все сценарии; agent-tools «Ограда недоверенного вывода», сценарии «Результат MCP в одной ограде», «MCP-инструмент не объявляет себя доверенным»):
  - `codelab_agent_core/test/runtime/session_mcp_test.dart` на fake `McpConnector`: слияние с конфигом, пропуски с причинами D6, изоляция сессий, порядок закрытия, в журнале нет `command`/`env`/`url`/`headers`; исключение коннектора → сессия без MCP; сбой `createSession` / `loadSession` после подключения закрывает серверы; инструмент коннектора без `mcp__` или с именем встроенного → `mcp.tool.invalid` (agent-runtime «MCP-серверы сессии», сценарии «Сбой после подключения закрывает серверы», «Коннектор бросил», «Коннектор отдал инструмент без префикса»);
  - `codelab_agent_core/test/loop/step_update_tools_test.dart`: `StepUpdate.tools` и `StepUpdate.systemPrompt` меняют следующий запрос без замены транскрипта (agent-loop «Хуки и сборка payload», сценарий «Новые инструменты без замены транскрипта»);
  - `codelab_agent_mcp/test/connector_test.dart`: коллизия двух серверов при обратном порядке подключения, коллизия внутри сервера, порядок регистрации; коллизия в обновлении отключает сервер, чьё обновление её вызвало; непредвиденное исключение одного сервера → `unexpected error: <runtimeType>`;
  - `fence_test.dart`: `core/mcp-tool-cannot-declare-trusted`, одна ограда.

  Красный.
- [x] 4.4 `[agent]` Реализация — 4.3 зелёный:
  - реестр на сессию в `AgentRuntimeImpl._open`;
  - `SessionSpec.mcpServers`, `loadSession(..., mcpServers:)`;
  - закрытие транспортов в `AgentSession.close()` после простоя хода;
  - правило префикса `mcp__` в `ToolCallExecutor`;
  - `StepUpdate.tools` и `StepUpdate.systemPrompt` в `loop_config.dart` и их применение в цикле;
  - `McpSessionTools.replaceServers` — заглушка, бросающая `UnsupportedError`, до задачи 6.5;
  - `McpClientConnector` (`lib/src/connector.dart`);
  - при необходимости — `$textContains` для `toolResult` в `expect.lastMessage` `ScriptedStreamFunction` (§14.7, D15).
- [x] 4.5 `[agent]` Тест DoD (agent-permissions «MCP-вызов только после решения политики», все сценарии):
  - `codelab_agent_mcp/test/mcp_tool_goes_through_policy_test.dart: MCP tool is not executed without a permission decision` (закрывает F5.1, P-01): `buildAgentCore` + `McpClientConnector` + `FakeMcpServer`, gate `reject_once` → `FakeMcpServer.calls` пуст, вопрос задан до вызова сервера;
  - режим `plan` с ложной `readOnlyHint` — отказ без вопроса;
  - `no_bypass_test.dart` (`core/no-tool-bypasses-gate`) с fake MCP-инструментами.

  Должен быть зелёным без нового кода; если красный — исправление в 4.4.
- [x] 4.6 `[agent]` Тест `prompt_mcp_section_test.dart` (agent-prompts «Секция mcp», оба сценария; PR-6): строка `- fake: 2 tools, prefix mcp__fake__`; без серверов нет `mcp__`; сторож PR-6 зелёный. Красный.
- [x] 4.7 `[agent]` `prompts/mcp.md` (текст D12), `PromptInputs.mcpServers`, перегенерация `prompts.g.dart` — 4.6 зелёный.
- [x] 4.8 `[agent]` Тест `codelab_agent_mcp/test/mcp_logs_no_secrets_test.dart` (agent-mcp-client «Наблюдаемость MCP без секретов»): значения `env` и `headers` упавших серверов не встречаются в `RecordingLogger` и журнале. Красный, если утечка есть; затем поля логов по D13.
- [x] 4.9 Проверка итерации 1:
  - `fvm dart analyze` и `fvm dart test` в `codelab_agent_core`, `codelab_agent_mcp`;
  - `fvm dart run melos run guard`, `fvm dart run melos run web-compile`;
  - PR итерации 1, который называет следующую итерацию.

## 4б. Соответствие спецификации MCP (итерация 1б; D2, D5, D7, D8, D13)

Аудит итерации 1 против `docs/protocols/mcp/specification/` и `.../2025-11-25/` (решения одобрены пользователем). Повтор оборванного `subscriptions/listen` — HTTP-сценарий, он в 9.1/9.2.

- [x] 4б.1 `[agent]` Тест `codelab_agent_mcp/test/mcp_client_spec_conformance_test.dart` (agent-mcp-client «Эпоха сервера и версия протокола», сценарии «Запрос modern-сервера без ответа», «Ping в окне рукопожатия», «Сервер снял подписку», «Probe отклонён modern-ошибкой», «Подтверждения подписки нет»; «Обновление списка инструментов», сценарий «Таймаут перечитывания шлёт отмену»):
  - запросы modern-сервера (`ping`, `sampling/createMessage`) → ответов в транспорте нет, `mcp.message.ignored` `server_request` с `method`; legacy-`ping` и `-32601` на прочее — тест 3.3;
  - legacy-`ping` в окне рукопожатия (после отправки `initialize`) → пустой `result`;
  - серверный `notifications/cancelled` с id `subscriptions/listen` → `subscription_closed`, `list_changed` больше не перечитывает, сервер подключён; `close()` не шлёт отмену на этот id;
  - `-32020` и `-32021` на пробе → `server rejected the probe (code N)` без отката; `-32022` — как раньше;
  - таймаут подтверждения подписки и таймаут `tools/list` перечитывания на живом соединении → один сигнал отмены (stdio — `notifications/cancelled`, транспорт `kind: http` — `abandon(id)`), `mcp.tools.refresh_failed` с `no answer to tools/list`; таймаут пробы — без сигнала.

  Красный.
- [x] 4б.2 `[agent]` `lib/src/mcp_client.dart` (ветка ответов на запросы сервера по `_outbound.era` с отправки `initialize`, `notifications/cancelled` сервера, сигнал отмены по таймауту служебных запросов, причина `server rejected the probe`), при необходимости `FakeMcpServer` — 4б.1 зелёный.
- [x] 4б.3 `[agent]` Тест `codelab_agent_mcp/test/mcp_tool_adapter_test.dart` (agent-tools «MCP-инструменты», сценарий «Кривая схема инструмента»): ключевые слова `type`, `required`, `properties`, `items`, `enum` неверного типа в корне и во вложенной схеме → `mcp.tool.invalid` `malformed inputSchema`, соседний инструмент зарегистрирован. Красный.
- [x] 4б.4 `[agent]` Рекурсивная проверка схемы в `lib/src/mcp_tool.dart` — 4б.3 зелёный.
- [x] 4б.5 `[agent]` Тесты ядра (agent-tools «Валидация и приведение аргументов», сценарии «Некорректное ключевое слово схемы», «Исключение при валидации»):
  - `codelab_agent_core/test/tools/validator_test.dart` — неверный тип `type`, `required`, `properties`, `items`, `enum` в корне и вложенно → нарушение `schema: "<keyword>" must be <expected>` (вложенные — с путём), без исключения;
  - `codelab_agent_core/test/tools/tool_throws_test.dart` — исключение геттера `parameters` → результат-ошибка `failed`, `ToolCallFinished`, ход продолжается.

  Красный.
- [x] 4б.6 `[agent]` Терпимый разбор схемы в `lib/src/tools/validator.dart`, перехват исключения валидации в `lib/src/tools/executor.dart` — 4б.5 зелёный.
- [x] 4б.7 `[agent]` Документы ядра: `agent-core/06-tools.md` §6.3.1–§6.3.2 (терпимый валидатор, исключение валидации) и §6.4 «MCP-инструменты» (недоверенная схема, отступления D7, запросы сервера, снятие подписки, отмена по таймауту); `12-observability-and-errors.md` §12.3 (`server_request` и `method`, причины `server rejected the probe`, `no answer to tools/list`).
- [x] 4б.8 `[agent]` Добор тестов к уже реализованному поведению (должны быть зелёными без нового кода; красный — исправление в 4б.2/4б.4/4б.6):
  - `mcp_client_spec_conformance_test.dart`: запрос сервера во время пробы `server/discover` остаётся без ответа (D5); `notifications/cancelled` сервера с чужим `requestId` → `unknown_notification`, подписка жива; `notifications/cancelled` на id подписки до подтверждения → подключение без обновлений; `method` длиннее 64 рун обрезается;
  - `mcp_tool_adapter_test.dart`: boolean-схема свойства (`properties.flag: true`) — инструмент зарегистрирован; схема глубже 32 уровней → `malformed inputSchema` (сценарий «Кривая схема инструмента»);
  - `tool_throws_test.dart`: исключение валидации не меняет счётчик `MisuseBreaker`, а нарушение ключевого слова схемы (`schema: "required" must be …`) — меняет, как любая ошибка шага 3 (agent-tools, сценарии «Исключение при валидации», «Некорректное ключевое слово схемы»).
- [x] 4б.9 Проверка итерации 1б:
  - проверки затронутого (`AGENTS.md` §21): `fvm dart format`, `fvm dart analyze` и `fvm dart test` в `codelab_agent_core`, `codelab_agent_mcp`;
  - `fvm dart run melos run guard`, `fvm dart run melos run web-compile`;
  - `openspec validate add-agent-mcp-client --strict`;
  - PR итерации 1б, который называет следующую итерацию (2).
- [x] 4б.10 `[agent]` Исправления по ревью итерации 1б (PR #156), тесты до кода:
  - тесты: `mcp_tool_adapter_test.dart` — `items: true`, `items: false` и tuple-форма `items: [...]` не отклоняют инструмент; схема ровно 32 уровней (корень — 0) регистрируется, 33 → `malformed inputSchema`; длинное имя инструмента в `mcp.tool.invalid` обрезано до 64 рун (agent-tools, сценарии «Boolean и tuple-форма items допустимы», «Граница глубины схемы»); `validator_test.dart` — не-объект `items` игнорируется, вложенная схема проверяется лениво (сценарий «Вложенная схема проверяется лениво»); `tool_throws_test.dart` — `tool.validate.error` с `tool` и `tool_call_id`; `mcp_client_spec_conformance_test.dart` — `notifications/cancelled` с `requestId: "5"` при id подписки `5` → `unknown_notification`, подписка жива (agent-mcp-client «Эпоха сервера и версия протокола», снятие подписки);
  - реализация: одна функция формы ключевых слов в ядре (например, `schemaKeywordViolations`) рядом с `validator.dart`, `McpTool` применяет её рекурсивно с границей глубины 32 вместо своей копии правил (D7, §6.3.2); не-объект `items` игнорируется валидатором; лог `tool.validate.error` в `executor.dart` (D13); обрезка `tool` в `mcp.tool.invalid`; строгое сравнение id подписки по типу (D5).

## 5. stdio-транспорт (D9; E-02)

- [x] 5.1 `[agent]` Тест `codelab_agent_io/test/mcp/stdio_process_transport_test.dart` на скрипте `test/support/line_echo.dart` (agent-mcp-client «stdio-транспорт MCP», все сценарии):
  - окружение — только allowlist и `env` сервера (`SECRET_X` не виден);
  - строка туда и обратно;
  - строка длиннее 16 МиБ закрывает транспорт;
  - stderr не блокирует процесс;
  - `sh -c 'trap "" TERM; …'` завершается `SIGKILL` с потомками не позже 10 с;
  - несуществующий `command` → `spawn failed`;
  - `done` при выходе процесса.

  Красный.
- [x] 5.2 `[agent]` `lib/src/mcp/stdio_process_transport.dart` (`StdioProcessTransport`, `StdioMcpTransportFactory`) на `process_tree.dart`; экспорт из бареля `codelab_agent_io`; dev-зависимость `codelab_agent_mcp` не нужна — 5.1 зелёный.

## 6. ACP-адаптер (D11; R-24, E-03)

- [x] 6.1 `[protocol]` Тест `codelab_agent_acp/test/initialize_test.dart` (agent-acp-server «initialize», сценарии «Ответ codelab-app», «Ядро без MCP»): `mcpCapabilities.http` по плану ядра. Ожидаемый кадр `acp/initialize-capabilities` → `http: true` со ссылкой `02-Initialization.md#mcp-capabilities` (правило изменения фикстур). Красный.
- [x] 6.2 `[protocol]` `_initialize` читает capability `mcp` из `BuiltAgentCore.plan.profile` — 6.1 зелёный.
- [x] 6.3 `[protocol]` Тесты `session_new_test.dart` и `session_load_test.dart` (agent-acp-server «session/new», «session/load и реплей», новые сценарии):
  - stdio и http отображаются в `McpServerConfig`;
  - `sse` → `mcp.server.skipped`; тест «an MCP server is skipped with mcp.server.skipped» переписан на `sse` (R-02, D11);
  - неизвестный `type` → `mcp.server.skipped` с `reason: unknown transport`, сессия создана; `type: http` без `url` → `-32602` (agent-acp-server «Неизвестный транспорт MCP-сервера», сценарии «Сервер будущего транспорта», «Известный тип по-прежнему строг»);
  - сбой сервера — успешный ответ;
  - серверы загруженной сессии;
  - повторная загрузка открытой сессии с другим набором.

  Красный.
- [x] 6.4 `[agent]` Тест `codelab_agent_core/test/runtime/set_mcp_servers_test.dart` (agent-runtime «MCP-серверы сессии», `setMcpServers`):
  - совпавшие остаются;
  - исчезнувшие закрыты, новые подключены;
  - серверы конфига не тронуты;
  - во время хода — после `TurnEnded`.

  Красный.
- [x] 6.5 `[agent]` `AgentSession.setMcpServers`, `McpSessionTools.replaceServers` — заглушка итерации 1 (`UnsupportedError` в `connector.dart`) заменяется реализацией D11 — 6.4 зелёный.
- [x] 6.6 `[protocol]` Тест `codelab_acp_protocol/test/session_test.dart` (agent-acp-server «Неизвестный транспорт MCP-сервера», сценарий «Модель сохраняет неизвестный сервер»): `{"type":"websocket","name":"future","extra":1}` → `McpServerUnknown`, `toJson()` равен исходному; известные типы с лишним ключом и нестроковый `type` — по-прежнему ошибка; прежний тест «unknown type throws» переписан. Красный.
- [x] 6.7 `[protocol]` Вариант `McpServer.unknown({type, name?, raw})` в `codelab_acp_protocol/lib/src/acp/session.dart` (freezed, `toJson` — `raw`), ветки `McpServerUnknown` в исчерпывающих `switch`; перегенерация `session.freezed.dart`; `melos run protocol-conformance` зелёный — 6.6 зелёный.
- [x] 6.8 `[protocol]` Отображение `acp.McpServer` → `McpServerConfig` в `agent_server.dart` (`McpServerUnknown` и `McpServerSse` — пропуск с причиной), передача в `createSession` / `loadSession`, `setMcpServers` при открытой сессии; удаление пропуска этапа 4 — 6.3 зелёный.

## 7. Формат и фикстуры MCP (D15; P-01, P-16, E-02, R-24)

- [x] 7.1 `[protocol]` Тест согласованности схемы и загрузчика (acp-golden-fixtures «Формат golden-фикстуры ACP», сценарий «Схема и загрузчик согласованы»): ключи `setup.mcp`, `after.mcpCalls`; `AgentFixtureSetup` отдаёт их фабрике. Красный.
- [x] 7.2 `[protocol]` `_schema.json`, `fixture.dart`, `agent_conformance.dart` — 7.1 зелёный.
- [x] 7.3 `[protocol]` Фабрика `codelab_agent_acp/test/conformance_test.dart`:
  - dev-зависимость `codelab_agent_mcp`;
  - fake `McpTransportFactory` по `setup.mcp`: stdio — пара в памяти `FakeMcpServer`;
  - `verify()` сверяет `after.mcpCalls`.

  Тест (сценарий «Лишний вызов MCP-сервера»): фикстура с `after.mcpCalls: {"fake": []}` и вызовом падает с именем сервера.
- [x] 7.4 `[protocol]` Фикстуры (acp-golden-fixtures «MCP-фикстуры этапа 8»), сначала красные в агентском прогоне, затем зелёные:
  - `acp/session-new-with-mcp` (R-24; серверы обеих эпох — modern `fake` и legacy `old`);
  - `acp/mcp-tool-permission` (P-01);
  - `acp/mcp-stdio-tool-call` (E-02);
  - `acp/mcp-result-fenced` (P-16);
  - `acp/set-mode-plan-rejects-mcp-write` (P-01).

  Роль `agent`, ссылки `spec` по D15. `fvm dart run melos run conformance:agent` зелёный; клиентский прогон их пропускает с причиной.

## 8. Бинарь `codelab-agent` (D3; E-02, R-24)

- [x] 8.1 `[agent]` Тест `apps/codelab_agent/test/mcp_stdio_process_test.dart` (agent-binary «MCP-серверы в бинаре», сценарий «Реальный stdio-сервер»):
  - реальный бинарь с `--llm-script` и реальный `fake_mcp_stdio_server.dart`;
  - `mcp__fake__echo` после одобрения → `completed` с `hi`;
  - после EOF stdin агента процесс сервера по pid не жив не позже 10 с.

  Красный.
- [x] 8.2 `[agent]` Сборка в `agent_host.dart`: `McpClientConnector(transports: McpTransports(stdio: StdioMcpTransportFactory(…)))` в `AgentCoreServices.mcp`; зависимость `codelab_agent_mcp` в `pubspec.yaml` бинаря (allowlist из 1.1); точка входа `test/support/fake_mcp_stdio_server.dart` — 8.1 зелёный. До группы 9 профиль сужается до `mcp: {stdio}` с причиной «HTTP-транспорт — итерация 3».
- [x] 8.3 Проверка итерации 2:
  - проверки затронутого: `codelab_agent_io`, `codelab_agent_acp`, `codelab_acp_testing`, `apps/codelab_agent`;
  - `fvm dart run melos run conformance:agent`, `guard`;
  - PR итерации 2.

## 9. Streamable HTTP и `tools/list_changed` (D6, D10; E-03)

- [ ] 9.1 `[agent]` Тест DoD `codelab_agent_mcp/test/streamable_http_test.dart` на `MockClient` / `MockClient.streaming` с HTTP-обработчиком `FakeMcpServer` обеих эпох (agent-mcp-client «Транспорт streamable HTTP», «Эпоха сервера и версия протокола», сценарий «Legacy-сервер по HTTP»):
  - **обе эпохи:** заголовки `POST`, `202` для уведомлений, ответ JSON, ответ SSE с промежуточным уведомлением и keep-alive-комментарием; `307` не выполняется; схема `ftp` → `invalid url`; тело больше 16 МиБ → ошибка;
  - **modern:** `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method`, `Mcp-Name`, `Mcp-Param-*` из `x-mcp-header` с кодированием `=?base64?…?=` (в том числе для значения, похожего на маркер; `null` — без заголовка); инструмент с невалидным `x-mcp-header` исключён из `tools/list` с `mcp.tool.invalid`; `-32020` → один `tools/list` и повтор с новым id; нет `Mcp-Session-Id`, GET и `DELETE`; `subscriptions/listen` — долгий поток с `list_changed`; отмена — закрытие потока ответа без POST `notifications/cancelled`;
  - **проба эпохи:** `400` (а также `404`, `405`) с телом `-32022` → нет общей версии без отката; `400` с пустым телом, `404`, `405` и `404` с `-32601` → откат на `initialize`;
  - **legacy:** `Mcp-Session-Id` и `MCP-Protocol-Version` (`2025-06-18`) в следующих запросах, без `MCP-Protocol-Version` для `2025-03-26`; GET-поток при `listChanged`, `405` без потока; `404` → `HTTP session expired`; `DELETE` при закрытии; отмена — `notifications/cancelled` и закрытие потока; поток ответа, закрытый после события `id: e1` с `retry: 100`, возобновлён `GET` с `Last-Event-ID: e1` через 100 мс без второго `tools/call`, не больше 5 возобновлений;
  - **обрыв без возобновления:** `tools/call` — `disconnected during the call` без повтора; `tools/list`, `server/discover` и `subscriptions/listen` — один повтор с новым id (D10, «Повтор после обрыва»; agent-mcp-client, сценарий «Оборванная подписка переиздаётся»): после подтверждения переизданной подписки — ровно один `tools/list` перечитывания (изменения из окна обрыва не теряются), `list_changed` принимается только с новым `subscriptionId`, второй обрыв подписки — без обновлений; тест 3.3 об обрыве подписки уточняется — `subscription_failed` только после второго обрыва.

  Красный.
- [ ] 9.2 `[agent]` `lib/src/streamable_http.dart` (обе эпохи), зеркальные заголовки modern в `McpClient`, один повтор оборванного `subscriptions/listen` с новым id и одно перечитывание `tools/list` после его подтверждения в `McpClient` (D10), `StreamableHttpTransportFactory`, `McpTransports`; экспорт `SseDecoder` и `ServerSentEvent` из бареля ядра; HTTP-обработчик `FakeMcpServer` для `MockClient` — 9.1 зелёный.
- [ ] 9.3 `[agent]` Тест `codelab_agent_mcp/test/mcp_list_changed_boundary_test.dart` (agent-mcp-client «Обновление списка инструментов», оба сценария; D6):
  - уведомление посреди пакета вызовов применяется к следующему запросу;
  - modern — принимается только с `subscriptionId` своей подписки, legacy — с общего канала;
  - два уведомления → не больше двух `tools/list`;
  - коллизия в новом наборе отключает сервер, чьё обновление её вызвало;
  - секция `mcp` пересобрана;
  - лог `mcp.tools.changed`.

  Красный.
- [ ] 9.4 `[agent]` Перечитывание в `McpClient`, `McpSessionTools.takeUpdate`, применение в `prepareNextStep` → `StepUpdate.tools` и `StepUpdate.systemPrompt` и перед ходом — 9.3 зелёный.
- [ ] 9.5 `[protocol]` Фикстура `acp/mcp-http-tool-call` (E-03; сценарий «HTTP-сервер и пропуск SSE»): сервер `web` типа `http` (modern), `old` типа `sse` и `future` неизвестного типа `websocket` (D11). В фабрике conformance http — `StreamableHttpTransport` на `MockClient` с обработчиком `FakeMcpServer`. Сначала красная, затем зелёная.
- [ ] 9.6 `[agent]` Бинарь: HTTP-транспорт на HTTP-клиенте хоста, сужение `mcp` из 8.2 снято. Тест `agent_host_test.dart`: `initialize` даёт `mcpCapabilities.http: true` (agent-binary, сценарий «Возможности MCP в initialize»).
- [ ] 9.7 Проверка итерации 3: проверки затронутого, `conformance:agent`, `guard`, `web-compile`; PR итерации 3.

## 10. Документы и Definition of Done

- [ ] 10.1 `[agent]` `agent-parity-goals.md`:
  - критерии P-01, P-16, E-02, E-03, E-05, R-24 — пометка «закрыто change `add-agent-mcp-client`» с файлами тестов и фикстур;
  - R-02 — сценарий и критерий без «сервер пропущен» для поддерживаемых транспортов, пропуск — для `sse`;
  - сценарий E-05 (строка 723) — «конфликтующий сервер отключён с причиной, называющей оба источника, сессия создана» (D6);
  - E-02 — пометка, что серверы конфигурации подключаются после change `add-agent-configuration`.
- [ ] 10.2 `[protocol]` `13-acp-adapter.md` §13.15 и `14-golden-fixtures.md` §14.2 сверены с итогом реализации; Purpose спецификации `agent-acp-server` при архивации — без отклонения «MCP по stdio не подключаются».
- [ ] 10.3 `[agent]` `09-13-stage-8-mcp-config.md` — DoD 8.1–8.4 отмечены; `delivery-roadmap.md` — ссылка на change, если в вехе MVP есть пункт MCP; `THIRD_PARTY_NOTICES.md` не меняется (D1).
- [ ] 10.4 Проверка DoD:
  - проверки затронутого (`AGENTS.md` §21) зелёные локально и в CI pull request; полный `melos run check` — зелёный в CI на `develop` после merge, локально — только по просьбе пользователя;
  - `mcp_tool_goes_through_policy_test.dart` и `streamable_http_test.dart` зелёные;
  - `melos run guard` — `codelab_agent_mcp` без `dart:io`;
  - шесть MCP-фикстур зелёные в агентском прогоне;
  - `openspec validate add-agent-mcp-client --strict` без ошибок;
  - PR итерации 4.

  Архивация change — только по просьбе пользователя.
