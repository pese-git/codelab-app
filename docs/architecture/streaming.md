# Streaming в ACP Client

Этот документ определяет правила обработки streaming events в ACP Client.

Цели:

* обеспечить предсказуемое обновление state;
* исключить дублирование данных;
* корректно обрабатывать late events;
* сохранить consistency при reconnect;
* обеспечить корректную cancellation semantics;
* локализовать streaming logic вне Flutter widgets;
* сделать streaming поведение тестируемым.

Связанные документы:

* `AGENTS.md`
* `docs/architecture/acp-boundary.md`
* `docs/architecture/session-lifecycle.md`
* `docs/architecture/concurrency.md`
* `docs/architecture/observability.md`
* `docs/architecture/testing.md`

---

## 1. Основной принцип

Streaming event не должен напрямую изменять Flutter UI.

Предпочтительный flow:

```text
ACP transport
    │
    ▼
protocol decode
    │
    ▼
client/application event
    │
    ▼
stream reducer / state machine
    │
    ▼
application state
    │
    ▼
BLoC / Cubit
    │
    ▼
Flutter UI
```

Widgets должны отображать уже нормализованное состояние.

---

## 2. Что считается streaming

К streaming относятся долгоживущие операции, результат которых приходит несколькими событиями.

Например:

* incremental assistant output;
* progress notifications;
* tool-call updates;
* status changes;
* partial results;
* execution logs;
* file-operation progress;
* completion/error notifications.

Streaming не обязательно означает текстовый token stream.

---

## 3. Ownership

Streaming lifecycle должен иметь одного authoritative owner.

Предпочтительно:

```text
ACP request streaming
    → acp_client_core

presentation projection
    → BLoC/Cubit
```

Не допускается одновременно иметь независимую streaming aggregation logic в:

* transport;
* client core;
* BLoC;
* widget.

---

## 4. Correlation

Каждое streaming event должно быть связано с корректным operation context.

В зависимости от ACP это могут быть:

* `session_id`;
* `request_id`;
* `message_id`;
* `tool_call_id`;
* sequence number;
* connection generation.

Не следует связывать event с request только по признаку:

```text
"это сейчас единственный active request"
```

если protocol предоставляет явный identifier.

---

## 5. Request ownership

Каждый active streaming request должен иметь owner.

Conceptual model:

```text
StreamingRequest
├── sessionId
├── requestId
├── connectionGeneration
├── lifecycle
└── accumulatedState
```

Точная модель определяется реализацией.

---

## 6. Connection generation

Streaming event должен относиться к connection generation, если reconnect способен оставить late events от старого transport.

Пример:

```text
generation 7
    request 42
        chunk A

reconnect

generation 8
    request 42 / restored request

late chunk from generation 7
```

Late chunk старой generation не должен автоматически применяться к current state.

---

## 7. Stale events

Event считается stale, если он относится к уже неактуальному:

* connection;
* session;
* request;
* tool call;
* streaming generation.

Stale event НЕ ДОЛЖЕН менять authoritative current state.

Он может быть:

* проигнорирован;
* залогирован на debug/trace level;
* учтён в diagnostic metrics.

---

## 8. Duplicate events

Если ACP допускает replay или duplicate delivery, streaming reducer должен быть устойчив к дубликатам.

Пример нежелательного поведения:

```text
chunk "Hello"
chunk "Hello" replayed

UI:
HelloHello
```

Idempotency strategy должна основываться на protocol guarantees.

Возможные механизмы:

* stable event id;
* sequence number;
* offset;
* revision;
* deduplication key.

Не следует придумывать deduplication heuristic без protocol basis.

---

## 9. Ordering

Клиент не должен предполагать ordering сильнее, чем гарантирует ACP.

Нужно явно определить:

* гарантирован ли порядок внутри request;
* гарантирован ли порядок между tool events;
* возможно ли interleaving нескольких requests;
* возможно ли получение completion раньше buffered updates.

Если ordering является частью protocol, reducer должен проверять его.

---

## 10. Sequence numbers

Если ACP предоставляет sequence number, его следует использовать как first-class concept.

Например:

```text
request 42:
seq 1
seq 2
seq 3
```

Клиент может обнаруживать:

* duplicate sequence;
* missing sequence;
* out-of-order sequence.

