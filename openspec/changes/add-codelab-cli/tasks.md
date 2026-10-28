Задачи идут парами «тест → реализация» (§9.0, правило 3). В скобках — задача этапа 6 (`dart-agent-and-clients/09-11-stage-6-cli-mvp.md`), строка матрицы целей и требование спецификации.

Пути — в `apps/codelab_cli/`, если не указано иное. Группы задач по итерациям (design.md, D16):
- группы 1–3 — итерация 1 (headless-срез);
- группа 4 — итерация 2 (headless полностью);
- группы 5–6 — итерация 3 (REPL: ход);
- группа 7 — итерация 4 (REPL: взаимодействие);
- группа 8 — итерация 5 (драйвер фикстур);
- группа 9 — итерация 6 (документы и DoD).

Каждая итерация — отдельный PR в `develop`. PTY-e2e — приёмочные ворота итерации (§9.0, исключение (б)), модульные тесты пишутся первыми.

## 1. Приложение и сторож (6.1)

- [x] 1.1 Создать `apps/codelab_cli`: `pubspec.yaml` с зависимостями design.md D3 и `executables: codelab: codelab`, вложенный `AGENTS.md` (правила приложения, порт `Terminal`, импорт `codelab_acp_testing` только из `lib/src/scenario/`, TDD, готовность итерации), `bin/codelab.dart`, барель `lib/codelab_cli.dart`; добавить в `workspace:` корневого `pubspec.yaml`; `melos bootstrap`
- [x] 1.2 Тест (workspace-architecture «Автоматический сторож границ пакетов»): правила `apps/codelab_cli` и `apps/codelab_cli/lib/src` (без `scenario/`) в `codelab_architecture_tests/test/support/rules.dart` вместо комментария этапа 6, `cliAllowlist` в `pubspec_allowlist_test.dart`, негативные тесты: `package:codelab_agent_core/` в `lib/` и `package:codelab_acp_testing/` в `lib/src/repl/` → нарушение (красный)
- [x] 1.3 Реализовать правила и allowlist — 1.2 зелёный; `fvm dart run melos run guard` зелёный
- [x] 1.4 Тест (codelab-cli «Команда codelab и разбор флагов»): `test/cli_args_test.dart` — `parseCliArgs(args, environment)`: REPL без `-p`; `-p`, `-f`, `--approve`, `--timeout` (`90s`, `10m`, неверная длительность → `UsageError`); `--resume` вместе с `--continue` → `UsageError`; незарегистрированные флаги (`--output-format`, `--include-thoughts`, `--trace-file`, `--ui`, `--session`) → `UsageError('Unknown flag …')`; неизвестная подкоманда → `UsageError('Unknown command …')`; `--version`, `--help` (красный)
- [x] 1.5 Реализовать `lib/src/cli_args.dart` (`ArgParser`, `CliOptions`, `UsageError`, `usage()`), `exit_codes.dart`, `run.dart` с `--version`/`--help` и кодом `64` на `UsageError` (stdout пуст) — 1.4 зелёный

## 2. Профили (6.2, U-06)

