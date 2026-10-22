# 9.11. Этап 6 — codelab_cli MVP

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.10. Этап 5 — Общий клиентский слой](09-10-stage-5-client-kit.md) · [Оглавление](../dart-agent-and-clients.md) · [9.12. Этап 7 — Встроенный режим в обоих клиентах](09-12-stage-7-embedded.md) →

**Цель.** Терминальный клиент `codelab`, который заменяет Python TUI: REPL со стримингом,
одобрения, slash-команды, профили подключения, headless-режим для скриптов и CI, драйвер
фикстур. Работает с Python-агентом и scripted-агентом сразу, с Dart-агентом — после этапа 4.

**Задачи.** Пути — в `apps/codelab_cli/`.

1. **6.1. Каркас:** `bin/codelab.dart`, `lib/src/cli_runner.dart` (разбор аргументов на
   `package:args`, `CommandRunner`), `lib/src/composition_root.dart` (сборка `ClientWorkspace`,
   резолверы stdio и WebSocket из `package:acp_transports/io.dart`, адаптеры `acp_client_io`).
2. **6.2. Профили:** `lib/src/profiles/profile_arg.dart` — разбор значения `--agent` (таблица
   ниже), команда `codelab profiles list|show|add|remove`.
3. **6.3. Рендер:** `lib/src/render/terminal_renderer.dart` (потоковый текст, мысли приглушённым
   цветом, строки инструментов без сырого JSON, план, уведомления), `lib/src/render/ansi.dart`
   (цвета; `NO_COLOR`, `--no-color` и не-TTY → без ANSI).
4. **6.4. Редактор строки и клавиши:** `lib/src/repl/line_editor.dart` (raw-режим `stdin`,
   история в `~/.codelab/cli_history`, многострочный ввод), `lib/src/input/key_bindings.dart`.
   Без TTY — построчный ввод без raw-режима.
5. **6.5. REPL:** `lib/src/repl/repl.dart` и `lib/src/repl/commands/` — по файлу на клиентскую
   команду (таблица ниже); слияние с командами агента через `CommandCatalog`.
6. **6.6. Одобрение:** `lib/src/repl/approval_prompt.dart` (UX ниже).
7. **6.7. Headless:** `lib/src/headless/headless_runner.dart` (промпт из `-p`, `-f` или stdin),
   `lib/src/headless/exit_codes.dart`, `lib/src/headless/approval_policy.dart`,
   `lib/src/headless/stream_json/` — `StreamJsonProjector` (чистая проекция ревизий kit),
   `StreamJsonRedactor`, `StreamJsonWriter` (единственный владелец stdout в `json` и
   `stream-json`) по §12.5.3; схемы — `apps/codelab_cli/schema/stream-json.v1.schema.json` и
   `json.v1.schema.json`.
8. **6.8. Драйвер фикстур:** `lib/src/scenario/test_scenario_command.dart` поверх загрузчика
   фикстур из `acp_testing` и `ClientWorkspace`.
9. **6.9. Сигналы:** SIGINT и SIGTERM (`ProcessSignal.sigint.watch()`, `sigterm`) — отмена хода,
   корректное закрытие транспорта и дочернего процесса агента.
10. **6.10. E2E:** `test/e2e/` — запуск собранного бинаря как процесса против scripted stdio-агента
    из `acp_testing` и против Python-агента (если установлен; иначе тест пропускается с
    сообщением). Имена тестов = id строк матрицы: `cli/repl-prompt-streaming`,
    `cli/repl-permission-allow-once`, `cli/repl-permission-reject`, `cli/slash-menu-merges-agent-commands`,
    `cli/client-commands-smoke`, `cli/model-picker-sets-config-option`, `cli/esc-cancels-turn`,
    `cli/prompt-queue-drains-after-turn`, `cli/headless-print-basic`, `cli/headless-exit-codes`,
    `cli/headless-permission-denied`, `cli/headless-bypass-flag`, `cli/resume-last-session`,
    `cli/connect-profiles-stdio-ws-embedded` (вариант `embedded` — на этапе 7),
    `cli/headless-stream-json-golden`, `cli/headless-stream-json-schema`,
    `cli/headless-stream-json-errors`, `cli/headless-stream-json-redaction`,
    `cli/headless-stream-json-flags`, `cli/headless-stream-json-flush`,
    `cli/headless-json-single-object` (§12.5.8). Интерактивные сценарии идут через псевдотерминал
    (обвязка PTY ниже) с вводом клавиш из файла. После MVP: `cli/bang-command`,
    `cli/theme-user-json`, `cli/update-rejects-bad-signature`, `cli/update-replaces-and-resumes`,
    `cli/tui-scroll-follow`, `cli/power-assertion-released-after-turn`, `cli/restart-reloads-session`,
    `cli/model-remembered-per-folder`, `cli/tui-copy-osc52`, `cli/headless-stream-thinking-stderr`,
    `cli/sessions-filter` (§12.6); `cli/login-openrouter-pkce` (agent-core-architecture §17.10.6);
    `cli/trajectory-export-atif` (agent-core-architecture §17.13.3); `cli/config-export-no-secrets`,
    `cli/config-import-providers-merge` (agent-core-architecture §17.14.4).

