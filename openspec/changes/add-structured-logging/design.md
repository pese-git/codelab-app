## Context

Сегодня в кодовой базе уже есть три независимых, не связанных друг с другом кусочка будущей observability:

- `DiagnosticEntry`/`_recordDiagnostic` в `AcpClientApplication` (`packages/dart/acp_client_core/lib/src/application/acp_client_application.dart:1503`) — единственный реально работающий "лог": in-memory список записей (`severity: debug|info|warning|error`, `source`, `context`, `cause`), **неограниченный** (`_diagnostics.add(entry)` без cap), читается UI-инспектором (`inspector_pane.dart`).
- `SecretRedactor` (`packages/dart/acp_client_core/lib/src/domain/secret_redaction.dart`) — уже покрывает маскирование (regex по ключам/значениям: token/password/secret/api-key/authorization/private key), применяется к каждой `DiagnosticEntry` перед сохранением, и повторно используется напрямую в `shell_cubit.dart`.
- `AcpTransportEvent.diagnostic(message, severity)` (`packages/dart/acp_transports/lib/src/acp_transport.dart:34`) — typed-событие, которым `acp_transports` сообщает о connect/disconnect/process lifecycle, не создавая собственной зависимости на логгер; `acp_client_core` подписывается на этот stream и превращает события в `DiagnosticEntry`.
- `_generation`/`generation` в `AcpClientApplication` (`acp_client_application.dart:126`) — уже реализует ровно то, что `observability.md` §5 называет `connection_generation` (инкремент на каждый `reconnect`, используется для отбрасывания stale-событий).

Т.е. значительная часть §OBS-001..006 уже частично покрыта ad hoc — не хватает: bounded storage, явного Logger-порта со structured/JSON выводом наружу приложения, типизированных correlation-полей поверх уже существующих identifiers, разделения application logging / protocol tracing (§2 `observability.md`) и release/debug различия (OBS-005).

## Goals / Non-Goals

**Goals:**
- Ввести Logger-порт + `structured_log`-адаптер, не ломая существующий контракт `DiagnosticEntry`/inspector UI.
- Переиспользовать уже существующие примитивы вместо изобретения новых: `SecretRedactor` для маскирования, `generation` для `connection_generation`, session-scoping для `session_id`.
- Ограничить `_diagnostics` bounded ring buffer (OBS-004).
- Дать слоям (`acp_protocol`/`acp_transports`/`acp_client_core`/presentation) явную, но минимальную по footprint возможность логировать по правилам ownership (§3 `observability.md`, OBS-006), не размазывая новую pub-зависимость по всем pure Dart пакетам без необходимости.
- Отделить developer-only protocol tracing (полный ACP payload) от обычного application logging, выключенный по умолчанию в release (OBS-005).

**Non-Goals:**
- Перестройка UI debug-логов панели (`/logs`, `agent-workbench-ui`) — она уже существует через `inspector_pane.dart` и продолжит читать `DiagnosticEntry` в прежней форме.
- Crash reporting / audit trail / performance metrics (§24, §37, §57 `observability.md`) — отдельные будущие решения, не часть этого change.
- Редактирование секретов в выводе integrated terminal — явно вне scope `SecretRedactor` (см. `add-integrated-terminal/proposal.md`), не меняется этим change.
- Migration/rotation policy лог-файлов на диске в деталях — фиксируется как open question, не блокирует эту итерацию.

## Decisions

### 1. `structured_log` добавляется только в `acp_client_core`, не в `acp_protocol`/`acp_transports`

`acp_protocol` разрешает только "pure Dart libraries, необходимые для реализации protocol" (`layers-and-dependencies.md` §5) — логирование им не является. `acp_transports` уже решает задачу "может логировать connect/disconnect" **без** зависимости на логгер — через typed `AcpTransportEvent.diagnostic`, который выше слушает `acp_client_core`.

