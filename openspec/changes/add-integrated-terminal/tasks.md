Задачи кода идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2; дорожная карта §9.1): сначала красный тест, затем код. В скобках — требование спецификации (`integrated-terminal` «…», сценарий) или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, правила сторожа для зависимостей app и документы app;
- `[client]` — задач нет: `codelab_client_core`, `codelab_client_io`, `codelab_client_acp` и `apps/codelab_cli` не меняются (D2, D10);
- `[protocol]`, `[agent]` — задач нет: ACP и агент не меняются.

Итерации — каждая отдельным pull request в `develop` (design.md, D14):
- 0 — решения пользователя по Q1–Q13 и документы;
- 1 — спайк зависимостей (ворота), технологический стек, сторож, порт и адаптер;
- 2 — feature `terminal`: Cubit, организм кита, панель в доке;
- 3 — клавиши, палитра, выход из app, приёмка.

Зависимости: 1 ← 0; 2 ← 1 (решение спайка 1.1); 3 ← 2. Если спайк 1.1 не прошёл ворота, итерации 2–3 не начинаются, вопрос возвращается пользователю (D14).

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

- [ ] 1.1 `[desktop]` Спайк — ворота итерации (D14). Каталог `apps/codelab_desktop/tool/terminal_spike/` (вне `lib/`, по образцу `apps/codelab_cli/tool/tui_spike/` change `add-cli-tui`). Проверить на macOS с Flutter из `.fvmrc`:
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
- [ ] 1.2 `[desktop]` `docs/architecture/technology-stack.md` §20г–§20д — финал по итогу 1.1: выбранный пакет, точная версия, транзитивные зависимости и лицензии, проверка по §24–§25 (D11; Q3 — без ADR). `THIRD_PARTY_NOTICES.md` и `licensing-and-attribution` не меняются (Q12); проверить только, что в коде change нет воспроизведённых фрагментов.
- [ ] 1.3 `[desktop]` Тест (workspace-architecture «Автоматический сторож границ пакетов»; D11): в `packages/dart/codelab_architecture_tests/test/import_guard_test.dart` правила `apps/codelab_desktop` под выбранный пакет. Для `xterm2`: `package:xterm2_core/` вне `features/terminal/`; `package:xterm2/` вне `features/terminal/presentation/`; `package:flutter/` в `features/terminal/application/`; PTY-пакет вне `core/platform/user_shell_launcher.dart`. Негативные тесты: `package:xterm2/` в `features/terminal/application/`, `package:xterm2_core/` в `features/workbench/`, PTY-пакет в `features/terminal/` → нарушение (красный). Для запасного `xterm` — вариант правил из D11.
- [ ] 1.4 `[desktop]` Добавить выбранные пакеты рендера (`xterm2` и `xterm2_core` либо `xterm`) и PTY точными версиями в `dependencies` `apps/codelab_desktop/pubspec.yaml`, выполнить `fvm dart run melos bootstrap`, правила в `test/support/rules.dart` с комментариями (почему, ссылка на D11) — 1.3 зелёный; `melos run guard` зелёный.
- [ ] 1.5 `[desktop]` Контрактный тест адаптера (`integrated-terminal` «Терминал — настоящий псевдотерминал», «Жизненный цикл процессов терминала»; D2, D13). При `pty2` — `apps/codelab_desktop/test/core/platform/user_shell_launcher_test.dart` на Dart VM, при `flutter_pty` — `integration_test/user_shell_launcher_test.dart` (только `release/*`). Проверяет:
  - `test -t 0 && test -t 1` → код `0`;
  - `cwd` соблюдается;
  - `tput cols` после `resize(100, 30)` → `100`;
  - `hangUp()` завершает `sh`;
  - `kill()` завершает `trap '' HUP; sleep 100`;
  - повторные `kill()` и `hangUp()` после выхода — без ошибок;
  - несуществующий исполняемый файл → `UserShellStartFailure` без пути в тексте;
  - `isSupported` на macOS — `true`.

  Тест красный.
- [ ] 1.6 `[desktop]` Реализовать порт `UserShellLauncher`, `UserShell`, `UserShellStartFailure` и адаптер на выбранном пакете в `apps/codelab_desktop/lib/core/platform/user_shell_launcher.dart`; `Platform.is*` только здесь (D2, D12). Комментарии по `AGENTS.md` §15 — 1.5 зелёный.
- [ ] 1.7 `[desktop]` Проверки итерации 1 (шапка) и PR итерации 1.