**Обвязка PTY для e2e.** `apps/codelab_cli/test/e2e/support/pty_process.dart` —
`PtyProcess.start(executable, args, {columns, rows, environment})`: `Process.start` системной
утилиты `script`, которая даёт дочернему процессу псевдотерминал; stdin обвязки — клавиши,
stdout — вывод терминала. Своего FFI-пакета PTY в репозитории нет, и для MVP он не добавляется
(новая зависимость — решение по `AGENTS.md` §4). У утилиты разный синтаксис, поэтому команда
собирается по ОС в одном месте — в этой обвязке:

| ОС | Вызов | Примечание |
|---|---|---|
| macOS (BSD `script`) | `script -q /dev/null sh -c 'stty cols 100 rows 30; exec "$0" "$@"' <codelab> <args…>` | команда идёт сразу после файла записи; код выхода — код дочернего процесса |
| Linux (util-linux `script`) | `script -q -e -f -c "stty cols 100 rows 30; exec <codelab> <args…>" /dev/null` | команда — одной строкой в `-c` (аргументы экранируются обвязкой); `-e` — вернуть код дочернего процесса, `-f` — сбрасывать вывод сразу |
| Windows | — | PTY-тесты не запускаются (пропуск с сообщением); ручная проверка перед релизом (см. «Риски») |

Обвязка при старте проверяет, что `script` есть в `PATH`, и разбирает вывод `script --version`
(есть только у util-linux) — так выбирается вариант; нет утилиты — тест пропускается с
сообщением, а не падает. Переводы строк PTY (`\r\n`) нормализуются перед сравнением. Тест самой
обвязки — `test/e2e/support/pty_process_test.dart`: `sh -c 'test -t 0 && test -t 1; exit 3'`
возвращает код `3` и `tput cols` печатает `100` на обеих ОС.

## Спецификация CLI

Команда — `codelab`. Без подкоманды запускает REPL.

```text
codelab [опции] [первое сообщение]        REPL (первое сообщение отправляется сразу)
codelab -p "<промпт>" [опции]             headless: один ход, вывод в stdout, код выхода
codelab sessions [--cwd <dir>] [--json]   список сессий агента для папки
codelab profiles list|show <id>|add <id> ...|remove <id>
codelab test-scenario <путь>... --agent <профиль> [опции]
codelab config get|set|unset|path|check ...   конфиг встроенного агента (§12.4.8)
codelab config migrate [<путь>] [--print] [--project|--local]   codelab.toml → config.yaml (agent-core §15.7; флаги слоя — этап 8, agent-core §17.5)
codelab config export-providers|import-providers ...   обмен провайдерами без секретов (agent-core §17.14.4)
codelab provider add|list|remove ...          провайдеры; add без флагов на TTY — мастер (§12.4.4)
codelab mcp add|list|remove ...               MCP-серверы в конфиге
codelab secret set|delete|list ...            хранилище секретов
codelab update [--check] [--channel stable|beta|pinned] [--version <x.y.z>] [--allow-downgrade] [--yes]   самообновление (после MVP, §12.6.4)
codelab login <provider> [--device] [--no-browser] [--timeout <duration>]   вход по подписке (после MVP, agent-core §17.10.6)
codelab logout <provider>                     удалить токен входа (после MVP, agent-core §17.10.6)
codelab trajectory export [<id>|--last] [флаги]   траектория сессии встроенного агента в JSON (ATIF, agent-core §17.13.3)
codelab --version | --help
```

Подкоманды `config`, `provider`, `mcp` и `secret` по этапам: `config get|path|check` и
`config migrate` — этап 8, задача 8.5 (чтение и проверка; план сборки встроенного агента в
`config check` — этап 7, задача 7.6); `secret set|delete|list` — этап 8, задача 8.9 (нужна MVP);
`config set|unset`, `provider add|list|remove`, `mcp add|list|remove` — этап 8, задача 8.10
(Should — не блокирует MVP); мастер `provider add` — этап 9 (задача 9.6, Should);
`config export-providers|import-providers` — после MVP (E-14). До своего этапа подкоманда не
регистрируется (`codelab <команда>` → код 64 `Unknown command`). Это общая реализация ядра
(agent-core-architecture §17.5.4, §17.5.5: флаги `--project`/`--local`, тексты, коды выхода
0/1/2); CLI вызывает её через `codelab_setup/io.dart` и добавляет только мастер и проверку
адреса к `provider add` (§12.4.4, §12.4.8). Они работают без запуска агента. Пока конфиг
получен из устаревшего `codelab.toml`, подкоманды записи выходят с кодом 1 и подсказкой
`Run "codelab config migrate" first: codelab.toml is read-only.`; `config migrate` — тот же
перевод, что при чтении, и запись `config.yaml` (agent-core-architecture §15.7).

