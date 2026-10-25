Задачи идут парами «тест → реализация» (§9.0, правило 3). В скобках — задача этапа 4 (`dart-agent-and-clients/09-09-stage-4-acp-adapter.md`) и требование спецификации.

Пути — в `apps/codelab_agent/`, если не указано иное. Группы задач по итерациям (design.md, D12):
- группы 1–4 — итерация 1 (транспорты и stdio-бинарь);
- группы 5–6 — итерация 2 (WebSocket и транспортные фикстуры);
- группы 7–8 — итерация 3 (e2e app и Zed).

Каждая итерация — отдельный PR в `develop`.

## 1. Серверные транспорты (4.5)

- [x] 1.1 Тест (agent-transports «Серверные транспорты ACP»): `packages/dart/acp_transports/test/stdio_server_transport_test.dart` — на потоках в памяти: строка 2 МиБ целиком, пустые строки пропущены, 1 000 сообщений в порядке отправки целыми строками, EOF → `inbound` закрыт и состояние `closed`, неразбираемый JSON → `-32700` с `id: null`, кадр без `jsonrpc` → `-32600` с `id` кадра, после плохого кадра корректный запрос доходит, событие `diagnostic` `warning` на каждый плохой кадр (красный)
- [x] 1.2 Тест: `packages/dart/acp_transports/test/websocket_server_transport_test.dart` — `HttpServer` на loopback и порту `0`, клиент `WebSocketAcpTransport`: текстовый кадр = сообщение в обе стороны, бинарный кадр → `-32600`, неразбираемый JSON → `-32700`, закрытие сокета клиентом → `inbound` закрыт (красный)
- [x] 1.3 Реализовать `lib/src/io/stdio_server_acp_transport.dart` и `lib/src/io/websocket_server_acp_transport.dart` в `acp_transports`, экспорт из `io.dart`; уточнить документацию `AcpTransport.inbound` и `send` (design.md, D2); тест web-безопасного бареля — серверные транспорты в нём не экспортируются — 1.1, 1.2 зелёные

## 2. Приложение и сторож (4.6)

- [x] 2.1 Записать `package:args` в `docs/architecture/technology-stack.md` (таблица §1 и раздел §20б по §27: назначение, где используется — `apps/codelab_agent`, на этапе 6 `apps/codelab_cli`; где нет — пакеты `packages/*`; ADR не нужен). Создать `apps/codelab_agent` (`pubspec.yaml` с зависимостями D1, вложенный `AGENTS.md`; анализ — по корневому `analysis_options.yaml`; `bin/codelab_agent.dart`, барель `lib/codelab_agent.dart`), добавить в `workspace:` корневого `pubspec.yaml`
- [x] 2.2 Тест (workspace-architecture «Автоматический сторож границ пакетов»): правило `apps/codelab_agent` в `codelab_architecture_tests/test/support/rules.dart` (`lib/`; HOST-6 — `lib/` и `bin/`, `host_assembly_guard_test.dart`), allowlist в `pubspec_allowlist_test.dart`, негативные тесты сторожа: `import 'package:flutter/…'` и текст `AgentRuntime(` во временном файле приложения → нарушение (HOST-6) (красный)
- [x] 2.3 Реализовать проверку HOST-6 и правило в стороже — 2.2 зелёный

## 3. Флаги, сборка хоста и логи (4.6)

- [x] 3.1 Тест (agent-binary «Минимальный конфиг из флагов», «Сценарий --llm-script»): `test/serve_flags_test.dart` — `parseServeArgs(args, env)`: флаг сильнее переменной; повторяемый `--model` (первое — по умолчанию); `CODELAB_MODEL` без `--model`; `cli/<id>` с `--provider` и `scripted/<id>` с `--llm-script`; `--model openai/gpt-5` без `--provider` → `UsageError`; `--provider` вместе с `--llm-script`, неизвестный флаг, неизвестный режим, оба транспорта, нет транспорта, ни модели ни сценария → `UsageError`; неизвестная `CODELAB_*` → предупреждение; `ServeOptions.toString` и текст ошибок не содержат значения `CODELAB_API_KEY`; справка не упоминает `--llm-script` (красный)
- [x] 3.2 Реализовать `lib/src/cli/serve_args.dart` (`ArgParser` из `package:args` и правила §15.6 поверх него; `ArgParserException` → `UsageError`) и справку `serveUsage()` в том же файле (design.md, D1, D4) — 3.1 зелёный
- [x] 3.3 Тест (agent-binary «Сценарий --llm-script»): `test/agent_host_test.dart` — сценарий из файла: модели `scripted/<id>` по `--model`, без `--model` — из `llm.model`; `${cwd}` — рабочая папка сессии запроса для двух сессий с разными `cwd`, `${sessionId}` — её id; невалидный файл → `UsageError` с путём поля; `sessionPersistence` сужена, `CODELAB_HOME` не создан; провайдер из флагов → `JsonlSessionStore` под `$CODELAB_HOME/sessions` и `loadSession: true`; WebSocket → `fileListing` выключен с причиной (красный)
- [x] 3.4 Добавить в `ScriptedStreamFunction` (`codelab_agent_core/lib/src/testing/`) параметр `cwdOf(sessionId)` с тестом в `codelab_agent_core/test/testing/scripted_stream_function_test.dart`; реализовать `lib/src/host/agent_host.dart` и `lib/src/host/llm_script.dart` только через `buildAgentCore` (design.md, D3) — 3.3 зелёный
- [x] 3.5 Тест (agent-binary «Логи бинаря»): `test/log_sinks_test.dart` — stderr-sink: одна строка на запись; файл: JSON Lines с `ts`, `level`, `event` первыми, каталог `0700`, файл `0600`, дописывание; `--log-file` в `-`, `/dev/stdout`, `/dev/fd/1`, `/proc/self/fd/1` и неоткрываемый путь → `UsageError` с текстом §12.3.1; уровень по умолчанию `info` (красный)
- [x] 3.6 Реализовать `lib/src/log/host_logger.dart`, `stderr_sink.dart` и `file_sink.dart` (design.md, D5) — 3.5 зелёный

