# Error handling в ACP Client

Этот документ определяет архитектуру обработки ошибок в ACP Client.

Цели:

* разделить ошибки разных архитектурных уровней;
* не допускать утечки implementation-specific exceptions в UI;
* обеспечить типизированную обработку ожидаемых failures;
* явно определить retryability и recovery semantics;
* сохранить диагностический context;
* обеспечить безопасное отображение ошибок пользователю;
* сделать error handling предсказуемым и тестируемым.

Связанные документы:

* `AGENTS.md`
* `docs/architecture/layers-and-dependencies.md`
* `docs/architecture/acp-boundary.md`
* `docs/architecture/session-lifecycle.md`
* `docs/architecture/streaming.md`
* `docs/architecture/concurrency.md`
* `docs/architecture/permissions.md`
* `docs/architecture/state-management.md`
* `docs/architecture/observability.md`
* `docs/architecture/testing.md`

---

## 1. Основной принцип

Ошибка должна представляться на том уровне, semantics которого она описывает.

Типичный flow:

```text id="l22vsl"
External / runtime exception
        │
        ▼
Infrastructure / protocol error
        │
        ▼
Application failure
        │
        ▼
Presentation error state
        │
        ▼
User-facing message
```

Не каждая ошибка обязана иметь отдельный type на каждом уровне.

Mapping необходим тогда, когда меняется semantics ошибки или требуется скрыть implementation details.

---

## 2. Основные категории

Следует различать:

```text id="4v76hh"
Exception
Error
Failure
Error State
User Message
```

Эти понятия не являются взаимозаменяемыми.

---

## 3. Exception

Exception представляет exceptional condition, обычно возникшую на technical boundary или внутри стороннего API.

Примеры:

* `FileSystemException`;
* `SocketException`;
* `FormatException`;
* `ProcessException`;
* `TimeoutException`;
* `PlatformException`.

Exception может быть implementation detail.

Он НЕ ДОЛЖЕН автоматически становиться частью public application API.

---

## 4. Programming error

Programming error означает нарушение invariant или ошибку реализации.

Примеры:

* unreachable state;
* invalid internal assumption;
* unexpected null;
* impossible transition;
* misuse API.

Programming error не следует автоматически преобразовывать в обычный recoverable business failure.

Он должен быть:

* диагностируемым;
* иметь stack trace;
* исправляться как defect.

---

## 5. Failure

Failure представляет ожидаемую или нормализованную ошибку операции на application boundary.

Например:

```text id="wtihls"
ConnectionFailure
ProtocolFailure
SessionFailure
PermissionDenied
FileAccessFailure
```

Failure отвечает на вопрос:

> Почему application operation не смогла завершиться?

а не:

> Какой конкретный Dart exception был выброшен?

---

## 6. Typed failures

Ожидаемые failure modes следует представлять типизированно.

Предпочтительно:

```dart id="6blp58"
sealed class ConnectionFailure {
  const ConnectionFailure();
}
```

или эквивалентная модель.

Не следует использовать:

```dart id="9r2ucn"
Exception('connection failed')
```

как единственную application-level representation.

---

## 7. `fpdart`

Проект использует `fpdart`.

`Either<Failure, T>` может использоваться для operations, где failure является ожидаемой частью contract.

Conceptually:

```dart id="hwum6i"
Future<Either<ConnectionFailure, Session>> connect();
```

Это пример подхода, а не обязательная сигнатура существующего API.

Следует придерживаться established error model конкретного package.

---

## 8. Когда использовать `Either`

`Either` хорошо подходит, если caller должен явно обработать ожидаемые outcomes.

Например:

```text id="wmw7nl"
success
unsupported
permission denied
connection unavailable
```

---

## 9. Когда использовать Exception

Exception допустим, если:

* этого требует внешний API;
* ошибка действительно exceptional;
* caller не может осмысленно восстановиться локально;
* нарушение является programming error.

На архитектурной boundary exception следует нормализовать, если caller должен принимать application decision.

---

## 10. Не смешивать error models

Для одной категории operations не следует хаотично использовать:

```text id="r2u3wg"
Either<Failure, T>
T?
bool
Exception
Result<T>
```

без различий в semantics.

Consistency важнее локального удобства.

