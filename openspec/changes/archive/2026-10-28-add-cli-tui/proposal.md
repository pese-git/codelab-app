## Why

Построчный REPL `codelab` (change `add-codelab-cli`) не может перерисовать уже напечатанное. Поэтому без полноэкранного режима не работают:
- прокрутка истории;
- композер на несколько строк с курсором;
- зона одобрения на месте композера;
- постоянная статус-строка.

Это цель U-12 матрицы (Should). Разведка 6.11 подтвердила пакет `dart_tui` 3.0.0 по чек-листу §12.2.7, обязательный пункт 2 (bracketed paste) выполнен. Решение владельца проекта: TUI встаёт **рядом** с REPL флагом `--ui tui`, а REPL остаётся режимом по умолчанию и запасным путём.

## What Changes

- **Флаг `--ui line|tui`** (по умолчанию `line`). `tui` требует TTY на stdin и stdout, иначе код `64`. Вместе с `-p`/`-f` флаг тоже даёт код `64`.
- **Полноэкранный режим** в `apps/codelab_cli/lib/src/tui/`, по архитектуре Model–Update–View §12.2.7:
  - чистое ядро экрана `TuiModel` / `reduce` / `render` без `package:dart_tui` и `dart:io`;
  - адаптер к `dart_tui`: `TuiApp`, `TuiInput`, `TuiEffects`, `TuiRunner`.
- **Кадр**:
  - прокручиваемый транскрипт: следование за выводом, PgUp/PgDn/End, строка «↓ N новых»;
  - многострочный композер с историей, общей с REPL;
  - зона одобрения вместо композера с теми же клавишами `y/a/n/N/?`;
  - строка подсказок клавиш из реестра;
  - статус-строка: профиль, модель, режим, состояние хода, очередь.
- **Команды и очередь.** Те же клиентские slash-команды, команды агента и очередь, что в REPL: TUI вызывает те же `ReplCommand` через свой контекст. Tab дополняет команду. `/model`, `/mode` и `/sessions` без аргумента открывают пикер.
- **Часть U-23 в TUI.** Bracketed paste: вставка попадает в композер целиком и не отправляется. Shift+Enter даёт новую строку, где терминал его различает (kitty CSI u, modifyOtherKeys), плюс Alt+Enter и `\` + Enter. Ctrl+J в TUI неотличим от Enter (разведка 6.11) и остаётся только в REPL.
- **Восстановление терминала** при выходе, исключении и SIGTERM. После выхода в обычный экран печатается последний ответ.
- **Зависимость `dart_tui: ^3.0.0`.** Правило сторожа: `package:dart_tui/` только из `lib/src/tui/`, а ядро экрана пакет не импортирует.
- **Каталог спайка** `apps/codelab_cli/tool/tui_spike/` удаляется. Итог разведки — таблица в `design.md` этого change.
- **Документы.** §12.2.7 и §12.2.9: поправки по итогам разведки (Ctrl+J, строки режет наш `render`); §9.11: строка `--ui`; матрица: статус U-12; technology-stack §20а: версия из `pubspec.lock`.

Вне change:
- мышь и `/mouse` (U-22);
- ANSI-markdown (U-10) и diff (U-11);
- вложения и `@` (U-14);
- несколько сессий (U-37);
- копирование (U-28);
- `/terminal-setup` (остаток U-23);
- `cli.yaml` и темы;
- `/inspect` и подробности вызова (change `add-cli-stream-json`).

TUI по умолчанию — только после приёмки на Linux и Windows (§12.2.12).

## Capabilities

### New Capabilities
- `codelab-tui`: полноэкранный режим `codelab --ui tui`:
  - кадр и раскладка;
  - прокрутка транскрипта;
  - композер и вставка;
  - зона одобрения;
  - команды и пикеры;
  - статус-строка;
  - восстановление терминала;
  - граница ядра экрана и адаптера `dart_tui`.

### Modified Capabilities
- `codelab-cli`: флаг `--ui line|tui` и его сочетания (TTY, headless) в требовании «Команда codelab и разбор флагов».
- `workspace-architecture`: allowlist `apps/codelab_cli` пополняется `dart_tui`; правило сторожа — `package:dart_tui/` только из `apps/codelab_cli/lib/src/tui/`, кроме файлов ядра экрана.
- `testing-quality`: PTY-e2e терминального клиента — дымовой `cli/tui-smoke`, а также тесты адаптера через `withInput`/`withOutput` без терминала.

## Impact

- **Код:**
  - новый `apps/codelab_cli/lib/src/tui/`;
  - `cli_args.dart` (флаг `--ui`) и `run.dart` (выбор режима);
  - `repl/repl_command.dart`: контекст команд получает реализацию для TUI, интерфейс `ReplContext` не меняется по смыслу;
  - `input/key_bindings.dart`: действия TUI в общем реестре.
- **Зависимости:** `dart_tui` (`^3.0.0`, MIT; транзитивно `characters`, `ffi`, `path`), уже утверждён technology-stack §20а.
- **Сторож:**
  - правило в `packages/dart/codelab_architecture_tests/test/support/rules.dart`, вместо комментария-заготовки;
  - `cliAllowlist`.
- **Тесты:**
  - модульные тесты `reduce`/`render` (без терминала и пакета);
  - `test/tui/tui_app_test.dart` через `withInput`/`withOutput`;
  - PTY-e2e `cli/tui-smoke`.
- **Kit и app не меняются.**
