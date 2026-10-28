Задачи идут парами «тест → реализация» (§9.0, правило 3). В скобках — задача этапа 4 (`dart-agent-and-clients/09-09-stage-4-acp-adapter.md`) и требование спецификации.

Пути — в `packages/dart/codelab_agent_acp/`, если не указано иное. Группы задач по итерациям (design.md, D11):
- группы 1–2 — итерация 1 (каркас соединения);
- группы 3–5 — итерация 2 (ход);
- группы 6–8 — итерация 3 (сессии и опции);
- группы 9–10 — итерация 4 (корпус).

Каждая итерация — отдельный PR в `develop`.

## 1. Пакет, протокол и транспорт в памяти (4.1)

- [x] 1.1 Создать пакет `packages/dart/codelab_agent_acp` (`pubspec.yaml` с allowlist D1, `analysis_options.yaml`, вложенный `AGENTS.md`), добавить в `workspace:` корневого `pubspec.yaml`; правило `codelab_agent_acp` в `codelab_architecture_tests/test/support/rules.dart` и allowlist в `pubspec_allowlist_test.dart`; тест сторожа на временном файле с `import 'dart:io'` (workspace-architecture «Автоматический сторож границ пакетов»)
- [x] 1.2 Тест: `packages/dart/acp_protocol/test/set_session_mode_test.dart` — `SetSessionModeRequest`/`SetSessionModeResponse` по схеме `docs/protocols/acp/protocol/12-Session Model.md`, запись в `acpMethodRegistry`, кодирование и декодирование (design.md, D2) (красный)
- [x] 1.3 Реализовать модели и константу метода `session/set_mode` в `acp_protocol` — 1.2 зелёный
- [x] 1.4 Тест: `packages/dart/acp_testing/test/in_process_acp_link_test.dart` — асинхронная доставка в порядке `send`, глубокая копия, не-JSON значение → `sendFailed`, буфер до `start()`, закрытие одного конца → `failed` у другого, сообщение после закрытия отброшено с диагностикой (design.md, D9; §13.11) (красный)
- [x] 1.5 Реализовать `packages/dart/acp_testing/lib/src/in_process_acp_link.dart` и экспорт из `acp_testing` — 1.4 зелёный

## 2. Каркас соединения (4.1, 4.4)

- [x] 2.1 Тест (agent-acp-server «Правила протокольного уровня»): `test/robustness/bad_frames_test.dart` — сообщения, которые доходят до сервера (сырые кадры разбирает транспорт, D12): неизвестный метод → `-32601`; неизвестное уведомление — лог; параметры не декодируются → `-32602`; исключение обработчика → `-32603`; ответ на неизвестный id — лог `acp.frame.bad`; соединение живо после каждого (ACP-4) (красный)
- [x] 2.2 Тест (agent-acp-server «Соединение ACP-сервера», «initialize»): `test/initialize_test.dart` — ответ по §13.2 с `loadSession` и `sessionCapabilities.list` по `sessionPersistence`; повторный `initialize` и `session/*` до него → `-32600`; `authenticate` → `-32601`; `clientCapabilities` без поля → лог `acp.client_capabilities.absent` (красный)
- [x] 2.3 Реализовать `lib/src/agent_server.dart` (`AcpAgentServer`, `AcpServerConfig`, `AcpTimeouts`), `lib/src/connection/inbound_router.dart`, `outbound_queue.dart`, `pending_requests.dart`, барель `lib/codelab_agent_acp.dart` — 2.1, 2.2 зелёные
- [x] 2.4 Тест (agent-acp-server «session/new», «session/list»): `test/session_new_test.dart` — ответ с `modes` и `configOptions`, `available_commands_update` с пустым списком после ответа и ни одного уведомления до него (ACP-8), относительный `cwd` и несуществующий каталог при локальном листинге → `-32602`, MCP-сервер пропущен с `mcp.server.skipped`; `test/session_list_test.dart` — фильтр по `cwd`, страница, `nextCursor`, неверный `cursor` → `-32602` (красные)
- [x] 2.5 Реализовать `session/new` и `session/list` в `agent_server.dart` и `lib/src/session_bridge.dart`, опции `mode` и `model` в `lib/src/config_options.dart` — 2.4 зелёные
- [x] 2.6 Проверка итерации 1: `fvm dart run melos run check` зелёный (с новым пакетом в `guard`); документ ядра §13 правится там, где реализация уточнила контракт; PR итерации 1