Конкретная reaction определяется specification.

---

## 11. Out-of-order event

Out-of-order event не должен автоматически применяться к state, если это нарушает semantics.

Возможные стратегии:

* buffer;
* reject;
* wait for missing event;
* mark request inconsistent;
* fail request.

Выбор должен соответствовать ACP/OpenSpec.

UI не должен самостоятельно переставлять protocol events.

---

## 12. Buffering

Buffering допускается только если он решает конкретную protocol/application проблему.

Buffer должен иметь:

* owner;
* bounded lifecycle;
* size policy;
* cleanup behavior.

Не допускается бесконечный buffer без лимитов.

---

## 13. Buffer limits

Если streaming способен генерировать большой объём данных, следует определить limits.

Например:

* max buffered events;
* max buffered bytes;
* max retained logs;
* max in-memory message size.

Exceeded limit должен иметь определённое behavior.

---

## 14. Backpressure

Если producer может генерировать события быстрее, чем client способен обрабатывать, необходимо учитывать backpressure.

Возможные подходы зависят от transport/API:

* bounded queue;
* throttling;
* sampling для non-critical progress;
* batching;
* producer-side flow control.

Критические protocol events нельзя терять ради UI performance.

---

## 15. UI throttling

Application state и UI refresh rate — разные concerns.

Допустимо:

```text
100 protocol events/sec
        │
        ▼
application state updates
        │
        ▼
UI projection throttled to 30 FPS
```

если это не меняет semantics.

UI optimization не должна приводить к потере authoritative events.

---

## 16. Text streaming

Для incremental text следует определить semantics event.

Возможные модели:

```text
append delta
replace current text
revision snapshot
```

Нельзя предполагать `append`, если protocol передаёт полный snapshot.

---

## 17. Delta semantics

Если event является delta:

```text
"Hel"
"lo"
```

reducer может собрать:

```text
"Hello"
```

Если event является snapshot:

```text
"Hel"
"Hello"
```

результат также:

```text
"Hello"
```

но algorithm другой.

Это должно быть определено protocol layer/application mapping.

---

## 18. Revision-based updates

Если ACP поддерживает revisions, следует хранить revision/version.

Пример:

```text
message revision 1
message revision 2
```

Older revision не должен перезаписывать newer state.

---

## 19. Multiple streams

Session может потенциально иметь несколько параллельных streams.

Например:

```text
assistant output
tool execution
progress
diagnostics
```

Их не следует объединять в один stream только ради удобства, если semantics различаются.

---

## 20. Concurrent requests

Если ACP поддерживает concurrent requests:

```text
request A ── stream
request B ── stream
```

reducer обязан разделять их по request identifiers.

Один BLoC state может агрегировать несколько requests, но ownership каждого event должен оставаться однозначным.

---

## 21. Single-request policy

Если приложение разрешает только один active request на session, это должно быть application invariant.

Streaming implementation не должна случайно допускать второй request только потому, что transport способен его передавать.

---

## 22. Completion

Completion является lifecycle event, а не просто очередным chunk.

После terminal completion request должен перестать принимать normal streaming updates, если protocol не определяет иначе.

---

## 23. Duplicate completion

Duplicate completion должен быть безопасным.

Он не должен:

* повторно финализировать state;
* повторно показывать notification;
* повторно запускать persistence;
* повторно завершать completer;
* генерировать вторую analytics event без необходимости.

---

## 24. Event after completion

Event, пришедший после terminal completion, должен быть обработан согласно protocol semantics.

По умолчанию его следует считать unexpected/stale, а не оживлять request.

---

## 25. Error completion

Error должен быть явным terminal outcome, если ACP определяет его как terminal.

Например:

```text
streaming
    │
    ▼
failed
```

После этого обычные chunks не должны менять state.

---

## 26. Cancellation

Cancellation взаимодействует со streaming lifecycle.

Типовой flow:

```text
streaming
    │
    ▼
cancelling
    │
    ├── cancelled
    ├── completed
    └── failed
```

Во время `cancelling` могут прийти late events.

Их semantics должны быть определены.

---

## 27. Chunks during cancellation

Если chunk приходит после отправки cancel, но до acknowledgement:

* он может быть valid;
* он может быть ignored;
* он может быть accepted до terminal cancellation.

