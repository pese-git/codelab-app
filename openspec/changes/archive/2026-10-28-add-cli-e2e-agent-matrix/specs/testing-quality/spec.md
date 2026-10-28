## MODIFIED Requirements

### Requirement: Проверки workspace
CodeLab SHALL предоставлять Melos-скрипты для format, analyze, test, protocol conformance, сторожа архитектуры (`guard`), компиляции ядра агента для web (`web-compile`) и полной проверки. Конфигурация Melos SHALL храниться в одном месте — секции `melos:` корневого `pubspec.yaml`. Полная проверка `check` SHALL включать `check-format`, `analyze`, `guard`, `test`, `protocol-conformance`, `web-compile` и `test:e2e:cli:dart-agent` — e2e терминального клиента против Dart-агента (Dart VM). Прогон против Python-агента (`test:e2e:cli:python-agent`) SHALL быть отдельным скриптом вне `check`.

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

#### Scenario: e2e CLI против Dart-агента
- **WHEN** выполняется `fvm dart run melos run test:e2e:cli:dart-agent`
- **THEN** тесты `apps/codelab_cli/test/e2e/` без тега `scripted-only` идут с `CODELAB_E2E_AGENT=dart` против `codelab-agent serve --stdio --llm-script`, скомпилированного в kernel на этот прогон

#### Scenario: e2e CLI против Python-агента
- **WHEN** выполняется `fvm dart run melos run test:e2e:cli:python-agent`
- **THEN** идут только тесты с тегом `python-agent` с `CODELAB_E2E_AGENT=python`; без установленного Python-агента они пропущены с причиной, а прогон зелёный

### Requirement: Непрерывная интеграция
CodeLab SHALL запускать CI (`.github/workflows/ci.yml`) на каждый pull request и на push в `master` и `develop`. Обязательные джобы `format`, `analyze`, `test`, `conformance`, `guard`, `web-compile` и `e2e-cli-dart` SHALL запускать соответствующие Melos-скрипты на FVM-закреплённом SDK; `e2e-cli-dart` — `test:e2e:cli:dart-agent`. Python-агента в CI нет, и прогон против него в CI НЕ SHALL запускаться. Ночной запуск по расписанию SHALL прогонять те же джобы. Интеграционные тесты в CI SHALL выполняться только на Dart VM (`ubuntu-latest`); Flutter-тесты приложения на macOS (`test:e2e:app:*`) в CI НЕ SHALL запускаться — это локальные приёмочные ворота этапа. Шаблон pull request SHALL содержать чек-лист: OpenSpec change, тесты, сторонний код.

#### Scenario: Pull request с нарушением
- **WHEN** открыт pull request, в котором нарушен формат, анализ, тест, сторож или web-компиляция
- **THEN** соответствующий джоб CI красный

#### Scenario: Интеграционные тесты на Dart VM
- **WHEN** CI запускается на pull request, push или по расписанию
- **THEN** интеграционные тесты чистых Dart-пакетов (реальные процессы и сокеты `codelab_acp_transports`) выполняются в джобе `test` на `ubuntu-latest`, а джобов на macOS в workflow нет

#### Scenario: Шаблон pull request
- **WHEN** автор открывает pull request на GitHub
- **THEN** описание заполнено чек-листом из `.github/pull_request_template.md` с пунктами об OpenSpec change, тестах и стороннем коде

#### Scenario: e2e CLI против Dart-агента в CI
- **WHEN** CI запускается на pull request
- **THEN** джоб `e2e-cli-dart` на `ubuntu-latest` прогоняет e2e терминального клиента против Dart-агента, и его падение делает pull request красным