- [x] 2.1 Тест (acp-client-kit «Профили и резолверы транспорта»): `packages/dart/codelab_client_core/test/connection/profile_parsing_test.dart` — кавычки одинарные и двойные, `\"` и `\\` в двойных, `\ ` вне кавычек, пустые слова в кавычках, незакрытая кавычка → `FormatException`, строки без кавычек — как раньше (красный)
- [x] 2.2 Реализовать `parseShellWords` по POSIX без подстановок (design.md, D14) — 2.1 зелёный; в app незакрытая кавычка в аргументах stdio — ошибка формы с причиной (`apps/codelab_desktop/test/features/workbench/application/stdio_args_quotes_test.dart`); тесты профилей app зелёные
- [x] 2.3 Тест (codelab-cli «Профили подключения CLI»): `test/home_test.dart` — `CODELAB_HOME` и умолчание `$HOME/.codelab`, создание каталога `0700`; `test/profiles/profile_arg_test.dart` — `stdio:` с кавычками, `ws://` и `wss://` с `tokenRef: env:CODELAB_AGENT_TOKEN`, `embedded` → `UsageError` с текстом этапа 7, id из `profiles.json`, неизвестный id, нет `default` → текст подсказки; `EnvSecretSource` читает только `env:*`; `test/profiles/profiles_command_test.dart` — `list`, `show`, `add`, `remove` на временном `CODELAB_HOME`, токен в файл не пишется (красный); `ProfileStore.remove` — тест в `packages/dart/codelab_client_io/test/stores/json_file_stores_test.dart` (spec acp-client-kit «IO-адаптеры клиента»)
- [x] 2.4 Реализовать `lib/src/home.dart`, `profiles/profile_arg.dart` (с `EnvSecretSource`), `profiles/profiles_command.dart`, `ProfileStore.remove` в kit и `JsonFileProfileStore` (design.md, D4, D14) — 2.3 зелёный

## 3. Headless: срез `codelab -p` (6.7, H-01, H-02)

- [x] 3.1 Тест (cli-headless «Коды выхода headless»): `test/headless/exit_codes_test.dart` — `exitCodeOf` по каждой ветке `HeadlessOutcome`: `end_turn` с текстом → `0`; без текста, `max_tokens`, `max_turn_requests`, `refusal`, `PromptFailure` ошибки агента и обрыва, `ConnectFailed` → `1`; `TimedOut` → `130`; `Signalled(130|143)` (красный)
- [x] 3.2 Реализовать `lib/src/headless/outcome.dart` и `exitCodeOf` (design.md, D9) — 3.1 зелёный
- [x] 3.3 Тест (cli-headless «Вывод headless»): `test/headless/headless_runner_test.dart` на `ClientWorkspace` поверх `InProcessAcpLink` или `FakeAcpTransport`: дельты `AgentTextItem` пишутся в stdout по мере ревизий байт в байт, `\n` в конце, мысли и строки инструментов не попадают в stdout, строки инструментов — в stderr, `--verbose` — диагностика в stderr (красный)
- [x] 3.4 Реализовать `lib/src/headless/headless_runner.dart` (подключение, `newSession`, `send`, ожидание исхода, вывод), `composition_root.dart` (`ClientWorkspace` + `ioTransportResolver` + `EnvSecretSource`), `cli_logger.dart` (лог ядра клиента только в stderr и только с `--verbose`: по умолчанию ядро пишет JSON в stdout; `test/cli_logger_test.dart`) и `render/sanitize.dart` раньше задачи 5.4 — строки инструментов headless в stderr (`test/render/sanitize_test.dart`) — 3.3 зелёный
- [x] 3.5 Обвязка запуска CLI в тестах: `test/support/cli_process.dart` (kernel компилируется один раз, `start(args, {environment, workingDirectory, stdin})`, захват stdout и stderr) и `test/support/scripted_agent.dart` (исходник scripted stdio-агента во временном каталоге, значение `--agent`)
- [x] 3.6a Тест (acp-protocol-client «Неожиданный отказ транспорта транслируется в состояние соединения»): `packages/dart/codelab_client_acp/test/application/agent_exit_during_initialize_test.dart` — отказ транспорта во время `initialize` сразу завершает `connect` (красный); реализовать обрыв ожидающих запросов в состоянии `initializing` — зелёный (design.md, D14)
- [x] 3.6 E2E `cli/headless-print-basic` (`test/e2e/headless_print_basic_test.dart`): `codelab -p hello -a 'stdio:dart <agent.dart>'` против режима `normal` → stdout с текстом ответа, код `0`; пустой `CODELAB_HOME` без `--agent` → код `64` и подсказка, агент не запущен; `--agent 'stdio:/nonexistent'` → код `1`
- [x] 3.7 Скрипты `build:cli` и `test:e2e:cli` в корневом `pubspec.yaml` (testing-quality «Проверки workspace»); проверка: `build/bin/codelab --version`
- [x] 3.8 Проверка итерации 1: `fvm dart run melos run check` зелёный (новое приложение в `guard` и `test`); PR итерации 1

