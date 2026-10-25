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
