## Context

Этап 6 (`docs/architecture/proposals/dart-agent-and-clients/09-11-stage-6-cli-mvp.md`) — терминальный клиент `codelab` поверх общего клиентского слоя этапа 5. Источники решений:
- §9.11: команды, флаги, REPL, клавиши, одобрение, headless, драйвер фикстур, обвязка PTY;
- §12.2: поверхности вывода, мысли, строки инструментов, клавиши;
- §9.10: API kit;
- документ ядра: §13 («коды выхода — из событий»), §14 (формат фикстур);
- матрица целей, блоки «Headless» и «CLI/TUI»;
- `docs/architecture/permissions.md`.

Что уже есть в коде:
- **`codelab_client_core`.** `ClientWorkspace` (`connect`, `newSession`, `loadSession`, `loadMoreSessions`, `reconnect`, `dispose`, потоки `state`, `promptOutcomes`, `diagnostics`). `SessionHandle` (`send` с очередью, `cancel`, `respond`, `setConfigOption`, `view`). `SessionView` (транскрипт `TranscriptItem`, `pendingApprovals`, `configOptions`, `agentCommands`, `queue`). `CommandCatalog`. Профили `StdioProfile` и `WebSocketProfile`, `ConfigTransportResolver`, `SecretSource`.
- **`codelab_client_io`.** `ioTransportResolver`, `JsonFileProfileStore`, `JsonFileRecentProjectsStore`.
- **`codelab_acp_testing`.** Загрузчик корпуса, `runAgentFixtureOver`, scripted stdio-агент с 17 режимами (исходник генерируется и запускается `dart <файл>`).
- **`apps/codelab_agent`.** Образец разбора флагов на `package:args`, кодов выхода, сигналов и запуска процесса в тестах (`AgentProcess.kernel()`).

Чего нет:
- плана в `SessionView`: app строит его сам (`currentPlanOf`);
- признака `_meta.codelab.critical` у одобрения;
- кавычек в `parseShellWords`;
- соглашения о `CODELAB_HOME` на стороне клиента;
- `FixtureReplayAgent`;
- правила сторожа для CLI: есть только комментарий в `rules.dart`;
- полной модели отображения §12.1: `ToolRowView`, diff, вывод, `streaming`.

## Goals / Non-Goals

**Goals:**
- Строки матрицы уровня Must этапа 6 — H-01, H-02, H-04, U-01–U-07, U-15 — и Should U-08, U-09 получают доказательства в виде модульных тестов и PTY-e2e.
- `codelab -p` пригоден для скриптов и CI: stdout — только ответ, коды выхода — из событий.
- CLI использует kit так же, как app: своего состояния сессий, очереди и одобрений нет.
- Архитектура готова к следующим change:
  - `add-cli-stream-json` встаёт в `lib/src/headless/` рядом с текстовым выводом;
  - TUI встаёт в `lib/src/tui/`;
  - `embedded` встаёт третьей веткой резолвера профилей.

**Non-Goals:**
- stream-json и `json`, `--include-*`, `--trace-file`, `/trace`, `/inspect`, diff в `?` (D1);
- разведка `dart_tui` и `--ui tui`;
- `cli.yaml`, локализация строк, U-23, `--session`;
- встроенный агент;
- подкоманды конфига.

## Decisions

### D1. Граница MVP и перенос части §9.11

Решение владельца проекта: change закрывает Must этапа и U-08/U-09. Перенесено:
- **stream-json (H-03, Should) и флаги вывода.** `--output-format`, `--include-thoughts`, `--include-acp`, `--input-format` уходят в change `add-cli-stream-json`. Проекции нужны поля, которых в kit нет: `rawInput` и `locations` вызова, итоговый вывод, diffs, `streaming` текста, `durationMs`. Это расширение модели отображения §12.1 и отдельная работа с app.
- **Отвод протокола.** `--trace-file`, `/trace` и `--include-acp` используют один и тот же отвод кадров, поэтому переносятся вместе. `/inspect` и diff правки в `?` переносятся туда же: им нужна та же расширенная модель вызова.
- **Разведка `dart_tui` (6.11).** Уходит в change полноэкранного TUI (U-12). MVP от неё не зависит: REPL и headless пакет не используют. Правило сторожа для `package:dart_tui/` появится вместе с пакетом.
- **Should вне MVP.** `--session` (S-14), bracketed paste, Shift+Enter и `/terminal-setup` (U-23). По §9.0, правило 6, незакрытые Should уходят в отдельный change.