## 4. Headless полностью (6.7, 6.9, H-01, H-02)

- [x] 4.1 Тест (acp-client-kit «Одобрения привязаны к вызову»): `packages/dart/codelab_client_core/test/` — `PendingApprovalView.critical` из `_meta.codelab.critical: true`, `false` без поля и при нестроковом/небулевом значении (красный)
- [x] 4.2 Реализовать `ApprovalRequest.critical` в `codelab_client_acp` и `PendingApprovalView.critical` в kit (признак из `_meta` запроса или его `toolCall`, design.md, D14), перегенерировать freezed — 4.1 зелёный (`packages/dart/codelab_client_core/test/approvals/critical_approval_test.dart`)
- [x] 4.3 Тест (cli-headless «Политика одобрений headless»): `test/headless/approval_policy_test.dart` — `reject`, `read-only` (вид `read` → `allow_once`, иначе `reject_once`), `allow-all` (критичный → `reject_once` с причиной `critical`), нет нужного варианта → первый `reject_*`, нет `reject_*` → `cancelled`; строка stderr решения (красный)
- [x] 4.4 Реализовать `lib/src/headless/approval_policy.dart` и ответ раннера через `SessionHandle.respond`, предупреждение `allow-all` — 4.3 зелёный
- [x] 4.5 Тест (cli-headless «Источники промпта headless»): `test/headless/prompt_source_test.dart` — `-p` не читает файл с таким именем, `-f <файл>`, `-f -`, stdin не TTY, пустой промпт → `UsageError('No prompt.')`, ошибка чтения файла → `UsageError`, позиционные аргументы вместе с `-p` → `UsageError` (красный)
- [x] 4.6 Реализовать `lib/src/headless/prompt_source.dart` — 4.5 зелёный
- [x] 4.7 Тест: `headless_runner_test.dart` дополняется — `--timeout` → `cancel` и `TimedOut`; `--resume <id>` → `loadSession`, реплей не печатается; `--continue` → последняя сессия по `updatedAt`; `--model`/`--mode` → `setConfigOption` до `send`, неизвестное значение → код `1` с сообщением; агент без `loadSession` и `--resume` → код `1` (красный)
- [x] 4.8 Реализовать таймаут, загрузку сессии и опции в `headless_runner.dart` — 4.7 зелёный
- [x] 4.9 Тест (codelab-cli «Сигналы CLI»): `test/signals_test.dart` — безопасное завершение вызывает `cancel`, ждёт до 2 с, `dispose`, `restore`; повторный сигнал — немедленный код (на фейковом источнике сигналов) (красный)
- [x] 4.10 Реализовать `lib/src/signals.dart` и безопасное завершение в `run.dart` (design.md, D13) — 4.9 зелёный
- [x] 4.11 Режимы scripted stdio-агента `prompt_error`, `empty_response`, `hangs_until_cancel`, `with_critical_permission` с тестами в `packages/dart/codelab_acp_testing/test/` (design.md, D10)
- [x] 4.12 E2E: `cli/headless-exit-codes` (`prompt_error` → `1`, `empty_response` → `1`, `--timeout 1s` с `hangs_until_cancel` → `130` и `session/cancel` у агента, неизвестный флаг → `64`, SIGTERM во время хода → `143`, SIGINT → `130`), `cli/headless-permission-denied` (`with_permission_request` без `--approve` → `reject_once`, строка stderr), `cli/headless-bypass-flag` (`--approve allow-all` разрешает обычный запрос и отклоняет критичный, предупреждение в stderr), `cli/resume-last-session` (`with_session_list`: `-p` создаёт сессию, `-c -p` продолжает её)
- [x] 4.13 Проверка итерации 2: `check` зелёный; PR итерации 2