Правило должно соответствовать ACP.

UI не должен самостоятельно решать этот race.

---

## 28. Completion during cancellation

Completion и cancellation могут соревноваться.

Необходимо иметь deterministic rule.

Например:

```text
completion received first
    → completed

cancellation acknowledgement received first
    → cancelled
```

Конкретное правило — source of truth в specification/application lifecycle.

---

## 29. Disconnect during stream

При disconnect необходимо определить судьбу stream.

Варианты:

* fail immediately;
* suspend;
* recover after reconnect;
* replay after reconnect;
* resume from sequence.

Это protocol/application policy.

---

## 30. Reconnect

Reconnect не должен автоматически создавать второй subscriber на тот же logical stream.

После reconnect необходимо проверить:

* какие subscriptions были закрыты;
* какие восстановлены;
* какие request IDs ещё valid;
* какие events могли быть replayed.

---

## 31. Replay after reconnect

Если agent может replay события после reconnect, reducer обязан быть idempotent.

Если replay начинается с определённой sequence/revision, client должен использовать её для reconciliation.

---

## 32. Resume cursor

Если ACP поддерживает resume cursor/offset/sequence, его следует хранить на application boundary.

Например:

```text
lastAppliedSequence = 184
```

После reconnect:

```text
resume from 185
```

если protocol это поддерживает.

---

## 33. Snapshot reconciliation

Если после reconnect agent присылает полный snapshot, приложение должно уметь reconciliate его с локальным state.

Snapshot может быть authoritative.

Не следует автоматически append snapshot к старому state.

---

## 34. Local optimistic state

Если UI показывает optimistic state, его следует отличать от confirmed ACP state.

Например:

```text
local:
prompt submitted

remote:
request accepted
```

Optimistic update не должен уничтожать возможность корректной reconciliation при failure.

---

## 35. Tool call streaming

Tool call может иметь собственный stream:

```text
requested
arguments partial
awaiting permission
executing
progress
completed
```

Tool call events должны коррелироваться по `tool_call_id` или эквиваленту.

---

## 36. Permission pause

Если tool call ждёт permission, это не обязательно terminal pause всего session stream.

Необходимо определить:

* продолжает ли agent слать другие events;
* блокируется ли request;
* возможны ли параллельные tool calls.

State model должна поддерживать protocol semantics.

---

## 37. Progress events

Progress events обычно менее critical, чем state transitions.

Их можно:

* throttle;
* aggregate;
* drop intermediate values;

если конечный state сохраняется и specification это допускает.

---

## 38. Critical vs non-critical events

Следует различать:

### Critical

* request started;
* tool call requested;
* permission required;
* completed;
* failed;
* cancelled.

### Potentially compressible

* percentage progress;
* frequent intermediate status;
* rendering-only telemetry.

Оптимизации не должны затрагивать critical events.

---

## 39. Event normalization

Protocol events следует нормализовать до application semantics.

Например:

```text
ACP notification A
ACP notification B
ACP notification C
        │
        ▼
RequestProgressChanged
```

если они представляют одно application concept.

---

## 40. Reducer

Для сложного streaming state следует использовать reducer/state machine approach.

Conceptually:

```text
CurrentState + Event → NewState
```

Преимущества:

* deterministic tests;
* replay;
* observability;
* race analysis;
* duplicate handling.

---

## 41. Reducer purity

По возможности reducer должен быть pure.

То есть:

```text
state + event -> new state
```

без:

* network;
* filesystem;
* dialogs;
* timers;
* hidden global state.

Side effects запускаются отдельно на application layer.

---

## 42. Side effects

Streaming event может инициировать side effect.

Например:

```text
PermissionRequired
    → request user decision
```

Но reducer должен сначала сформировать explicit state/event, а не напрямую открыть dialog.

---

## 43. Event processing queue

Если несколько events могут приходить concurrently, application layer должна определить serialization strategy.

Для одного logical request обычно следует сохранять sequential processing.

Нельзя позволять двум async handlers одновременно мутировать один mutable state.

---

## 44. Sequential processing

Conceptually:

```text
event 1
   ↓
reduce
   ↓
event 2
   ↓
reduce
```

предпочтительнее:

```text
event 1 ── async mutate ──┐
                          ├── race
event 2 ── async mutate ──┘
```

