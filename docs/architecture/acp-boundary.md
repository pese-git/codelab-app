# Граница ACP

Документ задаёт архитектурную границу между протоколом ACP (Agent Client Protocol) и остальным кодом CodeLab — клиентами (desktop, CLI) и агентской стороной.

Цели:

* изолировать проводной протокол;
* сделать развитие протокола предсказуемым;
* не допускать утечки протокола в UI;
* держать прикладные модели стабильными;
* сделать логику ACP-клиента тестируемой;
* корректно обрабатывать ошибки;
* сохранять устойчивость к потоковым событиям, переподключению и смене версий.

Общие правила — корневой `AGENTS.md` (§2, §3.4, §5, §7, §9, §10, §16), [`layers-and-dependencies.md`](layers-and-dependencies.md), [`session-lifecycle.md`](session-lifecycle.md), [`streaming.md`](streaming.md), [`concurrency.md`](concurrency.md), [`permissions.md`](permissions.md), [`error-handling.md`](error-handling.md), [`observability.md`](observability.md), [`testing.md`](testing.md). Референсная спецификация ACP — `docs/protocols/acp/protocol/` (схема — `17-Schema.md`); её не меняют. Агентская сторона подробно — [`proposals/agent-core/13-acp-adapter.md`](proposals/agent-core/13-acp-adapter.md).

Термины:

* **Граница ACP** (ACP boundary) — место, где проводное представление протокола переводится в понятия приложения и обратно (§2).
* **Провод** (wire) — сообщения JSON-RPC в том виде, в каком их передаёт транспорт.
* **Протокольная модель** (protocol model, wire DTO) — типизированное представление сообщения ACP; отвечает на вопрос «как данные выглядят в ACP».
* **Прикладная модель** (application model) — что данные означают для клиента: сессия, ход, вызов инструмента, запрос разрешения.
* **Модель представления** (presentation model, view model) — форма данных, удобная конкретному экрану.
* **Преобразование** (mapping) — перевод модели одного уровня в модель другого (§8, §9).
* **Корреляция** (correlation) — привязка события или ответа к его сессии, запросу, вызову инструмента (§12).
* **Поколение соединения** (connection generation) — локальный номер экземпляра транспорта; растёт при каждой его замене (§13).
* **Утечка протокола** (protocol leakage) — протокольные детали в слоях выше границы (§39).
* **Обратная / прямая совместимость** (backward / forward compatibility) — работа с агентом старой / новой версии протокола (§21, §22).
* **Возможность** (capability) — функция, которую сторона объявляет при `initialize` (§32).
* **Кадр** (frame) — одно сообщение JSON-RPC; у клиента — также его проекция `ProtocolFrame` для показа (§35а).

Где в коде. Протокол `codelab_acp_protocol` (`packages/dart/codelab_acp_protocol/lib/src/`): конверт JSON-RPC — `JsonRpcMessage` (`JsonRpcRequest`, `JsonRpcNotification`, `JsonRpcResponse`), `JsonRpcId`, `JsonRpcError`, кодек `encodeJsonRpcMessage`/`decodeJsonRpcMessage` (`json_rpc/`); модели ACP на freezed (`acp/initialize.dart`, `session.dart`, `session_update.dart`, `prompt.dart`, `tool_call.dart`, `permission.dart`, `fs.dart`, `terminal.dart`; поле `_meta` хранится как `meta`), версия `ProtocolVersion`; реестр методов `acpMethodRegistry` (`AcpRequestMethod`, `AcpNotificationMethod`) и кодеки `encodeAcpParams`, `decodeAcpRequestParams`, `decodeAcpNotificationParams`, `decodeAcpResult` (`acp/acp_method_codec.dart`); проверка формы — `requireAcpObject`, `requireOnlyRootKeys`, `requireAcpCapabilityObject`, `tolerateUnknownRootFields` (`acp/acp_validation.dart`); незнакомый вид `session/update` — `unsupportedSessionUpdateKind`; ошибки — `JsonRpcProtocolException`, `AcpProtocolError` (`json_rpc/protocol_error.dart`). Транспорты `codelab_acp_transports`: `AcpTransport`, `AcpTransportEvent`, `AcpTransportException` с `AcpTransportErrorCode` (`lib/src/acp_transport.dart`), пара в памяти `InProcessAcpLink`; IO-транспорты из `lib/io.dart` — `StdioAcpTransport`, `WebSocketAcpTransport`, серверные `StdioServerAcpTransport`, `WebSocketServerAcpTransport`. Протокольный клиент `codelab_client_acp`: `AcpClientApplication` (`lib/src/application/acp_client_application.dart`) — маршрутизация входящих кадров (`_handleInboundMessage`), отсев прежнего поколения (`_bindTransport`), согласование версии и возможностей (`connect`), перевод протокольных событий в доменные модели `AcpSession`, `PromptTurn`, `ToolCallRecord`, `ApprovalRequest`, `ClientConnectionState` (`lib/src/domain/domain_models.dart`) через автоматы `state_machines.dart`; команды и use case-ы — `application_models.dart`, `use_cases.dart`; клиентские `fs/*` и `terminal/*` — порты `TextFileReader`, `TextFileWriter`, `TerminalProcessRunner` и containment `resolveWithinWorkingDirectory` (`domain/fs_access.dart`, `domain/terminal_access.dart`); расширения CodeLab — `codelabClientExtensionsMeta`, `CodelabExtensions` (`domain/codelab_extensions.dart`), `PromptFailure` (`domain/prompt_failure.dart`); кадры — `ProtocolFrame` и политика payload `ProtocolPayloadPolicy` (`application/protocol_frame.dart`), их строит `ProtocolFrameRecorder`. Ядро клиента `codelab_client_core`: порт `AgentBackend` (`lib/src/backend/agent_backend.dart`), `ClientWorkspace` и `SessionHandle` (`lib/src/workspace/client_workspace.dart`), проекции `SessionView`, `WorkspaceState` (`workspace_state.dart`), `ConnectionView` (`lib/src/connection/connection_view.dart`), `TranscriptProjector` и `TranscriptItem` (`lib/src/transcript/`), декодеры расширений usage `UsageDecoder` и `UsageLedgerDecoder` (`lib/src/usage/`), буфер кадров `ProtocolFrameLog` (`lib/src/protocol/protocol_frame_log.dart`). IO-адаптеры клиента `codelab_client_io`: `ioTransportResolver`, `IoTextFileIo`, `IoTerminalProcessRunner`. Агентская сторона `codelab_agent_acp`: `AcpAgentServer`, `AcpServerConfig` (`lib/src/agent_server.dart`), `InboundRouter`, `OutboundQueue`, `AcpRequestError` (`lib/src/connection/`), `AcpClientExecutionEnv`, `AcpPermissionGate`. Тестовые средства — `FakeAcpTransport` и корпус фикстур (`codelab_acp_testing`). Границы импорта и зависимостей проверяет сторож `codelab_architecture_tests` (`test/support/rules.dart`, `test/pubspec_allowlist_test.dart`).

---

## 1. Основной принцип

ACP — **внешняя граница протокола** (external protocol boundary).