Скрипт прогона Terminal-Bench (`tool/bench/`, H-06) вызывает обычный `codelab -f …
--output-format stream-json --approve allow-all` только внутри контейнера задачи
(agent-core-architecture §17.14.5); флагов для бенчмарка у CLI нет.

**`codelab trajectory export`** (после MVP, S-11, agent-core-architecture §17.13.3):

```text
codelab trajectory export [<sessionId>|--last] [--cwd <dir>] [--out <file>] [--leaf <recordId>]
    [--thinking include|omit] [--images omit|files] [--subagents omit|nest]
    [--redact standard|strict] [--pretty]
```

| Флаг | Значение | По умолчанию |
|---|---|---|
| `<sessionId>` | полный id или префикс ≥ 8 символов | — (без него и без `--last` → код 64 `Pass a session id or --last.`) |
| `--last` | последняя сессия папки `--cwd` | выключено |
| `--cwd <dir>` | папка для `--last` | текущая |
| `--out <file>` | файл вместо stdout | stdout |
| `--leaf <recordId>` | экспорт ветки до этой записи | активный лист |
| `--thinking` | рассуждения модели | `include` |
| `--images` | `omit` — только описание в `extra`; `files` — файлы `images/` рядом с `--out` и `ContentPart` в шаге (без `--out` → код 64; agent-core-architecture §17.13.3) | `omit` |
| `--subagents` | вложить траектории субагентов | `omit` |
| `--redact` | `standard` — слои `redact.*`; `strict` — плюс пути, картинки, рассуждения | `standard` |
| `--pretty` | отступы | выключено |

Коды выхода: `0` — успех; `1` — сессия не найдена, не единственна или является журналом
субагента; `2` — ошибка чтения или записи (текст ОС в stderr); `64` — неверные флаги. Подкоманда
работает без запуска агента, как `codelab config`; для внешнего агента (`--agent`) не
применяется.

Этап флага указан в начале столбца «Значение»; флаг без пометки — этап 6. Флаг более позднего
этапа до своего этапа не регистрируется (код 64 `Unknown flag`); «после MVP» — цель вне MVP.

