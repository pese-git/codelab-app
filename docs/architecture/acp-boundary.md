# ACP boundary

Этот документ описывает архитектурную границу между ACP (Agent Client Protocol) и остальной частью ACP Client.

Цель документа — обеспечить:

* изоляцию wire protocol;
* предсказуемое evolution протокола;
* отсутствие protocol leakage в UI;
* стабильные application models;
* тестируемость ACP client logic;
* корректную обработку ошибок;
* устойчивость к streaming, reconnect и version changes.

Обязательные repository-wide правила:

`AGENTS.md`

Связанные документы:

* `docs/architecture/layers-and-dependencies.md`
* `docs/architecture/session-lifecycle.md`
* `docs/architecture/streaming.md`
* `docs/architecture/concurrency.md`
* `docs/architecture/permissions.md`
* `docs/architecture/testing.md`

---

## 1. Основной принцип

ACP является **external protocol boundary**.

Wire representation ACP не является внутренней моделью всего приложения.

Основной inbound flow:

```text
External Agent
      │
      ▼
Transport
      │
      ▼
ACP wire message
      │
      ▼
acp_protocol
      │
      ▼
ACP client core
      │
      ▼
Application concepts/state
      │
      ▼
Presentation mapping
      │
      ▼
Flutter UI
```

Outbound flow:

```text
Flutter UI
      │
      ▼
User/Application intent
      │
      ▼
ACP client core
      │
      ▼
Protocol command/request
      │
      ▼
acp_protocol
      │
      ▼
Transport
      │
      ▼
External Agent
```

---

## 2. Что считается ACP boundary

К ACP boundary относятся:

* protocol messages;
* request/response;
* notifications;
* method identifiers;
* protocol version;
* serialization/deserialization;
* transport framing;
* correlation identifiers;
* protocol errors;
* compatibility rules;
* unknown fields/messages;
* transport lifecycle.

Эти детали не должны бесконтрольно распространяться по presentation layer.

---

## 3. Ответственность `acp_protocol`

Package:

`packages/dart/acp_protocol`

Отвечает только за protocol-level concerns.

Допустимо содержать:

* wire DTO;
* typed requests;
* typed responses;
* notifications;
* method names/identifiers;
* serialization;
* deserialization;
* schema validation;
* protocol version types;
* protocol-level errors.

Не должен содержать:

* BLoC;
* Flutter widgets;
* permission dialogs;
* navigation;
* presentation state;
* application workflow;
* reconnect UX;
* tool-call visual state.

---

## 4. Ответственность `acp_transports`

Package:

`packages/dart/acp_transports`

Отвечает за передачу protocol data.

Допустимо содержать:

* stdio transport;
* process transport;
* socket transport;
* stream transport;
* transport framing;
* connection lifecycle primitives;
* transport-level failures.

Transport не должен решать application semantics.

Например:

```text
process exited
```

является transport event.

Но решение:

```text
reconnect session
```

является application behavior.

---

## 5. Ответственность `acp_client_core`

Package:

`packages/dart/acp_client_core`

Отвечает за reusable client-side semantics ACP.

Он может:

* связывать transport и protocol;
* управлять request lifecycle;
* управлять session lifecycle;
* отслеживать correlation;
* преобразовывать protocol events в application/client events;
* инициировать cancellation;
* управлять reconnect policy;
* публиковать application-level state;
* создавать permission requests.

Он не должен зависеть от Flutter.

---

## 6. Protocol model ≠ Application model

Нужно различать как минимум два уровня:

```text
Protocol model
      │
      ▼
Application/client model
```

Protocol model отвечает на вопрос:

> Как данные выглядят в ACP?

Application model отвечает на вопрос:

> Что эти данные означают для клиента?

Например protocol message может содержать:

```text
method
params
id
version
metadata
```

Application layer может преобразовать это в:

```text
PromptStarted
PromptChunkReceived
ToolCallRequested
PermissionRequired
PromptCompleted
SessionDisconnected
```

