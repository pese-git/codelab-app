## Context

После change `add-dart-agent-acp-server` есть `AcpAgentServer.serve(AcpTransport)` и полный агентский прогон корпуса в памяти (44 фикстуры). Не хватает процесса, который клиент может запустить или к которому может подключиться:

- `acp_transports` содержит только клиентские транспорты: `StdioAcpTransport` запускает дочерний процесс, `WebSocketAcpTransport` подключается к endpoint. Серверной стороны нет. Разбор сырых кадров тоже клиентский: `decodeJsonRpcMessage` бросает `JsonRpcProtocolException`, и клиентский stdio-транспорт переводит соединение в `failed`. Сервер по D12 предыдущего change ждёт от серверного транспорта другого: ответить `-32700` / `-32600` и продолжить.
- `apps/` содержит только `codelab_app`. Хоста, который собирает ядро в профиле `agent-serve` с реальными провайдерами, `LocalExecutionEnv` и `JsonlSessionStore`, нет.
- Корпус этапа 4 неполон: две транспортные фикстуры (`acp/ws-auth-bearer-required`, `acp/stdio-framing-large-line`) не выражаются форматом фикстур, который знает только JSON-RPC кадры.
- E2E-тесты codelab-app (8 файлов в `integration_test/`) жёстко ждут scripted-агента из `acp_testing` (`CodelabCompatibleStdioAgentMode`).

Контракт бинаря описан в принятых документах: `09-09-stage-4-acp-adapter.md` (задачи 4.5, 4.6, 4.9, 4.10 и контракт e2e), документ ядра §12.3 (логи), §13.3 (защита соединения на уровне транспорта), §13.10 (правила протокольного уровня), §15.6 (флаги и переменные этапа 4), §14 (фикстуры). Этот документ фиксирует то, чего там нет: раскладку кода, решения на стыке транспорта и сервера, формат транспортных фикстур, порядок итераций.

## Goals / Non-Goals

**Goals:**
- `codelab-agent serve --stdio` работает с codelab-app и Zed как внешний ACP-агент; `serve --ws` — с аутентификацией Bearer.
- Минимальный конфиг из флагов и переменных достаточен для работы с OpenAI-совместимым и Anthropic-провайдером; `--llm-script` даёт детерминированного агента для тестов клиентов.
- Корпус этапа 4 полон (35 фикстур), агентская сторона — 46 фикстур с ролью `agent`.
- E2E-тесты app параметризованы агентом и собираются в режиме `dart`.

**Non-Goals:**
- YAML-конфиг, `ConfigLoader`, файл лога по умолчанию, редакция секретов, protocol trace — этап 8.
- MCP-серверы, slash-команды, флаг `--local-exec` — этап 8.
- Встроенный агент app и `InProcessAcpLink` в `acp_transports` — этап 7.
- Прогон e2e на устройстве в feature-ветке (`AGENTS.md` §21) и смена встроенного профиля подключения app на Dart-агента.

## Decisions

### D1. Раскладка приложения

```text
apps/codelab_agent/
  bin/codelab_agent.dart          main: exit(await runCodelabAgent(args))
  lib/codelab_agent.dart          барель для bin/ и тестов
  lib/src/run.dart                runCodelabAgent: флаги → лог → хост → транспорт → код выхода
  lib/src/cli/serve_args.dart     ArgParser и правила §15.6 → ServeOptions | UsageError; serveUsage()
  lib/src/host/agent_host.dart    сборка: провайдер или сценарий, каталог моделей, хранилище,
                                  → BuiltAgentCore и AcpServerConfig (только buildAgentCore, HOST-6)
  lib/src/host/llm_script.dart    файл {"llm": {...}} → ScriptedStreamFunction и модели; CwdTrackingStore
  lib/src/log/host_logger.dart    HostLogger и порт LogSink: фильтр уровня, раздача, отключение сбойного sink
  lib/src/log/stderr_sink.dart    основной sink: одна строка на запись
  lib/src/log/file_sink.dart      JSON Lines, права 0600/0700, проверка «не stdout» (§12.3.1)
  lib/src/serve/serve_stdio.dart  StdioServerAcpTransport + localListing + завершение по EOF/сигналу
  lib/src/serve/serve_ws.dart     HttpServer, проверка Bearer, WebSocketServerAcpTransport (итерация 2)
  lib/src/serve/signals.dart      SIGINT/SIGTERM: первый — безопасное завершение, второй — сразу
  lib/src/serve/exit_codes.dart   коды выхода 0, 1, 64, 130, 143
  test/                           serve_flags, agent_host, log_sinks, stdio_process, ws_auth,
                                  transport_conformance; support/agent_process.dart, support/acp_peer.dart;
                                  llm_scripts/hello.json
```

