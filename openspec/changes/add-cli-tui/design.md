## Context

Полноэкранный режим `codelab --ui tui` — цель U-12 (Should) матрицы целей. Источники решений:
- `docs/architecture/proposals/dart-agent-and-clients/12-2-cli-display-and-input.md`:
  - §12.2.7 — архитектура Model–Update–View, цикл `Program`, раскладка кадра, чек-лист разведки;
  - §12.2.6 — статус-строка;
  - §12.2.9 — реестр клавиш;
  - §12.2.11 — инварианты TUI-1–TUI-11;
  - §12.2.12 — обоснование и риски `dart_tui`;
  - §12.2.13 — `cli/tui-smoke`;
- technology-stack §20а — `dart_tui` утверждён для `lib/src/tui/`;
- `09-11-stage-6-cli-mvp.md` — флаг `--ui`, клавиши, одобрение.

Что уже есть (change `add-codelab-cli`, архив `2026-10-28-add-codelab-cli`):
- **REPL.** `Repl`, `ReplSession`, `ReplCommand` и `ReplContext`, `mvpReplCommands`, `CommandRouter` (маршрут строки, дополнение Tab), `ApprovalPrompt.optionFor` (y/a/n/N).
- **Рендер.** `toolRow` / `isFinalToolCall`, `sanitize.dart`, `ansi.dart`, `OutputSurface`, `noticeText`, `ThoughtsMode`.
- **Ввод.** `KeyDecoder`, `KeyBindings.mvp`, `LineEditor`, `History` / `HistoryFile`.
- **Сессия.** `openCliSession` и `session_setup.dart`: открытие по `--resume`/`--continue`, `--model`/`--mode`.
- **Kit.** `SessionView`: `transcript`, `queue`, `configOptions`, `agentCommands`, `pendingApprovals`, `plan`, `status`, `revision`.

Итог разведки 6.11 — ниже (D14). Пакет подтверждён.

## Goals / Non-Goals

**Goals:**
- `codelab --ui tui` даёт рабочее место в альтернативном экране:
  - транскрипт с прокруткой и следованием;
  - композер на несколько строк;
  - зона одобрения;
  - пикеры;
  - строка подсказок;
  - статус-строка.

  Поведение хода, команд, очереди и одобрения — то же, что в REPL, потому что логика одна (kit и общие `ReplCommand`).
- Ядро экрана — чистые функции, проверяемые модульными тестами на кадрах без терминала и без `dart_tui` (TUI-5).
- Терминал восстанавливается при любом выходе (TUI-4).
- Замена `dart_tui` затрагивает только четыре файла адаптера.

**Non-Goals:**
- мышь и `/mouse` (U-22);
- ANSI-markdown (U-10), diff правок (U-11);
- вложения и `@` (U-14), дополнение путей (U-24);
- несколько сессий (U-37), копирование (U-28);
- `/terminal-setup` (остаток U-23), `cli.yaml`, темы, локализация;
- `/inspect` и подробности вызова;
- статус-строка с usage, стоимостью и веткой (U-13: в kit нет данных);
- TUI по умолчанию.

## Decisions

### D1. Объём