## 3. Env и gate через клиента (4.3)

- [x] 3.1 Тест (agent-execution-env «ListingOverlayEnv»): `packages/dart/codelab_agent_core/test/env/listing_overlay_env_test.dart` — `listDir` от второго env, остальное от первого, общая граница `BoundedEnv` (красный)
- [x] 3.2 Реализовать `packages/dart/codelab_agent_core/lib/src/env/listing_overlay_env.dart` и экспорт — 3.1 зелёный
- [x] 3.3 Тест (agent-acp-server «Запросы агента к клиенту»): `test/acp_client_env_test.dart` на fake-клиенте — общий набор `execution_env_contract.dart` ядра; `fs/*` с абсолютным путём, `line`, `limit`; `stat` через `limit: 1`; `-32002` → `notFound`; таймаут 30 с на `FakeClock`; `exec`: `terminal/create` с `/bin/sh -c`, `env`, `outputByteLimit`; `release` после успеха, ошибки `wait_for_exit`, таймаута и отмены (ACP-9, ENV-7); нет capability → `Err(unsupported)` без кадра; разрыв → `io` «client connection lost» (красный)
- [x] 3.4 Реализовать `lib/src/acp_client_env.dart` — 3.3 зелёный
- [x] 3.5 Тест (agent-acp-server «Запросы агента к клиенту»): `test/acp_permission_gate_test.dart` — `toolCall` с `rawInput`, `locations`, `diff`; четыре варианта и без `allow_always`; `_meta.codelab.critical` у критической команды; неизвестный `optionId`, ошибка JSON-RPC и разрыв → `rejectOnce` с логом; `cancelled` и отмена хода → `cancelled`, поздний ответ игнорируется (PERM-4) (красный)
- [x] 3.6 Реализовать `lib/src/acp_permission_gate.dart` — 3.5 зелёный

## 4. Ход, проекция и итог (4.2)

- [x] 4.1 Тест (agent-acp-server «session/prompt, проекция и итог хода»): `test/projection/every_agent_event_is_projected_test.dart` — список подтипов `AgentEvent` ↔ таблица проекции (ACP-6); `test/projection/event_projection_test.dart` — таблица §13.7 строка за строкой, статусы `pending` → `in_progress` → итог, `outcome` у `cancelled`/`rejected`, `diff` у правок, `terminal` в `content` (красные)
- [x] 4.2 Тест: `test/prompt_test.dart` — ход в фоне; `turnActive`; пустой `prompt` и `audio` → `-32602`; контент `resource`/`resource_link` по §13.4; итог хода по таблице §13.8 (`end_turn`, `max_turn_requests` с `budgetExceeded`, `max_tokens`, `refusal`, `-32603` с `data.codelab`) (ACP-7); 1 000 дельт на медленном транспорте — ответ последний (ACP-3) (красный)
- [x] 4.3 Реализовать `lib/src/event_projection.dart`, фоновый ход и хук `markInProgress` в `session_bridge.dart`, `lib/src/prompt_content.dart` — 4.1, 4.2 зелёные

## 5. Отмена (4.2)

- [x] 5.1 Тест (agent-acp-server «session/cancel»): `test/cancel_test.dart` — отмена во время стрима модели, во время запроса разрешения (ответ `cancelled`), во время `terminal/wait_for_exit` (`kill`, `output`, `release`), ответ всегда `stopReason: cancelled` (ACP-5); отмена без хода — лог `acp.cancel.no_turn`; `session/cancel` как запрос — дополнительно ответ `null` (красный)
- [x] 5.2 Реализовать отмену в `session_bridge.dart` и `pending_requests.dart` — 5.1 зелёный
- [x] 5.3 Проверка итерации 2: `fvm dart run melos run check` зелёный; документ ядра §13 правится там, где реализация уточнила контракт; PR итерации 2

