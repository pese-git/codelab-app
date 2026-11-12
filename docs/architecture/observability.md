# Observability в ACP Client

Этот документ определяет правила логирования, tracing, correlation и diagnostics в ACP Client.

Цели:

* сделать lifecycle ACP диагностируемым;
* быстро находить причины ошибок;
* связывать события между transport, session, request и tool call;
* не допускать утечки sensitive data;
* отделить debug diagnostics от production logging;
* сохранить разумный объём logs.

Связанные документы:

* `AGENTS.md`
* `docs/architecture/acp-boundary.md`
* `docs/architecture/session-lifecycle.md`
* `docs/architecture/streaming.md`
* `docs/architecture/concurrency.md`
* `docs/architecture/permissions.md`
* `docs/architecture/testing.md`

---

## 1. Основной принцип

Каждое значимое ACP/application событие должно быть диагностируемо без необходимости логировать весь payload целиком.

Предпочтительный подход:

```text
event
  + correlation ids
  + lifecycle state
  + outcome
```

вместо:

```text
dump everything
```

---

## 2. Уровни observability

Следует различать:

```text
application logging
protocol tracing
debug diagnostics
security audit
crash/error reporting
```

Это разные concerns.

Обычный logger НЕ ДОЛЖЕН автоматически считаться полноценным audit log или crash reporting system.

---

## 3. Logging ownership

Каждый layer логирует события своей ответственности.

### `codelab_acp_protocol`

Может логировать:

* parse failure;
* unsupported message;
* invalid schema;
* protocol version mismatch.

### `codelab_acp_transports`

Может логировать:

* connect/disconnect;
* process start/exit;
* stream closure;
* transport error.

### `codelab_client_acp`

Может логировать:

* session transitions;
* request lifecycle;
* reconnect;
* cancellation;
* permission lifecycle;
* stale/duplicate events.

### Presentation

Может логировать:

* significant user intents;
* UI-level failures;
* navigation diagnostics при необходимости.

Presentation НЕ ДОЛЖНА дублировать весь ACP trace.

---

## 4. Correlation identifiers

Для связанных событий следует использовать explicit identifiers.

По возможности:

* `session_id`;
* `request_id`;
* `message_id`;
* `tool_call_id`;
* `connection_generation`;
* `operation_id`.

Пример:

```text
event=request_completed
session_id=s-14
request_id=r-42
connection_generation=8
```

---

## 5. Connection generation

Local connection generation следует логировать при:

* connect;
* reconnect;
* stale event;
* disconnect;
* transport replacement.

Это помогает отличать late event старого transport от current connection.

---

## 6. Lifecycle transitions

Significant state transitions следует логировать в structured form.

Например:

```text
component=session
from=ready
to=running
request_id=r-42
```

или:

```text
component=connection
from=connected
to=reconnecting
reason=transport_closed
generation=8
```

---

## 7. Structured logging

Следует предпочитать structured fields вместо построения длинной строки вручную.

Предпочтительно:

```text
event=request_failed
request_id=r-42
reason=transport_lost
```

вместо:

```text
"Request r-42 failed because transport was lost"
```

Human-readable message может существовать дополнительно.

---

## 8. Log levels

Рекомендуемая semantics:

### trace

Очень подробные internal events.

Например:

* каждый streaming event;
* reducer decisions;
* deduplication details.

### debug

Диагностика development workflow.

Например:

* state transitions;
* reconnect attempts;
* protocol mapping details.

### info

Значимые нормальные lifecycle события.

Например:

* connected;
* session created;
* request completed.

### warning

Recoverable abnormal condition.

Например:

* reconnect attempt;
* stale event;
* unknown optional field;
* retryable failure.

### error

Operation failed или нарушен expected flow.

### fatal

Application не может безопасно продолжать работу.

Конкретные levels должны соответствовать project logger.

---

## 9. Не злоупотреблять `error`

Не каждое неожиданное событие является `error`.

Например:

```text
reconnect attempt 1
```

обычно warning/debug, а не error.