Проводное представление ACP не является внутренней моделью всего приложения.

Основной входящий путь:

```text
Внешний агент
      │
      ▼
Транспорт
      │
      ▼
Сообщение ACP на проводе
      │
      ▼
codelab_acp_protocol
      │
      ▼
Ядро ACP-клиента
      │
      ▼
Понятия и состояние приложения
      │
      ▼
Преобразование для представления
      │
      ▼
Flutter UI
```

Исходящий путь:

```text
Flutter UI
      │
      ▼
Намерение пользователя или приложения
      │
      ▼
Ядро ACP-клиента
      │
      ▼
Протокольная команда или запрос
      │
      ▼
codelab_acp_protocol
      │
      ▼
Транспорт
      │
      ▼
Внешний агент
```

В CodeLab «ядро ACP-клиента» — `AcpClientApplication` (`codelab_client_acp`), «понятия и состояние приложения» — доменные модели `codelab_client_acp` и проекции `codelab_client_core` (`ClientWorkspace`, `SessionView`), «преобразование для представления» — мапперы и Cubit-ы `apps/codelab_desktop` (`features/workbench/application/ui_mappers.dart`) и экраны `apps/codelab_cli`. Встроенный агент отличается от внешнего только транспортом (`InProcessAcpLink`, §49).

---

## 2. Что относится к границе ACP

К границе ACP относятся:

* сообщения протокола;
* запрос и ответ (request/response);
* уведомления (notifications);
* идентификаторы методов;
* версия протокола;
* сериализация и десериализация;
* кадрирование транспорта (transport framing);
* идентификаторы корреляции;
* ошибки протокола;
* правила совместимости;
* неизвестные поля и сообщения;
* жизненный цикл транспорта.

Эти детали НЕ ДОЛЖНЫ бесконтрольно распространяться по слою представления.

---

## 3. Ответственность `codelab_acp_protocol`

Пакет:

`packages/dart/codelab_acp_protocol`

Отвечает только за вопросы уровня протокола.

МОЖЕТ содержать:

* проводные DTO;
* типизированные запросы;
* типизированные ответы;
* уведомления;
* имена и идентификаторы методов;
* сериализацию;
* десериализацию;
* проверку по схеме;
* типы версии протокола;
* ошибки уровня протокола.

НЕ ДОЛЖЕН содержать:

* BLoC;
* Flutter-виджеты;
* диалоги разрешений;
* навигацию;
* состояние представления;
* прикладной workflow;
* UX переподключения;
* визуальное состояние вызова инструмента.

В коде зависимости пакета — только `fpdart`, `freezed_annotation`, `json_annotation`, `meta` (`pubspec.yaml`); правила импорта для него в `rules.dart` сторожа нет — чистоту держит состав зависимостей.

---

## 4. Ответственность `codelab_acp_transports`

Пакет:

`packages/dart/codelab_acp_transports`

Отвечает за передачу протокольных данных.

МОЖЕТ содержать:

* stdio-транспорт;
* транспорт процесса;
* сокетный транспорт;
* потоковый транспорт;
* кадрирование транспорта;
* примитивы жизненного цикла соединения;
* сбои уровня транспорта.

Транспорт НЕ ДОЛЖЕН решать вопросы прикладной семантики.

Например:

```text
process exited
```

(процесс завершился) — событие транспорта.

А решение:

```text
reconnect session
```

(переподключить сессию) — поведение приложения.

В коде: основной барель `package:codelab_acp_transports/codelab_acp_transports.dart` web-безопасен (`AcpTransport`, `InProcessAcpLink`, конфигурации), IO-транспорты — только из `package:codelab_acp_transports/io.dart`; правило проверяет сторож (`webUnsafe` в `rules.dart`). Транспорт сообщает о сбое событием `AcpTransportEvent.failure` с `AcpTransportErrorCode`, а не переходом сессии (§27).

---

## 5. Ответственность `codelab_client_acp`

Пакет:

`packages/dart/codelab_client_acp`

Отвечает за переиспользуемую клиентскую семантику ACP.

Он МОЖЕТ:

* связывать транспорт и протокол;
* управлять жизненным циклом запросов;
* управлять жизненным циклом сессии;
* отслеживать корреляцию;
* преобразовывать протокольные события в события приложения и клиента;
* инициировать отмену;
* управлять политикой переподключения;
* публиковать состояние уровня приложения;
* создавать запросы разрешений.

Он НЕ ДОЛЖЕН зависеть от Flutter.

В коде: `AcpClientApplication` связывает транспорт и кодеки, ведёт ожидающие запросы по `JsonRpcId`, автоматы соединения, сессии и хода, публикует `connectionStateChanges`, `sessionChanges`, `diagnosticChanges`, `protocolFrames`; запрос агента `session/request_permission` превращает в `ApprovalRequest`. Переподключение — операция `reconnect(ReconnectCommand)`; автоматического переподключения нет, его запускает пользователь через `ClientWorkspace.reconnect` (`error-handling.md` §79). Пакет web-безопасен и без `intl`: сторож запрещает ему `webUnsafe` (в том числе `package:flutter/`) и пакеты языка интерфейса.

---

## 6. Протокольная модель ≠ прикладная модель

ДОЛЖНЫ различаться как минимум два уровня:

```text
Протокольная модель
      │
      ▼
Прикладная (клиентская) модель
```

Протокольная модель отвечает на вопрос:

> Как данные выглядят в ACP?

Прикладная модель отвечает на вопрос:

> Что эти данные означают для клиента?

Например, протокольное сообщение может содержать:

```text
method
params
id
version
metadata
```

Прикладной слой может преобразовать это в (иллюстративные имена):

```text
PromptStarted
PromptChunkReceived
ToolCallRequested
PermissionRequired
PromptCompleted
SessionDisconnected
```

В коде событий с такими именами нет: протокольные `SessionNotification`/`SessionUpdate`, `RequestPermissionRequest`, ответы `session/prompt` и события транспорта переводятся в состояния доменных моделей — `PromptTurn` со статусом `PromptTurnStatus`, `ToolCallRecord`, `ApprovalRequest`, `ClientConnectionState` (`session-lifecycle.md`).

---

## 7. Прикладная модель ≠ модель представления

Представлению может понадобиться ещё одна форма данных:

```text
Протокол
   ↓
Приложение
   ↓
Представление
```

Например, прикладное состояние (иллюстрация):

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

Модель представления создаётся, только когда семантика UI действительно отличается.

Создавать отдельный DTO на каждом уровне автоматически не нужно.

В коде три уровня: `ToolCallRecord` (`codelab_client_acp`) → `ToolCallItem` транскрипта (`codelab_client_core`, `TranscriptProjector`) → `CodeLabToolCallRow` (`codelab_ui`), его строит `_toolCallRowOf` в `apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart`.

---

## 8. Когда преобразование обязательно

Преобразование между протокольной и прикладной моделью ДОЛЖНО выполняться, если верно хотя бы одно:

* протокольная модель содержит проводные поля;
* схема может меняться независимо от UI;
* приложение объединяет несколько протокольных сообщений;
* у протокольного сообщения более низкоуровневая семантика;
* требуется нормализация;
* требуется проверка;
* требуется логика совместимости;
* приложение должно скрыть детали реализации протокола.

---

## 9. Когда преобразование не нужно

Отдельное преобразование не требуется, если тип:

* является стабильным value object;
* не несёт проводной семантики;
* не создаёт нежелательной связанности;
* не меняет смысл между слоями.

Архитектура НЕ ДОЛЖНА создавать DTO ради DTO.

---

## 10. Сырые протокольные сообщения в UI

Виджеты НЕ ДОЛЖНЫ:

* разбирать сырой JSON ACP;
* проверять строку метода;
* декодировать протокольные поля;
* вручную интерпретировать версию;
* самостоятельно отправлять (dispatch) протокольные команды.

Неправильно:

```dart
if (message.method == 'session/update') {
  ...
}
```

в виджете или BLoC слоя представления.

Правильнее:

```text
Обработчик протокола
      │
      ▼
SessionUpdated
      │
      ▼
BLoC
      │
      ▼
Виджет
```

В коде этот путь — `AcpClientApplication._handleSessionUpdate` → снимок `AcpSession` в `sessionChanges` → `ClientWorkspace` → `SessionView` → Cubit app → виджет (`streaming.md` §1). Панель Protocol получает готовые поля кадра и JSON-RPC не разбирает (§35а). Сторож проверяет только направление зависимостей пакетов: правила, запрещающего `package:codelab_acp_protocol/` в `presentation/` app, в `rules.dart` нет; сейчас протокольные типы импортируют только `lib/app/` и `application/` app (§40).

---

## 11. Исходящие команды

UI ДОЛЖЕН выражать **намерение** (intent), а не проводную команду ACP.

Например:

Неправильно:

```text
Widget
  → sendRawRequest("session/prompt", {...})
```

Предпочтительно:

```text
Widget
  → намерение SendPrompt
      → API клиента или приложения
          → запрос ACP
```

Так представление протокола можно менять без изменения UI.

В коде: Cubit вызывает `SessionHandle.send(text)` (`codelab_client_core`) → `AgentBackend.sendPrompt(SendPromptCommand)` → `AcpClientApplication.sendPrompt` → запрос `session/prompt`. Тот же путь доступен use case-ом `SendPrompt` (`codelab_client_acp`, `use_cases.dart`).

---

## 12. Корреляция

У всех запросов, ответов и долгоживущих операций ДОЛЖНА быть явная стратегия корреляции.

По возможности СЛЕДУЕТ использовать идентификаторы ACP:

* `session_id`;
* `request_id`;
* `message_id`;
* `tool_call_id`.

Прикладной слой НЕ ДОЛЖЕН полагаться только на порядок сообщений, если ACP даёт явные идентификаторы.

В коде: на проводе это `sessionId`, `id` JSON-RPC и `toolCallId`; имена в snake_case — ключи корреляции журнала (`Logger.withCorrelation`: `sessionId`, `requestId`, `connectionGeneration`, `toolCallId`, `messageId`, `operationId`). Поля `messageId` в схеме ACP (`17-Schema.md`) нет. Ответ сопоставляется с запросом по `JsonRpcId` (`_pendingRequests`), запрос разрешения — по id своего запроса JSON-RPC (§31), обновления вызова — по `toolCallId` (`streaming.md` §35).

---

## 13. Поколение соединения

При переподключении СЛЕДУЕТ использовать дополнительный локальный идентификатор — поколение соединения.

Пример:

```text
connection #41
connection #42
```

Событие предыдущего поколения НЕ ДОЛЖНО менять актуальное состояние.

Пример:

```text
generation=41 -> late completion
generation=42 -> current connection
```

Событие поколения 41 ДОЛЖНО быть проигнорировано, если операция уже принадлежит поколению 42.

В коде: `AcpClientApplication.generation` растёт при каждой замене транспорта; `_bindTransport` запоминает поколение подписки и отбрасывает входящие кадры и события транспорта прежнего поколения с записью `event_ignored` (`reason: stale_generation`), а ответ, пришедший после замены, отсекает `_requireCurrentGeneration` (`session-lifecycle.md` §15, `streaming.md` §6).

---

## 14. Владение сессией

Идентификатор сессии ACP и локальное состояние выполнения СЛЕДУЕТ различать.

Возможны:

```text
ACP session id
local session entity
connection generation
active request id
```

НЕ СЛЕДУЕТ использовать один идентификатор для разных понятий жизненного цикла.

Это особенно важно при:

* переподключении;
* восстановлении;
* возобновлении сессии;
* отмене;
* параллельных запросах.

В коде: `SessionId` (ACP) — ключ `AcpSession`; ход — локальный `PromptTurnId`; запрос разрешения — `ApprovalRequestId`; поколение — `generation`; исходящий запрос — `JsonRpcId`.

---

## 15. Потоковые события

Потоковые сообщения ACP НЕ ДОЛЖНЫ напрямую менять виджеты.

Предпочтительный путь:

```text
Уведомление ACP
      │
      ▼
Декодирование протокола
      │
      ▼
Событие клиента
      │
      ▼
Редьюсер / автомат состояний
      │
      ▼
Состояние приложения
      │
      ▼
BLoC / представление
```

Подробные правила:

`docs/architecture/streaming.md`

---

## 16. Идемпотентность

Если ACP допускает повторную доставку или реплей, обработка ДОЛЖНА быть идемпотентной.

НЕ ДОЛЖНО происходить:

```text
повторный чанк
    → повторное сообщение в UI

повторное завершение
    → двойная финализация

повторный вызов инструмента
    → второй диалог разрешения
```

Стратегия идемпотентности ДОЛЖНА использовать стабильные идентификаторы или порядковую информацию, если они доступны.

В коде: повторный `session/request_permission` с тем же id JSON-RPC не создаёт второго одобрения (`_handledPermissionRequests`); второй ответ на тот же запрос не находит ожидающего (`response_ignored`); `tool_call` и `tool_call_update` сливаются по `toolCallId`. Чанки — дельты без ключа, ACP не даёт их отличить от следующей дельты с тем же текстом, поэтому они всегда дописываются (`streaming.md` §8).

---

## 17. Порядок

ЗАПРЕЩЕНО предполагать порядок, который ACP не гарантирует.

Если протокол гарантирует порядок только внутри запроса или сессии, это ДОЛЖНО быть отражено в обработке состояния.

Если порядок критичен, использовать:

* порядковые номера;
* корреляцию;
* автомат состояний;
* явную буферизацию;

в соответствии со спецификацией.

НЕ СЛЕДУЕТ «исправлять» порядок эвристиками в UI.

В коде: ACP задаёт, что агент отвечает на `session/load`, когда весь реплей отправлен (`03-Session Setup.md`), а на `session/prompt` — когда ход закончен, при отмене — после отправки ожидающих обновлений (`05-Prompt Turn.md`); клиент копит реплей в `_sessionReplays`, а обновления ещё не созданной сессии — в `_earlyUpdates` (`streaming.md` §9, §12). Агентская сторона держит этот порядок очередью `OutboundQueue` (ACP-3, §49).