## 6. Каталог и опции в ядре (D3, D4)

- [x] 6.1 Тест (agent-runtime «AgentRuntime и AgentSession», «Минимальная сборка buildAgentCore»): `packages/dart/codelab_agent_core/test/runtime/session_options_test.dart` — каталог по умолчанию из `defaultModel`; `setModel` пишет `model_change`, модели нет в каталоге → `ArgumentError`; `setEffort` пишет `config_change`, запрос несёт усилие только у модели с рассуждением; `loadSession` восстанавливает модель из каталога и усилие; модели журнала нет в каталоге → поведение этапа 3; `SessionHostPorts.extraBeforeToolCall` у загруженной сессии стоит после политики (красный)
- [x] 6.2 Реализовать `AgentCoreServices.models`, `CoreConfig.effort`, `AgentRuntime.models`, `AgentSession.model`/`effort`/`setModel`/`setEffort`, хуки `SessionHostPorts` и восстановление в `loadSession` — 6.1 зелёный

## 7. session/load и опции через ACP (4.1)

- [x] 7.1 Тест (agent-acp-server «session/load и реплей»): `test/session_load_test.dart` — неизвестный id → `-32002`; реплей по правилам §13.5 (слова пользователя, служебные user-записи пропущены, мысли, текст, `tool_call` с итоговым статусом и `diff`, `interrupted`, `compaction` не отправляется); хвост `plan`, `current_mode_update`, `config_option_update`, `available_commands_update`, `session_info_update`; ответ последним (ACP-3); `cwd` запроса выигрывает с записью `codelab.cwd_changed` (красный)
- [x] 7.2 Реализовать `lib/src/replay.dart` и `session/load` в `agent_server.dart` — 7.1 зелёный
- [x] 7.3 Тест (agent-acp-server «Режимы и опции сессии»): `test/config_options_test.dart` — порядок `mode`, `model`, `effort`; `effort` только у модели с рассуждением и сохраняется при смене модели и `session/load` (ACP-10); `set_config_option` для каждой опции, неизвестный `configId` и значение → `-32602`, нет сессии → `-32002`, ответ без дублирующего `config_option_update` (ACP-11); `session/set_mode` → `{}` и `current_mode_update`; синонимы режимов на входе (красный)
- [x] 7.4 Реализовать `session/set_config_option`, `session/set_mode`, опцию `effort` в `config_options.dart` — 7.3 зелёный

## 8. Отсоединение и завершение (4.1)

- [x] 8.1 Тест (agent-acp-server «Отсоединение, переподключение и завершение»): `test/detach_test.dart` на `FakeClock` — закрытие транспорта во время разрешения и загрузка новым соединением в пределах grace → реплей и новый `session/request_permission` с тем же `toolCallId` (PERM-4), итог хода — `session_info_update` с `_meta.codelab.turnEnded`; grace истёк → ход `cancelled`; `detachGrace: Duration.zero` — отмена сразу; `session/load` во время хода в живом соединении → `-32602` `sessionBusy`; `shutdown` — новые запросы `-32603`, ходы отменены, транспорты закрыты (красный)
- [x] 8.2 Реализовать отсоединение, переподключение и `shutdown` в `agent_server.dart` — 8.1 зелёный
- [x] 8.3 Проверка итерации 3: `fvm dart run melos run check` зелёный; документ ядра §13 и §10.7 правятся там, где реализация уточнила контракт; PR итерации 3

## 9. Агентский драйвер и корпус этапа 4 (4.8)

