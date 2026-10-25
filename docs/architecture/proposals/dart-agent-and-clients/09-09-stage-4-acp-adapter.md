# 9.9. Этап 4 — ACP-адаптер и codelab-agent

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

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
   Декодирование параметров — через `AcpMethodDefinition` из `acp_protocol`. Модели
   `SetSessionModeRequest`/`SetSessionModeResponse` добавляются в `acp_protocol` (решено,
   agent-core-architecture §13.6, §16.2); обработчик — тот же, что для `configId: "mode"`.
   `configOptions` — `mode`, `model`, `effort` (§13.6; `effort` — только у модели с
   `supportsReasoning` из каталога задачи 1.12, ACP-10). После ответа на `session/new` —
   `available_commands_update` с пустым списком: встроенных slash-команд на этапе 4 нет, они
   приходят на этапе 8 (задача 8.7, §13.4).
2. **4.2. Проекция событий:** `lib/src/event_projection.dart` по таблице документа ядра
   §13 и тест `test/projection/every_agent_event_is_projected_test.dart`: перечисляет все подтипы
   `AgentEvent` и требует для каждого строку проекции или явную пометку «не передаётся».
3. **4.3. Порты через клиента:** `lib/src/acp_client_env.dart` (`fs/read_text_file`,
   `fs/write_text_file`, `terminal/create` / `output` / `wait_for_exit` / `kill` / `release`,
   таймауты на `fs/*`), `lib/src/acp_permission_gate.dart` (`session/request_permission` с
   `rawInput`, `locations`, diff; отмена хода → ответ `cancelled` обрабатывается как отказ).
   `ListingOverlayEnv` в ядре (`codelab_agent_core/lib/src/env/listing_overlay_env.dart`):
   `ExecutionEnv` + `DirectoryListing`, `listDir` — от второго env, остальное — от первого.
   `AcpAgentServer` принимает от хоста `localListing: ExecutionEnv Function(String cwd)?`; при
   нём env сессии — `BoundedEnv` над `ListingOverlayEnv(AcpClientExecutionEnv, localListing(cwd))`,
   и `ls`/`search` включены; без него (WebSocket) — выключены с причиной (§4.7, §10.4, §16.2).
4. **4.4. Устойчивость кадров:** неразбираемый JSON → `-32700`, неизвестный метод → `-32601`,
   неверные параметры → `-32602`; соединение и ход живут. Тест `test/robustness/bad_frames_test.dart`.
5. **4.5. Серверные транспорты** в `packages/dart/acp_transports/lib/io.dart`:
   `StdioServerAcpTransport` (stdin/stdout текущего процесса, построчный JSON) и
   `WebSocketServerAcpTransport` (обёртка над принятым `WebSocket` из `dart:io`). Документация
   `AcpTransport.inbound` уточняется: «сообщения от другой стороны соединения».
6. **4.6. Бинарь `apps/codelab_agent`:** `bin/codelab_agent.dart`, `apps/codelab_agent/lib/src/serve.dart`
   (`serve --stdio`, `serve --ws --host 127.0.0.1 --port 8765 --token-env CODELAB_AGENT_TOKEN`),
   профиль `agent-serve`; по stdio сервер получает `localListing: (cwd) => LocalExecutionEnv(cwd)`.
   Логи — только в stderr или файл: stdout занят протоколом. **Минимальный конфиг до этапа 8**
   (файлы конфига не читаются, agent-core-architecture §15.6):
   * `--provider openai-compatible|anthropic`, `--base-url <url>`, `--model <model>` (можно
     повторять: первое значение — модель по умолчанию, все — модели провайдера `cli` в
     каталоге 1.12), ключ — из переменной `CODELAB_API_KEY`; `--model` без `--provider` и
     переменная `CODELAB_MODEL` — как в §15.6 (`provider/model`);
   * `--permission-mode <mode>` (`CODELAB_PERMISSION_MODE`), `--log-level`, `--log-file` — по §15.6;
     остальные ключи — значения по умолчанию §15.4;
   * `--llm-script <file.json>` — только для тестов, в справке скрыт: вместо провайдера
     `ScriptedStreamFunction` из файла `{"llm": {"model": {...}, "steps": [...]}}` — того же
     формата, что блок `llm` фикстуры (§14.7: шаги по порядку, `expect` — утверждение,
     переменные `${cwd}` и `${sessionId}`); провайдер — `scripted`, `--model` задаёт его модели;
     один сценарий на процесс, шаги общие для всех сессий соединения; сессии — в
     `MemorySessionStore`, в `$CODELAB_HOME` ничего не пишется;
   * на этапе 8 YAML-конфиг (задача 8.5) заменяет этот минимум, флаги остаются переопределениями.
   Задача владеет `apps/codelab_agent/test/llm_scripts/hello.json` (один шаг: ответ `hello`,
   `stopReason: stop`) — его использует проверка DoD — и тестом
   `apps/codelab_agent/test/serve_flags_test.dart` (разбор флагов, ошибка на `--provider` вместе с
   `--llm-script`, ключ не попадает в лог).
