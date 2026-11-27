# Обработка ошибок в CodeLab

Документ задаёт, как клиент и агент CodeLab представляют, преобразуют, журналируют и показывают ошибки на каждом архитектурном уровне.

Цели:

* разделить ошибки разных архитектурных уровней;
* не пропускать в UI исключения, зависящие от реализации;
* обрабатывать ожидаемые сбои типизированно;
* явно задать, можно ли повторить операцию и как восстановиться;
* сохранить контекст для диагностики;
* безопасно показывать ошибки пользователю;
* сделать обработку ошибок предсказуемой и тестируемой.

Общие правила — корневой `AGENTS.md` (§2, §10, §12, §15, §16), [`layers-and-dependencies.md`](layers-and-dependencies.md), [`acp-boundary.md`](acp-boundary.md), [`session-lifecycle.md`](session-lifecycle.md), [`streaming.md`](streaming.md), [`concurrency.md`](concurrency.md), [`permissions.md`](permissions.md), [`state-management.md`](state-management.md), [`observability.md`](observability.md), [`testing.md`](testing.md). Модель ошибок ядра агента — [`proposals/agent-core/12-observability-and-errors.md`](proposals/agent-core/12-observability-and-errors.md) (§12.2).

Термины:

* **Исключение** (exception) — объект, брошенный через `throw`; обычно возникает на технической границе или в стороннем API.
* **Ошибка программиста** (programming error) — нарушение инварианта или дефект реализации.
* **Сбой** (failure) — ожидаемая или нормализованная ошибка операции на границе приложения; отвечает на вопрос «почему операция не удалась».
* **Состояние ошибки** (error state) — представление сбоя в состоянии приложения или экрана.
* **Сообщение пользователю** (user message) — текст, который видит человек; отделён от диагностического сообщения (§99).
* **Восстановимый / терминальный сбой** (recoverable / terminal) — после первого работа продолжается или повторяется, после второго текущая операция автоматически продолжиться не может (§26–§28).
* **Преобразование** (mapping) — перевод ошибки одного уровня в ошибку другого, когда меняется её семантика (§18).
* **Устаревший сбой** (stale failure) — сбой операции, которую уже заменила другая или чьё соединение сменилось (§77).

Где в коде. Протокол: `AcpProtocolError` с видом `AcpProtocolErrorKind` и кодом `jsonRpcCode`, исключение разбора `JsonRpcProtocolException`, коды JSON-RPC (`jsonRpcParseErrorCode` −32700 … `jsonRpcInternalErrorCode` −32603) и ACP `acpResourceNotFoundCode` −32002 (`packages/dart/codelab_acp_protocol/lib/src/json_rpc/protocol_error.dart`), объект ошибки ответа `JsonRpcError` (`json_rpc_error.dart`). Транспорты: `AcpTransportException` с `AcpTransportErrorCode` (`startFailed`, `sendFailed`, `receiveFailed`, `protocolViolation`, `closed`, `timeout`, `disconnected`, `unknown`), событие `AcpTransportEvent.failure`, причина `AcpWebSocketHandshakeRejected` (`packages/dart/codelab_acp_transports/lib/src/acp_transport.dart`); серверный разбор кадра — `ServerFrame` (`lib/src/io/server_frames.dart`). Протокольный клиент `codelab_client_acp`: исключения `AcpClientApplicationException` и наследники `AcpConnectionLostException`, `MissingAcpSessionException`, `AcpRequestTimeoutException`, `UnsupportedProtocolVersionException` (`lib/src/application/acp_client_application.dart`), сбой хода `PromptFailure` (`lib/src/domain/prompt_failure.dart`), `ConnectionFailureReason` и `ClientConnectionState.failed` (`lib/src/domain/domain_models.dart`), `FsAccessFailure` (`lib/src/domain/fs_access.dart`), `TerminalAccessFailure` (`lib/src/domain/terminal_access.dart`), `StateTransitionException` и `StateTransitionResult` (`lib/src/domain/state_machines.dart`), `AcpClientApplicationFailure` (`lib/src/application/application_models.dart`) и `TaskEither<AcpClientApplicationFailure, T>` use case-ов (`lib/src/application/use_cases.dart`), маскирование `SecretRedactor` (`lib/src/domain/secret_redaction.dart`), политика payload `ProtocolPayloadPolicy` (`lib/src/application/protocol_frame.dart`). Ядро клиента `codelab_client_core`: `ClientWorkspaceException`, `ConnectionView.lost`/`failed`, `PromptOutcome`, `SessionView.canRetry`, `NoticeReason`, `WorkspaceDiagnostic` и `describeFailure` (`lib/src/diagnostics/diagnostics.dart`), sealed-результаты `ProfileCommitResult`, `ProfileDraftResult`, `ThemeImportResult`. Агент: `Result<T, E>` с `Ok`/`Err` (`packages/dart/codelab_agent_core/lib/src/util/result.dart`), `FileError`/`FileErrorCode` и `ExecError`/`ExecErrorCode` (`lib/src/env/execution_env.dart`), `LlmErrorClass` (`lib/src/llm/errors.dart`), событие `AgentError` с `AgentErrorClass` (`lib/src/loop/agent_events.dart`), `ConfigException`, `HostWiringException`; ACP-проекция агента — `AcpRequestError` (`packages/dart/codelab_agent_acp/lib/src/connection/acp_error.dart`), `ClientCallFailure` (`lib/src/connection/client_requests.dart`), ответ-ошибка хода с `data.codelab` (`turnResponse`, `lib/src/event_projection.dart`).

---

## 1. Основной принцип

Ошибка ДОЛЖНА представляться на том уровне, семантику которого она описывает.

Типичный путь:

```text
Внешнее исключение / исключение среды выполнения
        │
        ▼
Ошибка инфраструктуры / протокола
        │
        ▼
Сбой приложения
        │
        ▼
Состояние ошибки для отображения
        │
        ▼
Сообщение пользователю
```

Не каждая ошибка обязана иметь отдельный тип на каждом уровне.

Преобразование ДОЛЖНО выполняться там, где меняется семантика ошибки или нужно скрыть детали реализации.

---

## 2. Основные категории

СЛЕДУЕТ различать:

```text
Exception
Error
Failure
Error State
User Message
```

Эти понятия не взаимозаменяемы.

---

## 3. Исключение

Исключение (exception) описывает исключительную ситуацию — обычно на технической границе или внутри стороннего API.

Примеры:

* `FileSystemException`;
* `SocketException`;
* `FormatException`;
* `ProcessException`;
* `TimeoutException`;
* `PlatformException`.

Исключение может быть деталью реализации. Оно НЕ ДОЛЖНО автоматически становиться частью публичного API приложения.

---

## 4. Ошибка программиста

Ошибка программиста — нарушение инварианта или дефект реализации.

Примеры:

* недостижимое состояние;
* неверное внутреннее допущение;
* неожиданный `null`;
* невозможный переход;
* неправильное использование API.

Ошибку программиста НЕ СЛЕДУЕТ автоматически превращать в обычный восстановимый сбой.

Она ДОЛЖНА:

* быть диагностируемой;
* сохранять стек вызовов (stack trace);
* исправляться как дефект.

В коде ядро агента бросает для таких случаев `StateError`, `ArgumentError`, `ConfigException` и `HostWiringException` (`12-observability-and-errors.md` §12.2, третий класс).

---

## 5. Сбой

Сбой (failure) — ожидаемая или нормализованная ошибка операции на границе приложения.

Иллюстрация семейств:

```text
ConnectionFailure
ProtocolFailure
SessionFailure
PermissionDenied
FileAccessFailure
```

Имена иллюстративные; реальные типы — в абзаце «Где в коде» и §68.

Сбой отвечает на вопрос:

> Почему операция приложения не смогла завершиться?

а не:

> Какое именно исключение Dart было брошено?

---

## 6. Типизированные сбои

Ожидаемые виды сбоев СЛЕДУЕТ представлять типизированно.

Предпочтительно:

```dart
sealed class ConnectionFailure {
  const ConnectionFailure();
}
```

или эквивалентная модель.

НЕ СЛЕДУЕТ использовать

```dart
Exception('connection failed')
```

как единственное представление на уровне приложения.

В коде так устроены `PromptFailure`, `FsAccessFailure`, `TerminalAccessFailure`, `ClientCallFailure` (sealed-классы) и `ClientConnectionState.failed` с `ConnectionFailureReason`; класса `ConnectionFailure` нет.

---

## 7. `fpdart`

`fpdart` — утверждённая библиотека функциональных примитивов (`technology-stack.md` §10).

`Either<Failure, T>` МОЖЕТ использоваться для операций, где сбой — ожидаемая часть контракта.

Концептуально:

```dart
Future<Either<ConnectionFailure, Session>> connect();
```

Это пример подхода, а не обязательная сигнатура существующего API.

СЛЕДУЕТ придерживаться модели ошибок, уже принятой в конкретном пакете.

В коде `fpdart` импортирует только `codelab_client_acp`: use case-ы `lib/src/application/use_cases.dart` возвращают `TaskEither<AcpClientApplicationFailure, T>`. `ClientWorkspace` и приложения эти use case-ы не используют: приложения работают через `ClientWorkspace`, а он вызывает `AcpClientApplication` через `AcpClientBackend` (`codelab_client_core/lib/src/backend/agent_backend.dart`), ловит ошибки в основном `on Object` и сводит их в текст `describeFailure`; типизированная проверка одна — `is AcpClientApplicationException`. `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_acp_testing` и `apps/codelab_desktop` объявляют `fpdart` в `pubspec.yaml`, но в `lib/` его не импортируют. Ядро агента `fpdart` не использует (allowlist PKG-2) и возвращает ожидаемые сбои окружения собственным `Result<T, E>` (ENV-1).

---

## 8. Когда использовать `Either`

`Either` хорошо подходит, если вызывающий должен явно обработать ожидаемые исходы, например:

```text
success
unsupported
permission denied
connection unavailable
```

---

## 9. Когда использовать исключение

Исключение МОЖНО использовать, если:

* этого требует внешний API;
* ошибка действительно исключительная;
* вызывающий не может осмысленно восстановиться на месте;
* это ошибка программиста.

На архитектурной границе исключение СЛЕДУЕТ нормализовать, если вызывающий принимает по нему решение приложения.

---

## 10. Не смешивать модели ошибок

Для одной категории операций НЕ СЛЕДУЕТ хаотично использовать

```text
Either<Failure, T>
T?
bool
Exception
Result<T>
```

без различий в семантике. Единообразие важнее локального удобства.

В коде модель выбрана по пакету: протокольный клиент бросает типизированные исключения (`AcpClientApplicationException` и наследники), ядро клиента возвращает sealed-результаты для пользовательских операций (`ProfileCommitResult`, `ThemeImportResult`, `PromptOutcome`), ядро агента — `Result<T, E>` для окружения и события `AgentError` для сбоев работы (OBS-1).

---

## 11. Ошибки протокола

Ошибки протокола принадлежат `codelab_acp_protocol`.

Примеры:

* некорректное сообщение ACP;
* неверный тип поля;
* отсутствует обязательное поле;
* неподдерживаемая версия протокола;
* неверный payload метода.

Ошибка протокола ДОЛЖНА содержать достаточно контекста для диагностики и НЕ ДОЛЖНА содержать поведения, связанного с Flutter.

В коде: `JsonRpcProtocolException` (`invalidJson`, `invalidShape`, `unknownMethod`) бросает разбор, `AcpProtocolError` несёт вид (`AcpProtocolErrorKind`), метод и причину и сам выбирает код и текст JSON-RPC (`jsonRpcCode`, `jsonRpcMessage`, `toJsonRpcError`).

---

## 12. Неизвестные данные протокола

Неизвестные необязательные данные — не обязательно ошибка.

Если ACP допускает прямую совместимость (forward compatibility), неизвестное необязательное поле может быть нормальным условием.

ЗАПРЕЩЕНО превращать любое неизвестное поле в фатальный сбой протокола.

В коде: `session/update` незнакомого вида пропускается с записью debug (`_skipUnsupportedSessionUpdate`), незнакомый `ToolKind` сводится к `other` с предупреждением в журнале, поле `data.codelab` неожиданного типа в ответе-ошибке считается отсутствующим (`PromptFailure.fromJsonRpcError`).

---

## 13. Неподдерживаемый протокол

Если агент использует несовместимую версию протокола, это ДОЛЖНО быть явным сбоем, например `UnsupportedProtocolVersion`. Presentation затем может показать понятное сообщение.

В коде: `UnsupportedProtocolVersionException` (`codelab_client_acp`), соединение переходит в `ClientConnectionState.failed` с `ConnectionFailureReason.unsupportedProtocolVersion`.

---

## 14. Ошибки транспорта

Ошибки транспорта принадлежат `codelab_acp_transports`.

Примеры:

* соединение отклонено;
* процесс завершился;
* поток закрыт;
* разорван канал (broken pipe);
* сбой сокета;
* сбой разбиения на кадры (framing).

Ошибка транспорта описывает технический сбой транспортного уровня.

В коде это `AcpTransportException` с `AcpTransportErrorCode` и причиной `cause`/`stackTrace`; приходит событием `AcpTransportEvent.failure` в `events`, а не ошибкой потока. Отказ рукопожатия WebSocket различается по `cause is AcpWebSocketHandshakeRejected` с HTTP-статусом, а не по тексту.

---

## 15. Ошибка транспорта ≠ сбой сессии

Например, `ProcessExited` может быть преобразован в `ConnectionLost`, а затем привести к `SessionState.reconnecting`.

Транспорт НЕ ДОЛЖЕН сам определять итоговую семантику сессии.

В коде: `AcpTransportFailure` в `AcpClientApplication._handleTransportEvent` переводит соединение в `ClientConnectionState.failed` (причина — `ConnectionFailureReason` по коду транспорта), если соединение было готово или инициализировалось, снимает ожидающие запросы `AcpConnectionLostException` и одобрения; `ClientWorkspace` публикует `ConnectionView.lost`. Автоматического перехода в переподключение нет: его запускает пользователь (`reconnect()`, §79).

---

## 16. Ошибки инфраструктуры

Адаптеры инфраструктуры ДОЛЖНЫ нормализовать исключения, зависящие от реализации.

Например:

```text
FileSystemException
       │
       ▼
FileAccessFailure
```

или:

```text
PlatformException
       │
       ▼
SecureStorageFailure
```

Код приложения НЕ ДОЛЖЕН без необходимости зависеть от исключений конкретного плагина.

В коде: клиентские `fs/*` дают `FsAccessFailure` (`PathOutsideWorkingDirectoryFailure`, `FsNotFoundFailure`, `FsIoFailure`), `terminal/*` — `TerminalAccessFailure`; окружение агента — значения `Err(FileError)` и `Err(ExecError)` вместо исключений (ENV-1).

---

## 17. Сбои приложения

Сбой приложения описывает ошибку осмысленной операции.

Иллюстрация:

```text
SessionUnavailable
PromptRejected
PermissionDenied
ReconnectExhausted
WorkspaceUnavailable
```

Сбой приложения может объединять несколько технических причин нижнего уровня.

В коде таких имён нет; ближайшие — `MissingAcpSessionException`, `PromptFailure`, `ClientWorkspaceException`, `AcpClientApplicationFailure` (`transport`, `protocol`, `stateRejected`, `missingSession`, `unexpected`).

