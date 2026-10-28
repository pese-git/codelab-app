## MODIFIED Requirements

### Requirement: Команда codelab и разбор флагов
Терминальный клиент `apps/codelab_cli` SHALL собираться в бинарь `codelab` (`melos run build:cli` → `build/bin/codelab`). Без подкоманды и без `-p`/`-f` `codelab [опции] [первое сообщение]` SHALL запускать REPL; подкоманды MVP — `profiles` и `test-scenario`; `--version` и `--help` SHALL печатать версию и справку и выходить с кодом `0`. Флаги MVP — по таблице `09-11-stage-6-cli-mvp.md` без пометки этапа и с пометкой «этап 6», кроме перечисленных в design.md, D1 как перенесённые. Флаг или подкоманда, не зарегистрированные в этой сборке, SHALL давать код `64` и строку `Unknown flag` / `Unknown command` в stderr без запуска агента. Флаг `--ui line|tui` SHALL выбирать интерактивный режим: `line` (по умолчанию) — построчный REPL, `tui` — полноэкранный режим (capability `codelab-tui`). `--ui tui` SHALL давать код `64` без запуска агента, если stdin или stdout не TTY (`--ui tui needs a terminal on stdin and stdout`) и вместе с `-p`/`-f` (`--ui applies only to the interactive mode`); неизвестное значение — код `64`. Ошибка разбора SHALL оставлять stdout пустым. Клиент НЕ SHALL импортировать Flutter и `package:codelab_agent_*`.

#### Scenario: Неизвестный флаг
- **WHEN** запускается `codelab --output-format stream-json -p hi`
- **THEN** процесс завершается с кодом `64`, stdout пуст, в stderr — `Unknown flag`, агент не запускается

#### Scenario: Версия
- **WHEN** запускается `codelab --version`
- **THEN** в stdout одна строка с версией клиента, код выхода `0`

#### Scenario: TUI без терминала
- **WHEN** запускается `codelab --ui tui` со stdout в pipe
- **THEN** процесс завершается с кодом `64`, в stderr — `--ui tui needs a terminal on stdin and stdout`, агент не запускается

#### Scenario: TUI с headless
- **WHEN** запускается `codelab --ui tui -p hi`
- **THEN** процесс завершается с кодом `64`, stdout пуст, агент не запускается