До своего change эти флаги не регистрируются: их использование даёт код `64` `Unknown flag`, как требует §9.11 для флагов более позднего этапа.

Этот change правит §9.11: раздел «OpenSpec change» и DoD (пункты stream-json, `dart_tui` и сторож `package:dart_tui/` переносятся со ссылками на новые change). В §12.5 появляется ссылка на `add-cli-stream-json`.

### D2. Раскладка приложения

```text
apps/codelab_cli/
├── AGENTS.md
├── pubspec.yaml                 # executables: codelab: codelab
├── bin/codelab.dart             # exit(await runCodelab(args, environment: Platform.environment))
├── lib/codelab_cli.dart         # барель: runCodelab
└── lib/src/
    ├── run.dart                 # runCodelab: разбор, выбор режима, коды выхода
    ├── cli_args.dart            # ArgParser, CliOptions, UsageError, usage()
    ├── exit_codes.dart          # 0, 1, 64, 130, 143
    ├── signals.dart             # watchStopSignals
    ├── home.dart                # CodelabHome: CODELAB_HOME, profiles.json, cli_history
    ├── composition_root.dart    # ClientWorkspace + ioTransportResolver + EnvSecretSource
    ├── profiles/                # profile_arg.dart (значение --agent), profiles_command.dart
    ├── render/                  # output_surface.dart, ansi.dart, sanitize.dart, terminal_renderer.dart, tool_row.dart
    ├── input/                   # key_decoder.dart, key_bindings.dart, line_editor.dart, history.dart, terminal.dart (порт), io_terminal.dart
    ├── repl/                    # repl.dart, repl_session.dart, approval_prompt.dart, commands/ (по файлу на команду)
    ├── headless/                # headless_runner.dart, prompt_source.dart, approval_policy.dart, outcome.dart
    └── scenario/                # test_scenario_command.dart, agent_connector.dart
```

Разбивка следует §9.11. Отступления от неё такие:
- `cli_runner.dart` назван `run.dart`, как в `apps/codelab_agent`;
- `exit_codes.dart` вынесен из `headless/` на верхний уровень, потому что коды нужны и REPL, и `test-scenario`.

Логика (рендер ревизий, декодер клавиш, редактор строки, политика одобрений, вычисление кода выхода) — чистый Dart поверх портов. `dart:io` есть только в `run.dart`, `io_terminal.dart`, `home.dart`, `signals.dart`, `composition_root.dart` и `scenario/agent_connector.dart`. Так модульные тесты идут без процессов и терминала (`docs/architecture/testing.md` §1).

### D3. Зависимости и сторож

`dependencies`:
- `codelab_client_core`, `codelab_client_io` и `codelab_client_acp`. Последний нужен composition root (`AcpClientApplication` для `AcpClientBackend`) и типам одобрения (`ApprovalRiskLevel`).
- `codelab_acp_protocol` (`PermissionOptionKind`) и `codelab_acp_transports` (`io.dart` в connector драйвера).
- `codelab_acp_testing`: загрузчик фикстур и `runAgentFixtureOver` для `test-scenario`.
- `args`, `async`, `path`, `meta`.

Новых технологий стека нет: `package:args` уже записан в technology-stack §20б для `apps/codelab_cli`.

`codelab_acp_testing` как обычная зависимость нарушает правило `AGENTS.md` §5 «только `dev_dependency`». Конфликт разрешается узким исключением: `test-scenario` — рабочая команда бинаря (§9.11, H-04), а не тест. Альтернатива — вынести загрузчик и драйвер в отдельный пакет. Это новый пакет ради одной команды (`AGENTS.md` §13), а `codelab_acp_testing` всё равно остался бы его зависимостью. Исключение ограничено сторожем: `package:codelab_acp_testing/` импортируется только из `lib/src/scenario/`. Формулировка `AGENTS.md` §5 и требование `workspace-architecture` правятся в этом change.

Правило сторожа:
- `PackageRule('apps/codelab_cli', forbidden: ['package:flutter/', 'package:fluent_ui/', 'package:codelab_ui/', 'package:codelab_agent_'])`;
- правило для `apps/codelab_cli/lib/src` с `forbidden: ['package:codelab_acp_testing/']` и `exclude: ['scenario/']`, по образцу комментария `dart_tui` в `rules.dart`;
- allowlist `cliAllowlist` в `pubspec_allowlist_test.dart`.

