# State management в ACP Client

Этот документ определяет правила управления состоянием в ACP Client.

Основной state-management framework:

`flutter_bloc`

Цели документа:

* разделить application state и presentation state;
* определить ownership состояния;
* избежать дублирования source of truth;
* не переносить ACP protocol semantics напрямую в widgets;
* сделать lifecycle state явным;
* обеспечить тестируемость BLoC/Cubit;
* избежать избыточного использования глобального состояния.

Связанные документы:

* `AGENTS.md`
* `docs/architecture/layers-and-dependencies.md`
* `docs/architecture/acp-boundary.md`
* `docs/architecture/session-lifecycle.md`
* `docs/architecture/streaming.md`
* `docs/architecture/concurrency.md`
* `docs/architecture/permissions.md`
* `docs/architecture/testing.md`

---

## 1. Основной принцип

State должен находиться на том уровне, которому принадлежит его semantics.

Предпочтительная модель:

```text
Protocol state
    → acp_protocol / acp_client_core

Application state
    → acp_client_core / application layer

Presentation state
    → BLoC / Cubit

Ephemeral widget state
    → Widget
```

Не следует помещать всё состояние приложения в BLoC только потому, что проект использует `flutter_bloc`.

---

## 2. Один authoritative owner

Каждое значимое состояние должно иметь одного authoritative owner.

Например:

```text
connection/session lifecycle
    → acp_client_core

selected tab
    → presentation

hover state
    → widget
```

Несколько layers МОГУТ иметь derived representation одного state, но source of truth должен быть однозначным.

---

## 3. Application state

Application state описывает фактическое состояние системы.

Примеры:

* connection lifecycle;
* session lifecycle;
* active request;
* request completion;
* permission request;
* reconnect state;
* tool call lifecycle.

Application state не должен зависеть от того, как именно он отображается в Flutter.

---

## 4. Presentation state

Presentation state описывает состояние, необходимое UI.

Например:

```text
isPromptInputEnabled
showReconnectBanner
selectedConversationId
activePanel
permissionDialogState
```

Часть presentation state может быть derived из application state.

Например:

```text
SessionState.running
      │
      ▼
canSendPrompt = false
canCancel = true
```

---

## 5. Derived state

Не следует хранить отдельный authoritative field, если значение однозначно выводится из другого state.

Нежелательно:

```dart
class ChatState {
  final SessionState sessionState;
  final bool canSendPrompt;
  final bool canCancel;
}
```

если:

```text
canSendPrompt
canCancel
```

полностью определяются `sessionState`.

Лучше вычислять их как derived properties/selectors.

---

## 6. Ephemeral widget state

Локальный Widget state допустим для presentation-only concerns.

Примеры:

* hover;
* focus;
* animation;
* temporary expansion;
* local scroll interaction;
* drag state.

Для такого state не нужно автоматически создавать Cubit.

---

## 7. Что НЕ должно быть Widget state

Widget не должен быть authoritative owner для:

* ACP connection;
* session;
* request;
* tool call;
* permission;
* persistence status;
* reconnect;
* business/application data.

Rebuild или уничтожение Widget не должны уничтожать critical application state.

---

## 8. BLoC vs Cubit

Использовать существующие patterns проекта.

Общий guideline:

### Cubit

Подходит, когда transitions простые и API естественно выражается методами:

```text
selectTab()
togglePanel()
loadSettings()
```

### BLoC

Подходит, когда важны:

* explicit events;
* event ordering;
* concurrency semantics;
* сложная state machine;
* внешний event stream.

Не следует превращать любой простой state в BLoC только ради uniformity.

---

## 9. BLoC responsibility

BLoC/Cubit может:

* принимать user intents;
* подписываться на application events;
* преобразовывать application state в presentation state;
* управлять presentation workflow;
* инициировать application operations;
* управлять UI-specific lifecycle.

BLoC/Cubit НЕ ДОЛЖЕН:

* парсить raw ACP;
* реализовывать serialization;
* владеть concrete transport;
* выполнять filesystem implementation;
* реализовывать security policy;
* содержать reusable ACP lifecycle logic, если оно принадлежит `acp_client_core`.

---

## 10. BLoC не является service layer

Не следует использовать BLoC как место для всей бизнес-логики.

Нежелательно:

```text
SessionBloc
├── creates process
├── parses ACP
├── reconnects transport
├── writes files
├── evaluates permission
├── persists history
└── updates UI
```

Предпочтительно:

```text
SessionBloc
    │
    ▼
ACP client/application API
    │
    ├── transport
    ├── session lifecycle
    ├── permissions
    └── persistence
```

---

## 11. State immutability

BLoC/Cubit state должен быть immutable.

Для сложных state типов допустимо использовать Freezed.

Например:

```dart
@freezed
sealed class SessionViewState with _$SessionViewState {
  const factory SessionViewState.disconnected() = _Disconnected;
  const factory SessionViewState.connecting() = _Connecting;
  const factory SessionViewState.ready() = _Ready;
  const factory SessionViewState.running() = _Running;
}
```

Это пример подхода, а не требование использовать именно такие states.

---

## 12. Freezed

Freezed следует использовать, когда он даёт реальную пользу:

* union states;
* immutable models;
* equality;
* `copyWith`;
* exhaustive matching.

Не следует использовать Freezed для каждого простого класса автоматически.

---

## 13. Impossible states

State model должна минимизировать возможность представить невозможный state.

Нежелательно:

```dart
class SessionState {
  final bool connected;
  final bool reconnecting;
  final bool running;
  final bool cancelling;
}
```

Предпочтительно:

```text
Disconnected
Connecting
Ready
Running
Cancelling
Reconnecting
```

если эти states mutually exclusive.

---

## 14. Orthogonal state

Не всё нужно помещать в один union.

Например:

```text
Session lifecycle
+
selected UI tab
```

являются независимыми dimensions.

Не следует создавать combinatorial union:

```text
ReadyOnChatTab
ReadyOnSettingsTab
RunningOnChatTab
RunningOnSettingsTab
...
```

---

## 15. State decomposition

Большой state следует разделять, если части:

* имеют разный lifecycle;
* меняются независимо;
* имеют разных consumers;
* вызывают лишние rebuilds;
* принадлежат разным features.

Но дробление не должно приводить к десяткам Cubit без ясной ответственности.

---

## 16. Feature ownership

Предпочтительно, чтобы feature владела своим presentation state.

Например:

```text
features/chat/
    → ChatBloc

features/settings/
    → SettingsCubit
```

Global state допускается только для действительно application-wide concerns.

---

## 17. Global state

Кандидаты на application-wide state:

* active workspace;
* app-level session registry;
* theme/settings;
* authentication/configuration, если применимо;
* top-level connection status.

Не следует делать глобальным state только потому, что его используют два widgets.

---

## 18. Shared state

Если несколько features используют один authoritative state, следует определить semantic owner.

Возможные решения:

* application service;
* app-level BLoC;
* shared read-only projection;
* feature facade.

Не следует дублировать state в каждой feature.

---

## 19. Source of truth

Пример правильного ownership:

```text
AcpClientCore
    │
    └── authoritative SessionState
             │
             ▼
        SessionBloc
             │
             └── SessionViewState
```

BLoC может преобразовывать state, но не должен независимо воспроизводить полный lifecycle.

---

## 20. State synchronization

Если BLoC получает state из application layer, предпочтительно использовать event/state subscription.

Не следует периодически polling-ить объект только для синхронизации, если доступен stream/state API.

---

## 21. Initial state

Initial state должен быть определён явно.

Например:

```text
unknown
initializing
disconnected
```

следует выбирать исходя из реальной semantics.

