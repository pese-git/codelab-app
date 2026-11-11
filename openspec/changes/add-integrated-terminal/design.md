## Context

Редакция 2026-11-11 сверяет change с кодом `develop` (5e6e1254). Первая редакция (2026-08-25) опиралась на вещи, которых больше нет:
- архивный change `define-codelab-mvp`;
- поле `state.stdioCwd` — профили подключения больше не хранят рабочую папку;
- имя `AcpTerminalPanel`;
- «строку под лентой» рядом с решением «панель в доке».

**Что есть в коде сейчас.**

- **Док.** `CodeLabToolDock` (`packages/flutter/codelab_ui/lib/src/organisms/codelab_tool_dock.dart`) показывает вкладки открытых панелей и содержимое активной. Набором и шириной владеет `LayoutCubit` (`apps/codelab_desktop/lib/features/workbench/application/layout_cubit.dart`): `openPane`, `togglePane`, `closePane`. Раскладка сохраняется в `DockLayoutStore` (`lib/core/platform/dock_layout_store.dart`, ключи `codelab.dock.*`). `ToolPane.terminal` уже есть в enum. `CodeLabShell._availablePanes` пока содержит только `plan` и `protocol`, а ветка `_` в `switch` содержимого дока рисует Protocol для любой другой панели.
- **Процессы.** Процессы клиента сегодня — это:
  - процесс агента (`StdioAcpTransport`);
  - ACP `terminal/*` через порт `TerminalProcessRunner` (`codelab_client_acp`) и адаптер `IoTerminalProcessRunner` (`codelab_client_io`): `Process.start` без TTY, буфер вывода с `outputByteLimit`, `kill` — `SIGTERM`.

  Процессы `terminal/*` убивает `AcpClientApplication` при разрыве и `dispose` (`openspec/specs/acp-terminal-client/spec.md`).
- **Рабочая папка.** Папка новых сессий — `WorkspaceState.projectDirectory` (`ClientWorkspace.connect(projectDirectory:)`). У сессии своя `SessionHandle.cwd`. Без проекта — `WorkingDirectoryProvider.currentPath` (`codelab_client_io`), проверка существования — `DirectoryExists` / `ioDirectoryExists`.
- **Клавиши.** `CodeLabWorkbenchShortcuts` (`codelab_ui`) вешает `CallbackShortcuts` на всё рабочее место:
  - Cmd/Ctrl+K, N, B, `,` (палитра, новая сессия, сайдбар, настройки);
  - Esc (отмена хода или закрытие палитры);
  - Cmd/Ctrl+Enter, Cmd/Ctrl+Backspace (одобрение и отказ);
  - Alt+←/→ (инспектор).

  Ctrl+` и Ctrl+Shift+` свободны.
- **Палитра.** Палитра — `CommandCatalog` из `codelab_client_core`. Команды хоста — шесть `CodeLabCommandAction.defaults` из `codelab_ui`, сводятся в `HostCommand` в `ui_mappers.dart`. Выбор обрабатывает `CodeLabShellCubit.selectCommand`.
- **Выход из app.** `AppLifecycleListener` и перехвата закрытия нет. Root scope закрывается из `dispose` виджета `CodeLabBootstrap`. `AppDelegate` (macOS) завершает app после закрытия последнего окна.
- **Платформы.** У `apps/codelab_desktop` есть только `macos/`, песочница выключена (`com.apple.security.app-sandbox = false`).
- **Сторож.** В `rules.dart` нет правил для сторонних пакетов app. Прецедент ограничения стороннего пакета одним каталогом — правило `dart_tui` для `apps/codelab_cli/lib/src` с `exclude: ['tui/']` (change `add-cli-tui`, D3; `technology-stack.md` §20а, п. 5). Правила для markdown в репозитории нет.

**Проверка зависимостей (pub.dev API, 2026-11-11).** Пакеты не собирались, архивы `xterm`, `xterm2`, `xterm2_core`, `pty2` и `flutter_pty` просмотрены только чтением. Итоги, требующие сборки, помечены «не проверено».

Рендер терминала — пять кандидатов (решение Q2 — ниже):

