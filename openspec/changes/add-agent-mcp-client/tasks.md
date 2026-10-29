Задачи идут парами «тест → реализация» (dart-agent-and-clients §9.0, правило 3; `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование спецификации этого change, строка матрицы или решение design.md. Красный тест коммитится отдельно до кода (коммит — только по просьбе пользователя).

Метки исполнителей:
- `[agent]` — `codelab_agent_mcp`, `codelab_agent_core`, `codelab_agent_io`, `apps/codelab_agent`, сторож агентских пакетов и документы ядра;
- `[protocol]` — `codelab_agent_acp`, фикстуры и драйвер `codelab_acp_testing`, документы §13–§14.

Задач `[client]` и `[desktop]` нет (proposal, «Не входит»).

Итерации — тонкие сквозные срезы, каждая отдельным PR (или 2–3 PR) в `develop`:
- итерация 0 — группа 0: нормативный текст MCP и правки документов, без кода;
- итерация 1 — группы 1–4: пакет, порты ядра, клиент и проекция в памяти — MCP-инструмент через политику на `FakeMcpServer`;
- итерация 2 — группы 5–8: stdio-транспорт, ACP, фикстуры, бинарь — реальный stdio-сервер из `session/new`;
- итерация 3 — группа 9: streamable HTTP и `tools/list_changed`, фикстура HTTP;
- итерация 4 — группа 10: матрица, документы и Definition of Done.

## 0. Источник истины и документы (без кода)

- [ ] 0.1 `[agent]` Сверить D2–D10 с нормативными текстами в ветке, без скачивания нового: modern `2026-07-28` (`docs/protocols/mcp/specification/`: `basic/index.md`, `basic/versioning.md`, `basic/transports/{stdio,streamable-http}.md`, `basic/patterns/{cancellation,subscriptions,mrtr}.md`, `server/{discover,tools}.md`, `server/utilities/pagination.md`, `schema.md`) и legacy `2025-11-25` (`docs/protocols/mcp/specification/2025-11-25/`: `basic/lifecycle.md`, `basic/transports.md`, `basic/utilities/{cancellation,ping}.md`, `server/tools.md`, `server/utilities/pagination.md`, `schema.md`, `changelog.md`). Расхождения — правкой design.md до кода групп 3 и 9.
- [ ] 0.2 `[agent]` Точечные правки документа ядра:
  - `agent-core/01-layers-and-packages.md` §1.2–§1.3 — каталог `codelab_agent_core/lib/src/mcp/`, порт транспорта в ядре, раскладка `codelab_agent_mcp` (D3);
  - `06-tools.md` §6.4 — одна ограда, правило префикса `mcp__` в точке исполнения, проекция содержимого, обрезка описания до 2048 символов, тексты ошибок, коллизия по порядку списка (D6–D8);
  - `10-core-assembly-and-profiles.md` §10.3, §10.8 — `AgentCoreServices.mcp: McpConnector?` вместо `McpTransportFactory?` (D3);
  - `11-prompts.md` — полный текст `mcp.md` (D12);
  - `12-observability-and-errors.md` §12.2 — события D13.
- [ ] 0.3 `[protocol]` Точечные правки:
  - `agent-core/13-acp-adapter.md`:
    - §13.2 — `mcpCapabilities.http` по плану;
    - §13.4, шаги 2–4 — отображение, `sse` и неизвестный `type` (`unknown transport`, D11);
    - §13.5 — `setMcpServers` открытой сессии (D11);
    - §13.15 — отклонение сужается до профиля без stdio;
  - `14-golden-fixtures.md` — `setup.mcp`, `after.mcpCalls`, состав MCP-фикстур (D15).
- [ ] 0.4 `[agent]` `09-13-stage-8-mcp-config.md`:
  - задача 8.1 — порт транспорта в ядре (D3);
  - DoD этапа и критерий E-05 — «коллизия имени отключает сервер с причиной, называющей оба источника, сессия создаётся» вместо «ошибка сборки» (D6, решение пользователя 2026-10-29);
  - ссылка на этот change.

## 1. Пакет `codelab_agent_mcp` и сторож (D14)

- [ ] 1.1 `[agent]` Тест (workspace-architecture «Автоматический сторож границ пакетов», сценарии «MCP-клиент импортирует dart:io», «Зависимость MCP-клиента вне allowlist»):
  - `pubspec_allowlist_test.dart` — `mcpAllowlist = {codelab_agent_core, http, meta, async}` и `codelab_agent_mcp` в `binaryAllowlist`;
  - `import_guard_test.dart` — правило пакета на временном пакете с `import 'dart:io'` и `package:codelab_acp_protocol/` даёт два нарушения.

  Красный: пакета и правила нет.
- [ ] 1.2 `[agent]` Пакет `packages/dart/codelab_agent_mcp`:
  - `pubspec.yaml` с allowlist и комментарием `# allowlist §1.2; расширение — только через OpenSpec`;
  - барель, `lib/testing.dart`, вложенный `AGENTS.md`;
  - `workspace:` корневого `pubspec.yaml`;
  - правило в `rules.dart` вместо заготовки `// stage 8`;
  - `README.md` — таблица и граф (D14).

  1.1 зелёный, `fvm dart run melos run guard` зелёный.

## 2. Порты ядра, имена и capability (D3, D6, D7)

- [ ] 2.1 `[agent]` Тест `codelab_agent_core/test/mcp/mcp_tool_name_test.dart` — критерий `core/mcp-tool-name-sanitized` (E-05; agent-tools «MCP-инструменты», сценарии «Замена символов», «Длинное имя»):
  - `my.srv` + `get issue` → `mcp__my_srv__get_issue`;
  - 100 символов → ровно 64 = 56 + `_` + 7 hex SHA-256 полного имени;
  - два имени с общими 56 символами различаются;
  - `a.b` и `a_b` дают разные хэши.

  Красный.
- [ ] 2.2 `[agent]` `lib/src/mcp/mcp_tool_name.dart` и зависимость `crypto` в `pubspec.yaml` ядра (в allowlist PKG-2) — 2.1 зелёный.
- [ ] 2.3 `[agent]` Тесты (agent-runtime «Профили хостов и сужение», сценарий «Сужение транспортов MCP»; «Минимальная сборка buildAgentCore», сценарии «Матрица профиля», «Коннектор без нужного транспорта»):
  - `agent-serve` и `embedded-cli` имеют `mcp: {stdio, http}`;
  - расширение до `{http, stdio}` из `{http}` — `HostWiringException`;
  - без `services.mcp` — `offReasons[mcp]`;
  - коннектор только со `stdio` — исключение, называющее `http`;
  - golden профилей обновлён.

  Красный.
- [ ] 2.4 `[agent]` Реализация, экспорт из бареля — 2.3 зелёный:
  - `HostCapability.mcp` и состояния профилей;
  - `lib/src/mcp/`: `McpServerConfig`, `McpServerOrigin`, `McpTransport`, `McpTransportFactory`, `McpTransportClosed`, `McpConnector`, `McpConnectRequest`, `McpSessionTools`, `McpToolsUpdate`, `McpServerSummary`;
  - `AgentCoreServices.mcp`, `CoreConfig.mcpServers`, шаги 1–2 `buildAgentCore`.

## 3. Кодек JSON-RPC и `McpClient` (D2, D4, D5, D8)

- [ ] 3.1 `[agent]` Тест `codelab_agent_mcp/test/json_rpc_test.dart`:
  - запрос, уведомление, ответ, ошибка — туда и обратно;
  - modern `_meta` (`protocolVersion`, `clientCapabilities`, `clientInfo`) добавляется к каждому modern-запросу и не добавляется к legacy;
  - распознавание modern-ошибок `-32020`, `-32021`, `-32022` с `data.supported`;
  - `resultType`: нет → `complete`, неизвестный → ошибка схемы;
  - массив → последовательность (`2025-03-26`);
  - `id: null` и не-JSON → ошибка разбора без исключения наружу;
  - исходящие id растут без повторов.

  Красный.
- [ ] 3.2 `[agent]` `lib/src/json_rpc.dart` и модели `lib/src/protocol.dart` (`server/discover`, `DiscoverResult`, `initialize`, `tools/list`, `tools/call`, `CallToolResult`, `resultType`, `Tool`, аннотации, `x-mcp-header`, `subscriptions/listen`, уведомления, эпохи и наборы версий) — 3.1 зелёный.
- [ ] 3.3 `[agent]` Тест `test/mcp_client_connect_test.dart` на `FakeMcpServer` в памяти обеих эпох (agent-mcp-client «Эпоха сервера и версия протокола», все сценарии):
  - **modern:** без `initialize`, `_meta` на каждом запросе, `subscriptions/listen` при `listChanged`, две страницы `tools/list`;
  - **legacy со stdio-откатом** по ошибке `-32601` и по молчанию (таймаут пробы на `FakeClock`): `initialize` `2025-11-25`, `initialized` после ответа, поздний ответ на пробу → `mcp.message.ignored`;
  - **legacy-версии:** ответ `2025-06-18` и `2025-03-26` принимается, `2024-11-05` → `mcp.server.failed`;
  - **нет общей версии:** `-32022` с `data.supported: ["2027-01-01"]` → без отката на `initialize`;
  - таймаут `initialize` без `notifications/cancelled`; 100 страниц; legacy-`ping`; другой запрос сервера → `-32601`;
  - логи `mcp.server.era` с `probe` каждого исхода;
  - кэш эпохи HTTP по `origin`, повторная проба после неподтверждённого кэша.

  Красный.
- [ ] 3.4 `[agent]` `McpClient.connect` (проба эпохи, modern и legacy ветки, кэш эпохи в `McpClientConnector`) и `FakeMcpServer` эпох `modern`/`legacy`/`dualEra` (`lib/testing.dart`, вход в памяти; свой код, D15) — 3.3 зелёный.
- [ ] 3.5 `[agent]` Тест `test/mcp_client_call_test.dart` (agent-mcp-client «Вызов инструмента, отмена и таймаут»):
  - результат;
  - отмена на stdio (обе эпохи) → одно `notifications/cancelled` и `CancelledException`; на транспорте `kind: http` modern → только `abandon(id)`, legacy → уведомление и `abandon(id)` (fake-транспорт записывает вызовы);
  - ответ после отмены → `mcp.message.ignored` `late_response`, итог `cancelled`;
  - таймаут на `FakeClock` → уведомление и текст D8;
  - закрытие транспорта во время вызова → `disconnected during the call`;
  - вызов после падения → `is not connected`;
  - `-32602` → текст с кодом;
  - ответ не по схеме и неизвестный `resultType` → `invalid tools/call result`;
  - `resultType: input_required` → `asked for client input`, повтора нет;
  - обрыв транспорта на `tools/call` → `disconnected during the call` без повтора; оборванный `tools/list` повторён один раз с новым id;
  - таймаут — константа 10 минут (`McpClientOptions.callTimeout` без ключа конфига).

  Красный.
- [ ] 3.6 `[agent]` `McpClient.callTool`, `McpClientOptions.callTimeout` (10 мин) — 3.5 зелёный.

## 4. Проекция в `AgentTool`, реестр сессии, политика, промпт (D6, D7, D12, D13)

- [ ] 4.1 `[agent]` Тест `codelab_agent_mcp/test/mcp_tool_adapter_test.dart` (agent-tools «MCP-инструменты», сценарии «Вид по аннотациям», «Длинное описание обрезается»; agent-mcp-client «Проекция результата MCP-инструмента»; §6.7 документа ядра):
  - `kind` по аннотациям, `tier == exec`, `outputTrust == untrusted` при любых аннотациях;
  - `present().title` — полное имя;
  - `permissionPattern` — канонический JSON;
  - `mcp.tool.invalid` для `inputSchema` не-объекта;
  - таблица проекции D7 построчно, `isError`, картинка с поддержкой и без, `structuredContent`.
  - описание 5 000 символов → 2048 символов + `[Description truncated: 2952 characters omitted.]` и лог `mcp.tool.description_truncated`; ровно 2048 — без изменений; эмодзи на границе не разрывается;

  Красный.
- [ ] 4.2 `[agent]` `lib/src/mcp_tool.dart` — 4.1 зелёный.
- [ ] 4.3 `[agent]` Тесты ядра и коннектора (agent-runtime «MCP-серверы сессии», все сценарии; agent-tools «Ограда недоверенного вывода», сценарии «Результат MCP в одной ограде», «MCP-инструмент не объявляет себя доверенным»):
  - `codelab_agent_core/test/runtime/session_mcp_test.dart` на fake `McpConnector`: слияние с конфигом, пропуски, изоляция сессий, порядок закрытия, в журнале нет `command`/`env`/`url`/`headers`;
  - `codelab_agent_mcp/test/connector_test.dart`: коллизия двух серверов при обратном порядке подключения, коллизия внутри сервера, порядок регистрации;
  - `fence_test.dart`: `core/mcp-tool-cannot-declare-trusted`, одна ограда.

  Красный.
- [ ] 4.4 `[agent]` Реализация — 4.3 зелёный:
  - реестр на сессию в `AgentRuntimeImpl._open`;
  - `SessionSpec.mcpServers`, `loadSession(..., mcpServers:)`;
  - закрытие транспортов в `AgentSession.close()` после простоя хода;
  - правило префикса `mcp__` в `ToolCallExecutor`;
  - `McpClientConnector` (`lib/src/connector.dart`);
  - при необходимости — `$textContains` для `toolResult` в `expect.lastMessage` `ScriptedStreamFunction` (§14.7, D15).
- [ ] 4.5 `[agent]` Тест DoD (agent-permissions «MCP-вызов только после решения политики», все сценарии):
  - `codelab_agent_mcp/test/mcp_tool_goes_through_policy_test.dart: MCP tool is not executed without a permission decision` (закрывает F5.1, P-01): `buildAgentCore` + `McpClientConnector` + `FakeMcpServer`, gate `reject_once` → `FakeMcpServer.calls` пуст, вопрос задан до вызова сервера;
  - режим `plan` с ложной `readOnlyHint` — отказ без вопроса;
  - `no_bypass_test.dart` (`core/no-tool-bypasses-gate`) с fake MCP-инструментами.

  Должен быть зелёным без нового кода; если красный — исправление в 4.4.
- [ ] 4.6 `[agent]` Тест `prompt_mcp_section_test.dart` (agent-prompts «Секция mcp», оба сценария; PR-6): строка `- fake: 2 tools, prefix mcp__fake__`; без серверов нет `mcp__`; сторож PR-6 зелёный. Красный.
- [ ] 4.7 `[agent]` `prompts/mcp.md` (текст D12), `PromptInputs.mcpServers`, перегенерация `prompts.g.dart` — 4.6 зелёный.
- [ ] 4.8 `[agent]` Тест `codelab_agent_mcp/test/mcp_logs_no_secrets_test.dart` (agent-mcp-client «Наблюдаемость MCP без секретов»): значения `env` и `headers` упавших серверов не встречаются в `RecordingLogger` и журнале. Красный, если утечка есть; затем поля логов по D13.
- [ ] 4.9 Проверка итерации 1:
  - `fvm dart analyze` и `fvm dart test` в `codelab_agent_core`, `codelab_agent_mcp`;
  - `fvm dart run melos run guard`, `fvm dart run melos run web-compile`;
  - PR итерации 1, который называет следующую итерацию.

## 5. stdio-транспорт (D9; E-02)

- [ ] 5.1 `[agent]` Тест `codelab_agent_io/test/mcp/stdio_process_transport_test.dart` на скрипте `test/support/line_echo.dart` (agent-mcp-client «stdio-транспорт MCP», все сценарии):
  - окружение — только allowlist и `env` сервера (`SECRET_X` не виден);
  - строка туда и обратно;
  - строка длиннее 16 МиБ закрывает транспорт;
  - stderr не блокирует процесс;
  - `sh -c 'trap "" TERM; …'` завершается `SIGKILL` с потомками не позже 10 с;
  - несуществующий `command` → `spawn failed`;
  - `done` при выходе процесса.

  Красный.
- [ ] 5.2 `[agent]` `lib/src/mcp/stdio_process_transport.dart` (`StdioProcessTransport`, `StdioMcpTransportFactory`) на `process_tree.dart`; экспорт из бареля `codelab_agent_io`; dev-зависимость `codelab_agent_mcp` не нужна — 5.1 зелёный.

## 6. ACP-адаптер (D11; R-24, E-03)

- [ ] 6.1 `[protocol]` Тест `codelab_agent_acp/test/initialize_test.dart` (agent-acp-server «initialize», сценарии «Ответ codelab-app», «Ядро без MCP»): `mcpCapabilities.http` по плану ядра. Ожидаемый кадр `acp/initialize-capabilities` → `http: true` со ссылкой `02-Initialization.md#mcp-capabilities` (правило изменения фикстур). Красный.
- [ ] 6.2 `[protocol]` `_initialize` читает capability `mcp` из `BuiltAgentCore.plan.profile` — 6.1 зелёный.
- [ ] 6.3 `[protocol]` Тесты `session_new_test.dart` и `session_load_test.dart` (agent-acp-server «session/new», «session/load и реплей», новые сценарии):
  - stdio и http отображаются в `McpServerConfig`;
  - `sse` → `mcp.server.skipped`; тест «an MCP server is skipped with mcp.server.skipped» переписан на `sse` (R-02, D11);
  - неизвестный `type` → `mcp.server.skipped` с `reason: unknown transport`, сессия создана; `type: http` без `url` → `-32602` (agent-acp-server «Неизвестный транспорт MCP-сервера», сценарии «Сервер будущего транспорта», «Известный тип по-прежнему строг»);
  - сбой сервера — успешный ответ;
  - серверы загруженной сессии;
  - повторная загрузка открытой сессии с другим набором.

  Красный.
- [ ] 6.4 `[agent]` Тест `codelab_agent_core/test/runtime/set_mcp_servers_test.dart` (agent-runtime «MCP-серверы сессии», `setMcpServers`):
  - совпавшие остаются;
  - исчезнувшие закрыты, новые подключены;
  - серверы конфига не тронуты;
  - во время хода — после `TurnEnded`.

  Красный.
- [ ] 6.5 `[agent]` `AgentSession.setMcpServers`, `McpSessionTools.replaceServers` — 6.4 зелёный.
- [ ] 6.6 `[protocol]` Тест `codelab_acp_protocol/test/session_test.dart` (agent-acp-server «Неизвестный транспорт MCP-сервера», сценарий «Модель сохраняет неизвестный сервер»): `{"type":"websocket","name":"future","extra":1}` → `McpServerUnknown`, `toJson()` равен исходному; известные типы с лишним ключом и нестроковый `type` — по-прежнему ошибка; прежний тест «unknown type throws» переписан. Красный.
- [ ] 6.7 `[protocol]` Вариант `McpServer.unknown({type, name?, raw})` в `codelab_acp_protocol/lib/src/acp/session.dart` (freezed, `toJson` — `raw`), ветки `McpServerUnknown` в исчерпывающих `switch`; перегенерация `session.freezed.dart`; `melos run protocol-conformance` зелёный — 6.6 зелёный.
- [ ] 6.8 `[protocol]` Отображение `acp.McpServer` → `McpServerConfig` в `agent_server.dart` (`McpServerUnknown` и `McpServerSse` — пропуск с причиной), передача в `createSession` / `loadSession`, `setMcpServers` при открытой сессии; удаление пропуска этапа 4 — 6.3 зелёный.

## 7. Формат и фикстуры MCP (D15; P-01, P-16, E-02, R-24)

- [ ] 7.1 `[protocol]` Тест согласованности схемы и загрузчика (acp-golden-fixtures «Формат golden-фикстуры ACP», сценарий «Схема и загрузчик согласованы»): ключи `setup.mcp`, `after.mcpCalls`; `AgentFixtureSetup` отдаёт их фабрике. Красный.
- [ ] 7.2 `[protocol]` `_schema.json`, `fixture.dart`, `agent_conformance.dart` — 7.1 зелёный.
- [ ] 7.3 `[protocol]` Фабрика `codelab_agent_acp/test/conformance_test.dart`:
  - dev-зависимость `codelab_agent_mcp`;
  - fake `McpTransportFactory` по `setup.mcp`: stdio — пара в памяти `FakeMcpServer`;
  - `verify()` сверяет `after.mcpCalls`.

  Тест (сценарий «Лишний вызов MCP-сервера»): фикстура с `after.mcpCalls: {"fake": []}` и вызовом падает с именем сервера.
- [ ] 7.4 `[protocol]` Фикстуры (acp-golden-fixtures «MCP-фикстуры этапа 8»), сначала красные в агентском прогоне, затем зелёные:
  - `acp/session-new-with-mcp` (R-24; серверы обеих эпох — modern `fake` и legacy `old`);
  - `acp/mcp-tool-permission` (P-01);
  - `acp/mcp-stdio-tool-call` (E-02);
  - `acp/mcp-result-fenced` (P-16);
  - `acp/set-mode-plan-rejects-mcp-write` (P-01).

  Роль `agent`, ссылки `spec` по D15. `fvm dart run melos run conformance:agent` зелёный; клиентский прогон их пропускает с причиной.

## 8. Бинарь `codelab-agent` (D3; E-02, R-24)

- [ ] 8.1 `[agent]` Тест `apps/codelab_agent/test/mcp_stdio_process_test.dart` (agent-binary «MCP-серверы в бинаре», сценарий «Реальный stdio-сервер»):
  - реальный бинарь с `--llm-script` и реальный `fake_mcp_stdio_server.dart`;
  - `mcp__fake__echo` после одобрения → `completed` с `hi`;
  - после EOF stdin агента процесс сервера по pid не жив не позже 10 с.

  Красный.
- [ ] 8.2 `[agent]` Сборка в `agent_host.dart`: `McpClientConnector(transports: McpTransports(stdio: StdioMcpTransportFactory(…)))` в `AgentCoreServices.mcp`; зависимость `codelab_agent_mcp` в `pubspec.yaml` бинаря (allowlist из 1.1); точка входа `test/support/fake_mcp_stdio_server.dart` — 8.1 зелёный. До группы 9 профиль сужается до `mcp: {stdio}` с причиной «HTTP-транспорт — итерация 3».
- [ ] 8.3 Проверка итерации 2:
  - проверки затронутого: `codelab_agent_io`, `codelab_agent_acp`, `codelab_acp_testing`, `apps/codelab_agent`;
  - `fvm dart run melos run conformance:agent`, `guard`;
  - PR итерации 2.

## 9. Streamable HTTP и `tools/list_changed` (D6, D10; E-03)

- [ ] 9.1 `[agent]` Тест DoD `codelab_agent_mcp/test/streamable_http_test.dart` на `MockClient` / `MockClient.streaming` с HTTP-обработчиком `FakeMcpServer` обеих эпох (agent-mcp-client «Транспорт streamable HTTP», «Эпоха сервера и версия протокола», сценарий «Legacy-сервер по HTTP»):
  - **обе эпохи:** заголовки `POST`, `202` для уведомлений, ответ JSON, ответ SSE с промежуточным уведомлением и keep-alive-комментарием; `307` не выполняется; схема `ftp` → `invalid url`; тело больше 16 МиБ → ошибка;
  - **modern:** `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method`, `Mcp-Name`, `Mcp-Param-*` из `x-mcp-header` с кодированием `=?base64?…?=`; `-32020` → один `tools/list` и повтор с новым id; нет `Mcp-Session-Id`, GET и `DELETE`; `subscriptions/listen` — долгий поток с `list_changed`; отмена — закрытие потока ответа без POST `notifications/cancelled`;
  - **проба эпохи:** `400` с телом `-32022` → нет общей версии без отката; `400` с пустым телом, `404`, `405` → откат на `initialize`;
  - **legacy:** `Mcp-Session-Id` и `MCP-Protocol-Version` (`2025-06-18`) в следующих запросах, без `MCP-Protocol-Version` для `2025-03-26`; GET-поток при `listChanged`, `405` без потока; `404` → `HTTP session expired`; `DELETE` при закрытии; отмена — `notifications/cancelled` и закрытие потока; поток ответа, закрытый после события `id: e1` с `retry: 100`, возобновлён `GET` с `Last-Event-ID: e1` через 100 мс без второго `tools/call`, не больше 5 возобновлений;
  - **обрыв без возобновления:** `tools/call` — `disconnected during the call` без повтора; `tools/list` и `server/discover` — один повтор с новым id.

  Красный.
- [ ] 9.2 `[agent]` `lib/src/streamable_http.dart` (обе эпохи), зеркальные заголовки modern в `McpClient`, `StreamableHttpTransportFactory`, `McpTransports`; экспорт `SseDecoder` и `ServerSentEvent` из бареля ядра; HTTP-обработчик `FakeMcpServer` для `MockClient` — 9.1 зелёный.
- [ ] 9.3 `[agent]` Тест `codelab_agent_mcp/test/mcp_list_changed_boundary_test.dart` (agent-mcp-client «Обновление списка инструментов», оба сценария; D6):
  - уведомление посреди пакета вызовов применяется к следующему запросу;
  - modern — принимается только с `subscriptionId` своей подписки, legacy — с общего канала;
  - два уведомления → не больше двух `tools/list`;
  - коллизия в новом наборе отключает сервер;
  - секция `mcp` пересобрана;
  - лог `mcp.tools.changed`.

  Красный.
- [ ] 9.4 `[agent]` Перечитывание в `McpClient`, `McpSessionTools.takeUpdate`, применение в `prepareNextStep` → `StepUpdate.context` и перед ходом — 9.3 зелёный.
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