Не следует показывать `disconnected`, если приложение ещё не завершило initialization и фактический status неизвестен.

---

## 22. Loading state

`loading` не должен быть универсальным состоянием для всех operations.

Следует различать:

```text
connecting
loading history
creating session
sending prompt
```

если UX или lifecycle semantics различаются.

---

## 23. Error state

Ошибка не всегда должна заменять весь state.

Например:

```text
session = ready
lastSendError = ...
```

может быть лучше, чем:

```text
SessionState.error
```

если session остаётся работоспособной.

---

## 24. Terminal vs recoverable error

Следует различать:

* operation error;
* recoverable session error;
* terminal session failure;
* presentation error.

Не использовать один общий:

```text
ErrorState(message)
```

для всех failure modes.

---

## 25. Typed failures

Presentation должна получать typed application failure или нормализованную presentation error model.

Не следует передавать raw exception прямо в Widget.

Нежелательно:

```dart
Text(exception.toString())
```

---

## 26. State transitions

Significant transitions должны происходить через один понятный mechanism.

Например:

```text
event
  ↓
BLoC handler
  ↓
emit(newState)
```

или через application state stream.

Не следует менять тот же state из нескольких независимых объектов без coordination.

---

## 27. Events

BLoC event должен описывать intent или значимое external event.

Хорошие примеры:

```text
ConnectRequested
PromptSubmitted
CancelRequested
SessionStateChanged
PermissionDecisionSubmitted
```

Плохие:

```text
ButtonClicked
BooleanChanged
DoThing
```

если event теряет смысл.

---

## 28. User intent vs application event

Следует различать:

```text
PromptSubmitted
    → user intent

PromptCompleted
    → application event
```

Они имеют разное происхождение и semantics.

---

## 29. BLoC event naming

Имена должны отражать уже произошедшее событие или intent.

Пример:

```text
ConnectRequested
ConnectionLost
ReconnectSucceeded
```

Это упрощает event logs и debugging.

---

## 30. Event concurrency

Для каждого event handler нужно понимать concurrency semantics.

Возможные варианты:

* sequential;
* concurrent;
* restartable;
* droppable.

Выбор должен соответствовать смыслу operation.

Подробнее:

`docs/architecture/concurrency.md`

---

## 31. Send prompt

`PromptSubmitted` обычно не должен быть `restartable`, если cancellation handler не отменяет реальный ACP request.

Новый event не должен локально "отменять" предыдущий request, оставляя его работающим у agent.

---

## 32. Connect

Repeated `ConnectRequested` может использовать single-flight/droppable semantics, если повторное подключение не имеет смысла.

Однако authoritative protection должна находиться и в application lifecycle.

---

## 33. Search/filter

Presentation-only search может использовать debounce/restartable semantics.

Это пример операции, где новый intent действительно заменяет предыдущий.

---

## 34. Subscription в BLoC

Если BLoC подписывается на application stream, subscription должна:

* иметь owner = BLoC;
* создаваться один раз;
* отменяться в `close()`;
* иметь error handling.

---

## 35. Subscription event mapping

Предпочтительно переводить external callback в BLoC event:

```text
client stream
    │
    ▼
SessionStateChanged event
    │
    ▼
BLoC handler
```

Это помогает сохранить один event-processing path.

---

## 36. Direct emit from callback

Direct `emit` из arbitrary callback может усложнить concurrency.

Если используется, lifecycle и serialization должны быть безопасными.

Для сложного BLoC предпочтительнее dispatch typed event.

---

## 37. BLoC close

После `close()`:

* subscriptions закрыты;
* timers остановлены;
* callbacks не должны dispatch events;
* late async operation не должна emit state.

---

## 38. DI и BLoC

BLoC должен получать dependencies через constructor/утверждённый Cherrypick composition.

Например:

```dart
class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc({
    required AcpClient client,
  }) : _client = client;
}
```

Не следует получать concrete infrastructure через global locator внутри handler.

