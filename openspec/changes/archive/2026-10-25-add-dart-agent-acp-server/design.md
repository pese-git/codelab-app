## Context

Ядро `codelab_agent_core` после этапов 1–3 даёт прямой API: `buildAgentCore` → `AgentRuntime` (`createSession`, `loadSession`, `listSessions`) → `AgentSession` (`prompt`, `cancel`, `setMode`, `events`, `replay`). Журнал сессии, сжатие, разрешения и инструменты работают без протокола.

ACP-сторона репозитория пока клиентская:
- `acp_protocol` содержит модели и кодек всех методов MVP, кроме `session/set_mode`. Кодек симметричный: у каждого метода есть `decodeParams`/`encodeParams`/`decodeResult`/`encodeResult`, а коды JSON-RPC (`-32700` … `-32603`) — в `protocol_error.dart`. Диспетчера входящих запросов нет: клиент разбирает кадры внутри `AcpClientApplication`.
- `acp_transports` — порт `AcpTransport` и клиентские `StdioAcpTransport` / `WebSocketAcpTransport`. Серверных транспортов и пары транспортов в памяти нет.
- `acp_testing` — 12 фикстур этапа 0 (11 с ролью `agent`), загрузчик, матчер и клиентский драйвер. Агентского драйвера и скрипта `conformance:agent` нет.
- Каталог моделей (`ModelCatalog`, `StaticModelCatalog`, задача 1.12) есть в ядре, но не подключён к сборке и сессиям.

Контракт адаптера — алгоритмы, проекция, коды ошибок, инварианты ACP-1 … ACP-12 — описан в принятом документе ядра §13, агентский прогон корпуса — в §14.9. Этот документ фиксирует только то, чего там нет: объём этапа 4, раскладку кода, решения на стыке с ядром и с change `add-codelab-agent-binary`, состав корпуса и порядок итераций. Где ниже нет отдельного решения, действует документ ядра как есть.

## Goals / Non-Goals

**Goals:**
- `AcpAgentServer` обслуживает соединение по любому `AcpTransport` по §13: все методы MVP, фоновый ход, проекция событий, запросы агента к клиенту, правила протокольного уровня.
- Ядро получает то, что нужно адаптеру: каталог моделей, смену модели и усилия рассуждения у сессии, хуки хоста для загруженной сессии, `ListingOverlayEnv`.
- Корпус фикстур проверяет агента так же, как клиента: агентский драйвер в `acp_testing`, фикстуры этапа 4, скрипт `conformance:agent` в `check`.
- Contract test: настоящий `AcpClientApplication` против `AcpAgentServer` в памяти.

**Non-Goals:**
- Бинарь `codelab-agent`, серверные транспорты, конфиг из флагов, e2e-тесты app, проверка с Zed — `add-codelab-agent-binary`.
- Вынос результата и его фикстуры, редакция секретов, slash-команды, MCP — этапы 8 и 1.0 (proposal, «Не входит»).
- Окончательный `InProcessAcpLink` в `acp_transports` и встроенный режим — этап 7.

## Decisions

### D1. Раскладка пакета

```text
packages/dart/codelab_agent_acp/
  lib/codelab_agent_acp.dart          барель: AcpAgentServer, AcpServerConfig, AcpTimeouts
  lib/src/agent_server.dart           AcpAgentServer, соединения, shutdown
  lib/src/connection/
    inbound_router.dart               разбор кадра, маршрутизация, коды ошибок (§13.10)
    outbound_queue.dart               единая очередь исходящих кадров (ACP-3)
    pending_requests.dart             исходящие запросы агента: id, таймаут, отмена
  lib/src/session_bridge.dart         сессия ACP ↔ AgentSession: фоновый ход, ответ по TurnEnded
  lib/src/event_projection.dart       AgentEvent → session/update (§13.7), итог хода (§13.8)
  lib/src/replay.dart                 реплей журнала при session/load (§13.5, шаги 5–7)
  lib/src/config_options.dart         configOptions mode/model/effort (§13.6)
  lib/src/prompt_content.dart         ContentBlock ACP → блоки ядра (§13.4)
  lib/src/acp_client_env.dart         AcpClientExecutionEnv (§4.7, §13.9)
  lib/src/acp_permission_gate.dart    AcpPermissionGate (§7.8)
```

