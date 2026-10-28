Задачи идут парами «тест → реализация» (§9.0, правило 3). В скобках — требование спецификации, строка матрицы целей или решение design.md.

Пути — в `apps/codelab_cli/`, если не указано иное. Группы задач по итерациям (design.md, D15):
- группы 1–3 — итерация 1 (ядро и запуск);
- группы 4–5 — итерация 2 (взаимодействие);
- группа 6 — итерация 3 (документы и DoD).

Каждая итерация — отдельный PR в `develop`. Модульные тесты пишутся первыми, отдельным красным коммитом до кода. PTY-e2e — приёмочные ворота итерации.

## 1. Зависимость, сторож и флаг (D3, D4)

- [x] 1.1 Тест (workspace-architecture «Автоматический сторож границ пакетов»): в `packages/dart/codelab_architecture_tests/` правила `apps/codelab_cli/lib/src` (`package:dart_tui/` вне `tui/`) и `apps/codelab_cli/lib/src/tui/core` (`package:dart_tui/`, `dart:io`) вместо комментария-заготовки в `rules.dart`; `dart_tui` в `cliAllowlist`. Негативные тесты: `package:dart_tui/` в `lib/src/repl/` и в `lib/src/tui/core/` → нарушение (красный)
- [x] 1.2 Добавить `dart_tui: ^3.0.0` в `dependencies`, `melos bootstrap`, реализовать правила — 1.1 зелёный; `fvm dart run melos run guard` зелёный
- [x] 1.3 Тест (codelab-cli «Команда codelab и разбор флагов»): `test/cli_args_test.dart` — `--ui line|tui`, умолчание `line`; `--ui tui` с `-p`/`-f` → `UsageError`; неизвестное значение → `UsageError`; `--ui` убран из списка незарегистрированных флагов. `test/run_test.dart` — `--ui tui` без TTY → `64` и текст, агент не запускается (красный)
- [x] 1.4 Реализовать флаг в `cli_args.dart` и выбор режима в `run.dart` (headless → REPL → TUI) поверх `openCliSession` — 1.3 зелёный

## 2. Чистое ядро экрана (D5, D6, D8, D11)