Решение владельца проекта: U-12 и часть U-23 в TUI.
- **Часть U-23:** bracketed paste; Shift+Enter, где терминал различает его; Alt+Enter и `\` + Enter.
- **Пикеры:** `/model`, `/mode`, `/sessions`.
- **Строка подсказок клавиш.**

Остальное — в Non-Goals, каждое своим change. Режим по умолчанию остаётся `line`. TUI становится умолчанием только после приёмки на Linux и Windows (§12.2.12, D14, пункт 7).

### D2. Раскладка `lib/src/tui/`

```text
apps/codelab_cli/lib/src/tui/
├── core/                      # чистое ядро: без package:dart_tui и dart:io (TUI-5)
│   ├── tui_model.dart         # TuiModel, ComposerState, ScrollState, OverlayState, TerminalSize
│   ├── tui_msg.dart           # sealed TuiMsg
│   ├── tui_cmd.dart           # sealed TuiCmd — данные
│   ├── tui_update.dart        # reduce(model, msg) → (model, List<TuiCmd>)
│   ├── tui_view.dart          # render(model, chrome) → Frame
│   ├── tui_chrome.dart        # TuiChrome: готовые строки компонентов dart_tui (D12)
│   ├── frame.dart             # Frame: строки и курсор; fitLine — ширина и сброс атрибутов
│   ├── transcript_lines.dart  # TranscriptItem → строки; кэш переносов
│   ├── composer.dart          # многострочный редактор: курсор 2D, история
│   └── status_line.dart       # сегменты §12.2.6, доступные без usage
├── tui_app.dart               # TuiApp implements Model (dart_tui); компоненты SpinnerModel, ListModel, HelpModel
├── registry_key_map.dart      # RegistryKeyMap implements KeyMap: реестр клавиш → HelpModel (TUI-7)
├── tui_input.dart             # сообщения dart_tui → TuiMsg через реестр клавиш
├── tui_effects.dart           # TuiCmd → Cmd dart_tui; единственный владелец SessionHandle в TUI
├── tui_command_context.dart   # ReplContext для TUI: вывод команд — заметки в транскрипт
└── tui_runner.dart            # Program, подписки на kit, восстановление терминала
```

Почему ядро в `core/`, а не в файлах `tui_model.dart` и др. рядом с адаптером, как в §12.2.7: правило сторожа «`package:dart_tui/` только из `lib/src/tui/`, но не из `lib/src/tui/core/`» выражается одним `exclude` по каталогу. Список файлов в правиле устаревал бы при каждом новом файле ядра. §12.2.7 правится этим change.

### D3. Зависимость и сторож

- **Зависимость.** `dart_tui: ^3.0.0` в `dependencies` `apps/codelab_cli`; точная версия — в `pubspec.lock` (§12.2.12, мера 2). Пакет уже утверждён technology-stack §20а, новых технологий стека нет. `cliAllowlist` пополняется `dart_tui`.
- **Правила сторожа** (вместо комментария-заготовки в `rules.dart`):
  - `PackageRule('apps/codelab_cli/lib/src', forbidden: ['package:dart_tui/'], exclude: ['tui/'])`;
  - `PackageRule('apps/codelab_cli/lib/src/tui/core', forbidden: ['package:dart_tui/', 'dart:io'])`.
- **Транзитивные зависимости** `characters`, `ffi`, `path` в allowlist не вносятся: allowlist проверяет только прямые `dependencies`.

### D4. Флаг `--ui` и выбор режима

- `--ui line|tui`, по умолчанию `line`.
- `run.dart` после разбора выбирает режим так:
  - headless (`-p`, `-f`, промпт из stdin);
  - REPL;
  - TUI.
- Подключение и открытие сессии общие — `openCliSession`. `TuiRunner.run` получает уже открытую `SessionHandle`, как `Repl`.
- Коды `64`:
  - `--ui tui` вместе с `-p`/`-f` — `--ui applies only to the interactive mode`;
  - stdin или stdout не TTY — `--ui tui needs a terminal on stdin and stdout`;
  - неизвестное значение — `Invalid value for --ui`.

  Агент при этих кодах не запускается.
- Первое сообщение (позиционные аргументы) отправляется сразу, как в REPL.

### D5. Чистое ядро

`TuiModel` неизменяема и хранит:
- последний `SessionView` и `WorkspaceState`;
- `ComposerState` (строки, курсор, позиция в истории);
- `ScrollState` (`offsetFromBottom`, `follow`, `newSinceHold`);
- `OverlayState?` — открытый пикер или список дополнений как `PickerSpec` (что выбирается и какая команда исполнится); навигацию и фильтр держит компонент адаптера (D12);
- `TerminalSize`;
- `turnStartedAt` — начало идущего хода, для времени в статус-строке;
- локальные заметки клиента `notes` (вывод команд, вставленный после элемента транскрипта с индексом на момент вывода);
- `ThoughtsMode`;
- `exitArmedAt` (двойной Ctrl+C);
- `errorStreak`.

`TuiMsg`:
- `KeyMsg(Key)` — `Key` из `input/key_decoder.dart`, общий с REPL;
- `PasteMsg(text)`, `ResizeMsg`;
- `SessionViewMsg(view, at)` — `at` ставит адаптер: из него `reduce` берёт `turnStartedAt`, оставаясь чистым; `WorkspaceMsg`;
- `NoteMsg(text)` — вывод команды;
- `EffectFailedMsg`;
- `OpenPickerMsg(PickerSpec)` — от команды без аргумента;
- `PickerChosenMsg(index)` и `PickerClosedMsg` — от компонента пикера в адаптере.

`TuiCmd` (данные, D7):
- `SubmitCmd(text)`, `CancelTurnCmd`, `RespondCmd(id, optionId)`;
- `RunCommandCmd(input)`, `QuitCmd`;
- `SaveHistoryCmd(entry)`.

`reduce` — чистая функция:
- отбрасывает `SessionViewMsg` с ревизией меньше последней;
- маршрутизирует ввод через `CommandRouter` — тот же разбор, что в REPL.

`render(model, chrome) → Frame`:
- `chrome` — `TuiChrome`: готовые строки компонентов `dart_tui`, которые построил адаптер — кадр спиннера, строки пикера, строка подсказок (D12). Для ядра это обычные строки: `render` остаётся чистой функцией, а тесты ядра подставляют свои;
- раскладка сверху вниз: транскрипт → оверлей пикера (строки `chrome.picker`, не выше половины экрана) → «↓ N new» → зона одобрения или композер (1–10 строк) → строка подсказок `chrome.hints` (скрыта при высоте < 15) → статус-строка со спиннером `chrome.spinner`;
- каждая строка проходит `fitLine`:
  - обрезка по нашей ширине графем с запасом в одну колонку для спорных символов (D14, пункт 8);
  - сброс атрибутов в конце (TUI-9);
- текст сессии проходит `sanitize` до попадания в кадр (TUI-11).

`reduceGuarded`/`renderGuarded` (§12.2.7, шаг 7) живут в `TuiApp`, а не в ядре: ядро бросает ошибки, адаптер решает, что с ними делать.

### D6. Транскрипт и прокрутка

- **Строки элемента.** `transcript_lines.dart` переиспользует то, что уже есть у REPL:
  - `toolRow` — строки инструментов без сырого JSON, TUI-6;
  - `noticeText` и `sanitize`;
  - правило мыслей по `ThoughtsMode` — `dim` приглушённо, `collapsed` одной строкой «thinking…», `hidden` — ничего;
  - план — блоком при `/plan`.

  Markdown не рендерится (U-10): текст ответа выводится как есть с переносом по ширине.
- **Кэш переносов** по ключу `(item.id, ревизия элемента, ширина, режим мыслей)`. При дельте переносится только изменившийся элемент.
- **Прокрутка** — по §12.2.7:
  - `follow` по умолчанию;
  - PgUp выключает `follow`, и счётчик «↓ N new» растёт;
  - End, PgDn до низа, отправка промпта и ответ на одобрение включают `follow` обратно;
  - новые дельты `follow` не включают;
  - строки строятся только для окна плюс экран сверху и снизу.

### D7. Адаптер к `dart_tui`

- **`TuiApp implements Model`** держит `TuiModel` и компоненты `dart_tui` (D12).
  - `update`:
    - пока открыт пикер, клавиши навигации и фильтра уходят в его `ListModel`; Enter даёт `PickerChosenMsg(index)`, Esc — `PickerClosedMsg`;
    - `TickMsg` пакета продвигает `SpinnerModel`;
    - остальное переводит `TuiInput`, затем `reduceGuarded`;
    - после `reduce` адаптер синхронизирует компоненты с моделью: `OverlayState` появился — создаёт `ListModel` из `PickerSpec`, исчез — убирает; ход начался — выпускает `every(100 мс)` для спиннера, кончился — перестаёт;
    - `List<TuiCmd>` переводит `TuiEffects.toDartTuiCmd` (несколько команд — `batch`).
  - `view`: собирает `TuiChrome` из `view()` компонентов, вызывает `renderGuarded(model, chrome)` и `frameToView` — `View(altScreen: true, cursor: …)`. Bracketed paste и расширенные клавиши включает `Program` по умолчанию (разведка, пункты 2–3).
- **`TuiInput`** переводит сообщения пакета:
  - `KeyPressMsg` → `Key` нашего реестра (`TeaKey.code` и `modifiers` → `Key`); `shift+enter` и `alt+enter` → `newline`;
  - `PasteMsg` → `PasteMsg`;
  - `WindowSizeMsg` → `ResizeMsg`, неизменившийся размер отбрасывается;
  - `PasteStartMsg`/`PasteEndMsg`, `KeyboardEnhancementsMsg`, `ModeReportMsg` → `null`.
- **`TuiEffects`** исполняет команды:
  - `SubmitCmd` → `SessionHandle.send` (очередь kit, U-15);
  - `CancelTurnCmd` → `cancel`;
  - `RespondCmd` → `respond`;
  - `RunCommandCmd` → команда из `mvpReplCommands` через `TuiCommandContext`;
  - `SaveHistoryCmd` → `HistoryFile`;
  - `QuitCmd` → `QuitMsg`.

  Каждая функция `Cmd` ловит исключение и возвращает `DomainMsg(EffectFailedMsg)`: обработчик пакета печатает поверх кадра и завершает программу (§12.2.7, шаг 7).
- **`TuiRunner.run(handle, …)`.**
  - Собирает `Program(options: [withAltScreen(), withFps(60)])`.
  - Подписывается на `SessionHandle.view` и `ClientWorkspace.state` сразу после запуска `run`: событие → `program.send(DomainMsg(…))`.
  - В `finally`:
    - отменяет подписки;
    - повторно пишет последовательности выключения (повтор безвреден, TUI-4) и возвращает `echoMode`/`lineMode` stdin;
    - в обычном экране печатает последний ответ агента и статус-строку.
  - Код выхода: `0` — по `/exit`, Ctrl+D или двойному Ctrl+C; `143` — по SIGTERM (пакет переводит его в `QuitMsg`; `TuiRunner` различает причину по `watchStopSignals`, общему с REPL); `1` — три ошибки ядра подряд или исключение пакета.

### D8. Композер и клавиши

- **Композер** (`core/composer.dart`): строки, курсор в 2D, перенос по ширине для отображения, история `HistoryFile` (общая с REPL).
- **Клавиши.**
  - Действия TUI добавляются в общий реестр `KeyBindings` новой областью `KeyScope.transcript` и таблицей `KeyBindings.tui`:
    - PgUp/PgDn — `scroll_up`/`scroll_down`;
    - End — `follow`;
    - ↑/↓ — история на первой и последней строке композера, иначе перемещение курсора.
  - `KeyBindings.tui` строится из `mvp` без Ctrl+J и с `newline` на Shift+Enter и Alt+Enter: в TUI Ctrl+J приходит от пакета как Enter (D14, пункт 3).
  - `\` + Enter — запасной путь, как в REPL.
  - Подсказки и `/help keys` в TUI строятся из `KeyBindings.tui` (TUI-7).
- **Вставка.** `PasteMsg` вставляет текст в позицию курсора целиком: `\r\n` и `\r` → `\n`, управляющие символы, кроме `\n` и `\t`, удаляются. Вставка никогда не вызывает `submit` (TUI-3).
- **Выход и очистка.**
  - Esc при идущем ходе — `cancel_turn`, без хода — очистка композера.
  - Ctrl+C: при ходе — отмена хода; иначе очистка, а повтор за 1 с — выход.
  - Ctrl+D на пустом композере — выход.

### D9. Зона одобрения

- Пока у `SessionView.pendingApprovals` есть элемент, вместо композера рисуется зона:
  - заголовок с видом и риском;
  - команда или путь, рабочая папка;
  - подсказка только с вариантами, которые предложил агент.
- Клавиши `y/a/n/N` выбирают вариант через `ApprovalPrompt.optionFor`, общий с REPL.
- `?` раскрывает `rawInput` с редакцией секретов (`formatRedactedJson`) в зоне с прокруткой.
- Esc и Ctrl+C отменяют ход.
- Несколько запросов показываются по одному.
- Ответ включает `follow`.

### D10. Команды и пикеры

- **Контекст команд.** Команды — те же `ReplCommand`. `ReplContext` сейчас открывает `TerminalRenderer` целиком, но команды используют только `renderer.thoughts = …` (`/thoughts`) и `renderer.printPlan` (`/plan`). `renderer` заменяется тремя членами:
  - `set thoughts(ThoughtsMode)`;
  - `void showPlan(List<PlanEntryView>)`;
  - `void pick(PickerSpec)` — список вариантов для команды без аргумента (ниже). `PickerSpec` (заголовок, пункты, текущий, команда выбора) лежит в `lib/src/repl/picker_spec.dart`: тип общий для REPL и TUI, а `repl/` не зависит от `tui/`.

  REPL реализует их через рендер, `pick` — печатью списка, как сейчас. `TuiCommandContext`:
  - `say` → `NoteMsg`;
  - `clearScreen` → сброс заметок;
  - `openSession`, `switchProfile` и `reconnect` заменяют `SessionHandle` в `TuiRunner` и переподписываются (как в REPL после `/profile`).

  Смысл интерфейса не меняется.
- **Пикеры.** `/model`, `/mode` и `/sessions` без аргумента в TUI открывают пикер вместо печати списка: `TuiCommandContext.pick(PickerSpec)` → `OpenPickerMsg`.
  - Пикер рисует `ListModel` `dart_tui` с фильтром (D12): пункты — те же строки, что печатает REPL, курсор стоит на текущем значении.
  - ↑/↓ выбирают, `/` включает фильтр, Enter запускает ту же команду с аргументом (`/model <id>`, `/resume <n>`), Esc закрывает.
  - В REPL `pick` печатает список, как сейчас.
- **Дополнение.** Tab на `/` берёт кандидатов `CommandRouter`: один кандидат подставляется, несколько — тот же пикер с командами (команды агента помечены).

### D11. Статус-строка

- Последняя строка кадра. Сегменты по §12.2.6 из того, что есть в kit:
  - профиль;
  - режим — опция категории `mode`, иначе с id `mode`;
  - модель — та же логика, что `config_option_support.dart`;
  - очередь — `queue: N`, только при `N > 0`;
  - во время хода слева — значок хода и время `12s`: время считает `render` по `turnStartedAt` модели и `chrome.now`, который адаптер подставляет на каждом кадре (тик спиннера раз в 100 мс перерисовывает кадр).
- Разделитель ` · `.
- Порядок отбрасывания на узком экране: профиль → модель (сначала сокращается до части после `/`) → остальное; режим и очередь не отбрасываются.
- Usage, стоимость и ветка — U-13.
- Значок хода — `SpinnerModel` `dart_tui` (D12): кадры `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` по умолчанию, при `supportsUnicode == false` — `|/-\`. Его строка приходит в `render` через `chrome.spinner`.

### D12. Компоненты `dart_tui` в адаптере

Решение владельца проекта: значок хода, пикеры и строку подсказок рисуют компоненты пакета, как в §12.2.7:
- значок хода — `SpinnerModel`;
- пикеры — `ListModel` с фильтром;
- строка подсказок — `HelpModel` через `RegistryKeyMap implements KeyMap`: таблица действий одна, TUI-7.

Компонент — `Model` со своим `update` и `view`. Ядро не импортирует пакет (TUI-5, правило сторожа D3), поэтому компоненты живут в `TuiApp`, а не в `TuiModel`.
- **Ядро решает, что показывать.** Открыт ли пикер и какой (`OverlayState` с `PickerSpec`), идёт ли ход, какие клавиши активны.
- **Адаптер решает, как.** Создаёт и обновляет компоненты по модели, передаёт им клавиши, пока открыт пикер, и отдаёт их `view()` в `render` строками `TuiChrome`.
- **Выбор возвращается в ядро** сообщением (`PickerChosenMsg`), команду исполняет `reduce` → `RunCommandCmd`.

Кадр собирает одна функция ядра, поэтому раскладка, ширина и сброс атрибутов (`fitLine`, TUI-9) применяются и к строкам компонентов. Тесты ядра подставляют `TuiChrome` со своими строками; тест адаптера проверяет, что строки компонентов попали в кадр.

Не используются:
- `TextAreaModel` и `TextInputModel` — нет реестра клавиш и истории;
- `ViewportModel` для транскрипта — переносит весь текст на каждом изменении;
- `Style` для markdown.

### D13. Тесты

- **Модульные, без терминала и без пакета:**
  - `test/tui/tui_update_test.dart` — клавиши, вставка, ревизии → модель и `TuiCmd`;
  - `test/tui/tui_view_test.dart` — кадры как строки, по образцу golden. Проверяют:
    - ширину строк ≤ колонок;
    - сброс атрибутов (TUI-9);
    - вырезанный `ESC` из текста агента (TUI-11);
    - раскладку при высоте 10 и 30;
  - `test/tui/composer_test.dart`, `status_line_test.dart`, `transcript_lines_test.dart`.
- **Адаптер:**
  - `test/tui/tui_app_test.dart` — `Program` с `withInput` (байты), `withOutput` (буфер), `withWindowSize(100, 30)` и `withoutSignalHandler()` против `FakeAgent`. Проверяет:
    - промпт и стрим;
    - вставку с `\n` без отправки;
    - Shift+Enter в кодировках kitty и modifyOtherKeys;
    - одобрение `y`;
    - пикер `/model`: строки `ListModel` в кадре, ↓ и Enter → `session/set_config_option`;
    - спиннер в статус-строке во время хода и строка подсказок `HelpModel` из реестра;
    - последовательности восстановления в буфере (TUI-4);
  - `test/tui/tui_input_test.dart` — перевод клавиш пакета в `Key`;
  - `test/tui/tui_effects_test.dart` — каждая ветка `toDartTuiCmd`.
- **PTY-e2e `cli/tui-smoke`** (`test/e2e/tui_smoke_test.dart`, §12.2.13) — `codelab --ui tui` в PTY 100×30 против scripted-агента:
  - `ESC[?1049h`;
  - промпт → ответ на экране, статус-строка в последней строке;
  - Ctrl+D → `ESC[?1049l`, `ESC[?2004l`, курсор виден;
  - SIGTERM во время хода — то же восстановление и код `143`.

  PTY не отвечает на запросы терминала, поэтому e2e проверяет путь без synchronized output и без kitty; путь с ними — тест адаптера.
- **Разбор флагов** — `test/cli_args_test.dart`: `--ui`, сочетание с `-p`, не TTY.

### D14. Итог разведки 6.11

Окружение:
- **Пакет:** `dart_tui` 3.0.0, MIT. Зависимости `characters`, `path`, `ffi`.
- **Спайк:** `apps/codelab_cli/tool/tui_spike/`, отдельный пакет вне workspace; удаляется этим change.
  - Модель с транскриптом и композером; стрим «агента» таймером через `Program.send`.
  - Команды `/stream`, `/wide`, `/copy`, `/crash`, журнал сообщений `SPIKE_LOG`, режим `--test-io`.
- **Где проверялось:** macOS — псевдотерминал `pty`; tmux 3.8 (`TERM=tmux-256color`) с `extended-keys on` и без; `--test-io`.
- **Не проверялось:** Linux, Windows Terminal и conhost, SSH, Apple Terminal, iTerm2.

| № | Возможность | Итог | Как проверено |
|---|---|---|---|
| 1 | внешние сообщения | да | `Program.send` из `Timer.periodic`: все дельты стрима доходят в `update` по порядку и видны в кадре (tmux, `--test-io`) |
| 2 | bracketed paste | да | `PasteStartMsg`, `PasteMsg` с полным текстом и `\n`, `PasteEndMsg`; Enter не срабатывает (tmux `paste-buffer -p`, `--test-io`) |
| 3 | Shift+Enter, Ctrl+Enter | да, с оговоркой | kitty `ESC[13;2u` и modifyOtherKeys `ESC[27;2;13~` → `shift+enter` (`--test-io`); tmux с `extended-keys on` — `shift+enter`, без него — `enter`; `KeyboardEnhancementsMsg` tmux не присылает; Alt+Enter → `alt+enter`. **Ctrl+J приходит как `enter`** — в TUI убран из `newline` (D8) |
| 4 | synchronized output | да | tmux отвечает на DECRQM `?2026` значением 2, и пакет включает обёртку кадра; без ответа (голый PTY) кадр пишется без обёртки; `withCellRenderer()` не нужен |
| 5 | восстановление терминала | да | `/crash` (исключение в `update`) и SIGTERM: пакет выключает расширенные клавиши, мышь, фокус, bracketed paste, показывает курсор и выходит из альтернативного экрана; `stty -g` до и после совпадают (PTY); исключение из `update` пакет пробрасывает из `run` |
| 6 | тестовый ввод-вывод | да | `withInput`, `withOutput`, `withWindowSize(60, 12)`, `withoutSignalHandler()`: клавиши, вставка и стрим без терминала; `run` возвращает итоговую модель |
| 7 | Windows Terminal и conhost | не проверено | нет окружения; `--ui tui` на Windows не включается по умолчанию, ручная проверка — до смены умолчания (D1) |
| 8 | ширина символов | да, с оговоркой | CJK, эмодзи с модификатором, комбинируемые и ZWJ-последовательности выводятся в tmux; **пакет не режет строки шире экрана**: длинная строка переносится терминалом и сдвигает кадр. Обрезка по ширине — обязанность `render` (`fitLine`, D5) |
| 9 | tmux и SSH | tmux — да; SSH — не проверено | tmux 3.8: кадр, diff строк, `?2026`, вставка; Shift+Enter — только с `extended-keys on` (подсказка §12.2.9 подтверждается) |
| 10 | запись вне кадра | да | `/copy` во время стрима: OSC 52 записан между кадрами, после завершённой записи строки (PTY) |

Решение: **пакет подтверждён**. Обязательный пункт 2 выполнен, неустранимых поломок на macOS нет.

Две поправки документа §12.2:
- Ctrl+J в TUI (§12.2.9);
- обрезка строк кадра — обязанность нашего рендера (§12.2.7, шаг 4; запасной путь пункта 8 становится правилом).

Пункты 7 и 9 (SSH) и Apple Terminal, iTerm2, Linux — ручная проверка перед сменой режима по умолчанию.

### D15. Итерации и TDD

Каждая итерация — отдельный PR в `develop`. Модульные тесты пишутся первыми, отдельным красным коммитом до кода. PTY-e2e — приёмочные ворота.

1. **Ядро и запуск.**
   - Зависимость и сторож, флаг `--ui`.
   - Ядро: модель, транскрипт с прокруткой, композер, статус-строка, `fitLine`.
   - Адаптер и `TuiRunner`, ход и очередь.
   - `cli/tui-smoke`.

   Закрывает основу U-12, TUI-3, TUI-4, TUI-9, TUI-11.
2. **Взаимодействие.** Зона одобрения, команды через `TuiCommandContext` (сужение `ReplContext`), пикеры, дополнение Tab, строка подсказок, `/help keys` по `KeyBindings.tui`.
3. **Документы и DoD.**
   - Поправки §12.2.7, §12.2.9, §9.11 и матрицы.
   - Удаление спайка.
   - Ручная проверка в Terminal.app или iTerm2.

## Risks / Trade-offs

- **[`dart_tui` молод: 3.0.0 от 2026-10-17, три мажорные версии]** → адаптер из четырёх файлов, ядро без пакета, версия `^3.0.0` и `pubspec.lock`; переход на новую мажорную версию — отдельный PR с прогоном чек-листа.
- **[Windows не проверен]** → TUI не по умолчанию; REPL остаётся основным путём на всех ОС.
- **[Ширина графем расходится с терминалом]** → `fitLine` режет с запасом в одну колонку для спорных символов; хвост строки теряется, но кадр не сдвигается.
- **[PTY-e2e не видит synchronized output и kitty]** → эти пути проверяет тест адаптера с `withInput`, где ответы терминала подаются байтами.
- **[Компоненты пакета привязаны к его версии и стилям]** → они живут только в адаптере и попадают в кадр строками `TuiChrome`; при замене пакета их заменяют свои, а ядро и его тесты не меняются.
- **[Клавиши пикера обрабатывает компонент, а не наш реестр]** → пока пикер открыт, реестр не применяется; Enter и Esc адаптер перехватывает до компонента, остальное (↑/↓, фильтр) — поведение `ListModel`, проверяется тестом адаптера.
- **[Сужение `ReplContext` трогает REPL]** → смысл не меняется, тесты REPL `/thoughts` и `/plan` подтверждают.

## Migration Plan

Новый режим за флагом; `line` по умолчанию, поведение REPL и headless не меняется. Откат — revert PR итерации.

## Open Questions

Открытых вопросов нет. Объём (D1) выбран владельцем проекта при создании change.