### Requirement: PTY-e2e терминального клиента
E2E-тесты `apps/codelab_cli/test/e2e/` SHALL запускать CLI как процесс (Dart VM, программа один раз компилируется в kernel) против агента, выбранного переменной окружения `CODELAB_E2E_AGENT`: `scripted` (по умолчанию) — scripted stdio-агент из `codelab_acp_testing`; `dart` — `codelab-agent serve --stdio` со сценарием `--llm-script` из `test/e2e/llm_scripts/`, запущенный из kernel без импорта `package:codelab_agent_*`; `python` — `codelab serve --stdio` из `PATH` с временным `CODELAB_HOME` и провайдером `mock`. Ожидания, которые у агентов различаются (текст ответа, заголовок и команда одобрения, итог одобрения, модели), SHALL браться из одного помощника `test/e2e/support/e2e_agent.dart`, а не из текстов конкретного агента в тестах. Тесты поведения, которое есть только у scripted-агента, и тесты, не зависящие от агента, SHALL иметь тег `scripted-only`; тесты обычного хода, которые идут и против Python-агента, — тег `python-agent`. Каждый сценарий `--llm-script` e2e CLI SHALL загружаться без ошибок (`apps/codelab_agent/test/llm_scripts_load_test.dart`); имена тестов SHALL совпадать с id критериев матрицы целей (`cli/<id>`). Интерактивные сценарии SHALL идти через псевдотерминал системной утилиты `script` (обвязка `test/e2e/support/pty_process.dart`), команда которой собирается по ОС в одном месте: BSD `script` на macOS, util-linux `script` на Linux. Без утилиты и на Windows PTY-тест SHALL пропускаться с сообщением, а не падать. Переводы строк PTY SHALL нормализоваться перед сравнением. E2E CLI SHALL входить в `melos run test` (Dart VM, `AGENTS.md` §21) и НЕ SHALL требовать устройства или симулятора. Тест против Python-агента SHALL пропускаться с сообщением, если агент не установлен (`codelab serve --help` не отвечает как Python-агент). Полноэкранный режим SHALL проверяться на трёх уровнях: модульными тестами чистого ядра экрана (`reduce`, `render`) без терминала и без `dart_tui`; тестами адаптера через `Program` с `withInput`/`withOutput`/`withWindowSize`/`withoutSignalHandler`, без терминала, где ответы терминала (kitty, modifyOtherKeys, bracketed paste) подаются байтами; дымовым PTY-e2e `cli/tui-smoke`.

#### Scenario: Обвязка даёт терминал
- **WHEN** `PtyProcess.start('sh', ['-c', 'test -t 0 && test -t 1; exit 3'], columns: 100, rows: 30)` на macOS или Linux
- **THEN** код выхода — `3`, а `tput cols` внутри обвязки печатает `100`

#### Scenario: Нет утилиты script
- **WHEN** `script` нет в `PATH`
- **THEN** PTY-тесты помечаются пропущенными с причиной, прогон зелёный

#### Scenario: Дымовой тест TUI
- **WHEN** `cli/tui-smoke` запускает `codelab --ui tui` в PTY 100×30 против scripted-агента, вводит промпт и Ctrl+D
- **THEN** ответ агента виден на экране, вывод содержит `ESC[?1049h`, затем `ESC[?1049l`, `ESC[?2004l` и `ESC[?25h`, код выхода `0`

#### Scenario: Тот же тест против Dart-агента
- **WHEN** `cli/repl-permission-allow-once` идёт с `CODELAB_E2E_AGENT=dart`
- **THEN** блок одобрения показывает команду `echo hello` из сценария, `y` разрешает вызов, а ход заканчивается выполненным вызовом `echo hello`

#### Scenario: Python-агент не установлен
- **WHEN** `CODELAB_E2E_AGENT=python`, а `codelab serve --help` не отвечает как Python-агент
- **THEN** тесты с тегом `python-agent` пропущены с причиной `Python agent (codelab serve) is not installed`, прогон зелёный

#### Scenario: Ответ Python-агента
- **WHEN** `cli/headless-print-basic` идёт с `CODELAB_E2E_AGENT=python` и установленным Python-агентом
- **THEN** stdout содержит `Mock response`, код выхода `0`