Решение: сохранить этот существующий паттерн. `acp_protocol` продолжает бросать типизированные protocol-ошибки (parse failure и т.д.), ничего не логируя сам. `acp_transports` продолжает эмитить `AcpTransportEvent.diagnostic`. Новый Logger-порт и его единственный `structured_log`-адаптер живут в `acp_client_core`, которая уже является потребителем обоих источников и уже выполняет их трансляцию в `DiagnosticEntry`.

Альтернатива (отклонена): дать каждому пакету собственную зависимость на `structured_log`. Отклонено — размазывает pub-зависимость по трём pure Dart пакетам ради `МОЖЕТ`-требования (§3 `observability.md` использует "может", не "должен"), нарушает §13 AGENTS.md (пропорциональность) и требует правки dependency-матрицы без архитектурной необходимости, раз typed-event паттерн уже решает задачу.

### 2. Correlation ID переиспользуют существующие identifiers, а не создают новые

`session_id` → уже есть session-scoping в `_sessions`/`SessionId`; `connection_generation` → уже есть `AcpClientApplication.generation`; `request_id`/`tool_call_id` → уже присутствуют в ACP application-моделях (request/tool-call identifiers, использующихся в `_recordDiagnostic`'s `context`).

Типизированный API появился в `structured_log` 0.2.0-dev.1: `LogCorrelation` + `BoundLogger.withCorrelation({sessionId, requestId, connectionGeneration, toolCallId, messageId, operationId})` — ровно набор полей, запрошенный в ТЗ пакету. Задача этого change со стороны интеграции — принять уже существующие значения (`AcpClientApplication.generation` и т.д.) как параметры `withCorrelation`, не изобретать новую схему идентификаторов.

### 3. `DiagnosticEntry` не заменяется, а получает второй output

`_recordDiagnostic` продолжает создавать `DiagnosticEntry` (для inspector UI) **и** дополнительно передаёт тот же, уже прошедший `SecretRedactor`, набор полей в `Logger` — один redaction pass на оба потребителя, как и раньше. Дублирования redaction-логики не возникает.

`_diagnostics` (`acp_client_application.dart:99`) получает ring buffer cap. Число берётся из собственного примера `observability.md` §28 ("last 500 events") — не изобретается произвольно.

Альтернатива (отклонена): полностью заменить `DiagnosticEntry` на события, читаемые напрямую из `Logger`. Отклонено — ломает существующий, покрытый тестами контракт `AcpClientApplication.diagnostics`/`inspector_pane.dart` без необходимости; Non-Goal этого change — не трогать UI debug-панель.

### 4. Protocol tracing — `LogLevel.trace` + отдельная `category`, gated через sink `enabled`

**Уточнение по факту сверки с исходниками:** в 0.2.0-dev.1 пакет определял `LogLevel` без `trace`; начиная с **0.2.0-dev.3** добавлен `LogLevel.trace` (ниже `debug`) и `BoundLogger.trace(event, {context})` — ровно то, что нужно для семантики §8 `observability.md` ("очень подробные internal events"). Ближайший аналог `fatal` из §8 — по-прежнему `critical` (отдельного `fatal` пакет не вводит).

Полный ACP payload логируется вызовом `logger.trace(...)`. Sink, принимающий эти записи, получает `minLevel: LogLevel.trace` (иначе default `minLevel: LogLevel.debug` их отфильтрует — подтверждено `LogSink.accepts`: `level.index < minLevel.index`).

Но `LogSink.minLevel` — `final`, немутируемое поле: уровнем нельзя переключить protocol tracing в runtime. Поэтому "выключен по умолчанию, включается explicit действием" (§49 `observability.md`, не автоматически при ошибке) реализуется через **runtime-mutable** `LogSink.enabled` (см. Decision 6), а `category`/`minLevel: trace` — как раз тот фильтр, который решает, какие записи вообще могут в этот sink попасть, когда он включён.

`category` — это не отдельный параметр вызова `trace()`/`debug()`/..., а обычный ключ `'category'` в context-map записи (`LogSink.accepts` читает `entry['category']`). Чтобы событие маршрутизировалось в protocol-sink, вызывающий код обязан выставить `context: {'category': 'protocol', ...}` либо заранее забиндить его: `logger.bind({'category': 'protocol'})`.

Protocol-trace sink по умолчанию выключен (`enabled: false`) — включается явным debug/runtime-действием через `StructlogConfiguration.setSinkEnabled('protocol', enabled: true)`.

### 5. Композиция и конфигурация — в composition root `codelab_app`, по образцу существующих модулей

`BoundLogger`-инстансы (через `getLogger()`/прямое конструирование, см. Decision 7) настраиваются в новом `CodeLabLoggingModule` в `app_scope.dart`, по аналогии с уже существующим `CodeLabPlatformModule`. Presentation (`CodeLabShellCubit` и другие Cubit'ы, которым нужно логировать значимые user intents/UI failures) получают Logger-порт через constructor injection из CherryPick-scope — так же, как сейчас получают use case'ы (`CreateSession`, `SendPrompt` и т.д.). Ни один widget не создаёт и не резолвит Logger-порт напрямую (§6/§10 AGENTS.md, §36 `layers-and-dependencies.md`).

### 6. Маршрутизация "одна запись → несколько outputs": native multiplexing в `structured_log` 0.2.0-dev.1+

Начиная с `structured_log` 0.2.0-dev.1 пакет нативно поддерживает multi-output: `StructlogConfiguration(sinks: [...])` + `LogSink(name, output, minLevel, categories, enabled)`, с изоляцией ошибки одного sink от остальных (`BoundLogger.tryLog` оборачивает `sink.output(...)` в try/catch и пишет ошибку в `stderr`, не пробрасывая её дальше — закрывает ровно тот риск, который раньше был отдельным пунктом в Risks). Обходной путь с двумя независимыми Logger-инстансами и ручной маршрутизацией на стороне `acp_client_core`, ранее описанный как fallback, **не требуется**.

Конфигурация в `CodeLabLoggingModule` (сигнатуры сверены с реальным `lib/src/sink.dart`/`lib/src/configuration.dart`/`lib/src/async_file_output.dart`/`lib/src/logger.dart` на `develop`, версия пакета `0.2.0-dev.3`):

```dart
final protocolTraceOutput = AsyncRotatingFileOutput(
  'protocol.log',
  maxSizeBytes: …,
  maxBackups: …,
);

final loggingConfig = StructlogConfiguration(
  processors: [secretRedactionProcessor, dropNullValues],
  sinks: [
    LogSink(
      name: 'application',
      output: coloredConsoleOutput,
      minLevel: LogLevel.debug, // default — trace остаётся вне этого sink
      categories: {'application'},
    ),
    LogSink(
      name: 'protocol',
      output: protocolTraceOutput,
      minLevel: LogLevel.trace, // иначе default minLevel:debug отфильтрует logger.trace(...)
      categories: {'protocol'},
      enabled: false, // включается через setSinkEnabled, см. Decision 4
    ),
  ],
);
```

`AsyncRotatingFileOutput`/`AsyncFileOutput` (появились в `structured_log` 0.2.0-dev.2) — неблокирующие аналоги `rotatingFileOutput`/`fileOutput`: пишут через async `dart:io` API вместо `writeAsStringSync`, сериализуют записи через внутреннюю очередь (порядок гарантирован), а ошибка одной записи не останавливает очередь. Используются вместо sync-вариантов для **обоих** файловых sinks (protocol-trace и application-лог в release) — закрывает риск блокировки UI isolate, который раньше был явным пунктом в Risks (см. ниже).

Одна запись эмитится один раз через `BoundLogger.tryLog`, а пакет сам решает, в какие `LogSink` она попадает — по `minLevel` (default `LogLevel.debug`, т.е. sink без явного `minLevel` принимает все уровни) и `categories` каждого sink. Runtime-toggle protocol-trace sink — `StructlogConfiguration.setSinkEnabled('protocol', enabled: ...)` (мутирует `enabled` существующих `LogSink` **на месте**, без пересборки конфигурации/логгеров — подтверждено исходником).

Альтернатива (отклонена, актуальна только исторически): держать логику маршрутизации в `acp_client_core` через два отдельных Logger-инстанса. Отклонено теперь, когда пакет сам решает задачу — дублировать её в consumer'е больше нет смысла.

### 7. Явный `StructlogConfiguration`-инстанс вместо глобального singleton

Пакет по умолчанию работает через process-global mutable state: `StructlogConfiguration.current`/`.configure()` (static) и `getLogger()` (top-level функция, читающая `.current`). Но конструктор `BoundLogger(config, [context, correlation])` принимает `StructlogConfiguration` явным параметром — то есть можно полностью обойти глобальный singleton.

Решение: `CodeLabLoggingModule` создаёт один `StructlogConfiguration`-инстанс и передаёт его явно в `BoundLogger(...)` при биндинге Logger-порта, не вызывая `StructlogConfiguration.configure()`/`getLogger()`. Это соответствует §23 `layers-and-dependencies.md` (DI через composition root, не через global service locator) и не даёт нескольким `AcpClientApplication` (например, в параллельных тестах) непреднамеренно делить и мутировать один и тот же глобальный logging state.

### 8. Graceful shutdown ждёт `flushed` async-sinks

`AsyncFileOutput`/`AsyncRotatingFileOutput` (Decision 6) буферизуют записи во внутренней очереди — на момент вызова `dispose()` часть записей может быть ещё не сброшена на диск. `CodeLabLoggingModule` обязан сохранить ссылки на оба async-output инстанса (application-в-release и protocol-trace) и дождаться их `flushed`-future при остановке приложения — по аналогии с уже существующим `CodeLabRootLifecycle.dispose()` (`app_scope.dart:203`), который последовательно закрывает `shellCubit`/`transport`/`application`. Без этого шага последние diagnostic/protocol-trace записи перед закрытием (в т.ч. потенциально самые информативные — про причину завершения, §40 `observability.md`) рискуют не попасть в файл.

## Risks / Trade-offs

- [`structured_log` 0.2.0-dev.3 — всё ещё prerelease (`-dev`), API продолжает меняться между dev-версиями (например, `LogLevel.trace` появился только в dev.3) вплоть до стабильного 0.2.0] → пин на точную dev-версию в `pubspec.yaml` (не caret-диапазон); при выходе стабильного 0.2.0 — точечно свериться с changelog и обновить пин, не откладывая надолго, т.к. пакет полностью подконтролен команде.
- [Ring buffer теряет старые `DiagnosticEntry` в очень долгих сессиях] → не теряет данные безвозвратно: полный structured-вывод продолжает идти в `Logger`-sink (stdout/файл) независимо от bounded in-memory списка для UI; ring buffer ограничивает только память инспектора.
- [Confining `structured_log` только к `acp_client_core` означает, что `acp_protocol`/`acp_transports`, используемые отдельно от `acp_client_core` (гипотетически), не получат structured-вывод напрямую] → приемлемо: сегодня оба пакета потребляются только через `acp_client_core`; если появится независимый consumer, это отдельное архитектурное решение, а не часть этого change.
- [Ошибка конфигурации sink (например, недоступный путь для лог-файла на диске) может тихо потерять логи] → покрыто "per-sink error isolation" пакета (Decision 6) плюс собственный safe-fallback адаптера (no-op/stdout-only), не должен ронять приложение.
- [~~`fileOutput`/`rotatingFileOutput` пишут синхронно и могут тормозить UI isolate при высокочастотном protocol-trace~~ — **устранено в 0.2.0-dev.2**: `AsyncFileOutput`/`AsyncRotatingFileOutput` пишут асинхронно, не блокируя вызывающий isolate (Decision 6).] → остаточный риск — очередь async-записей не сброшена на shutdown, покрыт Decision 8 (`flushed`-await при `dispose()`).

## Open Questions

- Точный путь и rotation policy для лог-файла на macOS/Windows/Linux (включая `protocol.log`) — решается в рамках `docs/architecture/platform-integration.md` при реализации `CodeLabLoggingModule`, не фиксируется в этом design.
- Точные значения `maxSizeBytes`/`maxBackups` для `rotatingFileOutput` protocol-trace-логгера — оставлено на этап `tasks`/имплементации.