## 4. serve --stdio и жизненный цикл (4.6)

- [x] 4.1 Создать `test/llm_scripts/hello.json` (один шаг: ответ `hello`, `stopReason: stop`)
- [x] 4.2 Тест (agent-binary «Команда serve», «Жизненный цикл процесса», «Минимальный конфиг из флагов»): `test/stdio_process_test.dart` — процесс бинаря на Dart VM (`bin/codelab_agent.dart`, один раз скомпилированный в kernel, `test/support/agent_process.dart`) `serve --stdio --llm-script test/llm_scripts/hello.json`: строка `initialize` → одна строка ответа с `protocolVersion: 1`; `session/new` и `session/prompt` → `agent_message_chunk` `hello` и `end_turn`; в stdout только строки JSON-RPC, лог только в stderr; EOF stdin во время хода → код `0`; `SIGINT` → `130`, `SIGTERM` → `143`; `--log-file /dev/stdout` → `64`; с `CODELAB_API_KEY=sk-test-secret` и `--log-level debug --log-file <tmp>` ни stderr, ни файл не содержат ключа (красный)
- [x] 4.3 Реализовать `lib/src/serve/serve_stdio.dart`, `signals.dart`, `exit_codes.dart` и `runCodelabAgent` (сигналы, коды выхода `0`, `1`, `64`, `130`, `143`, design.md, D7) — 4.2 зелёный
- [x] 4.3a Тест (agent-acp-server «Отсоединение, переподключение и завершение»): `packages/dart/codelab_agent_acp/test/robustness/half_closed_input_test.dart` — запрос, прочитанный до конца входа, получает ответ, транспорт закрывается, `serve` завершается (красный); реализовать в `AcpAgentServer.serve` и идемпотентном закрытии соединения — зелёный (design.md, D7)
- [x] 4.4 Проверка итерации 1: `fvm dart run melos run check` зелёный (новое приложение в `guard` и `test`); документы ядра §12.3.1 (файл лога по умолчанию до этапа 8) и §13.10 (ответы после конца входа) правятся там, где реализация уточнила контракт; PR итерации 1

## 5. serve --ws и аутентификация (4.5, 4.6)

- [ ] 5.1 Тест (agent-binary «Аутентификация WebSocket»): `test/ws_auth_test.dart` — процесс `serve --ws --port 0 --llm-script …` с `CODELAB_AGENT_TOKEN`: фактический порт из записи `serve.ws.listening` в stderr; без upgrade → `426`; без `Authorization` → `401` с `WWW-Authenticate: Bearer`; неверный токен → `401`, запись `serve.ws.unauthorized` без токенов; верный токен на пути `/acp` и на `/` → `initialize` отвечает; пустая переменная токена → код `64`; не-loopback `--host` → предупреждение; два подключения — две независимые сессии; `SIGTERM` → `143` (красный)
- [ ] 5.2 Реализовать `lib/src/serve/serve_ws.dart` (сравнение токена за постоянное время, design.md, D6) — 5.1 зелёный

## 6. Транспортные фикстуры (4.8)