---

## 18. Преобразование ошибок

Преобразование СЛЕДУЕТ выполнять на границе, где меняется семантика.

Пример:

```text
SocketException
      │
      ▼
TransportConnectionFailure
      │
      ▼
SessionConnectionLost
```

Отдельная обёртка не нужна, если она не добавляет семантики.

В коде этот путь — `SocketException` → `AcpTransportException(startFailed | disconnected …)` → `ConnectionFailureReason` в `ClientConnectionState.failed` → `ConnectionView.failed` или `ConnectionView.lost`; ход, прерванный обрывом, получает `PromptFailure.connectionLost()`.

---

## 19. Без механического оборачивания

НЕ СЛЕДУЕТ строить цепочку

```text
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

если каждый уровень только меняет имя. Преобразование ДОЛЖНО иметь архитектурный смысл.

---

## 20. Сохранение причины

При преобразовании технической ошибки СЛЕДУЕТ сохранять исходную причину для диагностики, если это безопасно.

Концептуально:

```text
ConnectionFailure(
  reason: transportClosed,
  cause: originalError,
)
```

Исходная причина НЕ ДОЛЖНА автоматически становиться содержимым для пользователя.

В коде поле `cause` есть у `AcpTransportException`, `AcpProtocolError`, `AcpClientApplicationException`, `ClientConnectionState.failed`, `AcpClientApplicationFailure` и `DiagnosticEntry`; текст причины в записях диагностики (`_recordDiagnostic`) выбирает `_causeDetail` в `AcpClientApplication`: при `ProtocolPayloadPolicy.full` это `toString()` после `SecretRedactor`, при `metadataOnly` — только класс ошибки (`observability.md` §48а; D3 change `redesign-protocol-pane`). По этому правилу пишутся поле `DiagnosticEntry.cause` и внутренняя причина сбоя транспорта: `_handleTransportEvent` кладёт в `context` записи `code` и `inner_cause`, и при `metadataOnly` там класс внутренней причины (`SocketException`, `JsonRpcProtocolException`), а не её текст с путями и фрагментами кадра. В журнале ключ `cause` — только поле `DiagnosticEntry.cause`, вложенная причина идёт под `inner_cause`, значения не перекрывают друг друга (`_logDiagnosticEntry`; D3, «Текст ошибки агента»). Проверяют `payload_policy_diagnostics_test.dart` и `agent_error_text_test.dart` (`codelab_client_acp`).

---

## 21. Стек вызовов

Неожиданное исключение ДОЛЖНО сохранять стек вызовов.

НЕ СЛЕДУЕТ писать

```dart
try {
  ...
} catch (e) {
  throw MyFailure();
}
```

если при этом теряются стек и причина.

В коде стек сохраняется не везде. Его хранят `AcpTransportException.stackTrace` и ветки отката инструментов цикла агента (`_settle`, `Error.throwWithStackTrace`). Порт `Logger` клиента (`codelab_client_acp/lib/src/domain/logger.dart`) параметра для стека не имеет; `_mapApplicationFailure` получает `StackTrace` и не сохраняет его; адаптер журнала встроенного агента в app (design D9 change `add-embedded-agent-mode`) намеренно пишет только `error_class` без стека — так сказано в его doc-комментарии (`apps/codelab_desktop/lib/app/embedded_logger.dart`); изолированная очистка `_step` в `app_scope.dart` тоже пишет только `error_type`; общий `catch` хода в цикле агента стек не ловит (`agent_loop.dart`, ветка `TurnEndReason.failed`).

---

## 22. Где ловить

`try/catch` ДОЛЖЕН находиться там, где компонент способен:

* восстановиться;
* добавить осмысленный контекст;
* изменить семантику ошибки;
* выполнить очистку ресурсов.

НЕ СЛЕДУЕТ ловить исключение только ради того, чтобы сразу бросить его снова без пользы.

---

## 23. Перехват всего

Перехват всего (catch-all)

```dart
catch (e) {
  ...
}
```

МОЖНО использовать на внешней границе, чтобы не допустить неконтролируемого сбоя.

Но catch-all НЕ ДОЛЖЕН превращать ошибки программиста в обычное «Something went wrong» без диагностики.

В коде глобальных обработчиков (`runZonedGuarded`, `FlutterError.onError`, `PlatformDispatcher.instance.onError`) в `apps/*` нет; catch-all стоят на границах операций — шаги завершения app (`_step` в `app_scope.dart`), общий `catch` хода в цикле агента (LOOP-1), `on Object` в обработчиках запросов `fs/*` и `terminal/*` клиента с ответом `-32603`.

---

## 24. Молчаливый catch

ЗАПРЕЩЕНО

```dart
try {
  ...
} catch (_) {}
```

для значимой операции.

Если ошибка игнорируется намеренно, причина ДОЛЖНА быть очевидна и безопасна (комментарий рядом, как в `_step` при сбое самого журнала).

---

## 25. Владелец ошибки

Ошибку ДОЛЖЕН обрабатывать тот слой, который способен принять решение.

Например:

```text
ошибка транспорта
    ↓
ядро клиента решает о переподключении
```

а не:

```text
ошибка транспорта
    ↓
виджет решает о переподключении
```

---

## 26. Восстановимые и терминальные

У каждого значимого сбоя ДОЛЖНА быть понятная семантика восстановления.

СЛЕДУЕТ различать `recoverable` и `terminal` или использовать эквивалентную модель.

---

## 27. Восстановимый сбой

Восстановимый сбой позволяет продолжить операцию или жизненный цикл системы.

Например:

* временная потеря соединения;
* ошибка транспорта, допускающая повтор;
* восстановимый конфликт при сохранении.

Он может приводить к состояниям `retrying`, `reconnecting`, `waiting`.

---

## 28. Терминальный сбой

Терминальный сбой означает, что текущая операция не может продолжиться автоматически.

Например:

* несовместимый протокол;
* исчерпана политика переподключения;
* неверное сохранённое состояние без миграции;
* обязательная возможность недоступна навсегда.

Терминальный сбой не обязательно означает падение всего приложения.

---

## 29. Возможность повтора

Возможность повтора (retryability) — политика приложения или транспорта, а не свойство UI.

СЛЕДУЕТ уметь определить `retryable` и `notRetryable` или более конкретную политику.

В коде: агент помечает сбой хода `data.codelab.retryable` по `LlmErrorClass` (`network`, `timeout`, `rateLimited`, `server`; `_retryable` в `event_projection.dart`), клиент выводит `SessionView.canRetry` из `PromptFailure` и состояния сессии (`_canRetry` в `client_workspace.dart`, spec `acp-client-kit` «Повтор сорвавшегося хода»).

---

## 30. Не повторять всё подряд

ЗАПРЕЩЕНО автоматически повторять при:

* отказе в разрешении;
* некорректном сообщении протокола;
* неподдерживаемой версии;
* неверном пользовательском вводе;
* ошибке программиста.

У повтора ДОЛЖНО быть смысловое основание.

В коде `withTransientRetry` ядра агента никогда не повторяет `aborted`, `overflow`, `auth`, `badRequest`, `terminalFinish` и ничего после фиксации ответа (LLM-8, LLM-9); у клиента автоматических повторов запросов ACP нет.

---

## 31. Контекст повтора

Повтор ДОЛЖЕН сохранять контекст корреляции, например:

```text
request_id
attempt
generation
failure_type
```

---

## 32. Исчерпание повторов

После исчерпания политики повторов ДОЛЖЕН возникать явный терминальный исход, например `ReconnectExhausted`, а не бесконечный цикл повторов.

В коде: у ядра агента итоговая ошибка `withTransientRetry` несёт историю попыток и становится `AgentError(retrying: false)` → `TurnEnded(failed)`. У клиента политики повторов переподключения нет (§79), поэтому нет и `ReconnectExhausted`.

---

## 33. Таймаут

Таймаут — отдельная причина сбоя.

СЛЕДУЕТ различать:

* таймаут подключения транспорта;
* таймаут запроса;
* таймаут разрешения;
* таймаут завершения работы.

У них разная семантика восстановления.

В коде: `AcpRequestTimeoutException` — таймаут исходящих запросов клиента (`requestTimeout`, по умолчанию 60 с; `session/prompt` без таймаута); `AcpTransport.close({timeout})` — завершение; `ClientTimedOut` — запросы агента к клиенту (`fs/*` 30 с, `terminal/kill` 10 с, `13-acp-adapter.md` §13.9); `session/request_permission` таймаута по умолчанию не имеет (ждёт человека; `permissions.timeout` конфигурации агента включает его); `AcpTransportErrorCode.timeout` и `LlmErrorClass.timeout`.

---

## 34. Отмена — не всегда ошибка

Отмена по просьбе пользователя обычно — нормальный исход жизненного цикла, а не `error`.

Например, `RequestCancelled` НЕ СЛЕДУЕТ автоматически журналировать на уровне error.

В коде отменённый ход завершается `stopReason: cancelled` (статус `cancelled`, не `failed`), отмена журналируется на уровне info (`Cancelled prompt turn …`).

---

## 35. Отказ в разрешении — не падение

Отказ в разрешении — ожидаемый исход приложения.

Он ДОЛЖЕН быть:

* типизирован;
* обработан;
* при необходимости показан пользователю;

и НЕ ДОЛЖЕН считаться неожиданным исключением.

В коде: решения `PermissionDecision` ядра агента (`rejectOnce`, `rejectAlways`, `cancelled`), у клиента — `ApprovalStatus` одобрения.

---

## 36. Устаревшее событие — не обязательно ошибка

Устаревшее событие после переподключения может быть ожидаемым следствием конкурентности.

Обычно «проигнорировать и записать debug/warning» лучше, чем фатальная ошибка. Если устаревшее событие нарушает гарантию ACP, серьёзность может быть выше.

В коде — запись `event_ignored` (`reason: stale_generation`) на уровне debug (`streaming.md` §6).

---

## 37. Дублирующее событие

Дублирующее событие тоже не обязательно сбой. Если реплей разрешён, устранение дублей — нормальное поведение.

---

## 38. Состояние ошибки для отображения

Presentation ДОЛЖЕН получать нормализованное состояние ошибки.

Иллюстрация:

```text
SessionErrorViewState(
  title,
  description,
  canRetry,
)
```

Это модель отображения, а не исключение транспорта.

В коде этой роли служат `ConnectionView.lost`/`failed`, заметки транскрипта `NoticeItem` с `NoticeReason` и `SessionView.canRetry`.

---

## 39. Сообщение для пользователя

Сообщение для пользователя ДОЛЖНО:

* быть понятным;
* описывать действие и последствие;
* не раскрывать внутренний стек вызовов;
* не раскрывать секреты;
* по возможности предлагать действие для восстановления.

---

## 40. Не показывать `toString()`

ЗАПРЕЩЕНО использовать

```dart
Text(error.toString())
```

как общий способ показа ошибок в production.

Текст технического исключения может:

* быть непонятным;
* содержать пути;
* содержать детали реализации;
* содержать чувствительные данные.

В коде ядро клиента даёт текст для UI и CLI через `describeFailure`: поле `message` известных исключений вместо `ClassName: message`, после `SecretRedactor.redactText`. Для прочих объектов используется `toString()` после той же редакции.

`describeFailure` — текст **для пользователя**. Для журнала при базовой политике `metadataOnly` текст ошибки агента не используется: запись о сбое строится через `describeFailureMetadata` (класс, код JSON-RPC и его стандартное имя, код транспортной ошибки) — `observability.md` §48а, change `redesign-protocol-pane` D3.

---

## 41. Технические подробности

UI МОЖЕТ предоставлять отдельный раскрываемый раздел диагностики в debug-сборке или в одобренном продуктом сценарии.

Например:

```text
Connection to agent was lost.

[Retry]

Technical details:
Transport closed unexpectedly.
```

Технические подробности ДОЛЖНЫ проходить очистку (sanitization).

---

## 42. Коды ошибок

Для поддержки и диагностики полезны стабильные коды ошибок, например:

```text
ACP_PROTOCOL_UNSUPPORTED
ACP_CONNECTION_LOST
ACP_RECONNECT_EXHAUSTED
PERMISSION_DENIED
```

Код ошибки НЕ ДОЛЖЕН заменять типизированную модель ошибок внутри Dart.

В коде строковых кодов такого вида нет. Стабильные коды — перечисления (`AcpTransportErrorCode`, `ConnectionFailureReason`, `AcpProtocolErrorKind`, `FileErrorCode`, `ExecErrorCode`, `LlmErrorClass`), числовые коды JSON-RPC и ACP на проводе и поля расширения CodeLab `data.codelab.errorClass` и `data.codelab.reason`.

---

## 43. Локализация

Текст ошибки для пользователя НЕ СЛЕДУЕТ хранить внутри низкоуровневого типа сбоя, если приложение поддерживает локализацию.

Лучше:

```text
Failure
   ↓
преобразование в presentation
   ↓
локализованное сообщение
```

В CodeLab эта граница реализована change [`add-desktop-localization`](../../openspec/changes/archive/2026-11-20-add-desktop-localization/design.md) (D5, D6; правила — `layers-and-dependencies.md` §54):

* **Ядро клиента** (`codelab_client_core`, `codelab_client_acp`) отдаёт типизированную причину и сбой: `PromptFailure`, `ProfileDraftIssueCode`, sealed-результаты `ProfileCommitter`, причина заметки транскрипта `NoticeReason` (spec `acp-client-kit` «Типизированная причина заметки транскрипта»). Английские `text`/`message` ядра остаются для CLI и диагностики; `intl` в ядре клиента запрещён сторожем.
* **App** строит переведённый текст по варианту и коду (`context.l10n`) и НЕ ДОЛЖЕН разбирать английскую строку ядра. Не хватает данных — ядро получает аддитивное типизированное поле.
* **Разовое сообщение об ошибке или исходе** (ошибка записи конфига, отказ подключения, исход удаления) хранится в состоянии Cubit-а типизированным значением с аргументами, а не готовой строкой: текст собирает presentation, поэтому при смене языка он пересобирается.
* **Не переводятся** (D7): тексты ошибок от агента и бэкендов (тело `PromptFailure`, причина хранилища секретов), диагностика (`WorkspaceDiagnostic.message`, `ClientWorkspaceException.message`, «Debug log», «Inspector»), события журнала. Они подставляются в переведённую фразу плейсхолдером как есть (§99 — диагностическое сообщение и сообщение пользователю).
* Текст исключения пользователю не показывается и в переводимые сообщения не попадает; в журнал пишется только `runtimeType` (`observability.md`).

---

## 44. Обработка ошибок в BLoC/Cubit

BLoC или Cubit ДОЛЖЕН:

* вызвать API приложения;
* получить типизированный сбой;
* преобразовать его в состояние или эффект отображения.

BLoC/Cubit НЕ ДОЛЖЕН знать о:

* `SocketException`;
* `ProcessException`;
* сырых ошибках разбора ACP;

если граница приложения уже обязана их нормализовать.

В CodeLab это Cubit-ы `apps/codelab_desktop` поверх `ClientWorkspace` (`state-management.md`).

---

## 45. try/catch в BLoC/Cubit

НЕ СЛЕДУЕТ повторять во всех обработчиках

```dart
try {
  await client.doSomething();
} catch (e) {
  emit(ErrorState(e.toString()));
}
```

Стратегия обработки ошибок ДОЛЖНА быть согласованной.

---

## 46. Состояние ошибки и разовый эффект

Некоторые ошибки — долговременное состояние, например «сессия сорвалась». Другие — разовый эффект отображения, например «не удалось скопировать текст».

НЕ СЛЕДУЕТ превращать каждую мелкую ошибку операции в глобальное состояние ошибки экрана.

---

## 47. Частичный сбой

Операция одной функции может сорваться, пока остальное состояние приложения остаётся корректным.

Например:

```text
session = ready
historySave = failed
```

НЕ СЛЕДУЕТ переводить всю сессию в состояние сбоя, если сбой локальный.

---

## 48. Агрегированные сбои

Если операция выполняет несколько независимых действий, может понадобиться агрегированный результат.

Но НЕ СЛЕДУЕТ делать общий `List<Exception>` API приложения. У агрегации ДОЛЖНА быть понятная семантика.

---

## 49. Ошибки проверки

Сбой проверки (validation) — ожидаемый исход.

СЛЕДУЕТ различать проверку в presentation, проверку в приложении и проверку протокола: они принадлежат разным границам.

---

## 50. Проверка пользовательского ввода

Простая проверка в UI может оставаться задачей presentation — например, пустое поле или неверный формат локального пути.

Но ограничения безопасности и приложения ДОЛЖНЫ проверяться ниже UI.

---

## 51. Проверка протокола

Проверка протокола охватывает:

* схему;
* типы;
* обязательные поля;
* инварианты протокола.

Она НЕ ДОЛЖНА определять политику разрешений приложения.

---

## 52. Сбои безопасности

Сбой безопасности ДОЛЖЕН закрывать доступ (fail closed).

Например, внутреннее исключение подсистемы разрешений НЕ ДОЛЖНО приводить к автоматическому разрешению.

Предпочтительно:

```text
ошибка политики
    ↓
операция отклонена
    ↓
неожиданный сбой записан в журнал
```

В коде: без `PermissionGate` любое «спросить» становится отказом (PERM-5); сбой запроса `session/request_permission` у ACP-проекции агента (ошибка клиента, неверный ответ) даёт `rejectOnce` и предупреждение `acp.permission.failed` (`_failed` в `acp_permission_gate.dart`).

---

## 53. Ошибки хранения

СЛЕДУЕТ различать:

* данные недоступны;
* данные повреждены;
* сбой миграции;
* сбой записи;
* конфликт устаревшей записи.

НЕ СЛЕДУЕТ представлять всё одним `StorageException`, если восстановление различается.

---

## 54. Повреждённые сохранённые данные

У повреждения данных ДОЛЖНА быть явная политика восстановления.

Варианты:

* отклонить;
* восстановить резервную копию;
* сбросить затронутые данные;
* спросить пользователя.

ЗАПРЕЩЕНО молча игнорировать повреждение, если это ведёт к потере данных.

В коде: неразбираемый снимок рабочего пространства сбрасывается с предупреждением `Workspace snapshot is invalid; starting fresh.` (`WorkspaceRestorer._readProject`); резервных копий хранилища не делают.

---

## 55. Ошибки платформы

Ошибки, зависящие от платформы, ДОЛЖНЫ нормализоваться до кроссплатформенной семантики там, где это возможно.

Например:

```text
Windows credential error
macOS keychain error
Linux keyring error
        │
        ▼
CredentialStoreFailure
```

---

## 56. Неподдерживаемая возможность

Неподдерживаемая возможность ДОЛЖНА иметь типизированное представление, например `CapabilityUnavailable`. Это лучше общего исключения.

Presentation может отключить действие или показать пояснение.

---

## 57. Контекст ошибки

Сбой может содержать структурированный контекст:

```text
sessionId
requestId
operation
reason
```

Но контекст НЕ ДОЛЖЕН без необходимости превращаться в произвольный `Map<String, dynamic>`.

---

## 58. Чувствительный контекст

Объекты сбоев НЕ ДОЛЖНЫ бесконтрольно хранить:

* токен;
* учётные данные;
* полный промпт;
* полное содержимое файла.

Иначе они могут случайно попасть в журналы или отчёты о падениях.

---

## 59. Журналирование ожидаемого сбоя

Ожидаемый сбой СЛЕДУЕТ журналировать на подходящем уровне:

```text
отказ в разрешении              → info/debug
временная потеря соединения     → warning
неожиданное нарушение инварианта → error
```

В коде любой `AcpTransportFailure`, включая обрыв соединения, записывается в диагностику клиента с `DiagnosticSeverity.error` (`_handleTransportEvent`). На тот же обрыв `ClientWorkspace` пишет вторую запись уровня error `Connection to ACP agent lost` — это ещё и дубль (§60).

---

## 60. Не журналировать одну ошибку в каждом слое

НЕ СЛЕДУЕТ для одной причины писать:

```text
transport: ERROR
client: ERROR
bloc: ERROR
widget: ERROR
```

Лучше:

```text
транспорт
    → технический сбой + стек вызовов

клиент
    → переход и восстановление приложения

presentation
    → состояние, видимое пользователю
```

---

## 61. Корреляция ошибок

Ошибка ДОЛЖНА сохранять связь с операцией, в которой возникла.

При наличии СЛЕДУЕТ использовать:

* `session_id`;
* `request_id`;
* `message_id`;
* `tool_call_id`;
* `connection_generation`;
* `operation_id`.

Это особенно важно для конкурентных операций.

В коде клиент привязывает корреляцию через `Logger.withCorrelation` и параметры `_recordDiagnostic` (`sessionId`, `requestId`, `toolCallId`); у агента записи о вызове инструмента несут `session_id`, `turn_id`, `tool_call_id` (OBS-3).

---

## 62. Корреляция после преобразования

При преобразовании

```text
TransportFailure
      │
      ▼
SessionConnectionLost
```

контекст корреляции НЕ ДОЛЖЕН теряться.

Слой приложения ДОЛЖЕН иметь возможность определить:

```text
какая сессия потеряла соединение
какое поколение завершилось
был ли активный запрос
```

---

## 63. Идентичность ошибки

НЕ СЛЕДУЕТ использовать текст сообщения как идентичность ошибки.

Плохо:

```dart
if (error.message == 'Connection closed') {
  reconnect();
}
```

Предпочтительно:

```dart
switch (failure) {
  case ConnectionLost():
    ...
}
```

или другой типизированный механизм.

В коде есть ветвления по тексту:

* `AcpClientExecutionEnv` ищет `timed out` в сообщении `FileError`, которое сам сформировал из `ClientTimedOut` (`codelab_agent_acp/lib/src/acp_client_env.dart`) — типизированная альтернатива возможна;
* сравнение диагностики с константой сообщения: `agent_definition_row_view.dart` в `codelab_setup` (`agentDefinitionModelNotInCatalogMessage`, осознанное решение D18 change `add-settings-agents-modes`) и `secret_migrator.dart` в `codelab_agent_io` (`providerKeySourcesConflictMessage`, префикс `untrustedProjectWritePrefix`);
* подсказка к тексту ошибки провайдера по `prompt_cache_key` (`codelab_agent_core/lib/src/llm/providers/http_support.dart`);
* разбор сообщений внешних библиотек без типизированной альтернативы — `YamlException` (`codelab_agent_io/lib/src/config/yaml_reader.dart`) и `ArgParserException` (`apps/codelab_cli/lib/src/cli_args.dart`).

---

## 64. Коды ошибок и типизированные ошибки

Стабильный код ошибки может быть частью типизированного сбоя.

Концептуально:

```text
ConnectionLost
    code = ACP_CONNECTION_LOST
```

Типизированный класс использует логика приложения. Код используется для:

* диагностики;
* поддержки;
* телеметрии;
* внешнего представления.

---

## 65. Равенство ошибок

Если сбой хранится как неизменяемое состояние, равенство ДОЛЖНО быть предсказуемым.

НЕ СЛЕДУЕТ без необходимости включать в равенство изменяемые или случайные технические объекты. Например, стек вызовов обычно НЕ ДОЛЖЕН определять смысловое равенство состояния отображения.

---

## 66. Иерархия сбоев

НЕ СЛЕДУЕТ создавать одну гигантскую иерархию всех ошибок приложения, если предметные области независимы.

Предпочтительно иметь ограниченные семейства

```text
ProtocolFailure
TransportFailure
SessionFailure
PermissionFailure
FileFailure
CredentialFailure
```

в соответствующих пакетах.

---

## 67. Общий `AppFailure`

Один общий тип

```dart
class AppFailure {
  final String message;
}
```

обычно слишком слаб для решений приложения.

Если используется общий базовый тип, конкретные типы сбоев ДОЛЖНЫ сохранять семантику.

---

## 68. Владелец типа сбоя

Тип сбоя ДОЛЖЕН находиться рядом с границей, контракт которой он представляет.

Иллюстрация:

```text
codelab_acp_protocol
    → ProtocolFailure

codelab_acp_transports
    → TransportFailure

codelab_client_acp
    → SessionFailure / ClientFailure

адаптер платформы
    → FileAccessFailure
```

В коде:

```text
codelab_acp_protocol    → AcpProtocolError, JsonRpcProtocolException, JsonRpcError
codelab_acp_transports  → AcpTransportException, AcpTransportErrorCode
codelab_client_acp      → AcpClientApplicationException и наследники, PromptFailure,
                          FsAccessFailure, TerminalAccessFailure, StateTransitionException
codelab_client_core     → ClientWorkspaceException, ConnectionView, PromptOutcome
codelab_agent_core      → Result, FileError, ExecError, LlmErrorClass, AgentError,
                          ConfigException, HostWiringException
codelab_agent_acp       → AcpRequestError, ClientCallFailure
```

НЕ СЛЕДУЕТ складывать все типы сбоев в глобальный `errors.dart` только ради централизации.

---

## 69. `core` и ошибки

Общий пакет `core` МОЖЕТ содержать только действительно сквозные примитивы ошибок, например:

* общую абстракцию результата;
* общий маркер отмены;
* общие метаданные ошибок.

Сбои конкретной функции НЕ СЛЕДУЕТ переносить в `core`.

В коде общего пакета `core` нет: `codelab_client_core` — клиентский слой, а не сквозной; `Result` и `CancelledException` живут в `codelab_agent_core`, `lib/core/` app держит адаптеры платформы.

---

## 70. Публичный API

Если сбой — часть публичного API пакета, он ДОЛЖЕН быть:

* типизирован;
* документирован;
* достаточно стабилен для потребителей;
* экспортирован через публичный API пакета.

Потребитель из другого пакета НЕ ДОЛЖЕН импортировать `src/errors/...`.

---

## 71. Внутренние ошибки

Ошибка, нужная только реализации, МОЖЕТ оставаться приватной или внутренней.

НЕ СЛЕДУЕТ делать публичным каждое техническое исключение. Публичный API ДОЛЖЕН показывать только ошибки, которые потребитель способен осмысленно обработать.

---

## 72. Контракт асинхронной операции

У публичного асинхронного API ДОЛЖНА быть понятная семантика ошибок.

Потребитель ДОЛЖЕН понимать:

```text
какие сбои ожидаемы
какие исходы терминальны
можно ли повторить
можно ли отменить
```

Перечислять все исключения-ошибки программиста не обязательно.

---

## 73. Контракт ошибок потока

Для долгоживущих потоков СЛЕДУЕТ решить, как представлены ошибки:

### Через канал ошибок потока

```text
stream.addError(...)
```

### Через типизированное событие или состояние приложения

```text
ClientEvent.connectionFailed(...)
```

Для сложного жизненного цикла часто предпочтительнее типизированное событие или состояние: ошибка потока может завершить подписку.

В коде выбран второй вариант: сбой транспорта — событие `AcpTransportEvent.failure` в `events`, сбой соединения — состояние в `connectionStateChanges`, исход хода — `PromptOutcome` в `ClientWorkspace.promptOutcomes`.

---

## 74. Критические потоки

Критический поток приложения НЕ ДОЛЖЕН случайно завершаться из-за восстановимой ошибки.

Например, потеря соединения может быть событием «→ reconnecting», а не обязательно «поток завершён навсегда».

---

## 75. Завершение потока

Если поток действительно терминальный, это ДОЛЖНО быть частью контракта. Потребитель ДОЛЖЕН знать, что после `done` новых событий не будет.

---

## 76. Ошибка после dispose

Ошибка операции, завершившейся после dispose владельца, НЕ ДОЛЖНА:

* публиковать состояние отображения;
* показывать диалог;
* запускать переподключение;
* создавать уведомление.

При этом неожиданную ошибку НЕ СЛЕДУЕТ терять полностью: её МОЖНО диагностировать на нижнем слое, который ею владеет.

---

## 77. Устаревший сбой

Сбой может устареть так же, как успешный результат.

Пример:

```text
запрос A начат
запрос B заменил A
запрос A поздно завершился сбоем
```

Сбой A НЕ ДОЛЖЕН переводить UI запроса B в состояние ошибки.

---

## 78. Проверка поколения

Перед применением асинхронного сбоя к текущему состоянию СЛЕДУЕТ проверить:

* идентичность операции;
* идентичность сессии;
* поколение соединения;

если операция может устареть.

В коде: `_bindTransport` отбрасывает события транспорта прежнего поколения, `_requireCurrentGeneration` — ответы, пришедшие после замены транспорта (`streaming.md` §6).

---

## 79. Ошибка во время переподключения

Сбой отдельной попытки переподключения не обязательно терминальный.

Например:

```text
попытка 1 не удалась
    ↓
пауза (backoff)
    ↓
попытка 2
```

Presentation может оставаться в состоянии `reconnecting`, пока политика не исчерпана.

В коде политики повторов переподключения нет: `reconnect()` — одна попытка текущего профиля, после неудачи — `ConnectionView.failed` (spec `acp-client-kit` «Явный автомат соединения»; `ConnectionView.reconnecting.attempt` всегда 1). Введение повторов требует OpenSpec change.

---

## 80. Переподключение исчерпано

После исчерпания ДОЛЖЕН возникать явный терминальный сбой приложения, например:

```text
ReconnectExhausted(
  attempts: 5,
  lastFailure: ...
)
```

Конкретную модель определяет реализация. В коде её нет (§79).

---

## 81. Ошибка во время завершения работы

Ожидаемые ошибки, вызванные намеренным завершением работы, НЕ СЛЕДУЕТ ошибочно считать сбоями приложения.

Например, «поток закрыт», «процесс завершён», «подписка отменена» во время управляемого завершения могут быть нормальным жизненным циклом.

---

## 82. Контекст завершения работы

Жизненный цикл ДОЛЖЕН позволять отличить

```text
неожиданное завершение процесса
```

от:

```text
завершения процесса, потому что приложение закрывается
```

Иначе приложение может случайно запустить переподключение при закрытии.

В коде `StdioAcpTransport` после начала `close` (`_isClosed`) не публикует сбой завершения процесса; неожиданный выход даёт `AcpTransportErrorCode.disconnected`.

---

## 83. Ошибка при очистке ресурсов

Ошибка очистки ДОЛЖНА быть диагностируемой.

Например, сбой закрытия одного ресурса НЕ ДОЛЖЕН автоматически мешать очистке остальных.

Концептуально:

```text
закрыть подписку
закрыть транспорт
завершить процесс
освободить контейнер
```

СЛЕДУЕТ попытаться выполнить полностью, сохраняя ошибки.

В коде так устроено завершение app: каждый шаг идёт через `_step`, сбой шага пишется в журнал `app.shutdown_step_failed` с типом ошибки и не мешает следующим (`apps/codelab_desktop/lib/app/app_scope.dart`).

---

## 84. Несколько сбоев очистки

Если завершение работы порождает несколько сбоев, диагностику МОЖНО агрегировать.

Но интерфейс для пользователя обычно ДОЛЖЕН показывать осмысленный общий исход, а не список внутренних исключений.

---

## 85. Плавная деградация

Если необязательная подсистема сломалась, приложение может продолжить работу.

Например, «уведомления рабочего стола недоступны» не обязательно означает «ACP-клиент непригоден».

Серьёзность сбоя ДОЛЖНА соответствовать важности возможности.

---

## 86. Сбой обязательной зависимости

Если недоступна обязательная подсистема — например, ACP-транспорт не запускается, — приложение ДОЛЖНО перейти в явное состояние «недоступно» или «сбой».

НЕ СЛЕДУЕТ продолжать в частично инициализированном состоянии без определённой семантики.

---

## 87. Ошибки инициализации

У инициализации ДОЛЖЕН быть отдельный путь сбоя.

Например:

```text
initializing
    │
    ├── ready
    └── initializationFailed
```

НЕ СЛЕДУЕТ выдавать сбой инициализации за `disconnected`, если приложение ещё не было корректно инициализировано.

В коде `ClientConnectionState.initializing` переходит в `ready` или `failed`; выход агента во время `initialize` сразу снимает ожидающий запрос, не дожидаясь таймаута.

---

## 88. Ошибки конфигурации

Неверная конфигурация ДОЛЖНА отличаться от сбоя транспорта во время работы.

Например, `AgentExecutableNotConfigured`, `InvalidAgentArguments`, `UnsupportedConfiguration` могут требовать действия пользователя, а не повтора.

В коде: `UnsupportedConnectionProfileException` (нет резолвера для профиля), `ProfileDraftIssueCode` черновика профиля, у агента — `ConfigIssue`/`ConfigException` до старта транспорта (бинарь завершается с кодом `64`, `12-observability-and-errors.md` §12.2).

---

## 89. Ошибки с действием

Если пользователь может исправить проблему, presentation ДОЛЖЕН по возможности предложить действие.

Например:

```text
Agent executable not found.

[Choose executable]
```

или:

```text
Connection lost.

[Retry]
```

Действие ДОЛЖНО соответствовать семантике типизированного сбоя.

---

## 90. Ошибки без действия

Если повтор бессмыслен, UI НЕ ДОЛЖЕН показывать ложную кнопку Retry.

Например, несовместимая версия протокола может требовать обновить клиент или агента, но не повторить немедленно тот же запрос.

---

## 91. `canRetry`

`canRetry` может быть проекцией типизированного сбоя в presentation.

НЕ СЛЕДУЕТ хранить его как независимый источник истины, если возможность повтора определяется типом сбоя и политикой.

В коде `SessionView.canRetry` вычисляется при каждой публикации (`_canRetry`): повтор запрещён при `PromptFailure.connectionLost` и `AgentPromptFailure(retryable: false)`, при идущем или отменяемом ходе и без соединения.

---

## 92. Действие повтора

Presentation выражает намерение — `RetryRequested`. Слой приложения решает, какую операцию действительно повторить.

Виджет НЕ ДОЛЖЕН вручную повторять низкоуровневый вызов транспорта.

В коде намерение — `retry()` сессии `ClientWorkspace`: она повторяет промпт последнего сорвавшегося хода или бросает `ClientWorkspaceException`, если повторять нечего.

---

## 93. Состояние восстановления

Если восстановление занимает время, у него ДОЛЖНО быть явное состояние.

Например:

```text
failed
  ↓ retry
retrying
  ↓
ready
```

а не:

```text
failed
  ↓
сразу делаем вид, что ready
```

---

## 94. История ошибок

НЕ СЛЕДУЕТ хранить в состоянии приложения бесконечную историю всех сбоев. Для диагностики служит подсистема наблюдаемости.

Состояние приложения ДОЛЖНО хранить только данные, нужные текущему поведению и UI.

---

## 95. Последняя ошибка

`lastError` МОЖНО использовать, если его семантика понятна.

Но СЛЕДУЕТ избегать общего глобального

```dart
Object? lastError;
```

на всё приложение.

---

## 96. Сброс ошибки

ДОЛЖНО быть определено, когда ошибка перестаёт быть актуальной.

Например:

```text
отправка не удалась
    ↓
новая отправка успешна
    ↓
старая ошибка отправки сброшена
```

Старая ошибка НЕ ДОЛЖНА продолжать влиять на несвязанную операцию.

---

## 97. Разовое уведомление об ошибке

Для локальной недолговременной ошибки МОЖЕТ использоваться эффект отображения: «Copy failed → показать уведомление». Менять основное состояние экрана не обязательно.

---

## 98. Граница локализации ошибок

Низкоуровневый пакет НЕ ДОЛЖЕН формировать окончательный локализованный текст для пользователя.

Например,

```dart
throw TransportFailure(
  userMessage: 'Не удалось подключиться к агенту',
);
```

создаёт связь с presentation. Лучше передать типизированную причину.

В коде app строит текст заметок по `NoticeReason` и `PromptFailure`, а английский `NoticeItem.text` остаётся только запасным текстом (`transcriptRowsOf` в `apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart`; §43).

---

## 99. Диагностическое сообщение и сообщение пользователю

СЛЕДУЕТ различать `diagnosticMessage` и `userMessage`.

Первое может содержать технический контекст после очистки. Второе ДОЛЖНО быть понятно пользователю.

---

## 100. Ошибки, чувствительные для безопасности

Ошибка безопасности НЕ ДОЛЖНА раскрывать лишнюю информацию.

Например, сбой аутентификации НЕ ДОЛЖЕН показывать секрет, токен или внутренние детали хранилища учётных данных.

В коде: `AcpWebSocketHandshakeRejected` несёт только HTTP-статус, без URL, заголовков и токена; тексты клиента проходят `SecretRedactor` (`describeFailure`, `_recordDiagnostic`); ошибки провайдера у агента вычищаются от `ProviderConfig.secrets` (`redactSecrets`, OBS-2).

---

## 101. Сбой политики разрешений

Если подсистема разрешений неожиданно сломалась (исключение при оценке), опасная операция ДОЛЖНА быть отклонена.

При этом неожиданное исключение ДОЛЖНО попасть в диагностику.

В коде — §52.

---

## 102. Некорректное сообщение ACP

Некорректное сообщение ДОЛЖНО:

1. Создать ошибку уровня протокола.
2. Получить контекст корреляции, если его можно безопасно извлечь.
3. Быть записано в журнал.
4. Привести к определённому поведению протокола или приложения.

ЗАПРЕЩЕНО просто

```dart
catch (_) {
  return null;
}
```

и продолжать, будто сообщения не было.

В коде стороны поступают по-разному. Клиентский транспорт считает некорректный кадр агента нарушением протокола: `AcpTransportException(protocolViolation)` с причиной и стеком, соединение переходит в `failed` (`StdioAcpTransport._handleStdoutLine`, `WebSocketAcpTransport`). Серверный транспорт агента соединение не рвёт: отвечает `-32700` или `-32600` и сообщает о кадре диагностикой (`decodeServerFrame`, ACP-4).

---

## 103. Неизвестный метод

Неизвестный метод обрабатывается по политике совместимости ACP.

Возможные исходы:

* игнорировать;
* ошибка протокола;
* событие «не поддерживается»;
* сбой соединения или сессии.

Решение НЕ ДОЛЖНО приниматься в presentation.

В коде клиент отвечает на неизвестный запрос агента `-32601 Method not found` (JSON-RPC требует ответа на каждый запрос, `15-Extensibility.md`) и журналирует только метод и id; неизвестные уведомления пропускаются. Агент отвечает `AcpRequestError.methodNotFound`.

---

## 104. Недопустимый переход состояния

Попытка выполнить операцию в недопустимом состоянии ДОЛЖНА давать типизированный исход.

Например, `sendPrompt` без соединения НЕ ДОЛЖЕН приводить к случайному исключению `null` или `late`.

В коде редьюсеры возвращают `StateTransitionResult` (`applied`, `ignored`, `rejected`), отказ доходит до вызывающего `StateTransitionException`; `ClientWorkspace` отклоняет вызов в неподходящем состоянии `ClientWorkspaceException`.

---

## 105. Предусловия

API приложения МОЖЕТ проверять предусловия до побочного эффекта.

Например:

```text
сессия должна быть готова
запрос не должен быть уже активен
вызов инструмента должен ещё ждать решения
```

Невыполненное предусловие — ожидаемый исход приложения.

---

## 106. Утверждения

`assert` МОЖНО использовать для инвариантов разработчика, но не для проверки внешних, пользовательских или протокольных данных: в release утверждения могут быть отключены.

ЗАПРЕЩЕНО использовать

```dart
assert(userInputIsValid);
```

как единственную защиту поведения в production.

---

## 107. Исчерпывающая обработка

Для sealed-типов сбоев СЛЕДУЕТ предпочитать исчерпывающую обработку там, где вызывающий обязан учесть все случаи.

Sealed-классы и `freezed` помогают проверке компилятором.

---

## 108. Ветка `default`

НЕ СЛЕДУЕТ добавлять широкую ветку `default`, которая скрывает новый тип сбоя, критичный для безопасности или протокола.

Например,

```dart
default:
  return retry();
```

может стать опасной после добавления нового сбоя без повтора.

---

## 109. Развитие модели ошибок

При добавлении нового типа сбоя СЛЕДУЕТ проверить:

* обработчики приложения;
* политику повторов;
* преобразование в BLoC/Cubit;
* наблюдаемость;
* тесты;
* отображение пользователю.

Типизированная модель ошибок ДОЛЖНА развиваться контролируемо.

---

## 110. Совместимость публичных ошибок

Изменение публичного типа сбоя в переиспользуемом пакете может быть несовместимым изменением API.

Если изменение архитектурно значимо, потребители ДОЛЖНЫ учитываться через OpenSpec change или ADR.

---

## 111. Тестирование обработки ошибок

Обработка ошибок ДОЛЖНА иметь прямые тесты.

Минимальные категории:

* ожидаемый сбой;
* неожиданное исключение;
* преобразование;
* сбой с повтором;
* терминальный сбой;
* устаревший сбой;
* отмена;
* отказ в разрешении;
* ошибка протокола;
* ошибка транспорта.

---

## 112. Тесты преобразования

СЛЕДУЕТ тестировать осмысленные преобразования, например «`ProcessExited` неожиданно → `ConnectionLost`».

Тестировать тривиальное оборачивание в конструктор не нужно.

---

## 113. Тесты повторов

Проверять:

* ошибка с повтором запускает повтор;
* ошибка без повтора его не запускает;
* исчерпание повторов терминально;
* ручное отключение останавливает повторы.

---

## 114. Тесты устаревших ошибок

Обязательный сценарий гонки:

```text
операция A начинается
операция B заменяет A
A поздно завершается сбоем
```

Состояние B НЕ ДОЛЖНО перейти в сбой из-за A.

---

## 115. Тесты отображения

Тесты BLoC/Cubit и presentation ДОЛЖНЫ проверять

```text
типизированный сбой
    ↓
верное состояние или действие UI
```

НЕ СЛЕДУЕТ воспроизводить в этих тестах низкоуровневое исключение.

---

## 116. Тесты ошибок безопасности

Минимум:

* ошибка подсистемы разрешений → отказ;
* секрет не попадает в сообщение пользователю;
* секрет не попадает в журнал;
* неизвестная опасная возможность не одобряется автоматически.

---

## 117. Тесты наблюдаемости

Неожиданное исключение ДОЛЖНО сохранять:

* тип ошибки;
* стек вызовов;
* контекст корреляции.

Ожидаемый сбой приложения НЕ ДОЛЖЕН ошибочно попадать в отчёты как падение.

---

## 118. Нежелательные паттерны

### `catch (e) => Error(e.toString())`

```dart
try {
  ...
} catch (e) {
  emit(ErrorState(e.toString()));
}
```

теряет семантику и может раскрыть технические подробности.

---

### Общий `Exception`

```dart
throw Exception('failed');
```

для ожидаемого исхода приложения.

---

### Молчаливый catch

```dart
catch (_) {}
```

для значимой операции.

---

### Повтор всего подряд

```dart
catch (_) {
  retry();
}
```

опасен.

---

### Сообщение пользователю в инфраструктуре

```dart
throw FileFailure('Не удалось открыть файл');
```

если строка — задача presentation или локализации.

---

### Текст ошибки как управление потоком

```dart
if (e.toString().contains('closed')) {
  reconnect();
}
```

ЗАПРЕЩЕНО.

---

### Сырое исключение в состоянии BLoC/Cubit

```dart
class ErrorState {
  final Object error;
}
```

как основной контракт отображения.

В коде `PromptFailed.error` (`codelab_client_core/lib/src/queue/prompt_queue.dart`) — `Object`: исключение `codelab_client_acp` как есть, без типизированного сбоя.

---

### Журнал и повторный throw везде

```text
слой A пишет в журнал
слой B пишет в журнал
слой C пишет в журнал
```

создаёт дублирующий шум.

---

## 119. Чек-лист при добавлении сбоя

Перед добавлением нового типа сбоя агент ОБЯЗАН определить:

1. Какой слой владеет сбоем?
2. Это ожидаемый исход или неожиданное исключение?
3. Должен ли вызывающий его обрабатывать?
4. Восстановим ли он?
5. Можно ли его повторить?
6. Терминален ли он для текущей операции?
7. Как он влияет на состояние жизненного цикла?
8. Как он показывается в presentation?
9. Какие поля корреляции нужны?
10. Есть ли чувствительный контекст?
11. Как он журналируется?
12. Какие тесты нужны?

---

## 120. Чек-лист при `catch`

Перед добавлением `catch` определить:

1. Почему исключение ловится именно здесь?
2. Может ли этот слой восстановиться?
3. Меняется ли семантика ошибки?
4. Нужно ли сохранить причину?
5. Нужно ли сохранить стек вызовов?
6. Нужно ли журналировать?
7. Не будет ли ошибка записана в журнал ещё раз выше?
8. Может ли результат устареть?
9. Что увидит вызывающий?
10. Что увидит пользователь?

Если ответ только

> чтобы приложение не упало

СЛЕДУЕТ проверить, не стоит ли `catch` на неправильном уровне.

---

## 121. Чек-лист для ошибки, показываемой пользователю

Перед показом ошибки пользователю проверить:

1. Понятно ли, что произошло?
2. Понятно ли влияние на текущую работу?
3. Может ли пользователь что-то сделать?
4. Нужно ли показывать Retry?
5. Не раскрываются ли чувствительные данные?
6. Не показывается ли текст внутреннего исключения?
7. Не устарела ли ошибка?