| Флаг | Сокращение | Значение | По умолчанию |
|---|---|---|---|
| `--agent <профиль>` | `-a` | `embedded`; id профиля из `profiles.json`; `stdio:<команда> [аргументы]`; `ws://…` или `wss://…` | `embedded` (с этапа 7); до этапа 7 — профиль `default` из `profiles.json`; если файла или профиля `default` нет — код 64 и `No default agent profile. Pass --agent or run "codelab profiles add default stdio:<command>".` (агент не запускается, `embedded` до этапа 7 → код 64 `Embedded agent is not available in this build.`) |
| `--cwd <dir>` | `-C` | рабочая папка сессии | текущая папка |
| `--model <id>` | `-m` | значение опции конфигурации `model` после создания сессии; после MVP сильнее модели, запомненной для папки (U-27, §12.6.9), и не запоминается | из агента |
| `--mode <id>` | | значение опции конфигурации `mode` | из агента |
| `--resume <sessionId>` | `-r` | загрузить сессию (`session/load`) вместо новой; после MVP сессия, открытая на запись другим процессом (`sessionLocked`, agent-core-architecture §17.6.10), → сообщение `Session <id> is open for writing in <profile> (pid <pid>). Use --read-only to watch it or /fork to continue in a copy.` и код выхода `1` | — |
| `--read-only` | | после MVP: с `--resume` — открыть сессию только для чтения (`_meta.codelab.openMode: "readOnly"`); статус-строка получает сегмент `read-only` (agent-core-architecture §17.6.11) | выключено |
| `--continue` | `-c` | загрузить последнюю сессию этой папки (`session/list`) | — |
| `--session <name>` | | этап 6, Should — не блокирует MVP (S-14): открыть сессию с заголовком `<name>` в рабочей папке или создать новую с этим заголовком (S-14, agent-core-architecture §8.10.2); несколько совпадений — в headless код 1 со списком id, в REPL — выбор; вместе с `--resume`/`--continue` → код 64 | — |
| `--print <промпт>` | `-p` | headless-режим | — |
| `--prompt-file <файл>` | `-f` | headless: промпт из файла; `-` — из stdin | — |
| `--output-format text\|json\|stream-json` | | только headless: `text` — ответ как есть; `json` — один итоговый объект в конце; `stream-json` — NDJSON v1 (§12.5.3); в REPL → код 64 | `text` |
| `--include-thoughts` | | headless: события `thought_delta` в `stream-json` (§12.5.3) | выключено |
| `--stream-thinking` | | после MVP (H-08): headless `text`/`json` — мысли модели в stderr по мере прихода (приглушённо, если stderr — TTY); stdout не меняется; со `stream-json` не действует (одна строка предупреждения, мысли там — `--include-thoughts`); с `--no-stream-thinking` или в REPL → код 64 (§12.6.11) | `headless.stream_thinking` (`false`) |
| `--no-stream-thinking` | | после MVP (H-08): выключить вывод мыслей явно; сильнее `headless.stream_thinking` (§12.6.11) | — |
| `--include-acp` | | только с `--output-format stream-json`: строки `acp` с исходными кадрами после редакции (§12.5.3); иначе код 64 | выключено |
| `--input-format text\|stream-json` | | `text` — промпт из `-p`, `-f` или stdin; `stream-json` зарезервирован → код 64 (§12.5.2) | `text` |
| `--approve <политика>` | | headless: `reject` (отклонять всё), `read-only` (разрешать once только вызовы вида `read`, остальное отклонять), `allow-all` (разрешать once всё, кроме запросов с `_meta.codelab.critical: true`; печатает предупреждение в stderr) | `reject` |
| `--permission-mode <режим>` | | этап 7 (нужен встроенный агент; у `codelab-agent serve` тот же флаг — этап 4); `accept-edits` — после MVP (P-06). Режим встроенного агента: `plan`, `ask`, `standard`, `accept-edits`, `bypass`, `autopilot` (только с `-p`) (agent-core-architecture §7.7, §13.6); на внешнего агента не влияет | `standard` |
| `--timeout <длительность>` | | headless: предел на ход (`90s`, `10m`); по истечении — `session/cancel` | без предела |
| `--deadline <длительность\|время>` | | после MVP (C-15): дедлайн сессии; `90s`, `45m`, `1h30m`, ISO-8601 или `HH:MM`; CLI отправляет `/timer until <ISO>` до первого промпта; агент без `/timer` — предупреждение и `session/cancel` в срок (agent-core-architecture §17.12.5) | без срока |
| `--drain-timeout <длительность>` | | после MVP (H-05, этап 9+); headless: сколько ждать фоновую работу агента (субагенты, фоновые команды — agent-core-architecture §17.9) после ответа на `session/prompt`; `0` — не ждать (agent-core-architecture §17.3.9) | `60s` (`subagents.drain_timeout`) |
| `--max-wakes <n>` | | после MVP (H-05, этап 9+); headless: сколько раз разбудить агента для доставки отчётов фоновых субагентов (`_meta.codelab.wake`, через OpenSpec); `0` — не будить (agent-core-architecture §17.3.9) | `3` (`subagents.max_wakes`) |
| `--role <роль>=<provider/model>` | | после MVP (L-10): модель роли на прогон; `default`, `smol`, `slow`, `plan`, `subagent`, после MVP `vision` (T-18, agent-core-architecture §17.11.5); флаг можно повторять (agent-core-architecture §15.4, §15.6; алгоритм — §17.10.5) | из `llm.roles.*` |
| `--tools <tool>=on\|off,…` | | этап 8, Should (T-26); встроенный агент: выключить или вернуть инструменты (agent-core-architecture §6.3.8, T-26); можно повторять; неизвестное имя → код 64; на внешнего агента не влияет; имена — список §6.3.8, после MVP с `memory`, `inspect_image`, `checkpoint`, `ask`, `session_history`, `discover_tools` (agent-core-architecture §17.11) и `context_expand` (§17.13.4) | из конфига (`tools.disabled`) |
| `--system-prompt <text>` | | этап 8, Should (E-08); встроенный агент: заменить базовый системный промпт (agent-core-architecture §11.6.1, E-08); вместе с `--system-prompt-file` → код 64 | из конфига |
| `--system-prompt-file <файл>` | | этап 8, Should (E-08); то же из файла (UTF-8, ≤ 64 КиБ) | из конфига |
| `--append-system-prompt <text>` | | этап 8, Should (E-08); дополнение после базового промпта (agent-core-architecture §11.6.1) | из конфига |
| `--no-color` | | без ANSI | цвет, если TTY и нет `NO_COLOR` |
| `--ui line\|tui` | | построчный REPL или полноэкранный TUI (U-12, после MVP, §12.2.1, §12.2.7); `tui` требует TTY на stdin и stdout | `line` (`ui.mode` в `cli.yaml`) |
| `--attach <файл>` | | вложение к первому промпту (REPL) или к промпту `-p`; флаг можно повторять (U-14, после MVP, §12.2.8) | — |
| `--trace-file <файл>` | | protocol trace (JSON-RPC кадры с редакцией секретов) в файл | выключено |
| `--log-file <файл>` | | этап 7, Should (E-16; встроенного агента в CLI до этапа 7 нет, у `codelab-agent serve` флаг — этап 4); лог встроенного агента (JSON Lines, с редакцией секретов) дописывается в файл; переменная `CODELAB_LOG_FILE`; флаг сильнее переменной, переменная сильнее `logging.file` (agent-core-architecture §12.3.1) | `logging.file` (`~/.codelab/logs/agent.log`) |
| `--verbose` | `-v` | диагностика соединения в stderr | выключено |
| `--debug-llm-snapshot[=headers\|body]` | | после MVP (L-27): встроенный агент пишет снимки зависших запросов к LLM (`logging.llm_snapshot`, agent-core-architecture §17.10.10) | выключено |
| `--config <файл>` | | этап 7 (загрузчик 8.5); конфигурация встроенного агента, `.yaml` или `.yml` | `~/.codelab/config.yaml` + `.codelab/config.yaml` |

