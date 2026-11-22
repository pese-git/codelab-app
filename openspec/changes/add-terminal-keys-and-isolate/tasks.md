Задачи перенесены из change `add-integrated-terminal` при разделении 2026-11-23 с прежними номерами: на них ссылаются design.md того change, `docs/architecture/` и описания pull request. Пары «тест → реализация» (TDD: `CLAUDE.md`, раздел «Процесс», и ближайший `AGENTS.md` пакета задачи): сначала красный тест, затем код. В скобках — требование спецификации (`integrated-terminal` «…», сценарий) или решение design.md change `add-integrated-terminal` (D2–D15, Q24, Q25). Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, документы app;
- `[client]`, `[protocol]`, `[agent]` — задач нет: клиентский слой, ACP и агент не меняются.

Итерации — каждая отдельным pull request в `develop`; обе — после выпуска 1.0 (решение пользователя 2026-11-12):
- 3 — клавиши, палитра, приёмка;
- 4 — `pty2` в фоновом isolate вкладки (задача 2.13, решение Q24; Q25 решается до начала).

Зависимости: итерации 3 и 4 независимы и могут начинаться сразу — влитый терминал описан в `add-integrated-terminal`. Предусловие архивирования этого change: до него архивирован `add-integrated-terminal`, иначе в `openspec/specs/` нет требований `integrated-terminal`, которые меняет MODIFIED (design.md, D2).

Проверки — только затронутого (`AGENTS.md` §21):
- `fvm dart format --set-exit-if-changed` изменённых файлов;
- `fvm flutter analyze` и `fvm flutter test` в `apps/codelab_desktop` (можно сузить до `test/features/terminal/`, `test/features/workbench/`, `test/core/platform/`) и в `packages/flutter/codelab_ui`;
- `fvm dart run melos run guard` — при правке импортов app;
- `test:e2e:app:*` и `integration_test/` на устройстве — только в ветке `release/<version>`; в `feature/*` — только `fvm flutter analyze`;
- для `openspec/` — `openspec validate add-terminal-keys-and-isolate --strict`.

## 1. Внешние issue

- [ ] 1.8 `[desktop]` Завести issue в репозитории `pty2` (ссылка — в D15, п. 8 и 9, и в Risks), по одному на дефект или одним с разделами:
  - окно pid-reuse между `waitpid` в воркере и доставкой кода в главный isolate — pidfd или сигнал из воркера (Risks, «Окно между `waitpid` и доставкой кода»);
  - `alloc failed` после `fork`: мастер закрывается без `kill` и `waitpid`, ребёнок без владельца, зомби до выхода app (Risks, «Ребёнок без владельца»);
  - на macOS закрываются только fd < 4096 при `RLIMIT_NOFILE` > 65536 (Risks, «Утечка дескрипторов»);
  - блокирующий FFI `waitpid` (`exitCodeBlocking`) в isolate на каждый shell держит Dart VM при остановке движка (`WaitForApplicationIsolateShutdown`): штатный выход хоста зависает, пока жив shell, а shell ждёт закрытия PTY-мастера, то есть выхода хоста; `Isolate.kill` вызов не прерывает (D15, п. 9). Просьба — неблокирующее ожидание (`WNOHANG` с опросом, `SIGCHLD` или pidfd/kqueue) или явный `dispose`, который закрывает мастер и снимает ожидание. Описание — без путей пользователя и без отчёта целиком;
  - синхронный `write`: при `EAGAIN` он крутит `poll(100 мс)` на вызывающем isolate и держит его, пока программа не прочитает ввод. Просьба — асинхронная запись (или запись из воркера) и публичный `pid` (геттер уже есть, закомментирован); с ними уйдут обёртка старта ради `pid` и, возможно, isolate вкладки (решения Q24, Q25; D2, «Фоновый isolate вкладки»; Risks, «Синхронная запись в PTY»). Замер для issue — без путей: программа в raw-режиме без чтения stdin, `write` 4/64/200 КБ, ~7,5 с блокировки, буфер ввода PTY macOS ~1 КБ.

  Отдельно — issue в `xterm2_core`: флаг, выключающий ответ на CSI 21 t (отчёт заголовка окна), иначе текст OSC 2 из чужого вывода попадает во ввод shell (Risks, «Отчёт заголовка CSI 21 t в ввод shell»).

  Текст issue — без путей и данных пользователя. Внешнее действие: заводит пользователь или исполнитель по его разрешению.

