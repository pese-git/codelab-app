# Testing strategy в ACP Client

Этот документ определяет стратегию тестирования ACP Client и правила выбора уровня тестов.

Цели:

* проверять correctness на минимально необходимом уровне;
* держать основную ACP/application logic тестируемой без Flutter;
* использовать `acp_testing` для reusable test infrastructure;
* избегать чрезмерно тяжёлых integration tests;
* покрывать lifecycle, streaming, reconnect и permission races;
* обеспечивать предсказуемую validation strategy для AI coding agents и CI.

Связанные документы:

* `AGENTS.md`
* `docs/architecture/layers-and-dependencies.md`
* `docs/architecture/acp-boundary.md`
* `docs/architecture/session-lifecycle.md`
* `docs/architecture/streaming.md`
* `docs/architecture/concurrency.md`
* `docs/architecture/permissions.md`
* `docs/architecture/state-management.md`
* `docs/architecture/platform-integration.md`
* `docs/architecture/observability.md`

---

## 1. Основной принцип

Тест должен находиться на минимально необходимом уровне.

Предпочтительная пирамида:

```text
                Integration / E2E
                     ▲
                     │
                 Widget tests
                     ▲
                     │
                  BLoC tests
                     ▲
                     │
        Application / client-core tests
                     ▲
                     │
          Protocol / pure Dart unit tests
```

Чем ниже уровень, тем быстрее и детерминированнее должен быть тест.

---

## 2. Тестировать behavior, а не implementation

Тест должен проверять observable semantics.

Предпочтительно:

```text
given:
  connection lost

when:
  reconnect succeeds

then:
  session returns to ready
```

вместо:

```text
method _retryInternal called exactly 2 times
```

если конкретный внутренний вызов не является частью contract.

---

## 3. Pure Dart first

Если behavior можно протестировать без Flutter, следует использовать pure Dart test.

Это особенно относится к:

* ACP protocol;
* serialization;
* transport abstractions;
* `acp_client_core`;
* state machines;
* permission policy;
* reconnect logic;
* streaming reducers;
* error mapping.

Не следует поднимать Flutter binding без необходимости.

---

## 4. Flutter tests

`flutter_test` используется для:

* widgets;
* BLoC/Cubit presentation behavior;
* rendering;
* navigation/presentation integration;
* Fluent UI components;
* `acp_ui`.

Flutter test не должен быть единственным способом проверки core behavior.

---

## 5. Integration tests

`integration_test` используется для сценариев, где важно проверить несколько реальных layers вместе.

Например:

```text
UI
  ↓
BLoC
  ↓
application
  ↓
fake ACP agent
```

или:

```text
codelab_app
  ↓
ACP client
  ↓
stdio transport
  ↓
test process
```

Integration test не должен заменять unit coverage.

---

## 6. `acp_testing`

Package:

`packages/dart/acp_testing`

предназначен для reusable ACP-specific testing infrastructure.

Он может содержать:

* fake transports;
* fake ACP agent;
* fixtures;
* builders;
* protocol message factories;
* request/session helpers;
* deterministic stream controllers;
* lifecycle assertions.

Production code НЕ ДОЛЖЕН зависеть от `acp_testing`.

---

## 7. Test dependency direction

Допустимо:

```text
acp_client_core tests
    ↓
acp_testing
```

Допустимо:

```text
codelab_app tests
    ↓
acp_testing
```

Недопустимо:

```text
acp_client_core/lib
    ↓
acp_testing
```

Test infrastructure не должна проникать в production API.

---

## 8. Protocol tests

`acp_protocol` должен иметь focused tests на:

* serialization;
* deserialization;
* required fields;
* optional fields;
* unknown fields;
* invalid shape;
* protocol version;
* round-trip;
* compatibility.

---

## 9. Serialization tests

Проверяют:

```text
model
  ↓
wire representation
```

Следует проверять meaningful contract fields, а не случайный порядок map keys.

---

## 10. Deserialization tests

Проверяют:

```text
wire representation
  ↓
typed model
```

Обязательные сценарии:

* valid payload;
* missing required field;
* wrong field type;
* unknown optional field;
* unsupported shape.

---

## 11. Round-trip tests

Для stable protocol models полезно:

```text
model
  ↓
serialize
  ↓
deserialize
  ↓
equivalent model
```

Round-trip не заменяет explicit schema tests.

---

## 12. Golden protocol fixtures

Для крупных protocol messages допустимо хранить JSON fixtures.

Fixtures должны:

* быть небольшими;
* отражать реальные protocol cases;
* не содержать secrets;
* иметь понятное имя.