---

## 11. Protocol errors

Protocol errors принадлежат `acp_protocol`.

Примеры:

* malformed ACP message;
* invalid field type;
* missing required field;
* unsupported protocol version;
* invalid method payload.

Protocol error должен содержать достаточно context для diagnostics.

Он не должен содержать Flutter-specific behavior.

---

## 12. Unknown protocol data

Unknown optional data не обязательно является error.

Если ACP разрешает forward compatibility:

```text id="q0qz0x"
unknown optional field
```

может быть нормальным condition.

Нельзя превращать любое неизвестное поле в fatal protocol failure.

---

## 13. Unsupported protocol

Если agent использует несовместимую protocol version, это должно быть explicit failure.

Например:

```text id="4s03zq"
UnsupportedProtocolVersion
```

Presentation может затем показать понятное сообщение пользователю.

---

## 14. Transport errors

Transport errors принадлежат `acp_transports`.

Примеры:

* connection refused;
* process exited;
* stream closed;
* broken pipe;
* socket failure;
* framing failure.

Transport error описывает technical failure transport layer.

---

## 15. Transport error ≠ Session failure

Например:

```text id="92x9mh"
ProcessExited
```

может быть преобразован в:

```text id="cyrmxs"
ConnectionLost
```

а затем привести к:

```text id="84qt6w"
SessionState.reconnecting
```

Transport не должен сам определять final session semantics.

---

## 16. Infrastructure errors

Infrastructure adapters должны нормализовать implementation-specific exceptions.

Например:

```text id="fv7lgv"
FileSystemException
       │
       ▼
FileAccessFailure
```

или:

```text id="x2pjxe"
PlatformException
       │
       ▼
SecureStorageFailure
```

Application code не должен зависеть от plugin-specific exceptions без необходимости.

---

## 17. Application failures

Application failure описывает ошибку meaningful operation.

Например:

```text id="zmsdxm"
SessionUnavailable
PromptRejected
PermissionDenied
ReconnectExhausted
WorkspaceUnavailable
```

Application failure может агрегировать несколько lower-level technical causes.

---

## 18. Error mapping

Mapping следует выполнять на boundary, где меняется semantics.

Пример:

```text id="z0l2nc"
SocketException
      │
      ▼
TransportConnectionFailure
      │
      ▼
SessionConnectionLost
```

Не нужно создавать отдельный wrapper, если он не добавляет semantics.

---

## 19. Не делать mechanical wrapping

Нежелательно:

```text id="im8wzq"
SocketException
    ↓
TransportException
    ↓
RepositoryException
    ↓
ServiceException
    ↓
ApplicationException
```

если каждый уровень только меняет имя.

Mapping должен иметь архитектурный смысл.

---

## 20. Preserve cause

При mapping technical error желательно сохранять original cause для diagnostics, если это безопасно.

Conceptually:

```text id="dxaw16"
ConnectionFailure(
  reason: transportClosed,
  cause: originalError,
)
```

Original cause не должен автоматически становиться user-facing content.

---

## 21. Stack trace

Unexpected exception должен сохранять stack trace.

Нежелательно:

```dart id="n2mq2l"
try {
  ...
} catch (e) {
  throw MyFailure();
}
```

если при этом теряется stack trace и причина.

---

## 22. Catch scope

`try/catch` должен находиться там, где component способен:

* восстановиться;
* добавить meaningful context;
* преобразовать error semantics;
* выполнить cleanup.

Не следует ловить exception только для того, чтобы сразу бросить его снова без пользы.

---

## 23. Catch-all

Использование:

```dart id="sjsqqd"
catch (e) {
  ...
}
```

допустимо на outer boundary для предотвращения uncontrolled failure.

Но catch-all НЕ ДОЛЖЕН превращать programming errors в обычный:

```text id="4g9pyf"
Something went wrong
```

без diagnostics.

---

## 24. Silent catch

ЗАПРЕЩЕНО:

```dart id="0o5l70"
try {
  ...
} catch (_) {}
```

для значимой operation.

Если ошибка намеренно игнорируется, причина должна быть очевидна и безопасна.

---

## 25. Error ownership

Ошибка должна обрабатываться тем layer, который способен принять решение.

Например:

```text id="7vq7z4"
transport error
    ↓
client core decides reconnect
```

а не:

```text id="ftxbt9"
transport error
    ↓
widget decides reconnect
```

---

## 26. Recoverable vs terminal

Каждый значимый failure должен иметь понятную recovery semantics.

Следует различать:

```text id="4y5htp"
recoverable
terminal
```

или эквивалентную модель.

---

## 27. Recoverable failure

Recoverable failure позволяет продолжить operation/system lifecycle.

Например:

* temporary connection loss;
* retryable transport error;
* recoverable persistence conflict.

Он может приводить к:

```text id="ok8vxr"
retrying
reconnecting
waiting
```

---

## 28. Terminal failure

Terminal failure означает, что текущая operation не может автоматически продолжиться.

Например:

* incompatible protocol;
* exhausted reconnect policy;
* invalid persisted state без migration;
* permanently unavailable required capability.

Terminal failure не обязательно означает crash всего приложения.

---

## 29. Retryability

Retryability является application/transport policy, а не свойством UI.

Следует уметь определить:

```text id="2bfpsx"
retryable
notRetryable
```

или более конкретную policy.

---

## 30. Не retry всё подряд

Нельзя автоматически retry:

* permission denied;
* invalid protocol message;
* unsupported version;
* invalid user input;
* programming error.

Retry должен иметь semantic basis.

---

## 31. Retry context

Retry operation должна сохранять correlation context.

Например:

```text id="84ixk3"
request_id
attempt
generation
failure_type
```

---

## 32. Retry exhaustion

После исчерпания retry policy должен возникнуть explicit terminal outcome.

Например:

```text id="d60yvv"
ReconnectExhausted
```

а не вечный цикл retries.

---

## 33. Timeout

Timeout является отдельным failure reason.

Следует различать:

* transport connect timeout;
* request timeout;
* permission timeout;
* shutdown timeout.

Они имеют разные recovery semantics.

---

## 34. Cancellation не всегда ошибка

User-requested cancellation обычно является нормальным lifecycle outcome, а не `error`.

Например:

```text id="tkfguo"
RequestCancelled
```

не следует автоматически логировать на error level.

---

## 35. Permission denied не crash

Permission denial — expected application outcome.

Он должен быть:

* типизирован;
* обработан;
* при необходимости показан пользователю;

но не считаться unexpected exception.

---

## 36. Stale event не обязательно error

Stale event после reconnect может быть ожидаемым consequence concurrency.

Обычно:

```text id="2cvnke"
ignored + debug/warning
```

лучше, чем fatal error.

Если stale event нарушает ACP guarantee, severity может быть выше.

---

## 37. Duplicate event

Duplicate event также не обязательно failure.

Если replay разрешён, deduplication является normal behavior.

---

## 38. Presentation error state

Presentation должна получать normalized error state.

Например:

```text id="imc0fh"
SessionErrorViewState(
  title,
  description,
  canRetry,
)
```

Это presentation model, а не transport exception.

---

## 39. User-facing message

User-facing message должен:

* быть понятным;
* описывать действие/последствие;
* не раскрывать internal stack trace;
* не раскрывать secrets;
* при возможности предлагать recovery action.

---

## 40. Не показывать `toString()`

ЗАПРЕЩЕНО использовать:

```dart id="n5sikd"
Text(error.toString())
```

как общий production error UX.

Technical exception text может:

* быть непонятным;
* содержать paths;
* содержать implementation details;
* содержать sensitive data.

---

## 41. Technical details

UI может предоставлять отдельный expandable diagnostic section в debug или product-approved flow.

Например:

```text id="14mnjc"
Connection to agent was lost.

[Retry]

Technical details:
Transport closed unexpectedly.
```

Technical details должны быть sanitized.

---

## 42. Error codes

Для support/diagnostics полезны stable error codes.

Например:

```text id="o7ic43"
ACP_PROTOCOL_UNSUPPORTED
ACP_CONNECTION_LOST
ACP_RECONNECT_EXHAUSTED
PERMISSION_DENIED
```

Error code не должен заменять typed error model внутри Dart.

---

## 43. Localization

User-facing error text не следует хранить внутри low-level failure type, если application поддерживает localization.