### D4. Домашний каталог и профили

`CodelabHome.resolve(environment)`: значение `CODELAB_HOME`, а без него `$HOME/.codelab` (`%USERPROFILE%\.codelab` на Windows). Тот же каталог использует `codelab-agent` для сессий. Файлы MVP:
- `profiles.json` — `JsonFileProfileStore`, формат kit `{"version":1,"profiles":[…]}`;
- `cli_history` — по строке на запись, многострочный ввод кодируется JSON-строкой, последние 1 000 записей;
- каталог создаётся с правами `0700`, файлы `0600`.

Значение `--agent` разбирает `parseAgentArg` по таблице §9.11:
- `stdio:` — `parseShellWords` kit (D14), id профиля — `inline`;
- URL — `WebSocketProfile(tokenRef: 'env:CODELAB_AGENT_TOKEN')`;
- `embedded` — `UsageError` до этапа 7;
- иначе — поиск в `profiles.json`.

Токен даёт `EnvSecretSource` CLI: ссылка `env:<VAR>` читает переменную окружения, другие ссылки возвращают `null`. Ни значение токена, ни переменная окружения целиком в профиль и в вывод не попадают.

`codelab profiles add <id> <значение>` принимает те же формы, кроме `embedded`, и пишет профиль. Для `StdioProfile` `runInProjectDirectory` равно `true`: агент стартует в `--cwd`.

### D5. Порт терминала и редактор строки

`Terminal` — порт с такими членами:
- `Stream<List<int>> input`;
- `IOSink`-подобный `output`;
- `bool get hasTerminal` (stdin и stdout — TTY);
- `int get columns`;
- `enableRawMode()` и `restore()`.

`IoTerminal` реализует порт на `stdin.echoMode`/`lineMode` и `stdout.hasTerminal`; `restore()` идемпотентен и вызывается в `finally` и из обработчика сигналов.

`KeyDecoder` превращает байты в `KeyEvent`. Он поддерживает UTF-8, разрезанный между чтениями, CSI-последовательности стрелок, одиночный Esc по таймауту 50 мс (подменяемые часы) и Alt+Enter (`ESC CR`).

`KeyBindings` — одна таблица `KeyAction ← (область, клавиша)`. Из неё строятся обработка, `/help keys` и проверка конфликта (TUI-7). Таблица MVP — в требовании «Редактор строки и клавиши»; Ctrl+Enter, Shift+Enter, bracketed paste и `keys` из `cli.yaml` добавляются в неё позже.

`LineEditor` — чистая модель: буфер, курсор, история, многострочность. Перерисовку строки ввода делает рендер.

Без TTY `LineEditor` не используется: ввод идёт построчно через `utf8.decoder` и `LineSplitter`. Это запасной путь для терминалов, где raw-режим не работает (риск §9.11).

### D6. Рендер

`OutputSurface` (`raw`, `plain`, `ansi`) выбирается по §12.2.1; `tui` в MVP нет.

`TerminalRenderer` получает ревизии `SessionView` и выводит изменения. Состояние рендера:
- длина напечатанного текста по `TranscriptItem.id`;
- последний статус каждого вызова;
- последний план.

Ревизии сравниваются так же, как в проекции §12.5.4. Элемент, `identical` прошлой ревизии, пропускается.

Вывод:
- **Текст агента** — хвост сверх напечатанного. Markdown в MVP печатается как есть на всех поверхностях, ANSI-рендер markdown (U-10) — после MVP. Поэтому `plain` отличается от `ansi` только отсутствием цвета.
- **Мысли** — приглушённо (`ESC[2m … ESC[0m`). При `collapsed` после завершения печатается одна строка `thought for <n>s`, при `hidden` ничего; на `raw` мысли не печатаются.
- **Вызов инструмента** — строка `<значок> <title> <command?> <время?>`:
  - значки: `…` выполняется, `✓` успех, `✗` ошибка, `⊘` отменён или отклонён; ASCII-замена `*`, `+`, `x`, `-` при не-UTF-8 локали;
  - деталь — `ToolCallView.command` или путь из заголовка;
  - время — от первого появления до итогового статуса по часам рендера;
  - `rawInput` в строку не попадает (TUI-6).
- **План** — блок `Plan:` и строки `[x]`/`[~]`/`[ ]` по статусу.
- **Заметки** — строка с префиксом по `NoticeKind`.

