## Purpose

Архитектурная форма CodeLab на уровне всего репозитория: границы пакетов monorepo, слоистая Clean Architecture внутри них, дисциплина SOLID/KISS/DRY, удерживающая эти границы осмысленными, настройка dependency injection через CherryPick и стандартные библиотеки моделирования (`fpdart`, `freezed`), которыми держится типизация состояния и результатов.

## Requirements

### Requirement: Границы пакетов monorepo
CodeLab SHALL использовать Dart/Flutter/FVM/Melos monorepo с разделёнными пакетами `acp_protocol`, `acp_transports`, `acp_client_core`, `acp_testing`, `acp_ui` и `codelab_app`.

#### Scenario: Пакеты workspace присутствуют
- **WHEN** реализация разворачивает workspace
- **THEN** репозиторий содержит все требуемые пакеты, и у каждого есть собственный `pubspec.yaml`

#### Scenario: Чистые Dart-пакеты остаются свободными от Flutter
- **WHEN** запускается статический анализ для `packages/dart/*`
- **THEN** ни один чистый Dart-пакет не импортирует Flutter, `fluent_ui`, Bloc или код UI приложения

### Requirement: Границы Clean Architecture
CodeLab SHALL следовать Clean Architecture с гексагональными границами, где `Domain` и `Application` не зависят от `Presentation` или конкретной `Infrastructure`.

#### Scenario: Domain зависит только от абстракций
- **WHEN** use case нуждается в поведении transport, логирования, approval или persistence
- **THEN** он зависит от порта/интерфейса, а не от конкретного адаптера

#### Scenario: Infrastructure подключается в composition root
- **WHEN** приложение запускается
- **THEN** конкретные адаптеры подключаются в composition root `apps/codelab_app`

### Requirement: Ограничения SOLID, KISS и DRY
CodeLab SHALL соблюдать SOLID, KISS и DRY как ограничения реализации, не создавая преждевременных абстракций или god-сервисов.

#### Scenario: Ответственность сервиса остаётся узкой
- **WHEN** добавляется сервис
- **THEN** у него одна чёткая ответственность, и он не совмещает протокол, transport, состояние, approvals и побочные эффекты UI

#### Scenario: Общая логика централизована
- **WHEN** реализуются кодеки ACP, переходы состояний или переиспользуемые UI-примитивы
- **THEN** они централизованы соответственно в `acp_protocol`, `acp_client_core` или `acp_ui/atomics`

### Requirement: CherryPick как dependency injection
CodeLab SHALL использовать CherryPick v4.x.x как DI-framework, настроенный в composition root приложения.

#### Scenario: Жизненный цикл root scope
- **WHEN** Flutter-приложение запускается и завершает работу
- **THEN** root scope CherryPick создаётся при bootstrap и закрывается при shutdown

#### Scenario: Domain избегает обращения к service locator
- **WHEN** классу domain или application нужны зависимости
- **THEN** он получает их через конструкторы или фабрики, а не через произвольный доступ к service locator

### Requirement: Стандартные библиотеки моделирования
CodeLab SHALL использовать `fpdart` для типизированных восстановимых результатов/опций и `freezed` для immutable-состояния, DTO и union-моделей там, где это повышает типобезопасность.

#### Scenario: Восстановимая ошибка моделируется типом
- **WHEN** use case может завершиться неудачей без падения приложения
- **THEN** он возвращает типизированный результат вроде `Either`, а не бросает неструктурированные исключения

#### Scenario: Union-состояние моделируется типом
- **WHEN** состояние сессии, prompt turn или approval имеет несколько вариантов
- **THEN** оно представлено immutable типизированными моделями, пригодными для исчерпывающей обработки