Приложение — чистый Dart (`apps/*` по `AGENTS.md` §5), в `workspace:` корня. Зависимости — `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `acp_protocol`, `acp_transports` (включая `io.dart`), `args`, `http`, `async`, `meta`. `--llm-script` использует `package:codelab_agent_core/testing.dart`: бинарь — тестовый хост для этого флага, а в справке флага нет.

**Флаги разбирает `package:args`** (решение владельца продукта; запись в `technology-stack.md` §20б в этом change). `ArgParser` с командой `serve` даёт синтаксис флагов, повторяемый `--model` (`addMultiOption`), скрытый `--llm-script` (`hide: true`), справку и ошибку неизвестного флага; этот же пакет нужен CLI `codelab` с подкомандами на этапе 6. Правила §15.6 поверх разбора — свои: переменная окружения как значение по умолчанию, флаг сильнее переменной, взаимоисключения (`--stdio`/`--ws`, `--provider`/`--llm-script`), ошибка использования → `UsageError` и код `64` (`ArgParserException` тоже переводится в `UsageError`). Альтернатива — свой разбор — отклонена: дублирует стандартный пакет Dart-команды, который уже есть в `pubspec.lock` транзитивно, и разошёлся бы с будущим CLI.

### D2. Серверные транспорты

В `acp_transports/lib/src/io/`, экспорт из `io.dart`:

- **`StdioServerAcpTransport({Stream<List<int>> input, IOSink output})`** — по умолчанию `stdin`/`stdout` процесса; параметры нужны тестам. Чтение — `utf8.decoder` + `LineSplitter` без ограничения длины строки (R-13: мегабайтные строки читаются целиком). Запись — одно сообщение `encodeJsonRpcMessage` + `\n` и `flush` в цепочке `Future`, чтобы кадры не перемешивались. EOF входа закрывает только `inbound`: отправка работает до `close()`, потому что клиент вида `echo '{…initialize…}' | codelab-agent serve --stdio` закрывает stdin сразу и ждёт ответа. `inbound` — поток с одной подпиской: сообщения до подписки сервера не теряются.
- **`WebSocketServerAcpTransport(WebSocket socket)`** — один текстовый кадр WebSocket = одно сообщение. Бинарный кадр — `-32600` «binary frames are not supported». Закрытие сокета — `inbound` закрывается.

**Сырые плохие кадры** обрабатывает транспорт, потому что сервер получает уже разобранные `JsonRpcMessage` (D12 предыдущего change): неразбираемый JSON → ответ `{"jsonrpc":"2.0","id":null,"error":{"code":-32700,…}}`, JSON не JSON-RPC 2.0 → `-32600` с `id` кадра, если он читается, иначе `null`. Плюс событие `diagnostic` (`warning`) для лога хоста. Соединение живёт (ACP-4). Пустые строки stdio пропускаются без ответа.

Альтернатива — отдавать серверу сырые строки и разбирать в `AcpAgentServer` — отклонена: тогда порт `AcpTransport` различался бы для клиента и сервера, а `InProcessAcpLink` и клиентские транспорты пришлось бы менять.

Документация `AcpTransport.inbound` и `send` уточняется: «сообщения от другой стороны соединения» — порт общий для клиента и агента.

### D3. Сборка хоста

`agent_host.dart` строит одно ядро на процесс:

| | `--llm-script` | провайдер из флагов |
|---|---|---|
| `StreamFunction` | `ScriptedStreamFunction` из файла | `createStreamFunction(ProviderConfig)` провайдера `cli` |
| каталог моделей | `scripted/<id>` для каждого `--model`, иначе модель из `llm.model` файла | `cli/<id>` для каждого `--model` |
| `SessionStore` | `MemorySessionStore`, capability `sessionPersistence` сужена с причиной `--llm-script` | `JsonlSessionStore(root: $CODELAB_HOME/sessions)`, `CODELAB_HOME` по умолчанию `~/.codelab` |
| `$CODELAB_HOME` | не создаётся и не читается | создаётся при первой записи журнала |

Профиль — `agent-serve`. Env хоста — `LocalExecutionEnv` (нужен для `localListing` по stdio); файлы и команды сессий всё равно идут через клиента (`AcpClientExecutionEnv`, §4.7). Для WebSocket capability `fileListing` сужается с причиной «клиент не на этой машине», и `localListing` не передаётся — так `AcpAgentServer` проверяет согласованность (D5 предыдущего change).

**`${cwd}` и `${sessionId}` в сценарии.** Шаги сценария общие для всех сессий процесса (`09-09`, задача 4.6), а `ScriptedStreamFunction` получает `cwd` при создании. Для бинаря сценарий получает функцию `cwdOf(sessionId)`: id сессии запроса — `LlmContext.cacheKey`, а `cwd` запоминает журнал бинаря `CwdTrackingStore` (обёртка `MemorySessionStore`) при создании заголовка сессии. Это только добавление параметра в тестовый `ScriptedStreamFunction`; контракт `StreamFunction` не меняется.

### D4. Флаги и переменные этапа 4

Ровно таблица §15.6 в части «с этапа 4» и общих флагов:

- `--provider openai-compatible|anthropic`, `--base-url <url>`, `--model <id>` (повторяемый), ключ — `CODELAB_API_KEY`. `CODELAB_MODEL` — значение `--model`, если флага нет. Форма `provider/model` из §15.6 допустима только с провайдером этого запуска (`cli/<id>` или `scripted/<id>`): провайдеры по имени появляются с конфигом этапа 8, поэтому `--model openai/gpt-5` без `--provider` — ошибка использования, а не молчаливая подмена;
- `--permission-mode <mode>` / `CODELAB_PERMISSION_MODE` (`plan`, `ask`, `standard`, `accept-edits`, `bypass`, `autopilot`);
- `--log-level <level>` / `CODELAB_LOG_LEVEL`, `--log-file <path>` / `CODELAB_LOG_FILE` (флаг сильнее переменной);
- `--llm-script <file.json>` (скрыт);
- `serve --stdio` или `serve --ws [--host 127.0.0.1] [--port 8765] [--token-env CODELAB_AGENT_TOKEN]`.

Ошибки использования (код `64`, текст в stderr, процесс не стартует сервер): неизвестный флаг, нет `--stdio`/`--ws` или оба сразу, `--provider` вместе с `--llm-script`, нет ни модели, ни сценария, неизвестный режим, `--log-file` в stdout, не открылся файл лога, у `--ws` пустая переменная токена. Неизвестная переменная `CODELAB_*` — предупреждение в лог (§15.6). Значение `CODELAB_API_KEY` не попадает ни в `ServeOptions.toString`, ни в лог; в лог пишется только `api_key_env` и признак «задан».

### D5. Логи

`Logger` хоста раздаёт записи sink'ам: stderr (всегда) и файл (если задан флагом или переменной). Формат файла — JSON Lines по §12.3.1, права `0700`/`0600`, дописывание, проверка «не stdout». stderr — одна строка `<ts> <level> <event> <fields>`; уровень по умолчанию `info`.

**Файл по умолчанию `$CODELAB_HOME/logs/agent.log` на этапе 4 не создаётся.** §15.4 даёт его как значение ключа `logging.file`, но ключ читается из конфига, а конфига до этапа 8 нет. Альтернатива — писать файл по умолчанию сразу — отклонена: без редакции секретов (§12.4, этап 8) постоянный файл на диске пользователя — лишний риск, а `--llm-script` обещает ничего не писать в `$CODELAB_HOME`.

### D6. WebSocket и аутентификация

`HttpServer.bind(host, port)`; по умолчанию `127.0.0.1:8765`. Не-loopback `--host` допустим, но даёт предупреждение `serve.ws.non_loopback`. Токен — значение переменной из `--token-env` (по умолчанию `CODELAB_AGENT_TOKEN`); пустая переменная — ошибка использования: сервер без токена не стартует (R-12).

Каждый HTTP-запрос: не upgrade → `426 Upgrade Required`; нет заголовка `Authorization: Bearer <token>` или токен не совпал (сравнение за постоянное время) → `401` с `WWW-Authenticate: Bearer`, до обмена ACP; иначе `WebSocketTransformer.upgrade` → `WebSocketServerAcpTransport` → `server.serve(transport)`. Путь запроса не проверяется: один процесс — один endpoint, поэтому маршрут клиента и сервера всегда совпадает (DF-07). Клиент codelab-app (`ws://localhost:8765/acp`) и CLI (`ws://127.0.0.1:8765`) подключаются одинаково. Токен в лог не пишется; отказ — запись `serve.ws.unauthorized` с адресом клиента.

