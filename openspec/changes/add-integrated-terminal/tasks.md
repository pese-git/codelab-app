Задачи кода идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2; дорожная карта §9.1): сначала красный тест, затем код. В скобках — требование спецификации (`integrated-terminal` «…», сценарий) или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, правила сторожа для зависимостей app и документы app;
- `[client]` — задач нет: `codelab_client_core`, `codelab_client_io`, `codelab_client_acp` и `apps/codelab_cli` не меняются (D2, D10);
- `[protocol]`, `[agent]` — задач нет: ACP и агент не меняются.

Итерации — каждая отдельным pull request в `develop` (design.md, D14); исключение — итерации 1 и 2 идут одним PR (решение Q23, D14, «Отступление»):
- 0 — решения пользователя по Q1–Q13 и документы;
- 1 — спайк зависимостей (ворота), технологический стек, сторож, порт и адаптер;
- 2 — feature `terminal`: Cubit, организм кита, панель в доке;
- 3 — клавиши, палитра, выход из app, приёмка — **после 1.0**;
- 4 — после 1.0: `pty2` в фоновом isolate вкладки (задача 2.13, решение Q24).

Терминал выпускается в 1.0 в объёме итераций 1–2 с известными ограничениями (решение пользователя 2026-11-12, вариант 2; design.md, D14, «Известные ограничения терминала в 1.0»). PR итераций 1–2 вливается в `develop` обычным порядком; итерации 3 и 4 — после 1.0.

Зависимости: 1 ← 0; 2 ← 1 (решение спайка 1.1); 3 ← 2; 4 ← 2. Если спайк 1.1 не прошёл ворота, итерации 2–3 не начинаются, вопрос возвращается пользователю (D14).

