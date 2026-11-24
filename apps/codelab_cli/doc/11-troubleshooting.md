# Частые проблемы разработчика

Глава собирает случаи, с которыми сталкивается тот, кто меняет `codelab_cli` или запускает его тесты. Каждый случай записан одинаково: симптом, причина, что сделать. Тексты сообщений и коды выхода взяты из кода приложения и проверены запуском на этой ветке, если не сказано иное. Проблемы пользователя (настройка провайдера, права файлов, переменные окружения) — в [руководстве пользователя](user/12-troubleshooting.md) и [эксплуатации](operations.md). Оглавление руководства — [README](README.md).

Случаи по теме:

- сборка и запуск: [не собирается из-за `*.freezed.dart`](#не-собирается-из-за-freezeddart), [`--ui tui needs a terminal`](#--ui-tui-needs-a-terminal-on-stdin-and-stdout), [интерактивный режим не видит терминал](#интерактивный-режим-не-видит-терминал);
- запуск без провайдера: [`no model is configured`](#no-model-is-configured), [`request failed after 4 attempts`](#request-failed-after-4-attempts), [`cannot start the agent`](#cannot-start-the-agent);
- аргументы: [`Unknown agent profile`](#unknown-agent-profile), [новая подкоманда выполняет `profiles`](#новая-подкоманда-выполняет-profiles), [новый флаг принимает `config`](#новый-флаг-принимает-config), [новая команда не видна в `/help`](#новая-команда-не-видна-в-help);
- тесты: [`CODELAB_E2E_LLM_SCRIPT is not set`](#codelab_e2e_llm_script-is-not-set), [PTY-тесты пропущены](#pty-тесты-пропущены), [`test-scenario` ничего не сыграл](#test-scenario-ничего-не-сыграл);
- выход и терминал: [терминал остался в raw-режиме](#терминал-остался-в-raw-режиме), [выход ждёт 10 секунд](#выход-ждёт-10-секунд), [в `--verbose` есть `[error]` при выходе](#в---verbose-есть-error-при-выходе);
- ввод: [Ctrl+J в TUI](#ctrlj-в-tui), [второй `listen` на stdin](#второй-listen-на-stdin);
- границы: [сторож упал на импорте](#сторож-упал-на-импорте).

## Не собирается из-за `*.freezed.dart`

**Симптом.** `fvm dart run apps/codelab_cli/bin/codelab.dart`, `melos run build:cli` или тесты падают с `Error when reading '….freezed.dart'`.

**Причина.** Сгенерированный код не лежит в git; пакеты клиентского слоя, от которых зависит CLI, его требуют.

**Что сделать.** Выполнить шаг генерации из [запуска из исходников](../../../docs/user/run-from-source.md#1-подготовка) (в [главе 00](00-getting-started.md#подготовка-репозитория) — конспект).

## `--ui tui needs a terminal on stdin and stdout`

**Симптом.** `codelab --ui tui` завершается кодом `64` с текстом `codelab: --ui tui needs a terminal on stdin and stdout`, stdout пуст.

**Причина.** Полноэкранному режиму нужны терминалы на stdin и stdout одновременно (`io.stdinIsTerminal`, `io.stdoutIsTerminal` в `_run`). Запуск из pipe, из CI, из инструмента с перехваченным выводом или с перенаправленным stdin не подходит.

**Что сделать.** Запускать в настоящем терминале или под `tmux` ([глава 00](00-getting-started.md#интерактивные-режимы-под-терминалом)). Для проверки без терминала используйте `-p` или тесты ядра экрана.

## Интерактивный режим не видит терминал

**Симптом.** REPL не включает raw-режим: клавиши приходят построчно, строка ввода не рисуется, вывод без цвета.

**Причина.** `Terminal.hasTerminal` требует и stdin, и stdout терминалами (`IoTerminal.hasTerminal`). Вывод в файл или pipe — поверхность `raw` (`selectOutputSurface`); stdin из pipe — построчный ввод без raw-режима.

**Что сделать.** Для проверки интерактива запускать под `tmux` или `script` с `stty rows 40 cols 120`. В тестах использовать `FakeTerminal` (задаёт `hasTerminal`) и `FakeCliIo(stdinIsTerminal:, stdoutIsTerminal:)`.

## `no model is configured`

**Симптом.** Запуск встроенного агента без настроенной модели завершается кодом `64`:

```text
codelab: defaults: agent.default_model: no model is configured; add a provider with at least one model
Configure the embedded agent in ~/.codelab/config.yaml; check it with: codelab config check
```

**Причина.** У встроенного агента нет провайдера. В интерактивных режимах на терминале вместо ошибки открывается мастер первого запуска ([глава 07](07-config-and-setup.md#первый-запуск)); в `-p`, в pipe и для внешних агентов готовность не вычисляется (SETUP-7).

**Что сделать.** Добавить провайдера. Для опытов без сети — на loopback-адрес:

```bash
codelab provider add local --kind openai-compatible --base-url http://127.0.0.1:9/v1 --model demo-model --context-window 8192 --default
```

Или запускать тестовую точку входа со сценарием модели ([глава 00](00-getting-started.md#тестовая-точка-входа-со-сценарием-модели)): ей настоящая модель не нужна, но конфигурация провайдера всё равно нужна, иначе откроется мастер.

## `request failed after 4 attempts`

**Симптом.** Ход заканчивается кодом `1` и строкой `codelab: request failed after 4 attempts in 5.6 s: attempt 1 network (connection failed: _ClientSocketException); … (network)`.

**Причина.** Провайдер недоступен: порт не слушают или адрес неверен. Встроенный агент повторяет запрос четыре раза и сообщает об ошибке.

**Что сделать.** Для разработки это ожидаемый путь ошибки. Для настоящей проверки провайдера — `codelab config check` и `--verbose`; для проверки хода без сети — сценарий модели.

## `cannot start the agent`

**Симптом.** `codelab: cannot start the agent "<команда>": Failed to connect ACP transport.` или `… with N arguments`, код `1`.

**Причина.** Команда из профиля `stdio:…` не запустилась или сразу завершилась. Значения аргументов CLI не печатает нигде: ни в ошибках, ни в `--verbose`, ни в `profiles show`; печатаются команда и число аргументов ([глава 08](08-profiles-and-home.md#что-печатается-о-профиле)).

**Что сделать.** Запустить ту же команду вручную. Для проверки значений аргументов открыть `$CODELAB_HOME/profiles.json`: значения видны только там. Если сообщение называет отказ по токену (`the agent rejected the token (HTTP 401).`), проверить `CODELAB_AGENT_TOKEN` или секрет профиля.

## `Unknown agent profile`

**Симптом.** `codelab: Unknown agent profile. Run "codelab profiles list".`, код `64`.

**Причина.** Значение `-a` не `embedded`, не `default`, не `stdio:…` и не `ws://…`, а id, которого нет в `profiles.json`. Текст не цитирует значение: без префикса `stdio:` оно могло быть командной строкой с токеном.

**Что сделать.** `codelab profiles list`; если нужна команда — `-a "stdio:<команда> <аргументы>"` или `codelab profiles add <id> stdio:…`. Id `embedded` и `default` зарезервированы, их нельзя сохранить профилем.

## Новая подкоманда выполняет `profiles`

**Симптом.** Новая подкоманда распознана, но вместо неё работает `profiles` (ошибка использования `profiles` или список профилей).

**Причина.** В `parseCliArgs` любая зарегистрированная подкоманда без своей ветки попадает в последний `if (results.command case final command?)` и превращается в `CliCommand.profiles`.

**Что сделать.** Добавить ветку для подкоманды до этого общего случая и значение `CliCommand` ([глава 10](10-extending.md#подкоманда)).

## Новый флаг принимает `config`

**Симптом.** `codelab config check --новый-флаг` не отвергается, а флаг молча игнорируется.

**Причина.** Флаг не добавлен в `_connectionFlags`: подкоманды записи отвергают только перечисленные там флаги.

**Что сделать.** Добавить имя в `_connectionFlags` и тест `--<флаг> does not apply to config check` ([глава 10](10-extending.md#флаг-или-режим-запуска)).

## Новая команда не видна в `/help`

**Симптом.** Тест `/where is listed by /help` остаётся красным, `/where` отвечает `Unknown command /where`.

**Причина.** Класс команды написан, но не добавлен в `mvpReplCommands` (`lib/src/repl/commands/commands.dart`): `/help`, маршрутизатор и Tab читают только список.

**Что сделать.** Добавить импорт и строку в список ([туториал](tutorial-new-command.md#шаг-4-регистрация)).

## `CODELAB_E2E_LLM_SCRIPT is not set`

**Симптом.** Процессные тесты с `CODELAB_E2E_AGENT=embedded` падают: `exit 2`, в stderr `embedded_cli_main: CODELAB_E2E_LLM_SCRIPT is not set`.

**Причина.** В варианте `embedded` CLI запускается из тестовой точки входа, которой нужен сценарий модели. Тесты с тегом `scripted-only` его не задают: они рассчитаны на scripted-агента.

**Что сделать.** Исключить их, как это делают скрипты Melos:

```bash
CODELAB_E2E_AGENT=embedded fvm dart test test/e2e/headless_print_basic_test.dart --exclude-tags scripted-only
```

Или запускать скрипт `test:e2e:cli:embedded` ([глава 09](09-testing.md#матрица-e2e-и-теги)).

## PTY-тесты пропущены

**Симптом.** Тесты `repl_turn`, `repl_interaction`, `tui_smoke`, `tui_setup`, `provider_setup`, `status_line_usage`, `recent_projects` пропущены с сообщением `PTY tests do not run on Windows (§9.11)` или `the "script" utility is not in PATH`.

**Причина.** Обвязка `PtyProcess` использует системную утилиту `script` (BSD на macOS, util-linux на Linux). В Windows и без утилиты тест пропускается, а не падает.

**Что сделать.** Запускать на macOS или Linux с установленным `script`. Логику без процесса проверяют модульные тесты (`FakeTerminal`, ядро экрана).

## `test-scenario` ничего не сыграл

**Симптом.** `codelab test-scenario …` печатает `0 passed, 0 failed, 0 skipped` или только `SKIP`, затем в stderr `codelab: no fixtures were played`, код `1`.

**Причина.** Фильтр `--filter` ничего не нашёл, либо все фикстуры пропущены: агент не принимает их входы (`setup.config`, `setup.mcp`, …) или это сторонний агент и фикстура содержит сценарий модели ([глава 06](06-test-scenario.md#какие-фикстуры-пропускаются)).

**Что сделать.** Смотреть причину под каждым `SKIP`, проверить glob (`*` — любые символы, `?` — один) и профиль `--agent`.

## Терминал остался в raw-режиме

**Симптом.** После аварийного завершения `codelab` в терминале нет эха, Enter не переводит строку, на экране остаётся альтернативный буфер.

**Причина.** Процесс убит сигналом, который нельзя перехватить (`SIGKILL`), или завершился до `finally`. `IoTerminal.restore()` и повторное выключение режимов `TuiRunner` (`_restoreSequences`) в `finally` срабатывают при любом перехваченном выходе, но не при `SIGKILL`.

**Что сделать.** В терминале выполнить `reset` или `stty sane`. Если режим остаётся после обычного выхода или `Ctrl+C` — это дефект: проверьте, что новый код выхода не обходит `finally` в `_runRepl` и `_runTui`.

## Выход ждёт 10 секунд

**Симптом.** После `/exit` или Ctrl+D процесс завершается не сразу, затем печатает `codelab: the embedded agent did not stop in 10 s`.

**Причина.** `CliRuntime.dispose` ждёт остановки встроенного агента (`dispose`: отмена хода, закрытие MCP, запись журнала) не дольше 10 секунд, затем выходит.

**Что сделать.** Смотреть `--verbose`: событие `embedded.close_timeout` и последние записи агента. Если вы изменили порядок закрытия, проверьте, что `dispose` агента по-прежнему не бросает и не ждёт клиента.

## В `--verbose` есть `[error]` при выходе

**Симптом.** После нормального хода с `-v` в stderr две строки: `[error] In-process client transport peer closed the connection. …` и `[warning] connection_state_changed … from=ClientConnectionReady to=ClientConnectionFailed`. Код выхода `0`.

**Причина.** При выходе клиентский слой закрывает пару in-process транспортов, и это записывается в журнал уровнем `error`. Это не сбой запуска.

**Что сделать.** Ничего: код выхода и stdout не затронуты. Не ищите в этих строках причину проблемы, если ответ и код выхода верны.

## Ctrl+J в TUI

**Симптом.** Ctrl+J в TUI отправляет промпт, а не вставляет новую строку.

**Причина.** `dart_tui` присылает Ctrl+J как Enter (разведка 6.11), поэтому в таблице TUI его нет.

**Что сделать.** Новая строка в TUI — Shift+Enter или Alt+Enter; запасной путь любого терминала — `\` в конце строки перед Enter.

## Второй `listen` на stdin

**Симптом.** При добавлении нового чтения ввода `Bad state: Stream has already been listened to` или потеря нажатий между мастером и REPL.

**Причина.** `io.stdin` — поток с одной подпиской, а отмена подписки закрывает fd 0. Владелец ввода на процесс — `SharedStdin` (broadcast-поток поверх одной подписки на паузе, пока слушателей нет).

**Что сделать.** Брать `SharedStdin().stream` из `run.dart` и отдавать его через `IoTerminal(input:)` или `TuiRunner(input:)`; новый компонент не должен слушать `io.stdin` сам ([глава 03](03-repl.md#общий-stdin)).

## Сторож упал на импорте

**Симптом.** `fvm dart run melos run guard` падает с названием файла и запрещённым импортом.

**Причина.** Нарушено правило границ приложения (`packages/dart/codelab_architecture_tests/test/support/rules.dart`):

| Импорт | Где разрешён |
|---|---|
| `package:codelab_setup/io.dart` | только `lib/src/run.dart` (правило на весь `lib/`) |
| `package:codelab_embedded/io.dart` | только `lib/src/composition_root.dart` (весь `lib/`) |
| `package:codelab_embedded/testing.dart` | только `lib/src/scenario/` (весь `lib/`) |
| `package:codelab_acp_testing/` | только `lib/src/scenario/` (правило на `lib/src`) |
| `package:dart_tui/` | только `lib/src/tui/` (правило на `lib/src`) |
| `dart:io`, `package:dart_tui/` | запрещены в `lib/src/tui/core/` |
| `package:codelab_agent_*`, `package:flutter/`, `package:fluent_ui/`, `package:codelab_ui/` | нигде в приложении |

Правила для `codelab_setup/io.dart`, `codelab_embedded/io.dart` и `codelab_embedded/testing.dart` действуют на весь `lib/`, поэтому барель `lib/codelab_cli.dart` не может их реэкспортировать; запреты `codelab_acp_testing` и `dart_tui` — на `lib/src`. Точка входа `bin/` не знает мосты `io.dart` и `testing.dart` вовсе.

**Что сделать.** Перенести код в разрешённое место или получить нужное через порт ([глава 01](development.md#швы-для-тестов)). Расширение списка зависимостей (`cliAllowlist`) — только через OpenSpec change.

## Смотрите также

- [Глава 09: тестирование](09-testing.md)
- [Глава 10: рецепты](10-extending.md)