Например:

```text
test/fixtures/
├── session_update.json
├── tool_call_request.json
└── invalid_missing_id.json
```

---

## 13. Compatibility tests

Если поддерживается compatibility, обязательны тесты на:

* older supported version;
* unknown optional fields;
* newer extension fields;
* unsupported version behavior.

---

## 14. Transport tests

`acp_transports` следует тестировать отдельно от application semantics.

Проверять:

* connect;
* send;
* receive;
* framing;
* disconnect;
* stream close;
* process exit;
* transport errors.

Transport tests не должны проверять Flutter UI.

---

## 15. Fake transport

Fake transport должен позволять детерминированно:

* inject inbound event;
* capture outbound event;
* close connection;
* throw error;
* delay completion;
* replay event;
* send malformed data.

---

## 16. Client-core tests

`acp_client_core` должен иметь основную behavioral coverage ACP client semantics.

Ключевые области:

* connection lifecycle;
* session lifecycle;
* request lifecycle;
* streaming;
* cancellation;
* reconnect;
* stale event filtering;
* permission flow;
* error normalization.

---

## 17. State machine tests

Для explicit state machine следует тестировать transitions.

Например:

```text
disconnected
  + connect
  → connecting
```

```text
running
  + cancel
  → cancelling
```

```text
reconnecting
  + success
  → ready/recovered
```

---

## 18. Invalid transition tests

Нужно проверять запрещённые transitions.

Например:

```text
disconnected
  + sendPrompt
  → rejected
```

или другой expected result по API.

---

## 19. Streaming tests

Минимум:

* one chunk;
* multiple chunks;
* completion;
* duplicate chunk;
* duplicate completion;
* late chunk;
* stale generation;
* out-of-order event;
* replay after reconnect;
* cancellation during stream.

---

## 20. Deterministic streaming tests

Не следует использовать реальные задержки:

```dart
await Future.delayed(const Duration(milliseconds: 500));
```

для синхронизации теста.

Использовать:

* `Completer`;
* controlled `StreamController`;
* fake clock;
* explicit event injection.

---

## 21. Concurrency tests

Обязательные race scenarios:

```text
completion vs cancel
disconnect vs completion
reconnect vs manual disconnect
old result vs new request
dispose vs callback
duplicate connect
duplicate cancel
```

---

## 22. Forced ordering

Полезный pattern:

```text
start A
start B
complete B
complete A
```

и проверить, что stale A не перезаписал B.

---

## 23. Permission tests

Permission policy должна тестироваться pure Dart.

Обязательные scenarios:

* safe → allow;
* dangerous → ask user;
* forbidden → deny;
* unknown dangerous → deny;
* stale decision ignored;
* wrong tool call id rejected;
* cancelled request cannot be approved.

---

## 24. Permission UI tests

Widget/BLoC tests должны проверять:

* request отображается;
* approve отправляет правильный decision;
* deny отправляет правильный decision;
* repeated click не создаёт duplicate decision;
* stale request исчезает;
* secrets не отображаются без необходимости.

---

## 25. BLoC tests

BLoC tests проверяют:

* user intent;
* interaction с application API;
* resulting presentation state;
* error mapping;
* subscription lifecycle.

Они НЕ ДОЛЖНЫ повторно тестировать protocol parsing.

---

## 26. Cubit tests

Cubit tests должны быть focused и быстрыми.

Если для simple Cubit требуется запуск transport/process, dependency boundary следует проверить.

---

## 27. BLoC dependencies

В BLoC tests использовать fake/mock application-facing dependencies.

Например:

```text
FakeAcpClient
FakeSessionController
FakePermissionService
```

Не использовать real external process без причины.

---

## 28. Widget tests

Widget tests предназначены для проверки presentation behavior.

Проверять:

* correct rendering;
* controls enabled/disabled;
* events/intents emitted;
* error state;
* loading state;
* permission state;
* reusable `acp_ui` components.

---

## 29. Не тестировать pixels без необходимости

Golden/image tests следует использовать только там, где visual regression действительно важно.

Обычный behavior лучше проверять semantic widget assertions.

---

## 30. Fluent UI tests

Для `fluent_ui` components следует проверять:

* наличие нужного control;
* state;
* callback;
* text/semantic content.

Не следует привязывать test к внутренней реализации Fluent UI без необходимости.

---

## 31. Navigation tests

Navigation tests должны проверять route semantics, а не private router implementation.

Например:

```text
when session selected
then workbench route displayed
```

---

## 32. Integration tests