Иначе production logs становятся шумными.

---

## 10. Protocol tracing

ACP protocol tracing может существовать отдельно от обычного logging.

Он полезен для:

* debugging compatibility;
* расследования malformed messages;
* воспроизведения protocol flow.

Protocol tracing НЕ ДОЛЖЕН быть включён в release по умолчанию.

---

## 11. Full payload logging

Полный ACP payload МОЖЕТ логироваться только в debug/diagnostic mode, если это безопасно.

В production по умолчанию следует логировать:

* method/type;
* ids;
* size;
* sequence;
* outcome;

без полного content.

---

## 12. Sensitive data

Нельзя логировать без необходимости:

* API keys;
* auth tokens;
* passwords;
* credentials;
* secret environment variables;
* secure storage values;
* private file contents;
* user prompts целиком, если это чувствительные данные.

---

## 13. Masking

Sensitive value должно быть masked ДО передачи logger.

Например:

```text
token=sk-***redacted***
```

Нельзя рассчитывать на то, что downstream log collector сам всё скроет.

---

## 14. Structured redaction

Если payload имеет known sensitive fields, redaction should be schema-aware.

Например:

```text
authorization
token
api_key
password
secret
```

следует маскировать централизованно.

---

## 15. Tool-call logging

Для tool calls полезно логировать:

* tool name/capability;
* tool call id;
* session/request id;
* lifecycle;
* permission outcome.

Не следует по умолчанию логировать полный arguments payload.

---

## 16. Permission logging

Для permission flow полезно логировать:

```text
permission_requested
permission_auto_allowed
permission_auto_denied
permission_user_allowed
permission_user_denied
permission_stale
```

с correlation identifiers.

---

## 17. Security-sensitive actions

Для dangerous operations следует логировать минимум:

* action type;
* target summary;
* decision;
* correlation;
* outcome.

Но logs не должны превращаться в копию sensitive payload.

---

## 18. User decision

User decision следует логировать как факт:

```text
decision=allow
scope=once
```

без ненужных personal details.

---

## 19. Streaming logs

Не следует логировать каждый text token на обычном `debug/info`.

Для high-frequency stream полезнее:

```text
request_id=r-42
event=chunk_received
seq=18
size=124
```

на `trace`, если tracing включён.

---

## 20. Duplicate event

Duplicate/stale event полезно логировать:

```text
event=ignored
reason=duplicate
request_id=r-42
seq=18
```

или:

```text
reason=stale_generation
```

Это критично для диагностики reconnect races.

---

## 21. Error context

Error log должен содержать context, достаточный для поиска причины.

Например:

```text
component=transport
operation=connect
generation=7
error_type=ProcessExitFailure
```

а не только:

```text
Something went wrong
```

---

## 22. Exception stack trace

Stack trace следует сохранять для unexpected internal exceptions.

Expected typed failure не всегда требует stack trace.

---

## 23. Error normalization

Logger должен различать:

```text
expected application failure
unexpected exception
programming error
```

Не следует писать stack trace для каждого validation failure.

---

## 24. Crash reporting

Если используется crash reporting system, он должен получать:

* normalized error;
* stack trace;
* app version;
* platform;
* non-sensitive correlation context.

Нельзя автоматически прикладывать full ACP payload.

---

## 25. Breadcrumbs

Полезные breadcrumbs:

```text
connected
session_created
prompt_sent
tool_requested
permission_allowed
connection_lost
reconnect_started
```

помогают понять crash context без full trace.

---

## 26. Session correlation

Если crash происходит во время session, можно прикладывать session identifier, если это безопасно.

Identifier не должен содержать sensitive data сам по себе.

---

## 27. Debug diagnostics panel

В debug build может существовать diagnostics panel.

Он может показывать:

* connection state;
* current session id;
* request ids;
* active tool calls;
* connection generation;
* recent protocol events.

Не следует включать такой panel в release без product decision.

---

## 28. Ring buffer

Для recent debug events полезен bounded ring buffer.

Например:

```text
last 500 events
```