7. **4.7. Contract test клиент ↔ адаптер:**
   `packages/dart/codelab_agent_acp/test/contract/client_application_contract_test.dart` —
   настоящий `AcpClientApplication` через пару транспортов в памяти (тестовая копия
   `InProcessAcpLink`, окончательная версия — этап 7) против `AcpAgentServer` на scripted
   LLM: промпт, отмена, разрешение, `session/load`.
8. **4.8. Драйвер агентской проверки и conformance агента.** Драйвер
   `packages/dart/acp_testing/lib/src/fixtures/agent_conformance.dart` создаётся здесь (на этапе 0
   был только клиентский): алгоритм agent-core-architecture §14.9 — агент в профиле `agent-serve`
   на агентском конце `InProcessAcpLink` (тестовая копия из 4.7), файлы и команды через ACP
   (`AcpClientExecutionEnv`), поэтому кадры `fs/*` и `terminal/*` — часть фикстуры, а ответы
   клиента берутся из её кадров `c2a`; `MemoryExecutionEnv` — только для тестов `core/*`. Драйвер
   берёт фикстуры, у которых `roles` содержит `agent`, и не зависит от пакетов агента: тест
   `packages/dart/codelab_agent_acp/test/conformance_test.dart` передаёт ему фабрику агента.
   Фикстуры этапа 0 уже содержат кадры `fs/*` и `terminal/*` (задача 0.7), поэтому входят в
   агентский прогон без правки. Скрипт `conformance:agent` входит в `check`. Корпус этапа 4 —
   ровно 35 фикстур (§14.2): 33 в change `add-dart-agent-acp-server` и 2 транспортные в
   `add-codelab-agent-binary`; вместе с 11 фикстурами этапа 0 с ролью `agent` агентский прогон
   к концу этапа покрывает 46 (44 после `add-dart-agent-acp-server`):
   * сессии: `acp/session-load-replay`, `acp/session-list-cwd-filter`, `acp/session-info-title`,
     `acp/session-load-interrupted-turn`, `acp/multi-session-concurrent-prompts`;
   * ход и LLM: `acp/prompt-max-turn-requests`, `acp/prompt-failed-provider-auth`,
     `acp/prompt-streaming-text`, `acp/prompt-thought-chunk`, `acp/prompt-anthropic-tool-call`,
     `acp/prompt-network-drop`, `acp/prompt-provider-error`, `acp/prompt-cancel-mid-stream`,
     `acp/prompt-parallel-tool-calls`, `acp/prompt-turn-budget-exceeded`,
     `acp/prompt-cancel-during-terminal`, `acp/compaction-long-session-continues`;
   * инструменты: `acp/tool-write-permission-diff`, `acp/tool-edit-exact-replace`,
     `acp/tool-edit-ambiguous-match-error`, `acp/tool-list-dir`, `acp/tool-search-content`,
     `acp/tool-invalid-args-error`, `acp/tool-exec-terminal-env-array` (фикстуры выноса
     `acp/tool-exec-spill`, `acp/agent-serve-spill-local-read` перенесены в
     `add-agent-core-output-spill`, веха 1.0);
   * разрешения и режимы: `acp/permission-allow-always-scoped`,
     `acp/permission-critical-pattern-in-bypass`, `acp/permission-options-all-four`,
     `acp/permission-outcome-cancelled`, `acp/set-mode-bypass-no-prompt`,
     `acp/set-mode-plan-rejects-edit`, `acp/set-mode-updates-current-mode`;
   * опции и протокол: `acp/config-effort-option`, `acp/errors-bad-frame-survives`,
     `acp/ws-auth-bearer-required`, `acp/stdio-framing-large-line`.

   Встроенные slash-команды — этап 8: `acp/slash-help`, `acp/slash-mode-plan`,
   `acp/available-commands-no-tools`; после этапа 9 — `acp/prompt-usage-meta` (расширение usage,
   §16.3) и `acp/usage-and-redact-commands` (команды `/usage` и `/redact` — после MVP, §13.4). Фикстуры, которые ожидают `_meta.codelab.outcome`,
   объявляют `"extensions": ["outcome"]` (FIX-4, §14.2).