---

## 7. Application model ≠ Presentation model

Presentation может требовать ещё одну форму данных:

```text
Protocol
   ↓
Application
   ↓
Presentation
```

Например application state:

```text
ToolCall(
  id,
  capability,
  arguments,
  status,
)
```

может отображаться как:

```text
ToolCallViewModel(
  title,
  description,
  statusLabel,
  canApprove,
  canDeny,
)
```

Presentation model создаётся только когда UI semantics действительно отличаются.

Не нужно создавать отдельный DTO на каждом уровне автоматически.

---

## 8. Когда mapping обязателен

Mapping между protocol и application model обязателен, если хотя бы одно верно:

* protocol model содержит wire-specific поля;
* schema может меняться независимо от UI;
* application объединяет несколько protocol messages;
* protocol message имеет более низкоуровневую semantics;
* требуется normalisation;
* требуется validation;
* требуется compatibility logic;
* application должен скрыть protocol implementation details.

---

## 9. Когда mapping не нужен

Отдельный mapping не требуется, если type:

* является стабильным value object;
* не содержит wire-specific semantics;
* не создаёт нежелательного coupling;
* не меняет смысл между layers.

Архитектура не должна создавать DTO ради DTO.

---

## 10. Raw protocol messages в UI

Widgets НЕ ДОЛЖНЫ:

* парсить raw ACP JSON;
* проверять method string;
* декодировать protocol fields;
* вручную интерпретировать version;
* самостоятельно dispatch protocol commands.

Неправильно:

```dart
if (message.method == 'session/update') {
  ...
}
```

в widget/BLoC presentation layer.

Правильнее:

```text
Protocol handler
      │
      ▼
SessionUpdated
      │
      ▼
BLoC
      │
      ▼
Widget
```

---

## 11. Outbound commands

UI должен выражать **intent**, а не ACP wire command.

Например:

Неправильно:

```text
Widget
  → sendRawRequest("session/prompt", {...})
```

Предпочтительно:

```text
Widget
  → SendPrompt intent
      → client/application API
          → ACP request
```

Это позволяет менять protocol representation без изменения UI.

---

## 12. Correlation

Все request/response и долгоживущие operations должны иметь явную correlation strategy.

По возможности использовать identifiers ACP:

* `session_id`;
* `request_id`;
* `message_id`;
* `tool_call_id`.

Application layer не должен полагаться только на порядок сообщений, если ACP предоставляет explicit IDs.

---

## 13. Connection generation

При reconnect рекомендуется использовать дополнительный локальный идентификатор connection generation.

Пример:

```text
connection #41
connection #42
```

Event от предыдущей generation не должен менять актуальное state.

Пример:

```text
generation=41 -> late completion
generation=42 -> current connection
```

Event generation 41 должен быть проигнорирован, если операция уже принадлежит generation 42.

---

## 14. Session ownership

Session identifier ACP и local runtime state следует различать.

Возможны:

```text
ACP session id
local session entity
connection generation
active request id
```

Не следует использовать один identifier для разных lifecycle concepts.

Это особенно важно при:

* reconnect;
* restore;
* session resume;
* cancellation;
* concurrent requests.

---

## 15. Streaming

Streaming ACP messages не должны напрямую мутировать widgets.

Предпочтительный pipeline:

```text
ACP notification
      │
      ▼
Protocol decode
      │
      ▼
Client event
      │
      ▼
State reducer/state machine
      │
      ▼
Application state
      │
      ▼
BLoC/presentation
```

Подробные rules:

`docs/architecture/streaming.md`

---

## 16. Idempotency

Если ACP допускает duplicate delivery или replay, обработка должна быть идемпотентной.

Необходимо избегать:

```text
duplicate chunk
    → duplicate UI message

duplicate completion
    → double finalize

duplicate tool call
    → second permission dialog
```

Idempotency strategy должна использовать stable identifiers или sequence information, если они доступны.

---

## 17. Ordering