### D7. Жизненный цикл и коды выхода

- **stdio:** EOF stdin → соединение отвечает на уже прочитанные запросы и закрывает транспорт, `AcpAgentServer.serve` завершается → `AgentHost.shutdown(grace: 5 с)` → код `0`. `detachGrace` — `Duration.zero`: для stdio отсоединение — конец процесса, идущий ход отменяется (§13.10).
- **Уточнение сервера.** До этого change `AcpAgentServer.serve` завершался сразу по концу входа и не закрывал транспорт: прочитанный, но ещё не отвеченный запрос мог остаться без ответа, а транспорт — открытым. Теперь `serve` после конца входа ждёт ответов на начатые запросы, отправляет очередь и закрывает транспорт; повторное закрытие из `shutdown` — та же операция (тест `codelab_agent_acp/test/robustness/half_closed_input_test.dart`).
- **WebSocket:** сервер живёт до сигнала; закрытие одного сокета — отсоединение с `detachGrace` 30 с.
- **Сигналы:** `SIGINT` → shutdown → `130`; `SIGTERM` → shutdown → `143` (те же значения, что у `codelab -p`, §13.10). Повторный сигнал во время shutdown — немедленный выход с тем же кодом.
- **Ошибки использования** — `64`; непойманная ошибка запуска (например, порт занят) — `1` с текстом в stderr.

