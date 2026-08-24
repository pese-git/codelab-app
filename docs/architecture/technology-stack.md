# Технологический стек ACP Client

Этот документ описывает утверждённый технологический стек проекта **ACP Client**, назначение используемых технологий и правила их применения.

Документ определяет **роль технологий и архитектурные ограничения**, но не дублирует точные версии зависимостей.

Источники истины для версий:

* `.fvm/fvm_config.json` — используемая версия Flutter SDK;
* `pubspec.yaml` — ограничения версий и declared dependencies;
* `pubspec.lock` — разрешённые версии зависимостей;
* `melos.yaml` — monorepo orchestration.

Общие обязательные правила для AI-agents находятся в корневом `AGENTS.md`.

---

## 1. Общий стек

Проект использует:

| Область                    | Технология              |
| -------------------------- | ----------------------- |
| Язык                       | Dart                    |
| UI                         | Flutter Desktop         |
| Design system              | Fluent UI (`fluent_ui`) |
| State management           | `flutter_bloc`          |
| Dependency Injection       | Cherrypick              |
| Functional primitives      | `fpdart`                |
| Immutable/generated models | Freezed                 |
| Code generation            | `build_runner`          |
| Monorepo                   | Dart Workspace + Melos  |
| Flutter SDK management     | FVM                     |
| Specifications             | OpenSpec                |
| Flutter tests              | `flutter_test`          |
| Integration tests          | `integration_test`      |
| Lints                      | `flutter_lints`         |

Технологии из этой таблицы считаются **утверждёнными решениями проекта**.

Не следует добавлять альтернативный framework для той же задачи без явной архитектурной причины.

---

## 2. Dart

Основной язык проекта — Dart.

Текущий допустимый SDK range определяется `pubspec.yaml`.

Dart используется для:

* ACP protocol;
* transports;
* client/application logic;
* domain logic;
* infrastructure;
* testing utilities;
* Flutter application logic.

Если задача не требует Flutter API, следует предпочитать pure Dart implementation.

Это особенно важно для reusable packages.

---

## 3. Flutter Desktop

Flutter используется для desktop application и presentation layer.

Основное приложение:

`apps/codelab_app`

Flutter-specific код следует ограничивать слоями и packages, которым действительно необходим Flutter.

Pure Dart packages НЕ ДОЛЖНЫ получать dependency на Flutter только ради:

* `BuildContext`;
* UI events;
* convenience utilities;
* state management presentation layer;
* dialogs;
* navigation.

Application/domain behavior следует сохранять независимым от Flutter там, где это практически возможно.

---

## 4. FVM

Flutter SDK управляется через FVM.

Источник истины для фактически используемой версии:

`.fvm/fvm_config.json`

Flutter/Dart commands должны выполняться через FVM:

```bash
fvm flutter ...
fvm dart ...
```

Не следует полагаться на глобально установленный Flutter SDK.

CI должен использовать ту же версию Flutter SDK, что определена FVM configuration.

SDK constraints из `pubspec.yaml` определяют допустимые версии, но не заменяют FVM как механизм фиксации SDK для разработки.

---

## 5. Dart Workspace

Packages используют Dart workspace dependency resolution:

```yaml
resolution: workspace
```

Workspace отвечает за:

* совместное dependency resolution;
* работу local packages;
* согласованный dependency graph monorepo.

Dart Workspace и Melos выполняют разные функции:

```text
Dart Workspace
    └── dependency resolution

Melos
    └── repository orchestration
```

Не следует использовать Melos как замену workspace dependency resolution.

---

## 6. Melos

Melos используется для управления repository-wide operations.

Основные задачи:

* bootstrap;
* formatting;
* static analysis;
* tests;
* code generation;
* выполнение команд по packages.

Основные команды определяются `melos.yaml`.

Типовые операции:

```bash
melos bootstrap
melos format
melos analyze
melos test
```

После изменения package structure или dependencies следует выполнить соответствующий bootstrap workflow проекта.

Repository-wide scripts следует по возможности централизовать в Melos вместо создания множества независимых shell scripts.

---

## 7. Fluent UI

Основная UI/design system проекта:

`fluent_ui`

Новые application widgets следует реализовывать в соответствии с Fluent UI, если конкретная задача не требует другого.

Не следует вводить Material или Cupertino как параллельную design system приложения.

Наличие:

```yaml
flutter:
  uses-material-design: true
```