---

## 18. Неизвестные поля

Прямая совместимость ДОЛЖНА сохраняться там, где этого требует ACP.

Неизвестные поля НЕ ДОЛЖНЫ автоматически приводить к фатальной ошибке разбора, если протокол разрешает их игнорировать или сохранять.

Если протокольная модель поддерживает поля расширений, их СЛЕДУЕТ сохранять в той форме, которую определяет реализация.

ЗАПРЕЩЕНО придавать неизвестному полю известную семантику без спецификации.

В коде: ACP запрещает собственные поля в корне типов спецификации — расширения идут через `_meta` (`15-Extensibility.md`), а модели хранят `_meta` как `meta`. Поэтому разбор по умолчанию строгий: `requireOnlyRootKeys` отвергает незнакомое поле в корне объекта как `invalidShape` («use _meta for extensions»). Терпимы к лишним полям в корне (поле читается моделью только если известно, иначе пропускается):

* результаты ответов агента — `decodeAcpResult` через `tolerateUnknownRootFields`;
* параметры `session/update` — `decodeAcpNotificationParams`;
* объекты возможностей `initialize` — `requireAcpCapabilityObject`.

Запросы, которые инициирует агент (`session/request_permission`, `fs/*`, `terminal/*`), и запросы клиента остаются строгими: они требуют ответа и касаются безопасности. Незнакомое значение дискриминатора — по-прежнему `invalidShape`, кроме двух мягких случаев: незнакомый вид `session/update` пропускается (`unsupportedSessionUpdateKind`, `_skipUnsupportedSessionUpdate`), незнакомый `ToolKind` сводится к `other` с предупреждением в журнале (change `tolerate-unknown-tool-kind`).

---

## 19. Неизвестные методы и сообщения

Неизвестный метод или сообщение ACP ДОЛЖЕН обрабатываться явно.

Возможные стратегии зависят от спецификации:

* игнорировать;
* записать в журнал;
* вернуть ошибку протокола;
* сохранить как неизвестное сообщение;
* завершить несовместимую сессию.

ЗАПРЕЩЕНО молча интерпретировать неизвестный метод как существующий.

В коде: `requireAcpMethod` бросает `JsonRpcProtocolException.unknownMethod` для метода вне `acpMethodRegistry`. Клиент отвечает на неизвестный запрос агента `-32601 Method not found` и пишет диагностику только с методом и id (`_rejectUnsupportedRequest`), а неизвестное уведомление (например, `_vendor/...`) пропускает без отдельной записи — остаются только кадр `ProtocolFrame` и общая trace-запись `protocol_message` (`_handleInboundMessage`); ACP предписывает игнорировать нераспознанные уведомления (`15-Extensibility.md`). Агент: неизвестный запрос — `-32601`, неизвестное уведомление — запись в журнал и пропуск (`13-acp-adapter.md` §13.10).

---

## 20. Версия протокола

Версия протокола ДОЛЖНА быть самостоятельным понятием (first-class concept), если ACP версионируется.

Согласование версии и совместимость ДОЛЖНЫ происходить на границе ACP и клиента.

Представление НЕ ДОЛЖНО знать:

```text
if ACP v1 -> ...
if ACP v2 -> ...
```

если это можно скрыть в протокольном и прикладном слоях.

Предпочтительно:

```text
ACP v1
ACP v2
   │
   ▼
нормализованная прикладная модель
   │
   ▼
тот же UI
```

В коде: ACP версионируется целым `protocolVersion` в `initialize` (`02-Initialization.md`), тип — `ProtocolVersion`. Клиент поддерживает одну версию — `AcpClientApplication.supportedProtocolVersion` (`ProtocolVersion(1)`); если агент ответил другой, соединение переходит в `ClientConnectionState.failed` с `ConnectionFailureReason.unsupportedProtocolVersion`, транспорт закрывается и бросается `UnsupportedProtocolVersionException` (ACP: клиенту СЛЕДУЕТ закрыть соединение и сообщить пользователю). Агент отвечает `ProtocolVersion(1)`. Нормализации нескольких версий пока нет.

---

## 21. Обратная совместимость

При поддержке старой версии агента:

* логика совместимости локализуется на границе протокола и клиента;
* UI НЕ ДОЛЖЕН быть заполнен проверками версии;
* старые данные нормализуются в актуальную прикладную семантику, если возможно;
* неподдерживаемая возможность ДОЛЖНА быть представлена явно.

В коде старых версий протокола клиент не поддерживает (§20).

---

## 22. Прямая совместимость

При получении данных от агента более новой версии:

* неизвестные допустимые поля НЕ ДОЛЖНЫ ломать клиент;
* неизвестная возможность НЕ ДОЛЖНА автоматически считаться безопасной;
* неизвестное поведение ДОЛЖНО приводить к предсказуемому отказу;
* протокольная диагностика ДОЛЖНА содержать версию и контекст.

В коде: незнакомый `ToolKind` становится `other`, а вызов без классификации получает `ApprovalRiskLevel.unknown` и требует явного одобрения (`ApprovalRequest.riskLevel`, D27 change `add-provider-setup-ui`). Диагностика содержит метод, id запроса и поколение соединения, но не версию протокола: версия хранится в `ClientConnectionReady.protocolVersion` и в тексте `UnsupportedProtocolVersionException`, в записи журнала не попадает (расхождение с нормой; при политике `full` версия видна только в `payload` записей `protocol_message` для `initialize`).

---

## 23. Сериализация

Сериализация ДОЛЖНА быть централизована в `codelab_acp_protocol`.

НЕ СЛЕДУЕТ вручную сериализовать payload ACP в:

* BLoC;
* виджете;
* прикладной feature;
* адаптере транспорта.

Транспорт ДОЛЖЕН работать с установленным протокольным представлением.

В коде транспорты принимают и отдают `JsonRpcMessage` и вызывают кодек пакета (`encodeJsonRpcMessage`, `decodeJsonRpcMessage`); параметры и результаты методов кодирует `acpMethodRegistry`. Расширения CodeLab разбираются вне `codelab_acp_protocol`: блоки `_meta.codelab` — `CodelabExtensions.parse`, `data.codelab` ответа-ошибки — `PromptFailure.fromJsonRpcError`, уведомление `_codelab/session/usage` и запрос `_codelab/session/usage/ledger` маршрутизирует `codelab_client_acp` (`UsageNotification`, `UsageLedgerReply` хранят `params` и `result` сырыми), разбирают `UsageDecoder` и `UsageLedgerDecoder` (`codelab_client_core`), на стороне агента — `usage_accounting.dart` (`codelab_agent_acp`). Это прикладные расширения поверх `meta` и сырых `params`, а не модели ACP.

---

## 24. Десериализация

Десериализация ДОЛЖНА выполнять:

* проверку формы;
* проверку обязательных полей;
* проверку типов;
* разбор с учётом версии, если необходимо.

Ошибка разбора ДОЛЖНА нести достаточно контекста для диагностики, но НЕ ДОЛЖНА раскрывать секреты в журналах production.