### D8. Транспортные фикстуры

Формат фикстур знает только JSON-RPC кадры, поэтому получает два расширения (спецификация `acp-golden-fixtures`):

- **`setup.transport`** — `{"kind": "stdio"}` или `{"kind": "ws", "attempts": [{"authorization": "none" | "wrong" | "valid", "expectStatus": 401}]}`. Попытки играются по порядку до основного подключения; основное — всегда с верным токеном.
- **`{"$repeat": {"text": "<s>", "times": <n>}}`** — генератор строки в кадрах `c2a` (материализуется до отправки) и в ожидаемых кадрах `a2c` (сравнивается как точная строка). Без него мегабайтная строка не помещается в читаемую фикстуру.

Фикстуры с `setup.transport` имеют роль `agent` и тег `stdio` или `ws`. Агентский драйвер в памяти их **пропускает** (строка в отчёте, не провал): транспорта в памяти у него нет. Их играет **транспортный драйвер** — `apps/codelab_agent/test/transport_conformance_test.dart`: запускает `fvm dart run bin/codelab_agent.dart serve --stdio|--ws --llm-script <сценарий из fx.llm>` как процесс и проходит кадры через настоящий stdio или WebSocket по тому же алгоритму сравнения (`runAgentFixture` с другим стартером). Это интеграционный тест на Dart VM — разрешён в feature-ветке (`AGENTS.md` §21).

