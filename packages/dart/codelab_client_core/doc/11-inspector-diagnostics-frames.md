# Инспектор, диагностика и буфер кадров

Глава разбирает три средства, которыми хост видит, что происходит на проводе и внутри слоя: диагностику событий (`WorkspaceDiagnostic`), буфер кадров ACP (`ProtocolFrameLog`) и проекцию инспектора (`InspectorProjection`). Общее правило: ничего секретного в них не попадает, а решение, что показывать и что писать в журнал, остаётся за хостом (корневой `AGENTS.md` §16).

## Диагностика

`ClientWorkspace.diagnostics` — поток `WorkspaceDiagnostic(severity, source, message)`: события, которыми владеет слой. Хост подписывается и пишет их в свой журнал; слой сам их не пишет. Поток синхронный и доставляет событие после публикации состояния. Сообщения, которые зависят от формы хоста (например, об установке подключения), пишет сам хост.

`severity` — `DiagnosticSeverity` из `codelab_client_acp`. `source` — область: `prompt`, `session`, `approval`, `transport`, `restore`. `message` уже прошёл `SecretRedactor`: `_report` редактирует текст перед публикацией.

События слоя:

| `source` | Уровень | Сообщение |
|---|---|---|
| `prompt` | info | `Prompt completed with stopReason <причина>.` |
| `prompt` | error | `Failed to send prompt: <причина>` (в том числе у `detached`-сессии) |
| `prompt` | info | `Cancelled prompt turn <id>.` |
| `prompt` | error | `Failed to cancel prompt turn: <причина>` |
| `approval` | info | `Resolved approval <id> (<status>).` |
| `approval` | error | `Failed to respond to approval request: <причина>` |
| `session` | info | `Set config option <id> to <value>.` |
| `session` | error | `Failed to set config option <id>: <причина>` |
| `session` | error | `Failed to load ACP session <id>: <причина>` |
| `session` | error | `Failed to list ACP sessions: <причина>` |
| `transport` | error | `Connection to ACP agent lost: <причина>` — только неожиданная потеря установленного соединения, не сбой явного `connect` |
| `restore` | warning | `Failed to read workspace snapshot: …`, `Workspace snapshot is invalid; starting fresh.`, `Failed to save workspace snapshot: …`, `Failed to restore the workspace: …` |

Что важно:

- Сбой явного `connect` или `reconnect` не дублируется диагностикой: его сообщает вызывающий и состояние `ConnectionFailed`.
- Исход промпта, который слой отправил из очереди сам, тоже даёт диагностику: события слоя не зависят от того, кто вызвал `send`.
- Предупреждения ядра клиента, например о снятом одобрении при замене транспорта, идут в диагностику `AcpClientApplication`, а не в поток слоя.

### `describeFailure` и `formatRedactedJson`

`describeFailure(Object error)` — текст ошибки для интерфейса и CLI без токенов и ключей. Исключения `codelab_client_acp` печатаются как `ClassName: message`, а человеку нужен только текст: функция берёт `message` у `AcpClientApplicationException`, `AcpTransportException`, `StateTransitionException` и `ClientWorkspaceException`, а остальное превращает в строку; результат проходит `SecretRedactor.redactText`.

`formatRedactedJson(Object?)` — JSON с отступами после редакции секретов по ключам и по тексту; `null` — `null`. Через неё идут сырые аргументы вызовов в инспекторе и в одобрениях. Правила редактора и политику payload описывает [«Маскирование секретов»](../../codelab_client_acp/doc/redaction.md).

Пример проверки: исключение с токеном в тексте превращается в сообщение с маской. Тест — `test/diagnostics/diagnostics_test.dart`.

## Буфер кадров ACP

`ProtocolFrameLog` хранит историю кадров соединения для панели Protocol и экспорта. Почему он в слое: история кадров — клиентское состояние (политика «что хранить и сколько»), а владелец такого состояния — слой, а не Cubit app (design D5 change `redesign-protocol-pane`).

Устройство:

- создаётся в конструкторе `DefaultClientWorkspace`, подписан на `AgentBackend.protocolFrames` и закрывается в `dispose`; снаружи доступен только как `ClientWorkspace.protocolFrames`;
- в `WorkspaceState` кадры **не входят**: при стриминге их сотни в секунду, а `WorkspaceState` перестраивает рабочее место;
- хост слушает `changes` (сигнал без копии списка), по `revision` понимает, что снимок устарел, и берёт `frames` — неизменяемый список, старые первыми;
- `clear()` очищает буфер, запись продолжается;
- пределы: `maxFrames = 2000` кадров и `maxPayloadBytes = 8 MiB` суммарного payload (размер — длина UTF-8 от `jsonEncode`); старейшие кадры вытесняются;
- переподключение буфер **не очищает**: кадры несут `connectionGeneration`; поздние кадры старого поколения отбрасывает ядро клиента, а не буфер;
- «область» (сессия в фокусе) буфер не знает — это дело хоста.