Зависимости `lib/` — `codelab_agent_core`, `acp_protocol`, `acp_transports` (только web-безопасный барель), `meta`, `async`. Без `dart:io`: пакет обслуживает любой транспорт, а локальный листинг и транспорты приходят от хоста. Сторож — правило `codelab_agent_acp` с `webUnsafe` в `rules.dart` (там уже есть комментарий-заготовка этапа 4); allowlist зависимостей пакета — в `pubspec_allowlist_test.dart`.

Маршрутизатор, очередь и реестр запросов — внутри пакета, а не в `acp_protocol`: это поведение агентской стороны соединения (фоновый ход, порядок «уведомления → ответ»), а `acp_protocol` остаётся моделями и кодеком. Альтернатива — общий диспетчер JSON-RPC в `acp_protocol` для клиента и агента — отклонена: клиент свой разбор уже имеет, а общий слой без второго потребителя был бы абстракцией ради абстракции (`AGENTS.md` §13).

### D2. `session/set_mode` в `acp_protocol`

`SetSessionModeRequest {sessionId, modeId}` и `SetSessionModeResponse {}` по схеме `docs/acp/protocol/12-Session Model.md`, константа метода и запись в `acpMethodRegistry`. Обработчик агента — та же функция, что `configId: "mode"`: ответ `{}`, затем `current_mode_update`. Клиентский код не меняется: `AcpClientApplication` метод не вызывает, а тест покрытия методов корпуса (FIX-2) получает его в агентской части (D8).

### D3. Каталог моделей и опции сессии в ядре

`configOptions` требуют списка моделей, а `effort` — признака `supportsReasoning` (§13.6, ACP-10). Ядро получает:

- `AgentCoreServices.models` — `ModelCatalog?`. `null` — каталог из одной `CoreConfig.defaultModel` (тесты и хосты без каталога). Хост этапа 4 (`add-codelab-agent-binary`) передаёт `StaticModelCatalog` моделей из флагов.
- `CoreConfig.effort` — `ReasoningEffort`, по умолчанию `medium` (`agent.effort`, §15.4).
- `AgentRuntime.models` — тот же каталог для адаптера.
- `AgentSession`: `model` (текущая `ModelRef`), `effort`, `setModel(ModelId)` — запись `model_change`, действует со следующего шага; `setEffort(ReasoningEffort)` — запись `config_change {optionId: "effort"}`. Эффективная модель запроса — `catalog.resolve(id, effort: effort)`, поэтому модель без рассуждения параметр не получает (§2.12.3).
- `loadSession` восстанавливает модель журнала через каталог: последняя `model_change` ветки, найденная в каталоге, выигрывает у `CoreConfig.defaultModel`; не найденная — поведение этапа 3 с логом `session.model.not_restored` (завершение D4 change `add-agent-core-sessions-and-compaction`). Усилие — последняя `config_change` с `optionId: "effort"`.

Заметка о смене на модель без рассуждения (§2.12.3, «первым `agent_message_chunk` следующего хода») — часть фикстуры `acp/config-effort-option`; ядро ставит её в начало ответа следующего хода как заметку цикла `LoopNoteOrigin`, а не в журнал.

### D4. Хуки хоста для загруженной сессии

`markInProgress` (§13.7) адаптер передаёт в `SessionSpec.extraBeforeToolCall` новой сессии. У `loadSession` такого параметра нет — `SessionHostPorts` получает `extraBeforeToolCall` и `extraAfterToolCall` с тем же правилом сборки: после проверки разрешений, последними в цепочке (§10.7). `SessionHostPorts.env` и `gate` у загруженной сессии уже есть — ими адаптер подставляет `AcpClientExecutionEnv` и `AcpPermissionGate` своего соединения.

### D5. Env сессии и `ListingOverlayEnv`

`ListingOverlayEnv(ExecutionEnv primary, ExecutionEnv listing)` в `codelab_agent_core/lib/src/env/listing_overlay_env.dart`: `ExecutionEnv` + `DirectoryListing`, `listDir` (и `stat`, если primary его не даёт осмысленно) — от `listing`, остальное — от `primary`. `BoundedEnv` оборачивает результат целиком, поэтому граница одна для обоих (§4.7, §10.4).

`AcpServerConfig.localListing: ExecutionEnv Function(String cwd)?`. Есть — env сессии `ListingOverlayEnv(AcpClientExecutionEnv, localListing(cwd))`, `ls` и `search` работают. Нет — env сессии `AcpClientExecutionEnv`. Env передаётся сессии через `SessionSpec.ports.env` / `SessionHostPorts.env`, а `BoundedEnv` поверх него ставит сама сессия, как для любого env хоста.

