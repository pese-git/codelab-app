# Concurrency и async lifecycle в ACP Client

Этот документ определяет правила конкурентного и асинхронного поведения в ACP Client.

Цели:

* избежать race conditions;
* исключить stale async results;
* корректно управлять subscriptions;
* сделать cancellation предсказуемой;
* не блокировать Flutter UI isolate;
* обеспечить явное ownership long-lived операций;
* сохранить тестируемость ACP client logic.

Связанные документы:

* `AGENTS.md`
* `docs/architecture/acp-boundary.md`
* `docs/architecture/session-lifecycle.md`
* `docs/architecture/streaming.md`
* `docs/architecture/testing.md`

---

## 1. Основной принцип

Любая async operation должна иметь понятный lifecycle.

Для каждой операции необходимо знать:

* кто её запустил;
* кто является owner;
* может ли она пережить owner;
* можно ли её отменить;
* что происходит при dispose;
* что происходит при reconnect;
* как обрабатываются late results;
* какие ошибки она может завершить.

Не следует запускать async работу без ответа на эти вопросы.

---

## 2. UI isolate

Flutter UI isolate НЕ ДОЛЖЕН блокироваться длительными synchronous operations.

На UI isolate допустимы:

* короткие state transitions;
* presentation mapping;
* создание widgets;
* лёгкие immutable transformations;
* небольшие synchronous calculations.

Следует избегать:

* больших циклов;
* тяжёлого parsing;
* длительного filesystem I/O;
* process waiting;
* CPU-heavy transformations.

---

## 3. Async I/O

Операции с:

* ACP transport;
* filesystem;
* network;
* process;
* secure storage;

должны выполняться асинхронно, если API это поддерживает.

Нельзя использовать blocking API только ради простоты реализации, если оно может заморозить UI.

---

## 4. CPU-heavy операции

CPU-heavy работу следует выносить из UI isolate, если она способна заметно влиять на rendering responsiveness.

Возможные подходы:

* isolate;
* `compute`;
* специализированный worker abstraction.

Не следует вводить isolate для любой небольшой операции.

---

## 5. Ownership

Каждая long-lived operation должна иметь одного owner.

Например:

```text id="ms8kqw"
ACP transport connection
    → acp_client_core

transport subscription
    → acp_client_core

client event subscription
    → SessionBloc

temporary widget animation
    → Widget
```

Если owner не определён, lifecycle операции почти наверняка станет проблемой.

---

## 6. Subscription ownership

Каждый `StreamSubscription` должен быть:

* сохранён;
* привязан к owner;
* отменён при завершении owner;
* защищён от повторного создания без cleanup.

Нежелательно:

```dart id="x4i54m"
client.events.listen(onEvent);
```

без сохранения результата `listen`.

Предпочтительно:

```dart id="mekdjt"
_subscription = client.events.listen(onEvent);
```

с явным `cancel()`.

---

## 7. Duplicate subscriptions

Reconnect, rebuild или повторная инициализация не должны создавать duplicate subscriptions.

Перед созданием новой subscription необходимо:

* либо гарантировать, что старой нет;
* либо явно отменить старую;
* либо использовать abstraction, которая сама управляет единственной подпиской.

---

## 8. Widget lifecycle

Widget НЕ ДОЛЖЕН владеть critical ACP lifecycle, если этот lifecycle должен переживать rebuild.

Rebuild widget не должен:

* переподключать transport;
* пересоздавать ACP client;
* повторно отправлять request;
* создавать duplicate subscriptions.

Long-lived state должен принадлежать BLoC/application/client layer.

---

## 9. BLoC lifecycle

BLoC/Cubit может владеть presentation-level subscriptions.

При `close()` он должен:

* отменить subscriptions;
* остановить presentation timers;
* перестать принимать external callbacks;
* безопасно игнорировать late results.

BLoC не должен владеть reusable low-level ACP transport lifecycle, если тот относится к `acp_client_core`.

---

## 10. Stale async result

Типичный race:

```text id="3wz0mt"
load A started
load B started
load B completed
load A completed late
```