9. **4.9. Интеграционные тесты app против Dart-агента** — контракт e2e ниже. Код
   `apps/codelab_app/lib` не меняется; меняются только тесты: они параметризуются
   помощником и не содержат захардкоженных ожиданий scripted-агента.
10. **4.10. Ручная проверка с Zed:** подключение, промпт, инструменты, одобрение, отмена,
    `session/load`; результат — чек-лист в `design.md` change.

**Контракт e2e app с Dart-агентом (задача 4.9).**

* **Выбор агента** — `--dart-define=CODELAB_E2E_AGENT=scripted|dart` (по умолчанию `scripted`;
  с этапа 7 — ещё `embedded`, §9.12). Для `dart` — ещё `CODELAB_E2E_AGENT_BIN` (путь к собранному
  `codelab-agent` относительно `apps/codelab_app`). `melos run test:e2e:app:dart-agent` (§9.5,
  «Артефакт: скрипты melos») сначала выполняет `build:agent`, затем запускает
  `flutter test integration_test -d macos --exclude-tags scripted-only` с
  `--dart-define=CODELAB_E2E_AGENT=dart --dart-define=CODELAB_E2E_AGENT_BIN=../../build/bin/codelab-agent`.
  Скрипты `test:e2e:app:<имя>` без define работают как сейчас (scripted, все тесты).
* **Помощник** `apps/codelab_app/integration_test/support/e2e_agent.dart` отдаёт значения для
  полей `transport-field-Command` и `transport-field-Args` и ожидания, которые сейчас
  захардкожены в тестах. Сценарий выбирается тем же значением
  `CodelabCompatibleStdioAgentMode`, что и сейчас: для `dart` LLM-сценарий —
  `apps/codelab_app/integration_test/llm_scripts/<mode.wireName>.json` (формат `{"llm": {...}}`,
  §14.7), подобранный так, чтобы видимый результат совпал со scripted-агентом.
* **Тег** `scripted-only` (объявлен в `apps/codelab_app/dart_test.yaml`) — у тестов, которые
  проверяют поведение именно scripted-агента; в режиме `dart` они исключаются.
* **Пути** в аргументах — абсолютные, без пробелов: помощник приводит их через
  `File(...).absolute.path`, как сейчас `fs_flow_test.dart` поступает с `CODELAB_E2E_DART`.

```dart
// apps/codelab_app/integration_test/support/e2e_agent.dart (эскиз API)
enum E2eAgentKind { scripted, dart }

final class E2eAgent {
  static final E2eAgent current = E2eAgent._(
    switch (const String.fromEnvironment('CODELAB_E2E_AGENT', defaultValue: 'scripted')) {
      'scripted' => E2eAgentKind.scripted,
      'dart' => E2eAgentKind.dart,
      final other => throw ArgumentError.value(other, 'CODELAB_E2E_AGENT'),
    },
  );
  E2eAgent._(this.kind);
  final E2eAgentKind kind;
  bool get isScripted => kind == E2eAgentKind.scripted;

  /// scripted: пишет агента из acp_testing в [tempDir]; dart: ничего не пишет.
  Future<E2eLaunch> launch(Directory tempDir,
      {CodelabCompatibleStdioAgentMode mode = CodelabCompatibleStdioAgentMode.normal});
}

final class E2eLaunch {
  final String command;      // scripted: CODELAB_E2E_DART; dart: абсолютный CODELAB_E2E_AGENT_BIN
  final String args;         // scripted: '<agent.dart> serve --stdio'
                             // dart: 'serve --stdio --llm-script <abs>/llm_scripts/<wireName>.json'
                             //       + '--permission-mode …' и '--model …' по таблице ниже
  final Matcher sessionLabel;                         // scripted: equals('Session codelab-test-session'); dart: matches(r'^Session \S+$')
  final List<({String value, String name})> models;   // scripted: gpt-5/GPT-5, gpt-4/GPT-4; dart: scripted/gpt-5 и gpt-5, scripted/gpt-4 и gpt-4
  final String permissionTitle;                       // scripted: 'Run test command'; dart: 'echo hello' (заголовок exec — команда)
  final String rawInputMarker;                        // scripted: '/bin/bash'; dart: 'timeout'
  Finder get sessionLabelFinder;                      // Text, совпавший с sessionLabel
}
```