- [x] 2.1 Тест (codelab-tui «Кадр TUI»): `test/tui/frame_test.dart` — `fitLine` режет по ширине графем (ASCII, CJK, эмодзи с модификатором, ZWJ, комбинируемые) с запасом в одну колонку для спорных символов, кончается `ESC[0m` (TUI-9); `test/tui/transcript_lines_test.dart` — текст агента с переносом по ширине, строки инструментов по `toolRow` без `rawInput` (TUI-6), мысли по `ThoughtsMode`, `ESC` и `BEL` из текста вырезаны (TUI-11), кэш переносов пересчитывает только изменившийся элемент (красный)
- [x] 2.2 Реализовать `lib/src/tui/core/frame.dart` и `core/transcript_lines.dart` — 2.1 зелёный
- [x] 2.3 Тест (codelab-tui «Композер TUI», «Вставка в TUI»): `test/tui/composer_test.dart` — ввод, курсор 2D, `newline`, `\` + Enter, история ↑/↓ на первой и последней строке, вставка с нормализацией `\r\n` и удалением управляющих символов без `submit` (TUI-3) (красный)
- [x] 2.4 Реализовать `core/composer.dart` — 2.3 зелёный
- [x] 2.5 Тест (codelab-tui «Строка подсказок и статус-строка TUI»): `test/tui/status_line_test.dart` — сегменты профиль · режим · модель · `queue: N`, время хода по `turnStartedAt` и `chrome.now`, строка спиннера из `chrome`, отбрасывание на 30 колонках, обрезка с `…` (красный)
- [x] 2.6 Реализовать `core/status_line.dart` — 2.5 зелёный
- [x] 2.7 Тест (codelab-tui «Кадр TUI», «Прокрутка транскрипта TUI», «Композер TUI»): `test/tui/tui_update_test.dart` — клавиши → модель и `TuiCmd`: Enter → `SubmitCmd` (во время хода — тоже, очередь kit), Esc/Ctrl+C при ходе → `CancelTurnCmd`, без хода — очистка, двойной Ctrl+C за 1 с и Ctrl+D на пустом → `QuitCmd`; PgUp/PgDn/End, «↓ N new», отправка включает следование, дельты — нет; ревизия меньше последней отбрасывается; `/…` → `RunCommandCmd`. `test/tui/tui_view_test.dart` — кадры как строки при 100×30 и 60×10: раскладка, строка подсказок скрыта при высоте < 15, все строки не шире терминала, статус-строка последняя (красный)
- [x] 2.8 Реализовать `core/tui_model.dart`, `core/tui_msg.dart`, `core/tui_cmd.dart`, `core/tui_chrome.dart`, `core/tui_update.dart` (`reduce`), `core/tui_view.dart` (`render`); `KeyBindings.tui`, клавиши `shiftEnter`, `pageUp`, `pageDown` и действия `scrollUp`, `scrollDown`, `follow` в `input/` (без Ctrl+J, `newline` на Shift+Enter и Alt+Enter, D8) с тестом в `test/input/key_bindings_test.dart` — 2.7 зелёный

## 3. Адаптер и запуск (D7, D12, D13)

- [x] 3.1 Тест (codelab-tui «Граница ядра экрана и адаптера», «Восстановление терминала после TUI»): `test/tui/tui_input_test.dart` — `KeyPressMsg` пакета → `Key` (`shift+enter`, `alt+enter`, `ctrl+c`, `esc`, PgUp), `PasteMsg`, `WindowSizeMsg` (повтор размера отбрасывается); `test/tui/tui_effects_test.dart` — каждая ветка `toDartTuiCmd`, исключение эффекта → `EffectFailedMsg`; `test/tui/tui_app_test.dart` — `Program` с `withInput`/`withOutput`/`withWindowSize(100, 30)`/`withoutSignalHandler()` против `FakeAgent`: промпт и стрим, вставка с `\n` без отправки, Shift+Enter в `ESC[13;2u` и `ESC[27;2;13~`, спиннер в статус-строке во время хода, строка подсказок `HelpModel` из реестра, последовательности восстановления в буфере (TUI-4), три ошибки `reduce` подряд → выход с кодом `1` (красный)
- [x] 3.2 Реализовать `tui/tui_input.dart`, `tui/tui_effects.dart`, `tui/registry_key_map.dart`, `tui/tui_app.dart` (компоненты `SpinnerModel`, `HelpModel`; `reduceGuarded`/`renderGuarded`), `tui/tui_runner.dart` (подписка на `SessionHandle.view`, `finally` с повторным восстановлением, печать последнего ответа, коды `0`/`143`/`1`) — 3.1 зелёный
- [x] 3.3 PTY-e2e (codelab-tui «Запуск полноэкранного режима», «Восстановление терминала после TUI»; testing-quality «PTY-e2e терминального клиента»): `test/e2e/tui_smoke_test.dart` `cli/tui-smoke` — `--ui tui` в PTY 100×30 против scripted-агента: `ESC[?1049h`, промпт → ответ на экране, статус-строка последней строкой, первое сообщение из позиционных аргументов, Ctrl+D → `ESC[?1049l`, `ESC[?2004l`, `ESC[?25h` и код `0`; SIGTERM во время хода → то же и код `143`
- [x] 3.4 Проверка итерации 1: `fvm dart run melos run check` зелёный; PR итерации 1

## 4. Одобрение (D9)

- [x] 4.1 Тест (codelab-tui «Одобрение в TUI»): в `test/tui/tui_update_test.dart` и `tui_view_test.dart` — зона одобрения вместо композера с заголовком, командой или путём и папкой; подсказка только с предложенными вариантами; `y/a/n/N` → `RespondCmd` с `optionId` через `ApprovalPrompt.optionFor`; Enter и непредложенный вариант — без команд; `?` раскрывает `rawInput` с редакцией; Esc → `CancelTurnCmd`; два запроса — по одному; ответ включает следование (красный)
- [x] 4.2 Реализовать зону одобрения в ядре — 4.1 зелёный; в `tui_app_test.dart` — одобрение `y` против `FakeAgent`

## 5. Команды, пикеры и подсказки (D10, D12)

- [x] 5.1 Тест (codelab-cli «Slash-меню и клиентские команды»): сужение `ReplContext` — `set thoughts(ThoughtsMode)`, `showPlan(List<PlanEntryView>)` и `pick(PickerSpec)` вместо `renderer`; тесты REPL `/thoughts`, `/plan`, `/model`, `/mode` и `/sessions` без аргумента (печать списка, как сейчас) зелёные на новом интерфейсе (красный там, где тесты обращаются к `renderer`)
- [x] 5.2 Реализовать сужение в `repl/repl_command.dart`, `repl/repl_session.dart` и командах — 5.1 зелёный, поведение REPL не меняется
- [x] 5.3 Тест (codelab-tui «Команды и пикеры TUI»): `test/tui/tui_command_context_test.dart` — `say` → заметка в транскрипте, `clearScreen` сбрасывает заметки, `pick` → `OpenPickerMsg`, `openSession`/`switchProfile`/`reconnect` меняют `SessionHandle` и подписки; `test/tui/tui_update_test.dart` — `PickerChosenMsg` → `RunCommandCmd('/model m2')`, `PickerClosedMsg` закрывает без команд, Tab с одним кандидатом подставляет, с несколькими — пикер; `tui_app_test.dart` — `/model`: строки `ListModel` в кадре с курсором на текущем, ↓ и Enter → `session/set_config_option` с `m2`, Esc без запросов; `/help keys` печатает `KeyBindings.tui` (TUI-7) (красный)
- [x] 5.4 Реализовать `tui/tui_command_context.dart`, `repl/picker_spec.dart`, пикер `ListModel` и дополнение Tab в `TuiApp` — 5.3 зелёный
- [x] 5.5 PTY-e2e: в `cli/tui-smoke` — одобрение `y` и `/model` с выбором `m2` против scripted-агента
- [x] 5.6 Проверка итерации 2: `check` зелёный; PR итерации 2

## 6. Документы и Definition of Done

- [x] 6.1 `12-2-cli-display-and-input.md`:
  - §12.2.7: ядро в `tui/core/` и правило сторожа; компоненты пакета в адаптере и `TuiChrome` (D12); строки кадра режет наш рендер (шаг 4); чек-лист разведки — ссылка на D14;
  - §12.2.9: Ctrl+J в TUI не различается с Enter, `newline` в TUI — Shift+Enter, Alt+Enter, `\` + Enter;
  - §12.2.12, мера 3: итог разведки — в `design.md` change `add-cli-tui`.
- [x] 6.2 Обновить ссылки и статусы:
  - `09-11-stage-6-cli-mvp.md`: строка `--ui` — change `add-cli-tui`; пункт 6.11 и DoD разведки — ссылки на D14;
  - `agent-parity-goals.md`: U-12 — «закрыто change `add-cli-tui`» с файлом `cli/tui-smoke`; U-23 — частично (вставка и Shift+Enter в TUI);
  - `technology-stack.md` §20а: версия `dart_tui` из `pubspec.lock`;
  - вложенный `apps/codelab_cli/AGENTS.md`: `package:dart_tui/` только в `lib/src/tui/`, ядро `tui/core/` без пакета.
- [x] 6.3 Удалить каталог спайка `apps/codelab_cli/tool/tui_spike/`.
- [x] 6.4 Ручная проверка `--ui tui` в терминале (tmux) против Dart-агента `codelab-agent serve --stdio` с моделью LM Studio (`--provider openai-compatible`, решение владельца проекта вместо Python-агента): промпт, вставка, Shift+Enter или Alt+Enter, одобрение, `/model`, `/mode`, `/sessions`, `/resume`, выход. Итог — в описании PR.
- [x] 6.5 Проверка DoD: `fvm dart run melos run check` и `test:e2e:cli` зелёные локально и в CI; `openspec validate add-cli-tui --strict` без ошибок; PR итерации 3