Перед выводом весь текст из сессии проходит `sanitizeTerminalText`: C0 кроме `\t`/`\n`, DEL и C1 вырезаются, `\t` раскрывается в пробелы (TUI-11). Строка с атрибутами кончается `ESC[0m` (TUI-9).

### D7. REPL и клиентские команды

Сам цикл — `Repl`, состояние активной сессии и вывод — `ReplSession`. Состояния ввода:
- `editing` — ввод промпта;
- `awaitingApproval` — блок одобрения;
- `running` — ход идёт, ввод открыт и уходит в очередь.

Ход и очередь — `SessionHandle.send` и `SessionHandle.queue`.

Команды — `ReplCommand { name, description, Future<void> run(ReplContext, List<String> args) }`, по файлу на команду в `repl/commands/`. Набор MVP — в требовании «Slash-меню и клиентские команды». Отображение на ACP:
- `/new` — `newSession`;
- `/sessions` — `WorkspaceState.sessions` с `loadMoreSessions`;
- `/resume` — `loadSession`;
- `/mode` и `/model` — `setConfigOption` с опциями `mode` и `model`;
- `/config` — любая опция;
- `/cancel` — `cancel`;
- `/reconnect` — `reconnect`;
- `/profile <id>` — `dispose` и новый `connect`.

Kit не поддерживает устаревший `session/set_mode`, поэтому `/mode` работает только через опцию конфигурации `mode`. Агент без неё получает сообщение `The agent does not expose a "mode" config option.` Python-агент и Dart-агент объявляют режим опцией.

Слияние каталога — `CommandCatalog(host: …, agent: view.agentCommands)`. Все команды клиента доступны (`isAvailable: true`), поэтому одноимённые команды агента остаются в каталоге рядом, и CLI сам решает:
- `/<имя>` — команда клиента;
- `/agent:<имя>` — промпт `/<имя> …`;
- имя, известное только агенту, — промпт без префикса.

Tab дополняет по `catalog.search`.

### D8. Одобрение в REPL

`ApprovalPrompt` строит блок из `PendingApprovalView`:
- заголовок `Permission: <title>` с риском;
- `command:` — `command` или первая строка `rawInput` без сериализации объекта;
- `cwd:` — `SessionHandle.cwd`;
- подсказка из клавиш только тех вариантов, `kind` которых есть в `options`.

Если вариантов одного `kind` несколько, клавиша выбирает первый.

`?` печатает `rawInput` целиком через `formatRedactedJson` kit; diff правки появится в `add-cli-stream-json`. Esc и Ctrl+C вызывают `SessionHandle.cancel`. По ACP отмена хода сама даёт ожидающим запросам исход `cancelled`, и kit отражает это в `ResolvedApprovalView`. Новые запросы показываются по одному в порядке `pendingApprovals`.

### D9. Headless

`HeadlessRunner` работает по шагам:
1. подключение;
2. `newSession`, `loadSession` по `--resume`, или последняя сессия по `--continue`;
3. `--model` и `--mode`;
4. `send`;
5. ожидание `PromptOutcome` этой сессии.

Ответ печатается дельтами `AgentTextItem` по мере ревизий (`raw`): скрипт, читающий pipe, видит текст сразу. В конце, если ответ не кончается `\n`, печатается `\n`.

`HeadlessOutcome` — sealed-иерархия:
- `Completed(stopReason, hadText)`;
- `Failed(PromptFailure)`;
- `ConnectFailed`;
- `TimedOut`;
- `Signalled(code)`.

`exitCodeOf(HeadlessOutcome)` — единственное место таблицы кодов (H-02, документ ядра §13). Пустой ответ (`end_turn` без `AgentTextItem` хода) даёт код `1` и строку stderr `empty response`.

`ApprovalPolicy` — чистая функция `decide(PendingApprovalView, policy) → Decision(optionId | cancelled, reason)` по требованию «Политика одобрений headless». Вид `read` определяется по `ToolCallView.kind` вызова в транскрипте.

`--timeout` — `Timer`, затем `SessionHandle.cancel`; итог — `TimedOut` → `130`.

Headless сам не переподключается. Обрыв соединения — `Failed(ConnectionLost)` → `1`.

