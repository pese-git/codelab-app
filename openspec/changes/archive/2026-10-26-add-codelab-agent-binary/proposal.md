## Why

Change `add-dart-agent-acp-server` дал `AcpAgentServer`, но запустить его может только тест: процесса, который клиент стартует по stdio или к которому подключается по WebSocket, нет. Поэтому codelab-app, Zed и будущий `codelab` CLI не могут работать с Dart-агентом, а цели R-12, R-13, D-01 и D-02 матрицы (`agent-parity-goals.md`) не имеют доказательств.

Этот change закрывает этап 4 (`docs/architecture/proposals/dart-agent-and-clients/09-09-stage-4-acp-adapter.md`): задачи 4.5 (серверные транспорты), 4.6 (бинарь `codelab-agent` с минимальным конфигом из флагов), 4.9 (e2e-тесты app против Dart-агента) и 4.10 (ручная проверка с Zed), а также две транспортные фикстуры корпуса этапа 4. Источник решений — принятый документ ядра `agent-core-architecture.md`: §13.1, §13.3, §13.10 (адаптер и транспорт), §12.3 (логи), §15.6 (флаги и переменные), §14 (фикстуры), §10.4 (профиль `agent-serve`).

## What Changes

- **Серверные транспорты (4.5)** в `package:acp_transports/io.dart`: `StdioServerAcpTransport` (stdin/stdout процесса, одна строка — одно сообщение, строки любой длины) и `WebSocketServerAcpTransport` (обёртка над принятым `WebSocket` из `dart:io`). Транспорт сам отвечает `-32700` на неразбираемый JSON и `-32600` на кадр не JSON-RPC 2.0 и не закрывает соединение (D12 change `add-dart-agent-acp-server`). Документация `AcpTransport.inbound` — «сообщения от другой стороны соединения».
- **Бинарь `apps/codelab_agent` (4.6)**: `codelab-agent serve --stdio` и `codelab-agent serve --ws --host 127.0.0.1 --port 8765 --token-env CODELAB_AGENT_TOKEN`, профиль `agent-serve`. По stdio сервер получает локальный листинг (`ls`, `search`). WebSocket слушает loopback по умолчанию и проверяет Bearer-токен при upgrade: без токена или с неверным — `401` до обмена ACP (R-12).
- **Минимальный конфиг из флагов** (до этапа 8 файлы конфига не читаются, §15.6): `--provider`, `--base-url`, `--model` (повторяемый), ключ из `CODELAB_API_KEY`, `--permission-mode`, `--log-level`, `--log-file` и их переменные `CODELAB_*`. Ошибка использования — код выхода `64`.
- **`--llm-script <file.json>`** — только для тестов, в справке скрыт: вместо провайдера `ScriptedStreamFunction` из файла формата блока `llm` фикстуры (§14.7), сессии в памяти, в `$CODELAB_HOME` ничего не пишется.
- **Логи** — только в stderr и, если задан `--log-file` или `CODELAB_LOG_FILE`, в файл JSON Lines (§12.3.1). stdout занят протоколом. Значение ключа провайдера не попадает ни в лог, ни в аргументы.
- **Жизненный цикл**: EOF stdin, `SIGINT` и `SIGTERM` — безопасное завершение `AcpAgentServer.shutdown` с кодами выхода `0`, `130`, `143`.
- **Транспортные фикстуры** `acp/stdio-framing-large-line` и `acp/ws-auth-bearer-required`: формат фикстур получает блок `setup.transport` и генератор значения `$repeat`; их играет транспортный драйвер против процесса бинаря, а агентский драйвер в памяти их пропускает. Корпус этапа 4 становится полным — 35 фикстур.
- **E2E app против Dart-агента (4.9)**: помощник `integration_test/support/e2e_agent.dart`, LLM-сценарии `integration_test/llm_scripts/*.json`, тег `scripted-only`, скрипты `build:agent` и `test:e2e:app:dart-agent`. Код `apps/codelab_app/lib` не меняется. Прогон на устройстве — только в ветке `release/<version>` (`AGENTS.md` §21); в этом change тесты написаны и проходят анализ.
- **Ручная проверка с Zed (4.10)**: чек-лист в `design.md`.
- **Сторож и workspace**: `apps/codelab_agent` в `workspace:`, правило сторожа (без Flutter и клиентских пакетов, без сборки ядра в обход `buildAgentCore` — HOST-6), allowlist зависимостей.