Headless (`-p`, `-f`) передаёт `_meta.codelab.sealOnClose: true` в `session/new`/`session/load` и объявляет `clientCapabilities._meta.codelab.jobBoard: true`; после итоговой строки закрывает соединение — сессия запечатывается (S-15, agent-core-architecture §8.5.1).

После MVP headless `text` и `json` печатают в stderr признак жизни `… thinking <N>s` каждые
`headless.liveness_interval` (10 с) тишины, пока модель думает (H-08, §12.6.11); stdout и коды выхода от
этого не зависят.

Значение `--agent`:

| Форма | Пример | Профиль |
|---|---|---|
| `embedded` | `codelab -a embedded` | `EmbeddedProfile(hostProfile: 'embedded-cli')` |
| id профиля | `codelab -a python` | из `~/.codelab/profiles.json` |
| `stdio:` | `codelab -a 'stdio:codelab-agent serve --stdio'` | `StdioProfile`; разбор как в shell (кавычки, экранирование) |
| URL | `codelab -a ws://127.0.0.1:8765` | `WebSocketProfile`; токен — из `CODELAB_AGENT_TOKEN` |

Слово «профиль» означает три разных понятия. **Профиль подключения** — значение `--agent <профиль>`
и команды `/profile`, хранится в `~/.codelab/profiles.json`: как CLI запускает агента или
подключается к нему. **Профиль хоста** — набор capability встроенного агента (`embedded-cli`,
`agent-serve`; `--profile`/`CODELAB_PROFILE`, agent-core-architecture §10.4, §15.6).
**Промпт-профиль** — определение агента с телом промпта, например `architect`, выбирается опцией
сессии `agent` (agent-core-architecture §17.12.2, §13.6).

**Команды REPL.** Клиентские команды имеют приоритет; агентская команда с тем же именем доступна
как `/agent:<имя>`. Tab дополняет команду (нечёткий поиск по подпоследовательности).