В коде: `JsonRpcProtocolException` несёт вид (`invalidJson`, `invalidShape`, `unknownMethod`) и сообщение, в тексте которого указан путь к полю; конверт проверяют `jsonRpcMessageFromJson` (в том числе `jsonrpc: "2.0"`) и `requireJsonRpcId`. Сырые `params` в диагностику клиента попадают только при политике `full`, иначе — лишь размер (`_rawPayloadContext`, `observability.md` §48а).

---

## 25. Проверка протокола

Проверка делится на два уровня.

Протокольная проверка:

```text
"поле существует?"
"тип правильный?"
"сообщение соответствует схеме?"
```

Прикладная проверка:

```text
"можно ли выполнить это действие сейчас?"
"принадлежит ли запрос текущей сессии?"
"разрешена ли возможность?"
```

НЕ СЛЕДУЕТ смешивать эти две ответственности.

В коде протокольная проверка — в `codelab_acp_protocol` (`requireAcpObject`, `requireJsonObject`, кодеки моделей); прикладная — в `codelab_client_acp`: результат перехода автомата `StateTransitionResult` (`applied`, `ignored`, `rejected`), `StateTransitionException`, `MissingAcpSessionException`, проверка варианта ответа на разрешение (`_requirePermissionOption`) и containment путей `fs/*` и `terminal/*` (§30).

---

## 26. Ошибки

Ошибки ДОЛЖНЫ преобразовываться на границах.

Пример (иллюстрация):

```text
InvalidJson
    ↓
ProtocolDecodeError
    ↓
ACPClientProtocolFailure
    ↓
Состояние ошибки в представлении
```

Не каждая ошибка требует четырёх отдельных классов.

Преобразование оправдано, когда меняется семантика.

В коде (входящий битый JSON у клиента): `JsonRpcProtocolException` (`invalidJson`) → `AcpTransportException` с `AcpTransportErrorCode.protocolViolation` → `ClientConnectionState.failed` с `ConnectionFailureReason.protocolViolation` → `ConnectionView` (`codelab_client_core`) → состояние Cubit-а. Полная модель — `error-handling.md`.

---

## 27. Сбои транспорта

Сбой транспорта НЕ ДОЛЖЕН напрямую определять состояние приложения.

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

в зависимости от политики приложения.

Транспорт НЕ ДОЛЖЕН сам решать, какой UX показать.

В коде: `AcpTransportEvent.failure` обрабатывает `AcpClientApplication._handleTransportEvent` — соединение переходит в `ClientConnectionState.failed` (причина — `ConnectionFailureReason` по `AcpTransportErrorCode`), ожидающие запросы снимаются `AcpConnectionLostException`, ожидающие одобрения — `_dropPendingApprovals`; `ClientWorkspace` публикует `ConnectionView.lost`. Автоматического переподключения нет (§5). Строка stdout агента, которая не разбирается как JSON-RPC, роняет клиентский `StdioAcpTransport` с `protocolViolation`, тогда как агентская сторона после плохого кадра продолжает работу (ACP-4, §49).

---

## 28. Сбои протокола

Примеры сбоев протокола:

* некорректный ответ;
* неизвестное обязательное поле;
* неверный id запроса;
* неподдерживаемая версия;
* неверный payload метода.

Они ДОЛЖНЫ записываться в журнал с контекстом корреляции.

В release ЗАПРЕЩЕНО без необходимости сохранять полный чувствительный payload.

В коде: `_recordDiagnostic` пишет метод, `requestId`, при наличии `sessionId` и `toolCallId`; payload — только при политике `full` (§24, §35).

---

## 29. Отмена

Отмена ДОЛЖНА проходить через API ACP-клиента или приложения.

UI выражает намерение:

```text
CancelCurrentOperation
```

Ядро клиента определяет:

* какой запрос отменяется;
* какое сообщение ACP отправить;
* как обработать гонку завершения и отмены;
* как обновить состояние жизненного цикла.

UI НЕ ДОЛЖЕН сам считать операцию отменённой только после нажатия кнопки.

В коде: `SessionHandle.cancel()` → `AcpClientApplication.cancelTurn(CancelTurnCommand)`: уведомление `session/cancel`, ответ `cancelled` на ждущие `session/request_permission`, ход — в нетерминальный `PromptTurnStatus.cancelling`; итог хода задаёт ответ на `session/prompt` (`stopReason`), повторная отмена возвращает тот же ход (`streaming.md` §26, `session-lifecycle.md` §29).

---

## 30. Вызовы инструментов

Вызов инструмента ДОЛЖЕН проходить через прикладную границу.

Пример:

```text
Запрос инструмента ACP
      │
      ▼
ядро клиента
      │
      ▼
прикладная модель ToolCall
      │
      ▼
политика разрешений
      │
      ▼
представление
```

Виджет НЕ ДОЛЖЕН разбирать сырой payload инструмента, чтобы принять решение о безопасности.

Подробности:

`docs/architecture/permissions.md`

В коде: вызов приходит уведомлениями `session/update` (`tool_call`, `tool_call_update`) и, если агент спрашивает разрешение, запросом `session/request_permission`; ядро клиента сводит их в `ToolCallRecord` с уровнем риска `ApprovalRiskLevel` и в `ApprovalRequest`. Уровень риска считает `ApprovalPolicy.classifyToolCall` (`domain/approval_policy.dart`); это подсказка для показа, а не решение. Режимы разрешений принадлежат агенту (spec [`agent-permissions`](../../openspec/specs/agent-permissions/spec.md)), клиентских режимов нет; автоматически, без вопроса пользователю, отвечает только политика headless CLI `--approve` (spec [`approval-safety`](../../openspec/specs/approval-safety/spec.md) «Уровни риска», `permissions.md` §58). App получает готовый уровень риска (`_approvalRiskOf` в `ui_mappers.dart`).

Клиентские методы `fs/*` и `terminal/*` — исключение `AGENTS.md` §10: собственного гейта одобрения у клиента нет, разрешение — ответственность агента. Компенсирующий контроль — containment: `resolveWithinWorkingDirectory` проверяет `path` запросов `fs/*` и `cwd` запроса `terminal/create` относительно рабочей папки сессии до операции и при выходе за неё отвечает `-32602` (`AcpProtocolError.invalidAcpParams`, `PathOutsideWorkingDirectoryFailure`). Проверка лексическая: symlink не разрешается, это принятый остаточный риск (комментарий `fs_access.dart`). Исполняют операции IO-адаптеры `codelab_client_io` (`IoTextFileIo`, `IoTerminalProcessRunner`).

---

## 31. Результаты разрешений

Решение пользователя ДОЛЖНО быть связано с конкретным идентификатором операции.

ЗАПРЕЩЕНО хранить только:

```text
lastPermission = allowed
```

без корреляции.

Предпочтительно (иллюстрация):

```text
PermissionDecision(
  sessionId,
  requestId,
  toolCallId,
  decision,
)
```

Конкретная модель определяется реализацией или спецификацией.