Реестр инструментов собирается один раз на ядро (§10.7), а `localListing` — свойство хоста: бинарь по stdio передаёт его, по WebSocket — нет (`add-codelab-agent-binary`). Поэтому `fileListing` сужает хост при сборке, а `AcpAgentServer` проверяет согласованность: capability `fileListing` включена, а `localListing` нет — `HostWiringException` при создании сервера. Без `clientCapabilities.terminal` у соединения `exec` возвращает `Err(unsupported)` и ни одного запроса не отправляет (§4.7).

Проверка `cwd` в `session/new` (§13.4, «каталог не существует → `-32602`») — через `localListing`, если он есть; без него проверяется только абсолютность пути: в ACP нет метода stat каталога.

### D6. Компоненты соединения и фоновый ход

- **`InboundRouter`.** Цикл чтения `transport.inbound`. Запрос → обработчик метода в отдельной задаче; ответ клиента → `PendingRequests` по id; уведомление → обработчик или лог. Исключение обработчика → `-32603`, стек в лог (§13.10).
- **`OutboundQueue`.** Одна цепочка `Future` на соединение: каждый кадр проходит кодек `acp_protocol` (ACP-1) и уходит строго в порядке постановки. Ответ `session/prompt` ставится в очередь событием `TurnEnded` — после всех уведомлений хода (ACP-3). Ответ `session/load` — после реплея.
- **`PendingRequests`.** Id исходящих запросов — `perm-<n>`, `fs-<n>`, `term-<n>` со счётчиком на соединение (§13.9). Каждый запрос — `Completer`, таймаут по `AcpTimeouts` и `CancelToken` хода.
- **Фоновый ход.** `session/prompt` запускает `AgentSession.prompt` без `await` в обработчике, подписка на `events` проецирует события в очередь. Ошибки фонового хода не теряются: они превращаются в итог хода (§13.8) и лог (`AGENTS.md` §12).

Порядок событий ядра и кадров совпадает, потому что проекция синхронно ставит кадры в очередь из подписчика `events`, а `Agent` ждёт каждого подписчика (LOOP-2).

### D7. Отсоединение и переподключение в объёме этапа 4

Событие транспорта `failure` или закрытие `inbound` → соединение `detached`:
- `AcpServerConfig.detachGrace` (по умолчанию 30 с; `Duration.zero` — без ожидания, так хост stdio выражает «конец процесса»);
- за время grace `session/load` той же сессии из нового соединения — переподключение по §13.5, шаг 3b: повторная доставка ожидающих разрешений с новым id и тем же `toolCallId` (PERM-4), итог хода новому соединению — `session_info_update` с `_meta.codelab.turnEnded`;
- grace истёк — ход отменяется, ожидающие разрешения → `cancelled`.

Второй живой клиент сессии — `-32602` с `reason: "sessionBusy"` (MVP, §13.5, шаг 3c). Время grace берётся от `Clock` ядра, поэтому тест идёт на `FakeClock`.

### D8. Корпус этапа 4 и агентский драйвер