---

## 39. BLoC creation

Создание BLoC должно происходить на правильном scope.

Например:

```text
application lifetime
feature lifetime
page lifetime
dialog lifetime
```

Scope должен соответствовать state lifecycle.

---

## 40. Scope mismatch

Не следует создавать page-scoped BLoC для state, который должен переживать navigation между страницами.

И наоборот, не следует создавать global singleton BLoC для временного dialog state.

---

## 41. Cherrypick scope

DI scope и BLoC lifecycle должны быть согласованы.

Если dependency session-scoped, она не должна случайно пережить session и использовать старые resources.

---

## 42. Presentation mapping

Application model можно преобразовывать в presentation model в:

* BLoC;
* dedicated mapper;
* view model factory.

Отдельный mapper нужен только если mapping достаточно сложный или reusable.

---

## 43. Не хранить widgets в state

BLoC state НЕ ДОЛЖЕН содержать:

* `Widget`;
* `BuildContext`;
* `NavigatorState`;
* dialog callbacks, тесно связанные с Widget tree.

State должен быть data-oriented.

---

## 44. Callbacks в state

Function callbacks в state следует использовать осторожно.

Для application state они обычно неуместны.

Presentation model может содержать callback только как чисто UI composition detail, но лучше actions связывать на уровне Widget.

---

## 45. Navigation

Navigation является presentation concern.

BLoC не должен зависеть от `BuildContext`.

Возможные patterns:

* UI reacts to state;
* one-shot presentation effect;
* router abstraction на presentation boundary.

---

## 46. One-shot effects

Некоторые UI actions не являются долговременным state:

* show notification;
* open dialog;
* navigate;
* copy confirmation.

Не следует моделировать их как boolean:

```text
showDialog = true
```

который остаётся в state и может повторно сработать после rebuild.

---

## 47. Effects

Если проект использует отдельный effect mechanism, его следует применять последовательно.

Conceptually:

```text
State
    → durable UI representation

Effect
    → one-time UI action
```

Не следует вводить новый effect framework без необходимости.

---

## 48. Dialog state

Permission dialog отличается от обычного ephemeral effect, потому что permission request имеет application lifecycle.

Authoritative request должен оставаться stateful:

```text
PermissionRequest.pending
```

а конкретный способ отображения может быть dialog/panel.

---

## 49. State persistence

Не каждый BLoC state должен persist.

Persist следует делать только для state, который имеет смысл после restart.

Например:

```text
user settings
workspace preferences
conversation history
```

Runtime states вроде:

```text
connecting
cancelling
hovered
```

обычно не должны сохраняться напрямую.

---

## 50. Persistence model ≠ BLoC state

Не следует сериализовать BLoC state целиком как storage model без осознанного решения.

Persistence model должна иметь собственную stable semantics.

---

## 51. Restoration

После restart persisted state должен пройти application-level restore/reconciliation.

Например saved:

```text
last known session
```

не означает:

```text
session currently connected
```

---

## 52. Streaming state

Streaming aggregation должна находиться в application/client layer, если она описывает ACP semantics.

BLoC может хранить presentation projection.

Например:

```text
application:
MessageStreamingState

presentation:
ChatMessageViewState
```

---

## 53. High-frequency updates

При frequent streaming updates следует уменьшать unnecessary rebuilds.

Использовать:

* `BlocSelector`;
* `buildWhen`;
* granular Widgets;
* derived projections.

Не следует решать performance problem переносом authoritative state обратно в Widget.

---

## 54. Equality

State equality должна быть корректной.

Freezed помогает обеспечить value equality.

Некорректная equality может приводить к:

* пропущенным rebuilds;
* лишним rebuilds;
* странным test failures.

---

## 55. Large collections

Большие immutable collections могут быть дорогими при частых copies.

Если streaming performance становится проблемой, следует оптимизировать representation осознанно.