## 5. План в kit и рендер (6.3, U-01, U-08, U-09)

- [x] 5.1 Тест (acp-client-kit «Публикация представлений сессии»): `packages/dart/codelab_client_core/test/` — `SessionView.plan` пуст до `plan`, заменяется целиком, порядок записей агента (красный)
- [x] 5.2 Реализовать `SessionView.plan` и `PlanEntryView` в kit; перевести `apps/codelab_desktop` с `currentPlanOf` на `SessionView.plan` и удалить `currentPlanOf`; тесты плана app зелёные (design.md, D14) — 5.1 зелёный
- [x] 5.3 Тест (codelab-cli «Поверхности вывода»): `test/render/output_surface_test.dart` — порядок условий §12.2.1; `test/render/sanitize_test.dart` — C0, DEL, C1, `ESC` вырезаны, `\t` раскрыт, `\n` сохранён (красный)
- [x] 5.4 Реализовать `render/output_surface.dart`, `render/ansi.dart`, `render/sanitize.dart` — 5.3 зелёный
- [x] 5.5 Тест (codelab-cli «Рендер хода в REPL»): `test/render/terminal_renderer_test.dart` на последовательностях ревизий `SessionView` — дельты без повтора, склейка нескольких обновлений в одной ревизии, мысли `ESC[2m` до ответа и режимы `dim|collapsed|hidden`, на `raw` мыслей нет и ANSI нет; план целиком при изменении; заметки; `test/render/tool_row_test.dart` — значки по статусу, ASCII-замена, деталь из `command`, время по фейковым часам, `rawInput` не выводится (красный)
- [x] 5.6 Реализовать `render/terminal_renderer.dart` и `render/tool_row.dart` (design.md, D6) — 5.5 зелёный

## 6. Ввод, REPL-ход и PTY (6.4, 6.5, 6.10, U-01, U-07, U-15)