Лучше:

```text id="0u5uvg"
Failure
   ↓
Presentation mapping
   ↓
localized message
```

---

## 44. BLoC error handling

BLoC должен:

* вызвать application API;
* получить typed failure;
* преобразовать его в presentation state/effect.

BLoC НЕ ДОЛЖЕН знать о:

* `SocketException`;
* `ProcessException`;
* raw ACP parse errors;

если application boundary уже должна их нормализовать.

---

## 45. BLoC try/catch

Нежелательно повторять:

```dart id="25tjdl"
try {
  await client.doSomething();
} catch (e) {
  emit(ErrorState(e.toString()));
}
```

во всех handlers.

Error handling strategy должна быть согласованной.

---

## 46. Error state vs effect

Некоторые ошибки являются durable state.

Например:

```text id="67w96h"
session failed
```

Другие могут быть one-shot presentation effect:

```text id="fy5gm9"
failed to copy text
```

Не следует превращать каждую мелкую operation error в global screen error state.

---

## 47. Partial failure

Одна feature operation может failed, пока остальное application state остаётся valid.

Например:

```text id="j7mtm4"
session = ready
historySave = failed
```

Не следует переводить всю session в failed state, если failure локальный.

---

## 48. Aggregated failures

Если operation выполняет несколько independent actions, может потребоваться aggregated result.

Но не следует создавать generic `List<Exception>` как application API.

Aggregation должна иметь понятную semantics.

---

## 49. Validation errors

Validation failure является ожидаемым outcome.

Следует различать:

```text id="kfr5l4"
presentation validation
application validation
protocol validation
```

Они принадлежат разным boundaries.

---

## 50. User input validation

Простая UI validation может оставаться presentation concern.

Например:

```text id="xmrz4g"
empty field
invalid local path format
```

Но security/application constraints должны проверяться ниже UI.

---

## 51. Protocol validation

Protocol validation проверяет:

* schema;
* types;
* required fields;
* protocol invariants.

Она не должна определять application permission policy.

---

## 52. Security failures

Security failure должен fail closed.

Например, internal exception permission subsystem НЕ ДОЛЖЕН приводить к auto-allow.

Предпочтительно:

```text id="chzfj1"
policy error
    ↓
deny operation
    ↓
log unexpected failure
```

---

## 53. Persistence errors

Следует различать:

* data unavailable;
* corrupted data;
* migration failure;
* write failure;
* stale write conflict.

Не следует представлять всё как:

```text id="yuehrd"
StorageException
```

если application recovery различается.

---

## 54. Corrupted persisted data

Corruption должна иметь explicit recovery policy.

Возможные варианты:

* reject;
* restore backup;
* reset affected data;
* ask user.

Нельзя молча игнорировать corruption, если это приводит к потере данных.

---

## 55. Platform errors

Platform-specific errors должны нормализоваться до cross-platform semantics там, где это возможно.

Например:

```text id="akvrar"
Windows credential error
macOS keychain error
Linux keyring error
        │
        ▼
CredentialStoreFailure
```

---

## 56. Unsupported capability

Unsupported capability должна иметь typed representation.

Это лучше, чем generic exception.

Например:

```text id="c82p0p"
CapabilityUnavailable
```

Presentation может disable action или показать explanation.

---

## 57. Error context

Failure может содержать structured context:

```text id="b51hrm"
sessionId
requestId
operation
reason
```

Но context не должен превращаться в arbitrary `Map<String, dynamic>` без необходимости.

---

## 58. Sensitive context

Failure objects не должны бесконтрольно хранить:

* token;
* credentials;
* full prompt;
* full file content.

Иначе они могут случайно попасть в logs/crash reports.

---

## 59. Logging expected failure

Expected failure следует логировать на appropriate level.

Например:

```text id="2a2yb8"
permission denied
    → info/debug
```

```text id="d6lrg4"
temporary connection loss
    → warning
```

```text id="edn3ff"
unexpected invariant violation
    → error
```

---

## 60. Не логировать одну ошибку в каждом layer

Нежелательно:

```text id="jyf54k"
transport: ERROR
client: ERROR
bloc: ERROR
widget: ERROR
```

для одной причины.

Лучше:

```text id="c57x7h"
transport
    → technical failure + stack trace

client
    → application transition/recovery

presentation
    → user-visible state
```

---

## 61. Error correlation

Ошибка должна сохранять correlation с operation, в которой она возникла.

При наличии следует использовать:

* `session_id`;
* `request_id`;
* `message_id`;
* `tool_call_id`;
* `connection_generation`;
* `operation_id`.

Это особенно важно для concurrent operations.

---

## 62. Correlation после mapping

При преобразовании:

```text id="pmk7oa"
TransportFailure
      │
      ▼
SessionConnectionLost
```

correlation context не должен теряться.

Например, application layer должен иметь возможность определить:

```text id="u5y6ny"
какая session потеряла connection
какая generation завершилась
был ли active request
```

---

## 63. Error identity

Не следует использовать текст сообщения как identity ошибки.

Плохо:

```dart id="1vyfja"
if (error.message == 'Connection closed') {
  reconnect();
}
```

Предпочтительно:

```dart id="xyv7ur"
switch (failure) {
  case ConnectionLost():
    ...
}
```

или другой typed mechanism.

---

## 64. Error codes и typed errors

Stable error code может быть частью typed failure.

Conceptually:

```text id="utpks8"
ConnectionLost
    code = ACP_CONNECTION_LOST
```

Typed class используется application logic.

Code используется для:

* diagnostics;
* support;
* telemetry;
* external representation.

---

## 65. Error equality

Если failure используется как immutable state, equality должна быть предсказуемой.

Не следует включать в equality mutable или случайные technical objects без необходимости.

Например stack trace обычно не должен определять semantic equality presentation state.

---

## 66. Failure hierarchy

Не следует создавать одну гигантскую hierarchy всех ошибок приложения, если domains независимы.

Предпочтительно иметь bounded families:

```text id="ck34mu"
ProtocolFailure
TransportFailure
SessionFailure
PermissionFailure
FileFailure
CredentialFailure
```

в соответствующих packages.

---

## 67. Generic `AppFailure`

Один общий:

```dart id="xmkvdh"
class AppFailure {
  final String message;
}
```

обычно слишком слаб для application decisions.

Если используется общий base type, concrete failure types должны сохранять semantics.

---

## 68. Failure ownership

Failure type должен находиться рядом с boundary, contract которого он представляет.

Например:

```text id="yyt4ya"
acp_protocol
    → ProtocolFailure

acp_transports
    → TransportFailure

acp_client_core
    → SessionFailure / ClientFailure

platform adapter
    → FileAccessFailure
```

Не следует помещать все failure types в глобальный `errors.dart` только ради централизации.

---

## 69. `core` и errors

Shared `core` package может содержать только действительно cross-cutting error primitives.

Например:

* common result abstraction;
* generic cancellation marker;
* shared error metadata.

Feature-specific failure не следует переносить в `core`.

---

## 70. Public API

Если failure является частью public API package, он должен быть:

* typed;
* documented;
* stable enough для consumers;
* экспортирован через public package API.

Consumer другого package не должен импортировать `src/errors/...`.

---

## 71. Internal errors

Implementation-only error может оставаться private/internal.

Не следует делать public каждый technical exception.

Public API должен показывать только errors, которые consumer способен осмысленно обработать.

---

## 72. Async operation contract

Public async API должен иметь понятную error semantics.

Consumer должен понимать:

```text id="ftr84a"
какие failures ожидаемы
какие outcomes terminal
можно ли retry
можно ли cancel
```

Необязательно перечислять все programming exceptions.

---

## 73. Stream error contract

Для long-lived streams следует решить, как errors представлены:

### Через stream error channel

```text id="mvk2vr"
stream.addError(...)
```

### Через typed application event/state

```text id="0lvdsw"
ClientEvent.connectionFailed(...)
```

Для complex lifecycle часто предпочтительнее typed event/state, потому что stream error может завершить subscription.

---

## 74. Critical streams

Critical application stream не должен случайно умереть из-за recoverable error.

Например connection loss может быть:

```text id="nqfxp3"
event → reconnecting
```

а не обязательно:

```text id="n2bc97"
stream terminated forever
```

---

## 75. Stream termination

Если stream действительно terminal, это должно быть частью contract.