Integration tests покрывают critical user journeys.

Минимальные кандидаты:

```text
launch
connect
create session
send prompt
receive stream
complete
```

---

## 33. Reconnect integration

Если reconnect является critical product behavior:

```text
connect
send prompt
transport lost
reconnect
recover
```

должен иметь integration coverage.

---

## 34. Permission integration

Critical flow:

```text
agent requests tool
permission shown
user approves
decision sent
tool continues
```

и deny variant.

---

## 35. Platform integration tests

Platform-specific adapters следует тестировать отдельно.

Например:

* filesystem;
* secure storage;
* process execution;
* window APIs.

Application tests должны использовать fake adapter.

---

## 36. Real process tests

Real process integration tests допустимы для `acp_transports`, если stdio/process transport критичен.

Использовать controlled test executable/process, а не внешний production agent.

---

## 37. Test agent

Полезно иметь fake/test ACP agent, который умеет:

* accept connection;
* return session response;
* stream chunks;
* request tool;
* disconnect;
* replay events;
* return malformed message.

Он должен быть детерминированным.

---

## 38. Error tests

Проверять не только happy path.

Минимальные failure classes:

* protocol error;
* transport error;
* permission denied;
* timeout;
* reconnect exhausted;
* invalid state transition.

---

## 39. Observability tests

Следует проверять security-critical logging behavior:

* token redacted;
* full payload not logged in release;
* correlation IDs present;
* stale event diagnostic contains reason.

---

## 40. Secrets tests

Если redaction code существует отдельно, оно должно иметь direct unit tests.

Например:

```text
input:
Authorization: Bearer abc123

output:
Authorization: ***redacted***
```

---

## 41. Persistence tests

Если persistence присутствует, проверять:

* read/write;
* migration;
* corruption;
* concurrent writes;
* stale revision protection;
* restore semantics.

---

## 42. Migration tests

Persistence migration должна иметь fixture старой версии данных.

Проверить:

```text
old data
  ↓ migrate
current model
```

---

## 43. Test naming

Имена тестов должны описывать behavior.

Предпочтительно:

```text
ignores late completion from previous connection generation
```

вместо:

```text
test reconnect 3
```

---

## 44. Arrange / Act / Assert

Для сложных tests полезна структура:

```text
Given
When
Then
```

или:

```text
Arrange
Act
Assert
```

Не обязательно формально использовать комментарии.

---

## 45. One behavior per test

Тест должен иметь одну понятную причину failure.

Не следует создавать огромный test, проверяющий весь application lifecycle от запуска до shutdown, если это не integration scenario.

---

## 46. Test fixtures

Fixture должна быть минимальной.

Не следует создавать full ACP session object, если test проверяет только один identifier.

---

## 47. Builders

Test builders полезны для сложных immutable models.

Например:

```text
aSession()
aToolCall()
anAcpMessage()
```

Builders должны иметь sensible defaults и позволять переопределить relevant fields.

---

## 48. Random data

Randomness по умолчанию нежелательна.

Если property/fuzz testing используется, random seed должен быть воспроизводимым.

---

## 49. Fuzzing

Особенно полезно для:

* protocol parser;
* framing;
* invalid payload;
* ordering;
* duplicate event processing.

Но fuzzing дополняет, а не заменяет deterministic tests.

---

## 50. Property-based invariants

Полезные invariants:

```text
duplicate event does not change final state
```

```text
old generation never changes current generation state
```

```text
terminal request never becomes running again
```

---

## 51. No real network by default

Unit tests НЕ ДОЛЖНЫ зависеть от real network.

Использовать fake transport/network adapter.

---

## 52. No real filesystem by default

Unit tests application logic не должны писать в реальный user filesystem.

Использовать temp directory или fake abstraction.

---

## 53. Temp directories

Если test действительно требует filesystem:

* использовать isolated temp directory;
* cleanup после test;
* не использовать реальные user paths.

---

## 54. Time

Time-dependent logic должна зависеть от injectable/testable clock, если time существенно влияет на behavior.

Это особенно относится к:

* retry;
* timeout;
* expiration;
* permission scope expiry.

---

## 55. Fake clock

Fake clock позволяет тестировать:

```text
retry after 1s
retry after 2s
retry after 4s
```

без ожидания реальных секунд.

---

## 56. Test isolation

Каждый test должен иметь независимое state.

Не использовать shared mutable singleton между tests без reset.

---

## 57. Parallel tests

Tests должны по возможности быть безопасны для parallel execution.

Не использовать:

* общий temp filename;
* фиксированный port;
* global mutable state.

