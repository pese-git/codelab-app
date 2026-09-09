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

`structured_log` дорабатывается (силами автора пакета, апстрим) типизированным API context-binding под эти поля — единственная задача этого change со стороны пакета: принять уже существующие значения как параметры, не изобретать новую схему идентификаторов.

### 3. `DiagnosticEntry` не заменяется, а получает второй output

`_recordDiagnostic` продолжает создавать `DiagnosticEntry` (для inspector UI) **и** дополнительно передаёт тот же, уже прошедший `SecretRedactor`, набор полей в `Logger` — один redaction pass на оба потребителя, как и раньше. Дублирования redaction-логики не возникает.

`_diagnostics` (`acp_client_application.dart:99`) получает ring buffer cap. Число берётся из собственного примера `observability.md` §28 ("last 500 events") — не изобретается произвольно.

Альтернатива (отклонена): полностью заменить `DiagnosticEntry` на события, читаемые напрямую из `Logger`. Отклонено — ломает существующий, покрытый тестами контракт `AcpClientApplication.diagnostics`/`inspector_pane.dart` без необходимости; Non-Goal этого change — не трогать UI debug-панель.

### 4. Protocol tracing — отдельная категория/level, с собственным file sink

Полный ACP payload логируется только на `trace`-уровне (§8 `observability.md`), который по умолчанию выключен и не активируется автоматически при ошибке (§49) — включается явным debug/runtime действием. Логически это тот же Logger-порт с другим `category`/level (не отдельная подсистема) — но физически protocol trace (`category=protocol`) пишется в собственный ротируемый файл, отдельно от человекочитаемого application-лога в консоли (см. Decision 6 — technical reason: `structured_log` не умеет сам маршрутизировать одну запись на несколько outputs).

### 5. Композиция и конфигурация — в composition root `codelab_app`, по образцу существующих модулей

Logger-инстансы конструируются и настраиваются в новом `CodeLabLoggingModule` в `app_scope.dart`, по аналогии с уже существующим `CodeLabPlatformModule`. Presentation (`CodeLabShellCubit` и другие Cubit'ы, которым нужно логировать значимые user intents/UI failures) получают `Logger` через constructor injection из CherryPick-scope — так же, как сейчас получают use case'ы (`CreateSession`, `SendPrompt` и т.д.). Ни один widget не создаёт и не резолвит `Logger` напрямую (§6/§10 AGENTS.md, §36 `layers-and-dependencies.md`).

### 6. Два Logger-инстанса вместо одного multi-output: application-консоль и protocol-файл

`structured_log` не поддерживает мультиплексирование одной записи на несколько outputs и не имеет встроенной per-category маршрутизации — у одной конфигурации/`Logger` один `output` (проверено по документации пакета). Поэтому композиция в `CodeLabLoggingModule` создаёт **два independent Logger-инстанса** за одним и тем же портом:

- **application-логгер** — `output: coloredConsoleOutput` в debug (человекочитаемый, с ANSI-цветами, как просил пользователь для stdio/terminal) и JSON/`fileOutput` в release; получает события `component=client|transport|protocol-error` (см. Decision 1) и presentation-события;
- **protocol-trace-логгер** — `output: rotatingFileOutput('protocol.log', maxSizeBytes: …, maxBackups: …)`, включается только явным toggle (Decision 4), получает исключительно `category=protocol` trace-события полного ACP payload.

`AcpClientApplication`/адаptер сам решает, в какой из двух инстансов писать конкретное событие — маршрутизация по category реализуется на нашей стороне (в `acp_client_core`), а не средствами `structured_log`. Это не создаёт нового публичного API поверх Logger-порта — вызывающий код обращается к одному и тому же порту, выбор физического sink инкапсулирован в адаптере/composition root.

Альтернатива (отклонена): один `Logger`-инстанс с кастомным composite `Output`, который сам решает, писать ли запись в консоль или в файл. Отклонено на этом этапе — требует писать и поддерживать собственную реализацию `Output` внутри проекта вместо простой композиции двух готовых, уже задокументированных output-функций пакета; можно пересмотреть, если понадобится больше двух sinks одновременно.

## Risks / Trade-offs

- [`structured_log` v0.1.0 — API для типизированных correlation-полей ещё не существует, дорабатывается апстрим силами автора пакета в отдельном репозитории] → пин на точную версию в `pubspec.yaml`; пока типизированного API нет, correlation-поля передаются как обычный `Map<String, Object?>` context (пакет уже это поддерживает) — не блокирует эту итерацию.
- [Ring buffer теряет старые `DiagnosticEntry` в очень долгих сессиях] → не теряет данные безвозвратно: полный structured-вывод продолжает идти в `Logger`-sink (stdout/файл) независимо от bounded in-memory списка для UI; ring buffer ограничивает только память инспектора.
- [Confining `structured_log` только к `acp_client_core` означает, что `acp_protocol`/`acp_transports`, используемые отдельно от `acp_client_core` (гипотетически), не получат structured-вывод напрямую] → приемлемо: сегодня оба пакета потребляются только через `acp_client_core`; если появится независимый consumer, это отдельное архитектурное решение, а не часть этого change.
- [Ошибка конфигурации sink (например, недоступный путь для лог-файла на диске) может тихо потерять логи] → Logger-адаптер обязан иметь безопасный fallback (например, no-op/stdout-only при ошибке инициализации файлового sink), не должен ронять приложение.
- [Два независимых Logger-инстанса (application/protocol) могут разойтись в masking/correlation-логике, если их конфигурировать по отдельности] → оба инстанса создаются одной фабрикой в `acp_client_core` с общим `SecretRedactor`-processor и общей correlation-обвязкой (Decision 2/3); различается только `output`, не остальная конфигурация.

## Open Questions

- Точный путь и rotation policy для лог-файла на macOS/Windows/Linux (включая `protocol.log`) — решается в рамках `docs/architecture/platform-integration.md` при реализации `CodeLabLoggingModule`, не фиксируется в этом design.
- Точные значения `maxSizeBytes`/`maxBackups` для `rotatingFileOutput` protocol-trace-логгера — оставлено на этап `tasks`/имплементации.
