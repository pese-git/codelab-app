## Why

Этап 7 плана Dart-агента — встроенный режим: агент работает внутри процесса codelab-app и `codelab` (CLI) через тот же ACP-код, что и внешний агент (ADR-0001, `agent-core-architecture` §10, §13.11, `dart-agent-and-clients` §9.12). Пара транспортов в памяти `InProcessAcpLink` уже есть (задачи 7.1–7.2, change `add-in-process-acp-transport`). Конфигурация (8.5, `add-agent-configuration`) и хранилище секретов (8.9, `add-agent-secret-store`, D15) тоже готовы. Нет хоста, который соберёт ядро в процессе клиента, и профиля подключения, который его выберет.

Сейчас:
- `codelab -a embedded` даёт код `64` и `Embedded agent is not available in this build.`; без `--agent` нужен профиль `default` из `profiles.json`;
- в codelab-app агента можно только запустить процессом (stdio) или подключить по WebSocket;
- `test-scenario --agent embedded` даёт код `64`;
- `AcpAgentServer` всегда исполняет файлы и команды через `fs/*` и `terminal/*` клиента. Профили `embedded-*` по §10.4 исполняют их локально, а профиля `embedded-app-desktop` в ядре нет.

Этот change — задачи 7.3–7.9 плана.

## What Changes

- **Пакет `packages/dart/codelab_embedded`** (7.3) — мост между сторонами без префикса стороны (ADR-0002), как `codelab_setup`. Пакет — второй хост ядра рядом с `apps/codelab_agent` (`agent-core-architecture` §10.1). Три точки входа:
  - основной барель — web-безопасный: `createEmbeddedAgent`, `EmbeddedAgent`, `EmbeddedAgentConfig`, `EmbeddedHostServices`, `EmbeddedAgentOpener`, `EmbeddedAgentConfigException`, реэкспорт `Logger` и `LogLevel`;
  - `io.dart` — настольные хосты: `openLocalEmbeddedAgent`. Он вызывает загрузчик конфигурации 8.5, затем `openHostSecrets` 8.9, `JsonlSessionStore`, `LocalExecutionEnv`, MCP stdio и HTTP, файлы проекта;
  - `testing.dart` — сценарий модели для тестов и `test-scenario`.

  Ядро собирается только через `buildAgentCore` (HOST-6), сервер — `AcpAgentServer` на агентском конце `InProcessAcpLink`. Сторож, allowlist и вложенный `AGENTS.md` появляются вместе с пакетом (design.md, D1–D3).
- **Профиль хоста `embedded-app-desktop`** (7.4) в `HostProfile.of` по таблице §10.4: capability и причины те же, что у `embedded-cli`. Встроенные профили исполняют файлы и команды локально через `LocalExecutionEnv` с containment `BoundedEnv` по `cwd` сессии, даже если клиент объявил `fs`/`terminal` (D4).
- **`AcpServerConfig.localEnv`** в `codelab_agent_acp`. Если хост задал локальный env, сессии соединения работают на нём, а `fs/*` и `terminal/*` клиенту не отправляются. Методов, полей и состояний ACP не добавляется: использовать возможности клиента агент не обязан (D4).
- **Жизненный цикл встроенного агента** (D6):
  - один агент на соединение;
  - закрытие клиентского конца запускает `dispose`: ожидающие разрешения → отказ, ход отменён, журнал дописан, HTTP и MCP закрыты;
  - необработанная ошибка агента переводит клиентский транспорт в `failed` с `disconnected`, kit показывает обрыв;
  - повторный `open` сначала дожидается `dispose` прежнего агента.
