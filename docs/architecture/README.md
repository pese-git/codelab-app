# Архитектура ACP Client

Этот каталог содержит архитектурную документацию **ACP Client** — Flutter Desktop приложения для взаимодействия с AI agents по ACP (Agent Client Protocol).

Документы предназначены для:

* разработчиков;
* AI coding agents;
* code review;
* проектирования новых features;
* анализа архитектурных изменений.

Обязательные repository-wide правила находятся в корневом:

`AGENTS.md`

Спецификации поведения находятся в:

`openspec/specs/`

Активные изменения находятся в:

`openspec/changes/`

---

## 1. Назначение архитектурной документации

`AGENTS.md` определяет **что необходимо соблюдать**.

`docs/architecture/` объясняет:

* как устроена система;
* где проходят архитектурные boundaries;
* какой компонент владеет определённым поведением;
* как взаимодействуют слои;
* какие architectural invariants должны сохраняться;
* почему были выбраны определённые решения.

OpenSpec определяет **поведение продукта и contracts**.

Таким образом:

```text id="gh7bl1"
AGENTS.md
    │
    └── обязательные engineering rules

docs/architecture/
    │
    └── устройство системы и architectural decisions

openspec/specs/
    │
    └── ожидаемое поведение и contracts

openspec/changes/
    │
    └── проектируемые изменения
```

---

## 2. Архитектурные принципы

Архитектура проекта строится вокруг следующих принципов.

### Явные boundaries

Внешние системы должны быть отделены от application logic.

К внешним boundaries относятся:

* ACP;
* filesystem;
* network;
* persistence;
* secure storage;
* operating system;
* native APIs;
* external processes.

Flutter UI не должен напрямую управлять этими системами.

---

### Feature-first

Application code организуется прежде всего вокруг пользовательских и application capabilities, а не вокруг технических типов файлов.

Предпочтительно:

```text id="kn3tkv"
features/
├── chat/
├── sessions/
├── permissions/
└── settings/
```

вместо глобальной структуры:

```text id="uf8ls2"
controllers/
services/
repositories/
models/
widgets/
```

Внутри сложной feature допускается разделение на:

```text id="8zn3l3"
domain/
application/
infrastructure/
presentation/
```

Не каждая feature обязана иметь все эти слои.

---

### Dependency direction

Основное направление dependencies:

```text id="ubqzy4"
presentation
     │
     ▼
application
     │
     ▼
domain

infrastructure
     │
     └────► application / domain
```

Внешние технологии располагаются на краях архитектуры.

---

### ACP — внешний protocol boundary

ACP wire model не является моделью UI.

```text id="ofop1f"
ACP
 │
 ▼
Protocol
 │
 ▼
Transport
 │
 ▼
Application
 │
 ▼
Application State
 │
 ▼
Presentation
```

Изменения ACP не должны без необходимости распространяться по всему приложению.

---

### Явное состояние

Сложное application state должно моделироваться явно.

Особенно это относится к:

* connection lifecycle;
* session lifecycle;
* prompt execution;
* streaming;
* cancellation;
* reconnect;
* permission requests.

Следует избегать набора независимых flags, допускающих невозможные состояния.

---

### Controlled side effects

Side effects должны иметь явного владельца.

Например:

```text id="20m91d"
filesystem
network
ACP transport
secure storage
process execution
native APIs
```

не должны вызываться произвольно из widgets или domain.

---

### Architecture proportionality

Архитектура должна защищать boundaries, а не увеличивать количество файлов.

Не требуется создавать:

```text id="m3ydt2"
Repository
RepositoryImpl
Service
ServiceImpl
UseCase
Manager
```

для каждой простой операции.

Abstraction вводится тогда, когда существует реальная architectural boundary или testability benefit.

---

## 3. Карта документации

### `technology-stack.md`

Описывает утверждённый технологический стек:

* Flutter/Dart;
* state management;
* dependency injection;
* routing;
* serialization;
* persistence;
* logging;
* testing;
* code generation;
* desktop libraries;
* monorepo tooling.

Читать перед добавлением новой dependency или framework.

---

### `layers-and-dependencies.md`

Определяет:

* application layers;
* responsibilities слоёв;
* разрешённые dependencies;
* запрещённые dependencies;
* package boundaries;
* feature boundaries.

Читать перед созданием новой feature, package или существенным refactoring.

---

### `acp-boundary.md`

Описывает:

* место ACP в архитектуре;
* wire DTO;
* serialization;
* transport;
* application mapping;
* protocol errors;
* versioning;
* compatibility.

Читать перед изменением:

* `packages/acp_protocol`;
* ACP transport;
* ACP message handling;
* protocol mapping.

---

### `session-lifecycle.md`

Описывает state machine ACP connection/session.

Включает:

* connect;
* disconnect;
* session creation;
* running;
* cancellation;
* reconnect;
* failure;
* recovery.

Читать перед изменением session или connection lifecycle.

---

### `streaming.md`

Определяет правила обработки streaming events:

* ordering;
* duplicate events;
* replay;
* incremental updates;
* completion;
* stale events;
* correlation.

Читать перед изменением streaming behavior.

---

### `permissions.md`

Описывает security boundary для действий AI agent:

* permission policy;
* permission request;
* user decision;
* tool call correlation;
* deny-by-default;
* security-sensitive capabilities.

Читать перед изменением tool calls или permission flow.

---

### `concurrency.md`

Определяет правила:

* async operations;
* streams;
* subscriptions;
* cancellation;
* race conditions;
* ownership;
* disposal;
* isolates;
* stale results.

Читать перед реализацией нетривиального asynchronous behavior.

---

### `state-management.md`

Описывает:

* выбранный state-management подход;
* ownership state;
* application state;
* presentation state;
* controllers/notifiers;
* derived state;
* lifecycle state.

Читать перед созданием нового state holder.

---

### `platform-integration.md`

Описывает integration с desktop OS:

* Windows;
* macOS;
* Linux;
* filesystem;
* native APIs;
* window management;
* secure storage;
* external processes;
* platform adapters.

Читать перед добавлением platform-specific поведения.

---

### `observability.md`

Определяет:

* logging;
* correlation IDs;
* protocol tracing;
* sensitive data masking;
* debug diagnostics;
* error reporting.

Читать перед изменением logging или diagnostics.

---

### `testing.md`

Определяет testing strategy:

* unit tests;
* application tests;
* protocol tests;
* widget tests;
* integration tests;
* mocks/fakes;
* architecture tests.

Читать при добавлении новых видов тестов или изменении testing strategy.

---

## 4. Карта чтения для AI-agent

AI-agent не обязан читать весь каталог перед каждой задачей.

Необходимо читать документы, относящиеся к изменяемой boundary.

### Обычное изменение UI

```text id="r8z6co"
AGENTS.md
technology-stack.md
state-management.md
```

При необходимости:

```text id="3h5jzq"
layers-and-dependencies.md
```

---

### Новая feature

```text id="0wr9gd"
AGENTS.md
technology-stack.md
layers-and-dependencies.md
state-management.md
testing.md
```

и документы для внешних boundaries, которые использует feature.

---

### Изменение ACP

```text id="0yqb86"
AGENTS.md
acp-boundary.md
streaming.md
testing.md
```

При изменении lifecycle:

```text id="3kds30"
session-lifecycle.md
concurrency.md
```

---

### Reconnect / disconnect

```text id="zwqk7x"
AGENTS.md
session-lifecycle.md
streaming.md
concurrency.md
```

---

### Tool calls / permissions

```text id="vxdy13"
AGENTS.md
permissions.md
acp-boundary.md
```

При asynchronous execution:

```text id="8ejm6o"
concurrency.md
```

---

### Filesystem / native integration

```text id="m4y7dd"
AGENTS.md
platform-integration.md
permissions.md
```

если операция может быть инициирована AI agent.

---

### Новая dependency

```text id="28k52m"
AGENTS.md
technology-stack.md
layers-and-dependencies.md
```

Агент сначала должен проверить, не решает ли существующий стек ту же задачу.

---

## 5. Architectural invariants

Следующие invariants должны сохраняться независимо от конкретной реализации.

### INV-001 — Domain независим от Flutter

Domain code не зависит от:

* Flutter;
* widgets;
* `BuildContext`;
* navigation;
* dialogs.

---

### INV-002 — UI не управляет infrastructure напрямую

Widgets не обращаются напрямую к:

* ACP transport;
* filesystem;
* persistence;
* secure storage;
* platform APIs;
* external processes.

---

### INV-003 — ACP DTO не является application state

Wire representation ACP не должен становиться внутренней моделью всего приложения.

Protocol-specific изменения локализуются на protocol/application boundary.

---

### INV-004 — Session lifecycle явный

Connection/session lifecycle моделируется явным state.