| Пакет | Версия, дата | Лицензия | Зависимости | Наблюдения | Итог |
|---|---|---|---|---|---|
| `xterm2` | 5.4.0, 2026-10-21 | MIT | `characters`, `convert`, `meta`, `quiver` (Apache-2.0), `equatable`, `zmodem`, `xterm2_core`, Flutter SDK; Flutter `>=3.27`, Dart `>=3.6` | Форк `xterm` (copyright xuty), publisher `sofluffy.io`, около 5 тыс. загрузок за 30 дней. С 5.4.0 модель экрана (автомат, буферы, парсер, кодирование ввода) вынесена в `xterm2_core` 1.0.0 — чистый Dart, единственная зависимость `characters`, импортов `package:flutter` и `dart:ui` нет (проверено чтением архива). `TerminalView` импортирует `material.dart` — библиотеку SDK, как и `fluent_ui`. Есть `onKeyEvent` и `shortcuts`. OSC 52 и родственные записи в буфер обмена управляются `clipboardDecoder` (`null` — запись отклоняется), `allowITerm2ClipboardCapture` (по умолчанию `true`) и `allowKittyClipboard`. Активные выпуски 5.0–5.4 за 2026-07…10 | основной, проверяется спайком первым |
| `xterm` | 4.0.0, 2024-02-27 | MIT | `convert`, `meta`, `quiver` (Apache-2.0), `equatable`, `zmodem`, Flutter SDK; Flutter `>=3.19` | 239 лайков, около 255 тыс. загрузок за 30 дней. `package:xterm/core.dart` без Flutter. Обновлений больше 2,5 лет, совместимость с Flutter 3.47 (`.fvmrc`) не проверена | запасной |
| `xterm3` | 6.4.0, 2026-11-10 | **AGPL-3.0** | — | форк `xterm`; лицензия несовместима с MIT | исключён |
| `kterm` | 1.6.0, 2026-10-22 | MIT | `meta`, `image`, `zmodem_lbp`, `kitty_protocol`, Flutter SDK | kitty-протокол клавиатуры и графики; около 850 загрузок, разбор изображений из вывода процесса — лишняя поверхность | не выбран |
| `terminal_view` | 0.5.0, 2026-10-14 | MIT | `convert`, `meta`, `quiver`, `equatable`, `zmodem`, Flutter SDK | форк с рендером для мобильных, около 580 загрузок, отдельного чистого ядра нет | не выбран |

Вне пятёрки рассмотрен `termui_flutter` 0.10.3 (MIT, автор `pty2`, около 1,4 тыс. загрузок) — слишком молодой; не выбран.

PTY-бэкенд:

| Пакет | Версия, дата | Лицензия | Зависимости | Платформы | Наблюдения |
|---|---|---|---|---|---|
| `pty2` | 0.8.1, 2026-11-10 | MIT | `ffi`, `hooks`, `code_assets`, `native_toolchain_c`, `win32`, `crypto`, `path` | macOS, Linux, Windows | Чистый Dart (`sdk:dart`), C-код собирается хуком native assets при сборке. Нужен C-компилятор: Xcode CLT, `cc`/`gcc`. Dart `>=3.11`. Чтение в фоновых isolate. Unix — `forkpty` и `setsid`; Windows — ConPTY, есть опциональная загрузка ConPTY из NuGet. Ломающие версии 0.6–0.8 вышли за две недели. Около 35 тыс. загрузок за 30 дней. Форк `pty` (copyright xuty) |
| `flutter_pty` | 0.4.2, 2025-01-06 | MIT | `ffi`, Flutter SDK | macOS, Linux, Windows, Android, iOS | FFI-плагин Flutter: CMake, на macOS — podspec CocoaPods. В README сказано «experimental». Окружение — белый список (`LOGNAME`, `USER`, `DISPLAY`, `LC_TYPE`, `HOME`, `PATH`) плюс переданное, `LANG=en_US.UTF-8`. `kill` — `Process.killPid` по pid. Использует `Pointer.elementAt`, устаревший в Dart 3.3; сборка с текущим SDK не проверена. Библиотеку грузит `DynamicLibrary.open` из бандла app, поэтому под `flutter test` на хосте её нет. 24 лайка |
| `pty` | 0.2.2-pre (stable 0.1.1, 2021) | MIT | `ffi ^1`, `win32 ^2` | — | заброшен, Dart 2 — исключён |

## Goals / Non-Goals

**Goals:**
- Интерактивный shell пользователя с настоящим TTY во вкладках панели Terminal дока.
- Предсказуемый жизненный цикл: закрытие вкладки и выход из app завершают процессы; закрытие панели и смена проекта — нет.
- Явные и проверяемые границы: вне одобрений агента, вне журнала и редакции, вне ACP `terminal/*`.
- Новые зависимости ограничены одним каталогом каждая и закреплены сторожем.

**Non-Goals:**
- Передача ввода или вывода агенту (`!<cmd>` — только CLI, `12-6-cli-desktop-extras.md`).
- Паритет с системным терминалом. Терминал best-effort: полноэкранные программы должны работать (это причина PTY), но лигатуры, поиск по scrollback и профили shell не заявляются.
- «Maximize» и разбиение дока (Q10). Сохранение вкладок между запусками (Q6).
- Проверка на Linux и Windows: их сборок у app нет (D12).

## Decisions

### D1. Место — вкладка Terminal существующего дока

Панель — `ToolPane.terminal` в `CodeLabToolDock`. `CodeLabShell` добавляет её в `_availablePanes`, когда PTY доступен на платформе (D12). В `switch` содержимого дока у неё своя ветка вместо ветки по умолчанию `_`. Ширину задаёт общая ширина дока, открытием и закрытием панели владеет `LayoutCubit`, как у Plan и Protocol.