| Команда | Действие | ACP |
|---|---|---|
| `/help` | список команд клиента и агента | — |
| `/exit`, `/quit` | выход | закрытие транспорта |
| `/new` | новая сессия в той же папке | `session/new` |
| `/sessions [--all] [--since today\|week\|<дата>] [--until <дата>] [--more] [текст]` | список сессий папки с номерами; превью и заголовок — `SessionSummary.title` (`derived` агент строит по словам пользователя, agent-core-architecture §8.10, шаг 1; своих правил по `origin` клиент не вводит, SES-14); после MVP с текстом или датой — фильтр kit по заголовку и дате, с расширением — и по тексту сообщений; `--all` — все папки (D-17, §12.6.12) | `session/list`; текст — `_codelab/session/search` |
| `/resume <n или id>` | загрузить сессию | `session/load` |
| `/mode [id]` | без аргумента — список режимов; с аргументом — сменить | `session/set_config_option` (`mode`) |
| `/model [id]` | то же для модели; форма `/model --role …` (после MVP) передаётся агентской команде `model` (как `/agent:model --role …`), см. agent-core-architecture §17.10.5; после MVP выбор запоминается для папки и профиля (U-27, §12.6.9); `/model --forget` — забыть выбор папки | `session/set_config_option` (`model`); `--role` — `session/prompt` |
| `/config [id] [значение]` | любые опции конфигурации; `/config reload` и `/config check` передаются агентской команде `config` (как `/agent:config reload`), если агент её объявил, иначе `The agent does not support /config reload.` (§12.4.8, agent-core-architecture §17.5.6) | `session/set_config_option`; `reload`/`check` — `session/prompt` |
| `/provider add\|list\|remove` | мастер и список провайдеров встроенного или локального агента (после MVP, §12.4.4); для удалённого агента — сообщение read-only | — |
| `/cancel` | отменить ход | `session/cancel` |
| `/queue`, `/queue drop <n>`, `/queue clear` | очередь промптов | — |
| `/queue steer <n>` | после MVP: направить n-й элемент очереди в идущий ход, не отменяя его (C-03, §12.2.9, agent-core-architecture §17.7.6); без хода или без capability — как отправка из очереди | `_codelab/session/steer` |
| `/steer <текст>` | после MVP: направить сообщение в идущий ход (C-03); без хода или без `agentCapabilities._meta.codelab.steering` — обычная отправка или очередь | `_codelab/session/steer` |
| `/rename <title>` | после MVP: переименовать сессию (S-06) | `_codelab/session/rename` или агентская команда `rename` |
| `/branches` | после MVP: ветки сессии и сообщения активной ветки (S-07) | `_codelab/session/branches` или агентская команда |
| `/branch <n или id>` | после MVP: продолжить с другой ветки или записи (S-07) | `_codelab/session/leaf` или агентская команда |
| `/rewind [<n или id>]` | после MVP: без аргумента — список сообщений; с аргументом — `dryRun`, вопрос `Files will not be restored: <пути>. Rewind? [y/N]`, перемотка, исходный текст в поле ввода (S-08) | `_codelab/session/rewind` или агентская команда |
| `/fork [<n или id>]` | после MVP: копия сессии; новая открывается сразу (S-07) | `_codelab/session/fork`, затем `session/load` |
| `/label <текст> \| clear` | после MVP: метка текущей записи | `_codelab/session/label` или агентская команда |
| `/tasks [cancel <id> \| output <id>]` | фоновая работа агента: субагенты и фоновые команды (agent-core-architecture §17.3.8, §17.9.11); команда агента | `session/prompt` |
| `/profile [id]` | показать профиль или переподключиться к другому | новое соединение |
| `/reconnect` | переподключиться и перезагрузить сессию; процесс агента не завершается намеренно; полный перезапуск — `/restart` | `initialize`, `session/load` |
| `/plan` | показать текущий план | — |
| `/inspect [toolCallId]` | подробности вызова инструмента: аргументы, вывод, разрешение | — |
| `/trace on\|off` | protocol trace в файл сессии | — |
| `/clear` | очистить экран (сессия сохраняется) | — |
| `/thoughts dim\|collapsed\|hidden` | как показывать мысли модели (U-08, §12.2.3) | — |
| `/paste-image` | приложить картинку из буфера обмена к следующему промпту (U-14, после MVP, §12.2.8) | — |
| `/terminal-setup` | обнаруженные возможности терминала и подсказка, как сделать Shift+Enter различимым (U-23, §12.2.9) | — |
| `/help keys` | таблица клавиш из реестра `key_bindings.dart` (§12.2.9) | — |
| `!<команда>` | после MVP: выполнить команду в локальном shell в `cwd` сессии, вне агента; вывод прикладывается к следующему промпту (U-16, §12.6.2) | — |
| `/shell`, `/shell drop` | после MVP: приложенные выводы `!`; удалить их | — |
| `/theme [имя]` | после MVP: список тем или смена темы до конца процесса (U-18, §12.6.3) | — |
| `/update` | после MVP: самообновление и перезапуск в той же сессии (U-20, §12.6.4) | — |
| `/mouse [on\|off]` | после MVP, TUI: захват мыши (U-22, §12.6.5) | — |
| `/power [off\|turn\|always]` | после MVP: запрет сна системы (U-25, §12.6.6) | — |
| `/restart` | после MVP: завершить или пересоздать агента и загрузить сессию; идущий ход сначала отменяется (U-26, §12.6.7) | `session/cancel`, `initialize`, `session/load` |
| `/copy`, `/copy code [n]` | после MVP: копировать последний ответ или его n-й блок кода в буфер обмена (системная утилита или OSC 52, U-28, §12.6.10) | — |

Команды сессии `/rename`, `/branches`, `/branch`, `/rewind`, `/fork`, `/label` — клиентские
(видны в slash-меню): если агент объявил `agentCapabilities._meta.codelab.sessionTree`, они
вызывают методы `_codelab/session/*`, иначе передаются агентской команде того же имени (как
`/agent:<имя>`), иначе печатают `The agent does not support /<name>.` (agent-core-architecture
§17.6.11). Без расширения после смены ветки CLI перезагружает сессию (`/reconnect`).

Вопросы `ask` (после MVP, agent-core-architecture §17.11.7): REPL объявляет `_meta.codelab.ask` и
показывает вопросы по одному — номера вариантов (через запятую при множественном выборе), `o` —
свой ответ, Esc — отказ `declined` (действие `decline_ask`, приоритетнее `cancel_turn`, §12.2.9); headless `-p` возможность не объявляет.

**Клавиши.**