В коде: `ApprovalRequest` хранит `id` (`ApprovalRequestId` из id запроса JSON-RPC `session/request_permission`), `sessionId`, `turnId` и `toolCall`; решение — `RespondToPermissionCommand.selected(sessionId, approvalId, optionId)` или `.cancelled(sessionId, approvalId)`. `respondToPermission` принимает ответ, только если одобрение ждёт в активном ходе этой сессии, и проверяет, что `optionId` входит в варианты запроса.

---

## 32. Обработка возможностей

Возможности, которые поддерживает агент, ДОЛЖНЫ рассматриваться как согласованные во время выполнения (negotiated/runtime capability), если это предусмотрено ACP.

UI НЕ ДОЛЖЕН предполагать наличие возможности только потому, что клиент умеет её отображать.

Правильнее:

```text
client supports X
agent advertises X
session allows X
→ X available
```

В коде: клиент объявляет `fs.readTextFile`, `fs.writeTextFile` и `terminal` только при внедрённых `TextFileReader`, `TextFileWriter`, `TerminalProcessRunner`, а свои расширения — в `clientCapabilities._meta.codelab` (`codelabClientExtensionsMeta`). Возможности агента хранит `ClientConnectionReady.capabilities`, его расширения — `CodelabExtensions`. ACP требует считать неуказанную возможность неподдерживаемой (`02-Initialization.md`); `ClientWorkspace` не вызывает `session/load` без `loadSession`, а `session/list` — без `sessionCapabilities.list`.

---

## 33. Необязательная возможность

Отсутствие необязательной возможности не является сбоем протокола.

Приложение ДОЛЖНО уметь представить состояние «недоступно».

UI МОЖЕТ:

* скрыть действие;
* сделать действие неактивным;
* показать состояние «не поддерживается»;

в зависимости от продуктовой спецификации.

В коде без `loadSession` у агента `ClientWorkspace` (`client_workspace.dart`): явная загрузка (`loadSession`) завершается `ClientWorkspaceException` без запроса к агенту; восстановление проекта открывает новую сессию с уведомлением `NoticeKind.reconnected`; после переподключения открытые сессии становятся `SessionStatusView.detached` с уведомлением в транскрипте.

---

## 34. Журналирование ACP

СЛЕДУЕТ записывать в журнал:

* направление сообщения;
* метод или тип;
* идентификаторы корреляции;
* версию протокола;
* исход жизненного цикла;
* сбои разбора.

НЕ СЛЕДУЕТ по умолчанию записывать:

* секреты;
* токены аутентификации;
* чувствительное содержимое файлов;
* полный payload инструмента;
* пользовательские данные без необходимости.

В коде: каждое сообщение даёт trace-запись `protocol_message` в категории `protocol` (направление, вид, метод, `request_id`, размер; `payload` — только при политике `full`), переходы соединения — `connection_state_changed`, отброшенные события — `event_ignored` и `response_ignored`. Версии протокола в этих записях нет (§22; при `full` — только в `payload` `initialize`). Подробно — `observability.md`.

---

## 35. Отладочный дамп протокола

В debug-сборке МОЖЕТ существовать расширенная трассировка ACP.

Она ДОЛЖНА быть:

* явно включаемой;
* выключенной по умолчанию в release;
* способной маскировать чувствительные значения;
* пригодной для корреляции.

В коде политику payload выбирает composition root хоста: desktop — `full` в debug-сборке и `metadataOnly` в release (`apps/codelab_desktop/lib/app/app_scope.dart`), CLI — `full` только с `--verbose` (`apps/codelab_cli/lib/src/composition_root.dart`). При `metadataOnly` режим Trace панели Protocol (`AcpClientApplication.setFrameTrace`) временно даёт полные payload кадрам, но не записи `protocol_message` (`observability.md` §48а, §49а). В debug-сборке desktop полные payload включены по умолчанию, без отдельного включения (`kDebugMode`) — расхождение с нормой «явно включаемой» выше.

### 35а. Кадры протокола клиента (`ProtocolFrame`)

Источник — change [`redesign-protocol-pane`](../../openspec/changes/redesign-protocol-pane/design.md), D2, D3, D5.

Панель Protocol desktop показывает кадры ACP соединения. Граница для них та же, что для остального протокола (§10):

* **Кадр строится в `codelab_client_acp`.** `AcpClientApplication` записывает неизменяемый `ProtocolFrame` (через внутренний `ProtocolFrameRecorder`) в единственной точке, через которую проходят все сообщения: при отправке (до передачи транспорту) и при приёме — после проверки поколения соединения (§13). Поздние сообщения старого поколения кадров не дают. Поток — `AcpClientApplication.protocolFrames`.
* **Поля кадра — готовые значения, прочитанные только из полей схемы ACP**: направление, поколение, вид (`request`, `notification`, `result`, `error`), метод (у ответа — метод запроса с тем же id), id, `sessionId`, краткая подробность (`update.sessionUpdate`, исход `session/request_permission`, имя стандартного кода ошибки), код ошибки, размер. Сопоставление ответа с запросом делает ядро клиента, а привязку запроса `session/new` к сессии из результата — буфер kit (`ProtocolFrameLog`, `codelab_client_core`).
* **App не разбирает JSON-RPC.** Cubit и мапперы app строят область, фильтры, тон и подписи только по готовым полям кадра (`kind`, `sessionId`, `errorCode`, `method` и `id` — как текст для показа и поиска). Ветвиться по значению `method` и читать `params`, `result` или `error` из payload app НЕ ДОЛЖЕН. Payload для app — только замаскированный текст для показа (с подсветкой `<redacted>`), копирования и экспорта.
* **Прямая совместимость** (§18, §19, §22): незнакомый метод или незнакомая форма дают кадр без подробности, а не ошибку. Сбой построения кадра записывается в журнал (`protocol_frame.build_failed`) и не мешает отправке и обработке сообщения.
* **Маскирование и политика — до выхода из пакета.** Payload кадра — результат `SecretRedactor` и хранится только при действующей политике `full` (`observability.md` §14а, §48а, §49а); слишком большой payload (больше 256 KiB) не хранится и при `full` (`ProtocolPayloadOmitted.tooLarge`). Кадр — проекция уже декодированного `JsonRpcMessage`: новых методов, полей и `_meta` ACP нет.
* **Декоратор транспорта для кадров не используется**: у транспорта нет поколения соединения и пар «запрос — ответ», а маскирование — ответственность клиентского ядра (`observability.md` §3).

---

## 36. Тесты границы протокола

Минимальные категории тестов:

### Тесты сериализации

```text
model → wire
```

### Тесты десериализации

```text
wire → model
```

### Тесты кругового преобразования (round-trip)

```text
model → wire → model
```

если это имеет смысл для схемы.

### Тесты совместимости

* отсутствующие необязательные поля;
* неизвестные поля;
* поддерживаемые старые версии;
* поведение при неподдерживаемой версии.

### Тесты некорректных сообщений

* искажённый payload;
* неверный тип поля;
* неверные идентификаторы.

В коде: `packages/dart/codelab_acp_protocol/test/` (`json_rpc_codec_test.dart`, `acp_method_codec_test.dart`, `response_tolerance_test.dart`, `session_update_tolerance_test.dart`, `tool_kind_test.dart`, `protocol_conformance_test.dart` и тесты моделей), скрипт `melos run protocol-conformance`. Старых версий протокола нет (§21), поэтому есть только проверка неподдерживаемой версии на стороне клиента.

