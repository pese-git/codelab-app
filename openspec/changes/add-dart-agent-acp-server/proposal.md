## Why

Этапы 1–3 дали ядро Dart-агента с прямым API `AgentRuntime` / `AgentSession`: ход, инструменты, разрешения, журнал сессий и сжатие. Но ни codelab-app, ни Zed, ни будущий `codelab` CLI не умеют говорить с ядром напрямую: клиенты работают только по ACP (`AGENTS.md` §5, ADR-0001). Пока нет ACP-адаптера, Dart-агент невидим для клиентов, а корпус golden-фикстур проверяет только клиента.

Этап 4 (`docs/architecture/proposals/dart-agent-and-clients/09-09-stage-4-acp-adapter.md`) делает агента доступным по ACP. Этот change закрывает его серверную часть — задачи 4.1–4.4, 4.7 и 4.8: пакет `codelab_agent_acp`, проекцию событий, запросы агента к клиенту, устойчивость кадров, contract test с `AcpClientApplication` и агентский прогон корпуса. Бинарь `codelab-agent`, серверные транспорты stdio и WebSocket и e2e-тесты app (задачи 4.5, 4.6, 4.9, 4.10) — следующий change `add-codelab-agent-binary`. Источник решений — принятый документ ядра `agent-core-architecture.md`: §13 (адаптер), §14.9 (conformance агента), §4.7 (`AcpClientExecutionEnv`), §7.8 (`AcpPermissionGate`), §10.4 (листинг поверх клиента), §2.12 (каталог моделей), §16.2 (решённые вопросы).

Этап несёт больше трети Must-строк матрицы (`agent-parity-goals.md`, сводка по этапам: 29). Серверная часть даёт им доказательства через ACP: L-04, L-05, C-02, C-05, T-01, T-03, T-04, T-08, T-09, P-02, P-04, P-05, S-02, S-03, S-05, S-13, R-01 … R-06, R-09 … R-13 — в части агента; D-01, D-02 закрываются e2e-тестами app в `add-codelab-agent-binary`.

## What Changes

- **Пакет `packages/dart/codelab_agent_acp` (4.1).** `AcpAgentServer.serve(AcpTransport)`: одно соединение — один клиент, много сессий. Внутри соединения — маршрутизатор входящих кадров, единая исходящая очередь и реестр исходящих запросов агента (§13.1). Методы `initialize`, `session/new`, `session/load` (с реплеем журнала), `session/list`, `session/prompt` (ход в фоне), `session/cancel`, `session/set_mode`, `session/set_config_option` (§13.2–§13.7). Отсоединение и переподключение с `detachGrace`, безопасное завершение (§13.10).
- **Модели `session/set_mode` в `acp_protocol`.** `SetSessionModeRequest` / `SetSessionModeResponse` и запись в реестре методов — метод есть в спецификации ACP (`docs/acp/protocol/12-Session Model.md`), но не в моделях (§13.6, §16.2).
- **Проекция событий (4.2).** `AgentEvent` → `session/update` по таблице §13.7 исчерпывающим `switch`; итог хода → ответ `session/prompt` по §13.8, сбой хода — JSON-RPC `-32603` с `data.codelab`, а не `end_turn` (ACP-7). Хук `markInProgress` — статус `in_progress` после проверки разрешений.
- **Запросы агента к клиенту (4.3).** `AcpClientExecutionEnv` (`fs/*`, `terminal/*` с таймаутами и обязательным `terminal/release`, ENV-7), `AcpPermissionGate` (`session/request_permission`, отмена → отказ). `ListingOverlayEnv` в ядре: `ls` и `search` по локальной ФС агента, когда хост передал `localListing` (stdio), остальное — через клиента (§4.7, §10.4).
- **Устойчивость кадров (4.4).** `-32700`, `-32600`, `-32601`, `-32602`, `-32603`, `-32002`; плохой кадр не закрывает соединение и не прерывает ходы (ACP-4).
- **Опции сессии.** `configOptions` — `mode`, `model`, `effort` (§13.6). Ядро получает каталог моделей в сервисах сборки и API смены модели и усилия рассуждения у сессии; `session/load` восстанавливает модель журнала через каталог (завершение D4 change `add-agent-core-sessions-and-compaction`).
- **Расширения ACP** (каждое — через этот change, ACP-2): `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded`, `data.codelab` (`errorClass`, `message`, `retryable`, `reason`), `_meta.codelab.turnEnded`, `_meta.codelab.critical` у запроса разрешения критической команды.
- **Contract test (4.7).** Настоящий `AcpClientApplication` против `AcpAgentServer` через пару транспортов в памяти — тестовая копия `InProcessAcpLink` в `acp_testing` (окончательная — этап 7 в `acp_transports`).
- **Агентский прогон корпуса (4.8).** Драйвер `agent_conformance.dart` в `acp_testing` по алгоритму §14.9, тест `codelab_agent_acp/test/conformance_test.dart`, скрипт `conformance:agent` в `melos run check`. Фикстуры этапа 4, проверяемые через транспорт в памяти, и 11 фикстур этапа 0 с ролью `agent`.
- **Сторож и workspace.** Пакет в `workspace:` корневого `pubspec.yaml`, правило `codelab_agent_acp` в `codelab_architecture_tests` (без `dart:io` и `package:flutter`), allowlist зависимостей, вложенный `AGENTS.md`.