Отклонено:
- **строка под лентой** (первая редакция) — вторая система раскладки рядом с доком, конфликт с узким макетом, где док выдвигается поверх ленты;
- **пятый слот `CodeLabWorkbenchLayout`** — то же;
- **переключатель «Dock: Bottom / Right»** — две раскладки на одну панель, A16 его тоже отклоняет.

### D2. Слой процессов терминала — `lib/core/platform/` приложения

Порт `UserShellLauncher` и адаптер на PTY-пакете лежат в `apps/codelab_desktop/lib/core/platform/user_shell_launcher.dart`. Образец — `dock_layout_store.dart`: порт и реализация в одном файле, реализация на стороннем пакете остаётся в app. Порт узкий:
- `start(executable, args, cwd, env, columns, rows)` → `UserShell`;
- у `UserShell` — `output` (байты), `write`, `resize`, `exitCode`, `hangUp()`, `kill()`.

Ошибка старта — типизированный `UserShellStartFailure` (`error-handling.md`), без пути и окружения в тексте.

Почему не `codelab_client_io` с портом в `codelab_client_core` (`AGENTS.md` §13 «Пропорциональность»):
- **Один потребитель.** CLI сам работает в терминале, у него `!<cmd>` (`12-6-cli-desktop-extras.md`); web и мобильные клиенты процессов не имеют. Порт в kit был бы абстракцией «на вырост».
- **`flutter_pty` — Flutter-плагин.** `packages/dart/*` его не могут импортировать (`AGENTS.md` §5; правило `codelab_client_io` «без `package:flutter/`»).
- **`pty2` — native assets.** Хук сборки компилировал бы C-код для каждого потребителя `codelab_client_io`, в том числе для `codelab` CLI, которому PTY не нужен. Пришлось бы ещё расширять allowlist `codelab_client_io`.
- **Нет политики для kit.** В kit нет политики, которую стоило бы делить с CLI. Правила вкладок, предупреждение и жизненный цикл — UI-состояние одного app.

Порт нужен не ради второй реализации, а ради изоляции нативного API (`platform-integration.md` §8, §24, §73) и независимого тестирования `TerminalTabsCubit` с fake. Если появится второй потребитель, порт переедет в kit отдельным change.

Порт `TerminalProcessRunner` ACP не переиспользуется: у него другой контракт — буфер, `outputByteLimit`, без ввода и размера — и другой владелец (D10).

### D3. Feature `terminal`, владелец состояния и кит

- **`lib/features/terminal/application/`.** `TerminalTabsCubit` — единственный владелец вкладок. Он живёт в root scope, а не в виджете панели: процессы переживают закрытие панели (D4). Состояние — неизменяемое `TerminalTabsState`:
  - вкладки по владельцу (Q4: папка проекта);
  - активная вкладка владельца;
  - флаг «предупреждение показано» (Q7).

  Статус вкладки — закрытая иерархия `TerminalTabStatus`: `starting | running | exited(exitCode) | failed(reason)` (`AGENTS.md` §8). Набора флагов нет.
- **Реестр процессов вкладок.** Это не состояние Cubit. У каждой вкладки:
  - `UserShell`;
  - подписка на `output`;
  - модель эмулятора `Terminal` из `package:xterm2_core/xterm2_core.dart` (Q2). Если спайк выберет запасной `xterm`, то из `package:xterm/core.dart`.

  Модель эмулятора — это и есть scrollback и экран. Если пересоздавать её при каждом открытии панели, вывод терялся бы, а повтор сырых байт из усечённого буфера ломает состояние экрана: альтернативный экран, режимы.

  `xterm2_core` — отдельный пакет на чистом Dart (зависимость только `characters`, без Flutter и `dart:ui`), поэтому application не зависит от виджетов (`AGENTS.md` §6). Граница здесь сильнее, чем у `xterm`: там модель — библиотека внутри Flutter-пакета, и правило сторожа держит только путь импорта. У `xterm2` модель — отдельный пакет, и application физически не может импортировать виджеты через него.

  Предел scrollback — `maxLines` эмулятора (10 000 строк на вкладку); вывод в памяти, на диск не пишется.