Кадр `ProtocolFrame` (из `codelab_client_acp`): `seq`, `time`, `direction` (`outbound`, `inbound`), `connectionGeneration`, `kind` (`request`, `notification`, `result`, `error`), `method`, `id`, `sessionId`, `detail`, `errorCode`, `size`, `payload`, `payloadOmitted`. `payload` замаскирован `SecretRedactor` до попадания в кадр. Запрос `session/new` ещё не знает id сессии: буфер подставляет `sessionId` из результата в кадр запроса с тем же id, направлением, противоположным результату, и поколением, сохраняя место и `seq` (D6).

Реальный прогон на `FakeAcpTransport`:

```text
traceAvailable=true traceEnabled=false
revision=4, frames=4
#0 outbound request initialize size=293 payload=null (policy) session=null
#1 inbound result initialize size=259 payload=null (policy) session=null
#2 outbound request session/new size=88 payload=null (policy) session=s-1
#3 inbound result session/new size=53 payload=null (policy) session=s-1
--- trace on
#4 outbound request session/new size=88 payload=kept session=s-2
#5 inbound result session/new size=53 payload=kept session=s-2
--- trace off: revision 6 -> 7
payloads kept: 0
```

Источник: временный скрипт на `KitAgent`. Кадр `#2` — запрос `session/new`, к которому подставлен `session=s-1` из результата `#3`.

### Политика payload и режим Trace

Хранить ли payload (промпты, содержимое файлов), решает composition root при создании `AcpClientApplication`: параметр `protocolPayloads` — `ProtocolPayloadPolicy.metadataOnly` (по умолчанию: только метаданные) или `full`. CLI выбирает `full` только с `--verbose` (`composition_root.dart`). Слой политику не меняет.

Режим Trace — явное включение полных payload поверх базовой политики `metadataOnly`:

- `traceAvailable` фиксируется при создании буфера по `backend.traceAvailable`. При базовой `full` payload и так полные, Trace не нужен и недоступен.
- `setTrace(true)` переводит ядро клиента на `full` для **новых** кадров. Режим не сохраняется и при каждом запуске выключен.
- `setTrace(false)` возвращает `metadataOnly`, снимает payload со всех кадров буфера (копии с `payloadOmitted = policy`), обнуляет учёт объёма и увеличивает `revision`. Текст ошибки у кадров `error` заменяется стандартным именем кода: даже замаскированный, это текст агента.
- Повтор того же значения и вызов при `traceAvailable == false` — пустая операция: бэкенд не вызывается, `revision` не растёт.
- Пока Trace выключен при базовой `metadataOnly`, payload в буфер не попадает, даже если кадр построен ядром до выключения, но доставлен после: поток кадров ядра `sync: false`.

Тесты — `test/protocol/protocol_frame_log_test.dart`; фейк бэкенда с кадрами — `_FakeBackend` в этом файле.

## Проекция инспектора

`InspectorProjection().project(AcpSession)` — чистая функция: список `InspectorEntry` для последнего хода сессии либо, пока ходов нет, одна запись о сессии. Записи: одобрения хода, вызовы инструментов хода, каждое обновление хода и сам ход. У записи — `category` (`approval`, `toolCall`, `protocol`, `diagnostic`), `title`, `summary`, `risk`, `status`, `details` и сырые `rawInput`, `rawOutput` после `formatRedactedJson`.

Реальный вывод (тот же сценарий на `KitAgent`; вызов с `api_key` в аргументах):

```text
toolCall   tool-c1                  Run dart test | execute risk=shell rawInput={   "command": "dart test",   "api_key": "<redacted>" }
protocol   update-0                 session/update agent_message_chunk | Running.
protocol   update-1                 session/update tool_call | Run dart test rawInput={   "command": "dart test",   "api_key": "<redacted>" }
protocol   turn-turn-1              Prompt turn turn-1 | Status completed
```

Проекция принимает `AcpSession` — модель ядра клиента, а не `SessionView`; у слоя `SessionHandle` модели `AcpSession` не отдаёт. На момент написания проекцию вызывают только тесты (`test/inspector/inspector_projection_test.dart`): в `lib/` приложений её нет, а панель Protocol в desktop показывает кадры `ProtocolFrameLog`. Проекция остаётся частью публичного API и спецификации «Общий клиентский слой без UI».

## Что делать хосту

- Подписать `diagnostics` и писать записи в свой журнал с `source` как ключом (так делают Cubit-ы app и `--verbose` в CLI).
- Для панели кадров: `changes` → `frames` по `revision`, не копировать список на каждое событие.
- Не доставать payload из кадров в обход политики: если payload нужен, включить Trace или `full` на уровне composition root.
- Любой текст ошибки в интерфейс пропускать через `describeFailure`.