Не входит:
- бинарь `apps/codelab_agent`, `StdioServerAcpTransport` и `WebSocketServerAcpTransport`, минимальный конфиг из флагов, `--llm-script`, e2e-тесты app, ручная проверка с Zed и фикстуры `acp/ws-auth-bearer-required`, `acp/stdio-framing-large-line` — change `add-codelab-agent-binary`;
- фикстуры `acp/tool-exec-spill` и `acp/agent-serve-spill-local-read`: вынос результата (T-28) — веха 1.0, после редакции секретов P-10 (этап 8); фикстуры переходят в change `add-agent-core-output-spill`;
- встроенные slash-команды (`/compact`, `/mode`, `/model`, `/status`, `/help`) и их фикстуры — этап 8 (задача 8.7): `available_commands_update` уходит с пустым списком;
- MCP-серверы из `session/new` — этап 8: `mcpServers` декодируется, сервер пропускается с логом `mcp.server.skipped`;
- второй клиент той же сессии, lease, запечатывание, steering и прочие расширения после MVP (§13.12).

## Capabilities

### New Capabilities
- `agent-acp-server`: ACP-адаптер Dart-агента — соединение и его компоненты, `initialize`, `session/new`, `session/load` с реплеем, `session/list`, `session/prompt` и проекция событий, `session/cancel`, режимы и опции, итог хода, запросы агента к клиенту (`AcpClientExecutionEnv`, `AcpPermissionGate`), правила протокольного уровня и коды ошибок, отсоединение и переподключение, расширения `_meta.codelab` / `data.codelab`.

### Modified Capabilities
- `agent-runtime`: «AgentRuntime и AgentSession» — смена модели и усилия рассуждения у сессии, текущие опции сессии, хуки хоста для загруженной сессии; «Минимальная сборка buildAgentCore» — каталог моделей в сервисах сборки и восстановление модели журнала при загрузке.
- `agent-execution-env`: новое требование `ListingOverlayEnv` — `DirectoryListing` от локального env поверх env клиента под одной границей `BoundedEnv`.
- `acp-golden-fixtures`: новое требование «Агентский драйвер фикстур»; «Инварианты корпуса фикстур» — агентская часть покрытия (FIX-2) и состав корпуса этапа 4.
- `workspace-architecture`: «Автоматический сторож границ пакетов» — правило пакета `codelab_agent_acp`.

## Impact

- **Новый пакет** `packages/dart/codelab_agent_acp` (зависимости — `codelab_agent_core`, `acp_protocol`, `acp_transports` (web-безопасный барель), `meta`, `async`; dev — `acp_testing`, `acp_client_core`, `codelab_agent_io`, `test`).
- **`acp_protocol`**: модели `session/set_mode` и запись в `acpMethodRegistry`; клиентский код не меняется.
- **`acp_testing`**: `InProcessAcpLink` (тестовая копия), `agent_conformance.dart`, новые фикстуры в `fixtures/acp/`; клиентский драйвер не меняется.
- **`codelab_agent_core`**: `ListingOverlayEnv`; каталог моделей в `AgentCoreServices`; `AgentSession.setModel` и смена усилия рассуждения с записью `model_change` / `config_change`; `SessionHostPorts` получает хуки хоста для `loadSession`.
- **Корень**: `workspace:` и скрипт `conformance:agent` в `check`; правило сторожа.
- **Документы**: `agent-core/13-acp-adapter.md`, `14-golden-fixtures.md` (§14.2 — состав корпуса этапа 4 без фикстур выноса), `09-09-stage-4-acp-adapter.md` правятся в том же PR там, где реализация уточнит контракт.
- Клиенты (`apps/codelab_app`) не меняются. ACP-контракт не меняется, кроме перечисленных расширений и стандартного `session/set_mode`.