Нельзя предполагать ordering, который не гарантируется ACP.

Если protocol гарантирует порядок только внутри request/session, это должно быть отражено в state handling.

Если ordering критичен:

* использовать sequence;
* correlation;
* state machine;
* explicit buffering;

в соответствии со спецификацией.

Не следует "исправлять" порядок эвристиками в UI.

---

## 18. Unknown fields

Forward compatibility должна сохраняться там, где это требует ACP.

Unknown fields не должны автоматически приводить к fatal parsing error, если protocol разрешает их игнорирование/сохранение.

Если protocol model поддерживает extension fields, следует сохранять их в той форме, которую определяет implementation.

Нельзя использовать unknown field как known semantics без спецификации.

---

## 19. Unknown methods/messages

Unknown ACP method или message должен обрабатываться явно.

Возможные стратегии зависят от specification:

* ignore;
* log;
* return protocol error;
* preserve as unknown message;
* terminate incompatible session.

Нельзя молча интерпретировать unknown method как существующий.

---

## 20. Protocol version

Protocol version должен быть first-class concept, если ACP versioned.

Version negotiation и compatibility должны происходить на ACP/client boundary.

Presentation не должен знать:

```text
if ACP v1 -> ...
if ACP v2 -> ...
```

если это можно скрыть в protocol/application layers.

Предпочтительно:

```text
ACP v1
ACP v2
   │
   ▼
normalized application model
   │
   ▼
same UI
```

---

## 21. Backward compatibility

При поддержке старой версии agent:

* compatibility logic локализуется в protocol/client boundary;
* UI не должен быть заполнен version checks;
* старые данные нормализуются в актуальную application semantics, если возможно;
* unsupported capability должна быть представлена явно.

---

## 22. Forward compatibility

При получении данных от более новой версии agent:

* неизвестные допустимые поля не должны ломать client;
* неизвестная capability не должна автоматически считаться безопасной;
* неизвестное behavior должно fail predictably;
* protocol diagnostics должны содержать version/context.

---

## 23. Serialization

Serialization должна быть централизована в `acp_protocol`.

Не следует вручную сериализовать ACP payload в:

* BLoC;
* widget;
* application feature;
* transport adapter.

Transport должен работать с установленным protocol representation.

---

## 24. Deserialization

Deserialization должна выполнять:

* shape validation;
* required field validation;
* type validation;
* version-aware parsing, если необходимо.

Parsing error должен иметь достаточно context для диагностики, но не раскрывать secrets в production logs.

---

## 25. Protocol validation

Validation делится на два уровня.

Protocol validation:

```text
"поле существует?"
"тип правильный?"
"message соответствует schema?"
```

Application validation:

```text
"можно ли выполнить это действие сейчас?"
"принадлежит ли request текущей session?"
"разрешено ли capability?"
```

Не следует смешивать эти две ответственности.

---

## 26. Errors

Ошибки должны преобразовываться по boundaries.

Пример:

```text
InvalidJson
    ↓
ProtocolDecodeError
    ↓
ACPClientProtocolFailure
    ↓
Presentation error state
```

Не каждая ошибка требует четырёх отдельных классов.

Mapping оправдан, когда меняется semantics.

---

## 27. Transport failures

Transport failure не должен напрямую определять application state.

Например:

```text
ProcessExited
```

может привести к:

```text
SessionDisconnected
```

или:

```text
SessionReconnecting
```

в зависимости от application policy.

Transport не должен самостоятельно решать, какой UX показать.

---

## 28. Protocol failures

Примеры protocol failures:

* malformed response;
* unknown required field;
* invalid request id;
* unsupported version;
* invalid method payload.

Они должны логироваться с correlation context.

В release нельзя без необходимости сохранять полный sensitive payload.

---

## 29. Cancellation

Cancellation должна проходить через ACP client/application API.

UI выражает intent:

```text
CancelCurrentOperation
```

Client core определяет:

* какой request отменяется;
* какое ACP сообщение отправить;
* как обработать race completion/cancel;
* как обновить lifecycle state.

UI не должен самостоятельно считать операцию отменённой только после нажатия кнопки.

---

## 30. Tool calls

Tool call должен проходить через application boundary.

Пример:

```text
ACP tool request
      │
      ▼
client core
      │
      ▼
ToolCall application model
      │
      ▼
permission policy
      │
      ▼
presentation
```

Widget не должен анализировать raw tool payload для security decision.

Подробности:

`docs/architecture/permissions.md`

---

## 31. Permission results

Решение пользователя должно быть связано с конкретным operation identifier.

Нельзя хранить только:

```text
lastPermission = allowed
```

без correlation.

Предпочтительно:

```text
PermissionDecision(
  sessionId,
  requestId,
  toolCallId,
  decision,
)
```

Конкретная модель определяется реализацией/спецификацией.

---

## 32. Capability handling

Capabilities, поддерживаемые agent, должны рассматриваться как negotiated/runtime capability, если это предусмотрено ACP.

UI не должен предполагать наличие capability только потому, что клиент умеет её отображать.

Правильнее:

```text
client supports X
agent advertises X
session allows X
→ X available
```

---

## 33. Optional capability

Отсутствие optional capability не является protocol failure.

Application должен уметь представить unavailable state.

UI может:

* скрыть действие;
* disable действие;
* показать unsupported state;

в зависимости от product spec.

---

## 34. Logging ACP

Следует логировать:

* направление сообщения;
* method/type;
* correlation identifiers;
* protocol version;
* lifecycle outcome;
* parsing failures.

Не следует по умолчанию логировать:

* secrets;
* auth tokens;
* sensitive file contents;
* полный tool payload;
* user data без необходимости.

---

## 35. Debug protocol dump

В debug build может существовать расширенный ACP tracing.

Он должен быть:

* явно включаемым;
* отключённым по умолчанию в release;
* способным mask sensitive values;
* пригодным для correlation.

---

## 36. Testing protocol boundary

Минимальные категории тестов:

### Serialization tests

```text
model → wire
```

### Deserialization tests

```text
wire → model
```

### Round-trip tests

```text
model → wire → model
```

если это имеет смысл для schema.

### Compatibility tests

* missing optional fields;
* unknown fields;
* supported older versions;
* unsupported version behavior.

### Invalid message tests

* malformed payload;
* wrong field type;
* invalid identifiers.

---

## 37. Client-core tests

`acp_client_core` следует тестировать отдельно от Flutter.

Полезные сценарии:

* request/response correlation;
* streaming updates;
* cancellation;
* disconnect;
* reconnect;
* stale event;
* duplicate event;
* unknown message;
* permission request;
* transport failure.

Использовать `acp_testing` там, где это снижает boilerplate.

---

## 38. Fake transport

Для unit/integration тестов рекомендуется fake/in-memory transport.

Он должен позволять:

* отправлять inbound messages;
* наблюдать outbound messages;
* симулировать disconnect;
* симулировать latency;
* симулировать duplicate events;
* симулировать late events;
* симулировать malformed input.

Fake transport не должен зависеть от Flutter.

---

## 39. Не допускать protocol leakage

Признаки protocol leakage:

* widget содержит ACP method string;
* BLoC вручную делает `jsonDecode` ACP payload;
* UI проверяет protocol version;
* presentation state хранит raw response map;
* dialog решает semantics tool capability;
* feature создаёт raw protocol request.

При обнаружении такого pattern следует проверить, не должна ли логика быть перенесена в `acp_protocol` или `acp_client_core`.

---

## 40. Когда допустим protocol type выше boundary

Иногда stable protocol type можно использовать выше, если:

* type является value object;
* он не содержит transport/wire-specific details;
* его semantics совпадает с application semantics;
* это уменьшает бессмысленное duplication.

Такое решение должно быть осознанным.

Не следует автоматически копировать каждый protocol type в application model.

---