- [ ] 6.1 Тест (acp-golden-fixtures «Формат golden-фикстуры ACP»): в `packages/dart/acp_testing/test/` — загрузка `setup.transport` (`stdio`; `ws` с `attempts`), неизвестный `kind` → громкий провал; `$repeat` материализуется в `c2a` и сравнивается точной строкой в `a2c`; согласованность `_schema.json` и загрузчика (красный)
- [ ] 6.2 Реализовать `setup.transport` и `$repeat` в `fixture.dart`, матчере и `_schema.json` (точечная правка схемы) — 6.1 зелёный
- [ ] 6.3 Тест (acp-golden-fixtures «Агентский драйвер фикстур»): агентский драйвер пропускает фикстуру с `setup.transport` с причиной «transport driver» (красный)
- [ ] 6.4 Реализовать пропуск в `agent_conformance.dart` — 6.3 зелёный
- [ ] 6.5 Фикстуры `acp/stdio-framing-large-line` (промпт 2 МиБ через `$repeat`, ответ той же длины одной строкой) и `acp/ws-auth-bearer-required` (`attempts` `none` → `401`, `wrong` → `401`, затем `initialize`), роль `agent`, теги `stdio` и `ws`, ссылки `spec` на `docs/acp/protocol/16-Transports.md`; `fixtures_load_test.dart` знает корпус этапа 4 полностью (35)
- [ ] 6.6 Тест (acp-golden-fixtures «Транспортный драйвер фикстур»): `test/transport_conformance_test.dart` — стартер `runAgentFixture` поверх процесса бинаря и настоящего stdio или WebSocket, проверка `attempts`, обе транспортные фикстуры зелёные (красный до реализации стартера)
- [ ] 6.7 Реализовать транспортный стартер в `test/support/` приложения — 6.6 зелёный
- [ ] 6.8 Документы: `09-09-stage-4-acp-adapter.md` (DoD — 46 фикстур с ролью `agent`), `agent-core/14-golden-fixtures.md` §14.2 (итого к этапу 4 — 47 = 12 + 35) и описание `setup.transport` и `$repeat` (§14.3–§14.4) (design.md, D8)
- [ ] 6.9 Проверка итерации 2: `fvm dart run melos run check` зелёный, `conformance:agent` — 44 фикстуры в памяти и 2 пропущены с причиной; PR итерации 2

## 7. E2E app против Dart-агента (4.9)

- [ ] 7.1 Тест: `test/llm_scripts_load_test.dart` приложения — каждый файл `apps/codelab_app/integration_test/llm_scripts/*.json` загружается как сценарий `--llm-script` без ошибок (красный, пока сценариев нет)
- [ ] 7.2 Сценарии `apps/codelab_app/integration_test/llm_scripts/<wireName>.json` по таблице контракта `09-09` (`normal`, `withConfigOptions`, `withPermissionRequest`, `withFsAccess`, `withTerminalExecution`, `withPlan`, `withQueuedPromptDrain`, `withConcurrentSessions`, `echoesCwd`) — 7.1 зелёный
- [ ] 7.3 Помощник `apps/codelab_app/integration_test/support/e2e_agent.dart` (`E2eAgent`, `E2eLaunch`, design.md, D9); тег `scripted-only` в `apps/codelab_app/dart_test.yaml`
- [ ] 7.4 Параметризовать 8 тестов `apps/codelab_app/integration_test/` помощником по таблице контракта: `sessionLabel`, `models`, `permissionTitle`, `rawInputMarker`, поиск опции по `id: "model"`; тег `scripted-only` у `crashMidPrompt`, `withFsPathEscape`, `withTerminalPathEscape`, `withTerminalKill`; в `permission_flow_test.dart` для `dart` — проверка команды `echo hello` в карточке (D-02) (testing-quality «Интеграционные тесты stdio»)
- [ ] 7.5 Melos-скрипты `build:agent` и `test:e2e:app:dart-agent` в корневом `pubspec.yaml`; `apps/codelab_app/lib` в изменениях не тронут (testing-quality «Проверки workspace»)
- [ ] 7.6 Проверка: `fvm dart analyze` корня зелёный (интеграционные тесты собираются); `fvm dart run melos run build:agent` даёт `build/bin/codelab-agent`, и он отвечает на `initialize` командой DoD `09-09`

## 8. Zed и Definition of Done (4.10)

- [ ] 8.1 Ручная проверка с Zed — выполняет пользователь: чек-лист D13 в `design.md` заполнен
- [ ] 8.2 Definition of Done change: `fvm dart run melos run check` зелёный; `serve_flags_test.dart`, `stdio_process_test.dart`, `ws_auth_test.dart`, `transport_conformance_test.dart` зелёные; строки матрицы R-12, R-13 имеют доказательства (таблица в `design.md`), D-01 и D-02 — тестами app, прогон которых — в `release/<version>`; PR итерации 3
- [ ] 8.3 Перед архивированием: `openspec validate add-codelab-agent-binary --strict`; заполнить Purpose новой спецификации `agent-binary`