Late result A не должен перезаписать актуальный state B.

Нужно использовать:

* request token;
* generation;
* revision;
* cancellation;
* sequence;
* ownership check.

---

## 11. Operation token

Для операций, которые могут перекрываться, полезно использовать local operation token.

Например:

```text id="rn8dwc"
search generation 10
search generation 11
```

Результат generation 10 не применяется после начала generation 11.

---

## 12. Connection generation

Connection generation является частным случаем operation token.

Каждый новый connection instance получает generation.

Callback должен проверять, принадлежит ли он актуальной generation.

---

## 13. Request correlation

Async result request должен быть связан минимум с:

* request id;
* session id;
* connection generation,

если эти concepts применимы.

Не следует применять result только потому, что callback "пришёл последним".

---

## 14. Mutable shared state

Следует минимизировать mutable state, к которому обращаются несколько async handlers.

Плохо:

```dart id="2j3pqi"
final messages = <Message>[];

stream.listen((event) async {
  messages.add(...);
  await something();
  messages.add(...);
});
```

если несколько handlers способны interleave.

Предпочтительнее immutable state transitions через одного owner.

---

## 15. Sequential event processing

Events одного logical state machine обычно следует обрабатывать последовательно.

Conceptual model:

```text id="y4dr9d"
event A
   ↓
reduce
   ↓
event B
   ↓
reduce
```

вместо:

```text id="zgp1uf"
event A ── async mutate ─┐
                         ├─ shared state
event B ── async mutate ─┘
```

---

## 16. Event queue

Для complex client lifecycle допустимо иметь internal serialized event queue.

Она полезна, когда:

* несколько transport callbacks меняют один state;
* completion/cancel могут прийти одновременно;
* reconnect меняет active subscriptions;
* tool calls выполняются параллельно.

Queue не должна быть скрытым global event bus.

---

## 17. Side effects после transition

Предпочтительный pattern:

```text id="g216oh"
event
  ↓
validate
  ↓
state transition
  ↓
side effect
  ↓
result event
```

Например:

```text id="gt7c0l"
ConnectionLost
    ↓
state = reconnecting
    ↓
attemptReconnect()
    ↓
ReconnectSucceeded
```

Это проще тестировать, чем side effect внутри state mutation.

---

## 18. Async side effect

Async side effect не должен мутировать authoritative state напрямую после `await` без проверки актуальности context.

Пример:

```dart id="sc77eq"
final generation = _generation;

final result = await reconnect();

if (generation != _generation) {
  return;
}

apply(result);
```

Конкретная реализация может отличаться.

---

## 19. Cancellation как first-class concept

Cancellation не должна означать только:

```text id="vx1cgu"
ignore result
```

если underlying operation можно реально остановить.

Следует различать:

* cancel underlying operation;
* mark local result stale;
* detach consumer;
* terminate transport/request.

---

## 20. Cancellation ownership

Отменять operation должен её owner или компонент, которому owner явно делегировал cancellation.

Widget выражает intent:

```text id="bbtq95"
Cancel
```

Application/client layer выполняет actual cancellation semantics.

---

## 21. Cooperative cancellation

Если API не поддерживает hard cancellation, следует использовать cooperative cancellation.

Например:

```text id="ezr23o"
operation token
cancellation flag
generation check
```

Однако cancellation flag не должен быть глобальным mutable boolean для нескольких operations.

---

## 22. Cancellation token

Для generic long-lived operations можно использовать cancellation abstraction.

Conceptually:

```dart id="c2bdlh"
abstract interface class CancellationToken {
  bool get isCancelled;
}
```

Не требуется создавать такую abstraction, если существующий API уже решает задачу.

---

## 23. Cancel after completion

Если operation уже terminal, повторный cancel должен быть безопасным.

Возможные outcomes:

* ignore;
* return completed result;
* typed already-completed error.

Он не должен возвращать operation в active state.

---

## 24. Completion/cancel race

Race:

```text id="52ce6q"
completion
     ↘
      state
     ↗
cancel
```

