# Lifecycle соединения и ACP-сессии

Этот документ описывает lifecycle соединения с AI agent и ACP session.

Цели:

* исключить невозможные состояния;
* сделать reconnect предсказуемым;
* корректно обрабатывать cancellation;
* исключить влияние stale events;
* отделить transport lifecycle от session lifecycle;
* обеспечить тестируемую state machine.

Общие правила:

* `AGENTS.md`
* `docs/architecture/acp-boundary.md`
* `docs/architecture/streaming.md`
* `docs/architecture/concurrency.md`

---

## 1. Основной принцип

Connection и Session — разные lifecycle concepts.

Не следует смешивать:

```text
transport connection
ACP session
active request
tool call
permission request
```

в один общий набор boolean flags.

Каждый lifecycle должен иметь:

* owner;
* state;
* transitions;
* identifiers;
* failure semantics.

---

## 2. Уровни lifecycle

Основные уровни:

```text
Transport
   │
   ▼
Connection
   │
   ▼
ACP Session
   │
   ▼
Request / Prompt
   │
   ▼
Tool Call / Permission
```

Lower-level lifecycle не должен автоматически определять higher-level semantics.

Например:

```text
transport disconnected
```

не всегда означает:

```text
session permanently lost
```

Session может перейти в reconnecting/recovering state.

---

## 3. Connection lifecycle

Connection описывает физическую или логическую связь с agent.

Типичные состояния:

```text
disconnected
connecting
connected
disconnecting
reconnecting
failed
```

Конкретная модель должна соответствовать реализации.

---

## 4. Session lifecycle

ACP session описывает logical interaction context.

Типичные состояния:

```text
notCreated
creating
ready
running
cancelling
recovering
closed
failed
```

Не требуется использовать именно эти имена.

Важно, чтобы states:

* были mutually exclusive;
* имели понятные transitions;
* не допускали невозможных комбинаций.

---

## 5. Request lifecycle

Prompt/request также должен иметь отдельный lifecycle.

Пример:

```text
idle
starting
streaming
waitingForPermission
cancelling
completed
cancelled
failed
```

Session state и request state не обязательно должны быть одним типом.

Например:

```text
Session = ready
Request = completed
```

является нормальным состоянием.

---

## 6. Почему нельзя использовать набор boolean flags

Плохо:

```dart
bool isConnected;
bool isRunning;
bool isCancelling;
bool isReconnecting;
bool hasError;
```

Такая модель допускает:

```text
isConnected = false
isRunning = true
isCancelling = true
isReconnecting = true
```

и не объясняет, валидно ли это.

Предпочтительно использовать explicit state types.

Например:

```dart
sealed class SessionState {
  const SessionState();
}
```

или Freezed union.

---

## 7. State ownership

Рекомендуемое ownership:

```text
Transport state
    → acp_transports

Connection/session semantics
    → acp_client_core

Presentation state
    → BLoC/Cubit
```

BLoC не должен быть единственным владельцем низкоуровневого lifecycle, если тот reusable и относится к ACP client semantics.

---

## 8. Базовый lifecycle

Типовой flow:

```text
Disconnected
    │
    ▼
Connecting
    │
    ▼
Connected
    │
    ▼
SessionCreating
    │
    ▼
SessionReady
    │
    ▼
Running
    │
    ├──► Completed ───► SessionReady
    │
    ├──► Cancelling ──► SessionReady
    │
    └──► Failed ──────► SessionReady / Failed
```

Это conceptual model, а не обязательные имена классов.

---

## 9. Connect

Connect operation должен быть идемпотентным или явно запрещать повторный вызов.

Следует определить behavior для:

```text
connect() while disconnected
connect() while connecting
connect() while connected
connect() while reconnecting
```

Нельзя оставлять эти случаи неявными.

---

## 10. Duplicate connect

Если `connect()` вызван во время `connecting`, допустимые стратегии:

* вернуть существующий Future;
* игнорировать повторный intent;
* вернуть typed state error.

Не следует создавать второй transport connection.

---

## 11. Disconnect

Disconnect должен быть explicit operation.

Он должен определить:

* что происходит с active request;
* отменяются ли subscriptions;
* сохраняется ли session metadata;
* допускается ли reconnect;
* какой final state устанавливается.

---

## 12. Intentional disconnect

Нужно отличать:

```text
user requested disconnect
```

от:

```text
unexpected transport loss
```

Intentional disconnect обычно НЕ должен запускать reconnect policy.

---