| Клавиша | Когда | Действие |
|---|---|---|
| Enter | ввод | отправить; во время хода — в очередь (сообщение «в очереди: n») |
| Ctrl+Enter | идёт ход | после MVP: направить сообщение в ход (steering, C-03, §12.2.9); различим при CSI u, kitty или modifyOtherKeys; без хода или без capability — как Enter |
| Shift+Enter, Alt+Enter или Ctrl+J | ввод | новая строка; Shift+Enter — где терминал различает его (kitty keyboard protocol, xterm modifyOtherKeys; U-23, §12.2.9) |
| `\` + Enter | ввод | запасной путь в любом терминале: `\` в конце строки удаляется, вставляется перевод строки |
| вставка (bracketed paste) | ввод | вставленный текст с переводами строк попадает в ввод целиком и не отправляется (U-23) |
| Esc | идёт ход | отменить ход (`session/cancel`) |
| Esc | ввод, нет хода | очистить строку |
| Ctrl+C | идёт ход | отменить ход |
| Ctrl+C | ввод | очистить строку; повтор в течение 1 с — выход (U-07) |
| Ctrl+D | пустая строка | выход |
| ↑ / ↓ | ввод | история |
| Tab | строка начинается с `/` | дополнение команды |
| Ctrl+L | любое | очистить экран |
| Ctrl+V | ввод, TUI | приложить картинку из буфера обмена (после MVP, §12.2.8; в REPL — `/paste-image`) |
| Ctrl+O | транскрипт, TUI | развернуть или свернуть мысли (после MVP, §12.2.3) |
| колесо мыши | транскрипт, TUI | после MVP: прокрутка; вверх останавливает следование (U-22, §12.6.5) |
| Esc, Ctrl+C | идёт команда `!` | отменить команду, не ход (действие `cancel_shell`, приоритетнее `cancel_turn`; §12.2.9, §12.6.2) |
| Esc | вопрос `ask` | после MVP: ответить `declined`, не отменяя ход (действие `decline_ask`, приоритетнее `cancel_turn`; agent-core-architecture §17.11.7) |

Все клавиши — одна таблица действий `apps/codelab_cli/lib/src/input/key_bindings.dart`; из неё
строятся обработка, подсказки и `/help keys`. Переопределение — секция `keys` в
`~/.codelab/cli.yaml` (§12.2.9).

**Конфигурация клиента.** Настройки отображения и клавиш CLI живут в отдельном файле
`~/.codelab/cli.yaml` (и `.codelab/cli.yaml` проекта поверх него), который читает только
codelab_cli, а не в `config.yaml` агента (§12.2.10).

**Одобрение.** Запрос показывается блоком; клавиша выбирает вариант, который предложил агент
(вариантов, которых агент не предложил, в подсказке нет):

```text
╭─ Разрешение: exec npm test                                   риск: средний
│  команда: npm test
│  папка:   /Users/me/proj
╰─ [y] разрешить один раз  [a] разрешить всегда  [n] отклонить  [N] отклонить всегда  [?] подробнее
```

| Клавиша | Вид варианта ACP | Примечание |
|---|---|---|
| `y` | `allow_once` | |
| `a` | `allow_always` | агент запоминает по инструменту и шаблону аргументов |
| `n` | `reject_once` | ход продолжается: модель получает отказ текстом |
| `N` | `reject_always` | |
| `?` | — | показать `rawInput` целиком и diff правки, затем снова спросить |
| Esc, Ctrl+C | — | отменить ход; ожидающий запрос получает исход `cancelled` |

Enter без выбора ничего не делает: варианта «по умолчанию» нет. Пока ждёт одобрение, ввод в
композер недоступен; новые запросы одобрения ставятся в очередь и показываются по одному.

**Headless.** `codelab -p` создаёт (или загружает по `-r`/`-c`) сессию, отправляет один промпт,
печатает ответ и завершается. Запросы одобрения обрабатываются политикой `--approve` без вопросов;
каждое решение печатается в stderr; в `stream-json` дополнительно — событием `permission` (§12.5).

Коды выхода вычисляются из ответа `session/prompt` и ошибок, а не из транскрипта:

| Код | Когда |
|---|---|
| `0` | `stopReason: end_turn` и ответ не пустой (заметка о пустом ответе — тоже ответ, agent-core-architecture §5.4.1) |
| `1` | ошибка хода (ошибка JSON-RPC на `session/prompt`, ошибка провайдера), `end_turn` без единого `agent_message_chunk`, `max_tokens`, `max_turn_requests`, `refusal`, не удалось подключиться к агенту, агент завершился; после MVP — ответ с `_meta.codelab.held` (agent-core-architecture §17.12.4) |
| `64` | ошибка использования: неизвестный флаг, нет промпта, неверное значение `--agent`; битый конфиг (agent-core-architecture §13.10) |
| `130` | отмена: SIGINT или `--timeout` (`stopReason: cancelled`), или срок `--deadline` у агента без `/timer` |
| `143` | SIGTERM: ход отменён, транспорт закрыт |

Если после ответа истёк `--drain-timeout` и оставшаяся фоновая работа отменена, код `0` заменяется
на `1`; остальные коды не меняются (agent-core-architecture §17.3.9, шаг 9).

**Формат `stream-json`.** Собственная схема CodeLab v1 (§12.5): NDJSON, одна строка на событие,
закрытый набор `type` (`init`, `turn_start`, `user_message`, `text_delta`, `text`,
`thought_delta`, `tool_call`, `tool_update`, `tool_result`, `permission`, `plan`, `notice`,
`subagent`, `turn_end`, `acp`, `result`), версия в `init`. Это проекция модели отображения
`acp_client_kit`, а не кадров ACP; совместимость с другими CLI не обещается. Первая строка —
`init`, последняя — всегда `result` (в том числе при ошибке), `usage` до расширения равно `null`;
секреты редактируются тем же `SecretRedactor`, что и логи клиента. Схема —
`apps/codelab_cli/schema/stream-json.v1.schema.json`; контракт, типы Dart, алгоритм проекции,
примеры и тесты — §12.5.

**Драйвер фикстур.**

```text
codelab test-scenario <файл-или-папка>... --agent <профиль>
    [--filter <glob по id>] [--timeout 30s] [--junit <out.xml>] [--update-golden]