Невозможные комбинации состояний не должны быть representable там, где это практически возможно.

---

### INV-005 — Stale events не изменяют актуальное состояние

Event старого:

* connection;
* session;
* request;
* tool call;

не должен случайно изменить новое состояние.

---

### INV-006 — Side effects имеют owner

Long-lived operation, subscription или external resource должны иметь:

* owner;
* lifecycle;
* cleanup/disposal strategy.

---

### INV-007 — Permission policy находится вне UI

Presentation получает решение пользователя, но не определяет security policy.

---

### INV-008 — Неизвестное опасное действие запрещается

Для security-sensitive capability применяется deny-by-default, если спецификация явно не определяет другое поведение.

---

### INV-009 — Архитектура пропорциональна задаче

Нельзя добавлять abstraction только ради соблюдения design pattern.

Каждая abstraction должна иметь понятную ответственность.

---

### INV-010 — Существующий pattern предпочтительнее нового

Новый framework или architectural pattern не вводится, если утверждённое решение уже закрывает задачу.

---

## 6. Изменение архитектуры

Архитектурным считается изменение, которое затрагивает:

* dependency direction;
* package boundaries;
* feature boundaries;
* state-management strategy;
* DI strategy;
* ACP boundary;
* persistence strategy;
* permission/security model;
* connection/session lifecycle;
* platform integration model;
* значимую cross-cutting abstraction.

Такие изменения не следует выполнять как incidental refactoring.

Перед реализацией необходимо определить:

1. Какую проблему решает изменение.
2. Почему существующая архитектура недостаточна.
3. Какие boundaries затрагиваются.
4. Какие alternatives рассматривались.
5. Как изменится testing.
6. Есть ли migration/compatibility impact.

Если решение долгоживущее и существенно влияет на устройство системы, его следует зафиксировать через ADR.

---

## 7. ADR

Architecture Decision Records следует хранить в:

`docs/architecture/adr/`

Рекомендуемый формат:

```text id="jvwy10"
docs/architecture/adr/
├── 0001-<decision>.md
├── 0002-<decision>.md
└── ...
```

ADR нужен для решений уровня:

* выбор state-management framework;
* выбор persistence technology;
* изменение package boundaries;
* изменение session architecture;
* введение нового transport;
* изменение security model;
* значимая desktop integration strategy.

ADR не требуется для обычных implementation details.

---

## 8. Связь ADR и OpenSpec

ADR и OpenSpec решают разные задачи.

```text id="3pnubv"
OpenSpec
    │
    └── что система должна делать

ADR
    │
    └── почему выбрано архитектурное решение

Architecture docs
    │
    └── как система устроена сейчас
```

Одно изменение может требовать одновременно:

* OpenSpec change;
* ADR;
* обновления architecture documentation;
* изменения кода.

После принятия архитектурного решения основная документация должна описывать **актуальное состояние**, чтобы для понимания текущей архитектуры не требовалось читать всю историю ADR.

---

## 9. Поддержание документации

Architecture documentation является частью проекта и должна обновляться вместе с архитектурой.

При изменении architectural behavior агент должен проверить необходимость обновления:

* `AGENTS.md`;
* соответствующего документа в `docs/architecture/`;
* ADR;
* OpenSpec;
* diagrams;
* tests.

Документация не должна описывать архитектуру, которой больше нет.

При конфликте документации с кодом нельзя молча исправлять документацию под код.

Сначала необходимо определить, что является ожидаемым поведением и утверждённой архитектурой.

---

## 10. Основной принцип

Архитектура ACP Client должна обеспечивать следующий поток:

```text id="lbrz8f"
┌──────────────────────────┐
│       Presentation       │
│        Flutter UI        │
└────────────┬─────────────┘
             │ intent / state
             ▼
┌──────────────────────────┐
│       Application        │
│ orchestration / policies │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│          Domain          │
│ concepts / invariants    │
└──────────────────────────┘

             ▲
             │ ports
             │
┌────────────┴─────────────┐
│      Infrastructure      │
├──────────────────────────┤
│ ACP │ FS │ Storage │ OS  │
└──────────────────────────┘
```

Главная цель этой структуры — не формальное соблюдение Clean Architecture.

Цель — обеспечить:

* предсказуемое состояние;
* изоляцию ACP;
* контролируемые side effects;
* безопасность действий agent;
* тестируемость application logic;
* устойчивость streaming/reconnect;
* возможность развития desktop-клиента без неконтролируемого coupling.