само по себе не означает, что Material является основной UI-системой проекта.

Допустимо использовать Flutter/Material infrastructure, если она требуется сторонними packages или Flutter ecosystem, но визуальная система приложения должна оставаться согласованной.

Reusable ACP-specific Flutter components размещаются в:

`packages/flutter/acp_ui`

---

## 8. State management

Основной state-management framework:

`flutter_bloc`

BLoC/Cubit является утверждённым механизмом управления application/presentation state в Flutter layer.

Не следует добавлять competing state-management frameworks:

* Riverpod;
* Provider;
* GetX;
* MobX;
* Redux;
* другой аналогичный framework;

если существующий BLoC architecture решает задачу.

### 8.1. Ответственность BLoC/Cubit

BLoC/Cubit может:

* принимать user intents;
* вызывать application APIs;
* координировать presentation flow;
* преобразовывать application state в presentation state;
* хранить UI-relevant state;
* реагировать на application events.

BLoC/Cubit НЕ ДОЛЖЕН становиться местом для любой логики приложения.

В частности, он НЕ ДОЛЖЕН:

* реализовывать ACP serialization/deserialization;
* реализовывать low-level transport;
* напрямую управлять sockets/processes;
* содержать platform-specific filesystem implementation;
* выполнять security policy;
* самостоятельно реализовывать ACP protocol semantics.

Значимая reusable application logic должна находиться ниже Flutter presentation boundary.

---

## 9. Dependency Injection — Cherrypick

Основной dependency injection framework:

* `cherrypick`;
* `cherrypick_annotations`;
* `cherrypick_generator`.

Cherrypick является утверждённым механизмом dependency composition.

Не следует добавлять параллельный DI container, например:

* `get_it`;
* `injectable`;
* другой service locator;
* собственный global dependency registry;

если Cherrypick уже покрывает задачу.

### 9.1. Composition root

Создание concrete infrastructure dependencies должно происходить в ограниченном количестве composition roots.

Например:

```text
Application bootstrap
        │
        ▼
DI / composition
        │
        ├── ACP transports
        ├── ACP client
        ├── repositories
        ├── platform adapters
        └── BLoC dependencies
```

Widgets НЕ ДОЛЖНЫ вручную создавать infrastructure dependencies.

### 9.2. DI не является архитектурой

Наличие DI container не означает, что любая dependency разрешена.

Cherrypick должен соединять компоненты в соответствии с dependency rules проекта, а не обходить их.

---

## 10. `fpdart`

Проект использует:

`fpdart`

`fpdart` является утверждённым набором functional programming primitives.

Он может использоваться для:

* `Either`;
* `Option`;
* typed results;
* композиции операций;
* явного представления ожидаемых failures.

Следует придерживаться существующего error-handling pattern проекта.

Не следует без необходимости смешивать несколько способов представления одной категории ошибок:

```text
Either<Failure, T>
Result<T>
nullable T
Exception
bool success
```

Expected failures следует представлять последовательно.

Exceptions остаются допустимыми:

* на boundaries сторонних libraries;
* для truly exceptional conditions;
* для programming errors;

но при переходе через application boundary их следует преобразовывать в утверждённую error model, когда это имеет смысл.

---

## 11. Freezed

Проект использует Freezed для generated immutable models там, где это оправдано.

Freezed подходит для:

* immutable state;
* union/sealed-like state representations;
* application models;
* presentation models;
* typed state machines.

Не следует использовать Freezed автоматически для каждого DTO или простого value object.

Использование code generation должно давать практическую пользу:

* immutable semantics;
* exhaustive states;
* `copyWith`;
* equality;
* снижение boilerplate.

Generated files НЕ ДОЛЖНЫ редактироваться вручную.

---

## 12. Code generation

Основной code-generation stack:

* `build_runner`;
* `freezed`;
* `cherrypick_generator`.

Code generation следует запускать стандартизированной repository command, предпочтительно через Melos.

Generated output должен быть воспроизводим из source files.

AI-agent НЕ ДОЛЖЕН вручную исправлять generated Dart files вместо изменения их source definitions.

При изменении generated model/DI definition агент должен определить, требуется ли повторный запуск generator.

---

## 13. ACP package architecture

ACP functionality разделена на специализированные packages:

```text
packages/
├── dart/
│   ├── acp_protocol/
│   ├── acp_transports/
│   ├── acp_client_core/
│   └── acp_testing/
│
└── flutter/
    └── acp_ui/
```