Корректность важнее premature optimization.

---

## 56. Normalized state

Для сложной UI модели полезно хранить normalized state:

```text
messagesById
messageOrder
toolCallsById
```

вместо вложенных mutable structures.

Это особенно полезно при incremental updates.

---

## 57. Entity identity

List items, messages и tool calls должны иметь stable identity.

UI не должен полагаться только на list index для state correlation.

---

## 58. State revision

Для сложных derived/cached state может быть полезна revision.

Например:

```text
conversationRevision
```

Но revision не следует вводить без реальной необходимости.

---

## 59. Stale application updates

BLoC должен игнорировать update, если application layer уже пометил его stale или он относится к другому scoped session.

Presentation не должна повторно реализовывать весь stale filtering.

---

## 60. Session switching

При переключении между sessions необходимо определить:

* какой BLoC владеет selection;
* какие subscriptions переключаются;
* очищается ли old presentation state;
* как исключаются late events старой session.

---

## 61. Per-session state

Если несколько sessions могут быть активны одновременно, не следует использовать один flat `currentSessionState`, если UI должен сохранять state каждой session.

Возможна модель:

```text
sessionsById
activeSessionId
```

если это соответствует product architecture.

---

## 62. Single-session application

Если продукт сознательно поддерживает только одну active session, это должно быть application invariant, а не случайное ограничение BLoC.

---

## 63. Settings state

Settings чаще всего принадлежат отдельной feature.

Следует различать:

* saved settings;
* editing form state;
* effective runtime configuration.

Они не обязаны быть одним типом.

---

## 64. Form state

Temporary form input может находиться:

* локально в Widget;
* в Cubit, если form сложная;
* в dedicated form model.

Не следует отправлять каждое изменение текстового поля в global application BLoC без причины.

---

## 65. Validation

UI validation и application validation различаются.

Presentation validation:

```text
field empty
invalid local format
```

Application validation:

```text
operation forbidden in current session
unsupported capability
```

Security/application constraints не должны существовать только в form validation.

---

## 66. Loading collections

Для collection state полезно различать:

```text
initial loading
refreshing
loaded empty
loaded data
failed
```

если UX различается.

Один `isLoading` может быть недостаточен.

---

## 67. Optimistic updates

Optimistic state допустим, если существует reconciliation.

Например:

```text
prompt appears immediately
    ↓
request accepted/rejected
    ↓
confirm/rollback
```

Optimistic state должен быть distinguishable от confirmed state, если это влияет на correctness.

---

## 68. Rollback

Если optimistic operation failed, rollback должен быть deterministic.

Не следует просто оставлять UI в состоянии, которого server/agent не подтверждал.

---

## 69. Error presentation

User-visible message не должен быть единственной формой error state.

Желательно сохранить typed reason для:

* retry;
* diagnostics;
* UI decisions.

---

## 70. State logging

Significant state transitions следует логировать на application boundary.

Не нужно логировать каждый hover/local UI change.

Полезно логировать:

```text
SessionState.ready → SessionState.running
RequestState.streaming → completed
```

---

## 71. Debug BLoC logging

Если используется BLoC observer, он должен:

* маскировать sensitive data;
* не dump-ить большие ACP payload;
* не быть единственным источником lifecycle diagnostics.

---

## 72. Testing BLoC

BLoC tests должны проверять:

* input intent;
* application interaction;
* resulting presentation states;
* error mapping;
* lifecycle cleanup.

Не следует через BLoC tests заново тестировать protocol parser или transport.

---

## 73. Cubit tests

Cubit tests должны быть небольшими и focused.

Если для тестирования Cubit требуется поднять весь ACP stack, dependency boundary, вероятно, слишком тесная.

---

## 74. Fake application dependencies

В BLoC tests следует использовать fake/mocked application-facing dependencies.

Например:

```text
FakeAcpClient
FakeSessionController
```

а не real process transport.

---

## 75. Widget tests