## 2. Feature terminal и панель в доке (итерация 2)

- [ ] 2.1 `[desktop]` Тест `apps/codelab_desktop/test/features/terminal/application/terminal_tabs_cubit_test.dart` с `FakeUserShellLauncher` и fake-временем (`integrated-terminal` «Вкладки терминала принадлежат папке проекта», «Рабочая папка вкладки терминала», «Жизненный цикл процессов терминала», «Содержимое терминала не покидает экран»; D3–D5, D9). Проверяет:
  - вкладки по папке проекта, переключение владельца без остановки процессов;
  - снимок `cwd` на момент создания, без проекта — `WorkingDirectoryProvider`;
  - несуществующая папка → `failed` без вызова `start`;
  - новая вкладка активна; 12 вкладок подряд создаются без отказа (предела нет, Q8);
  - закрытие вкладки и `closeAll()` во время `start`: поздний `UserShell` сразу получает `kill()` и в реестр не попадает (D4, «Старт в полёте»);
  - закрытие: `hangUp` → через 2 с `kill`, вкладка исчезает сразу;
  - `exit 3` → `exited(3)`, ввод игнорируется;
  - поздний вывод закрытой вкладки не меняет состояние;
  - `closeAll()`: `hangUp` всем, через 3 с `kill`, затем новые вкладки не создаются, повторный вызов — без действий;
  - после `close()` Cubit нет событий;
  - флаг предупреждения — один раз за жизнь Cubit;
  - события D9 в fake-логгере без путей, окружения и вывода.

  Тест красный.
- [ ] 2.2 `[desktop]` Реализовать `lib/features/terminal/application/`: `TerminalTabsCubit`, `TerminalTabsState`, закрытую иерархию `TerminalTabStatus`, реестр вкладок с моделью `Terminal` из `package:xterm2_core/xterm2_core.dart` (`maxLines` 10 000; буфер обмена выключен, D3) — 2.1 зелёный.
- [ ] 2.3 `[desktop]` Widget-тест `packages/flutter/codelab_ui/test/organisms/codelab_terminal_pane_test.dart` (D3). Проверяет:
  - ключи `terminal-tab-<id>`, `terminal-tab-close-<id>`, `terminal-new-tab`, `terminal-disclosure`;
  - тег статуса из переданной подписи и тона;
  - пустое состояние «New terminal»;
  - закрытие предупреждения вызывает колбэк;
  - содержимое из слота показывается для активной вкладки.

  Тест красный.
- [ ] 2.4 `[desktop]` Реализовать организм `CodeLabTerminalPane` в `codelab_ui/lib/src/organisms/`, экспорт в `organisms.dart`, пример в `codelab_organism_previews.dart`; запись в `packages/flutter/codelab_ui/AGENTS.md` §4 (без пакета рендера терминала, без логики) — 2.3 зелёный.
- [ ] 2.5 `[desktop]` Widget-тест `apps/codelab_desktop/test/features/terminal/presentation/terminal_pane_test.dart` с `FakeUserShellLauncher` (`integrated-terminal` «Панель Terminal в доке инструментов», «Терминал вне одобрений агента», «Восстановление дока не запускает shell», «Терминал только там, где есть PTY», «Содержимое терминала не покидает экран»; D1, D7, D12). Проверяет:
  - `tool-toggle-terminal` открывает `tool-pane-terminal` с одной вкладкой;
  - закрытие панели и повторное открытие сохраняют вкладку;
  - выбор сессии другого проекта показывает её вкладки;
  - восстановленный док (`DockLayoutStore` с `terminal`) — пустое состояние без вызова `start`;
  - `isSupported: false` — переключателя нет;
  - предупреждение при первом открытии и его нет после закрытия;
  - маркер вывода fake-shell не появляется в `LogBuffer`;
  - OSC 52 записи и чтения в выводе fake-shell не меняют `Clipboard` (mock `SystemChannels.platform`) и не дают ответа процессу.

  Тест красный.
