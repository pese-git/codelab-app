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

### Requirement: Интеграционные тесты stdio
CodeLab SHALL тестировать stdio-интеграцию с `codelab-agent` либо совместимым тестовым двойником, использующим ту же семантику запуска/профиля. E2E-тесты `apps/codelab_app/integration_test/` SHALL параметризоваться агентом через `--dart-define=CODELAB_E2E_AGENT=scripted|dart` (по умолчанию `scripted`) и помощник `integration_test/support/e2e_agent.dart`; в режиме `dart` агент — бинарь `CODELAB_E2E_AGENT_BIN` со сценарием `integration_test/llm_scripts/<режим>.json`. Тесты поведения именно scripted-агента SHALL иметь тег `scripted-only` и исключаться в режиме `dart`. Код `apps/codelab_app/lib` для этого НЕ SHALL меняться. Прогон на устройстве или симуляторе (`melos run test:e2e:app:dart-agent`) SHALL выполняться только в ветке `release/<version>`; в feature-ветке тесты SHALL проходить статический анализ.

#### Scenario: Референсный агент инициализируется
- **WHEN** тест stdio-интеграции запускает настроенную команду
- **THEN** CodeLab завершает `initialize` ACP

#### Scenario: Prompt turn стримит
- **WHEN** интеграционный тест отправляет `session/prompt`
- **THEN** CodeLab получает потоковые `session/update` и финальный ответ на prompt

#### Scenario: Тест в режиме Dart-агента
- **WHEN** `permission_flow_test.dart` запускается с `CODELAB_E2E_AGENT=dart`
- **THEN** карточка одобрения показывает заголовок `Run echo hello` и команду `echo hello` из аргументов вызова

#### Scenario: Тест только для scripted-агента
- **WHEN** e2e-прогон идёт с `--exclude-tags scripted-only`
- **THEN** тест `agent dying mid-turn` не запускается