Такое разделение является архитектурной boundary, а не только организацией файлов.

---

## 14. `acp_protocol`

Package:

`packages/dart/acp_protocol`

Тип: **pure Dart**.

Отвечает за wire-level ACP.

Допустимая ответственность:

* protocol messages;
* request/response models;
* notifications;
* identifiers;
* protocol serialization;
* protocol deserialization;
* protocol-level validation;
* protocol errors;
* protocol version compatibility.

НЕ ДОЛЖЕН зависеть от:

* Flutter;
* `flutter_bloc`;
* `fluent_ui`;
* `acp_ui`;
* application widgets;
* navigation;
* dialogs.

`acp_protocol` описывает ACP wire contract, а не presentation model приложения.

---

## 15. `acp_transports`

Package:

`packages/dart/acp_transports`

Тип: **pure Dart**, пока transport implementation не требует иного архитектурного решения.

Отвечает за transport-level взаимодействие.

Например:

* stdio/process transport;
* stream-based transport;
* socket/network transport;
* connection primitives;
* transport errors;
* framing, если это ответственность transport.

Transport НЕ ДОЛЖЕН:

* зависеть от Flutter presentation;
* показывать dialogs;
* управлять navigation;
* содержать BLoC;
* принимать UX decisions.

Transport должен предоставлять API, пригодный для использования pure Dart client layer.

---

## 16. `acp_client_core`

Package:

`packages/dart/acp_client_core`

Тип: **pure Dart**.

Содержит reusable client-side ACP application logic.

Предполагаемая ответственность:

* ACP client orchestration;
* session behavior;
* application-level ACP events;
* request lifecycle;
* cancellation;
* permission abstractions;
* connection/session coordination;
* преобразование protocol events в client-level concepts.

`acp_client_core` НЕ ДОЛЖЕН зависеть от:

* Flutter;
* widgets;
* `BuildContext`;
* `fluent_ui`;
* `flutter_bloc`;
* `acp_ui`.

Если behavior может быть реализовано без Flutter и является общим для ACP client, следует сначала рассмотреть размещение в `acp_client_core`, а не в `codelab_app`.

При этом `acp_client_core` НЕ ДОЛЖЕН превращаться в dumping ground для любой application logic.

---

## 17. `acp_ui`

Package:

`packages/flutter/acp_ui`

Тип: **Flutter package**.

Отвечает за reusable ACP-specific presentation components.

Утверждённый stack:

* Flutter;
* `fluent_ui`;
* `flutter_bloc`.

Может содержать:

* reusable ACP widgets;
* ACP presentation components;
* presentation models;
* BLoC-aware reusable UI;
* common ACP visual states.

НЕ ДОЛЖЕН:

* реализовывать ACP transport;
* владеть low-level connection;
* зависеть от `codelab_app`;
* содержать desktop application-specific composition;
* реализовывать platform-specific infrastructure без явной необходимости.

`acp_ui` должен оставаться reusable Flutter boundary.

---

## 18. `acp_testing`

Package:

`packages/dart/acp_testing`

Предназначен для reusable ACP testing infrastructure.

Может содержать:

* fakes;
* fixtures;
* test builders;
* fake transports;
* protocol test helpers;
* reusable test scenarios.

Production packages НЕ ДОЛЖНЫ зависеть от `acp_testing`.

`acp_testing` следует сохранять pure Dart, если Flutter dependency не является необходимой.

Flutter-specific testing helpers при значительном объёме следует отделять от pure Dart testing utilities.

---

## 19. `codelab_app`

Application:

`apps/codelab_app`

является desktop composition root и конечным приложением.

Он объединяет:

* ACP packages;
* Flutter UI;
* state management;
* DI;
* desktop-specific integration;
* application-specific features.

`codelab_app` может зависеть от:

* `acp_client_core`;
* `acp_protocol`;
* `acp_transports`;
* `acp_ui`;
* утверждённых Flutter/application dependencies.

Однако наличие прямой dependency не означает, что любой слой приложения может использовать package напрямую.

Например, widget не должен обращаться к `acp_transports` только потому, что package объявлен в `codelab_app/pubspec.yaml`.

Architectural dependency rules важнее технической доступности dependency.

---

## 20. Направление package dependencies

Целевая модель ACP subsystem:

```text
                  ┌──────────────────┐
                  │   codelab_app    │
                  │ composition root │
                  └────────┬─────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
          acp_ui    acp_client_core   desktop
                          │           adapters
                 ┌────────┴────────┐
                 │                 │
                 ▼                 ▼
          acp_transports     acp_protocol
                 │
                 ▼
          external agent
```

Точная dependency matrix определяется:

`docs/architecture/layers-and-dependencies.md`

Основные invariants:

* `acp_protocol` не зависит от Flutter packages;
* `acp_transports` не зависит от Flutter UI;
* `acp_client_core` остаётся pure Dart;
* `acp_ui` не зависит от `codelab_app`;
* `codelab_app` выполняет composition;
* lower-level packages не зависят от application package.

---

## 21. Testing stack

Используются:

* `flutter_test`;
* `integration_test`;
* `acp_testing`;
* стандартные Dart testing capabilities там, где применимо.

Предпочтительный уровень тестирования определяется типом кода:

```text
Pure Dart logic
    → Dart unit tests

ACP protocol
    → protocol/serialization tests

ACP client core
    → unit + lifecycle tests

Flutter presentation
    → BLoC + widget tests

Desktop integration
    → integration tests
```

Pure Dart logic НЕ СЛЕДУЕТ тестировать через Flutter binding, если достаточно обычного unit test.

Reusable ACP test infrastructure следует размещать в `acp_testing`.

Подробная стратегия:

`docs/architecture/testing.md`

---

## 22. Static analysis

Проект использует:

`flutter_lints`

Конкретные lint rules определяются repository `analysis_options.yaml`.

Source of truth — фактическая конфигурация analyzer, а не этот документ.

Изменённый код должен проходить static analysis в соответствии с правилами `AGENTS.md`.

---

## 23. Desktop dependencies

Любая новая desktop-specific dependency должна быть проверена минимум по следующим критериям:

* Windows support;
* macOS support;
* Linux support;
* native dependencies;
* lifecycle;
* threading/isolate behavior;
* security implications;
* maintenance status.

Platform plugin следует изолировать за adapter, если его API начинает проникать в application logic.

Например:

```text
Feature
   │
   ▼
Application port
   ▲
   │
Desktop adapter
   │
   ▼
Platform plugin
```

Это позволяет менять implementation без распространения plugin API по приложению.

---

## 24. Новые dependencies

Перед добавлением новой dependency агент ОБЯЗАН проверить:

1. Решает ли уже существующая dependency ту же задачу.
2. Можно ли решить задачу средствами Dart/Flutter SDK.
3. Соответствует ли dependency архитектуре проекта.
4. Поддерживает ли она необходимые desktop platforms.
5. Совместима ли она с текущими SDK constraints.
6. Не вводит ли она competing framework.
7. Требует ли native configuration.
8. Как она влияет на testing.
9. Как она влияет на security.
10. Требуется ли ADR.

Особенно НЕ СЛЕДУЕТ без архитектурного решения добавлять альтернативы:

* `flutter_bloc`;
* Cherrypick;
* `fluent_ui`;
* `fpdart`;
* Freezed.

---

## 25. Когда требуется ADR

Architecture Decision Record требуется при значимом изменении технологического направления.

В частности, при:

* замене `flutter_bloc`;
* добавлении второго state-management framework;
* замене Cherrypick;
* добавлении второго DI container;
* смене основной UI/design system;
* изменении ACP transport architecture;
* выборе persistence technology;
* выборе networking stack;
* изменении error-handling strategy;
* значимом изменении code-generation strategy;
* выборе значимой platform integration technology.

Обычное обновление существующей dependency в пределах совместимого release само по себе обычно ADR не требует.

Если upgrade приводит к архитектурным или behavioral изменениям, необходимость ADR/OpenSpec оценивается по характеру этих изменений.

---

## 26. Добавление технологии в стек

При утверждении новой технологии этот документ должен быть обновлён.

Для технологии необходимо указать:

1. Назначение.
2. Где она может использоваться.
3. Где она не должна использоваться.
4. Какую существующую проблему она решает.
5. Как она влияет на architecture boundaries.
6. Заменяет ли она существующую технологию.
7. Требуется ли migration.
8. Требуется ли ADR.

`technology-stack.md` должен описывать **актуальный утверждённый стек**, а не историю всех ранее использовавшихся libraries.

История значимых решений хранится в ADR.