Не входит:
- YAML-конфиг, `$CODELAB_HOME/config.yaml`, файл лога по умолчанию из конфига, редакция секретов (§12.4) — этап 8;
- MCP-серверы из `session/new` — этап 8 (D16 change `add-dart-agent-acp-server`);
- флаг `--local-exec` (`exec.local_fallback`) — этап 8 вместе с конфигом: без `clientCapabilities.terminal` `exec` выключен;
- встроенный агент codelab-app (`InProcessAcpLink` в `acp_transports`, `codelab_embedded`) — этап 7;
- смена встроенного профиля подключения codelab-app на Dart-агента — после этапа 9 (вывод Python-агента);
- protocol trace `--trace-file` (§12.5) — этап 8 вместе с редакцией.

## Capabilities

### New Capabilities
- `agent-binary`: бинарь `codelab-agent` — команда `serve` со stdio и WebSocket, аутентификация WebSocket, минимальный конфиг из флагов и переменных окружения, `--llm-script`, логи в stderr и файл, жизненный цикл процесса и коды выхода.

### Modified Capabilities
- `agent-transports`: новое требование «Серверные транспорты ACP» — `StdioServerAcpTransport` и `WebSocketServerAcpTransport`, ответы транспорта на сырые плохие кадры; «Общий порт transport» — `inbound` несёт сообщения другой стороны соединения, а не только агента.
- `acp-golden-fixtures`: «Формат golden-фикстуры ACP» — блок `setup.transport` и генератор `$repeat`; новое требование «Транспортный драйвер фикстур»; «Агентский драйвер фикстур» — фикстуры с `setup.transport` в прогоне в памяти не участвуют.
- `workspace-architecture`: «Границы пакетов monorepo» — приложение `apps/codelab_agent`; «Автоматический сторож границ пакетов» — правило и allowlist `apps/codelab_agent`.
- `agent-acp-server`: «Отсоединение, переподключение и завершение» — после конца входа соединение отвечает на прочитанные запросы и закрывает транспорт, затем `serve` завершается (найдено бинарём по stdio, design.md, D7).
- `testing-quality`: «Проверки workspace» — скрипт `build:agent`; «Интеграционные тесты stdio» — e2e-тесты app параметризуются агентом (`scripted` или `dart`), тег `scripted-only`.

## Impact

- **Новое приложение** `apps/codelab_agent` (чистый Dart): `bin/codelab_agent.dart`, `lib/src/` — разбор флагов, сборка ядра, `serve`, логи. Зависимости — `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `acp_protocol`, `acp_transports`, `args`, `async`, `http`. `package:args` (разбор флагов) — новая технология стека: запись в `docs/architecture/technology-stack.md` (§20б) в этом change, design.md, D1.
- **`acp_transports`**: два серверных транспорта в `lib/src/io/`, экспорт из `io.dart`; уточнение документации порта.
- **`acp_testing`**: поле `setup.transport` и `$repeat` в загрузчике и `_schema.json`, транспортный драйвер, две фикстуры; агентский драйвер пропускает транспортные фикстуры.
- **`apps/codelab_app`**: только `integration_test/`, `dart_test.yaml` (тег `scripted-only`); `lib/` не меняется.
- **Корень**: `workspace:`, скрипты `build:agent` и `test:e2e:app:dart-agent`; тесты `apps/codelab_agent` входят в `test` (Dart VM, реальные процессы и сокеты — `AGENTS.md` §21).
- **Документы**: `09-09-stage-4-acp-adapter.md` (счёт фикстур в DoD), `agent-core/14-golden-fixtures.md` (§14.2 — итог корпуса этапа 4, формат `setup.transport`), `agent-core/13-acp-adapter.md`, `agent-core/12-observability-and-errors.md` там, где реализация уточнит контракт.
- **ACP-контракт** не меняется: новые методы и поля протокола не вводятся.