- **Конфигурация и ключи** (D5): конфиг — загрузчик 8.5 с `cwd` = папка проекта, ключ — `SecretResolver` из `openHostSecrets` (D15 change `add-agent-secret-store`). Невалидный конфиг даёт типизированную ошибку с проблемами, без значений. Тестовое хранилище `CODELAB_TEST_SECRET_STORE` читается только в сборке с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`.
- **Клиентский слой** (`codelab_client_core`, `codelab_client_io`): `ConnectionProfile.embedded` (`EmbeddedProfile` с `hostProfile`). `ConfigTransportResolver` его не поддерживает, `JsonFileProfileStore` его не сохраняет (D7).
- **CLI** (7.6):
  - `EmbeddedTransportResolver` в composition root;
  - `-a embedded` работает; без `--agent` используется встроенный агент, а профиль `default` из `profiles.json`, если он задан, остаётся сильнее (решение пользователя 2026-11-02, design.md, D13);
  - флаг `--debug-secrets` (D15 change `add-agent-secret-store`);
  - невалидный конфиг — код `64` с проблемами в stderr;
  - `test-scenario --agent embedded` играет корпус на встроенном агенте с профилем фикстуры (D8).
- **codelab-app** (7.5): тип подключения «Embedded agent» в диалоге подключения и `EmbeddedTransportResolver` в `app/app_scope.dart`. Логи агента идут в логгер приложения. Тип подключения по умолчанию остаётся stdio (D9).
- **Тесты** (7.7, 7.9):
  - e2e CLI `cli/*` с `CODELAB_E2E_AGENT=embedded` на Dart VM входят в `melos run check`, как и `test-scenario --agent embedded` на корпусе;
  - интеграционные тесты app с `CODELAB_E2E_AGENT=embedded` пишутся и анализируются в feature-ветке, а прогон на устройстве `melos run test:e2e:app:embedded` — только в `release/<version>` (`AGENTS.md` §21; D10, D13);
  - основной барель `codelab_embedded` компилируется в `web-compile`.
- **Замер 7.8** — разведка (исключение (д) §9.0, правило 3): `codelab_embedded/benchmark/stream_latency_benchmark.dart` на 10 000 чанках. Решение «ядро в isolate или нет» записывается в design.md с числами по критериям плана: p99 задержки цикла событий > 8 мс или максимум > 50 мс. Разбор журнала JSONL при `session/load` уходит в `Isolate.run` в любом случае (D11).

## Не входит

- `codelab_setup` для мастера, страница провайдеров app (D-05), статус ключа, `ConfigWriter` 8.10 — change `add-provider-setup-ui` (Should). Без них встроенный профиль настраивается файлом `config.yaml` и `codelab secret set`;
- сброс кэша `SecretResolver.invalidate` при смене ключа — вместе с 8.10. До него заменённый ключ виден после перезапуска (известное ограничение D3, D15 change `add-agent-secret-store`);
- `IsolateAcpLink` — пишется только если замер 7.8 провалит критерии, отдельной итерацией по эскизу плана (D11);
- `memoryHostServices`, `mobileHostServices`, профили `mobile` и `web` — этап 10. Основной барель остаётся web-безопасным, и дорога им не закрыта (D2);
- план сборки в `codelab config check` (7.6) — вне scope, отдельный change (решение пользователя 2026-11-02, design.md, D13, п. 5); этот change его не создаёт;
- флаги CLI `--permission-mode`, `--config`, `--log-file` для встроенного агента — вне scope, отдельный change (решение пользователя 2026-11-02, design.md, D13, п. 6). До него работают `CODELAB_CONFIG`, `permissions.mode` конфига и `--approve`;
- `TerminatingTransportResolver` и `/restart` — после MVP (§12.6.7);
- переключатель отладки секретов в UI app — §12.4. Сейчас работает `CODELAB_DEBUG_SECRETS=1`;
- изменения ACP: методов, полей, `_meta` и состояний не добавляется. `agentInfo` встроенного агента тот же, что у бинаря (D4).

## Capabilities

### New Capabilities

- `embedded-agent` — встроенный агент в процессе клиента:
  - пакет `codelab_embedded`, его точки входа и web-безопасность;
  - сборка через `buildAgentCore` на `InProcessAcpLink`;
  - конфигурация и секреты;
  - локальное исполнение и containment;
  - разрешения;
  - жизненный цикл, `dispose` и отказ;
  - сценарий модели для тестов;
  - замер нагрузки на UI-isolate.

  Ни одна существующая capability не описывает хост в процессе клиента: `agent-binary` — процесс `codelab-agent`, `agent-transports` — только транспорт.

### Modified Capabilities

- `agent-runtime` — «Профили хостов и сужение»: профиль `embedded-app-desktop`.
- `agent-acp-server` — новое требование «Локальное окружение сессии от хоста» (`AcpServerConfig.localEnv`).
- `acp-client-kit` — «Профили и резолверы транспорта»: `EmbeddedProfile`.
- `codelab-cli`:
  - «Профили подключения CLI»: `embedded` и выбор по умолчанию;
  - новое требование «Встроенный агент в CLI».
- `cli-scenario-driver` — «Команда test-scenario»: профиль `embedded`.
- `agent-workbench-ui` — новое требование «Тип подключения «Встроенный агент»».
- `workspace-architecture`:
  - «Границы пакетов monorepo»: пакет `codelab_embedded`, web-компиляция бареля;
  - «Автоматический сторож границ пакетов»: правила `codelab_embedded`, CLI и desktop.
- `testing-quality` — новое требование «Встроенный режим в e2e и conformance».

## Impact

- **Новый пакет** `packages/dart/codelab_embedded`:
  - `dependencies`: `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp`, `codelab_acp_protocol`, `codelab_acp_transports`, `http`, `meta`, `async` (D3);
  - пакет добавляется в `workspace:` корневого `pubspec.yaml`, получает вложенный `AGENTS.md` и правила в `codelab_architecture_tests` (импорты, allowlist, HOST-6).
- **`codelab_agent_core`** — профиль `embedded-app-desktop`, golden-матрица профиля.
- **`codelab_agent_io`**:
  - разбор сценария модели (`LlmScript` и слой провайдеров сценария) переезжает из `apps/codelab_agent` (D8);
  - `openHostSecrets` получает путь тестового хранилища (D5);
  - разбор журнала JSONL уходит в `Isolate.run` (D11).
- **`codelab_agent_acp`** — `AcpServerConfig.localEnv`.
- **`apps/codelab_agent`** — использует перенесённый `LlmScript`; поведение бинаря не меняется.
- **`codelab_client_core`, `codelab_client_io`** — `EmbeddedProfile`, ветки исчерпывающих `switch`.
- **`apps/codelab_cli`**:
  - зависимость `codelab_embedded` (allowlist CLI расширяется, D3);
  - резолвер, выбор по умолчанию, `--debug-secrets`, драйвер фикстур, e2e.
- **`apps/codelab_desktop`** — зависимость `codelab_embedded`, резолвер, тип подключения в форме, адаптер логгера, интеграционные тесты, скрипт `test:e2e:app:embedded`.
- **Граф** в `README.md`:
  - узел `codelab_embedded` с рёбрами к `codelab_agent_acp`, `codelab_agent_io` и `codelab_agent_mcp`;
  - рёбра `codelab_desktop` → `codelab_embedded` и `codelab_cli` → `codelab_embedded`;
  - фраза «ветки сходятся только на транспортах» уточняется: клиенты видят агентскую сторону только через мосты `codelab_setup` и `codelab_embedded`.
- **CI и melos**:
  - `web-compile` компилирует web-smoke `codelab_embedded`;
  - новые `test:e2e:cli:embedded` и `conformance:embedded` входят в `check`;
  - `test:e2e:app:embedded` — только `release/*`.
- **Документы:**
  - `agent-core/13-acp-adapter.md` §13.1 — `localEnv` (сделано при подготовке change);
  - `09-12-stage-7-embedded.md` — уточнения API (сделано при подготовке change);
  - `09-05-stage-0-foundation.md` — скрипт `test:e2e:app:embedded`;
  - `09-11-stage-6-cli-mvp.md` — `--agent` по умолчанию;
  - `README.md`, корневой `AGENTS.md` §5 и таблица зон в `CLAUDE.md` — новый пакет.
- **Безопасность:**
  - обхода permission flow нет: вопрос идёт тем же `session/request_permission` к kit, API для `PermissionGate` или режима извне нет;
  - секреты — только через `openHostSecrets`; значения не попадают в логи, ошибки и состояние UI;
  - containment — `BoundedEnv` ядра по `cwd` сессии.