## 13. Unexpected disconnect

Unexpected disconnect должен переходить в application-defined recovery flow.

Типовой вариант:

```text
Connected
    │
    ▼
ConnectionLost
    │
    ▼
Reconnecting
```

или:

```text
Connected
    │
    ▼
Failed
```

в зависимости от policy.

---

## 14. Reconnect

Reconnect является отдельным lifecycle.

Он не должен быть скрытым side effect без observable state.

UI должен иметь возможность отличать:

```text
connecting first time
```

от:

```text
reconnecting after loss
```

если это влияет на UX.

---

## 15. Connection generation

Каждое новое физическое connection instance должно иметь local generation/token.

Пример:

```text
generation 10
generation 11
generation 12
```

Event должен быть связан с generation, если существует риск late delivery.

---

## 16. Stale events

Event от предыдущей connection generation НЕ ДОЛЖЕН менять current state.

Пример:

```text
generation 5 disconnects
generation 6 connects
late event from generation 5 arrives
```

Late event generation 5 игнорируется.

---

## 17. Session resume

Если ACP поддерживает session resume/recovery, необходимо различать:

```text
new session
resume existing session
reconnect transport
```

Это разные операции.

Transport reconnect не должен автоматически создавать новую ACP session, если protocol поддерживает восстановление старой.

---

## 18. Session identity

Следует различать:

```text
local session object
ACP session id
connection generation
active request id
```

Один identifier не должен использоваться как surrogate для всех lifecycle уровней.

---

## 19. Session creation

Создание session должно иметь явный transition:

```text
connected
    │
    ▼
creating session
    │
    ├──► ready
    └──► failed
```

UI не должен считать session созданной до подтверждения ACP, если protocol требует response.

---

## 20. Session ready

`ready` означает:

* connection пригодно;
* session существует;
* нет active request, блокирующего новый prompt;
* application может принимать допустимые user intents.

Это application semantics, а не transport state.

---

## 21. Running

`running` означает, что существует активная ACP operation/request.

Running state должен быть связан с конкретным request identifier.

Не следует хранить просто:

```text
isRunning = true
```

без ownership/correlation.

---

## 22. Concurrent requests

Если ACP не поддерживает concurrent requests внутри session, client должен явно запрещать их.

Если поддерживает, state model должна отражать несколько active requests.

Не следует случайно получить concurrency только потому, что API асинхронный.

---

## 23. Request correlation

Каждый active request должен иметь:

* request id;
* owning session;
* connection generation;
* lifecycle state.

Это позволяет отфильтровывать stale events.

---

## 24. Streaming state

Request может находиться в streaming state после первого response/event.

Типовой flow:

```text
starting
   │
   ▼
streaming
   │
   ├──► completed
   ├──► cancelling
   └──► failed
```

Streaming details описаны в:

`docs/architecture/streaming.md`

---

## 25. Completion

Completion должен быть обработан ровно один раз на уровне state semantics.

Duplicate completion event не должен:

* повторно завершать state;
* добавлять дублированное сообщение;
* повторно запускать side effect.

---

## 26. Cancellation

Cancellation является отдельным transition:

```text
running
   │
   ▼
cancelling
   │
   ├──► cancelled
   ├──► completed
   └──► failed
```

Важно: `completed` во время cancellation может быть valid race.

---

## 27. Cancel race

Типичный race:

```text
user presses Cancel
client sends cancel
agent completes before cancel is processed
```

Client должен иметь deterministic rule.

Например:

```text
completion wins if valid completion arrived first
```

Конкретное правило должно соответствовать ACP/OpenSpec.

---

## 28. Cancellation acknowledgement

Если ACP предоставляет explicit acknowledgement cancellation, UI не должен считать operation окончательно cancelled до соответствующего application transition.

Допустимо показывать:

```text
Cancelling...
```

между user intent и подтверждением.

---

## 29. Double cancel

Повторный cancel не должен отправлять бесконечное число cancellation requests.

Допустимые стратегии:

* ignore;
* return current cancellation Future;
* typed already-cancelling result.

---

## 30. Disconnect during running

При disconnect во время active request client должен определить, что происходит с request.

Возможные варианты:

```text
request failed
request suspended
request awaiting reconnect
request recoverable
```

Это должно определяться protocol/application semantics, а не UI.

---

## 31. Disconnect during cancellation

Race:

```text
running
  ↓
cancelling
  ↓
connection lost
```

Client должен определить:

* считать ли cancel unresolved;
* пытаться ли reconnect;
* можно ли узнать итог;
* какой state показать UI.

Нельзя оставлять operation в вечном `cancelling`.

---

## 32. Failure model

Следует различать:

```text
transport failure
protocol failure
session failure
request failure
```

Они имеют разные recovery semantics.

---

## 33. Recoverable failure

Recoverable failure может привести к:

```text
reconnecting
retrying
session restoring
```

но не должен автоматически выглядеть как terminal error.

---

## 34. Terminal failure

Terminal failure означает, что automatic recovery завершилась или невозможна.

UI должен получить application-level reason, а не raw socket/process exception.

---

## 35. Retry policy

Retry/reconnect policy должна находиться вне widget.

Она должна определять:

* максимальное число попыток;
* delay/backoff;
* какие ошибки retryable;
* когда stop;
* как обрабатывается manual disconnect.

Если policy ещё не утверждена, не следует придумывать её в feature-коде.

---

## 36. Backoff

Если используется exponential backoff, он должен быть централизован и тестируем.

Не следует размножать:

```dart
Future.delayed(...)
```

по BLoC и widgets.

---

## 37. Manual retry

UI может выражать intent:

```text
RetryConnection
```

Но retry semantics принадлежат application/client layer.

---

## 38. Auto reconnect

Auto reconnect должен быть observable.

Presentation должна иметь возможность показать:

* lost connection;
* reconnecting;
* retry count, если требуется;
* final failure.

---

## 39. Reconnect ownership

Reconnect должен иметь одного owner.

Нельзя одновременно запускать reconnect из:

* transport;
* client core;
* BLoC;
* widget.

Иначе возможны duplicate connections.

---

## 40. Subscription lifecycle

Каждая subscription должна иметь owner.

Например:

```text
ACP transport subscription
    → acp_client_core

client event subscription
    → BLoC
```

Owner обязан cancel/dispose subscription.

---

## 41. Dispose

После dispose owner:

* новые events не должны менять его state;
* subscriptions должны быть закрыты;
* pending callbacks должны быть безопасны;
* stale async results должны игнорироваться.

---

## 42. Application close

При закрытии desktop application следует определить orderly shutdown:

```text
stop accepting intents
    ↓
cancel/close active session as required
    ↓
close ACP client
    ↓
close transport
    ↓
dispose DI/application resources
```

Не следует просто уничтожать Flutter tree и надеяться, что process/streams завершатся сами.

---

## 43. External agent process

Если agent запускается как child process, lifecycle process должен быть частью transport/infrastructure layer.

Следует определить:

* кто запускает process;
* кто владеет его lifetime;
* кто завершает;
* что делать при abnormal exit;
* что делать при app shutdown.

---

## 44. Process exit

Unexpected process exit должен преобразовываться:

```text
process exit
    ↓
transport failure
    ↓
connection/session transition
```

UI не должен напрямую подписываться на process exit.

---

## 45. State machine validation

Каждый transition должен иметь определённые source states.

Пример:

```text
sendPrompt
allowed:
  sessionReady

not allowed:
  disconnected
  connecting
  cancelling
```

Invalid transition должен быть:

* невозможен через API;
* либо возвращать typed error.

---

## 46. Transition table

Рекомендуется поддерживать transition table для сложных lifecycle.

Пример:

| Current state   | Event          | Next state       |
| --------------- | -------------- | ---------------- |
| disconnected    | connect        | connecting       |
| connecting      | connected      | connected        |
| connected       | createSession  | creatingSession  |
| creatingSession | sessionCreated | ready            |
| ready           | sendPrompt     | running          |
| running         | cancel         | cancelling       |
| running         | completed      | ready            |
| cancelling      | cancelled      | ready            |
| connected       | transportLost  | reconnecting     |
| reconnecting    | connected      | recovering/ready |
| reconnecting    | exhausted      | failed           |

Таблица должна соответствовать фактическому OpenSpec.

---

## 47. Presentation state

Presentation может преобразовывать lifecycle state в UI-specific state.

Например:

```text
application: reconnecting
presentation:
  showReconnectBanner = true
  disablePromptInput = true
```

Это допустимо как derived state.

Source of truth остаётся application lifecycle.

---

## 48. UI controls

Доступность действий должна выводиться из state.

Например:

```text
ready
  → send enabled

running
  → send disabled / cancel enabled

cancelling
  → cancel disabled

reconnecting
  → send disabled
```

Не следует хранить отдельный authoritative boolean `canSend`, если его можно derive из state.