---

## 37. Тесты ядра клиента

`codelab_client_acp` СЛЕДУЕТ тестировать отдельно от Flutter.

Полезные сценарии:

* корреляция запросов и ответов;
* потоковые обновления;
* отмена;
* обрыв соединения;
* переподключение;
* устаревшее событие;
* повторное событие;
* неизвестное сообщение;
* запрос разрешения;
* сбой транспорта.

Использовать `codelab_acp_testing` там, где это сокращает шаблонный код.

В коде: `packages/dart/codelab_client_acp/test/` (например, `state_machines_test.dart`, `unsupported_agent_requests_test.dart`, `unsupported_session_updates_test.dart`, `fs_access_test.dart`, `terminal_access_test.dart`, `protocol_frame_test.dart`) и прогон корпуса golden-фикстур против `AcpClientApplication` (`test/fixtures`, `melos run conformance:client`); агентская сторона — `melos run conformance:agent`.

---

## 38. Тестовый транспорт

Для unit- и интеграционных тестов СЛЕДУЕТ использовать тестовый транспорт в памяти (fake/in-memory transport).

Он ДОЛЖЕН позволять:

* отправлять входящие сообщения;
* наблюдать исходящие сообщения;
* имитировать обрыв;
* имитировать задержку;
* имитировать повторные события;
* имитировать поздние события;
* имитировать некорректный ввод.

Тестовый транспорт НЕ ДОЛЖЕН зависеть от Flutter.

В коде — `FakeAcpTransport` (`packages/dart/codelab_acp_testing/lib/src/fake_acp_transport.dart`, чистый Dart): входящие — `emitInbound`, исходящие — `sent`, `sentMessages`, `drainSentMessages`; обрыв и сбой — `fail`, `failNextSend`, события транспорта — `emitEvent`, `emitDiagnostic`; `initialize` он по умолчанию отвечает сам (`autoRespondToInitialize`, `initializeProtocolVersion`). Повторы и поздние события тест воспроизводит повторным или отложенным `emitInbound`. Отдельной имитации задержки нет, а вход у него — уже декодированные `JsonRpcMessage`, поэтому битый JSON проверяется тестами настоящих транспортов, а у `FakeAcpTransport` — через `fail` с `protocolViolation` или через `params`, не проходящие разбор модели.

---

## 39. Не допускать утечки протокола

Признаки утечки протокола:

* виджет содержит строку метода ACP;
* BLoC вручную делает `jsonDecode` payload ACP;
* UI проверяет версию протокола;
* состояние представления хранит сырую карту ответа;
* диалог решает семантику возможности инструмента;
* feature создаёт сырой протокольный запрос.

Найдя такой паттерн, СЛЕДУЕТ проверить, не должна ли логика переехать в `codelab_acp_protocol` или `codelab_client_acp`.

---

## 40. Когда протокольный тип допустим выше границы

В отдельных случаях стабильный протокольный тип МОЖНО использовать выше границы, если:

* тип является value object;
* он не несёт транспортных и проводных деталей;
* его семантика совпадает с прикладной;
* это убирает бессмысленное дублирование.

Такое решение ДОЛЖНО быть осознанным.

НЕ СЛЕДУЕТ автоматически копировать каждый протокольный тип в прикладную модель.

В коде так используются value-типы `codelab_acp_protocol`: `SessionId`, `ToolKind`, `PermissionOption`, `PermissionOptionKind`, `PermissionOptionId`, `StopReason`, `PlanEntry`, `PlanEntryStatus`, `PlanEntryPriority`, `SessionConfigOption` — в доменных моделях `codelab_client_acp` (например, `ApprovalRequest.options`), в `application/` и `lib/app/` desktop и в `apps/codelab_cli`. Слой `presentation/` desktop протокольных типов не импортирует.

---

## 41. Публичный API ACP

`codelab_client_acp` ДОЛЖЕН предоставлять API, удобный приложению.

Предпочтительно:

```text
connect()
createSession()
sendPrompt()
cancel()
respondToPermission()
disconnect()
```

или эквивалентные типизированные операции.

Менее предпочтительно для UI:

```text
send(method, Map<String, dynamic>)
```

Низкоуровневый API МОЖЕТ существовать внутри протокольного или клиентского пакета, но НЕ ДОЛЖЕН становиться основным интерфейсом слоя представления.

В коде `AcpClientApplication` даёт типизированные операции `connect`, `createSession`, `loadSession`, `listSessions`, `sendPrompt`, `cancelTurn`, `respondToPermission`, `setSessionConfigOption`, `reconnect`, `requestUsageLedger` и `dispose` (отдельного `disconnect` нет: соединение закрывает `dispose`); команды — `CreateSessionCommand`, `LoadSessionCommand`, `SendPromptCommand`, `CancelTurnCommand`, `RespondToPermissionCommand`, `ReconnectCommand`; use case-ы с теми же именами — `use_cases.dart`. Отправка сырого запроса закрыта (`_sendRequest`). Слой представления работает через `ClientWorkspace` и `SessionHandle` (`send`, `cancel`, `retry`, `respond`, `setConfigOption`).

---

## 42. Фасад ACP-клиента

При необходимости `codelab_client_acp` МОЖЕТ предоставлять фасад, скрывающий:

* транспорт;
* реестр запросов;
* корреляцию;
* протокольное кодирование;
* маршрутизацию событий;
* переходы жизненного цикла.

Концептуальный пример API (иллюстрация; типа `AcpClient` в коде нет):

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

Конкретный API ДОЛЖЕН соответствовать существующему коду и OpenSpec.

Пример не требует создать именно такие методы.

В коде роль фасада играет `AcpClientApplication`, а над ним для app и CLI — порт `AgentBackend` и `ClientWorkspace` (`codelab_client_core`).

---

## 43. Владение границей

Краткая таблица ответственности:

| Ответственность | Владелец |
| --- | --- |
| Проводные модели | `codelab_acp_protocol` |
| Сериализация | `codelab_acp_protocol` |
| Десериализация | `codelab_acp_protocol` |
| Ввод-вывод транспорта | `codelab_acp_transports` |
| Примитивы соединения | `codelab_acp_transports` |
| Создание транспорта клиента по профилю | `codelab_client_io` (`ioTransportResolver`); встроенный агент — `codelab_embedded` |
| Корреляция запросов | `codelab_client_acp` |
| Семантика сессии | `codelab_client_acp` |
| Семантика отмены | `codelab_client_acp` |
| Абстракция разрешений | `codelab_client_acp` / приложение |
| Containment клиентских `fs/*` и `terminal/*` | `codelab_client_acp` (проверка), `codelab_client_io` (исполнение) |
| Кадры протокола (`ProtocolFrame`) | `codelab_client_acp`; буфер — `codelab_client_core` (`ProtocolFrameLog`) |
| Клиентское состояние и проекции (транскрипт, представления сессий) | `codelab_client_core` (`ClientWorkspace`) |
| Состояние UI | BLoC/Cubit app |
| Отрисовка | `codelab_ui` / `codelab_desktop`; терминал — `apps/codelab_cli` |
| ACP-сервер агента (проекция ядра в протокол) | `codelab_agent_acp` (раздел 49) |