вместо бесконечного списка.

---

## 29. Memory limits

Diagnostics buffer должен иметь bounded memory.

Особенно нельзя хранить:

* все streaming chunks;
* все raw payload;
* бесконечную history transport events.

---

## 30. Performance

Logging не должен заметно влиять на streaming/rendering performance.

Для high-frequency events следует:

* снижать level;
* aggregate;
* sample;
* lazy-format fields.

---

## 31. Lazy serialization

Не следует сериализовать большой payload только для log, если текущий log level отключён.

---

## 32. `print` и `debugPrint`

Production code НЕ ДОЛЖЕН использовать:

```dart
print(...)
debugPrint(...)
```

как основной logging mechanism.

Использовать project logger.

---

## 33. Logger abstraction

Logger должен предоставляться через shared/core abstraction или установленный project mechanism.

Application code не должен зависеть от конкретного backend logger без необходимости.

---

## 34. Logger DI

Если logger является dependency, его следует передавать через DI/composition root.

Не следует создавать новый logger instance в каждом feature.

---

## 35. Categories/components

Useful log categories:

```text
protocol
transport
client
session
streaming
permissions
platform
persistence
ui
terminal
```

Это помогает фильтровать diagnostics.

`terminal` — панель Terminal десктопа (терминал пользователя; change [`add-integrated-terminal`](../../openspec/changes/add-integrated-terminal/design.md), D9), логгер `codelab_desktop.terminal`. Ввод и вывод терминала **не логируются вовсе**: их нет в журнале, `LogBuffer`, debug log, пересылке логов, диагностике рабочего места и инспекторе. Редакция секретов (§13–§14) к ним не применяется, потому что редактировать нечего — содержимое не покидает экран. События — только метаданные:

* `terminal.tab_opened` — `tab_id`, `session_id` (сессия-владелец вкладки, корреляционный идентификатор §16 `AGENTS.md`), `shell` (базовое имя исполняемого файла), `columns`, `rows`; остальные события ссылаются на вкладку по `tab_id`;
* `terminal.tab_exited` — `tab_id`, `exit_code` (поля нет, если PTY-бэкенд кода не сообщил);
* `terminal.tab_closed` — `tab_id`, `forced` (понадобился ли `kill` — и при закрытии вкладки, и при выходе из app);
* `terminal.start_failed` — `tab_id`, `reason` — вариант ошибки старта (`shellNotFound`, `folderNotFound`, `ptyUnavailable`); для неожиданной ошибки — `reason: ptyUnavailable` и `error_type` (`runtimeType`) без текста и стека: текст `Error` может содержать путь;
* `terminal.exit_wait_failed` — `tab_id`, `error_type` — имя типа ошибки ожидания выхода (`exitCode` порта завершился ошибкой; вкладка становится «exited» без кода);
* `terminal.link_opened`, `terminal.link_refused` — только `scheme` (схема адреса ссылки OSC 8), без адреса; `link_refused` — и для запрещённой схемы, и для адреса с bidi, нулевой шириной или управляющими символами;
* `terminal.close_all` — `count`, `forced`;
* `terminal.signal_failed` — `tab_id`, `signal` (`hangup` или `kill`), `error_type`: сигнал вкладке бросил исключение, закрытие остальных продолжается;
* `app.exit_requested` (компонент `app`) — ОС запросила выход, без полей;
* `app.exit_close_failed` (компонент `app`) — `error_type`: закрытие при выходе бросило целиком, выход не отменяется;
* `app.exit_closed` (компонент `app`) — `duration_ms`: закрытие root scope при выходе уложилось в предел;
* `app.exit_timeout` (компонент `app`, `warning`) — `timeout_ms`, `pending` (имена всех незавершённых шагов, в том числе не начатых, из закрытого набора `terminal`, `cubits`, `workspace`, `embedded`, `migration_offer`, `transport`, `client`): предел выхода истёк, app всё равно выходит;
* `app.shutdown_step_failed` (компонент `app`, `error`) — `step`, `error_type`: шаг закрытия root scope бросил, следующие шаги выполняются.