---

## 58. Ports

Если integration test требует socket, использовать dynamic/free port strategy.

Не хардкодить порт, который может быть занят.

---

## 59. Process cleanup

Integration test обязан завершать child processes даже при failure.

Cleanup должен находиться в `tearDown`.

---

## 60. Subscription cleanup

Tests должны закрывать:

* `StreamController`;
* subscriptions;
* BLoC;
* client;
* transport.

Dangling async resources приводят к flaky tests.

---

## 61. Flaky tests

Flaky test считается defect.

Не исправлять flaky test увеличением arbitrary delay.

Нужно найти race/ownership problem.

---

## 62. Retry tests в CI

Не следует автоматически retry любой failed test, скрывая flaky behavior.

Retry допустим только как временная diagnostic measure.

---

## 63. Snapshot/golden updates

AI-agent НЕ ДОЛЖЕН массово обновлять golden/snapshot files только чтобы tests стали зелёными.

Сначала нужно проверить, является ли изменение ожидаемым.

---

## 64. Mocking

Если mocking library утверждена проектом, использовать её последовательно.

Не добавлять второй mocking framework без причины.

Предпочитать fake для stateful protocols и transports, где fake даёт более реалистичное behavior.

---

## 65. Fake vs mock

Fake лучше для:

* transport;
* ACP agent;
* storage;
* lifecycle-heavy component.

Mock лучше для:

* простого взаимодействия;
* проверки одного вызова;
* stateless dependency.

---

## 66. Не over-mock

Если test состоит из десятков `verify`, он часто тестирует implementation wiring, а не behavior.

Следует проверить architecture/API.

---

## 67. Contract tests

Для ports/adapters полезны shared contract tests.

Например:

```text
FileStore contract:
  write → read same content
  missing file → expected failure
```

Каждая implementation проходит один набор tests.

---

## 68. Transport contract tests

Если несколько ACP transports, полезен общий contract:

* connect;
* send;
* receive;
* disconnect;
* error semantics.

---

## 69. Public API tests

Public package API следует проверять через public imports.

Это помогает убедиться, что нужный API реально экспортирован.

---

## 70. Internal tests

Internal implementation можно тестировать напрямую внутри package, но cross-package consumer tests не должны импортировать `src/`.

---

## 71. Architecture tests

Желательно автоматизировать critical dependency rules.

Проверять:

* pure Dart package не импортирует Flutter;
* production code не импортирует `acp_testing`;
* package не импортирует `src` другого package;
* `acp_ui` не зависит от `codelab_app`;
* forbidden dependency cycles отсутствуют.

---

## 72. Static analysis как часть testing strategy

`dart analyze` не заменяет tests, но является обязательной validation step.

Lint/analyzer ловит:

* type errors;
* invalid imports;
* dead code;
* unsafe patterns.

---

## 73. Formatting

Formatting не является test, но является частью Definition of Done.

Changed Dart files должны соответствовать `dart format`.

---

## 74. CI levels

CI может быть разделён на уровни.

Например:

```text
PR fast checks:
  format
  analyze
  unit tests
  BLoC/widget tests

Full checks:
  integration tests
  platform tests
  architecture tests
```

Конкретная pipeline определяется repository configuration.

---

## 75. Targeted validation

Для локального изменения агент может запускать targeted tests.

Например:

```bash
fvm flutter test test/features/chat/
```

или package-level command через Melos.

Но shared/package-level изменения требуют более широкого validation scope.

---

## 76. Когда запускать весь monorepo

Полный `melos test` особенно нужен при изменении:

* public package API;
* `acp_protocol`;
* `acp_client_core`;
* shared test utilities;
* dependency graph;
* code generation;
* cross-package models.

---

## 77. Validation honesty

AI-agent НЕ ДОЛЖЕН писать:

```text
all tests pass
```

если tests не запускались.

Если command невозможно выполнить, нужно сообщить:

* что не запускалось;
* почему;
* что осталось непроверенным.

---

## 78. Test coverage

Numeric coverage target сам по себе не является целью, если он не определён проектом.

Приоритет — critical behavior coverage.

Особенно:

* lifecycle;
* security;
* protocol;
* reconnect;
* cancellation;
* stale events.

---

## 79. Critical code

Для security/protocol-critical code expected coverage должна быть выше обычного UI glue.

Например:

* permission policy;
* protocol parsing;
* session state machine;
* reconnect;
* stale filtering.

---

## 80. Generated code

Generated files обычно не нужно тестировать отдельно.

Тестируется behavior source abstraction, которая их использует.