- **Буфер обмена (реализация решения Q13).** Процесс терминала не получает доступа к буферу обмена через escape-последовательности: ни записи, ни чтения. `clipboardDecoder` не задаётся — запись OSC 52 отклоняется. `allowITerm2ClipboardCapture` и `allowKittyClipboard` выключены, обработчик чтения OSC 52 не задаётся. Почему: вывод — недоверенный поток (например, `cat` чужого файла или ответ `ssh`-сервера), и запись в буфер или его чтение без жеста пользователя — утечка или подмена данных. Выделение мышью и копирование и вставка действием пользователя (Cmd+C и Cmd+V на macOS) работают как обычно.
- **`lib/features/terminal/presentation/`.** Здесь `TerminalView` (`package:xterm2/xterm.dart`) для активной вкладки и тема из `FluentTheme` (`TerminalTheme`: цвета фона, текста, выделения, курсора; моноширинный шрифт кита). Material здесь не становится второй дизайн-системой (`technology-stack.md` §7).
- **`codelab_ui`.** Новый организм `CodeLabTerminalPane`:
  - строка вкладок — заголовок, тег статуса, крестик;
  - «+» (`terminal-new-tab`);
  - пустое состояние «New terminal»;
  - место для предупреждения (`terminal-disclosure`, `InfoBar`);
  - слот `content: Widget`.

  Кит не зависит от пакета рендера: виджет терминала передаёт app в слот (правила `codelab_ui/AGENTS.md` §1–§2). Что показать и в каком статусе вкладка, решает app. Текст и тон тега даёт маппер.
- **Отклонено:**
  - **состояние вкладок в `CodeLabShellState` / `LayoutCubit`** — фасад рабочего места не владеет процессами, а `LayoutCubit` — только раскладкой;
  - **рендер терминала в `codelab_ui`** — новая зависимость кита ради одного употребления;
  - **свой парсер ANSI** — большая поверхность ошибок (escape-последовательности, широкие символы, альтернативный экран).

### D4. Жизненный цикл процессов

- **Закрытие вкладки.** Сначала `hangUp()`: на POSIX — `SIGHUP` процессу shell, как при закрытии окна терминала; интерактивный shell передаёт его своим заданиям. Если shell не вышел за 2 с — `kill()` (`SIGKILL`). На Windows `kill()` сразу. Вкладка удаляется из состояния сразу, процесс доживает в реестре до выхода. Повторное закрытие и закрытие уже вышедшего процесса — без ошибок (`concurrency.md` §23–§24).
- **Shell вышел сам** (`exit`, Ctrl+D). Вкладка остаётся со статусом `exited(code)` и строкой `[Process exited with code N]` в эмуляторе, пока пользователь её не закроет. Ввод в такую вкладку игнорируется.
- **Старт в полёте.** `start` асинхронный, вкладка до его конца — `starting`. Предела числа вкладок нет (Q8), поэтому защита — не счётчик, а владение результатом: у каждой вкладки свой id, выданный синхронно в момент действия, и `UserShell`, вернувшийся из `start`, принимается только если вкладка с этим id ещё в состоянии `starting`. Если её успели закрыть или начался `closeAll`, поздний `UserShell` сразу получает `kill()` и в реестр не попадает (`concurrency.md` §10, stale result). Каждое действие пользователя создаёт ровно одну вкладку; быстрые повторы дают столько вкладок, сколько было действий, а повтор клавиши при удержании отсекается на уровне сочетания (D6).
- **Закрытие панели в доке, смена проекта, смена сессии** процессы не трогают. Вывод продолжает писаться в модель эмулятора.
- **Выход из app.** `AppLifecycleListener(onExitRequested:)` в composition root (`lib/app/`) вызывает `TerminalTabsCubit.closeAll()`. Тот делает `hangUp` всем, ждёт до 3 с, затем `kill` оставшимся и возвращает `AppExitResponse.exit`. Тот же `closeAll()` вызывает закрытие root scope, повторный вызов ничего не делает. Отмены выхода нет (подтверждение — Q11). Последовательность — `concurrency.md` §45–§46: новые вкладки после начала выхода не создаются.
- **Страховочная сеть.** Если app упал или убит, PTY-мастер закрывается вместе с процессом app. Ядро шлёт `SIGHUP` сеансу shell (`setsid` в PTY-бэкенде), так что сиротами остаются только намеренно отвязанные задания (`nohup`, `disown`) — это поведение пользователя, а не утечка (`platform-integration.md` §23). У варианта без PTY (Q1 (b)) этой сети нет.
- **Не проверено:** доходит ли `onExitRequested` на macOS при Cmd+Q и закрытии последнего окна (`applicationShouldTerminateAfterLastWindowClosed`). Это пункт спайка итерации 1. Если не доходит, в `AppDelegate` добавляется вызов выхода через Flutter, это отдельная задача итерации 3.
- **События.** `terminal.tab_opened`, `terminal.tab_exited`, `terminal.tab_closed`, `terminal.start_failed`, `terminal.close_all` (D9).

### D5. Рабочая папка и окружение