---

## 45. Async event handlers

Если обработка event требует async operation, следует отделять:

```text
event received
    │
    ▼
state transition
    │
    ▼
side effect
    │
    ▼
result event
```

Например:

```text
ReconnectNeeded
    ↓
state = reconnecting
    ↓
attemptReconnect()
    ↓
ReconnectSucceeded / ReconnectFailed
```

---

## 46. Event loop ownership

Application/client layer должен иметь явный event processing mechanism.

Нельзя распределять обработку одного streaming lifecycle по множеству независимых callbacks без общего ownership.

---

## 47. Stream subscription lifecycle

Каждый `StreamSubscription` должен:

* иметь owner;
* быть сохранён;
* быть cancelled;
* не переживать owner без явной причины.

Не создавать `listen(...)` без lifecycle plan.

---

## 48. Broadcast streams

Broadcast stream следует использовать только когда действительно требуется несколько независимых consumers.

Не следует делать каждый stream broadcast по умолчанию.

Broadcast semantics усложняет:

* ordering;
* lifecycle;
* missed events;
* ownership.

---

## 49. Late subscribers

Если consumer должен видеть current state после подписки, обычный event stream может быть недостаточен.

Следует использовать:

* state holder;
* replay mechanism;
* current snapshot API;

вместо предположения, что новый subscriber получит старые events.

---

## 50. Stream errors

Нельзя позволять stream error бесконтрольно завершать critical subscription.

Следует определить:

* является ли error terminal;
* переводится ли он в application event;
* должен ли stream закрыться;
* требуется ли reconnect.

---

## 51. Stream closure

`onDone` должен иметь defined semantics.

Например:

```text
transport stream done
    ↓
TransportClosed
    ↓
ConnectionLost
```

а не просто молчаливое завершение updates.

---

## 52. Memory management

Streaming может удерживать большой объём state.

Следует избегать:

* бесконечной истории raw chunks;
* сохранения всех protocol payload;
* retaining stale requests;
* retaining old subscriptions.

Application может хранить normalized final state вместо всех промежуточных events.

---

## 53. Conversation history

Conversation history и streaming buffer — разные вещи.

После завершения message можно хранить:

```text
final message
```

а не обязательно:

```text
all 10 000 deltas
```

если они не нужны для diagnostics.

---

## 54. Diagnostics buffer

Если нужен protocol/event history для debug, он должен иметь bounded size.

Например:

```text
last N events
```

или ring buffer.

Не следует бесконечно хранить full protocol trace в RAM.

---

## 55. Logging

Streaming logs должны позволять понять flow без логирования каждого символа текста.

Полезно логировать:

* request id;
* event type;
* sequence/revision;
* generation;
* transition;
* duplicate/stale detection.

Например:

```text
request=42 seq=8 event=chunk applied
request=42 seq=8 event=chunk duplicate ignored
```

---

## 56. Payload logging

Полный streaming payload не следует логировать в production по умолчанию.

Причины:

* secrets;
* user data;
* performance;
* log volume.

Debug protocol tracing определяется `observability.md`.

---

## 57. BLoC boundary

BLoC должен получать application-friendly updates.

Предпочтительно:

```text
RequestStateChanged
MessageUpdated
ToolCallChanged
```

вместо raw:

```text
JsonRpcNotification(method, params)
```

---

## 58. BLoC rebuilds

Streaming может генерировать много state changes.

Presentation следует оптимизировать через:

* `buildWhen`;
* `BlocSelector`;
* granular state;
* derived view models;

где это необходимо.

Но optimization не должна менять authoritative application semantics.

---

## 59. Widget local state

Ephemeral presentation-only state может оставаться в widget.

Например:

* scroll hover;
* temporary animation state;
* local expansion state.

Streaming ACP state не должен становиться widget-local authoritative state.

---

## 60. Scroll behavior

Auto-scroll является presentation concern.

Он должен реагировать на presentation state, а не участвовать в streaming reducer.

Например:

```text
message updated
    ↓
UI rebuild
    ↓
auto-scroll policy
```

---

## 61. Persistence

Не следует записывать persistent storage на каждый маленький streaming chunk без необходимости.

Возможные strategies:

* debounce;
* periodic checkpoint;
* persist terminal state;
* transactional batches.