---

## 81. Freezed state tests

Не нужно тестировать, что Freezed корректно реализовал `copyWith`.

Нужно тестировать application state transitions.

---

## 82. Cherrypick tests

DI wiring следует проверять smoke/integration tests, а не unit test каждого binding.

Критично проверить, что composition root может построить graph.

---

## 83. Composition smoke test

Полезен тест:

```text
build application dependency graph
  → no missing bindings
```

если Cherrypick позволяет это делать без запуска real destructive resources.

---

## 84. Не запускать external agent в unit tests

Unit tests не должны зависеть от installed production AI agent.

Использовать fake/test agent.

---

## 85. Version compatibility matrix

Если ACP поддерживает несколько protocol versions, полезно иметь parameterized tests:

```text
v1 fixture
v2 fixture
future-fields fixture
```

---

## 86. Regression tests

При исправлении bug следует по возможности сначала добавить test, который воспроизводит bug.

Особенно для:

* race;
* stale event;
* duplicate;
* protocol incompatibility.

---

## 87. Bug without test

Если regression test невозможно/нецелесообразно добавить, это следует объяснить в task/change.

---

## 88. OpenSpec и tests

Behavior tests должны соответствовать `openspec/specs/`.

При изменении product behavior:

```text
spec
  ↓
tests
  ↓
implementation
```

Не следует менять tests только для подгонки под случайное текущее behavior.

---

## 89. Acceptance tests

Для OpenSpec change полезно связывать tasks/spec scenarios с tests.

Например:

```text
Spec:
When connection is lost during streaming,
client reconnects and ignores stale events.

Tests:
- reconnect_restores_stream_test
- stale_generation_ignored_test
```

---

## 90. Main test layers

### Layer 1 — Protocol

Проверяет wire correctness.

### Layer 2 — Transport

Проверяет I/O и framing.

### Layer 3 — Client core

Проверяет ACP client semantics.

### Layer 4 — BLoC/Cubit

Проверяет presentation orchestration.

### Layer 5 — Widget

Проверяет UI rendering/interactions.

### Layer 6 — Integration

Проверяет critical end-to-end flow.

---

## 91. Нежелительные patterns

### Всё тестируется integration test

Медленно, сложно диагностировать.

### `Future.delayed` для синхронизации

Создаёт flaky tests.

### Real network в unit test

Нестабильно.

### Real user filesystem

Опасно.

### Production agent в tests

Невоспроизводимо.

### Test implementation details

Ломается при любом refactor.

### Massive mocks

Признак слишком тесного coupling.

---

## 92. Checklist для новой feature

Перед завершением feature проверить:

1. Есть ли pure Dart logic?
2. Нужны ли unit tests?
3. Есть ли BLoC/Cubit?
4. Нужны ли BLoC tests?
5. Есть ли новый Widget behavior?
6. Нужен ли widget test?
7. Есть ли platform integration?
8. Нужен ли adapter test?
9. Затронут ли ACP?
10. Нужны ли compatibility tests?
11. Есть ли concurrency/race?
12. Нужен ли regression/integration test?

---

## 93. Checklist для bug fix

При bug fix:

1. Воспроизвести проблему.
2. Определить layer, где нарушен invariant.
3. Добавить regression test, если возможно.
4. Исправить минимальный owner component.
5. Запустить targeted tests.
6. Запустить analysis.
7. При shared change — расширить validation.

---

## 94. Главные invariants

### TEST-001 — Core behavior тестируется без Flutter

Protocol/client/state-machine logic остаётся pure Dart testable.

### TEST-002 — Race tests детерминированы

Нет arbitrary sleeps как основного способа синхронизации.

### TEST-003 — Integration tests дополняют unit tests

Не заменяют их.

### TEST-004 — Production не зависит от test infrastructure

`acp_testing` только test/dev dependency.

### TEST-005 — Security behavior имеет direct tests

Permission deny-by-default и stale decision покрыты тестами.

### TEST-006 — Protocol compatibility проверяется

Unknown/optional/versioned data имеет coverage.

### TEST-007 — Tests соответствуют specs

Тест не является источником нового product behavior сам по себе.

---

## 95. Основная модель

Хорошая testing strategy выглядит так:

```text
Protocol correctness
        ↓
Transport correctness
        ↓
Client lifecycle correctness
        ↓
Presentation orchestration
        ↓
Widget behavior
        ↓
Critical end-to-end flows
```

Если большинство bugs можно поймать только тяжёлым desktop integration test, lower-level boundaries и testability следует пересмотреть.