---

## 44. Изменение схемы ACP

При изменении схемы агент ОБЯЗАН определить:

1. Меняется ли проводной контракт.
2. Меняется ли версия протокола.
3. Нужна ли обратная совместимость.
4. Нужна ли прямая совместимость.
5. Какие сериализаторы и десериализаторы затрагиваются.
6. Какие тесты должны быть обновлены.
7. Нужно ли менять прикладную модель.
8. Нужно ли менять UI.
9. Требуется ли OpenSpec change.

Проводной контракт НЕ ДОЛЖЕН меняться только потому, что UI удобнее получить данные в другой форме.

Источник схемы — `docs/protocols/acp/protocol/17-Schema.md`; методы, поля и значения ACP не придумываются (`AGENTS.md` §3.4).

---

## 45. Изменение прикладной модели

Прикладная модель может меняться без изменения проводного протокола.

Например (иллюстрация):

```text
ACP message A
ACP message B
      │
      ▼
NormalizedSessionUpdate
```

Это позволяет развивать семантику UI и приложения независимо от схемы протокола.

В коде так несколько видов `session/update` сводятся в один `PromptTurn`/`AcpSession`, а те — в `TranscriptItem` и `SessionView` (`streaming.md` §39).

---

## 46. Изменение модели представления

Модель представления может меняться независимо от протокола ACP, если прикладная семантика не меняется.

Это желательное свойство архитектурной границы.

Редизайн UI НЕ ДОЛЖЕН требовать изменения схемы ACP.

---

## 47. Чеклист перед изменением кода ACP

Перед изменением границы ACP проверить:

1. Какой пакет владеет поведением?
2. Это семантика протокола, транспорта или приложения?
3. Есть ли соответствующая спецификация OpenSpec?
4. Не протекает ли сырой протокол в UI?
5. Не протекает ли Flutter в pure Dart пакет?
6. Как обрабатываются неизвестные поля и сообщения?
7. Как изменение влияет на совместимость версий?
8. Как выполняется корреляция?
9. Возможны ли повторные или поздние события?
10. Какие тесты нужно добавить?

---

## 48. Главный инвариант

Архитектура ДОЛЖНА позволять заменить или изменить проводные детали ACP с минимальным влиянием на Flutter UI.

Желаемая зависимость:

```text
Изменения ACP
    │
    ▼
граница протокола и клиента
    │
    ▼
стабильная прикладная семантика
    │
    ▼
UI
```

Нежелательная:

```text
переименовано поле ACP
    │
    ├── изменён виджет
    ├── изменён диалог
    ├── изменён BLoC
    ├── изменена навигация
    └── изменены пять features
```

Если небольшое изменение протокола требует широких правок слоя представления, СЛЕДУЕТ проверить качество границы ACP.

---

## 49. Агентская сторона границы ACP

Выше описана клиентская сторона. У ACP-соединения есть и вторая — агентская: CodeLab сам умеет быть ACP-агентом. Её владелец — `codelab_agent_acp`.

### Кто за что отвечает

| Ответственность | Владелец |
|---|---|
| Проекция событий ядра (`AgentEvent`) в `session/update`, ответы на `initialize`, `session/new`, `session/load`, `session/prompt` | `codelab_agent_acp` (`AcpAgentServer`) |
| Wire-модели и кодек | `codelab_acp_protocol` (общий для обеих сторон) |
| Транспорт: stdio, WebSocket, пара в памяти `InProcessAcpLink` | `codelab_acp_transports`; IO-транспорты подставляет хост |
| Запросы агента к клиенту (`fs/*`, `terminal/*`, `session/request_permission`) | `codelab_agent_acp` отправляет, клиент исполняет и решает |
| Правила разрешений и containment путей | ядро (`codelab_agent_core`), не адаптер |

Правила:

* Адаптер берёт методы, поля и значения только из `codelab_acp_protocol` и `docs/protocols/acp/protocol/`. Всё сверх них — `_meta.codelab.*`, `data.codelab` или методы `_codelab/*`, и каждое расширение вводит OpenSpec change (`AGENTS.md` §3.4, ACP-1, ACP-2).
* Ядро ACP не знает. Оно отдаёт `AgentEvent`; адаптер проецирует их, и каждый подтип либо проецируется, либо явно помечен «не передаётся» (ACP-6).
* Порядок на проводе: ответ на `session/prompt` идёт после последнего `session/update` хода, ответ на `session/load` — после реплея (ACP-3); после `session/cancel` ход завершается `stopReason: cancelled` (ACP-5), а сбой хода не выдаётся за `end_turn` (ACP-7).
* Плохой кадр не закрывает соединение и не прерывает активные ходы (ACP-4); ошибки JSON-RPC несут причину в `data.codelab.reason`, собственных кодов нет.
* Агент не выбирает транспорт сам (PKG-3): stdio и WebSocket подставляет `apps/codelab_agent`, пару `InProcessAcpLink` — `codelab_embedded`. Для клиента встроенный агент — обычный ACP-агент, отличается только транспорт, поэтому клиентский слой (`codelab_client_acp`) не знает, встроен агент или нет.
* Встроенному агенту клиентские `fs/*` и `terminal/*` не нужны: он работает в процессе клиента, и `AcpServerConfig.localEnv` подставляет локальное окружение. Containment (`BoundedEnv`) и разрешения при этом остаются теми же, что у внешнего агента.

В коде: неразбираемый JSON (`-32700` с `id: null`) и кадр не JSON-RPC 2.0 (`-32600`) отвечает серверный транспорт (`decodeServerFrame` в `codelab_acp_transports`), неизвестный метод (`-32601`) — `AcpAgentServer` через `AcpRequestError.methodNotFound`, параметры, не прошедшие декодер (`-32602`), — `InboundRouter`; исходящие идут через одну очередь `OutboundQueue` (ACP-3); отказ обработчика — `AcpRequestError`. Причину в `data.codelab.reason` несут ошибки, где она задана явно (`sessionBusy`, `turnActive`, `projectConfigInvalid`, `usageLedgerFailed`); остальные ошибки JSON-RPC — только код и сообщение. Внешнему агенту файлы и команды исполняет клиент через `AcpClientExecutionEnv`, вопрос о разрешении задаёт `AcpPermissionGate` (`session/request_permission`); при `localEnv` gate тот же. Методы расширений — `_codelab/session/usage` и `_codelab/session/usage/ledger` (`usage_accounting.dart`). Границы пакета держит сторож: `webUnsafe` запрещён в `rules.dart`, зависимости — allowlist `acpAllowlist` (`codelab_agent_core`, `codelab_acp_protocol`, `codelab_acp_transports`, `meta`, `async`).

Подробно: `docs/architecture/proposals/agent-core/13-acp-adapter.md` (правила протокольного уровня §13.10, инварианты ACP-1…ACP-12 §13.14).