Consumer должен знать, что после `done` новых events не будет.

---

## 76. Error after dispose

Ошибка от operation, завершившейся после dispose owner, не должна:

* emit presentation state;
* показывать dialog;
* запускать reconnect;
* создавать notification.

При этом unexpected error не следует полностью терять: его можно диагностировать на owning lower layer.

---

## 77. Stale failure

Failure может быть stale так же, как success result.

Пример:

```text id="w75mns"
request A started
request B replaced A
request A fails late
```

Failure A не должен переводить UI B в error state.

---

## 78. Generation guard

Перед применением async failure к current state следует проверить:

* operation identity;
* session identity;
* connection generation;

если operation может стать stale.

---

## 79. Error during reconnect

Failure отдельной reconnect attempt не обязательно terminal.

Например:

```text id="8r85tq"
attempt 1 failed
    ↓
backoff
    ↓
attempt 2
```

Presentation может оставаться в:

```text id="2xkdxs"
reconnecting
```

до exhaustion policy.

---

## 80. Reconnect exhausted

После exhaustion должен возникнуть explicit terminal application failure.

Например:

```text id="k2kn5r"
ReconnectExhausted(
  attempts: 5,
  lastFailure: ...
)
```

Конкретная модель определяется implementation.

---

## 81. Error during shutdown

Expected errors, вызванные intentional shutdown, не следует ошибочно считать application failures.

Например:

```text id="r2k8j3"
stream closed
process terminated
subscription cancelled
```

во время controlled shutdown могут быть normal lifecycle.

---

## 82. Shutdown context

Lifecycle должен позволять отличить:

```text id="f04ys4"
unexpected process exit
```

от:

```text id="m4nsl2"
process exit because application is shutting down
```

Иначе приложение может случайно запустить reconnect при закрытии.

---

## 83. Error during cleanup

Cleanup error должен быть диагностируемым.

Например failure закрыть один resource не должен автоматически предотвращать cleanup остальных resources.

Conceptually:

```text id="32ggzo"
close subscription
close transport
terminate process
dispose container
```

следует попытаться выполнить полностью, сохраняя errors.

---

## 84. Multiple cleanup failures

Если shutdown генерирует несколько failures, можно агрегировать diagnostics.

Но user-facing UX обычно должен показывать meaningful overall outcome, а не список внутренних exceptions.

---

## 85. Graceful degradation

Если optional subsystem failed, application может продолжить работу.

Например:

```text id="00as90"
desktop notifications unavailable
```

не обязательно означает:

```text id="74k0yv"
ACP client unusable
```

Failure severity должна соответствовать importance capability.

---

## 86. Required dependency failure

Если required subsystem недоступен:

```text id="2slf5j"
ACP transport cannot start
```

application должна перейти в explicit unavailable/failed state.

Не следует продолжать в partially initialized состоянии без defined semantics.

---

## 87. Initialization errors

Initialization должен иметь отдельный failure path.

Например:

```text id="r53odf"
initializing
    │
    ├── ready
    └── initializationFailed
```

Не следует маскировать initialization failure как `disconnected`, если application ещё не была корректно initialized.

---

## 88. Configuration errors

Invalid configuration должна быть отличима от runtime transport failure.

Например:

```text id="svq8u5"
AgentExecutableNotConfigured
InvalidAgentArguments
UnsupportedConfiguration
```

может требовать user action, а не retry.

---

## 89. Actionable errors

Если user может исправить проблему, presentation должна по возможности предоставить действие.

Например:

```text id="fh13mt"
Agent executable not found.

[Choose executable]
```

или:

```text id="t36rqn"
Connection lost.

[Retry]
```

Action должен соответствовать typed failure semantics.

---

## 90. Non-actionable errors

Если retry бессмысленен, UI не должен показывать ложную кнопку Retry.

Например incompatible protocol version может требовать:

* обновить client;
* обновить agent;

но не немедленно повторить тот же request.

---

## 91. `canRetry`

`canRetry` может быть presentation projection typed failure.

Не следует хранить его как независимый source of truth, если retryability определяется failure type/policy.

---

## 92. Retry action

Presentation выражает intent:

```text id="8jd5xg"
RetryRequested
```

