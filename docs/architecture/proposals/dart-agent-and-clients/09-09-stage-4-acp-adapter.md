# 9.9. Этап 4 — ACP-адаптер и codelab-agent

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.8. Этап 3 — Сессии и сжатие](09-08-stage-3-sessions.md) · [Оглавление](../dart-agent-and-clients.md) · [9.10. Этап 5 — Общий клиентский слой](09-10-stage-5-client-kit.md) →

**Цель.** Dart-агент доступен по ACP: codelab-app без изменений работает с ним по stdio, корпус
фикстур проходит против него.

**Задачи.**

1. **4.1. Пакет `packages/dart/codelab_agent_acp`:** `lib/src/agent_server.dart`
   (`AcpAgentServer.serve(AcpTransport transport)`: одно соединение — один клиент, много сессий;
   корреляция исходящих запросов агент → клиент, фоновая обработка `session/prompt`, методы
   `initialize`, `session/new`, `session/load`, `session/list`, `session/prompt`, `session/cancel`,
   `session/set_mode`, `session/set_config_option`), `lib/src/session_bridge.dart` (сессия ACP ↔
   `AgentSession`), `lib/src/replay.dart` (воспроизведение журнала при `session/load`).
   Декодирование параметров — через `AcpMethodDefinition` из `acp_protocol`.
2. **4.2. Проекция событий:** `lib/src/event_projection.dart` по таблице документа ядра
   §13 и тест `test/projection/every_agent_event_is_projected_test.dart`: перечисляет все подтипы
   `AgentEvent` и требует для каждого строку проекции или явную пометку «не передаётся».
3. **4.3. Порты через клиента:** `lib/src/acp_client_env.dart` (`fs/read_text_file`,
   `fs/write_text_file`, `terminal/create` / `output` / `wait_for_exit` / `kill` / `release`,
   таймауты на `fs/*`), `lib/src/acp_permission_gate.dart` (`session/request_permission` с
   `rawInput`, `locations`, diff; отмена хода → ответ `cancelled` обрабатывается как отказ).
4. **4.4. Устойчивость кадров:** неразбираемый JSON → `-32700`, неизвестный метод → `-32601`,
   неверные параметры → `-32602`; соединение и ход живут. Тест `test/robustness/bad_frames_test.dart`.
5. **4.5. Серверные транспорты** в `packages/dart/acp_transports/lib/io.dart`:
   `StdioServerAcpTransport` (stdin/stdout текущего процесса, построчный JSON) и
   `WebSocketServerAcpTransport` (обёртка над принятым `WebSocket` из `dart:io`). Документация
   `AcpTransport.inbound` уточняется: «сообщения от другой стороны соединения».
6. **4.6. Бинарь `apps/codelab_agent`:** `bin/codelab_agent.dart`, `apps/codelab_agent/lib/src/serve.dart`
   (`serve --stdio`, `serve --ws --host 127.0.0.1 --port 8765 --token-env CODELAB_AGENT_TOKEN`),
   загрузка минимальной конфигурации (провайдер, модель, ключ из env), профиль `agent-serve`.
   Флаг только для тестов `--llm-script <file>` подменяет провайдера на `ScriptedStreamFunction`.
   Логи — только в stderr или файл: stdout занят протоколом.
7. **4.7. Contract test клиент ↔ адаптер:**
   `packages/dart/codelab_agent_acp/test/contract/client_application_contract_test.dart` —
   настоящий `AcpClientApplication` через пару транспортов в памяти (тестовая копия
   `InProcessAcpLink`, окончательная версия — этап 7) против `AcpAgentServer` на scripted
   LLM: промпт, отмена, разрешение, `session/load`.
8. **4.8. Conformance агента:** `test/conformance_test.dart` (драйвер `agent_conformance.dart` из `acp_testing`) прогоняет
   весь корпус; скрипт `conformance:agent` входит в `check`.