должен иметь deterministic rule.

Решение принадлежит lifecycle/state machine, а не callback order "как получилось".

---

## 25. Timeouts

Timeout является application policy, если он определяет пользовательское поведение.

Transport-level timeout может существовать отдельно.

Следует различать:

```text id="4q27l0"
socket/connect timeout
request timeout
user-visible operation timeout
```

Они не обязаны иметь одинаковые значения или semantics.

---

## 26. Timeout ownership

Timeout должен иметь owner.

Не следует создавать независимые timers в нескольких слоях для одной операции.

Например одновременно:

```text id="j2sg2p"
transport timeout
BLoC timeout
widget timeout
```

без понятного отношения между ними.

---

## 27. Timer lifecycle

Каждый `Timer` должен:

* иметь owner;
* быть cancelled;
* не вызывать callback после dispose owner;
* не создавать duplicate retry.

---

## 28. Retry concurrency

Retry implementation должен гарантировать, что одновременно выполняется не больше допустимого числа retry attempts.

Для обычного reconnect чаще всего это один attempt.

Нежелательно:

```text id="h8yb8y"
timer retry
user retry
transport retry
```

запускающие три connection attempts.

---

## 29. Reconnect mutex

Если reconnect может быть инициирован из нескольких intents/events, нужен механизм single-flight.

Conceptually:

```text id="epuw0h"
reconnect requested
       │
       ▼
existing reconnect?
   yes ───► reuse/wait
   no  ───► start
```

Конкретная implementation может быть Future caching, state machine или queue.

---

## 30. Single-flight operation

Single-flight полезен для операций:

* connect;
* reconnect;
* initialize;
* refresh configuration;

когда duplicate invocation не имеет смысла.

---

## 31. Parallelism

Параллелизм должен быть осознанным.

Если две operations независимы:

```text id="a9zwu4"
load settings
load session history
```

их можно выполнять параллельно.

Если они меняют один lifecycle state, лучше serialized processing.

---

## 32. Concurrent tool calls

Если ACP допускает concurrent tool calls, каждый должен иметь independent:

* id;
* state;
* permission flow;
* cancellation;
* completion.

Нельзя использовать один global:

```text id="zxnc47"
currentToolCall
```

если protocol допускает несколько.

---

## 33. Permission concurrency

Несколько pending permission requests должны быть либо поддержаны явно, либо запрещены application invariant.

Если поддержаны:

```text id="a4w3be"
permission A
permission B
```

decision A не должен завершить B.

---

## 34. UI concurrency

Несколько user intents могут приходить почти одновременно.

Например:

```text id="9tks3r"
double click Connect
double click Send
Cancel + Disconnect
```

Application API должна быть устойчива к повторным intents.

---

## 35. Debounce

Debounce является presentation/application policy для частых не-критичных intents.

Подходит для:

* search input;
* autosave;
* UI filtering.

Не следует debounce critical protocol events.

---

## 36. Throttle

Throttle допустим для:

* UI progress;
* frequent rendering updates;
* telemetry.

Не применять throttle к:

* completion;
* permission request;
* cancellation acknowledgement;
* connection loss.

---

## 37. Fire-and-forget

`unawaited(...)` допустим только если операция действительно не должна блокировать caller.

Перед использованием необходимо определить:

* кто обрабатывает ошибку;
* кто владеет lifecycle;
* что происходит при shutdown;
* важен ли result.

---

## 38. Ошибки fire-and-forget

Неправильно:

```dart id="nwiqdw"
unawaited(saveState());
```

если exception потеряется.

Нужно либо:

```text id="g1qfwk"
handled async wrapper
```

либо иной явный error path.

---

## 39. Async errors

Ошибки `Future` и `Stream` не должны исчезать в unhandled zone.

Все long-lived async boundaries должны иметь error handling.

Особенно:

* transport streams;
* process output;
* reconnect loops;
* persistence background tasks.

---

## 40. Stream error handling

`Stream.listen` должен явно определять, что происходит при:

* `onError`;
* `onDone`.

