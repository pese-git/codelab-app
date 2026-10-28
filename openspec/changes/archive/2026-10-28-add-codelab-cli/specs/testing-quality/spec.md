## MODIFIED Requirements

### Requirement: Проверки workspace
CodeLab SHALL предоставлять Melos-скрипты для format, analyze, test, protocol conformance, сторожа архитектуры (`guard`), компиляции ядра агента для web (`web-compile`) и полной проверки. Конфигурация Melos SHALL храниться в одном месте — секции `melos:` корневого `pubspec.yaml`. Полная проверка `check` SHALL включать `check-format`, `analyze`, `guard`, `test`, `protocol-conformance` и `web-compile`.

#### Scenario: Запускается полная проверка
- **WHEN** в развёрнутом workspace выполняется `fvm dart run melos run check`
- **THEN** форматирование, анализ, сторож, тесты, protocol conformance и web-компиляция ядра проходят либо сообщают конкретные, действенные ошибки

#### Scenario: Протокол изменился
- **WHEN** меняются модели, кодеки или потоки протокола ACP
- **THEN** запускается `fvm dart run melos run protocol-conformance`

#### Scenario: Один источник конфигурации Melos
- **WHEN** выполняется `fvm dart run melos list` или любой скрипт из прежнего `melos.yaml`
- **THEN** команда работает, а файла `melos.yaml` в корне нет

#### Scenario: Сборка бинаря агента
- **WHEN** выполняется `fvm dart run melos run build:agent`
- **THEN** появляется исполняемый файл `build/bin/codelab-agent`, который отвечает на `initialize` по stdio; скрипт не входит в `check` (design.md change `add-codelab-agent-binary`, D9)

#### Scenario: Сборка терминального клиента
- **WHEN** выполняется `fvm dart run melos run build:cli`
- **THEN** появляется исполняемый файл `build/bin/codelab`, который печатает версию по `--version`; скрипт не входит в `check`

#### Scenario: Отдельный прогон e2e CLI
- **WHEN** выполняется `fvm dart run melos run test:e2e:cli`
- **THEN** запускаются только тесты `apps/codelab_cli/test/e2e/` на Dart VM

## ADDED Requirements

### Requirement: PTY-e2e терминального клиента
E2E-тесты `apps/codelab_cli/test/e2e/` SHALL запускать CLI как процесс (Dart VM, программа один раз компилируется в kernel) против scripted stdio-агента из `codelab_acp_testing`; имена тестов SHALL совпадать с id критериев матрицы целей (`cli/<id>`). Интерактивные сценарии SHALL идти через псевдотерминал системной утилиты `script` (обвязка `test/e2e/support/pty_process.dart`), команда которой собирается по ОС в одном месте: BSD `script` на macOS, util-linux `script` на Linux. Без утилиты и на Windows PTY-тест SHALL пропускаться с сообщением, а не падать. Переводы строк PTY SHALL нормализоваться перед сравнением. E2E CLI SHALL входить в `melos run test` (Dart VM, `AGENTS.md` §21) и НЕ SHALL требовать устройства или симулятора. Тест против Python-агента SHALL пропускаться с сообщением, если агент не установлен.

#### Scenario: Обвязка даёт терминал
- **WHEN** `PtyProcess.start('sh', ['-c', 'test -t 0 && test -t 1; exit 3'], columns: 100, rows: 30)` на macOS или Linux
- **THEN** код выхода — `3`, а `tput cols` внутри обвязки печатает `100`

#### Scenario: Нет утилиты script
- **WHEN** `script` нет в `PATH`
- **THEN** PTY-тесты помечаются пропущенными с причиной, прогон зелёный