- [x] 6.1 Тест (testing-quality «PTY-e2e терминального клиента»): `test/e2e/support/pty_process_test.dart` — `sh -c 'test -t 0 && test -t 1; exit 3'` → код `3`, `tput cols` → `100`; без `script` в `PATH` → пропуск (красный)
- [x] 6.2 Реализовать `test/e2e/support/pty_process.dart` по таблице ОС §9.11 (design.md, D11) — 6.1 зелёный на macOS; Linux — в CI
- [x] 6.3 Тест (codelab-cli «Редактор строки и клавиши»): `test/input/key_decoder_test.dart` — UTF-8, разрезанный между чтениями, стрелки, одиночный Esc по таймауту на фейковых часах, `ESC CR` → Alt+Enter, `0x03`, `0x04`; `test/input/key_bindings_test.dart` — таблица MVP, `/help keys` строится из неё, конфликт двух клавиш одной области — ошибка; `test/input/line_editor_test.dart` — вставка и удаление UTF-8, курсор, многострочность (Alt+Enter, Ctrl+J, `\` + Enter), история ↑/↓; `test/input/history_test.dart` — файл `cli_history`, многострочная запись, предел 1 000, права `0600` (красный)
- [x] 6.4 Реализовать `input/key_decoder.dart`, `key_bindings.dart`, `line_editor.dart`, `history.dart`, порт `terminal.dart` и `io_terminal.dart` (design.md, D5) — 6.3 зелёный
- [x] 6.5 Тест: `test/repl/repl_test.dart` на фейковом `Terminal` и `ClientWorkspace` поверх `InProcessAcpLink` — первое сообщение из позиционных аргументов, Enter отправляет, во время хода Enter ставит в очередь (`queued: 1`) и очередь уходит после хода, Esc и Ctrl+C во время хода → `cancel`, вне хода Esc очищает строку, двойной Ctrl+C за 1 с и Ctrl+D на пустой строке → выход `0`, `restore()` на любом выходе; без TTY — построчный ввод (красный)
- [x] 6.6 Реализовать `repl/repl.dart`, `repl/repl_session.dart` (состояния `editing`, `awaitingApproval`, `running`) — 6.5 зелёный
- [x] 6.7 Режим scripted stdio-агента `with_tool_calls` с тестом (design.md, D10)
- [x] 6.8 E2E (PTY): `cli/repl-prompt-streaming` (`normal`: ответ дельтами; в pipe — без `0x1B`; с `NO_COLOR=1` — без SGR), `cli/esc-cancels-turn` (`hangs_until_cancel`: Esc → `session/cancel`, ввод снова доступен), `cli/prompt-queue-drains-after-turn` (`hangs_until_cancel`: первый ход отменяется Esc, промпт из очереди уходит следующим; `with_queued_prompt_drain` ждёт ответа на одобрение, а ввод во время одобрения недоступен до группы 7), `cli/thought-rendered-dimmed` и `cli/tool-row-format` (`with_tool_calls`: `ESC[2m`, строки инструментов без `{` и `"env"`), SIGTERM во время хода → `143`, терминал восстановлен
- [x] 6.9 Проверка итерации 3: `check` зелёный; PR итерации 3

## 7. Одобрение, slash-меню и команды (6.5, 6.6, U-02–U-06)

- [x] 7.1 Тест (codelab-cli «Одобрение в REPL»): `test/repl/approval_prompt_test.dart` — блок из `PendingApprovalView` (заголовок, риск, команда, папка), подсказка только с предложенными вариантами, `y`/`a`/`n`/`N` → `optionId` нужного `kind`, клавиша непредложенного варианта и Enter ничего не отправляют, `?` печатает `rawInput` через `formatRedactedJson` и снова спрашивает, Esc → `cancel`, два запроса — по одному в порядке прихода, ввод промпта недоступен во время вопроса (красный)
- [x] 7.2 Реализовать `repl/approval_prompt.dart` и состояние `awaitingApproval` (design.md, D8) — 7.1 зелёный
- [x] 7.3 Тест (codelab-cli «Slash-меню и клиентские команды»): `test/repl/command_router_test.dart` — `/имя` клиента сильнее одноимённой команды агента, `/agent:<имя>` и имя только агента → промпт `/<имя> аргументы`, неизвестная команда → `Unknown command`, Tab: один кандидат подставляется, несколько — список с пометкой агента, новое `available_commands_update` меняет каталог (красный)
- [x] 7.4 Реализовать маршрутизатор команд поверх `CommandCatalog` и Tab-дополнение (design.md, D7) — 7.3 зелёный
- [x] 7.5 Тест: `test/repl/commands/` — по файлу на команду MVP: `/help` и `/help keys`, `/exit`/`/quit`, `/new`, `/sessions`, `/resume`, `/mode` и `/model` (список с отметкой текущего, установка, неизвестное значение без запроса, нет опции `mode` — сообщение), `/config`, `/cancel`, `/queue`, `/queue drop`, `/queue clear`, `/profile`, `/reconnect`, `/plan`, `/clear`, `/thoughts` (красный)
- [x] 7.6 Реализовать команды в `repl/commands/` — 7.5 зелёный
- [x] 7.7 E2E (PTY): `cli/repl-permission-allow-once` и `cli/repl-permission-reject` (`with_permission_request`), `cli/slash-menu-merges-agent-commands` (`with_available_commands`: Tab показывает `compact` и `plan` с пометкой, `/agent:plan` уходит промптом), `cli/client-commands-smoke` (`with_session_list`: `/help`, `/new`, `/sessions`, `/resume 1`, `/cancel`, `/exit`), `cli/model-picker-sets-config-option` (`with_config_options`), `cli/connect-profiles-stdio-ws-embedded` (stdio-профиль из `profiles.json`; WebSocket к `codelab-agent serve --ws` на собранном kernel бинаря агента с токеном из `CODELAB_AGENT_TOKEN`, пропуск без бинаря; `embedded` → `64`)
- [x] 7.8 Проверка итерации 4: `check` зелёный; PR итерации 4

## 8. Драйвер фикстур (6.8, H-04)

- [x] 8.1 Тест (acp-golden-fixtures «Агент-повторитель фикстуры»): `packages/dart/codelab_acp_testing/test/fixture_replay_agent_test.dart` — агентский драйвер против `FixtureReplayAgent` в процессе: весь корпус с ролью `agent` даёт `PASS`; кадр клиента вне фикстуры → `-32600`; процессный вариант (`dart <файл> <фикстура>`) отвечает на `initialize` (красный)
- [x] 8.2 Реализовать `FixtureReplayAgent` и генератор его исходника (design.md, D12) — 8.1 зелёный
- [x] 8.3 Тест (cli-scenario-driver «Команда test-scenario», «Вывод и коды выхода test-scenario»): `test/scenario/test_scenario_command_test.dart` — корпус против процессного `FixtureReplayAgent` → все `PASS`/`SKIP`, код `0`; копия фикстуры с испорченным ожидаемым кадром → `FAIL` с диффом, код `1`; `--filter`; фикстура без роли `agent` → `SKIP` с причиной; сторонний агент и фикстура с `llm` → `SKIP`; битый файл → код `64`; `embedded` → `64`; агент не запускается → `1`; формат строк и итога (красный)
- [x] 8.4 Реализовать `scenario/test_scenario_command.dart` и `scenario/agent_connector.dart` поверх `runAgentFixtureOver`, `--llm-script` для `codelab-agent` — 8.3 зелёный
- [x] 8.5 Интеграционный тест: `test-scenario` на корпусе с `--agent 'stdio:<kernel codelab-agent> serve --stdio'` — фикстуры роли `agent` без транспортного блока `PASS`; пропуск, если kernel бинаря агента не собирается
- [x] 8.6 Проверка итерации 5: `check` зелёный; PR итерации 5

## 9. Документы и Definition of Done

- [x] 9.1 `09-11-stage-6-cli-mvp.md`: раздел «OpenSpec change» и DoD — перенос stream-json и флагов вывода в `add-cli-stream-json`, разведки 6.11 и сторожа `package:dart_tui/` в change TUI, `--trace-file`/`/trace`/`/inspect`, U-23 и `--session`; примечание о строках MVP по-английски (design.md, D1, D15); `12-5-stream-json.md` — ссылка на `add-cli-stream-json`
- [x] 9.2 `agent-parity-goals.md`: статусы H-01, H-02, H-04, U-01–U-09, U-15 и уточнение критерия H-01 (позиционные файлы — к U-14, design.md, D9); `AGENTS.md` §5 — `apps/codelab_cli` в структуре и назначении, исключение для `codelab_acp_testing` (design.md, D3); `docs/architecture/testing.md` — PTY-e2e CLI, если раздел описывает уровни тестов приложений
- [x] 9.3 Ручная проверка с Python-агентом (`codelab -a 'stdio:codelab serve --stdio'`): промпт, одобрение, `/mode`, `/sessions`, `/resume`; итог — в описании PR. Одобрение на Python-агенте не проверяется: его mock-провайдер не вызывает инструменты; одобрение закрывают PTY-e2e `cli/repl-permission-*` против scripted-агента
- [ ] 9.4 Проверка DoD: `fvm dart run melos run check` и `test:e2e:cli` зелёные локально и в CI (macOS локально, Linux в CI); `build:cli` даёт `build/bin/codelab`; `openspec validate add-codelab-cli` без ошибок; PR итерации 6