Источники промпта — `PromptSource`. Позиционные аргументы MVP — только первое сообщение REPL, склеенное пробелом (§9.11 «`codelab [опции] [первое сообщение]`»). Строка H-01 матрицы описывает ещё разбор файлов в позиционных аргументах и `resource_link`. Kit сейчас шлёт только текст (`SessionHandle.send(String)`), поэтому эта часть переносится к вложениям (U-14, §12.2.8), а критерий H-01 в матрице уточняется в этом change.

### D10. Scripted stdio-агент: режимы для CLI

Сценарии CLI проверяются тем же scripted stdio-агентом, что e2e app; режимы добавляются в `CodelabCompatibleStdioAgentMode`:
- `with_tool_calls` — `agent_thought_chunk` ×3, вызовы `read` (`completed`), `exec` с `rawInput.env` (`completed`) и `edit` с запросом одобрения, затем ответ;
- `prompt_error` — JSON-RPC ошибка `-32603` с `data.codelab.errorClass: provider` на `session/prompt`;
- `empty_response` — `end_turn` без `agent_message_chunk`;
- `hangs_until_cancel` — не отвечает на `session/prompt`, пока не придёт `session/cancel`, затем `cancelled`;
- `with_critical_permission` — запрос одобрения с `_meta.codelab.critical: true` и вариантами `allow_once` и `reject_once`.

Существующие режимы переиспользуются:
- `normal` — стриминг;
- `with_permission_request` — одобрение;
- `with_config_options` — `/model`, `/mode`;
- `with_available_commands` — slash-меню;
- `with_queued_prompt_drain` — очередь;
- `with_session_list` — `--continue` и `/sessions`;
- `with_plan` — план;
- `crash_mid_prompt` — обрыв.

Каждый новый режим получает тест в `codelab_acp_testing/test/`.

### D11. Обвязка PTY и запуск CLI в тестах

`PtyProcess` описан в §9.11: `script` по ОС, проверка `script --version`, нормализация `\r\n`. Обвязка — в `test/e2e/support/` и пишется своя, а не берётся из `apps/codelab_agent`: приложения не зависят друг от друга. CLI в e2e запускается из kernel, который один раз компилируется в `setUpAll`. Так тесты идут на Dart VM в `melos run test` без предварительной сборки. `build:cli` проверяется отдельно (`testing-quality`).

Ввод клавиш — байты в stdin обвязки. Ожидание вывода — `expectLater(pty.output, emitsThrough(contains(…)))` с таймаутом 10 с.

`test:e2e:cli` — `fvm dart test apps/codelab_cli/test/e2e`.

### D12. Драйвер фикстур

`TestScenarioCommand` выполняет:
- загрузку путей (`loadFixtureFile` или `loadFixtureCorpus(directory:)`) и фильтр `--filter` (glob по id);
- для каждой фикстуры — `runAgentFixtureOver(fixture, connector)`.

`AgentConnector` строит из профиля процесс агента и клиентский транспорт:
- `stdio` — `StdioAcpTransport` на запущенном процессе;
- `ws` — `WebSocketAcpTransport` к URL.

Для `stdio`, у которого базовое имя команды `codelab-agent`, блок `llm` фикстуры пишется во временный файл, и к аргументам добавляется `--llm-script <файл>`; временный файл удаляется после фикстуры. Для другого агента фикстура с `llm` пропускается с причиной `third-party agent: llm script cannot be passed`.

Дифф `FAIL` — из `AgentFixtureResult` или сообщения расхождения драйвера: ожидаемый и фактический кадр в виде JSON с отступами. Нормализация — правила корпуса, своей у CLI нет.

`FixtureReplayAgent` (`codelab_acp_testing`) отвечает на кадры клиента ожидаемыми кадрами агента той же фикстуры, подставляя захваченные значения. Он нужен, чтобы `test_scenario_command_test.dart` проверял драйвер на всём корпусе без настоящего агента (DoD §9.11). Процессный вариант генерируется как исходник по образцу scripted stdio-агента: путь фикстуры передаётся аргументом.

Прогон против настоящего агента:
- `--agent 'stdio:codelab-agent serve --stdio'` — интеграционный тест на собранном kernel бинаря агента, пропускается, если бинаря нет;
- `embedded` — этап 7.

### D13. Сигналы

`watchStopSignals` в `apps/codelab_cli/lib/src/signals.dart` повторяет семантику бинаря агента (`apps/codelab_agent/lib/src/serve/signals.dart`): первый сигнал — безопасное завершение, второй — выход сразу. Код один и тот же, но приложения не зависят друг от друга, а в общий пакет он не выносится: в `codelab_client_io` ему не место, а пакет ради 30 строк — лишняя церемония (`AGENTS.md` §13).