- `acp/stdio-framing-large-line`: промпт из 2 МиБ текста одной строкой; сценарий вызывает `write` с содержимым той же длины в режиме `bypass`, поэтому `tool_call` (`rawInput`), `fs/write_text_file` и `diff` результата — мегабайтные кадры агента одной строкой. Текст ответа модели короткий: стрим по 16 символов дал бы сотни тысяч кадров.
- `acp/ws-auth-bearer-required`: попытки `none` → `401`, `wrong` → `401`, затем подключение с токеном и `initialize`.

Корпус этапа 4 — 35 фикстур (33 + 2), агентская сторона — 46 (11 этапа 0 + 35). `09-09-stage-4-acp-adapter.md` в DoD называет «49 фикстур», а §14.2 — «итого к этапу 4 — 49 (12 + 37)»: это счёт до переноса фикстур выноса (D8 предыдущего change). Оба числа правятся в этом change: 46 с ролью `agent`, 47 всего (12 + 35).

### D9. E2E app против Dart-агента

По контракту `09-09` (таблица «Тест → что нужно для `dart`»), без изменений `apps/codelab_app/lib`:

- `integration_test/support/e2e_agent.dart` — `E2eAgent.current`, `E2eLaunch` (команда, аргументы, ожидания `sessionLabel`, `models`, `permissionTitle`, `rawInputMarker`).
- `integration_test/llm_scripts/<mode.wireName>.json` — сценарии, подобранные так, чтобы видимый результат совпал со scripted-агентом.
- Тег `scripted-only` в `apps/codelab_app/dart_test.yaml`: `crashMidPrompt`, `withFsPathEscape`, `withTerminalPathEscape`, `withTerminalKill`.
- `melos run build:agent` → `fvm dart compile exe apps/codelab_agent/bin/codelab_agent.dart -o build/bin/codelab-agent`; `melos run test:e2e:app:dart-agent` — `build:agent`, затем `flutter test integration_test -d macos --exclude-tags scripted-only` с define из контракта.
- D-02: `permission_flow_test.dart` в режиме `dart` проверяет, что карточка показывает команду `echo hello`. Заголовок `exec` у Dart-агента — сама команда (`ToolPresentation` инструмента, фикстура `acp/tool-exec-terminal-embed`), поэтому `permissionTitle` для `dart` — `echo hello`, а не `Run echo hello`, как было в первой редакции контракта.
- Загрузку сценариев проверяет `apps/codelab_agent/test/llm_scripts_load_test.dart`, а не тест app: приложению запрещено импортировать `codelab_agent_*` (сторож), а файл проверяется только загрузчиком `--llm-script`. Тест читает `apps/codelab_app/integration_test/llm_scripts/*.json` по пути и требует сценарий для каждого режима таблицы контракта.

В feature-ветке тесты только проходят `analyze` (`fvm dart analyze` корня анализирует и `integration_test/`); прогон на устройстве — в `release/<version>`. `build:agent` в `check` не входит: компиляция в exe не проверяет ничего сверх `analyze` и процесса на VM (D10), а занимает минуты в CI.

### D10. Проверка процесса на Dart VM

`apps/codelab_agent/test/stdio_process_test.dart` запускает `dart run bin/codelab_agent.dart serve --stdio --llm-script test/llm_scripts/hello.json` и выполняет DoD этапа без компиляции: `initialize` → ответ, `session/new` → `session/prompt` → `hello`, EOF → код `0`; лог только в stderr, stdout — только JSON-RPC строки. `ws_auth_test.dart` — то же для `--ws` на свободном порту. Тесты входят в `melos run test`.

### D11. Сторож