События `app.exit_*` и `app.shutdown_step_failed` — change [`add-client-process-shutdown-on-exit`](../../openspec/changes/add-client-process-shutdown-on-exit/design.md), D6. Ядро клиента пишет `terminal_processes_killed` — `count`, `reason` (`connection_closed` | `dispose`), без команд, путей и идентификаторов терминалов; событие пишется после отправки сигналов, сбой журнала не мешает завершению процессов. Ответ на `terminal/*`, не отправленный из-за смены соединения или закрытия ядра, виден как `event_ignored {reason: stale_generation, kind}` (`kind`: `terminal_create_result` или `terminal_response`; §20, D15 change).

Путей, окружения, аргументов и `toString()` исключений в них нет (§43–§45).

---

## 36. Operation duration

Для значимых операций полезно логировать duration:

* connect;
* session create;
* reconnect;
* request completion;
* persistence;
* process startup.

Например:

```text
operation=connect
duration_ms=482
outcome=success
```

---

## 37. Performance metrics

Если metrics subsystem появится, его следует отделять от обычных logs.

Metrics подходят для:

* latency;
* reconnect count;
* failure rate;
* request duration.

Logs — для диагностического контекста.

---

## 38. Retry logging

Retry следует логировать с attempt number.

Например:

```text
event=reconnect_attempt
attempt=2
max_attempts=5
```

Не следует логировать один и тот же stack trace на каждой retry попытке, если это создаёт шум.

---

## 39. Final retry failure

Когда retry policy exhausted, final error должен быть явно виден.

Например:

```text
event=reconnect_failed
attempts=5
outcome=terminal
```

---

## 40. Shutdown logging

Orderly shutdown полезно логировать:

```text
shutdown_started
session_closed
transport_closed
agent_process_terminated
shutdown_completed
```

Это помогает находить orphan resources.

В CodeLab desktop эту роль играют `app.exit_requested` (shutdown_started), `terminal.close_all` и `terminal_processes_killed` (процессы закрыты), `embedded.close_timeout` и `app.exit_closed` / `app.exit_timeout {pending}` (shutdown_completed или что не успело); см. события компонента `app` выше.

---

## 41. Unexpected shutdown

Unexpected process/transport exit должен отличаться от intentional shutdown.

Иначе diagnostics будет путать нормальное закрытие с failure.

---

## 42. Platform context

При platform error полезно включать:

* OS;
* operation;
* capability;
* adapter.

Не нужно логировать лишние machine identifiers.

---

## 43. File paths

Filesystem path может содержать sensitive information.

Следует решить, можно ли логировать:

* full path;
* basename;
* workspace-relative path;
* redacted path.

По умолчанию предпочтителен минимально достаточный вариант.

---

## 44. Commands

Shell command logging может быть sensitive.

В production лучше логировать:

```text
executable=git
operation=process_run
```

чем полный command line, если arguments могут содержать secrets.

---

## 45. Environment

Environment variables целиком логировать запрещено.

---

## 46. Network endpoints

Host/port обычно можно логировать, если это не sensitive.

Authorization headers, tokens и query secrets — нельзя.

---

## 47. ACP methods

Method/type ACP обычно полезно логировать.

Например:

```text
direction=inbound
method=session/update
request_id=r-42
```

при условии, что method name сам по себе не sensitive.

---

## 48. Debug vs release

Следует иметь явную разницу:

### Debug

* более подробные logs;
* protocol trace;
* diagnostics panel;
* state transitions.

### Release

* bounded structured logs;
* masked payload;
* без full protocol dump;
* без developer-only diagnostics.

---

## 49. Runtime enabling diagnostics

Если full diagnostics можно включить в runtime, это должно быть explicit user/developer action.

Нельзя включать sensitive tracing автоматически после любой ошибки.

---

## 50. Export diagnostics

Если приложение позволяет экспортировать diagnostic bundle, необходимо:

* маскировать secrets;
* предупреждать о возможных sensitive data;
* ограничивать объём;
* включать app/platform version;
* включать correlation data.

---

## 51. Diagnostic bundle

Potential contents:

```text
app version
platform
recent lifecycle events
recent protocol metadata
error summaries
configuration summary
```

не обязательно:

```text
all prompts
all file contents
all environment variables
```

---

## 52. Testing observability

Следует тестировать минимум:

* secrets masked;
* stale event содержит correlation;
* lifecycle transition emits expected structured event;
* debug payload logging disabled in release configuration;
* permission decision logs without secret payload.

---

## 53. Logger tests

Не нужно проверять каждый log message дословно.

Тестировать следует semantic fields, если они являются важным contract diagnostics.

---

## 54. Error reporting tests

Unexpected exception должна сохранять:

* type;
* stack trace;
* correlation context.

Expected denial не должен ошибочно считаться crash.

---

## 55. Не логировать дважды

Если lower layer уже логирует transport error с полной technical context, upper layer может логировать application transition, но не обязательно повторять тот же stack trace.

Например:

```text
transport:
ProcessExited(exitCode=1)

application:
SessionState → reconnecting
```

Это полезнее двух одинаковых error logs.

---

## 56. Log ownership example

Хороший flow:

```text
codelab_acp_transports
    → transport closed

codelab_client_acp
    → connection state: connected → reconnecting

presentation
    → reconnect banner shown
```

Не нужно, чтобы каждый слой логировал:

```text
ERROR: CONNECTION LOST!!!
```

---

## 57. Audit trail

Если продукту потребуется security audit trail, нужно создать отдельный документ/модель.

Audit trail должен определять:

* какие действия фиксируются;
* immutable ли записи;
* retention;
* export;
* privacy;
* integrity.

Обычный application log этого не гарантирует.

---

## 58. PII и user data

User-generated content следует считать потенциально sensitive.

Не следует логировать:

* prompts;
* responses;
* filenames;
* tool output;

целиком без явной diagnostic необходимости.

---

## 59. Sampling

Sampling допустим для high-frequency informational events.

Не следует sampling critical errors или security decisions.

---

## 60. Correlation consistency

Один identifier должен иметь одинаковое имя во всех layers.

Например, не следует использовать одновременно:

```text
req
request
requestId
request_id
```

в structured logs.

Project logger должен иметь согласованный naming convention.

---

## 61. Suggested field naming

Рекомендуется snake_case:

```text
session_id
request_id
message_id
tool_call_id
connection_generation
operation
event
outcome
reason
duration_ms
```

---

## 62. Main invariants

### OBS-001 — Significant lifecycle диагностируем

Connection/session/request transitions имеют structured context.

### OBS-002 — Secrets masked

Sensitive values не записываются в logs в открытом виде.

### OBS-003 — Correlation explicit

Events можно связать через stable IDs/generation.

### OBS-004 — Debug trace bounded

Detailed tracing не создаёт unbounded memory/log growth.

### OBS-005 — Release не содержит full protocol dump по умолчанию

Raw payload tracing developer-only.

### OBS-006 — Layers логируют свою semantics

Transport не логирует UX, UI не дублирует protocol internals.

---

## 63. Checklist перед добавлением logging

Перед новым log event определить:

1. Зачем он нужен?
2. Какой layer владеет событием?
3. Какой level правильный?
4. Какие correlation fields нужны?
5. Есть ли sensitive data?
6. Нужен ли stack trace?
7. Может ли event происходить часто?
8. Нужен ли sampling/throttling?
9. Дублирует ли он lower-level log?
10. Полезен ли он для реальной диагностики?

---

## 64. Основная модель

Хорошая observability позволяет восстановить flow:

```text
connect
  ↓
session created
  ↓
request started
  ↓
streaming
  ↓
tool call
  ↓
permission allowed
  ↓
completion
```

через structured events и correlation IDs без необходимости хранить полный sensitive payload.

Если для расследования любой ошибки приходится добавлять `print()` в десяток мест, observability architecture недостаточна.