Безопасное завершение:
1. `cancel` идущего хода;
2. ожидание ответа до 2 с;
3. `ClientWorkspace.dispose`: транспорт закрывается, а `StdioAcpTransport` завершает дочерний процесс;
4. `Terminal.restore()`;
5. выход с кодом.

В raw-режиме Ctrl+C приходит байтом `0x03`, а не сигналом, и обрабатывается таблицей клавиш.

### D14. Доработки kit

- **`SessionView.plan: List<PlanEntryView>`** (`content`, `status`, `priority`). Проекция идёт из `PlanUpdate` сессии тем же правилом, что `currentPlanOf` app: последнее обновление заменяет план. `apps/codelab_desktop` переходит на `SessionView.plan`, `currentPlanOf` удаляется. Поведение app не меняется, и это подтверждают его тесты плана.
- **`PendingApprovalView.critical: bool`** из `_meta.codelab.critical` запроса; значение, отличное от `true`, даёт `false`.
- **`parseShellWords`** — POSIX-разбор без подстановок, как в требовании kit. Пользователи — профиль `stdio:` CLI и поле команды профиля в app; для команд без кавычек результат не меняется.

### D15. Строки CLI

Строки CLI MVP — английские константы в `lib/src/strings.dart`, одно место для будущего каталога. Локализация (`--lang`, TUI-12, `cli/strings-localized`) приходит после MVP. Блок одобрения §9.11 в документе показан по-русски; в MVP он выводится по-английски (`Permission:`, `[y] allow once`), и §9.11 правится примечанием.

### D16. Итерации и TDD

Итерации — тонкие сквозные срезы (§9.0, правило 8), каждая — отдельный PR в `develop`:
1. **Headless-срез.** Группы 1–3: приложение и сторож, профили, `codelab -p` с текстовым выводом и базовыми кодами. Закрывает часть H-01 и H-02, U-06 (stdio).
2. **Headless полностью.** Группа 4: политика одобрений, `--timeout`, сигналы, stdin и `-f`, `--resume`/`--continue`, `--model`/`--mode`. Закрывает H-01, H-02.
3. **REPL: ход.** Группы 5–6: PTY, рендер, редактор строки, история, очередь, план в kit. Закрывает U-01, U-07, U-08, U-09, U-15.
4. **REPL: взаимодействие.** Группа 7: одобрение, slash-меню, команды, профили. Закрывает U-02–U-06.
5. **Драйвер фикстур.** Группа 8: закрывает H-04.
6. **Документы и DoD.** Группа 9.

Модульные тесты пишутся первыми (красный коммит до кода). PTY-e2e — приёмочные ворота итерации (§9.0, исключение (б)).

## Risks / Trade-offs

- **[Raw-режим ломается в отдельных терминалах (Windows Console, tmux)]** → построчный режим без TTY, PTY-e2e на macOS и Linux, ручная проверка на Windows перед релизом (§9.11).
- **[PTY-e2e нестабильны по времени]** → ожидание по содержимому вывода, а не по паузам; таймаут 10 с; одиночный Esc различается по подменяемым часам декодера только в модульных тестах, а в e2e Esc подаётся отдельной записью с паузой больше таймаута.
- **[Утилиты `script` нет в CI]** → тест пропускается с сообщением; на runner Ubuntu и macOS утилита есть, поэтому e2e в CI фактически выполняются.
- **[Команда `codelab` занята Python-агентом]** → до этапа 9 бинарь лежит только в `build/bin` (§9.11, допущение 5).
- **[`codelab_acp_testing` в рабочем бинаре]** → импорт ограничен `lib/src/scenario/` сторожем; размер бинаря растёт незначительно.
- **[Перенос stream-json откладывает H-03]** → H-03 — Should и M2 не держит; `add-cli-stream-json` — следующий change этапа.
- **[Markdown без ANSI-рендера]** → U-10 — Should после MVP; на `raw` текст байт в байт и так требуется.

## Migration Plan

Новое приложение: ничего не мигрирует. App переходит с `currentPlanOf` на `SessionView.plan` в той же итерации, где появляется поле. `parseShellWords` для строк без кавычек даёт прежний результат. Откат — revert PR итерации.

## Open Questions

Открытых вопросов нет. Решения владельца по объёму (D1) и разведке `dart_tui` приняты при создании change.