- [ ] 2.6 `[desktop]` Реализовать:
  - `lib/features/terminal/presentation/` — привязку `TerminalView` (`package:xterm2/xterm.dart`) к модели вкладки, тему из `FluentTheme`, запись в эмулятор порциями не чаще кадра;
  - `CodeLabShell` — `ToolPane.terminal` в доступных панелях при `isSupported`, своя ветка `switch` вместо `_`;
  - маппер статуса вкладки в подпись и тон;
  - сборку `TerminalTabsCubit` в root scope и `CodeLabDependencies`, закрытие в `dispose` scope.

  Раздел «Терминал» в `apps/codelab_desktop/AGENTS.md`: где пакеты, владелец процессов, что не логируется, граница с `terminal/*`. 2.5 зелёный.
- [ ] 2.7 `[desktop]` Проверки итерации 2 (шапка) и PR итерации 2.

## 3. Клавиши, палитра, выход из app, приёмка (итерация 3)

- [ ] 3.1 `[desktop]` Тест `packages/flutter/codelab_ui/test/organisms/codelab_workbench_shortcuts_test.dart`: колбэки `onToggleTerminal` (Ctrl+`) и `onNewTerminalTab` (Ctrl+Shift+`) срабатывают с Control на любой платформе, не срабатывают с Meta, а `onNewTerminalTab` не срабатывает на `KeyRepeatEvent` (`includeRepeats: false`; D6, Q5, Q8). Тест красный.
- [ ] 3.2 `[desktop]` Реализовать колбэки в `CodeLabWorkbenchShortcuts` — 3.1 зелёный.
- [ ] 3.3 `[desktop]` Widget-тест `apps/codelab_desktop/test/features/terminal/presentation/terminal_keys_test.dart` (`integrated-terminal` «Клавиатура и палитра терминала»; D6). Проверяет:
  - Ctrl+` из композера открывает панель и фокусирует вкладку, повторное — возвращает фокус композеру;
  - Ctrl+Shift+` — новая вкладка;
  - фокус в терминале: Esc при идущем ходе не отправляет `session/cancel`, Ctrl+K при `debugDefaultTargetPlatformOverride = linux` не открывает палитру, а байты уходят fake-shell;
  - `/terminal` в палитре и inline-палитре открывает панель;
  - `/terminal` нет при `isSupported: false`;
  - команда агента `terminal` показана рядом с командой хоста.

  Тест красный.
- [ ] 3.4 `[desktop]` Реализовать:
  - `/terminal` в `CodeLabCommandAction.defaults` (кит) с фильтром по `isSupported` в `ui_mappers.dart`;
  - ветку `terminal` в `CodeLabShellCubit.selectCommand`;
  - перехват Ctrl+` и Ctrl+Shift+` в `TerminalView.onKeyEvent`;
  - привязку колбэков в `CodeLabShell`.

  Обновить тесты кита, считающие шесть команд палитры. 3.3 зелёный.
- [ ] 3.5 `[desktop]` Тест `apps/codelab_desktop/test/app/terminal_exit_test.dart` (`integrated-terminal` «Жизненный цикл процессов терминала», сценарий «Выход из приложения»; D4): обработчик выхода composition root вызывает `closeAll()` и возвращает `AppExitResponse.exit` не позже 3 с при зависшем fake-shell; закрытие root scope после этого не вызывает `start` и не бросает. Тест красный.
- [ ] 3.6 `[desktop]` Реализовать `AppLifecycleListener(onExitRequested:)` в `lib/app/`; правку `macos/Runner/AppDelegate.swift`, если спайк 1.1 показал, что запрос выхода не доходит до Flutter — 3.5 зелёный.
- [ ] 3.7 `[desktop]` `apps/codelab_desktop/integration_test/terminal_flow_test.dart` (приёмка D13): вкладка, `echo`, `tput cols`, закрытие вкладки без живого процесса, выход из app без сирот. В `feature/*` — только `fvm flutter analyze`; запуск на устройстве — в `release/<version>` (`AGENTS.md` §21).
- [ ] 3.8 `[desktop]` Документы DoD: `agent-parity-goals.md` D-28 — «закрыто change `add-integrated-terminal`» с тестами 2.5, 3.3, 3.7; A16 — ссылки на тесты; `delivery-roadmap.md` — статус строки.
- [ ] 3.9 `[desktop]` Удалить `apps/codelab_desktop/tool/terminal_spike/`. Проверки итерации 3 (шапка) и PR итерации 3.
- [ ] 3.10 `[desktop]` Архивирование change — только по просьбе пользователя, после merge итерации 3.