Critical stream не должен тихо завершаться.

---

## 41. Isolate boundary

Если используется isolate, сообщения между isolates должны быть:

* immutable/serializable;
* минимальными;
* независимыми от Flutter UI objects.

Не передавать:

* `BuildContext`;
* widgets;
* BLoC instances;
* DI container.

---

## 42. Process I/O

ACP через child process может иметь независимые stdout/stderr streams.

Следует определить:

```text id="ua527y"
stdout
    → protocol transport

stderr
    → diagnostics/logging
```

если именно это соответствует transport implementation.

Нельзя смешивать stderr diagnostics с ACP messages без framing contract.

---

## 43. Process shutdown race

При shutdown возможен race:

```text id="llz09q"
close transport
terminate process
process exits
onDone fires
```

State machine должна воспринимать expected exit как intentional shutdown, а не unexpected reconnect trigger.

---

## 44. Terminal process lifecycle (`terminal/*`)

`terminal/create` управляет отдельным session-scoped реестром процессов
(`SessionId → Map<TerminalId, TerminalProcessHandle>`), независимым от
собственного child-процесса ACP transport (§42-43) и от
`TerminalProcessFactory` локальной интерактивной terminal-панели
(`add-integrated-terminal`) — два разных owner'а, два разных lifecycle
(`add-acp-terminal-client-support/design.md`, Decision 6).

Правила:

* `TerminalId` — owner: сессия, в рамках которой он был создан
  (`terminal/create`'s `sessionId`), а не connection в целом.
* `kill` (`terminal/kill`) переводит процесс в terminal state (`exited`),
  но НЕ удаляет `TerminalId` из реестра — `output`/`wait_for_exit`/
  `release` остаются валидными после него.
* `release` (`terminal/release`) убивает процесс, если он ещё работает, И
  удаляет `TerminalId` из реестра — с этого момента id неотличим от
  никогда не существовавшего (единая "unknown terminal" ошибка для обоих
  случаев).
* И `kill`, и connection-level teardown ДОЛЖНЫ быть идемпотентны
  относительно уже завершившегося процесса — race между естественным
  exit и `kill` не должен менять уже зафиксированный exit-статус
  (см. §24 Completion/cancel race).
* При переходе connection в disconnected/failed или при dispose
  приложения ВСЕ активные terminal-процессы всех сессий убиваются
  (`kill`-семантика, не `release`) — это connection-level safety net, а
  не graceful `terminal/release` от имени агента; реестр при этом
  очищается полностью (§57 State after dispose).
* Буферизация output (`outputByteLimit`, truncation с начала буфера по
  границе UTF-8 символа) — ответственность infrastructure adapter, не
  application layer, аналогично разделению для ACP transport's
  stdout/stderr (§42).

Полное обоснование: `openspec/changes/add-acp-terminal-client-support/design.md`.

---

## 45. App shutdown

При закрытии приложения новые user/application intents должны перестать приниматься до destruction resources.

Рекомендуемый conceptual flow:

```text id="t7qedd"
shuttingDown = begin
      │
      ▼
stop new operations
      │
      ▼
cancel/complete active work
      │
      ▼
close client/subscriptions
      │
      ▼
close transport/process
      │
      ▼
dispose containers
```

---

## 46. Shutdown timeout

Если external process не завершается, application может иметь bounded shutdown timeout.

После timeout возможен force termination, если это соответствует policy.

Такой behavior должен быть централизован.

---

## 47. Persistence concurrency

Concurrent writes должны иметь определённую strategy.

Например:

* serialized writes;
* last-write-wins;
* transaction;
* revision check.

Не следует позволять старой async write завершиться после новой и перезаписать актуальные данные.

---

## 48. Revision guard

Для persistence useful pattern:

```text id="4ubnlw"
state revision 10 → save started
state revision 11 → save started
revision 11 saved
revision 10 completes late
```

Late revision 10 не должна становиться authoritative.

---

## 49. Autosave

Autosave следует проектировать как отдельный lifecycle.

Возможны:

* debounce;
* queued save;
* coalescing;
* explicit flush on shutdown.

Не следует запускать uncontrolled write на каждый streaming event.

---

## 50. Immutable snapshots

Перед передачей state в async operation следует предпочитать immutable snapshot.

Это уменьшает вероятность, что operation увидит half-mutated shared state.

---

## 51. Locks и mutex

Locks следует использовать только при реальной shared mutable concurrency.

В Dart isolate model часто достаточно:

* serialized event queue;
* state machine;
* single-flight Future;
* ownership.

Не следует вводить mutex abstraction автоматически.

---

## 52. Deadlocks

Если появляются locks, необходимо документировать lock ordering.

Лучше избегать нескольких nested locks.

В большинстве application-level Dart code architecture через ownership предпочтительнее lock-based design.

---

## 53. Reentrancy

Event handler не должен случайно re-enter state transition до завершения текущего transition.

Например:

```text id="nuzvff"
handle event
  → emits callback
      → callback sends new event synchronously
```

State machine должна быть устойчива к такому behavior либо сериализовать events.

---

## 54. Completer

`Completer` полезен для bridge callback/event API к `Future`.

Но его необходимо завершать максимум один раз.

Перед:

```dart id="2mnl8k"
completer.complete(...)
```

state machine должна гарантировать, что duplicate completion/cancel не вызовет second completion.

---

## 55. Cached Future

Для single-flight operation допустимо хранить current Future:

```text id="d1s27o"
_connectFuture
```

После terminal completion его нужно корректно сбросить.

Иначе новая legitimate operation может навсегда получать старый Future.

---

## 56. Backoff loop

Reconnect loop должен проверять актуальность intent после каждого `await`.

Например:

```text id="ruqwzu"
wait backoff
    ↓
still reconnecting?
    ↓
attempt
```

Если user уже нажал Disconnect, старый loop не должен снова подключиться.

---

## 57. Manual override

Manual user intent может инвалидировать background operation.

Например:

```text id="zfsway"
auto reconnect running
user selects Disconnect
```

Disconnect должен отменить/инвалидировать reconnect loop.

---

## 58. State after dispose

После dispose объект не должен:

* emit new BLoC state;
* обращаться к closed controller;
* вызывать UI callback;
* запускать reconnect;
* продолжать persistence loop.

Late callbacks должны иметь guard.

---

## 59. Mounted checks

`context.mounted` полезен только на Flutter presentation boundary.

Он НЕ является заменой нормального application cancellation/stale-result handling.

Нельзя решать lifecycle core logic через `context.mounted`.

---

## 60. BLoC event transformers

Если используются BLoC event transformers, их semantics должны соответствовать operation.

Например:

* sequential;
* droppable;
* restartable;
* concurrent.

Не следует выбирать transformer только ради performance.

Он определяет concurrency semantics feature.

---

## 61. Restartable semantics

Restartable подходит для операций, где новый intent полностью заменяет старый.

Например:

```text id="nwwbhv"
search query changed
```

Но опасен для:

```text id="8n8zlf"
send ACP prompt
```

если отмена предыдущего handler не означает реальную cancellation ACP request.

---

## 62. Droppable semantics

Droppable может подходить для duplicate UI intents:

```text id="8fa9tf"
Connect button pressed repeatedly
```

если current operation уже выполняется.

Не использовать droppable там, где каждое event имеет business meaning.

---

## 63. Sequential semantics

Sequential processing хорошо подходит для events, мутирующих один state machine.

Но длинный async handler может блокировать последующие critical events.

Поэтому side effects лучше превращать в отдельные result events.

---

## 64. Concurrent semantics

Concurrent handler допустим только если operations действительно независимы или имеют безопасную correlation model.

Не использовать concurrent transformer для одного mutable session state без анализа races.

---

## 65. Error recovery

После async failure state должен оказаться в defined состоянии.

Нельзя оставить:

```text id="e7oeac"
isLoading = true forever
```

или request в бесконечном `cancelling`.

Любая операция должна иметь terminal/recoverable transition.

---

## 66. Diagnostics

Для complex concurrency issues полезно логировать:

* operation id;
* request id;
* session id;
* generation;
* lifecycle state;
* transition;
* cancellation;
* stale result ignored.

Например:

```text id="alfj52"
request=42 generation=8 result=ignored reason=stale_generation
```

---

## 67. Не логировать task identity через object hash

Не следует использовать runtime object hash как единственный correlation identifier.

Использовать explicit IDs/generations.

---

## 68. Deterministic testing

Concurrency tests должны по возможности избегать реального времени.

Использовать:

* `Completer`;
* fake transport;
* controlled streams;
* fake clock;
* explicit event ordering.

Тест:

```text id="qq1tta"
sleep 500 ms and hope
```

хуже, чем deterministic coordination.

---

## 69. Race tests

Обязательные категории:

* completion vs cancel;
* disconnect vs completion;
* reconnect vs manual disconnect;
* old connection callback vs new connection;
* old request result vs new request;
* dispose vs callback;
* duplicate connect;
* duplicate cancel;
* concurrent permission requests.

---

## 70. Forced ordering tests

Полезно вручную управлять последовательностью:

```text id="4ffprm"
start operation A
start operation B
complete B
complete A
```

и проверять, что final state корректен.

---

## 71. Stress tests

Для сложных lifecycle полезно периодически запускать stress scenarios с разным ordering events.

Однако deterministic unit tests остаются основой correctness.

---

## 72. Нежелательные patterns

### Async callback без lifecycle

```dart id="ev84h3"
Future.delayed(duration, () {
  emit(...);
});
```

без cancellation/owner checks.

---

### Несколько reconnect loops

```text id="acywvz"
transport reconnect
client reconnect
BLoC reconnect
```

одновременно.

---

### Mutable global flag

```dart id="n8szxk"
bool cancelled = false;
```

для unrelated operations.

---

### `context.mounted` как business cancellation

```dart id="3dyspm"
if (!context.mounted) return;
```

не решает stale ACP request.

---

### Fire-and-forget без error handling

```dart id="6jjoh6"
unawaited(connect());
```

если failure должен менять state.

---

### Arbitrary delays

```dart id="0xet4u"
await Future.delayed(const Duration(milliseconds: 500));
```

для "синхронизации" race.

---

## 73. Checklist перед async реализацией

Перед добавлением нетривиальной async operation агент ОБЯЗАН определить:

1. Кто owner?
2. Какой у операции identifier?
3. Может ли операция перекрываться с другой?
4. Может ли результат прийти stale?
5. Есть ли cancellation?
6. Что происходит при dispose?
7. Что происходит при disconnect?
8. Что происходит при reconnect?
9. Нужен ли timeout?
10. Кто обрабатывает exception?
11. Нужен ли single-flight?
12. Может ли operation блокировать UI isolate?
13. Какие race tests нужны?

---

## 74. Главные invariants

### CON-001 — Long-lived operation имеет owner

Нет orphan tasks/subscriptions.

### CON-002 — Stale result не меняет current state

Все потенциально late operations имеют correlation/generation guard.

### CON-003 — Critical state mutation сериализована

Один logical state machine не мутируется несколькими независимыми async callbacks без coordination.

### CON-004 — Cancellation явная

Cancel intent имеет определённую semantics.

### CON-005 — Dispose terminal

После dispose owner не продолжает производить state changes.

### CON-006 — Reconnect single-owner

В системе существует один authoritative reconnect mechanism.

### CON-007 — UI isolate не блокируется

Heavy work выносится за пределы rendering-critical execution.

---

## 75. Основная модель

Предпочтительная mental model:

```text id="p8fem9"
intent/event
     │
     ▼
validate current generation/state
     │
     ▼
state transition
     │
     ▼
start side effect
     │
     ▼
async result
     │
     ▼
validate ownership/generation again
     │
     ▼
result event
     │
     ▼
next state
```

Если async correctness зависит от того, какой callback случайно завершится последним, необходимо добавить явную lifecycle/correlation model.
