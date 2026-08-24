# Слои и зависимости ACP Client

Этот документ определяет архитектурные слои ACP Client, ответственность packages и допустимые направления зависимостей.

Документ является обязательным при:

* создании нового package;
* создании новой feature;
* переносе кода между packages;
* добавлении cross-package dependency;
* изменении ACP client architecture;
* существенном refactoring.

Общие правила находятся в:

`AGENTS.md`

Технологический стек:

`docs/architecture/technology-stack.md`

---

## 1. Цель

Основная задача dependency rules — не формальное соблюдение Clean Architecture, а контроль coupling.

Архитектура должна обеспечивать:

* независимость ACP protocol от Flutter;
* независимость reusable client logic от Flutter;
* изоляцию transports;
* изоляцию platform-specific implementation;
* переиспользуемый ACP UI;
* тестируемость application logic;
* явное владение state и side effects.

Наличие dependency в `pubspec.yaml` означает только техническую доступность package.

Оно НЕ означает, что любой слой может использовать этот package напрямую.

---

## 2. Уровни архитектуры

Система состоит из следующих архитектурных уровней:

```text id="ll6a2s"
┌─────────────────────────────────────────────┐
│                codelab_app                  │
│                                             │
│ presentation / app-specific orchestration   │
│ composition root / desktop integration      │
└──────────────────────┬──────────────────────┘
                       │
             ┌─────────┴─────────┐
             ▼                   ▼
┌───────────────────────┐  ┌───────────────────────┐
│        acp_ui         │  │    acp_client_core    │
│                       │  │                       │
│ reusable Flutter UI   │  │ reusable ACP client  │
│ presentation          │  │ application logic     │
└───────────────────────┘  └───────────┬───────────┘
                                       │
                           ┌───────────┴───────────┐
                           ▼                       ▼
                ┌──────────────────┐    ┌──────────────────┐
                │  acp_transports  │    │   acp_protocol   │
                │                  │    │                  │
                │ transport layer  │    │ wire protocol    │
                └────────┬─────────┘    └──────────────────┘
                         │
                         ▼
                  External Agent
```

Testing infrastructure находится отдельно:

```text id="55dykc"
acp_testing
    │
    └── используется только test/dev кодом
```

---

## 3. Главное правило dependencies

Dependencies должны направляться от более высокоуровневых компонентов к более низкоуровневым либо к abstractions, определяющим boundary.

Lower-level package НЕ ДОЛЖЕН зависеть от higher-level application package.

Запрещено:

```text id="ljd98u"
acp_protocol
    → acp_client_core

acp_protocol
    → acp_ui

acp_protocol
    → codelab_app

acp_transports
    → acp_ui

acp_transports
    → codelab_app

acp_client_core
    → acp_ui

acp_client_core
    → codelab_app

acp_ui
    → codelab_app
```

---

## 4. Dependency matrix

Базовая dependency policy:

| From ↓ / To →     | `acp_protocol` | `acp_transports` | `acp_client_core` | `acp_ui` | `codelab_app` | `acp_testing` |
| ----------------- | -------------: | ---------------: | ----------------: | -------: | ------------: | ------------: |
| `acp_protocol`    |              — |                ❌ |                 ❌ |        ❌ |             ❌ |             ❌ |
| `acp_transports`  |              ✅ |                — |                 ❌ |        ❌ |             ❌ |             ❌ |
| `acp_client_core` |              ✅ |               ✅* |                 — |        ❌ |             ❌ |             ❌ |
| `acp_ui`          |             ⚠️ |                ❌ |                ⚠️ |        — |             ❌ |             ❌ |
| `codelab_app`     |              ✅ |                ✅ |                 ✅ |        ✅ |             — |             ❌ |
| `acp_testing`     |              ✅ |                ✅ |                 ✅ |       ❌* |             ❌ |             — |

Обозначения:

* ✅ — dependency разрешена;
* ❌ — dependency запрещена;
* ⚠️ — dependency допустима только при архитектурной необходимости;
* `*` — см. отдельные правила ниже.

Матрица описывает архитектурную policy.

Фактический `pubspec.yaml` должен быть не шире необходимого dependency graph.