- [x] 9.1 Тест (acp-golden-fixtures «Агентский драйвер фикстур»): `packages/dart/acp_testing/test/agent_conformance_test.dart` на заглушке агента — совпадение кадров, лишний кадр после тишины, лишний запрос `fs/*`, пропуск фикстуры без роли `agent`, неиспользованный шаг модели (красный)
- [x] 9.2 Реализовать `packages/dart/acp_testing/lib/src/fixtures/agent_conformance.dart` (`runAgentFixture`, `AgentFixtureSetup`) — 9.1 зелёный
- [x] 9.3 Тест (acp-golden-fixtures «Инварианты корпуса фикстур»): агентская часть теста покрытия FIX-2 со списком ожидаемого покрытия агента (красный до фикстур 9.4)
- [x] 9.4 Написать 33 фикстуры этапа 4 в `packages/dart/acp_testing/fixtures/acp/` (design.md, D8), у каждой `spec` на раздел `docs/protocols/acp/protocol/` (FIX-1) и `extensions` для `_meta.codelab`/`data.codelab` (FIX-4):
  - сессии: `session-load-replay`, `session-list-cwd-filter`, `session-info-title`, `session-load-interrupted-turn`, `multi-session-concurrent-prompts`;
  - ход и LLM: `prompt-max-turn-requests`, `prompt-failed-provider-auth`, `prompt-streaming-text`, `prompt-thought-chunk`, `prompt-anthropic-tool-call`, `prompt-network-drop`, `prompt-provider-error`, `prompt-cancel-mid-stream`, `prompt-parallel-tool-calls`, `prompt-turn-budget-exceeded`, `prompt-cancel-during-terminal`, `compaction-long-session-continues`;
  - инструменты: `tool-write-permission-diff`, `tool-edit-exact-replace`, `tool-edit-ambiguous-match-error`, `tool-list-dir`, `tool-search-content`, `tool-invalid-args-error`, `tool-exec-terminal-env-array`;
  - разрешения и режимы: `permission-allow-always-scoped`, `permission-critical-pattern-in-bypass`, `permission-options-all-four`, `permission-outcome-cancelled`, `set-mode-bypass-no-prompt`, `set-mode-plan-rejects-edit`, `set-mode-updates-current-mode`;
  - опции и протокол: `config-effort-option`, `errors-bad-frame-survives`
- [x] 9.5 Тест: `test/conformance_test.dart` — фабрика `AcpAgentServer` для драйвера (профиль из `setup.profile`, `MemorySessionStore`, `localListing: LocalExecutionEnv`); прогон 11 фикстур этапа 0 с ролью `agent` и 33 фикстур 9.4; скрипт `conformance:agent` в корневом `pubspec.yaml` и в `check` — расхождения агента с фикстурами исправляются в коде агента, фикстура меняется только со ссылкой на спецификацию (acp-golden-fixtures «Правила изменения фикстур»)

## 10. Contract test и закрытие change (4.7)

- [x] 10.1 Тест: `test/contract/client_application_contract_test.dart` — настоящий `AcpClientApplication` через `InProcessAcpLink` против `AcpAgentServer` на scripted LLM: `prompt response is sent after the last session/update of the turn` (ACP-3), `session/cancel yields stopReason cancelled` (ACP-5), разрешение с выбором варианта, `session/load` с реплеем
- [x] 10.2 Документы: §14.2 документа ядра и `09-09-stage-4-acp-adapter.md` — корпус этапа 4 без фикстур выноса и с транспортными фикстурами в `add-codelab-agent-binary` (D8); §13.12 — ссылки на этот change у расширений D10
- [x] 10.3 Definition of Done change: `fvm dart run melos run check` зелёный, включая `conformance:agent` (44 фикстуры), `guard` и `web-compile`; DoD-тесты этапа `client_application_contract_test.dart`, `every_agent_event_is_projected_test.dart`, `bad_frames_test.dart` зелёные; строки матрицы этапа 4 в части агента имеют доказательства (таблица в design.md добавляется в этой задаче); PR итерации 4
- [x] 10.4 Перед архивированием: `openspec validate add-dart-agent-acp-server --strict`; заполнить Purpose новой спецификации `agent-acp-server`