```

Алгоритм для каждой фикстуры:

1. Загрузить фикстуру (формат — документ ядра §14); фикстура без роли «проверка агента»
   пропускается с пометкой `skip`.
2. Запустить агента по профилю. Для `embedded` сценарий LLM из фикстуры передаётся встроенному
   агенту; для `stdio:codelab-agent …` — флагом `--llm-script`; для стороннего агента сценарий не
   передаётся, и фикстуры с секцией `llm` пропускаются.
3. Проиграть кадры клиента по порядку; после каждого ждать ожидаемые кадры агента до таймаута.
4. Нормализовать обе стороны (id, время, пути) и сравнить; при первом расхождении — `FAIL` с
   диффом ожидаемого и фактического кадра.
5. С `--update-golden` — записать фактические кадры агента в фикстуру (только для своего агента).

Вывод: строка `PASS|FAIL|SKIP <id> (<время>)` на фикстуру и итог. Код выхода: `0` — все прошли,
`1` — есть `FAIL`, `64` — ошибка использования.

**OpenSpec change.** `add-codelab-cli` — scope: команды и флаги, REPL-команды и клавиши, UX
одобрения, коды выхода, формат stream-json v1 по §12.5 (схема в apps/codelab_cli/schema/), драйвер фикстур. Отдельно, если
понадобится расширение ACP для статус-строки (usage) — свой change `add-usage-extension` после
этапа 9 (§12.1.5).
`tasks.md` — пары "тест → реализация" со ссылкой на критерий (§9.0, правило 3); PTY-e2e
`cli/*` — приёмочные ворота этапа (исключение (б)), модульные тесты REPL, рендера и headless
пишутся первыми.

**Что прочитать.** Этот раздел; §9.10 (API kit); документ ядра §13 (правило «коды выхода — из
событий»), §14; матрица целей, блоки «Headless» и «CLI/TUI»; `docs/architecture/permissions.md`.

**Definition of Done.**

* `melos run build:cli` даёт `build/bin/codelab`.
* `melos run test:e2e:cli` — все `cli/*` из задачи 6.10 зелёные против scripted stdio-агента на
  macOS и Linux; `test/e2e/support/pty_process_test.dart` зелёный на обеих ОС.
* `codelab -p hi` с пустым `CODELAB_HOME` (нет `profiles.json`) — код 64 и подсказка
  `codelab profiles add default …`; агент не запускается.
* `cli/headless-exit-codes`: ошибка провайдера → `1`, `session/cancel` по `--timeout` → `130`,
  неизвестный флаг → `64`, SIGTERM → `143`.
* `cli/headless-stream-json-golden`: вывод совпадает с golden-файлом `test/e2e/golden/stream_json_basic.ndjson`.
* `cli/headless-stream-json-schema`: каждая строка всех golden-файлов и живых прогонов `cli/headless-*` проходит `apps/codelab_cli/schema/stream-json.v1.schema.json`; `cli/headless-json-single-object`: `--output-format json` — ровно одна строка, проходит `json.v1.schema.json`; `cli/headless-stream-json-errors`, `-redaction`, `-flags`, `-flush` — зелёные (§12.5.8).
* `test/scenario/test_scenario_command_test.dart`: против `FixtureReplayAgent` из `acp_testing`
  (агент, который отвечает ожидаемыми кадрами самой фикстуры) весь корпус даёт `PASS`, а фикстура
  с испорченным ожидаемым кадром — `FAIL` с диффом и код выхода `1`. Прогон против настоящего
  агента — с этапа 7 (`--agent embedded`) и этапа 4 (`--agent 'stdio:codelab-agent serve --stdio'`).
* `melos run guard`: CLI не импортирует Flutter и агентские пакеты.
* Ручная проверка: сессия с Python-агентом (`codelab -a 'stdio:codelab serve --stdio'`) —
  промпт, одобрение, `/mode`, `/sessions`, `/resume`.

**Зависимости.** Этап 5. Для встроенного режима — этап 7; для `--llm-script` — этап 4.

**Риски.** Различия терминалов (Windows Console, tmux) ломают raw-режим — построчный режим как
запасной, PTY-тесты на macOS и Linux, ручная проверка на Windows перед релизом. Команда `codelab`
сейчас занята Python-агентом — до этапа 9 бинарь CLI ставится под именем `codelab` только в
`build/bin`, переименование установленной команды — на этапе 9 (§11, допущение 5).

---

← [9.10. Этап 5 — Общий клиентский слой](09-10-stage-5-client-kit.md) · [Оглавление](../dart-agent-and-clients.md) · [9.12. Этап 7 — Встроенный режим в обоих клиентах](09-12-stage-7-embedded.md) →