---

## 5. `acp_protocol`

Package:

`packages/dart/acp_protocol`

### Ответственность

`acp_protocol` представляет wire-level ACP contract.

Может содержать:

* request/response models;
* notifications;
* protocol DTO;
* identifiers;
* serialization;
* deserialization;
* protocol validation;
* protocol-level errors;
* version compatibility.

### Разрешённые dependencies

Только pure Dart libraries, необходимые для реализации protocol.

### Запрещённые dependencies

`acp_protocol` НЕ ДОЛЖЕН зависеть от:

* `acp_transports`;
* `acp_client_core`;
* `acp_ui`;
* `codelab_app`;
* Flutter;
* `flutter_bloc`;
* `fluent_ui`;
* platform UI.

### Invariant

```text id="k1fmlo"
ACP wire contract
      │
      ▼
acp_protocol
```

Ничто из application/presentation layer не должно быть необходимо для определения ACP message.

---

## 6. `acp_transports`

Package:

`packages/dart/acp_transports`

### Ответственность

Transport package отвечает за доставку ACP messages между client и agent.

Может содержать:

* stdio transport;
* process transport;
* stream transport;
* socket transport;
* framing;
* transport lifecycle;
* transport errors.

### Разрешённые dependencies

`acp_transports` МОЖЕТ зависеть от:

* `acp_protocol`;
* Dart SDK;
* transport-specific pure Dart libraries.

### Запрещённые dependencies

НЕ ДОЛЖЕН зависеть от:

* `acp_client_core`;
* `acp_ui`;
* `codelab_app`;
* Flutter presentation;
* `flutter_bloc`;
* `fluent_ui`.

### Transport boundary

Transport отвечает за:

```text id="fngjcp"
bytes / streams
      ↕
ACP messages
```

Transport НЕ отвечает за:

```text id="sz1o87"
session UI
permission dialogs
navigation
business state
presentation state
```

---

## 7. `acp_client_core`

Package:

`packages/dart/acp_client_core`

### Ответственность

`acp_client_core` содержит reusable client-side application behavior ACP.

Может содержать:

* ACP client orchestration;
* connection coordination;
* session lifecycle;
* request lifecycle;
* cancellation;
* application-level ACP events;
* permission abstractions;
* client state machines;
* mapping protocol → application concepts.

### Разрешённые dependencies

`acp_client_core` МОЖЕТ зависеть от:

* `acp_protocol`;
* transport abstractions;
* `acp_transports`, если concrete transport является осознанной частью client-core architecture;
* pure Dart libraries.

### Предпочтительная boundary

Если practical, `acp_client_core` СЛЕДУЕТ зависеть от transport abstraction, а concrete transport создавать выше — в composition root.

Предпочтительно:

```text id="gocztb"
acp_client_core
       │
       ▼
Transport interface
       ▲
       │
acp_transports
```

вместо сильного coupling:

```text id="3c0fr4"
acp_client_core
       │
       ▼
ConcreteStdioTransport
```

Это особенно важно, если существуют или планируются несколько transports.

### Запрещённые dependencies

`acp_client_core` НЕ ДОЛЖЕН зависеть от:

* Flutter;
* `flutter_bloc`;
* `fluent_ui`;
* `acp_ui`;
* `codelab_app`;
* widgets;
* `BuildContext`;
* navigation;
* dialogs.

### Invariant

Если ACP client behavior можно полностью протестировать обычным Dart test без Flutter binding, это сильный кандидат для `acp_client_core`.

---

## 8. `acp_ui`

Package:

`packages/flutter/acp_ui`

### Ответственность

`acp_ui` содержит reusable ACP-specific Flutter presentation.

Может содержать:

* ACP widgets;
* reusable conversation UI;
* tool-call UI;
* status UI;
* permission presentation;
* reusable presentation models;
* BLoC-aware components.

### Разрешённые dependencies

`acp_ui` МОЖЕТ зависеть от:

* Flutter;
* `fluent_ui`;
* `flutter_bloc`.

Dependency на `acp_client_core` или `acp_protocol` допустима только если reusable UI действительно должен понимать соответствующий public model.