| Тест (режим scripted-агента) | Что нужно для `dart` |
|---|---|
| `stdio_connect_flow_test.dart` | «missing stdio command» — агента нет, без изменений; «connects» — только `launch()`; «creates a session…» (`normal`) — `sessionLabel` вместо `codelab-test-session`, сценарий: ответ `hello from compatible stdio agent`; «selects a config option» (`withConfigOptions`) — `--model gpt-5 --model gpt-4` (модели провайдера `scripted`), тест ищет опцию по `id: "model"` (а не `.single`: у Dart-агента есть ещё `mode`) и сверяет `models`; сценарий без шагов; «agent dying mid-turn» (`crashMidPrompt`) — `scripted-only` |
| `permission_flow_test.dart` (`withPermissionRequest`) | сценарий: `exec` с `{"command": "echo hello", "timeout": 30}`, затем ответ `approved: allow_once`; режим `standard` (вопрос на `exec`); заголовок и маркер сырых аргументов — `permissionTitle`, `rawInputMarker`; четыре варианта ответа и `Shell` — как есть |
| `fs_flow_test.dart` | «reads and writes» (`withFsAccess`) — `--permission-mode accept-edits` (запись без вопроса); сценарий: `read input.txt`, `write output.txt` с `echo: hello from disk`, ответ `fs roundtrip complete: hello from disk`; «escapes the working directory» (`withFsPathEscape`) — `scripted-only`: Dart-агент отклоняет путь в `BoundedEnv` и не шлёт `fs/read_text_file` |
| `terminal_flow_test.dart` | «runs a real command» (`withTerminalExecution`) — `--permission-mode bypass`; сценарий: `exec` `printf hello-from-terminal; exit 3`, `expect` — `toolResult.isError: true`, ответ `terminal output: hello-from-terminal` и `exitCode: 3`; «cwd outside» (`withTerminalPathEscape`) — `scripted-only` (как для fs); «terminal/kill without releasing» (`withTerminalKill`) — `scripted-only`: Dart-агент всегда вызывает `terminal/release` (ENV-7) |
| `plan_progress_checklist_flow_test.dart` (`withPlan`) | сценарий из трёх пар шагов «`update_plan` → текст» на промпты `start working on the plan`, `keep going`, `finish the plan`; записи плана (тексты, приоритеты, статусы) — те же, что у scripted-агента |
| `prompt_queue_flow_test.dart` (`withQueuedPromptDrain`) | режим `standard`; сценарий: `exec` (вопрос), ответ `approved: allow_once`, затем ответ на очередной промпт `queued message delivered`; очередь — клиентская |
| `multi_session_concurrency_flow_test.dart` (`withConcurrentSessions`) | режим `standard`; шаги в порядке запросов: сессия A — `exec` (вопрос остаётся открытым), сессия B — ответ `hello from ${sessionId}`, затем A — `approved: allow_once`; шаги сценария общие для соединения |
| `open_project_flow_test.dart` | «sends cwd» (`echoesCwd`) — ответ `cwd was: ${cwd}`; «recent projects persist» — агента нет, без изменений |