- **Папка.** Папка новой вкладки — снимок в момент создания. Это папка владельца (Q4: `WorkspaceState.projectDirectory`), без проекта — `WorkingDirectoryProvider.currentPath`. Папка проверяется `DirectoryExists`. Если её нет, вкладка получает `failed`, процесс не стартует, текст — «Folder not found» без пути. Обратной связи нет: `cd` внутри shell не меняет ни проект, ни сессию, ни профиль.
- **Shell и окружение** — решение Q9:
  - macOS и Linux — `$SHELL` с `-l`. Login shell восстанавливает `PATH` из профиля пользователя: app из Finder получает минимальное окружение, см. `apps/codelab_desktop/AGENTS.md` «Секреты». Без `$SHELL` — `/bin/zsh` на macOS, `/bin/bash`, затем `/bin/sh`;
  - Windows — `%ComSpec%`.

  Окружение — окружение процесса app целиком плюс `TERM=xterm-256color`, `COLORTERM=truecolor`. Это осознанное отступление от `platform-integration.md` §53 «передавать только необходимое»: терминал — собственный shell пользователя, урезанное окружение сломало бы его инструменты. Отступление записывается в §52–§53 (итерация 0).
- **Размер.** Размер PTY — от `TerminalView` (`autoResize` → `resize(columns, rows)`).

### D6. Клавиши, фокус и палитра

- **Ctrl+`** на всех платформах (решение Q5) — сочетание рабочего места:
  - фокус вне терминала: открыть панель Terminal и активировать её, при отсутствии вкладок создать одну, отдать фокус активной вкладке;
  - фокус в терминале: вернуть фокус композеру, панель остаётся открытой.

  Это смысл A16, шаг 2. A13, шаг 3 («повторное сочетание закрывает панель») для Terminal уточняется: закрывает панель переключатель app bar или крестик вкладки дока.
- **Ctrl+Shift+`** — новая вкладка у текущего владельца. Предела числа вкладок нет (решение Q8). Повтор клавиши при удержании не создаёт вкладки: сочетание привязывается с `includeRepeats: false`, иначе удержание Ctrl+Shift+` за секунду запустило бы десятки shell.
- **Клавиши в терминале.** Пока фокус в `TerminalView`, клавиши получает shell, в том числе Esc, Ctrl+C, Ctrl+K, Ctrl+N, Ctrl+B, Ctrl+D. Сочетания рабочего места с Ctrl на Linux и Windows в терминале не срабатывают — так устроен порядок обработки клавиш Flutter: фокус → предки. Два сочетания терминала перехватываются раньше эмулятора через `TerminalView.onKeyEvent`. На macOS сочетания с Cmd остаются за app (Cmd+K, Cmd+N, Cmd+,), Cmd+C и Cmd+V — копирование и вставка терминала.
- **Палитра.** Команда хоста `/terminal` («Terminal», «Open the terminal panel.») в `CodeLabCommandAction.defaults` делает то же, что Ctrl+` вне терминала. Она доступна, только если платформа поддерживает PTY. Иначе её нет в каталоге: «панель без данных не предлагается», A13, шаг 6; заглушка «coming soon» здесь не нужна, потому что действие не «ещё не сделано», а невозможно. Одноимённая команда агента `terminal` показывается рядом — правило D3 `add-command-palette-agent-commands`. Inline-палитра композера ведёт себя так же.
- **Ключи тестов:** `tool-pane-terminal`, `tool-toggle-terminal`, `terminal-tab-<id>`, `terminal-tab-close-<id>`, `terminal-new-tab`, `terminal-disclosure`, `palette-item-terminal` (A16, шаг 7).

### D7. Состояние панели и восстановление дока

Панель закрыта по умолчанию: при первом запуске `openPanes` пуст. Открытая панель сохраняется в `codelab.dock.*`, как остальные: это правило дока, а не терминала.