9. **4.9. Интеграционные тесты app против Dart-агента.** Ввести в
   `apps/codelab_app/integration_test/support/e2e_agent.dart` выбор агента по
   `--dart-define=CODELAB_E2E_AGENT` (`scripted` по умолчанию, `dart-stdio`, позже `embedded`).
   Для `dart-stdio` тест запускает `codelab-agent serve --stdio --llm-script <скрипт>`, где
   скрипт из `integration_test/llm_scripts/` воспроизводит поведение соответствующего режима
   scripted-агента. Применимость — таблица ниже.
10. **4.10. Ручная проверка с Zed:** подключение, промпт, инструменты, одобрение, отмена,
    `session/load`; результат — чек-лист в `design.md` change.

| Интеграционный тест app | Против Dart-агента | Почему |
|---|---|---|
| `stdio_connect_flow_test.dart` | частично: подключение и config options — да; «агент падает на старте», «мусор в stdout», «падение посреди промпта» — только scripted | эти сценарии проверяют устойчивость клиента к плохому агенту |
| `permission_flow_test.dart` | да | LLM-скрипт вызывает `exec`; агент запрашивает разрешение |
| `fs_flow_test.dart` | чтение и запись — да; выход за рабочую папку — только scripted | Dart-агент отклоняет такой путь в `BoundedEnv` и не отправляет запрос клиенту |
| `terminal_flow_test.dart` | исполнение и kill — да; выход за папку — только scripted | то же |
| `plan_progress_checklist_flow_test.dart` | да | LLM-скрипт вызывает `update_plan` |
| `prompt_queue_flow_test.dart` | да | очередь — клиентская |
| `multi_session_concurrency_flow_test.dart` | да | две сессии в одном соединении |
| `open_project_flow_test.dart` | да | проверяет `cwd` сессии |

**OpenSpec change.** `add-dart-agent-acp-server` (задачи 4.1–4.8; scope: методы ACP агентской
стороны, проекция событий, расширение `_meta.codelab.outcome`, маппинг `TurnEnded(failed)`,
повторная доставка `session/request_permission`, `ls`/`search` поверх клиента — открытые вопросы
документа ядра §13 закрываются здесь) и `add-codelab-agent-binary` (задачи 4.5–4.6, 4.9; scope:
CLI агента, серверные транспорты, токен WebSocket).

**Что прочитать.** Документ ядра §13, §10 (профиль `agent-serve`), §7 (`AcpPermissionGate`),
§14; `docs/acp/protocol/05-Prompt Turn.md`, `08-Tool Calls.md`, `09-File System.md`,
`10-Terminal.md`, `12-Session Model.md`; `docs/architecture/acp-boundary.md`.

**Definition of Done.**

* `melos run conformance:agent` — весь корпус зелёный.
* `client_application_contract_test.dart: prompt response is sent after the last session/update of the turn` (ACP-3) и `...: session/cancel yields stopReason cancelled` (ACP-5).
* `every_agent_event_is_projected_test.dart` (ACP-6); `bad_frames_test.dart` (ACP-4).
* `melos run build:agent` даёт `build/bin/codelab-agent`, и он отвечает на `initialize`:
  `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}' | build/bin/codelab-agent serve --stdio --llm-script apps/codelab_agent/test/llm_scripts/hello.json`.
* `melos run test:e2e:app:dart-agent` — применимые тесты из таблицы зелёные.
* Чек-лист Zed заполнен.

**Зависимости.** Этап 3. Этап 4 несёт больше трети Must-строк матрицы, поэтому принимается по
группам фикстур: `acp/session-*`, `acp/prompt-*`, `acp/tool-*`, `acp/permission-*`, `acp/fs-*`,
`acp/terminal-*` — каждая группа отдельным PR.

**Риски.** Неверное прочтение спецификации закрепляется фикстурами — ссылка на раздел в каждой
фикстуре, ручная проверка с Zed и Claude Code ACP. Гонки отмены и разрешения — порядок из §7б
(Python, этап 2) берётся, если фикстура не определяет поведение.

---

← [9.8. Этап 3 — Сессии и сжатие](09-08-stage-3-sessions.md) · [Оглавление](../dart-agent-and-clients.md) · [9.10. Этап 5 — Общий клиентский слой](09-10-stage-5-client-kit.md) →