### Предпочтение

Следует предпочитать:

```text id="37e1mo"
ACP/application model
        │
        ▼
presentation mapping
        │
        ▼
acp_ui model/widget
```

вместо распространения raw protocol DTO по widget tree.

### Запрещённые dependencies

`acp_ui` НЕ ДОЛЖЕН зависеть от:

* `codelab_app`;
* concrete ACP transport;
* application composition root;
* desktop application-specific services.

### Invariant

`acp_ui` должен оставаться reusable.

Если component имеет смысл только внутри одной feature `codelab_app`, его не следует автоматически переносить в `acp_ui`.

---

## 9. `acp_testing`

Package:

`packages/dart/acp_testing`

### Ответственность

Reusable testing infrastructure.

Может содержать:

* fake ACP agent;
* fake transport;
* fixtures;
* protocol message builders;
* test factories;
* lifecycle test utilities;
* assertion helpers.

### Dependencies

`acp_testing` МОЖЕТ зависеть от pure Dart ACP packages:

* `acp_protocol`;
* `acp_transports`;
* `acp_client_core`.

Production code НЕ ДОЛЖЕН зависеть от `acp_testing`.

Если появляются reusable Flutter-specific test helpers, следует рассмотреть отдельный Flutter testing package вместо добавления Flutter dependency в pure Dart `acp_testing`.

---

## 10. `codelab_app`

Application:

`apps/codelab_app`

### Ответственность

`codelab_app` является конечным desktop application и composition root.

Отвечает за:

* application bootstrap;
* dependency composition;
* desktop-specific features;
* routing;
* top-level state;
* application presentation;
* связывание ACP core с Flutter UI;
* platform adapters.

### Разрешённые dependencies

Application МОЖЕТ зависеть от:

* `acp_protocol`;
* `acp_transports`;
* `acp_client_core`;
* `acp_ui`;
* Flutter;
* `flutter_bloc`;
* Cherrypick;
* `fpdart`;
* approved platform packages.

Однако dependency должна использоваться только соответствующим слоем.

---

## 11. Внутренняя структура `codelab_app`

Предпочтительная структура:

```text id="zxg2s2"
lib/
├── app/
│   ├── bootstrap/
│   ├── di/
│   ├── routing/
│   └── ...
│
├── core/
│   └── app-specific shared code
│
└── features/
    ├── chat/
    ├── sessions/
    ├── settings/
    └── ...
```

Feature МОЖЕТ быть простой:

```text id="87uazp"
features/settings/
├── settings_page.dart
├── settings_cubit.dart
└── settings_state.dart
```

или более сложной:

```text id="gxy9ns"
features/chat/
├── application/
├── infrastructure/
└── presentation/
```

Не создавать `domain/application/infrastructure/presentation` автоматически.

---

## 12. Feature boundaries

Feature должна владеть поведением, специфичным для своей capability.

Например:

```text id="1wjjhp"
features/
├── chat/
├── sessions/
├── settings/
└── workbench/
```

Одна feature НЕ ДОЛЖНА импортировать private implementation другой feature.

Запрещённый pattern:

```text id="pd29v2"
features/chat/internal/foo.dart
              ▲
              │
features/settings/bar.dart
```

Если functionality действительно shared:

1. определить её semantic owner;
2. выделить public feature API;
3. либо перенести в app-level `core`;
4. либо вынести в reusable package, если она нужна нескольким applications/packages.

---

## 13. `app/`

`app/` содержит application-level composition.

Типичные responsibilities:

* bootstrap;
* DI composition;
* routing;
* top-level window/application lifecycle;
* global BLoC wiring;
* app configuration.

`app/` НЕ ДОЛЖЕН превращаться в место хранения feature business logic.

---

## 14. App-level `core/`

`apps/codelab_app/lib/core/` предназначен только для действительно shared application-specific code.

Примеры:

* app-level abstractions;
* shared presentation primitives;
* cross-feature adapters;
* common application errors, если они действительно cross-feature.

`core/` НЕ ДОЛЖЕН быть dumping ground.

Перед переносом кода в `core` необходимо определить минимум два независимых consumers либо другую ясную cross-cutting responsibility.