## 41. Public ACP API

`acp_client_core` должен предоставлять application-friendly API.

Предпочтительно:

```text
connect()
createSession()
sendPrompt()
cancel()
respondToPermission()
disconnect()
```

или эквивалентные typed operations.

Менее предпочтительно для UI:

```text
send(method, Map<String, dynamic>)
```

Low-level API может существовать внутри protocol/client package, но не должен становиться основным interface presentation layer.

---

## 42. ACP client facade

При необходимости `acp_client_core` может предоставлять facade, скрывающий:

* transport;
* request registry;
* correlation;
* protocol encoding;
* event routing;
* lifecycle transitions.

Пример conceptual API:

```dart
abstract interface class AcpClient {
  Stream<AcpClientEvent> get events;

  Future<void> connect();

  Future<SessionId> createSession();

  Future<RequestId> sendPrompt(...);

  Future<void> cancel(RequestId requestId);

  Future<void> disconnect();
}
```

Конкретный API должен соответствовать существующему коду и OpenSpec.

Этот пример не является требованием создать именно такие методы.

---

## 43. Boundary ownership

Краткая таблица ответственности:

| Responsibility         | Owner                           |
| ---------------------- | ------------------------------- |
| Wire models            | `acp_protocol`                  |
| Serialization          | `acp_protocol`                  |
| Deserialization        | `acp_protocol`                  |
| Transport I/O          | `acp_transports`                |
| Connection primitives  | `acp_transports`                |
| Request correlation    | `acp_client_core`               |
| Session semantics      | `acp_client_core`               |
| Cancellation semantics | `acp_client_core`               |
| Permission abstraction | `acp_client_core` / application |
| UI state               | BLoC/Cubit                      |
| Rendering              | `acp_ui` / `codelab_app`        |

---

## 44. Изменение ACP schema

При изменении schema агент ОБЯЗАН определить:

1. Меняется ли wire contract.
2. Меняется ли protocol version.
3. Нужна ли backward compatibility.
4. Нужна ли forward compatibility.
5. Какие serializers/deserializers затрагиваются.
6. Какие tests должны быть обновлены.
7. Нужно ли менять application model.
8. Нужно ли менять UI.
9. Требуется ли OpenSpec change.

Изменение wire contract НЕ ДОЛЖНО происходить только потому, что UI удобнее получить данные в другой форме.

---

## 45. Изменение application model

Application model может изменяться без изменения wire protocol.

Например:

```text
ACP message A
ACP message B
      │
      ▼
NormalizedSessionUpdate
```

Это позволяет развивать UI/application semantics независимо от protocol schema.

---

## 46. Изменение presentation model

Presentation model может изменяться независимо от ACP protocol, если application semantics не меняется.

Это является желательной характеристикой architecture boundary.

UI redesign не должен требовать изменения ACP schema.

---

## 47. Checklist перед изменением ACP code

Перед изменением ACP boundary проверить:

1. Какой package является владельцем поведения?
2. Это protocol, transport или application semantics?
3. Есть ли соответствующая OpenSpec specification?
4. Не протекает ли raw protocol в UI?
5. Не протекает ли Flutter в pure Dart package?
6. Как обрабатываются unknown fields/messages?
7. Как изменение влияет на version compatibility?
8. Как выполняется correlation?
9. Возможны ли duplicate/late events?
10. Какие tests должны быть добавлены?

---

## 48. Главный invariant

Архитектура должна позволять заменить или изменить wire-level детали ACP с минимальным влиянием на Flutter UI.

Желаемая зависимость:

```text
ACP changes
    │
    ▼
protocol/client boundary
    │
    ▼
stable application semantics
    │
    ▼
UI
```

Нежелательная:

```text
ACP field renamed
    │
    ├── widget changed
    ├── dialog changed
    ├── BLoC changed
    ├── navigation changed
    └── five features changed
```

Если небольшое protocol изменение требует широких изменений presentation layer, следует проверить качество ACP boundary.
