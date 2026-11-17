## MODIFIED Requirements

### Requirement: Непрерывная интеграция
CodeLab SHALL запускать CI (`.github/workflows/ci.yml`) на каждый pull request и на push в `master` и `develop`. Обязательные джобы `format`, `analyze`, `test`, `conformance`, `guard`, `web-compile` и `e2e-cli-dart` SHALL запускать соответствующие Melos-скрипты на FVM-закреплённом SDK; `e2e-cli-dart` — `test:e2e:cli:dart-agent`. Обязательный джоб `site` SHALL проверять сайт `site/` на Node из `site/.nvmrc` (project-site «Проверка сайта в CI»; design.md change `add-astro-site`, D13); итоговый джоб `ci` SHALL ждать его наравне с джобами матрицы. Python-агента в CI нет, и прогон против него в CI НЕ SHALL запускаться. Ночной запуск по расписанию SHALL прогонять те же джобы. Интеграционные тесты в CI SHALL выполняться только на Dart VM (`ubuntu-latest`); Flutter-тесты приложения на macOS (`test:e2e:app:*`) в CI НЕ SHALL запускаться — это локальные приёмочные ворота этапа. Шаблон pull request SHALL содержать чек-лист: OpenSpec change, тесты, сторонний код.

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

#### Scenario: Сайт в CI
- **WHEN** CI запускается на pull request, который меняет `site/**` или опубликованную документацию
- **THEN** джоб `site` на `ubuntu-latest` собирает и проверяет сайт, и его падение делает итоговый джоб `ci` и pull request красными