---

## 15. Presentation layer

Presentation включает:

* Flutter widgets;
* pages;
* dialogs;
* BLoC/Cubit;
* presentation state;
* presentation mapping;
* navigation integration.

Presentation МОЖЕТ зависеть от application API.

Presentation НЕ ДОЛЖЕН напрямую:

* управлять low-level transport;
* выполнять ACP serialization;
* создавать processes;
* обращаться к filesystem implementation;
* принимать security policy decisions.

Правильный поток:

```text id="uvokq4"
User
 │
 ▼
Widget
 │
 ▼
BLoC / Cubit
 │
 ▼
Application API
```

---

## 16. Application layer

Application layer определяет действия системы.

Например:

* connect;
* create session;
* send prompt;
* cancel request;
* reconnect;
* resolve permission;
* process ACP event.

Application layer:

* координирует dependencies;
* определяет application state transitions;
* применяет application policies.

Он НЕ ДОЛЖЕН зависеть от:

* Flutter widgets;
* `BuildContext`;
* dialogs;
* concrete visual components.

Для reusable ACP behavior предпочтительным владельцем является `acp_client_core`.

---

## 17. Domain layer

Отдельный domain layer создаётся только там, где существует реальная domain model или invariants.

Domain может содержать:

* entities;
* value objects;
* state machines;
* policies;
* domain errors.

Не следует создавать domain layer только потому, что архитектурный шаблон содержит слово `domain`.

Domain НЕ ДОЛЖЕН зависеть от Flutter или infrastructure.

---

## 18. Infrastructure layer

Infrastructure реализует взаимодействие с внешним миром.

Примеры:

* ACP transport;
* filesystem;
* secure storage;
* persistence;
* native APIs;
* external process;
* network.

Предпочтительный pattern:

```text id="7gk75k"
Application
    │
    ▼
Port / abstraction
    ▲
    │
Infrastructure adapter
    │
    ▼
External system
```

Concrete infrastructure dependencies должны создаваться в composition root.

---

## 19. ACP model boundaries

Следует различать минимум три типа моделей:

```text id="vvtl2s"
Protocol model
     ↓ mapping
Application model
     ↓ mapping
Presentation model
```

Не каждый переход требует отдельного класса.

Mapping нужен тогда, когда модели имеют разные semantics или lifecycle.

### Protocol model

Описывает wire representation.

Владелец:

`acp_protocol`

### Application model

Описывает понятия ACP client.

Владелец:

`acp_client_core` или соответствующая application feature.

### Presentation model

Описывает данные в форме, удобной UI.

Владелец:

`acp_ui` или presentation конкретной feature.

---

## 20. Когда НЕ нужен mapping

Не следует создавать отдельные модели только ради layers.

Если immutable value object:

* имеет одинаковую semantics;
* не содержит protocol-specific details;
* не создаёт unwanted dependency;
* не требует отдельного lifecycle;

его можно переиспользовать.

Цель — контролировать coupling, а не увеличивать число DTO.

---

## 21. State ownership

Каждый state должен иметь одного понятного owner.

Например:

```text id="zunq6e"
Transport state
    → transport

ACP client/session state
    → acp_client_core

Presentation state
    → BLoC/Cubit

Ephemeral widget state
    → Widget
```

Не следует хранить один authoritative state одновременно в нескольких layers.

Derived presentation state допустим, но source of truth должен быть понятен.

---

## 22. Side-effect ownership

Каждый side effect должен иметь определённый architectural owner.

| Side effect           | Owner                  |
| --------------------- | ---------------------- |
| ACP serialization     | `acp_protocol`         |
| ACP transport I/O     | `acp_transports`       |
| Session orchestration | `acp_client_core`      |
| Permission policy     | application/core       |
| Dialog                | presentation           |
| Navigation            | presentation/app       |
| Filesystem            | infrastructure adapter |
| Secure storage        | infrastructure adapter |
| Process execution     | infrastructure adapter |
| Rendering             | Flutter presentation   |

Feature не должна выполнять side effect только потому, что соответствующий package технически доступен.

---

## 23. Dependency Injection boundary