---

## 49. Persisted session state

Persisted state и runtime state — разные concepts.

Например:

```text
saved conversation metadata
```

может существовать после:

```text
runtime session disconnected
```

Не следует сериализовать весь runtime state machine напрямую как persistence model без явного решения.

---

## 50. Restore after application restart

Если приложение поддерживает restore, нужно различать:

```text
restore local history
restore logical ACP session
reconnect agent
resume active request
```

Нельзя считать эти операции одинаковыми.

---

## 51. Active request after restart

Если ACP не гарантирует resume active request после restart, клиент не должен показывать его как всё ещё running без подтверждения.

Persisted UI state не должен подменять runtime truth.

---

## 52. Permission during reconnect

Если connection теряется во время pending permission request, application должна определить outcome.

Возможные варианты:

* permission request invalidated;
* restored after reconnect;
* request failed.

Нельзя автоматически применить старое решение к новому tool call.

---

## 53. Tool call lifecycle

Tool call может иметь отдельный lifecycle:

```text
requested
awaitingPermission
approved
denied
executing
completed
failed
cancelled
```

Он не обязан быть частью session state type.

Главное — correlation и ownership.

---

## 54. Unknown lifecycle event

Unknown или unexpected event не должен тихо ломать state machine.

Следует:

* логировать event;
* сохранить correlation context;
* игнорировать, если безопасно;
* либо переводить в failure, если protocol semantics нарушены.

---

## 55. Impossible state

State model должна делать невозможные состояния труднопредставимыми.

Например, лучше:

```text
SessionState.running(requestId)
```

чем:

```text
state = ready
activeRequestId = abc
```

если это противоречие.

---

## 56. Immutable state

Lifecycle state следует делать immutable.

Transition:

```text
old state
   +
event
   ↓
new state
```

предпочтительнее скрытой mutable state machine с множеством локальных flags.

---

## 57. Reducer/state machine

Сложный lifecycle желательно свести к одному transition mechanism.

Например:

```text
State + Event → State
```

Это упрощает:

* tests;
* race analysis;
* logging;
* replay;
* debugging.

---

## 58. Transition logging

Significant transitions следует логировать.

Например:

```text
session: ready → running
request_id: 42
```

или:

```text
connection: connected → reconnecting
reason: transport_lost
generation: 7
```

Sensitive payload для этого не нужен.

---

## 59. Testing

Минимальные lifecycle tests:

* connect success;
* connect failure;
* duplicate connect;
* session create success;
* session create failure;
* prompt start;
* streaming completion;
* cancellation;
* duplicate cancel;
* completion/cancel race;
* disconnect during running;
* reconnect success;
* reconnect exhausted;
* stale event;
* duplicate completion;
* dispose during async operation.

---

## 60. Deterministic tests

Lifecycle tests не должны зависеть от real delays, если можно использовать:

* fake clock;
* fake transport;
* controlled streams;
* explicit completers.

Retry/backoff следует тестировать детерминированно.

---

## 61. Property of stale events

Отдельно полезно тестировать invariant:

> Event от старой generation/request/session не изменяет current state.

Это один из ключевых invariants ACP client.

---

## 62. BLoC tests

BLoC tests должны проверять presentation mapping и intents, а не повторять всю ACP lifecycle state machine.

Core lifecycle следует тестировать в `acp_client_core`.

---

## 63. Integration tests

Integration tests должны покрывать end-to-end flows:

```text
connect
create session
send prompt
receive stream
complete
```

а также:

```text
connect
send prompt
disconnect
reconnect
recover
```

если recovery поддерживается.

---

## 64. Изменение lifecycle

Перед изменением lifecycle агент ОБЯЗАН определить:

1. Какой lifecycle изменяется: transport, connection, session, request или tool call.
2. Кто является owner.
3. Какие states добавляются/удаляются.
4. Какие transitions меняются.
5. Какие races появляются.
6. Как влияет reconnect.
7. Как влияет cancellation.
8. Как фильтруются stale events.
9. Как изменяется UI.
10. Какие tests должны быть добавлены.

---

## 65. Главный invariant

Lifecycle должен быть моделируем как последовательность явных transitions.

Желаемый принцип:

```text
event
  ↓
validated transition
  ↓
new state
```

Нежелательный:

```text
callback A → bool 1
callback B → bool 2
timer      → bool 3
widget     → bool 4
```

Если корректность session зависит от синхронизации множества независимых mutable flags, архитектуру следует пересмотреть.