Persistence strategy должна обеспечивать recovery semantics и не блокировать UI.

---

## 62. Crash recovery

Если требуется recovery незавершённого stream после crash, следует определить checkpoint semantics.

Нельзя предполагать, что любой промежуточный UI state является recoverable ACP state.

---

## 63. Testing strategy

Streaming tests должны быть преимущественно deterministic и pure Dart.

Использовать:

* fake transport;
* controlled streams;
* explicit sequence events;
* Completer;
* fake clock при необходимости.

---

## 64. Базовые streaming tests

Минимум:

* one chunk;
* multiple chunks;
* completion;
* duplicate chunk;
* duplicate completion;
* late chunk after completion;
* out-of-order event;
* stale generation event;
* stale request event;
* disconnect during stream;
* reconnect;
* cancellation during stream;
* completion/cancel race.

---

## 65. Replay tests

Если replay поддерживается:

```text
events 1..10 applied
reconnect
events 7..12 replayed
```

финальный state должен быть эквивалентен корректной последовательности `1..12`.

---

## 66. Interleaving tests

Если concurrent requests допустимы:

```text
A1
B1
A2
B2
A3
```

state request A и B должен собираться независимо.

---

## 67. Missing sequence tests

Если sequence является обязательным:

```text
1
2
4
```

должно приводить к defined behavior.

Не следует незаметно считать, что sequence 3 не нужен.

---

## 68. Load tests

Для high-volume streaming полезно отдельно проверять:

* memory growth;
* event processing latency;
* Flutter rebuild frequency;
* queue growth;
* log volume.

Performance optimization должна выполняться после сохранения correctness invariants.

---

## 69. Нежелательные patterns

### Raw stream в widget

```dart
StreamBuilder<RawAcpMessage>(...)
```

нежелателен для application-level ACP stream.

---

### JSON parsing в BLoC

```dart
final json = jsonDecode(event.payload);
```

для wire ACP protocol в presentation layer — нарушение boundary.

---

### Untracked `listen`

```dart
client.events.listen(...);
```

без сохранения subscription и disposal — запрещённый lifecycle pattern.

---

### Shared mutable accumulator

```dart
var currentText = '';

stream.listen((chunk) async {
  currentText += chunk;
  await something();
});
```

может создавать race при concurrent callbacks.

---

### UI-driven deduplication

```text
if widget already displays same text -> ignore event
```

не является protocol deduplication strategy.

---

## 70. Checklist перед изменением streaming

Перед реализацией агент ОБЯЗАН определить:

1. Какой request/session владеет stream.
2. Какие IDs используются для correlation.
3. Какие ordering guarantees даёт ACP.
4. Возможны ли duplicates.
5. Возможен ли replay.
6. Возможны ли late events.
7. Как определяется terminal state.
8. Как работает cancellation.
9. Что происходит при disconnect.
10. Как работает reconnect.
11. Требуется ли buffering.
12. Какие memory limits нужны.
13. Где находится reducer/state machine.
14. Какие tests покрывают races.

---

## 71. Главные invariants

### STR-001 — Raw ACP не мутирует UI напрямую

Все protocol events проходят application boundary.

### STR-002 — Event имеет owner

Любой event однозначно относится к session/request/tool call.

### STR-003 — Stale event не меняет current state

Old generation/request/session event игнорируется.

### STR-004 — Terminal state не оживает

После completion/cancel/failure обычный late event не возвращает request в running.

### STR-005 — Duplicate event безопасен

Replay/deduplication не создаёт duplicate user-visible state.

### STR-006 — Streaming lifecycle тестируем

Основная aggregation/state transition logic работает без Flutter binding.

### STR-007 — UI optimization не меняет semantics

Throttle/rebuild optimization допускается только на presentation boundary.

---

## 72. Основная модель

Streaming следует проектировать как deterministic processing pipeline:

```text
incoming event
      │
      ▼
validate identity
      │
      ▼
validate ordering/lifecycle
      │
      ├── stale/duplicate → ignore/log
      │
      ▼
normalize
      │
      ▼
reduce
      │
      ▼
new application state
      │
      ▼
presentation projection
```

Если корректность streaming зависит от случайного порядка async callbacks, widget lifecycle или набора mutable flags, архитектуру следует пересмотреть.
