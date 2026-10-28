## MODIFIED Requirements

### Requirement: PTY-e2e терминального клиента
E2E-тесты `apps/codelab_cli/test/e2e/` SHALL запускать CLI как процесс (Dart VM, программа один раз компилируется в kernel) против scripted stdio-агента из `codelab_acp_testing`; имена тестов SHALL совпадать с id критериев матрицы целей (`cli/<id>`). Интерактивные сценарии SHALL идти через псевдотерминал системной утилиты `script` (обвязка `test/e2e/support/pty_process.dart`), команда которой собирается по ОС в одном месте: BSD `script` на macOS, util-linux `script` на Linux. Без утилиты и на Windows PTY-тест SHALL пропускаться с сообщением, а не падать. Переводы строк PTY SHALL нормализоваться перед сравнением. E2E CLI SHALL входить в `melos run test` (Dart VM, `AGENTS.md` §21) и НЕ SHALL требовать устройства или симулятора. Тест против Python-агента SHALL пропускаться с сообщением, если агент не установлен. Полноэкранный режим SHALL проверяться на трёх уровнях: модульными тестами чистого ядра экрана (`reduce`, `render`) без терминала и без `dart_tui`; тестами адаптера через `Program` с `withInput`/`withOutput`/`withWindowSize`/`withoutSignalHandler`, без терминала, где ответы терминала (kitty, modifyOtherKeys, bracketed paste) подаются байтами; дымовым PTY-e2e `cli/tui-smoke`.

#### Scenario: Обвязка даёт терминал
- **WHEN** `PtyProcess.start('sh', ['-c', 'test -t 0 && test -t 1; exit 3'], columns: 100, rows: 30)` на macOS или Linux
- **THEN** код выхода — `3`, а `tput cols` внутри обвязки печатает `100`

#### Scenario: Нет утилиты script
- **WHEN** `script` нет в `PATH`
- **THEN** PTY-тесты помечаются пропущенными с причиной, прогон зелёный

#### Scenario: Дымовой тест TUI
- **WHEN** `cli/tui-smoke` запускает `codelab --ui tui` в PTY 100×30 против scripted-агента, вводит промпт и Ctrl+D
- **THEN** ответ агента виден на экране, вывод содержит `ESC[?1049h`, затем `ESC[?1049l`, `ESC[?2004l` и `ESC[?25h`, код выхода `0`