Cherrypick используется для composition, но НЕ отменяет dependency rules.

Неправильно:

```text id="nh7b4u"
Widget
  │
  └── resolve ConcreteTransport
```

Правильно:

```text id="18isnr"
Composition root
      │
      ├── ConcreteTransport
      │
      ├── ACP Client
      │
      └── Application API
                 │
                 ▼
              BLoC
                
```

## 23. Dependency Injection boundary

Cherrypick используется для composition, но НЕ отменяет dependency rules.

Неправильно:

```text
Widget
  │
  └── resolve ConcreteTransport
```

Правильно:

```text
Composition root
      │
      ├── ConcreteTransport
      │
      ├── ACP Client
      │
      └── Application API
                 │
                 ▼
              BLoC/Cubit
                 │
                 ▼
               Widget
```

DI container должен использоваться для сборки object graph, а не как механизм получения произвольных dependencies из любой точки приложения.

Следует предпочитать constructor injection или установленный Cherrypick pattern.

Не следует:

* передавать DI container глубоко в application code;
* использовать container как global service locator;
* разрешать dependency непосредственно внутри domain;
* разрешать infrastructure dependency непосредственно внутри widget.

---

## 24. Composition root

`codelab_app` является главным composition root desktop-приложения.

Composition root отвечает за связывание:

* concrete ACP transports;
* ACP client;
* platform adapters;
* storage implementations;
* application services;
* BLoC/Cubit;
* routing;
* configuration.

Composition root МОЖЕТ знать о concrete implementations.

Нижележащие layers не должны получать эту ответственность.

Пример:

```text
main/bootstrap
      │
      ▼
Cherrypick composition
      │
      ├── StdioTransport
      ├── AcpClient
      ├── PermissionPolicy
      ├── SecureStorageAdapter
      ├── PlatformAdapter
      └── SessionBloc
```

Создание нового concrete dependency следует выполнять в composition root либо в scoped composition module, если проект использует такую структуру.

---

## 25. Public API packages

Cross-package dependency должна проходить через public API package.

Предпочтительно:

```dart
import 'package:acp_protocol/acp_protocol.dart';
```

вместо импорта внутренних implementation files другого package.

Public API должен экспортировать только те сущности, которые действительно являются контрактом package.

Не следует экспортировать всё содержимое `lib/src/` ради удобства.

Package public API должен оставаться минимальным и осмысленным.

---

## 26. Internal API

Implementation details package должны находиться вне его public contract.

Предпочтительная структура:

```text
lib/
├── acp_protocol.dart
└── src/
    ├── models/
    ├── serialization/
    └── ...
```

Код другого package НЕ ДОЛЖЕН импортировать:

```dart
package:some_package/src/...
```

если это не является осознанным и явно документированным исключением.

Если внешний consumer вынужден использовать `src`, следует проверить, не отсутствует ли необходимая сущность в public API.

---

## 27. Cross-feature communication

Features не должны связываться через private implementation друг друга.

Предпочтительные варианты взаимодействия:

### Через application-level API

```text
Feature A
   │
   ▼
Application API
   ▲
   │
Feature B
```

### Через shared state/event abstraction

Если несколько features реагируют на одно application-level событие:

```text
          Application event
             /       \
            ▼         ▼
      Feature A     Feature B
```

### Через public feature facade

Если одна feature явно предоставляет capability другой:

```text
Feature B
   │
   ▼
Feature A public API
```

Не следует создавать глобальный event bus только ради устранения прямых imports.

---

## 28. Events

Events должны принадлежать тому уровню, semantics которого они описывают.

Примеры:

```text
AcpResponseReceived
    → protocol/client level

SessionConnected
    → application/client level

ChatScrolledToBottom
    → presentation level
```

Не следует использовать один event type одновременно как:

* protocol message;
* domain/application event;
* BLoC event;
* UI event;

если эти уровни имеют различную semantics.

---

## 29. Error boundaries

Ошибки также должны следовать архитектурным boundaries.

Предпочтительный поток:

```text
External exception
      │
      ▼
Infrastructure / transport error
      │
      ▼
Application failure
      │
      ▼
Presentation error state
      │
      ▼
User-visible message
```