Application layer решает, какую operation действительно повторить.

Widget не должен вручную повторять low-level transport call.

---

## 93. Error recovery state

Recovery должна иметь явный state, если операция занимает время.

Например:

```text id="0k60ba"
failed
  ↓ retry
retrying
  ↓
ready
```

а не:

```text id="d2e5rv"
failed
  ↓
immediately pretend ready
```

---

## 94. Error history

Не следует хранить бесконечную history всех failures в application state.

Для diagnostics используется observability subsystem.

Application state должен хранить только данные, необходимые текущему behavior/UI.

---

## 95. Last error

`lastError` допустим, если semantics понятна.

Но следует избегать generic global:

```dart id="6ec85f"
Object? lastError;
```

для всего приложения.

---

## 96. Error clearing

Необходимо определить, когда error перестаёт быть актуальной.

Например:

```text id="vv2dq1"
send failed
    ↓
new send succeeds
    ↓
old send error cleared
```

Старый error не должен продолжать влиять на unrelated operation.

---

## 97. One-shot error notification

Для локальной non-durable ошибки может использоваться presentation effect:

```text id="xf2k5n"
Copy failed
    → show notification
```

Не обязательно менять основной screen state.

---

## 98. Error localization boundary

Low-level package не должен формировать окончательный localized user text.

Например:

```dart id="ht5wq7"
throw TransportFailure(
  userMessage: 'Не удалось подключиться к агенту',
);
```

создаёт presentation coupling.

Лучше передать typed reason.

---

## 99. Diagnostic message vs user message

Следует различать:

```text id="nhm23k"
diagnosticMessage
```

и:

```text id="96a0gp"
userMessage
```

Первое может содержать technical context после sanitization.

Второе должно быть понятно пользователю.

---

## 100. Security-sensitive errors

Security error не должен раскрывать лишнюю информацию.

Например authentication failure не должен показывать secret/token или internal credential storage details.

---

## 101. Permission policy failure

Если permission subsystem неожиданно failed:

```text id="31xbmu"
evaluation exception
```

опасная operation должна быть denied.

При этом unexpected exception должен попасть в diagnostics.

---

## 102. ACP malformed message

Malformed message должен:

1. Создать protocol-level error.
2. Получить correlation context, если его можно безопасно извлечь.
3. Быть залогирован.
4. Привести к defined protocol/application behavior.

Нельзя просто:

```dart id="5v75vu"
catch (_) {
  return null;
}
```

и продолжить как будто сообщения не было.

---

## 103. Unknown method

Unknown method обрабатывается согласно ACP compatibility policy.

Возможные outcomes:

* ignore;
* protocol error;
* unsupported event;
* connection/session failure.

Решение не должно приниматься presentation layer.

---

## 104. Invalid state transition

Попытка выполнить operation в недопустимом state должна иметь typed outcome.

Например:

```text id="20hdvw"
sendPrompt while disconnected
```

не должна приводить к случайному null/late exception.

---

## 105. Preconditions

Application API может проверять preconditions до side effect.

Например:

```text id="qq7nwe"
session must be ready
request must not already be active
tool call must still be pending
```

Failure precondition является expected application outcome.

---

## 106. Assertions

`assert` может использоваться для developer invariants, но не для validation external/user/protocol data.

Assertions могут быть отключены в release.

Нельзя использовать:

```dart id="c9w8mt"
assert(userInputIsValid);
```

как единственную защиту production behavior.

---

## 107. Exhaustive handling

Для sealed failure types следует предпочитать exhaustive handling там, где caller обязан учитывать все cases.

Freezed/sealed classes могут помочь compiler-assisted handling.

---

## 108. Default branch

Не следует добавлять broad default branch, который скрывает новый security/protocol-critical failure type.

Например:

```dart id="z3m8sv"
default:
  return retry();
```

может стать опасным после добавления нового non-retryable failure.

---

## 109. Error model evolution

При добавлении нового failure type следует проверить:

* application handlers;
* retry policy;
* BLoC mapping;
* observability;
* tests;
* user-facing presentation.

Typed error model должен эволюционировать контролируемо.

---

## 110. Public error compatibility

Изменение public failure type в reusable package может быть breaking API change.