## 3. Клавиши, палитра, приёмка (итерация 3) — после 1.0

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

  Если change `add-app-keyboard-page` уже влит: активаторы Ctrl+\` и Ctrl+Shift+\` объявляются записями каталога `CodeLabShortcut` (комбинация «только Control» по физической клавише расширяет `CodeLabKeyCombo`), получают тексты «Action» и «Where» в `app_en.arb` и `app_ru.arb`, строки страницы «Settings › Keyboard» и сценарии в тесте нажатий каталога. Иначе тест-сторож литералов активаторов падает (design.md `add-app-keyboard-page`, D3, D13).
- [ ] 3.7 `[desktop]` Приёмочный тест в `apps/codelab_desktop/integration_test/` (приёмка D13; имя `terminal_flow_test.dart` уже занято тестом ACP `terminal/*` агента — новый файл, например `user_terminal_flow_test.dart`, решение D3 этого change): вкладка, `echo`, `tput cols`, закрытие вкладки без живого процесса, выход из app без сирот. В `feature/*` — только `fvm flutter analyze`; запуск на устройстве — в `release/<version>` (`AGENTS.md` §21).
- [ ] 3.8 `[desktop]` Документы DoD: `agent-parity-goals.md` D-28 — «закрыто changes `add-integrated-terminal` и `add-terminal-keys-and-isolate`» с тестами 2.5 (`add-integrated-terminal`), 3.3, 3.7; A16 — ссылки на тесты; `delivery-roadmap.md` — статус строки.
- [ ] 3.9 `[desktop]` Удалить `apps/codelab_desktop/tool/terminal_spike/`. Проверки итерации 3 (шапка этого файла) и PR итерации 3.

## 4. `pty2` в фоновом isolate вкладки (итерация 4) — после 1.0

- [ ] 2.13 `[desktop]` `pty2` в фоновом isolate вкладки (решение Q24, 2026-11-12; D2, «Фоновый isolate вкладки»; D4, «Сигналы при висящей записи»; `integrated-terminal` «Жизненный цикл процессов терминала», сценарии «Вставка в программу, которая не читает ввод», «Закрытие вкладки при висящей записи», «Порядок ввода»). **Отложено на после 1.0** (решение 2026-11-12; номер сохранён — на него ссылаются design.md и документы). Источник `pid` — вариант (a) Q25; Q25 решается до начала задачи, при другом выборе задача правится. После merge итераций 1–2, отдельным PR (можно вместе с итерацией 3 или до неё). Пары — сначала красный тест, затем код:
  - **spec delta сначала**: требование ввода и сценарии «Вставка в программу, которая не читает ввод», «Закрытие вкладки при висящей записи», «Порядок ввода» уже в `specs/integrated-terminal/spec.md` этого change (MODIFIED «Жизненный цикл процессов терминала», текст — design.md change `add-integrated-terminal`, D4); сверить с решением Q25 и при другом выборе поправить; снять пометки «план после 1.0» в D2, D4, D13, Risks, `concurrency.md` §4.2, `technology-stack.md` §20д по мере реализации; `openspec validate add-terminal-keys-and-isolate --strict`;
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

## 5. Завершение

- [ ] 5.1 `[desktop]` Архивирование change — только по просьбе пользователя, после merge итераций 3 и 4 и после архивирования `add-integrated-terminal`.