**OpenSpec change.** `add-dart-agent-acp-server` (задачи 4.1–4.4, 4.7–4.8; scope: методы ACP
агентской стороны, модели `session/set_mode` в `acp_protocol` (agent-core-architecture §16.2),
проекция событий, расширения `_meta.codelab.outcome`, `_meta.codelab.budgetExceeded` и
`data.codelab` — их агент шлёт всегда, а фикстуры, которые их ожидают, объявляют `"extensions"`
(FIX-4, §14.2), `ListingOverlayEnv`, агентский драйвер корпуса и поле `roles`). Вопросы, решённые в
§16.2 (маппинг `TurnEnded(failed)`, повторная доставка `session/request_permission`, `ls`/`search`
поверх клиента, `session/set_mode`, команда в `terminal/create`), не переоткрываются: `design.md`
ссылается на решения. `add-codelab-agent-binary` (задачи 4.5–4.6, 4.9; scope: CLI агента,
минимальный конфиг из флагов и `--llm-script`, серверные транспорты, токен WebSocket, контракт
e2e app). `tasks.md` — пары «тест → реализация» со ссылкой на критерий (§9.0, правило 3).

**Что прочитать.** Документ ядра §13, §10 (профиль `agent-serve`), §7 (`AcpPermissionGate`),
§14; `docs/acp/protocol/05-Prompt Turn.md`, `08-Tool Calls.md`, `09-File System.md`,
`10-Terminal.md`, `12-Session Model.md`; `docs/architecture/acp-boundary.md`.

**Definition of Done.**

* `melos run conformance:agent` и транспортный драйвер `apps/codelab_agent/test/transport_conformance_test.dart` — 46 фикстур этапов 0 и 4 с ролью `agent` зелёные (44 в памяти, 2 транспортные против процесса бинаря); кадры `fs/*`
  и `terminal/*` сверяются, `MemoryExecutionEnv` в прогоне не участвует.
* `client_application_contract_test.dart: prompt response is sent after the last session/update of the turn` (ACP-3) и `...: session/cancel yields stopReason cancelled` (ACP-5).
* `every_agent_event_is_projected_test.dart` (ACP-6); `bad_frames_test.dart` (ACP-4).
* `melos run build:agent` даёт `build/bin/codelab-agent`, и он отвечает на `initialize`:
  `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}' | build/bin/codelab-agent serve --stdio --llm-script apps/codelab_agent/test/llm_scripts/hello.json`.
* Интеграционные тесты app по таблице контракта написаны и собираются; код
  `apps/codelab_app/lib` в изменениях этапа не тронут. Прогон на устройстве —
  `melos run test:e2e:app:dart-agent` (все тесты без тега `scripted-only` зелёные),
  `melos run test:e2e:app:stdio` и остальные scripted-прогоны — выполняется в ветке
  `release/<version>` (`AGENTS.md` §21).
* `serve_flags_test.dart` (задача 4.6): ключ из `CODELAB_API_KEY` не попадает в лог, `--provider`
  вместе с `--llm-script` — ошибка использования.
* Чек-лист Zed заполнен.

**Зависимости.** Этап 3. Исключение — срез P0 ([дорожная карта](../delivery-roadmap.md)): урезанный
этап 4 (`initialize`, `session/new`, `session/prompt`, `session/cancel`, задачи 4.2, 4.3, 4.5 только
stdio и 4.6 `serve --stdio`) идёт сразу после этапа 2, без этапа 3; после P0 этапы 1–4 доводятся до
полного объёма в обычном порядке. Этап 4 несёт больше трети Must-строк матрицы, поэтому принимается по
группам фикстур: `acp/session-*`, `acp/prompt-*`, `acp/tool-*`, `acp/permission-*`, `acp/fs-*`,
`acp/terminal-*` — каждая группа отдельным PR.

**Риски.** Неверное прочтение спецификации закрепляется фикстурами — ссылка на раздел в каждой
фикстуре, ручная проверка с Zed и Claude Code ACP. Гонки отмены и разрешения — порядок из §7б
(Python, этап 2) берётся, если фикстура не определяет поведение.

---

← [9.8. Этап 3 — Сессии и сжатие](09-08-stage-3-sessions.md) · [Оглавление](../dart-agent-and-clients.md) · [9.10. Этап 5 — Общий клиентский слой](09-10-stage-5-client-kit.md) →