Правило `apps/codelab_agent` в `rules.dart`: запрещены `package:flutter/`, `package:acp_client_core/`, `package:acp_ui/`, `package:fluent_ui/`. Allowlist зависимостей приложения — `{codelab_agent_core, codelab_agent_io, codelab_agent_acp, acp_protocol, acp_transports, args, http, async, meta}` в `pubspec_allowlist_test.dart`. HOST-6 (документ ядра §10): в `apps/codelab_agent/lib` нет `ToolRegistry(`, `Agent(`, `AgentRuntime(` — текстовая проверка в том же тесте-стороже.

### D12. Итерации и TDD

Задачи — пары «тест → реализация», красные тесты коммитятся до кода. Каждая итерация — PR в `develop` из `feature/add-codelab-agent-binary`, ветка заново от `develop` после слияния.

1. **Транспорты и stdio-бинарь.** Серверные транспорты (D2), приложение, сторож, флаги (D4), сборка хоста (D3), логи (D5), `serve --stdio`, жизненный цикл (D7). DoD: тесты транспортов, `serve_flags_test.dart`, `stdio_process_test.dart`.
2. **WebSocket и транспортные фикстуры.** `serve --ws` с аутентификацией (D6), расширения формата и транспортный драйвер (D8), две фикстуры, правка счёта в документах. DoD: `ws_auth_test.dart`, `transport_conformance_test.dart`, `conformance:agent` — 44 в памяти + 2 пропущены с причиной.
3. **E2E app и Zed.** Помощник, сценарии, тег, melos-скрипты (D9), чек-лист Zed (заполняет пользователь — ручная проверка). DoD: `analyze` app зелёный; `melos run build:agent` выполняется локально; чек-лист заполнен.

### D13. Чек-лист ручной проверки с Zed (задача 4.10)

Заполняется по итогам ручной проверки: `codelab-agent serve --stdio` с реальным провайдером, подключённый в Zed как внешний агент (`agent_servers` в настройках Zed).

Проверка 2026-10-25: Zed 1.25.3 (macOS), бинарь `build/bin/codelab-agent` 0.1.0, провайдер `openai-compatible` — LM Studio (`http://localhost:1234/v1`), модель `qwen/qwen3.5-9b` (`--model cli/qwen/qwen3.5-9b`), режим `standard`; кадры — по ACP-логу Zed.

| Сценарий | Ожидание | Результат |
|---|---|---|
| Подключение | Zed показывает агента, `initialize` и `session/new` без ошибок | ок. Лишние поля `clientCapabilities` Zed (`session`, `auth`, `elicitation`) приняты. Найден дефект: `session/new` с MCP-сервером stdio без поля `type` (так его описывает `03-Session Setup.md`) отклоняется `-32602 Invalid params: type must be a string.`; проверка прошла с выключенными MCP-серверами Zed. Исправление — отдельный fix-PR в `acp_protocol` |
| Промпт | ответ стримится по частям | ок: `agent_thought_chunk` и `agent_message_chunk` дельтами, `session_info_update` с заголовком, ответ `end_turn` последним кадром |
| Инструменты | `read` и `ls` выполняются, вызовы видны в ленте | ок: `ls`, `read` (через `fs/read_text_file`), `search`; параллельные вызовы в одном ответе модели |
| Одобрение | запрос разрешения на `edit` или `exec` показывает аргументы; «разрешить» и «отклонить» работают | ок: `exec` — команда в заголовке и `rawInput`, четыре варианта; `allow_once` → `terminal/create` → `wait_for_exit` → `output` → `release`, `completed`. `edit` — diff в `content` запроса, `allow_once` → `fs/write_text_file`, `completed` с diff. `reject_once` для `exec` → `failed`, `_meta.codelab.outcome: rejected`, ход продолжился текстом |
| Отмена | отмена хода в Zed завершает ход, вызовы — `failed` | ок: `session/cancel` во время `sleep 30` → `terminal/kill` → `output` → `release`, вызов `failed` (`outcome: cancelled`), ответ `stopReason: cancelled`. Замечание: поздний ответ Zed на брошенный `terminal/wait_for_exit` пишется в лог как `warning acp.frame.bad` (unknown response id) — соединение не страдает |
| `session/load` | повторное открытие сессии показывает историю | ок: после перезапуска процесса Zed вызвал `session/load`; реплей реплик, рассуждений, ответов и вызовов в итоговых статусах, затем режим, опции, команды, заголовок и ответ. Замечание: у отменённого вызова в реплее есть текст `[Command was cancelled after …]`, которого не было в живом `tool_call_update` |

