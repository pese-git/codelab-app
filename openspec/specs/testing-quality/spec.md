## Purpose

Планка тестирования и качества workspace, которой CodeLab придерживается сам: Melos-скрипты, по которым проверяется каждое изменение, и многоуровневое тестовое покрытие (протокол, core state, stdio-интеграция, Flutter UI), на котором держится Definition of Done для задач реализации.
## Requirements
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

### Requirement: Модульные тесты протокола
CodeLab SHALL тестировать encode/decode протокола, обработку неизвестных полей, валидацию невалидных сообщений и отображение протокольных ошибок.

#### Scenario: Декодируются неизвестные поля
- **WHEN** валидное сообщение ACP включает `_meta` или совместимые с будущим поля
- **THEN** round-trip encode/decode сохраняет поддерживаемые данные расширения

#### Scenario: Декодируется невалидное сообщение
- **WHEN** получены невалидные данные ACP
- **THEN** тесты подтверждают типизированную протокольную ошибку вместо падения приложения

### Requirement: Тесты core state
CodeLab SHALL тестировать переходы состояния сессии, обработку дублирующихся событий потока, политику approval и пути отмены.

#### Scenario: Получено дублирующееся событие потока
- **WHEN** fake transport эмитирует одно и то же обновление дважды
- **THEN** видимое состояние содержит одну логическую запись сообщения/tool/approval

#### Scenario: Отмена происходит при ожидающих approval
- **WHEN** отмена происходит при наличии ожидающих запросов разрешения
- **THEN** тесты подтверждают, что каждый запрос получает outcome cancelled

### Requirement: Интеграционные тесты stdio
CodeLab SHALL тестировать stdio-интеграцию с `codelab-agent` либо совместимым тестовым двойником, использующим ту же семантику запуска/профиля.

#### Scenario: Референсный агент инициализируется
- **WHEN** тест stdio-интеграции запускает настроенную команду
- **THEN** CodeLab завершает `initialize` ACP

#### Scenario: Prompt turn стримит
- **WHEN** интеграционный тест отправляет `session/prompt`
- **THEN** CodeLab получает потоковые `session/update` и финальный ответ на prompt

### Requirement: Тесты Flutter UI
CodeLab SHALL тестировать состояния соединения, поведение prompt composer, рендеринг потокового transcript, approvals, видимость отмены, состояния ошибок и layout workbench.

#### Scenario: Рендерится UI approval
- **WHEN** состояние approval передано в UI
- **THEN** inline approval и детали инспектора видны с элементами approve/reject

#### Scenario: Рендерится следующее действие для состояния ошибки
- **WHEN** UI получает состояние disconnected или failed
- **THEN** он показывает понятную пользователю сводку и конкретное действие для восстановления

### Requirement: Соблюдение Definition of Done
CodeLab SHALL рассматривать тесты, архитектурные границы, политику безопасности и требования UI/UX как критерии приёмки для задач реализации.

#### Scenario: Задача реализации завершена
- **WHEN** задача помечена выполненной
- **THEN** релевантные тесты проходят, и задача удовлетворяет Definition of Done из спеки

### Requirement: Непрерывная интеграция
CodeLab SHALL запускать CI (`.github/workflows/ci.yml`) на каждый pull request и на push в `master` и `develop`. Обязательные джобы `format`, `analyze`, `test`, `conformance`, `guard` и `web-compile` SHALL запускать соответствующие Melos-скрипты на FVM-закреплённом SDK. Ночной запуск по расписанию SHALL прогонять те же джобы. Интеграционные тесты в CI SHALL выполняться только на Dart VM (`ubuntu-latest`); Flutter-тесты приложения на macOS (`test:e2e:app:*`) в CI НЕ SHALL запускаться — это локальные приёмочные ворота этапа. Шаблон pull request SHALL содержать чек-лист: OpenSpec change, тесты, сторонний код.

#### Scenario: Pull request с нарушением
- **WHEN** открыт pull request, в котором нарушен формат, анализ, тест, сторож или web-компиляция
- **THEN** соответствующий джоб CI красный

#### Scenario: Интеграционные тесты на Dart VM
- **WHEN** CI запускается на pull request, push или по расписанию
- **THEN** интеграционные тесты чистых Dart-пакетов (реальные процессы и сокеты `acp_transports`) выполняются в джобе `test` на `ubuntu-latest`, а джобов на macOS в workflow нет

#### Scenario: Шаблон pull request
- **WHEN** автор открывает pull request на GitHub
- **THEN** описание заполнено чек-листом из `.github/pull_request_template.md` с пунктами об OpenSpec change, тестах и стороннем коде

### Requirement: Клиентская conformance-проверка на корпусе фикстур
CodeLab SHALL проигрывать каждую golden-фикстуру с ролью `client` против `AcpClientApplication` тестом `packages/dart/acp_client_core/test/fixtures/client_fixture_conformance_test.dart`. Melos-скрипт `conformance:client` SHALL запускать эту проверку и SHALL входить в полную проверку `check` и в джоб CI `conformance`.

#### Scenario: Корпус этапа 0 проходит
- **WHEN** выполняется `fvm dart run melos run conformance:client`
- **THEN** все 12 фикстур этапа 0 с ролью `client` проходят

#### Scenario: Полная проверка включает клиентский прогон
- **WHEN** выполняется `fvm dart run melos run check` или джоб CI `conformance`
- **THEN** запускается и `protocol-conformance`, и `conformance:client`