Не каждая ошибка требует отдельного класса на каждом уровне.

Mapping нужен, если:

* меняется semantics;
* нужно скрыть implementation details;
* требуется нормализация нескольких внешних ошибок;
* UI не должен знать техническую ошибку;
* необходимо добавить application context.

---

## 30. Protocol errors

Protocol-level ошибки принадлежат `acp_protocol`.

Например:

* invalid message;
* unsupported protocol data;
* serialization failure;
* invalid protocol shape.

Они не должны содержать Flutter-specific behavior.

---

## 31. Transport errors

Transport errors принадлежат `acp_transports`.

Например:

* stream closed;
* process terminated;
* socket disconnected;
* framing error;
* transport unavailable.

Transport error не должен автоматически определять UX.

Например:

```text
SocketClosed
```

не означает автоматически:

```text
ShowReconnectDialog
```

Решение о reconnect и presentation принадлежит более высокому layer.

---

## 32. Application failures

Application layer может преобразовывать lower-level errors в более осмысленные failures.

Например:

```text
TransportClosedUnexpectedly
        │
        ▼
SessionConnectionLost
        │
        ▼
SessionState.reconnecting
```

Это позволяет presentation реагировать на application semantics, а не на детали transport implementation.

---

## 33. Permission boundary

Permission policy должна находиться выше transport/protocol, но ниже presentation decision collection.

Правильная dependency:

```text
ACP request
    │
    ▼
Application permission policy
    │
    ├── allowed
    │
    ├── denied
    │
    └── requires user decision
                │
                ▼
            Presentation
```

Неправильно:

```text
Transport
   │
   └── showDialog()
```

или:

```text
Widget
   │
   └── if (tool.name == 'shell') ...
```

Presentation не должна содержать authoritative security policy.

---

## 34. Platform boundary

Platform-specific functionality должна находиться за abstraction boundary, если она влияет на application behavior.

Например:

```dart
abstract interface class AppWindow {
  Future<void> minimize();

  Future<void> maximize();
}
```

Concrete implementation может использовать platform plugin:

```text
Application
    │
    ▼
AppWindow
    ▲
    │
FlutterDesktopWindowAdapter
    │
    ▼
Platform plugin
```

Это особенно важно для:

* window management;
* filesystem;
* secure storage;
* clipboard;
* notifications;
* external process execution;
* platform paths.

---

## 35. `dart:io`

Использование `dart:io` само по себе не запрещено.

Однако его использование должно соответствовать boundary.

Допустимо:

```text
acp_transports
desktop infrastructure adapters
filesystem adapters
process adapters
```

Не следует использовать `dart:io` непосредственно из:

* widgets;
* presentation BLoC, если это infrastructure operation;
* domain;
* reusable UI components.

---

## 36. BLoC boundary

`flutter_bloc` принадлежит Flutter/presentation side архитектуры.

BLoC/Cubit может зависеть от application-facing API.

Предпочтительно:

```text
Widget
   │
   ▼
BLoC
   │
   ▼
ACP Client/Application API
```

Не рекомендуется:

```text
Widget
   │
   ▼
BLoC
   │
   ▼
Concrete transport
```

BLoC НЕ ДОЛЖЕН становиться заменой application layer.

Если BLoC начинает содержать:

* transport lifecycle;
* ACP protocol parsing;
* complex permission policy;
* reusable session state machine;
* significant retry/reconnect algorithms;

следует проверить, не принадлежит ли эта логика `acp_client_core`.

---

## 37. `acp_ui` и BLoC

`acp_ui` может содержать BLoC-aware widgets, поскольку package явно является Flutter presentation package.

Однако reusable visual component следует по возможности отделять от конкретного state-management context.

Предпочтительно:

```dart
ToolCallView(
  status: state.status,
  name: state.name,
  onApprove: onApprove,
)
```

когда component является чисто визуальным.

BLoC-aware wrapper допустим, если он действительно улучшает reuse:

```text
ToolCallBlocView
      │
      ▼
ToolCallView
```

Это уменьшает coupling между reusable visual components и конкретным BLoC.

---

## 38. Cherrypick dependencies