Документ ядра §14.2 называет 37 фикстур этапа 4. В этот change входят 33:
- **уходят в `add-codelab-agent-binary`** `acp/ws-auth-bearer-required` и `acp/stdio-framing-large-line`: они проверяют серверные транспорты, а агентский прогон идёт через транспорт в памяти;
- **уходят в `add-agent-core-output-spill`** `acp/tool-exec-spill` и `acp/agent-serve-spill-local-read`: вынос результата перенесён в веху 1.0 после P-10 (PR #57). §14.2 и `09-09-stage-4-acp-adapter.md` правятся в этом change: корпус этапа 4 — 35 фикстур (33 + 2 транспортных), агентский прогон к концу этапа — 46 (11 этапа 0 + 35).

Драйвер `acp_testing/lib/src/fixtures/agent_conformance.dart` — алгоритм §14.9. Он не зависит от пакетов агента: тест `codelab_agent_acp/test/conformance_test.dart` передаёт фабрику, которая поднимает `AcpAgentServer` на агентском конце `InProcessAcpLink` с `localListing: LocalExecutionEnv` (`codelab_agent_io` — dev-зависимость теста). Скрипт `conformance:agent` — `fvm dart test packages/dart/codelab_agent_acp/test/conformance_test.dart`, входит в `check`.

Покрытие FIX-2 получает агентскую часть: каждый метод клиент → агент из `acp_method_codec.dart` и каждый вид `sessionUpdate`, который агент отправляет, встречается хотя бы в одной фикстуре с ролью `agent`, кроме явного списка ожидаемого покрытия (`user_message_chunk` живого хода не бывает — он только в реплее, и так далее).

### D9. `InProcessAcpLink` — тестовая копия в `acp_testing`

Contract test (4.7) и агентский драйвер (4.8) нужны оба, поэтому пара транспортов в памяти — `acp_testing/lib/src/in_process_acp_link.dart` по коду §13.11 (асинхронная доставка, копирование JSON-дерева, буфер до `start()`, закрытие → `failed` у другого конца). На этапе 7 окончательная версия переезжает в `acp_transports`, а копия в `acp_testing` удаляется в том же PR. Альтернатива — сразу в `acp_transports` — отклонена планом этапа (§9.9, задача 4.7): встроенный режим со своими требованиями — этап 7.

### D10. Расширения ACP этого change

По ACP-2 каждое расширение вводит OpenSpec change. Этот change вводит:

| Расширение | Где |
|---|---|
| `_meta.codelab.outcome` = `cancelled` / `rejected` / `interrupted` | `tool_call`, `tool_call_update` со `status: failed` |
| `_meta.codelab.budgetExceeded` | ответ `session/prompt` с `max_turn_requests` |
| `data.codelab` (`errorClass`, `message`, `retryable`, `reason`) | JSON-RPC ошибки |
| `_meta.codelab.turnEnded` | `session_info_update` после переподключения |
| `_meta.codelab.critical` (`critical`, `label`) | `session/request_permission` критической команды (§7.8) |

Фикстуры, которые их ожидают, объявляют `"extensions"` (FIX-4).

### D11. Итерации и TDD

Задачи — пары «тест → реализация», красные тесты коммитятся до кода (§9.0, правило 3). Каждая итерация — отдельный PR в `develop` из `feature/add-dart-agent-acp-server`; ветка создаётся заново от `develop` после слияния.

1. **Каркас соединения.** Пакет, сторож, `session/set_mode` в `acp_protocol`, `InProcessAcpLink`, маршрутизатор, очередь, реестр запросов, `initialize`, `session/new`, `session/list`, коды ошибок и плохие кадры (4.4). DoD: `bad_frames_test.dart`, `initialize_test.dart`, `session_new_test.dart`.
2. **Ход.** `session/prompt` в фоне, проекция (4.2), `session/cancel`, итог хода, `AcpClientExecutionEnv`, `AcpPermissionGate`, `ListingOverlayEnv`, `markInProgress` (4.3). DoD: `every_agent_event_is_projected_test.dart`, тесты env и gate, порядок «уведомления → ответ» на 1 000 дельт.
3. **Сессии и опции.** Каталог и опции в ядре (D3, D4), `session/load` с реплеем, `session/set_config_option`, `session/set_mode`, отсоединение и переподключение (D7). DoD: тесты реплея, опций, ACP-10, переподключения.
4. **Корпус.** Агентский драйвер, 33 фикстуры, contract test (4.7), `conformance:agent` в `check`, правка §14.2 и плана этапа. DoD: агентский прогон 44 фикстур (11 + 33) зелёный, contract test зелёный.

### D12. Уточнения контракта, найденные в итерации 1

Документ ядра правится в том же PR (§13.1, §13.2, §13.11):

- **Сырые кадры разбирает транспорт.** Порт `AcpTransport` отдаёт серверу уже разобранные `JsonRpcMessage`, поэтому неразбираемый JSON (`-32700`) и кадр не JSON-RPC 2.0 (`-32600`) до сервера не доходят. Отвечать на них кодами §13.10 и не закрывать соединение — обязанность серверных транспортов `StdioServerAcpTransport` и `WebSocketServerAcpTransport` (change `add-codelab-agent-binary`). Сервер отвечает на всё, что пришло сообщением: `-32600` (порядок `initialize`), `-32601`, `-32602`, `-32603`, `-32002`, а ответ на неизвестный id и битое уведомление логирует `acp.frame.bad`. Формат фикстур не умеет сырые кадры, поэтому `acp/errors-bad-frame-survives` проверяет только сообщения.
- **`mcpCapabilities.http: false` до этапа 8.** §13.2 ставит `http` по capability `mcp`, а её до этапа 8 нет: серверы из `session/new` пропускаются. Объявить `http: true` значило бы обещать подключение, которого нет. Фикстура `acp/initialize-capabilities` ждёт `true`; в итерации 4 значение в ней сверяется матчером со ссылкой на §13.2 (правило изменения фикстур).
- **`sessionCapabilities` — всегда объект.** Кодек `acp_protocol` пишет `sessionCapabilities` всегда; без `sessionPersistence` в нём нет поля `list` (§13.2: «поле отсутствует» — это `list`).
- **Сервер получает `BuiltAgentCore`.** Возможности `initialize` и проверка `fileListing` (D5) берутся из `CorePlan.profile`, поэтому конструктор — `AcpAgentServer({core, config, logger, clock})`, а не `runtime`. `TraceSink` (§13.1) не вводится в этом change: protocol trace — флаг `--trace-file` бинаря (`add-codelab-agent-binary`).
- **Уведомление после ответа.** Обработчик возвращает `Reply(result, after: …)`; маршрутизатор ставит ответ в очередь, затем выполняет `after`. Так `available_commands_update` уходит после ответа `session/new` (ACP-8) без отдельной синхронизации.
- **`AgentSession.model`** добавлен в итерации 1: опция `model` показывает модель сессии. Каталог и смена модели (D3) — итерация 3.
- **Закрытие конца `InProcessAcpLink`** переводит другой конец в `failed` и закрывает его `inbound` — как EOF у stdio, сервер видит конец соединения по завершению потока.
- **Покрытие FIX-2 клиента** получает элемент `session/set_mode`: codelab-app метод не вызывает (режимы — через `configOptions`), агентскую сторону покрывают фикстуры `acp/set-mode-*`. Это новый элемент протокола, а не возврат покрытого.

### D13. Уточнения контракта, найденные в итерации 2

Документы ядра правятся в том же PR (§4.7, §4.11, §7.8, §13.7, §13.9):

- **Терминал вызова — `ToolContext.onTerminal`.** `exec` передаёт его в `ExecOptions.onTerminal`, а точка исполнения отдаёт `terminalId` событием `ToolCallProgress` с `ToolCallTerminal` — так строка §13.7 «`terminal` в `content`» получает источник. Только добавление в `ToolContext`.
- **`PermissionRequest.pattern` и `criticalLabel`.** Политика кладёт в запрос шаблон «разрешить всегда» (`PermissionKey.pattern`) и метку критического правила. `AcpPermissionGate` называет варианты `Always allow <pattern>` и `Always reject <pattern>` (§13.9; пример §7.8 приведён к этому), а `_meta.codelab.critical` — `{"critical": true, "label": criticalLabel}`. Только добавления.
- **Отмена хода во время вопроса — исход `cancelled`.** Хук политики ставит `Block(outcome: cancelled)`, если токен хода отменён к моменту отказа: вызов отменён до старта (§13.7, «Статусы вызова»). Исход `cancelled` от клиента без отмены хода остаётся отказом `rejected` (PERM-7). Ожидание теста этапа 2 `policy_order_test.dart` («a cancel during the wait is cancelled») приведено к таблице статусов.
- **Таймаут и отмена `fs/*` — `io`.** В `FileErrorCode` нет `timeout`, поэтому таймаут §13.9 — `FileError(io, path, "client did not answer … (timed out)")`, у записи с пометкой `the write may have completed`. У порта `FileSystem` нет токена отмены: мост сессии при `session/cancel` вызывает `AcpClientExecutionEnv.abortPending`, ожидание завершается `io` «aborted».
- **`exec` без `terminal` — `ExecErrorCode.shellUnavailable`.** Кода `unsupported` у `ExecErrorCode` нет; ни одного кадра не уходит, как требует §4.7.
- **`in_progress` после `tool_call`.** События сессии приходят подписчику асинхронно, а хук `markInProgress` вызывается в цикле синхронно. Если `tool_call` вызова ещё не спроецирован, мост откладывает `in_progress` до его проекции — порядок кадров вызова не зависит от планировщика.
- **Автозаголовок — после ответа хода.** *Пересмотрено в D15:* ответ `session/prompt` ставится после возврата `AgentSession.prompt`, поэтому автозаголовок идёт до ответа, как ждут фикстуры этапа 0.
- **Ответ сбоя хода.** `message` ошибки `-32603` — `Turn failed: <текст>`; `retryable: true` только у классов провайдера `network`, `timeout`, `rateLimited`, `server`.
- **Разрыв соединения.** После конца входящего потока `PendingRequests` отвечает на новые запросы агента сразу `ClientDisconnected`, без кадра и без ожидания таймаута.
- **Общий набор env для клиента.** `execution_env_contract.dart` получает `clientBacked`: клиент различает только «не найдено» (`-32002`), поэтому набор требует ошибку-значение без точного кода, а `stat` — файл без размера и без каталогов (§4.7).
- **Проверка ACP-6 без `dart:mirrors`.** Тест читает подтипы `AgentEvent` из исходника иерархии и сверяет с `projectionTable`; исчерпывающий `switch` без `default` ловит обратное при компиляции.

### D14. Уточнения контракта, найденные в итерации 3

Документы ядра правятся в том же PR (§5.6, §10.7, §13.5, §13.6):

- **`loadSession(…, cwd:)`.** Рабочую папку задаёт клиент (§13.5, шаг 2), поэтому у `loadSession` есть `cwd`. Отличается от заголовка — сессия работает в новой папке (`BoundedEnv` по ней), а в конце загрузки, после ремонта, пишется `custom` `codelab.cwd_changed` с `{from, to}`. Только добавление.
- **`FixedModelCatalog`.** Каталог по умолчанию (D3) — `FixedModelCatalog([defaultModel])`: готовые `ModelRef` без разрешения метаданных; уровень рассуждения получает только модель с `supportsReasoning`. Хост этапа 4 передаёт `StaticModelCatalog`.
- **Смена модели посреди хода.** `setModel` и `setEffort` меняют модель агента для следующих ходов, а идущему ходу отдают её хуком `prepareNextStep` сессии на границе шага; идущий запрос не прерывается.
- **Заметка §2.12.3 — в мосте ACP.** D3 называл ядро, но смена через `session/set_config_option` — запрос ACP, а заметка не пишется в журнал и не уходит модели. Поэтому её ставит мост сессии первым `agent_message_chunk` следующего хода; смена обратно на модель с рассуждением заметку снимает.
- **Хвост реплея.** `plan` — только если план был; `session_info_update` — только если у сессии есть заголовок: пустое уведомление клиенту ничего не сообщает.
- **Открытая сессия без хода.** `session/load` из другого соединения переносит её туда (§13.5, шаг 3a): запросы, очередь и возможности клиента — нового соединения, прежнее перестаёт получать её кадры. После отсоединения без хода сессия остаётся открытой в сервере до `session/load` или `shutdown`.
- **`sessionBusy`.** Любой `session/load` сессии, ход которой идёт в живом соединении (в том числе в том же), — `-32602` с `reason: "sessionBusy"`.
- **Отсоединение.** Пока соединения нет, кадры сессии отбрасываются: события в журнале, а реплей отдаст их новому соединению. Ожидающий запрос разрешения не становится отказом: `AcpPermissionGate` ждёт переподключения (`waitForReconnect` моста) и после ответа `session/load` спрашивает снова — с id нового соединения и тем же `toolCallId`. Grace истёк — ход отменяется, вопрос даёт `cancelled`.
- **`_meta.codelab.turnEnded` при сбое.** Итог хода, переживший переподключение, — `{"stopReason": …}`, а при сбое хода — `{"error": data.codelab}` (§13.8).
- **`shutdown`.** Ходы отменяются и дожидаются `TurnEnded` не дольше `grace`, затем сессии закрываются, а соединение перед закрытием транспорта отвечает на начатые запросы (`InboundRouter.drained`) — ответ отменённого хода уходит до закрытия.

### D15. Уточнения контракта, найденные агентским прогоном корпуса (итерация 4)

Агентский прогон 44 фикстур нашёл расхождения агента и клиента с контрактом. Исправлено в коде, документы ядра правятся в том же PR (§4.7, §13.7, §14.2, §14.4, §14.7, §14.9, 09-09):

- **Ответ хода — по возврату `AgentSession.prompt`.** После `TurnEnded` сессия ещё пишет автозаголовок; мост отвечает на `session/prompt`, когда `prompt` вернулся, поэтому `session_info_update` идёт до ответа (фикстуры этапа 0). События сессии к этому моменту уже доставлены: их микрозадачи поставлены раньше. Мост передаёт ходу свой `CancelToken`: `session/cancel`, пришедший до старта цикла, не теряется.
- **Порядок кадров вызова.** Запрос разрешения ждёт, пока `tool_call` его вызова встанет в очередь (`SessionBridge.announced`), а `terminal/wait_for_exit` — пока в очередь встанет `tool_call_update` с терминалом (`AcpClientExecutionEnv.terminalShown`): события сессии приходят подписчику асинхронно, а gate и env работают синхронно с циклом.
- **Один `present()` на вызов.** Точка исполнения кладёт представление в `ToolContext.presentation`, политика берёт его для запроса разрешения: через клиента каждый `present()` — кадр `fs/read_text_file`. Только добавление поля.
- **Формы кадров.** `ToolCallProgress` — `tool_call_update` со `status: in_progress`; у отменённого вызова `tool_call_update` без `content` (§13.7: статус и outcome); пустые `locations` и `content` не отправляются. `read` без `path` в сырых аргументах — заголовок `read` без мест.
- **`ListingOverlayEnv.stat` — от листинга.** В ACP нет stat каталога, а `search` начинает со stat корня (D5 это допускал). Содержимое файлов `search` читает через клиента — клиент видит несохранённые правки; фикстура `acp/tool-search-content` закрепляет эти кадры.
- **Рабочая папка-ссылка.** `session/new` проверяет каталог по разрешённому пути: ссылка на каталог (`/tmp` на macOS) — допустимая рабочая папка.
- **`mcpCapabilities.http: false`** в фикстурах `acp/initialize-capabilities`, `acp/session-new-modes-config`, `acp/set-config-option-model` — правка по §13.2 и D12: до этапа 8 MCP-серверы не подключаются.
- **Формат фикстур.** `setup.sessions` — журналы сессий до сценария (прерванный ход не получить кадрами); шаг с `waitForCancel` и `reply` сначала отдаёт ответ, затем ждёт отмены (отмена посреди стрима без гонки). `acp/set-config-option-model` получает модели каталога в `setup.config.providers`, `acp/prompt-cancel-mid-tool` — необязательный кадр заголовка, как остальные фикстуры. Фабрика прогона читает ключи конфига `agent.default_model`, `agent.effort`, `budget.max_steps`, `budget.max_tokens`, `compaction.keep_recent_tokens`, `providers.<id>.models.<model>` (`context_window`, `reasoning`); другой ключ — провал.
- **Клиент: «файла нет» — `-32002`.** `acp_client_core` отвечал на чтение отсутствующего файла `-32603`, и создание нового файла через codelab-app ломалось: агент отличает отсутствие файла только по `-32002` (§4.7). Добавлены `FsNotFoundFailure`, вид `AcpProtocolErrorKind.resourceNotFound` и распознавание в адаптере `text_file_io.dart`; дельта спецификации `acp-fs-client`.
- **Роли фикстур.** Фикстуры загрузки и списка сессий, смены режима методом `session/set_mode`, плохих кадров, параллельных сессий и опции `effort` — только `agent`: клиентский драйвер не играет эти сценарии (`AcpClientApplication` не применяет реплей к ещё не открытой сессии, не вызывает `session/set_mode`). Остальные новые фикстуры проходят и клиентский прогон с проверками состояния.
- **Драйвер.** Стандартный handshake агентского драйвера — `initialize`, `session/new` и необязательный `available_commands_update`; в конце прогона драйвер сначала закрывает клиентский конец: ожидания агента завершаются разрывом, а не таймаутами `FakeClock`.

Доказательства строк матрицы целей (`agent-parity-goals.md`) этапа 4 в части агента — агентский прогон `conformance:agent`:

| Цель | Фикстуры |
|---|---|
| L-04 | `acp/prompt-network-drop`, `acp/prompt-provider-error`, `acp/prompt-failed-provider-auth` |
| L-05 | `acp/prompt-cancel-mid-stream` |
| L-16 | `acp/config-effort-option` |
| C-02 | `acp/prompt-max-turn-requests` |
| C-05, R-09 | `acp/prompt-update-plan` |
| C-13 | `acp/prompt-turn-budget-exceeded` |
| T-01 | `acp/tool-read-range` |
| T-03 | `acp/tool-write-permission-diff` |
| T-04 | `acp/tool-edit-exact-replace`, `acp/tool-edit-ambiguous-match-error` |
| T-08 | `acp/tool-exec-terminal-embed`, `acp/tool-exec-terminal-env-array` |
| T-09 | `acp/prompt-cancel-during-terminal`, `acp/prompt-cancel-mid-tool` |
| P-02 | `acp/prompt-tool-permission-allow`, `acp/permission-critical-pattern-in-bypass` |
| P-04 | `acp/prompt-tool-permission-reject-continues` |
| P-05 | `acp/set-mode-bypass-no-prompt`, `acp/set-mode-plan-rejects-edit` |
| S-02, R-03 | `acp/session-load-replay` |
| S-03, R-04 | `acp/session-list-cwd-filter` |
| S-05 | `acp/session-info-title` |
| S-13 | `acp/session-load-interrupted-turn` |
| R-01 | `acp/initialize-capabilities` |
| R-05 | `acp/set-mode-updates-current-mode` |
| R-06 | `acp/set-config-option-model`, `acp/config-effort-option` |
| R-10 | `acp/permission-options-all-four`, `acp/permission-outcome-cancelled` |
| R-11 | `acp/multi-session-concurrent-prompts` |

Вне этого change: R-12 и R-13 (`acp/ws-auth-bearer-required`, `acp/stdio-framing-large-line`) — `add-codelab-agent-binary`; R-02 с MCP (`acp/session-new-with-mcp`) — этап 8; D-01 и D-02 — тесты codelab-app против бинаря.

### D16. Известные отклонения от ACP после этапа 4

Сверка `AcpAgentServer` с `docs/acp/protocol/` после итерации 4. Методы клиент → агент, все виды `session/update`, `stopReason`, статусы вызова, запросы `fs/*` и `terminal/*` реализованы по спецификации. Расхождений два, оба — решения, а не пропуски; таблица — в §13.15 документа ядра:

- **MCP по stdio (MUST в `03-Session Setup.md`).** До этапа 8 серверы из `mcpServers` пропускаются с логом `mcp.server.skipped` (D12: `mcpCapabilities.http: false`). В профиле `mobile` stdio пропускается и после этапа 8.
- **Только POSIX-пути.** `cwd` вида `C:\…` получает `-32602`: ядро в MVP работает только с POSIX-путями (§4.4, §4.7 документа ядра). Принять такой `cwd` только в `session/new` нельзя — граница рабочей папки, пути `fs/*` и `terminal/*`, `diff` и `locations` считаются по правилам POSIX. Перевод путей на границе ACP — открытый вопрос §16.3 до поддержки Windows-хоста.

Не отклонение, но записано в §13.15: сбой аутентификации провайдера — `-32603` с `errorClass: "auth"`, а не `auth_required` (`-32000`): `authMethods` пуст, и `authenticate` клиенту предложить нечего (§13.3).

Пропуски, которые ACP разрешает: пустой `available_commands_update` (slash-команды не входят в change, proposal «Не входит»), нет `rawOutput` у вызовов, `audio: false`, бинарный ресурс и `resource_link` в промпте доходят до модели пометкой (§13.4).

## Risks / Trade-offs

- **[Неверное прочтение спецификации закрепляется фикстурами]** → у каждой фикстуры ссылка `spec` на раздел `docs/acp/protocol/` (FIX-1); клиентский прогон тех же фикстур против `AcpClientApplication` показывает расхождение агента и клиента; ручная проверка с Zed — в `add-codelab-agent-binary`.
- **[Гонки отмены, разрешения и ответа хода]** → одна исходящая очередь на соединение и ответ хода из события `TurnEnded` (D6); тесты отмены во время запроса разрешения и во время `terminal/wait_for_exit`; если фикстура не задаёт порядок, берётся порядок §7б плана (Python, этап 2).
- **[Фоновая ошибка хода теряется]** → обработчик хода завершает `Future` всегда: итог по §13.8, иначе `-32603` и лог; тест исключения в подписчике.
- **[Ядро меняет публичный API ради адаптера]** → только добавления (D3, D4), без изменения существующих сигнатур; тесты этапов 1–3 не меняются, кроме сборки с каталогом.
- **[Тестовая копия `InProcessAcpLink` расходится с окончательной]** → код по §13.11 дословно, тест семантики (асинхронность, копирование, буфер, закрытие) переезжает вместе с ним на этапе 7.
- **[Журнал этапов 4–7 хранит секреты из вывода инструментов]** → известное ограничение до задачи 8.11 (P-10); агентский прогон использует `MemorySessionStore`.

## Migration Plan

Новый пакет, клиенты не меняются. `acp_protocol` получает только новый метод. Откат — revert PR итерации.

## Open Questions

- Нужна ли `AcpServerConfig.allowLocalExecFallback` в этапе 4: без `clientCapabilities.terminal` `exec` выключен; локальный `exec` агента при stdio — решение хоста `add-codelab-agent-binary`. Поле не вводится и убрано из эскиза §13.1.