### Доказательства Definition of Done

| Строка матрицы | Критерий приёмки | Доказательство |
|---|---|---|
| R-12 | WebSocket только на loopback по умолчанию; без токена или с неверным — отказ до ACP; `Bearer` проходит `initialize` | `ws_auth_test.dart` (426, 401 с `WWW-Authenticate`, `/acp` и `/`, предупреждение `serve.ws.non_loopback`, пустая переменная — код 64); фикстура `acp/ws-auth-bearer-required` в `transport_conformance_test.dart` |
| R-13 | stdio: одно сообщение — одна строка stdout, логи только в stderr, строки любой длины | `stdio_process_test.dart` (stdout — только JSON-RPC, лог в stderr); фикстура `acp/stdio-framing-large-line` (2 MiB одной строкой) в `transport_conformance_test.dart`; ручная проверка с Zed (D13) |
| D-01 | чат со стримингом и одобрениями в ленте против Dart-агента | `app:permission_flow_test.dart`, `app:stdio_connect_flow_test.dart` в режиме `CODELAB_E2E_AGENT=dart` (D9); прогон на устройстве — `melos run test:e2e:app:dart-agent` в `release/<version>` |
| D-02 | карточка показывает команду для `exec`, путь и diff для правок | `app:permission_flow_test.dart` (команда `echo hello`, D9); diff `edit` — ручная проверка с Zed (D13); прогон app — в `release/<version>` |

## Risks / Trade-offs

- **[Правила §15.6 поверх `args` расходятся с будущим CLI]** → правила (переменная как значение по умолчанию, взаимоисключения, `UsageError`) — в одном файле с тестом на каждое правило; на этапе 6 CLI `codelab` переиспользует тот же подход (D1).
- **[Транспортный драйвер медленный: процесс на каждую фикстуру]** → две фикстуры, `dart run` один раз на фикстуру; время прогона под контролем в `melos run test`.
- **[Порт 8765 занят в CI]** → тесты WebSocket используют `--port 0` и читают фактический порт из записи лога `serve.ws.listening` в stderr.
- **[Сигналы не на всех ОС]** → `SIGTERM` недоступен на Windows; там только `SIGINT` (`ProcessSignal.sigint.watch()`), а пути Windows ядро в MVP и так не поддерживает (D16 предыдущего change).
- **[E2E в режиме `dart` не прогоняются до release]** → тесты обязаны проходить `analyze`; сценарии `llm_scripts/*.json` проверяются тестом загрузки в `apps/codelab_agent` (каждый файл — валидный сценарий).
- **[Сценарий `--llm-script` общий для всех сессий]** → шаги расходуются по порядку запросов, как описано в контракте `multi_session_concurrency_flow_test.dart`; это свойство теста, а не продукта.

## Migration Plan

Новых контрактов для существующих пользователей нет: codelab-app продолжает работать с любым агентом, встроенный профиль подключения не меняется. Откат — удаление `apps/codelab_agent` и серверных транспортов; клиентские транспорты и `AcpAgentServer` от них не зависят.

## Open Questions

Нет. Решено при подготовке change:

- **`--local-exec`** (`exec.local_fallback`, §15.6) — этап 8 вместе с конфигом. Без `clientCapabilities.terminal` `exec` выключен с причиной (D5 change `add-dart-agent-acp-server`); локальное исполнение команд в обход клиента — отдельное решение о безопасности, и его ключ живёт в конфиге.