Cherrypick относится прежде всего к composition/application bootstrap.

Наличие annotations не должно заставлять lower-level packages зависеть от DI framework без необходимости.

Pure reusable package следует сохранять независимым от Cherrypick, если dependency injection может выполняться его consumer.

Предпочтительно:

```dart
class AcpClient {
  AcpClient({
    required AcpTransport transport,
  });
}
```

а binding:

```text
AcpTransport → StdioAcpTransport
```

определять в composition layer.

Это позволяет:

* тестировать component без container;
* переиспользовать package вне Flutter app;
* заменять concrete implementation;
* уменьшать framework coupling.

---

## 39. `fpdart` boundary

`fpdart` может использоваться в pure Dart application packages.

Однако public API package не следует делать зависимым от `fpdart` только ради внутренней implementation convenience, если это без необходимости заставляет всех consumers работать с `Either`, `Option` и другими типами библиотеки.

Решение использовать `fpdart` types в public contract должно быть осознанным.

Если `Either<Failure, T>` является утверждённой частью application API, его использование допустимо.

Главное правило — consistency.

---

## 40. Freezed boundary

Freezed является implementation/code-generation инструментом и может использоваться в разных layers.

Однако generated API не должен случайно связывать layers.

Например, Freezed state BLoC не должен импортироваться в `acp_client_core` только потому, что он удобен для UI.

Тип должен жить на том уровне, semantics которого он представляет.

---

## 41. Testing dependencies

Test code может иметь более широкий dependency graph, чем production code.

Например:

```text
acp_client_core tests
       │
       └── acp_testing
```

Допустимо.

Однако test dependency НЕ ДОЛЖНА создавать production dependency.

Production source из `lib/` не должен импортировать test helpers.

Test-only packages должны находиться в `dev_dependencies`, если нет отдельной причины.

---

## 42. Architecture tests

Критические dependency invariants следует по возможности проверять автоматически.

Полезно проверять:

* `acp_protocol` не зависит от Flutter;
* `acp_client_core` не зависит от Flutter;
* `acp_transports` не зависит от Flutter presentation;
* `acp_ui` не зависит от `codelab_app`;
* production packages не зависят от `acp_testing`;
* запрещённые `package:*/src/*` imports отсутствуют между packages.

Архитектурное правило, которое можно надёжно проверить автоматически, следует постепенно переносить из документации в static/CI verification.

Документация при этом остаётся источником semantics правила.

---

## 43. Добавление нового package

Перед созданием нового package необходимо определить:

1. Какую конкретную responsibility он владеет.
2. Почему существующий package не является правильным owner.
3. Является ли код reusable.
4. Должен ли package быть pure Dart или Flutter.
5. Кто будет его consumer.
6. От каких packages ему разрешено зависеть.
7. Как выглядит его public API.
8. Как package будет тестироваться.
9. Не создаёт ли он новый dependency cycle.
10. Не является ли package слишком маленькой abstraction без самостоятельного смысла.

Новый package не создаётся только ради уменьшения количества файлов в существующем package.

---

## 44. Когда выносить код из `codelab_app`

Код является кандидатом на reusable package, если выполняется одно или несколько условий:

* он нужен нескольким applications;
* он представляет самостоятельную ACP capability;
* он должен работать без Flutter application;
* у него есть устойчивый public contract;
* isolation заметно улучшает testing;
* это явно отдельная technical boundary.

Не следует выносить code в package только потому, что feature стала большой.

Большая feature может оставаться feature приложения, если её semantics application-specific.

---

## 45. Когда код принадлежит `acp_client_core`

Код следует рассматривать для `acp_client_core`, если он:

* относится к ACP client behavior;
* не требует Flutter;
* должен быть reusable;
* управляет session/request lifecycle;
* реализует application-level ACP semantics;
* нужен разным ACP clients или UI layers.

Например:

```text
session state machine
request cancellation semantics
ACP client event reduction
reconnect policy abstraction
permission request model
```

могут быть хорошими кандидатами.

Конкретное размещение должно учитывать существующую структуру package.

---

## 46. Когда код принадлежит `acp_ui`

Код следует рассматривать для `acp_ui`, если он:

* является reusable ACP-specific Flutter presentation;
* не зависит от `codelab_app`;
* потенциально полезен в другом ACP Flutter application;
* имеет стабильный presentation contract.

Например:

```text
tool call card
ACP status indicator
permission prompt content
conversation message renderer
```

могут быть кандидатами.

Application-specific page или workflow следует оставить в `codelab_app`.

---

## 47. Когда код принадлежит feature приложения

Код должен оставаться внутри `codelab_app/features/<feature>`, если он:

* специфичен только для CodeLab application;
* определяет конкретный workflow приложения;
* тесно связан с routing приложения;
* не имеет самостоятельного reusable contract;
* использует несколько reusable ACP packages для реализации app-specific capability.

Не следует преждевременно превращать каждую feature в package.

---

## 48. Запрещённые shortcut patterns

Следующие shortcuts считаются архитектурно опасными.

### Widget → transport

```text
Widget
  ↓
acp_transports
```

ЗАПРЕЩЕНО для application behavior.

---

### Widget → filesystem

```text
Widget
  ↓
File(...)
```

НЕ СЛЕДУЕТ для infrastructure operations.

---

### Protocol → UI

```text
acp_protocol
    ↓
Flutter widget
```

ЗАПРЕЩЕНО.

---

### Core → presentation

```text
acp_client_core
      ↓
flutter_bloc / fluent_ui
```

ЗАПРЕЩЕНО.

---

### Reusable package → application

```text
acp_ui
   ↓
codelab_app
```

ЗАПРЕЩЕНО.

---

### Production → testing

```text
acp_client_core/lib
       ↓
acp_testing
```

ЗАПРЕЩЕНО.

---

### Feature → private feature internals

```text
features/a
    ↓
features/b/src/private
```

ЗАПРЕЩЕНО.

---

## 49. Допустимые pragmatic shortcuts

Не каждый direct dependency является нарушением архитектуры.

Например, простой presentation-only feature может выглядеть так:

```text
Widget
   │
   ▼
Cubit
```

без отдельного use case.

Это допустимо, если Cubit не содержит infrastructure/application complexity.

Простой immutable value object может использоваться сразу в нескольких слоях, если его semantics не меняется.

Не следует создавать mapper только ради того, чтобы существовал mapper.

---

## 50. Правило изменения dependency graph

При добавлении новой cross-package dependency агент ОБЯЗАН:

1. Определить direction dependency.
2. Проверить dependency matrix.
3. Проверить отсутствие cycle.
4. Проверить, не переносит ли dependency Flutter в pure Dart package.
5. Проверить public API target package.
6. Обосновать, почему dependency нужна.
7. Обновить этот документ, если dependency graph действительно меняется архитектурно.

Если новая dependency противоречит matrix, изменение требует архитектурного решения, а не просто изменения `pubspec.yaml`.

---

## 51. Целевая dependency model

Итоговый принцип:

```text
                     APPLICATION
                         │
                         ▼
                    codelab_app
                    /          \
                   ▼            ▼
              acp_ui      ACP application API
                               │
                               ▼
                       acp_client_core
                          /          \
                         ▼            ▼
                acp_transports   acp_protocol
                       │
                       ▼
                 External Agent
```

При наличии inversion через transport abstraction concrete graph может выглядеть так:

```text
                   composition root
                    /           \
                   ▼             ▼
          acp_client_core   acp_transports
                   │             │
                   ▼             │
           Transport Port ◄──────┘
                   │
                   ▼
              acp_protocol
```

Конкретный dependency direction должен минимизировать coupling и сохранять pure Dart boundaries.

---

## 52. Главный критерий размещения кода

При выборе места для нового кода нужно отвечать не на вопрос:

> Где удобнее его положить?

а на вопросы:

> Кто владеет этой responsibility?

> На каком уровне существует её semantics?

> Какие dependencies ей действительно необходимы?

> Должна ли она быть reusable?

> Требует ли она Flutter?

Если ответы определены правильно, расположение кода обычно становится очевидным.

Архитектурные boundaries важнее структуры директорий.

Структура директорий должна отражать архитектуру, а не заменять её.