Widget tests должны проверять:

* rendering state;
* controls enabled/disabled;
* intents отправляются;
* correct derived UI;
* permission UI behavior.

Application lifecycle тестируется ниже.

---

## 76. Integration tests

Integration tests покрывают связку:

```text
UI
  ↓
BLoC
  ↓
application
  ↓
ACP fake/test agent
```

для критических end-to-end сценариев.

---

## 77. Нежелательные patterns

### Raw ACP в state

```dart
class ChatState {
  final Map<String, dynamic> lastAcpMessage;
}
```

если это application UI state.

---

### Boolean soup

```dart
isLoading
isConnected
isRunning
hasError
isCancelling
```

без ясной state model.

---

### Global mega-BLoC

```text
AppBloc
├── sessions
├── settings
├── routing
├── permissions
├── files
├── ACP transport
└── entire UI
```

считается architectural smell.

---

### BLoC как service locator

```dart
final transport = container.resolve<StdioTransport>();
```

в event handler.

---

### Side effect в getter

State getter не должен выполнять I/O или изменять state.

---

### State containing `BuildContext`

Запрещено.

---

## 78. Когда создавать новый BLoC/Cubit

Перед созданием необходимо ответить:

1. Какой state он владеет?
2. Какой у него lifecycle?
3. Кто consumers?
4. Почему Widget-local state недостаточно?
5. Почему существующий BLoC не является owner?
6. Является ли state presentation или application state?
7. Какие dependencies ему нужны?
8. Какие tests будут написаны?

Если нет чёткой responsibility, новый BLoC/Cubit создавать не следует.

---

## 79. Когда НЕ создавать BLoC

Не нужен отдельный BLoC для:

* hover;
* simple toggle внутри одного Widget;
* animation controller;
* локального selected index, который нигде больше не нужен;
* immutable static presentation.

Использовать минимально необходимый mechanism.

---

## 80. Когда переносить логику из BLoC в `acp_client_core`

Следует рассмотреть перенос, если логика:

* не зависит от Flutter;
* описывает ACP lifecycle;
* нужна нескольким BLoC/features;
* содержит session/request state machine;
* содержит reconnect/cancellation semantics;
* должна тестироваться независимо от presentation.

---

## 81. Когда оставить логику в BLoC

Логику можно оставить в BLoC, если она:

* исключительно presentation-oriented;
* связывает user intents с application API;
* преобразует application state в UI state;
* управляет presentation-only interaction.

---

## 82. Главные invariants

### STATE-001 — Один source of truth

Authoritative state не дублируется между layers.

### STATE-002 — BLoC не владеет protocol semantics

Raw ACP и transport logic находятся ниже presentation.

### STATE-003 — State immutable

Significant state transitions происходят через новые immutable values.

### STATE-004 — Impossible states минимизированы

Используются explicit state types вместо неограниченного набора flags.

### STATE-005 — Widget state только ephemeral

Application lifecycle не хранится в Widget.

### STATE-006 — Derived state не дублируется без необходимости

`canSend`, `canCancel` и подобные значения выводятся из authoritative state, когда возможно.

### STATE-007 — State lifecycle соответствует DI/UI scope

Global state не создаётся для local concern, local state не используется для application-wide lifecycle.

---

## 83. Основная модель

Предпочтительная архитектура:

```text
            ACP / Infrastructure
                    │
                    ▼
             acp_client_core
                    │
          authoritative state
                    │
                    ▼
               BLoC/Cubit
                    │
           presentation state
                    │
                    ▼
                Widgets
```

User intent движется в обратном направлении:

```text
Widget
   │
   ▼
BLoC/Cubit
   │
   ▼
Application API
   │
   ▼
ACP client / infrastructure
```

Если Widget начинает владеть ACP lifecycle, BLoC реализует transport, а `acp_client_core` зависит от Flutter state types, boundaries следует пересмотреть.