Проверки — только затронутого (`AGENTS.md` §21):
- итерация 0: `openspec validate add-integrated-terminal --strict`, проверка относительных ссылок изменённых документов;
- итерации 1–3:
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm flutter analyze` в `apps/codelab_desktop` и `packages/flutter/codelab_ui`, `fvm dart analyze` в `packages/dart/codelab_architecture_tests`;
  - тесты изменённых пакетов: `fvm flutter test` в `apps/codelab_desktop` (можно сузить до `test/features/terminal/`, `test/features/workbench/`, `test/core/platform/`, `test/app/`) и в `packages/flutter/codelab_ui`, `fvm dart test` в `packages/dart/codelab_architecture_tests`;
  - `fvm dart run melos run guard` — меняются `pubspec.yaml` app и правила сторожа (итерация 1) и импорты app (итерации 2–3);
  - `protocol-conformance`, `conformance:*`, `test:e2e:cli:dart-agent`, `web-compile`, `prompts:check` не нужны: ACP, клиентский слой, CLI, агент и web-безопасные пакеты не меняются.
- `test:e2e:app:*` и `integration_test/` на устройстве — только в ветке `release/<version>`. В `feature/*` — только `fvm flutter analyze`.
- Полный `melos run check` — только по просьбе пользователя.

## 0. Решения и документы (итерация 0)

- [x] 0.1 `[desktop]` Ответы пользователя на Q1–Q13 — раздел «Решения пользователя 2026-11-11» в design.md; proposal, решения D, сценарии `specs/integrated-terminal/spec.md` и задачи приведены к ответам (Q2 — `xterm2`, Q8 — без предела, Q12 — лицензии в `technology-stack.md`, Q13 — буфер обмена через OSC запрещён). `openspec validate add-integrated-terminal --strict` проходит.
- [x] 0.2 `[desktop]` `docs/architecture/permissions.md` §2 — подраздел «Терминал пользователя» рядом с исключением `fs/*` и `terminal/*`:
  - команды человека не проходят permission policy;
  - containment не действует;
  - агент панель не видит.

  Ссылка на D8.
- [x] 0.3 `[desktop]` `docs/architecture/platform-integration.md`:
  - §52 — терминал пользователя как явное исключение из «использовать permission policy» (D8);
  - §53 — окружение shell пользователя целиком (D5, Q9);
  - §23 — сеанс PTY как страховка от сирот (D4).
- [x] 0.4 `[desktop]` `docs/architecture/observability.md` §35 — компонент `terminal` и правило «содержимое терминала не логируется», события D9. `docs/architecture/concurrency.md` §44 — `TerminalProcessFactory` → `UserShellLauncher` и `TerminalTabsCubit`; §45 — выход из app закрывает вкладки (D4).
- [x] 0.5 `[desktop]` `dart-agent-and-clients/12-3-desktop-display.md` по ответам Q4, Q5, Q10:
  - A13, шаг 3 — сочетания Terminal и уточнение «повторное сочетание» (D6);
  - A16, шаги 1–3 — владелец вкладок, сочетание, без «Maximize»;
  - A16, шаг 7 — ключи D6;
  - DSK-28 — смена проекта вместо смены сессии;
  - §12.3.6 — тесты итераций 2–3 вместо «раздела 5».
- [x] 0.6 `[desktop]` `agent-parity-goals.md` (D-28) — владелец вкладок и сочетание по ответам; `11-assumptions-and-open-questions.md` — строка PTY: ссылка на Q1 и спайк 1.1; `delivery-roadmap.md` — строка change: «выбор PTY — Q1, спайк 1.1».
- [x] 0.7 `[desktop]` `docs/architecture/technology-stack.md` — разделы `20г` (рендер терминала) и `20д` (PTY) с кандидатами, границами и пометкой «выбор — после спайка 1.1»; финал — задача 1.2 (Q3: без ADR).

## 1. Спайк, стек, сторож, порт (итерация 1)

- [x] 1.1 `[desktop]` Спайк — ворота итерации (D14). Каталог `apps/codelab_desktop/tool/terminal_spike/` (вне `lib/`, по образцу `apps/codelab_cli/tool/tui_spike/` change `add-cli-tui`). Проверить на macOS с Flutter из `.fvmrc`:
  - сборку `flutter build macos` с `pty2` (при неудаче — с `flutter_pty`) и `xterm2` (при неудаче — с `xterm` 4.0.0);
  - что `xterm2_core` импортируется в чистом Dart без Flutter (`fvm dart run` скрипта вне Flutter);
  - `TerminalView` внутри `FluentApp` без `MaterialApp`, тему из `FluentTheme`;
  - OSC 52 запись и чтение отклоняются при `clipboardDecoder: null`, выключенных `allowITerm2ClipboardCapture` и `allowKittyClipboard` и без обработчика чтения;
  - запуск `$SHELL -l` в папке, `test -t 0`, `tput cols` после `resize`, Ctrl+C, `vim`;
  - `SIGHUP` по закрытию;
  - сборку native assets `pty2` под `fvm flutter test` на хосте;
  - `AppLifecycleListener.onExitRequested` при Cmd+Q и закрытии последнего окна;
  - получает ли app Cmd+` (Q5);
  - `LogicalKeyboardKey.backquote` на русской раскладке;
  - рывки UI на `yes | head -n 200000`.

  Итог — раздел «Итог спайка» в design.md (D15): выбранные пакеты рендера и PTY, точные версии, полный список транзитивных зависимостей выбранных пакетов из `pubspec.lock` с лицензиями (несовместимые с MIT — стоп), что не подтвердилось. Каталог спайка удаляется в задаче 3.9.

  Состояние: выполнено 2026-11-11, автоматическая и ручная части (D15). Выбраны `pty2` 0.8.1, `xterm2` 5.4.0, `xterm2_core` 1.0.0. Находки перенесены в D2–D4, D6, D11, D13, Risks и Q15 (условный):
  - русская раскладка — сопоставление по физической клавише;
  - рывки под потоком — бюджет на кадр.
- [x] 1.2 `[desktop]` `docs/architecture/technology-stack.md` §20г–§20д — финал по итогу 1.1 (D15): выбранный пакет, точная версия, транзитивные зависимости и лицензии, проверка по §24–§25 (D11; Q3 — без ADR). `THIRD_PARTY_NOTICES.md` и `licensing-and-attribution` не меняются (Q12); проверить только, что в коде change нет воспроизведённых фрагментов.
- [x] 1.3 `[desktop]` Тест (workspace-architecture «Автоматический сторож границ пакетов»; D11): в `packages/dart/codelab_architecture_tests/test/import_guard_test.dart` правила `apps/codelab_desktop` под выбранный пакет. Правила: `package:xterm2_core/` вне `features/terminal/`; `package:xterm2/` вне `features/terminal/presentation/`; `package:flutter/` в `features/terminal/application/`; PTY-пакет вне `core/platform/user_shell_launcher.dart`. Негативные тесты: `package:xterm2/` в `features/terminal/application/`, `package:xterm2_core/` в `features/workbench/`, PTY-пакет в `features/terminal/` → нарушение (красный). Правило `flutter` в `features/terminal/application` — в итерации 2, вместе с каталогом (задача 2.0).
- [x] 1.4 `[desktop]` Зависимости и правила (D11, D15):
  - добавить `xterm2: 5.4.0`, `xterm2_core: 1.0.0`, `pty2: 0.8.1` точными версиями в `dependencies` `apps/codelab_desktop/pubspec.yaml`;
  - поднять `environment.sdk` `apps/codelab_desktop` до `>=3.11.0` (требование `pty2`); корень workspace и другие пакеты не трогать. Если pub workspace потребует общую границу — остановиться и записать решение в D11 явно;
  - выполнить `fvm dart run melos bootstrap`;
  - сверить `pubspec.lock` с D15: добавлены ровно 9 пакетов (`equatable`, `ffi_leak_tracker`, `native_toolchain_c`, `pty2`, `quiver`, `win32`, `xterm2`, `xterm2_core`, `zmodem`) и подняты `code_assets` 1.2.1 → 2.2.0, `hooks` → 2.2.0, `record_use` → 1.1.1, `objective_c` → 9.6.3. Расхождение записать в D15 (итог: `objective_c` разрешился в 9.6.4, BSD-3-Clause — D11, D15);
  - правила в `test/support/rules.dart` с комментариями (почему, ссылка на D11).

  Ожидаемый результат: 1.3 зелёный, `fvm dart run melos run guard` зелёный, `fvm flutter build macos` app собирается, в бандле есть `pty2_unix.framework`.

  Lock общий, поэтому подъём `code_assets` (мажор), `hooks`, `record_use` и `objective_c` — изменение межпакетных зависимостей (`AGENTS.md` §21, п. 4). Нужны:
  - `fvm dart run melos run analyze` по workspace;
  - тесты пакетов, которые тянут эти четыре пакета (найти по `fvm dart pub deps`).

  Полный `melos run check` — предложить пользователю, самим не запускать.
- [x] 1.5 `[desktop]` Контрактный тест адаптера (`integrated-terminal` «Терминал — настоящий псевдотерминал», «Жизненный цикл процессов терминала»; D2, D13): `apps/codelab_desktop/test/core/platform/user_shell_launcher_test.dart` на Dart VM (native assets `pty2` собираются под `flutter test`, D15). На код выхода тест не опирается (D4, «Код выхода»). Проверяет:
  - `test -t 0 && test -t 1 && echo tty` → в выводе `tty`;
  - переменная из `environment`, которой нет в узком наборе `pty2`, видна в shell; `TERM` и `COLORTERM` выставлены;
  - `cwd` соблюдается;
  - `tput cols` после `resize(100, 30)` → `100`;
  - `hangUp()` завершает интерактивный `sh` (`exitCode` завершается);
  - `kill()` завершает `sh -c "trap '' HUP; exec sleep 100"`, на который `hangUp()` не действует (D15, п. 6);
  - повторные `kill()`, `hangUp()`, `write()` и `resize()` после выхода — без ошибок;
  - `exitCode` = `-1` от `pty2` адаптер отдаёт как `null` (на fake-ядре или через отдельную функцию перевода);
  - несуществующий исполняемый файл → `UserShellStartFailure.shellNotFound`, несуществующая папка → `folderNotFound`; `start` пакета не вызывается, пути в тексте нет;
  - `isSupported` на macOS — `true`.

  Тест красный.
- [x] 1.6 `[desktop]` Реализовать порт `UserShellLauncher`, `UserShell` (`Stream<String> output`, `write(String)`, `exitCode` как `Future<int?>`), `UserShellStartFailure` с предпроверкой файла и папки и адаптер на `pty2`; окружение — `Platform.environment` целиком плюс `TERM`, `COLORTERM` в `apps/codelab_desktop/lib/core/platform/user_shell_launcher.dart`; `Platform.is*` только здесь (D2, D12). Комментарии по `AGENTS.md` §15 — 1.5 зелёный.
- [x] 1.6a `[desktop]` Выбор shell в адаптере (D2, «Выбор shell»; D5) — выполнено: чистая функция `chooseUserShell`, `UserShellCommand`, `UserShellLauncher.resolveShell()`, `ptyUnavailable` из `start` и `resize`; 28 тестов зелёные, мутации пойманы:
  - **тест** в `apps/codelab_desktop/test/core/platform/user_shell_launcher_test.dart` (красный):
    - POSIX — порядок `$SHELL` (абсолютный и исполняемый) → `/bin/zsh` → `/bin/bash` → `/bin/sh`;
    - `$SHELL` относительный, несуществующий или неисполняемый пропускается;
    - выбранному shell добавляется `-l`;
    - Windows — `%ComSpec%` без `-l`;
    - ни одного кандидата → `shellNotFound`;
    - не абсолютный `executable` → `shellNotFound` без поиска по `PATH`;
    - `PtyException` и другое `Exception` из `pty2.start` → `UserShellStartFailure.ptyUnavailable`; `Error` (`ArgumentError`, `UnsupportedError`, `StateError`) пробрасывается без обёртки; сбой первого `resize` при старте → `SIGKILL` shell и `ptyUnavailable`;
    - ошибка `exitCode` пробрасывается, после неё методы `UserShell` — no-op;
    - после завершения `exitCode` вызовы `write`, `resize`, `hangUp`, `kill` — no-op без исключений.

    Проверка файловой системы и платформы — через внедряемые функции, без `Platform.is*` в тесте;
  - **реализация** в `user_shell_launcher.dart` — тест зелёный.
- [x] 1.7 `[desktop]` **Перенесено в 2.11** (решение Q23, 2026-11-12): отдельного PR итерации 1 нет, итерации 1–2 идут одним PR; проверки ниже выполняются в 2.11. Исходный текст задачи — для справки. Проверки итерации 1 и PR итерации 1. Кроме шапки, проверки шире app: lock общий, в нём подняты `code_assets` (мажор), `hooks`, `record_use`, `objective_c` (D11).
  - `fvm dart run melos run analyze` по workspace;
  - тесты пакетов с native assets и хуками сборки — найти по `fvm dart pub deps` потребителей `hooks`/`code_assets`/`objective_c`;
  - `fvm dart run melos run web-compile`: web-безопасные пакеты делят тот же lock;
  - `fvm dart run melos run guard`.

  **Linux CI.** Подтвердить прогон контрактного теста на настоящем PTY в GitHub CI на `ubuntu-latest`: там `/bin/sh` — dash, нужны `tput` и terminfo. Итог записать в D15. Если тест там не собирается или падает по причине окружения, а не адаптера, — `skip` вне macOS с причиной в тексте и запись в D13.

  Полный `melos run check` — только предложить пользователю.
- [ ] 1.8 `[desktop]` Завести issue в репозитории `pty2` (ссылка — в D15, п. 8, и в Risks), по одному на дефект или одним с разделами:
  - окно pid-reuse между `waitpid` в воркере и доставкой кода в главный isolate — pidfd или сигнал из воркера (Risks, «Окно между `waitpid` и доставкой кода»);
  - `alloc failed` после `fork`: мастер закрывается без `kill` и `waitpid`, ребёнок без владельца, зомби до выхода app (Risks, «Ребёнок без владельца»);
  - на macOS закрываются только fd < 4096 при `RLIMIT_NOFILE` > 65536 (Risks, «Утечка дескрипторов»);
  - синхронный `write`: при `EAGAIN` он крутит `poll(100 мс)` на вызывающем isolate и держит его, пока программа не прочитает ввод. Просьба — асинхронная запись (или запись из воркера) и публичный `pid` (геттер уже есть, закомментирован); с ними уйдут обёртка старта ради `pid` и, возможно, isolate вкладки (решения Q24, Q25; D2, «Фоновый isolate вкладки»; Risks, «Синхронная запись в PTY»). Замер для issue — без путей: программа в raw-режиме без чтения stdin, `write` 4/64/200 КБ, ~7,5 с блокировки, буфер ввода PTY macOS ~1 КБ.

  Отдельно — issue в `xterm2_core`: флаг, выключающий ответ на CSI 21 t (отчёт заголовка окна), иначе текст OSC 2 из чужого вывода попадает во ввод shell (Risks, «Отчёт заголовка CSI 21 t в ввод shell»).

  Текст issue — без путей и данных пользователя. Внешнее действие: заводит пользователь или исполнитель по его разрешению.

## 2. Feature terminal и панель в доке (итерация 2)

- [x] 2.0 `[desktop]` Правила сторожа «`package:flutter/` запрещён в `apps/codelab_desktop/lib/features/terminal/application`» (D11, правило 3; перенесено из 1.3–1.4, потому что сторож требует существующий каталог) и «`package:zmodem/`, `package:xterm2/xterm.dart`, `package:xterm2/zmodem.dart` запрещены в `apps/codelab_desktop/lib`» (D11, правило 5; D3, «ZModem выключен»): presentation берёт `TerminalView` из `package:xterm2/ui.dart`, который `zmodem` не реэкспортирует (в 5.4.0 `xterm.dart` = `core.dart` + `ui.dart` + `zmodem.dart`). Сначала негативные тесты в `packages/dart/codelab_architecture_tests/test/import_guard_test.dart` (`flutter` в `application`; `zmodem` и `package:xterm2/xterm.dart` в `presentation` → нарушение; `package:xterm2/ui.dart` в `presentation` — не нарушение; красный), затем `PackageRule` в `test/support/rules.dart` вместе с появлением каталога в 2.2 — тест зелёный.
- [x] 2.1 `[desktop]` Тест `apps/codelab_desktop/test/features/terminal/application/terminal_tabs_cubit_test.dart` с `FakeUserShellLauncher` и fake-временем (`integrated-terminal` «Вкладки терминала принадлежат сессии», «Панель Terminal в доке инструментов» (сценарий «Нет активной сессии»), «Рабочая папка вкладки терминала», «Жизненный цикл процессов терминала», «Содержимое терминала не покидает экран»; D3–D5, D9; Q4 пересмотрено, Q17–Q19). `FakeUserShellLauncher` (с `isSupported`, `resolveShell`, `start` и управляемым fake-`UserShell`) — в `apps/codelab_desktop/test/support/fake_user_shell_launcher.dart`: им пользуются и 2.5, 2.9, 3.x. Журнал — `RecordingLogger` (`test/support/recording_logger.dart`). Fake-время — через `testWidgets` и `tester.pump(Duration)` / `tester.binding.delayed`; `fake_async` в `dev_dependencies` не добавляется (техническое решение 2026-11-11). `ClientWorkspace` — fake с управляемыми `current` и `state` (`activeSessionId`, `profile`) и `session(id)` с `SessionHandle.cwd`. Проверяет:
  - вкладки по сессии: владелец — `TerminalOwner(profileId, sessionId)` из `WorkspaceState.activeSessionId` и `WorkspaceState.profile.id` в момент активации (D5); смена активной сессии показывает её вкладки, процессы сессии A не получают сигналов;
  - нет активной сессии (`activeSessionId == null` или у `ClientWorkspace.session(id)` нет `SessionHandle`) → состояние «нет сессии», команда новой вкладки не вызывает `start` и вкладку не создаёт (Q17);
  - вкладки сессии переживают смену `projectDirectory`, смену `profile` и разрыв соединения (`ConnectionView` → disconnected → connected); возврат той же сессии (тот же `profileId` + `sessionId`) показывает прежние вкладки с живым процессом (Q18);
  - одинаковый `sessionId` у двух профилей — разные владельцы, вкладки не смешиваются (D5);
  - после подключения к другому профилю без выбора сессии показываются вкладки прежней сессии (владелец запомнен при активации; `ClientWorkspace` не сбрасывает `activeSessionId`, D5);
  - снимок `cwd`: вкладка стартует в `SessionHandle.cwd` активной сессии на момент создания, `WorkingDirectoryProvider` не вызывается (Q19);
  - несуществующая папка (`DirectoryExists` из `codelab_client_io` вернул `false`) → `failed(folderNotFound)` без вызова `start`;
  - shell берётся у порта: `FakeUserShellLauncher.resolveShell()` (метод порта `UserShellLauncher`, итерация 1) → его команда уходит в `start`; `resolveShell()` вернул `null` → вкладка `failed(shellNotFound)` без вызова `start`;
  - новая вкладка активна; 12 вкладок подряд создаются без отказа (предела нет, Q8);
  - закрытие вкладки и `closeAll()` во время `start`: поздний `UserShell` сразу получает `kill()` и в реестр не попадает (D4, «Старт в полёте»);
  - закрытие: `hangUp` → если `exitCode` не завершился за 2 с — `kill`, вкладка исчезает сразу, `forced` в событии;
  - `exit 3` → `exited(3)`; код `null` от порта → `exited(null)`, строка `[Process exited]`, событие без `exit_code`; ввод в вышедшую вкладку игнорируется;
  - запись в эмулятор порциями: 400 КБ вывода одним чанком fake-shell уходят в `Terminal.write` частями не больше заданного размера (4 КБ по умолчанию), без потери и перестановки данных; закрытие вкладки отбрасывает незаписанный остаток (D3, D4). Бюджет времени на кадр — задачи 2.7–2.8;
  - поздний вывод закрытой вкладки не меняет состояние;
  - `closeAll()`: `hangUp` всем, через 3 с `kill`, затем новые вкладки не создаются, повторный вызов — без действий;
  - после `exited` Cubit отписан от `output` и не вызывает `hangUp`/`kill` этой вкладки — ни при закрытии, ни в `closeAll()` (D4);
  - `exitCode` завершился ошибкой (fake пробрасывает исключение, как адаптер) → вкладка `exited(null)`, событие `terminal.exit_wait_failed` с `tab_id` и `error_type` (`runtimeType`, без `toString()`), без сигналов, отписка от `output` (D4, D9);
  - `UserShellStartFailure.ptyUnavailable` → `failed`, событие `terminal.start_failed` с `reason: ptyUnavailable`;
  - fake `start` бросает `ArgumentError('native library not found: /Users/x/lib.dylib')` → вкладка `failed(ptyUnavailable)`, в fake-журнале событие `terminal.start_failed` с `reason: ptyUnavailable` и `error_type: ArgumentError`; подстроки `/Users` в журнале нет, исключение из Cubit не выходит (D4, «Ошибка старта в Cubit»);
  - то же, но вкладку закрыли до конца `start` → только событие, состояние не меняется;
  - поздний `UserShell` закрытой вкладки, чей `exitCode` завершился ошибкой → событие `terminal.exit_wait_failed`, необработанной ошибки в зоне нет (тест под `runZonedGuarded` или с проверкой `FlutterError`), состояние не меняется (D4, «Старт в полёте»);
  - после `close()` Cubit нет событий;
  - флаг предупреждения — один раз за жизнь Cubit;
  - события D9 в fake-логгере без путей, окружения и вывода.

  Тест красный.
- [x] 2.2 `[desktop]` Реализовать `lib/features/terminal/application/`: `TerminalTabsCubit`, `TerminalTabsState`, закрытую иерархию `TerminalTabStatus`, реестр вкладок с моделью `Terminal` из `package:xterm2_core/xterm2_core.dart` (`maxLines` 10 000), буфер записи порциями — 2.1 зелёный. Модель вкладки создаёт **одна продакшн-фабрика** `terminalModel({required void Function(String data) onOutput, void Function(int columns, int rows)? onResize})` в application, перенесённая из `buildPolicyTerminal` (`tool/terminal_spike/lib/terminal_policy.dart` спайка; `onOutput` несёт и ввод пользователя, и ответы эмулятора shell-у — DA, DSR, запросы цвета; `Terminal.onResize` в `xterm2_core` — `(width, height, pixelWidth, pixelHeight)`). Политика буфера обмена Q13 (поля `Terminal` в `xterm2_core` 1.0.0):
  - `clipboardDecoder: (_, _) => null` — тип `String? Function(String selector, String data)?`, `final`;
  - `allowITerm2ClipboardCapture: false`, `allowKittyClipboard: false` — `final`, по умолчанию `true`;
  - пустой `onClipboardStore` — `void Function(String selector, String text)?`;
  - `onClipboardQuery` → `null` — `FutureOr<String?> Function(String selector)?`.

  Последние два — изменяемые поля: `TerminalView.initState` ставит их `??=`, поэтому они не `null`. `onOpenUrl` (OSC 1337 `OpenURL` — открытие адреса по команде процесса, без жеста) фабрика не задаёт, и `TerminalView` его не ставит: адрес открывается только через `onHyperlinkTap` и диалог (2.10). Модульный тест фабрики — в 2.1: каждое поле политики выставлено, обработчики не `null`, `onOpenUrl == null`. Других мест создания `Terminal` в app нет (D3).
- [x] 2.3 `[desktop]` Widget-тест `packages/flutter/codelab_ui/test/codelab_terminal_pane_test.dart` (D3; тесты кита лежат плоско в `test/`, подкаталога `organisms/` нет). Проверяет:
  - ключи `terminal-tab-<id>`, `terminal-tab-close-<id>`, `terminal-new-tab`, `terminal-disclosure` (статические `ValueKey`-фабрики организма, как `CodeLabToolDock.paneKey`);
  - тег статуса из переданной подписи и тона — `CodeLabBadge(label:, tone: CodeLabTone)`;
  - пустое состояние «New terminal»;
  - закрытие предупреждения вызывает колбэк;
  - содержимое из слота показывается для активной вкладки.

  Тест красный.
- [x] 2.4 `[desktop]` Реализовать организм `CodeLabTerminalPane` в `packages/flutter/codelab_ui/lib/src/organisms/codelab_terminal_pane.dart`, экспорт в `lib/src/organisms/organisms.dart`, пример в `lib/src/organisms/codelab_organism_previews.dart` (его покрывает `test/codelab_previews_test.dart`); запись в `packages/flutter/codelab_ui/AGENTS.md` §4 (без пакета рендера терминала, без логики) — 2.3 зелёный.
- [x] 2.5 `[desktop]` Widget-тест `apps/codelab_desktop/test/features/terminal/presentation/terminal_pane_test.dart` с `FakeUserShellLauncher` (`integrated-terminal` «Панель Terminal в доке инструментов», «Терминал вне одобрений агента», «Восстановление дока не запускает shell», «Терминал только там, где есть PTY», «Содержимое терминала не покидает экран»; D1, D7, D12). Приложение собирается `TestAppScope` (`test/support/test_app_scope.dart`) с fake-портом через шов `createCodeLabRootScope(userShellLauncher:)` (2.6). Проверяет:
  - `tool-toggle-terminal` (`CodeLabAppBar.toggleKey(ToolPane.terminal)`) открывает `tool-pane-terminal` (`CodeLabToolDock.paneKey`) с одной вкладкой;
  - закрытие панели крестиком вкладки дока (`tool-tab-close-terminal`, `CodeLabToolDock.closeKey`) и повторное открытие сохраняют вкладку;
  - выбор сессии B показывает её вкладки, возврат к A — вкладку A с живым процессом;
  - без активной сессии (`TestAppScope` без открытой сессии) переключатель открывает панель с «Open a session to use the terminal», без `terminal-new-tab`, `start` не вызывается (Q17);
  - выбор другого проекта и переподключение (`FakeAcpTransport` закрыт и открыт заново, затем `session/load` той же сессии) не закрывают вкладку сессии (Q18);
  - восстановленный док (`DockLayoutStore`: `TestAppScope(preferences: {'codelab.dock.open_panes': ['terminal'], 'codelab.dock.active_pane': 'terminal'})`) — пустое состояние (подсказка Q17, пока сессии нет) без вызова `start`;
  - `FakeUserShellLauncher(isSupported: false)` — переключателя нет;
  - предупреждение при первом открытии и его нет после закрытия;
  - маркер вывода fake-shell не появляется в `LogBuffer`;
  - буфер обмена (Q13, D3) — с настоящим `TerminalView` из `xterm2` над моделью вкладки из фабрики 2.2, фокус во вкладке: OSC 52 запись (`c` и `p`), OSC 52 запрос, OSC 1337 `CopyToClipboard`, OSC 5522 `write` в выводе fake-shell не вызывают `Clipboard.setData`/`getData` (mock `SystemChannels.platform`), а fake-shell не получает ответа. Контроль: модель без политики под тем же `TerminalView` вызывает `Clipboard.setData` — тест ловит именно подмену `??=`, а не отсутствие OSC;
  - выделение и копирование пользователем вызывают `Clipboard.setData` с выделенным текстом.

  Тест красный.
- [x] 2.6 `[desktop]` Реализовать:
  - `lib/features/terminal/presentation/` — привязку `TerminalView` (`package:xterm2/ui.dart`; `Terminal` и `CellOffset` — из `package:xterm2_core/xterm2_core.dart`) к модели вкладки, тему `TerminalTheme` из `FluentTheme`, сброс буфера записи не чаще кадра частями до 4 КБ (D3); обработчики буфера обмена модели не перезаписываются виджетом;
  - `CodeLabShell` (`lib/features/workbench/presentation/workbench_shell.dart`) — `_availablePanes` сейчас `static const [plan, protocol]`: становится списком, куда `ToolPane.terminal` входит при `isSupported`; в `switch (pane)` содержимого дока своя ветка `ToolPane.terminal =>` вместо ветки `_` (она рисует `_ProtocolPane`);
  - маппер статуса вкладки в подпись и тон;
  - сборку в root scope (`lib/app/app_scope.dart`) по образцу `SecretMigrationCubit`:
    - `bind<UserShellLauncher>()` в `CodeLabPlatformModule` (`PtyUserShellLauncher()`) и шов `createCodeLabRootScope(userShellLauncher:)`, его же — в `TestAppScope`;
    - `TerminalTabsCubit` — `.singleton()` в `CodeLabPresentationModule` с `ClientWorkspace`, `DirectoryExists` и логгером `StructuredLogLogger('codelab_desktop.terminal').bind({logCategoryKey: applicationLogCategory, logComponentKey: 'terminal'})`;
    - объект сброса буферов на `SchedulerBinding` (D3) — там же, рядом с Cubit, с тем же сроком жизни;
    - поле в `CodeLabDependencies`, `_CodeLabBootstrapState` и `BlocProvider.value` в `CodeLabApp` (`lib/app/codelab_app_widget.dart`);
    - закрытие — в `CodeLabRootLifecycle.dispose()` (новый параметр `CodeLabRootLifecycleModuleContract.rootLifecycle`; `app_scope.module.cherrypick.g.dart` перегенерировать `fvm dart run build_runner build` в app, руками не править).

  Раздел «Терминал» в `apps/codelab_desktop/AGENTS.md`: где пакеты, владелец процессов, что не логируется, граница с `terminal/*`. 2.5 зелёный.
- [x] 2.7 `[desktop]` Тест `apps/codelab_desktop/test/features/terminal/presentation/terminal_write_budget_test.dart` (D3, «Запись в эмулятор порциями»; D15, «Рывки на Flood»). Объект сброса буферов на `SchedulerBinding` (один на root scope, D3) с fake-часами и fake-моделью; кадр — `tester.pump()`:
  - за один кадр пишется столько частей, сколько укладывается в бюджет (fake-`write` «стоит» заданное время), остаток — на следующий кадр;
  - часть не больше заданного размера;
  - за кадр — не больше одной перерисовки `TerminalView`;
  - вкладка без отрисовки (панель закрыта или вкладка не активна) пишет в модель без перерисовки — объект сброса работает и без виджета панели;
  - при непустом буфере объект сам заказывает кадр (`scheduleFrame()` вместе с `scheduleFrameCallback`), при пустом — нет;
  - закрытие объекта (`dispose` root scope) отменяет заказанный обратный вызов;
  - порядок и полнота данных сохраняются.

  Тест красный.
- [x] 2.8 `[desktop]` Реализовать объект сброса буферов в `lib/features/terminal/presentation/` с бюджетом на кадр (стартовые значения: часть 4 КБ, бюджет 8 мс; константы рядом с ним), сборка — в 2.6 — 2.7 зелёный.

  Замер вручную: profile-сборка app на macOS (`fvm flutter run -d macos --profile`), «Flood» (`yes | head -n 200000`) во вкладке. Это ручной замер на машине разработчика, а не прогон `test:e2e:app:*`.
  - **Цель:** худший кадр меньше 50 мс.
  - Если цель не достигнута, по очереди: часть 1 КБ, меньший бюджет, без отрисовки фоновых вкладок.

  Итог (худший кадр, число кадров > 33 мс и > 100 мс, константы) записывается в D3. Если цель недостижима — Q15 пользователю до PR итерации 2.
- [x] 2.9 `[desktop]` Тест ссылок OSC 8 (`integrated-terminal` «Ссылки в выводе терминала»; D3, «Ссылки OSC 8»; Q14), красный:
  - `apps/codelab_desktop/test/features/terminal/application/terminal_link_decision_test.dart` — `terminalLinkDecision`: `http`/`https` в любом регистре — «можно открыть»; `file:`, `ssh:`, `javascript:`, `mailto:`, пустой и неразбираемый адрес — «нельзя»;
  - `test/features/terminal/presentation/terminal_link_test.dart` с настоящим `TerminalView` и fake-портом открытия адреса. Модификатор проверяет сам `TerminalView` (5.4.0): по `defaultTargetPlatform` — Meta на macOS, Control на остальных, и только тогда зовёт `onHyperlinkTap(String uri)` с адресом из `Terminal.hyperlinkAt`. Под `flutter test` платформа по умолчанию не macOS, поэтому тест Cmd+клика идёт с `debugDefaultTargetPlatformOverride = TargetPlatform.macOS` (или `variant: TargetPlatformVariant.only(TargetPlatform.macOS)`) и `tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft)` до клика:
    - Cmd+клик по ссылке `https` → `terminal-link-dialog` с полным адресом, а не текстом ссылки; «Open» вызывает порт ровно один раз, «Cancel» и Esc — ни разу;
    - Cmd+клик по `file:///etc/passwd` → диалог с сообщением и без «Open», порт не вызывается;
    - обычный клик — диалога нет;
    - OSC 1337 `OpenURL` в выводе — порт не вызывается, диалога нет (`onOpenUrl` не задан, 2.2);
    - адрес не появляется в `LogBuffer`, событие — только со схемой.
- [x] 2.10 `[desktop]` Реализовать ссылки OSC 8 — 2.9 зелёный:
  - `terminalLinkDecision` в application;
  - обработчик `TerminalView.onHyperlinkTap` (`void Function(String uri)?`) и диалог в presentation;
  - порт открытия адреса в `lib/core/platform/` на `url_launcher` (Q16, D11). Если `add-desktop-markdown` уже влит — переиспользовать его порт и правило сторожа. Иначе (на 2026-11-11 — так: в `develop` 938a5efc `url_launcher` нет):
    - добавить `url_launcher: 6.3.3` точной версией (последняя стабильная, 2026-10-02, publisher `flutter.dev`, BSD-3-Clause; требует Dart `^3.11.0`, Flutter `>=3.41.0`). Сухой прогон `fvm flutter pub add url_launcher:6.3.3 --dry-run` в app (2026-11-11) добавляет в lock 8 пакетов и ничего не поднимает: `url_launcher` 6.3.3, `url_launcher_android` 6.3.33, `url_launcher_ios` 6.4.2, `url_launcher_linux` 3.2.3, `url_launcher_macos` 3.2.6, `url_launcher_platform_interface` 2.3.2, `url_launcher_web` 2.4.3, `url_launcher_windows` 3.1.6 — все BSD-3-Clause (Flutter Authors). Нижнюю границу `flutter:` app (`>=3.35.0`) поднять до `>=3.41.0` по правилу D11 «Граница SDK» (решение принято 2026-11-11);
    - ввести порт тем же именем, путём и сигнатурой, что в ветке `feature/add-desktop-markdown` (170de43f): `ExternalLinkOpener` с `Future<ExternalLinkOutcome> open(Uri uri)` (`opened | failed | rejectedScheme`) в `lib/core/platform/external_link_opener.dart`, реализация `UrlLauncherExternalLinkOpener` — `launchUrl(uri, mode: LaunchMode.externalApplication)`, исключение платформы → `failed` без текста. Так второй из двух change при слиянии оставляет один файл, а не два порта;
    - ввести правило `PackageRule('apps/codelab_desktop/lib', forbidden: ['package:url_launcher/'], exclude: ['core/platform/'], sealExclude: false)` — то же, что у markdown change, — с негативным тестом в `import_guard_test.dart`;
    - в `technology-stack.md` — короткий раздел или ссылку на раздел markdown change, если он уже есть, без дублирования. Markdown change пинует `^6.3.3`; при слиянии второй change приводит запись к точному пину `6.3.3` (D11);
  - события `terminal.link_opened` и `terminal.link_refused` с полем `scheme` (D9).
- [x] 2.11 `[desktop]` Проверки итераций 1–2 и один PR итераций 1–2 (решение Q23; задача 1.7 перенесена сюда) — после 2.7–2.10 и 2.12:
  - проверки шапки для итераций 1–2;
  - проверки шире app из 1.7 (общий lock: подняты `code_assets` (мажор), `hooks`, `record_use`, `objective_c`; D11): `fvm dart run melos run analyze` по workspace, тесты пакетов-потребителей `hooks`/`code_assets`/`objective_c` (по `fvm dart pub deps`), `fvm dart run melos run web-compile`, `fvm dart run melos run guard`. Выполнены локально до 2.12; после 2.12 повторить `guard` и проверки app (2.12 меняет только app);
  - **Linux CI** — прогон контрактного теста адаптера на настоящем PTY в GitHub CI на `ubuntu-latest` (там `/bin/sh` — dash, нужны `tput` и terminfo) показывает этот PR. Итог записать в D15. Если тест там не собирается или падает по причине окружения, а не адаптера, — `skip` вне macOS с причиной в тексте и запись в D13;
  - в описании PR — известные ограничения терминала в 1.0 (design.md, D14): заморозка app при вставке больше ~1 КБ в программу, не читающую ввод (Q24 после 1.0); нет Ctrl+`, Ctrl+Shift+` и `/terminal` — только переключатель в шапке; выход из app без `hangUp`/`kill`, сиротами могут остаться задания с игнором `SIGHUP`; приёмка на устройстве (3.7) — ручная. Итерация 3 и 2.13 — после 1.0;
  - в описании PR — какие проверки запускались локально, что полный `melos run check` не запускался (`AGENTS.md` §21). Полный `check` — только предложить пользователю.

- [x] 2.12 `[desktop]` Исправления по двойному ревью итераций 1–2 (до 2.11). Каждая пара — сначала красный тест, затем код:
  - **`Disposable` у объекта сброса** (D3): тест — закрытие root scope вызывает `dispose` `TerminalOutputFlusher` без отдельного кода composition root, заказанный обратный вызов кадра и таймер отменены; реализация — `TerminalOutputFlusher` реализует `Disposable` cherrypick;
  - **владелец по `SessionHandle`** (D5; `integrated-terminal` «Вкладки терминала принадлежат сессии», сценарий «Совпадение идентификаторов сессий у разных агентов»): тест в `terminal_tabs_cubit_test.dart` — при том же `activeSessionId` другой объект `SessionHandle` (сессия другого профиля) даёт нового владельца без вкладок прежнего; reconnect и `session/load` с тем же `SessionHandle` сохраняют вкладки; реализация — Cubit запоминает `SessionHandle` вместе с владельцем;
  - **`forced` в `closeAll`** (D4, D9): тест — вкладка, которой в `closeAll()` понадобился `kill`, пишет `terminal.tab_closed` с `forced: true`, вышедшая по `hangUp` — с `forced: false`; реализация — в `closeAll`;
  - **шрифт** (D3): widget-тест — `TerminalView` получает `TerminalStyle` с моноширинным шрифтом кита; реализация — в presentation;
  - **буфер Q20** (D3, «Окно без кадров и предел буфера»; `integrated-terminal` «Вывод вкладки под большим потоком»): тест в `terminal_write_budget_test.dart` — при lifecycle `hidden`/`paused` сброс идёт по таймеру теми же частями и с тем же бюджетом, при возврате кадров таймер останавливается; буфер сверх предела (в тесте — уменьшенная константа) отбрасывает самый старый неразобранный вывод, в модель пишется `[output truncated]`, остаток идёт в исходном порядке; реализация — в `TerminalOutputFlusher` и буфере реестра;
  - **ссылки Q21** (D3, «Ссылки OSC 8»; `integrated-terminal` «Ссылки в выводе терминала», сценарии «Диалог показывает нормализованный адрес», «Адрес с символами подмены»): тест в `terminal_link_decision_test.dart` — нормализованный адрес `Uri.parse(...).toString()`; каждый символ из диапазонов bidi, нулевой ширины, C0, DEL и C1 → «нельзя открыть» при схеме `https`; в `terminal_link_test.dart` — диалог показывает нормализованный адрес, «Open» передаёт порту ровно его, для адреса с U+202E кнопки «Open» нет, событие `terminal.link_refused` только со схемой; реализация — `terminalLinkDecision` и диалог;
  - **заголовок Q22** (D3, D9; `integrated-terminal` «Панель Terminal в доке инструментов», сценарий «Вывод не меняет подпись вкладки»): тест — OSC 2 в выводе не меняет подпись «Terminal N»; реализация — подпись не читает заголовок модели (если тест сразу зелёный — оставить его как регрессионный);
  - **комментарии** (`AGENTS.md` §15): комментарий правила `flutter` в `features/terminal/application` в `rules.dart` — «прямые импорты запрещены; транзитивно через порты `core/platform` application зависит от Flutter-пакета app, образец `dock_layout_store.dart`» (D3); комментарии изменённых сущностей — по решениям Q20–Q22.

## 3. Клавиши, палитра, выход из app, приёмка (итерация 3) — после 1.0

- [ ] 3.1 `[desktop]` Тест `packages/flutter/codelab_ui/test/codelab_workbench_shortcuts_test.dart` (D6, «Сопоставление по физической клавише»; Q5, Q8). Колбэки `onToggleTerminal` (Ctrl+`) и `onNewTerminalTab` (Ctrl+Shift+`):
  - срабатывают с Control на любой платформе, не срабатывают с Meta;
  - срабатывают, когда `physicalKey` — `PhysicalKeyboardKey.backquote`, а `logicalKey` — `LogicalKeyboardKey.bracketRight` с символом `]` (русская раскладка, D15);
  - не срабатывают на логическую `` ` `` с другой физической клавишей;
  - `onNewTerminalTab` не срабатывает на `KeyRepeatEvent` (`includeRepeats: false`).

  События — через `simulateKeyDownEvent(…, physicalKey:)`. Тест красный.
- [ ] 3.2 `[desktop]` Реализовать в ките `ShortcutActivator` по физической клавише (Control, Shift, `includeRepeats`) и колбэки в `CodeLabWorkbenchShortcuts` — 3.1 зелёный.
- [ ] 3.3 `[desktop]` Widget-тест `apps/codelab_desktop/test/features/terminal/presentation/terminal_keys_test.dart` (`integrated-terminal` «Клавиатура и палитра терминала»; D6). Проверяет:
  - Ctrl+` из композера открывает панель и фокусирует вкладку, повторное — возвращает фокус композеру;
  - Ctrl+Shift+` — новая вкладка;
  - с фокусом в терминале Ctrl+` и Ctrl+Shift+` с физическим backquote и логической `]` перехватываются до эмулятора (`TerminalView.onKeyEvent`), а fake-shell не получает байтов;
  - фокус в терминале: Esc при идущем ходе не отправляет `session/cancel`, Ctrl+K при `debugDefaultTargetPlatformOverride = linux` не открывает палитру, а байты уходят fake-shell;
  - `/terminal` в палитре и inline-палитре открывает панель;
  - `/terminal` нет при `isSupported: false`;
  - команда агента `terminal` показана рядом с командой хоста.

  Тест красный.
- [ ] 3.4 `[desktop]` Реализовать:
  - `/terminal` в `CodeLabCommandAction.defaults` (кит) с фильтром по `isSupported` в `ui_mappers.dart`;
  - ветку `terminal` в `CodeLabShellCubit.selectCommand`;
  - перехват Ctrl+` и Ctrl+Shift+` в `TerminalView.onKeyEvent` тем же активатором по физической клавише из кита;
  - привязку колбэков в `CodeLabShell`.

  Обновить тесты кита, считающие шесть команд палитры. 3.3 зелёный.
- [ ] 3.5 `[desktop]` Тест `apps/codelab_desktop/test/app/terminal_exit_test.dart` (`integrated-terminal` «Жизненный цикл процессов терминала», сценарий «Выход из приложения»; D4): обработчик выхода composition root вызывает `closeAll()` и возвращает `AppExitResponse.exit` не позже 3 с при зависшем fake-shell; закрытие root scope после этого не вызывает `start` и не бросает. Тест красный.
- [ ] 3.6 `[desktop]` Реализовать `AppLifecycleListener(onExitRequested:)` в `lib/app/` — 3.5 зелёный. Правка `macos/Runner/AppDelegate.swift` не нужна: спайк подтвердил, что запрос выхода доходит при Cmd+Q и закрытии последнего окна (D15, «Ручная проверка»).
- [ ] 3.7 `[desktop]` `apps/codelab_desktop/integration_test/terminal_flow_test.dart` (приёмка D13): вкладка, `echo`, `tput cols`, закрытие вкладки без живого процесса, выход из app без сирот. В `feature/*` — только `fvm flutter analyze`; запуск на устройстве — в `release/<version>` (`AGENTS.md` §21).
- [ ] 3.8 `[desktop]` Документы DoD: `agent-parity-goals.md` D-28 — «закрыто change `add-integrated-terminal`» с тестами 2.5, 3.3, 3.7; A16 — ссылки на тесты; `delivery-roadmap.md` — статус строки.
- [ ] 3.9 `[desktop]` Удалить `apps/codelab_desktop/tool/terminal_spike/`. Проверки итерации 3 (шапка) и PR итерации 3.
- [ ] 3.10 `[desktop]` Архивирование change — только по просьбе пользователя, после merge итерации 3 и задачи 2.13 (раздел 4).

## 4. `pty2` в фоновом isolate вкладки (итерация 4) — после 1.0

- [ ] 2.13 `[desktop]` `pty2` в фоновом isolate вкладки (решение Q24, 2026-11-12; D2, «Фоновый isolate вкладки»; D4, «Сигналы при висящей записи»; `integrated-terminal` «Жизненный цикл процессов терминала», сценарии «Вставка в программу, которая не читает ввод», «Закрытие вкладки при висящей записи», «Порядок ввода»). **Отложено на после 1.0** (решение 2026-11-12; номер сохранён — на него ссылаются design.md и документы). Источник `pid` — вариант (a) Q25; Q25 решается до начала задачи, при другом выборе задача правится. После merge итераций 1–2, отдельным PR (можно вместе с итерацией 3 или до неё). Пары — сначала красный тест, затем код:
  - **spec delta сначала**: вернуть в `specs/integrated-terminal/spec.md` требование ввода и сценарии «Вставка в программу, которая не читает ввод», «Закрытие вкладки при висящей записи», «Порядок ввода» — текст в design.md, D4, «Сигналы при висящей записи»; снять пометки «план после 1.0» в D2, D4, D13, Risks, `concurrency.md` §4.2, `technology-stack.md` §20д по мере реализации; `openspec validate add-integrated-terminal --strict`;
  - **контрактный тест записи** в `apps/codelab_desktop/test/core/platform/user_shell_launcher_test.dart` на настоящем PTY (Dart VM, D13). Программа — `sh -c 'stty raw -echo; sleep 30'`, которая не читает stdin:
    - `write` 200 КБ возвращается меньше чем за 50 мс;
    - `Timer.periodic` 10 мс на вызывающем isolate во время висящей записи не пропускает больше 50 мс подряд — UI isolate не блокирован;
    - `kill()` при висящей записи завершает процесс: `exitCode` завершается за 3 с; то же для `hangUp()`;
    - после `hangUp()`/`kill()` и после выхода `write` — no-op, без ошибок;
    - вторая вкладка во время висящей записи первой отвечает на `echo` (isolate не общий);
    - порядок: 100 нумерованных `write` в `cat` дают вывод в том же порядке;
    - служебная последовательность `pid` из обёртки старта не попадает в `output` (первый вывод `printf ok` — ровно `ok`);
    - `kill()` по-прежнему завершает `sh -c "trap '' HUP; exec sleep 100"` (D15, п. 6) — регрессия 1.5.

    Тест красный на текущем адаптере (запись блокирует вызывающий isolate);
  - **модульные тесты адаптера без PTY** там же: разбор служебной последовательности `pid` (нет за 2 с, мусор, `pid` ≤ 1 → `ptyUnavailable` и `SIGKILL` через `pty2`; последовательность снимается только с головы потока, позже — проходит в `output` как есть); сбой isolate (`onError`/`onExit` до `exited`) → `exitCode` с `UserShellIsolateFailure`, `output` закрыт; `Error` при старте в isolate → `UserShellRemoteError` с именем типа, без текста; принудительное `Isolate.kill` через 2 с после `kill()`, если код выхода не пришёл (шов: фабрика isolate или ядро `pty2` с подменой, по образцу 1.6a). Тест красный;
  - **тест Cubit** в `terminal_tabs_cubit_test.dart`: `UserShellRemoteError('StateError')` из `start` → `terminal.start_failed` с `error_type: StateError`; `exitCode` с `UserShellIsolateFailure` → `exited(null)` и `terminal.exit_wait_failed` (если уже зелёный — оставить как регрессионный). Красный;
  - **реализация** в `apps/codelab_desktop/lib/core/platform/user_shell_launcher.dart`: isolate на каждый shell, закрытые классы сообщений, очередь записи FIFO частями по 4 КБ с отдачей цикла событий, обёртка старта и разбор `pid`, сигналы по `pid` (`Process.killPid`) и сообщением, принудительное `Isolate.kill`, `UserShellIsolateFailure`, `UserShellRemoteError`; в Cubit — `error_type` из `errorType`. Порт `UserShellLauncher`/`UserShell` и `FakeUserShellLauncher` не меняются. Правило сторожа не нужно: `pty2` по-прежнему только в этом файле (D11). Комментарии по `AGENTS.md` §15 со ссылками на Q24 и D2 — тесты выше зелёные;
  - **ручная проверка на macOS**: вставка 200 КБ во вкладку с `stty raw -echo; sleep 30` — UI отзывчив, вкладка закрывается; повтор «Flood» по критериям 2.7–2.8 — лишний переход вывода через isolate не ухудшил худший кадр больше чем на 10 мс (иначе — запись в Risks и вопрос пользователю). Итог — в D15;
  - затем проверки шапки для app и `guard` (как в 2.11) и PR в `develop`.