Вкладки и процессы между запусками не сохраняются (Q6). Если док восстановил открытую панель Terminal, она показывает пустое состояние «New terminal». Shell без действия пользователя не запускается: старт app не должен порождать процессы. Открытие панели действием пользователя — переключатель, Ctrl+`, `/terminal` — при пустом владельце создаёт одну вкладку.

### D8. Граница с одобрениями агента и permissions

`approval-safety` (`openspec/specs/approval-safety/spec.md`: «Уровни риска», «Режимы разрешений», «Поток разрешений ACP») классифицирует и одобряет **действия агента**. `permissions.md` §2 относит «shell/process execution» к чувствительным операциям, и `platform-integration.md` §52 требует для shell permission policy.

Терминал пользователя — действие человека с его правами. Policy app не решает, можно ли человеку набрать команду. Поэтому:
- команды терминала не проходят через одобрения, режимы разрешений и классификацию риска;
- рабочая папка не ограничивает shell. Containment `AGENTS.md` §10 — компенсирующий контроль для `fs/*` и `terminal/*` **агента**, а у пользователя `cd` за пределы проекта — нормальная работа;
- агент панель не видит и управлять ей не может (D10);
- предупреждение при первом открытии (Q7) говорит, что команды идут вне одобрений агента, а вывод не редактируется.

Это записывается в `permissions.md` §2 рядом с исключением `fs/*` и `terminal/*` и в `platform-integration.md` §52 как явное решение, а не пробел (итерация 0).

### D9. Граница с журналом и редакцией

`approval-safety` «Редактирование секретов» и `structured-logging` «Маскирование секретов в structured-выводе» требуют редактировать секреты в журнале, диагностике, инспекторе и debug-состоянии. Редактировать произвольный поток интерактивного процесса нельзя: подмена байт сломала бы экран и ввод паролей.

Поэтому содержимое терминала в эти места не попадает вовсе. Ввод и вывод НЕ ДОЛЖНЫ уходить:
- в `Logger`, `LogBuffer` и debug log;
- в `structured_log_remote_sync`;
- в `WorkspaceDiagnostic` и инспектор;
- в снимок рабочего места;
- к агенту.

Заголовок вкладки из OSC 0/2 показывается только в UI, обрезанный до 64 символов, и тоже не логируется.

События — логгер `codelab_desktop.terminal`, компонент `terminal`:
- `terminal.tab_opened` — `tab_id`, `shell` (базовое имя исполняемого файла), `columns`, `rows`;
- `terminal.tab_exited` — `tab_id`, `exit_code`;
- `terminal.tab_closed` — `tab_id`, `forced` (понадобился ли `kill`);
- `terminal.start_failed` — `tab_id`, имя типа ошибки;
- `terminal.close_all` — `count`, `forced`.

Путей, окружения, аргументов, ввода, вывода и `toString()` исключений в событиях нет (`observability.md` §43–§45). Проверка — тест: вывод с маркером не появляется в `LogBuffer`.

### D10. Граница с ACP `terminal/*`

| | Терминал пользователя (этот change) | ACP `terminal/*` (`acp-terminal-client`) |
|---|---|---|
| Кто запускает | человек в панели | агент запросом `terminal/create` |
| Порт и адаптер | `UserShellLauncher` (app, `lib/core/platform/`) | `TerminalProcessRunner` (`codelab_client_acp`) / `IoTerminalProcessRunner` (`codelab_client_io`) |
| TTY | PTY | нет, `Process.start` |
| Владелец | `TerminalTabsCubit`, владелец вкладок — папка проекта | `AcpClientApplication`, реестр `SessionId → TerminalId` |
| Где виден | панель Terminal дока | строка инструмента в ленте (A16, шаг 5; §12.1.6) |
| Одобрение | нет — действие человека (D8) | на усмотрение агента (`AGENTS.md` §10) |
| Containment | нет | путь и `cwd` в пределах папки сессии (`AGENTS.md` §10) |
| Завершение | закрытие вкладки, выход из app (D4) | `terminal/kill`, `terminal/release`, разрыв, `dispose` |

Ни один из них не знает о другом. Терминал агента не открывается вкладкой панели, вкладка пользователя не получает `TerminalId` и не уходит в протокол. Методов, полей и semantics ACP change не добавляет.

В `acp-terminal-client` требование «Изоляция process execution за platform-boundary» ссылается на `TerminalProcessFactory` — такого типа не было и не будет. Ссылка заменяется на `UserShellLauncher` (MODIFIED в `specs/acp-terminal-client/spec.md`), то же в `concurrency.md` §44. Сценарий требования («порт, реализуемый в `apps/codelab_desktop`») устарел — адаптер давно в `codelab_client_io`. Он переносится без изменений, чтобы не расширять объём; правка — отдельной задачей вне этого change.

### D11. Зависимости и сторож

- **Зависимости.** Они попадают только в `dependencies` `apps/codelab_desktop/pubspec.yaml`, пины точных версий без `^`, как у `structured_log` (`technology-stack.md` §17.1):
  - рендер терминала — `xterm2` и его `xterm2_core` (Q2), запасной — `xterm`;
  - PTY-пакет — `pty2`, запасной — `flutter_pty` (Q1).

  В `pubspec.yaml` попадает только выбранный спайком пакет каждой пары; оба пакета рендера одновременно не подключаются.

  `codelab_ui`, `codelab_client_*` и пакеты агента их не получают. `desktopAllowlist` (`pubspec_allowlist_test.dart`) проверяет только `codelab_*` и не меняется.
- **Правила `rules.dart`** — по образцу `dart_tui`, `sealExclude: false`:
  1. `apps/codelab_desktop/lib` — `package:xterm2_core/` запрещён, `exclude: ['features/terminal/']`;
  2. `apps/codelab_desktop/lib` — `package:xterm2/` запрещён, `exclude: ['features/terminal/presentation/']`: виджеты только в presentation, application получает модель из `xterm2_core`;
  3. `apps/codelab_desktop/lib/features/terminal/application` — `package:flutter/` запрещён;
  4. `apps/codelab_desktop/lib` — `package:<pty-пакет>/` запрещён, `exclude: ['core/platform/user_shell_launcher.dart']`.

  Если спайк выберет запасной `xterm`, правила 1–2 сводятся к двум: `package:xterm/` вне `features/terminal/` и `package:xterm/ui.dart`, `package:xterm/xterm.dart` в `features/terminal/application/` — модель в этом случае берётся из `package:xterm/core.dart`.

  Негативные тесты на каждое правило — в `import_guard_test.dart`.
- **Граф.** Нового пакета нет, граф `README.md` не меняется: на нём только пакеты `codelab_*`.
- **Технологический стек.** В `technology-stack.md` — разделы `20г` (рендер терминала) и `20д` (PTY) по §27, с проверкой по §24–§25. ADR не пишется (решение Q3) — по прецеденту `dart_tui` (§20а, п. 8): технология затрагивает одну feature одного app и не меняет границ пакетов, state management и ACP. В итерации 0 разделы записаны с кандидатами; выбор, версии и транзитивные лицензии — после спайка (задача 1.2).
- **Лицензии.** Выбранные кандидаты — MIT, транзитивный `quiver` — Apache-2.0; `xterm3` (AGPL) исключён. Полный список транзитивных зависимостей выбранных пакетов с лицензиями по `pubspec.lock` составляет спайк (задача 1.1) и записывает в раздел `technology-stack.md` (задача 1.2). Уведомления пакетов попадают в `LicenseRegistry` сборки Flutter.

  `THIRD_PARTY_NOTICES.md` и спецификация `licensing-and-attribution` не меняются (решение Q12): реестр — для фрагментов, которые близко воспроизводят внешний код, а зависимости pub.dev с лицензиями ведутся в `technology-stack.md` §20г–§20д. Задача 1.2 проверяет, что в коде change нет воспроизведённых фрагментов.

### D12. Платформы и capability

Адаптер сообщает `UserShellLauncher.isSupported`: `true` на macOS, Linux и Windows, где PTY-пакет собран; `false` иначе.

При `false`:
- переключатель Terminal не показывается;
- `/terminal` отсутствует в палитре;
- Ctrl+` ничего не делает.

Это правило «панель без данных не предлагается» (A13, шаг 6). Проверка `Platform.is*` есть только в адаптере (`AGENTS.md` §11). Сейчас app собирается только под macOS. Linux и Windows проверяются, когда у app появятся их сборки; до тех пор они в спецификации не заявлены.

### D13. Тесты

- **Dart VM без устройства.** Это всё, что гоняется в `feature/*` (`AGENTS.md` §21).
  - `TerminalTabsCubit` с `FakeUserShellLauncher`: вкладки по владельцу, снимок папки, несуществующая папка, закрытие (`hangUp` → 2 с → `kill`, fake-время), закрытие вкладки и `closeAll` во время `start` (поздний `UserShell` получает `kill`), `closeAll` с таймаутом, вышедший сам shell, поздний вывод закрытой вкладки не меняет состояние, после `close()` Cubit — без событий.
  - Widget-тесты `CodeLabTerminalPane` (кит) и панели в доке (app) с fake-эмулятором: ключи, предупреждение, пустое состояние, переключатель, Ctrl+`, `/terminal`, Esc в терминале не отменяет ход.
  - Тест журнала: маркер вывода не появляется в `LogBuffer`.
  - Правила сторожа.
- **Контрактный тест адаптера** (настоящий PTY: `test -t 0`, `tput cols`, `resize`, `hangUp`, `kill`) — по итогу Q1:
  - `pty2` — native assets собираются и под `flutter test` на хосте, тест идёт на Dart VM в `feature/*`. Это пункт спайка;
  - `flutter_pty` — библиотека есть только в бандле app, поэтому тест живёт в `integration_test/` и идёт только в `release/*` (`AGENTS.md` §21). В `feature/*` адаптер прикрыт только анализом.
- **Устройство** — `integration_test/terminal_flow_test.dart` (вкладка, `echo`, закрытие, выход из app) — только `release/<version>`.

### D14. Итерации

Каждая итерация — отдельный pull request в `develop`:
- **0** — решения пользователя по Q1–Q11 и документы;
- **1** — спайк зависимостей, сторож и порт с адаптером;
- **2** — feature `terminal` (Cubit, кит, панель в доке) без входа с клавиатуры и палитры;
- **3** — клавиши, палитра, выход из app, приёмка.

Итерация 1 — ворота: если ни один PTY-пакет не собирается на macOS с Flutter 3.47 или несовместимы оба пакета рендера (`xterm2` и `xterm`), работа останавливается, и вопрос возвращается пользователю. Тихого перехода на вариант без PTY нет.

## Risks / Trade-offs

- **Секреты на экране** (`cat .env`). Экран не защищён. Мера — предупреждение (Q7) и то, что содержимое никуда не уходит с экрана (D9). Пользователь, который не прочитал предупреждение, может считать терминал защищённым — это риск принимается.
- **Молодой форк `xterm2`** (один publisher, около 5 тыс. загрузок, 5.x вышли за четыре месяца). Мера — спайк итерации 1, пин точной версии, узкая привязка в `features/terminal/presentation/` (D11). Запасной вариант — `xterm` 4.0.0 (не обновлялся с 2024-02): API тот же, замена касается импортов одной feature. `xterm3` исключён из-за AGPL.
- **Нестабильный `pty2`** (ломающие версии 0.6–0.8 за две недели) или «experimental» `flutter_pty` без обновлений с 2025-01. Меры:
  - пин точной версии;
  - узкий порт D2, замена пакета не трогает feature;
  - обновление — отдельный PR с контрактным тестом адаптера.
- **Сборка.** `pty2` требует C-компилятор: на macOS — Xcode CLT, они нужны и Flutter, на CI Linux — `cc`. `flutter_pty` на macOS — CocoaPods, `Podfile` у app уже есть.
- **Нагрузка на UI isolate.** Чтение PTY идёт в фоновом isolate (`pty2`) или потоке (`flutter_pty`), но разбор в эмуляторе (`xterm2_core`) — на UI isolate. Поток вроде `cat` большого файла может давать рывки (`AGENTS.md` §12). Мера — запись в эмулятор порциями не чаще кадра; замер в спайке.
- **Сироты** при крахе app без PTY-сеанса. Закрывается выбором PTY (D4); у варианта (b) остаётся.
- **Клавиатурные раскладки.** На раскладках, где `` ` `` — другой символ (например, «ё» в русской), `LogicalKeyboardKey.backquote` может не совпасть. Мера — проверка в спайке; при расхождении — физическая клавиша (`PhysicalKeyboardKey.backquote`).
- **Cmd+` на macOS** — системное «следующее окно приложения», поэтому выбрано Ctrl+` на всех платформах (Q5).
- **Вставка нескольких строк** выполняет команды сразу. Защищает bracketed paste эмулятора, но не все shell его включают. Это поведение системных терминалов, принимается.

## Migration Plan

Миграции нет: данных и настроек терминала раньше не было. Ключи `codelab.dock.*` уже понимают `terminal` (`ToolPane.values.asNameMap()`). Откат — удаление панели из `_availablePanes`: сохранённая раскладка с `terminal` при чтении просто пропустит её.


## Решения пользователя 2026-11-11

Вопросы Q1–Q13 ставила редакция change от 2026-11-11 (варианты и рекомендации — в разделах D и Risks). Пользователь ответил в тот же день; ниже — вопрос и ответ, решения D уже приведены к ответам.

- **Q1. PTY-стратегия** → (a) настоящий PTY. Итерация 1 — спайк: сначала `pty2`, при неудаче `flutter_pty`. Если не соберётся ни один — стоп и вопрос пользователю. `Process.start` без PTY и обёртка `script` не берутся (D2, D14).
- **Q2. Рендер терминала** → основной — `xterm2` (модель экрана — чистый `xterm2_core`), запасной — `xterm` 4.0.0. Пин точной версии; правила сторожа — под выбранный пакет; транзитивные зависимости и лицензии — в задаче спайка. Сравнение пяти кандидатов — в разделе Context (D3, D11).
- **Q3. ADR для PTY** → без ADR, разделы в `technology-stack.md` (D11).
- **Q4. Чьи вкладки** → вкладки принадлежат папке проекта (D3, D5).
- **Q5. Сочетание** → Ctrl+` на всех платформах, Ctrl+Shift+` — новая вкладка (D6).
- **Q6. Сохранение между запусками** → вкладки не сохраняются (D7).
- **Q7. Предупреждение** → раз за запуск app, закрывается крестиком. Текст: «Commands here run as you, outside the agent's approval flow. Output is shown as is and is not redacted for secrets.» (D8).
- **Q8. Сколько вкладок** → без предела. Защита от гонок — не счётчик, а владение результатом старта и `includeRepeats: false` у сочетания (D4, D6).
- **Q9. Shell и окружение** → `$SHELL -l` и окружение app целиком плюс `TERM` и `COLORTERM`; отступление от `platform-integration.md` §53 записано явно (D5).
- **Q10. Объём A16** → «Maximize» и разбиение дока вне этого change.
- **Q11. Подтверждение** → без подтверждения при закрытии вкладки и выходе из app (D4).
- **Q12. Учёт зависимостей и лицензий** → (a) список зависимостей и лицензий ведётся в `technology-stack.md` §20г–§20д; `THIRD_PARTY_NOTICES.md` и спецификация `licensing-and-attribution` не меняются (D11).
- **Q13. Буфер обмена через escape-последовательности** (OSC 52 и родственные OSC 1337, 5522) → запретить и чтение, и запись. Выделение мышью и Cmd+C/Cmd+V работают (D3, «Буфер обмена»; `integrated-terminal` «Содержимое терминала не покидает экран»).

## Open Questions

Открытых вопросов нет. Остаются проверки спайка итерации 1 (задача 1.1); если спайк не пройдёт ворота D14, вопрос вернётся пользователю.