Необходимо учитывать consumers и OpenSpec/ADR, если изменение архитектурно значимо.

---

## 111. Testing error handling

Error handling должен иметь direct tests.

Минимальные категории:

* expected failure;
* unexpected exception;
* mapping;
* retryable failure;
* terminal failure;
* stale failure;
* cancellation;
* permission denial;
* protocol error;
* transport error.

---

## 112. Mapping tests

Следует тестировать meaningful mappings.

Например:

```text id="nn6fph"
ProcessExited unexpectedly
    → ConnectionLost
```

Не нужно тестировать trivial constructor wrapping.

---

## 113. Retry tests

Проверять:

* retryable error запускает retry;
* non-retryable error не запускает retry;
* retry exhaustion terminal;
* manual disconnect останавливает retry.

---

## 114. Stale error tests

Обязательный race scenario:

```text id="s0vgf7"
operation A starts
operation B supersedes A
A fails late
```

State B не должен перейти в failure из-за A.

---

## 115. Presentation mapping tests

BLoC/presentation tests должны проверять:

```text id="p0kl6d"
typed failure
    ↓
correct UI state/action
```

Не следует в этих tests воспроизводить low-level exception.

---

## 116. Security error tests

Минимум:

* permission subsystem error → deny;
* secret не попадает в user message;
* secret не попадает в log;
* unknown dangerous capability не auto-approved.

---

## 117. Observability tests

Unexpected exception должен сохранять:

* error type;
* stack trace;
* correlation context.

Expected application failure не должен ошибочно репортиться как crash.

---

## 118. Нежелательные patterns

### `catch (e) => Error(e.toString())`

```dart id="hn6b2p"
try {
  ...
} catch (e) {
  emit(ErrorState(e.toString()));
}
```

теряет semantics и может раскрывать technical details.

---

### Generic Exception

```dart id="wq1u0h"
throw Exception('failed');
```

для expected application outcome.

---

### Silent catch

```dart id="s57v6v"
catch (_) {}
```

для meaningful operation.

---

### Retry everything

```dart id="jgfdbk"
catch (_) {
  retry();
}
```

опасно.

---

### User message в infrastructure

```dart id="dhc0v3"
throw FileFailure('Не удалось открыть файл');
```

если строка является presentation/localization concern.

---

### Error text как control flow

```dart id="50xbga"
if (e.toString().contains('closed')) {
  reconnect();
}
```

запрещённый pattern.

---

### Raw exception в BLoC state

```dart id="dhxqob"
class ErrorState {
  final Object error;
}
```

как основной presentation contract.

---

### Logging and rethrowing everywhere

```text id="2g0df8"
layer A logs
layer B logs
layer C logs
```

создаёт duplicate noise.

---

## 119. Checklist при добавлении failure

Перед добавлением нового failure type агент ОБЯЗАН определить:

1. Какой layer владеет failure?
2. Это expected outcome или unexpected exception?
3. Нужно ли caller его обрабатывать?
4. Recoverable ли он?
5. Retryable ли он?
6. Terminal ли он для текущей operation?
7. Как он влияет на lifecycle state?
8. Как он отображается в presentation?
9. Какие correlation fields нужны?
10. Есть ли sensitive context?
11. Как он логируется?
12. Какие tests нужны?

---

## 120. Checklist при `catch`

Перед добавлением `catch` определить:

1. Почему exception ловится именно здесь?
2. Может ли этот layer восстановиться?
3. Меняется ли semantics ошибки?
4. Нужно ли сохранить cause?
5. Нужно ли сохранить stack trace?
6. Нужно ли логировать?
7. Не будет ли error залогирована ещё раз выше?
8. Может ли result стать stale?
9. Что увидит caller?
10. Что увидит пользователь?

Если ответ только:

> чтобы приложение не упало

следует проверить, не находится ли `catch` на неправильном уровне.

---

## 121. Checklist для user-facing error

Перед показом ошибки пользователю проверить:

1. Понятно ли, что произошло?
2. Понятно ли влияние на текущую работу?
3. Может ли пользователь что-то сделать?
4. Нужно ли показывать Retry?
5. Не раскрывается ли sensitive data?
6. Не показывается ли internal exception text?
7. Не устарела ли ошибка
