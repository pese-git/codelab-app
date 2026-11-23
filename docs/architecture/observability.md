# Наблюдаемость в CodeLab

Документ задаёт правила журналирования, трассировки протокола, корреляции событий и диагностики в клиентах CodeLab (desktop, CLI) и в Dart-агенте.

Цели:

* сделать жизненный цикл ACP диагностируемым;
* быстро находить причины ошибок;
* связывать события транспорта, сессии, запроса и вызова инструмента;
* не допускать утечки чувствительных данных;
* отделить отладочную диагностику от журнала рабочей сборки;
* держать объём журналов разумным.

Общие правила — корневой `AGENTS.md` (§2, §9, §10, §12, §16), [`acp-boundary.md`](acp-boundary.md), [`session-lifecycle.md`](session-lifecycle.md), [`streaming.md`](streaming.md), [`concurrency.md`](concurrency.md), [`permissions.md`](permissions.md), [`error-handling.md`](error-handling.md), [`testing.md`](testing.md). Технология журнала — [`technology-stack.md`](technology-stack.md) §17. Журнал и трасса ядра агента — [`proposals/agent-core/12-observability-and-errors.md`](proposals/agent-core/12-observability-and-errors.md) (§12.3–§12.5).

Термины:

* **Журналирование** (application logging) — структурные записи о значимых событиях приложения: событие, уровень, поля, корреляция (§7).
* **Трассировка протокола** (protocol tracing) — запись каждого кадра ACP; у клиента — запись `protocol_message` и кадры `ProtocolFrame` (§10).
* **Корреляционный идентификатор** (correlation identifier) — поле, связывающее записи одной сессии, запроса, вызова инструмента или соединения: `session_id`, `request_id`, `tool_call_id`, `connection_generation` и др. (§4, §61).
* **Поколение соединения** (connection generation) — локальный номер экземпляра транспорта; растёт при каждой его замене (§5, `session-lifecycle.md` §15).
* **Маскирование** (masking, redaction) — замена значения секрета на `<redacted>` до того, как запись попадёт в журнал (§13, §14).
* **Политика payload** (payload policy) — решение, хранится ли полное содержимое кадра ACP (`full`) или только его метаданные (`metadataOnly`) (§48а).
* **Кольцевой буфер** (ring buffer) — буфер с пределом размера, вытесняющий самые старые записи (§28).
* **Sink** — получатель записей журнала: консоль, файл, буфер окна журнала, пересылка на dev-сервер.
* **Отладочная / рабочая сборка** (debug / release build) — режим сборки desktop-клиента; у CLI его роль играет флаг `--verbose` (§48).

Где в коде. Порт журнала клиента — `Logger` (`packages/dart/codelab_client_acp/lib/src/domain/logger.dart`: уровни `trace`, `debug`, `info`, `warning`, `error`, `critical`, связывание `bind`, корреляция `withCorrelation` с ключами `session_id`, `request_id`, `connection_generation`, `tool_call_id`, `message_id`, `operation_id`); адаптер на `structured_log` — `StructuredLogLogger`, процессор маскирования `secretRedactionProcessor`, настройка sinks `configureCodeLabLogging`, переключатель файла трассы `setProtocolTracingEnabled`, ключи `category` (`application`, `protocol`) и `component` (`protocol`, `transport`, `client`, `presentation`) (`lib/src/infrastructure/structured_log_logger.dart`). Маскирование — `SecretRedactor` (`lib/src/domain/secret_redaction.dart`). Протокольный клиент `AcpClientApplication` (`lib/src/application/acp_client_application.dart`): записи `connection_state_changed`, `event_ignored`, `protocol_message`, диагностика `DiagnosticEntry` (`lib/src/domain/domain_models.dart`) в кольцевом буфере на 500 записей (`_recordDiagnostic`, `_logDiagnosticEntry`), текст причины `_causeDetail`; кадры — `ProtocolFrame` и `ProtocolPayloadPolicy` (`lib/src/application/protocol_frame.dart`), их строит `ProtocolFrameRecorder` (`protocol_frame_recorder.dart`). Ядро клиента `codelab_client_core`: `ClientWorkspace` пишет в тот же порт `Logger` и публикует `WorkspaceDiagnostic` (`lib/src/diagnostics/diagnostics.dart`), буфер кадров — `ProtocolFrameLog` (`lib/src/protocol/protocol_frame_log.dart`), инспектор — `InspectorProjection` (`lib/src/inspector/inspector_projection.dart`). Desktop: модуль `CodeLabLoggingModule` (`apps/codelab_desktop/lib/app/app_scope.dart`) настраивает sinks — консоль в debug, `application.log` в release, `protocol.log` (выключен по умолчанию), буфер окна журнала `LogBuffer` (`structured_log_flutter`), необязательная пересылка `RemoteSyncLogOutput` на dev-сервер; окно журнала читает `LogBufferRecordSource` (`lib/app/log_buffer_record_source.dart`), панель Protocol — `ProtocolPaneCubit` и экспорт `protocol_export.dart` (`lib/features/protocol/application/`), журнал встроенного агента переводит `CodeLabEmbeddedLogger` (`lib/app/embedded_logger.dart`). CLI: `CliLogger` и `CliEmbeddedLogger` пишут в stderr только с `--verbose`, кроме событий `secrets.lookup` встроенного агента (имена и источник, без значений) при `--debug-secrets` или `CODELAB_DEBUG_SECRETS=1` (`apps/codelab_cli/lib/src/cli_logger.dart`, `embedded_logger.dart`). Агент: порт `Logger`, `LogLevel` (`trace` … `error`), `LogRecord`, `BoundLogger` (`packages/dart/codelab_agent_core/lib/src/util/logger.dart`), события вида `<область>.<действие>` (`llm.retry`, `permission.decided`); бинарь `codelab-agent` пишет журнал через `HostLogger` в stderr и, по `--log-file` или `CODELAB_LOG_FILE`, в файл JSON Lines (`apps/codelab_agent/lib/src/log/`).

---

## 1. Основной принцип

Каждое значимое событие ACP и приложения ДОЛЖНО быть диагностируемым без записи всего payload целиком.

Предпочтительный подход:

```text
событие
  + корреляционные идентификаторы
  + состояние жизненного цикла
  + исход
```

вместо:

```text
выгрузить всё
```

---

## 2. Виды наблюдаемости

СЛЕДУЕТ различать:

```text
журналирование приложения (application logging)
трассировку протокола (protocol tracing)
отладочную диагностику (debug diagnostics)
журнал аудита безопасности (security audit)
отчёты о сбоях и ошибках (crash/error reporting)
```

Это разные задачи.

Обычный логгер НЕ ДОЛЖЕН автоматически считаться полноценным журналом аудита или системой отчётов о сбоях.

В коде есть первые три вида: журналирование — категория `application`, трассировка — категория `protocol` и кадры `ProtocolFrame` (§10), отладочная диагностика — `DiagnosticEntry`, `WorkspaceDiagnostic`, инспектор и панель Protocol (§27). Журнала аудита (§57) и системы отчётов о сбоях (§24) нет.

---

## 3. Кто владеет журналированием

Каждый слой журналирует события своей ответственности.

### `codelab_acp_protocol`

МОЖЕТ журналировать:

* сбой разбора;
* неподдерживаемое сообщение;
* нарушение схемы;
* несовпадение версии протокола.

### `codelab_acp_transports`

МОЖЕТ журналировать:

* подключение и отключение;
* запуск и завершение процесса;
* закрытие потока;
* ошибку транспорта.

### `codelab_client_acp`

МОЖЕТ журналировать:

* переходы сессии;
* жизненный цикл запроса;
* переподключение;
* отмену;
* жизненный цикл разрешений;
* устаревшие и повторные события.

### Presentation

МОЖЕТ журналировать:

* значимые намерения пользователя;
* сбои уровня UI;
* при необходимости — диагностику навигации.

Presentation НЕ ДОЛЖНА дублировать всю трассу ACP.

В коде `codelab_acp_protocol` и `codelab_acp_transports` сами не журналируют и зависимости `structured_log` не имеют (`technology-stack.md` §17.1): протокол сообщает об ошибках исключениями (`JsonRpcProtocolException`, `AcpProtocolError`), транспорт — событиями `AcpTransportEvent` (`diagnostic`, `failure`). Записи о них пишет `AcpClientApplication` с ключом `component` — `protocol` или `transport` (константы `protocolComponent`, `transportComponent`); собственные события клиента — `component: client`. В app логгеры с `component` связывает composition root (`app_scope.dart`): `app`, `terminal`, `protocol`, `project_files`, `usage`, `onboarding`, `workbench`, `recent_projects`, `settings`, `secret_migration`; журнал встроенного агента получает `component: embedded` в адаптере `CodeLabEmbeddedLogger` (`embedded_logger.dart`). Ядро агента пишет в собственный порт `Logger`; куда идут записи, решает хост (`12-observability-and-errors.md` §12.3).

---

## 4. Корреляционные идентификаторы

Для связанных событий СЛЕДУЕТ использовать явные идентификаторы.

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

В коде клиент получает эти ключи через `Logger.withCorrelation` (`codelab_client_acp`): `StructuredLogLogger` передаёт их в `structured_log`, `CliLogger` кладёт в контекст под теми же именами в snake_case. Агент передаёт `session_id`, `tool_call_id`, `request_id` полями записи; постоянные поля связывает `BoundLogger`. Поля `messageId` в схеме ACP нет (`acp-boundary.md` §12), поэтому `message_id` в записях не заполняется.

---

## 5. Поколение соединения

Локальное поколение соединения СЛЕДУЕТ журналировать при:

* подключении;
* переподключении;
* устаревшем событии;
* отключении;
* замене транспорта.

Это помогает отличить позднее событие старого транспорта от событий текущего соединения.

В коде `AcpClientApplication` связывает `connection_generation` с записями о соединении, кадрах, диагностике и устаревших событиях (`withCorrelation(connectionGeneration: …)`). Устаревшее событие помечается поколением, которому оно принадлежит, а не текущим (`_logStaleEvent`).

---

## 6. Переходы жизненного цикла

Значимые переходы состояния СЛЕДУЕТ журналировать в структурном виде.

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

В коде все переходы соединения проходят через одну точку — `AcpClientApplication._transitionConnection`: запись `connection_state_changed` с `component: client`, полями `from`, `to` (имена классов состояния `ClientConnectionState`) и `connection_generation`; уровень `info`, для перехода в `ClientConnectionFailed` — `warning`. Переходы сессии и хода общей записью не журналируются; есть отдельные события — `turn_interrupted`, `turn_interrupt_marked`, `turn_interrupt_mark_rolled_back` (`codelab_client_acp`) и диагностика ядра клиента, например `Cancelled prompt turn <id>.` (`ClientWorkspace`).

---

## 7. Структурное журналирование

СЛЕДУЕТ предпочитать структурные поля длинной строке, собранной вручную.

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

Читаемое человеком сообщение МОЖЕТ существовать дополнительно.

В коде события app называются `<область>.<действие>` (`project.drop`, `protocol_pane.trace`, `app.exit_timeout`), события протокольного клиента — в snake_case (`connection_state_changed`, `event_ignored`, `request_timeout`). Исключение — записи диагностики `DiagnosticEntry`: `_logDiagnosticEntry` пишет их с читаемым текстом вместо имени события (`Failed to send ACP request session/prompt.`), а различающие поля — `source` и контекст. Так же пишется предупреждение `Unknown ACP tool kind treated as other.`.

---

## 8. Уровни журнала

Уровням СЛЕДУЕТ придавать такую семантику.

### trace

Очень подробные внутренние события.

Например:

* каждое потоковое событие;
* решения редьюсера;
* подробности устранения дублей.

### debug

Диагностика для разработки.

Например:

* переходы состояния;
* попытки переподключения;
* подробности преобразования протокола.

### info

Значимые штатные события жизненного цикла.

Например:

* соединение установлено;
* сессия создана;
* запрос завершён.

### warning

Восстановимое нештатное состояние.

Например:

* попытка переподключения;
* устаревшее событие;
* неизвестное необязательное поле;
* сбой, который можно повторить.

### error

Операция не удалась или нарушен ожидаемый ход работы.

### fatal

Приложение не может безопасно продолжать работу.

Конкретные уровни ДОЛЖНЫ соответствовать логгеру проекта.

В коде уровень `fatal` у клиента называется `critical` (порт `Logger`, `LogLevel` пакета `structured_log`); у порта `Logger` агента уровни `trace` … `error`, без `critical`. Что попадает в sink, решает его минимальный уровень: у sinks `structured_log` по умолчанию — `debug`, буфер окна журнала (`debug-panel`) и файл трассы `protocol.log` принимают с `trace` (`configureCodeLabLogging`); CLI пишет с `info` (`CliLogger`, `CliEmbeddedLogger`); бинарь агента — с уровня из `--log-level` или `CODELAB_LOG_LEVEL`, по умолчанию `info`. Устаревшее событие клиент пишет на уровне `debug` (`event_ignored`, `response_ignored`), а не `warning`, как в примере выше.

---

## 9. Не злоупотреблять `error`

Не каждое неожиданное событие является `error`.

Например:

```text
reconnect attempt 1
```

обычно `warning` или `debug`, а не `error`.

Иначе журнал рабочей сборки становится шумным.

---

## 10. Трассировка протокола

Трассировка протокола ACP МОЖЕТ существовать отдельно от обычного журналирования.

Она полезна для:

* отладки совместимости;
* расследования некорректных сообщений;
* воспроизведения хода обмена по протоколу.

Трассировка протокола НЕ ДОЛЖНА быть включена в release по умолчанию.

В коде у клиента два канала трассировки. Запись `protocol_message` (уровень `trace`, категория `protocol`) идёт в буфер окна журнала и в файл `protocol.log`; файл выключен по умолчанию и включается только явно — `setProtocolTracingEnabled`. Кадры `ProtocolFrame` идут в буфер `ProtocolFrameLog` панели Protocol (§27а). Что именно они содержат, решает политика payload (§48а). У агента трасса ACP — после MVP: ключи `logging.trace` и `logging.trace_payload` читаются, но не применяются (`12-observability-and-errors.md` §12.5).

---

## 11. Запись полного payload

Полный payload ACP МОЖЕТ журналироваться только в режиме отладки или диагностики и только если это безопасно.

В рабочей сборке по умолчанию СЛЕДУЕТ журналировать:

* метод или тип;
* идентификаторы;
* размер;
* порядковый номер;
* исход;

без полного содержимого.

Как это устроено у клиента — §48а.

---

## 12. Чувствительные данные

ЗАПРЕЩЕНО журналировать без необходимости:

* API-ключи;
* токены авторизации;
* пароли;
* учётные данные;
* секретные переменные окружения;
* значения из защищённого хранилища;
* содержимое приватных файлов;
* промпты пользователя целиком, если это чувствительные данные.

---

## 13. Маскирование

Чувствительное значение ДОЛЖНО маскироваться ДО передачи логгеру.

Например:

```text
token=sk-***redacted***
```

ЗАПРЕЩЕНО рассчитывать на то, что сборщик журналов дальше по цепочке сам всё скроет.

В коде клиент маскирует в процессе: процессор `secretRedactionProcessor` стоит первым в цепочке `structured_log` и действует для всех sinks (`configureCodeLabLogging`); `CliLogger` и `CliEmbeddedLogger` прогоняют контекст через `SecretRedactor` сами; `_recordDiagnostic` маскирует текст и контекст `DiagnosticEntry` до хранения. Журнал бинаря `codelab-agent` (`HostLogger`) маскирования не делает — оно отложено до после 1.0 (`12-observability-and-errors.md` §12.4); до тех пор действует правило ядра (§12.3): значения секретов не пишутся ни в одно событие на любом уровне, а тексты сообщений и аргументы инструментов — только на уровне `debug`. У встроенного агента записи проходят маскирование журнала клиента (`CodeLabEmbeddedLogger`, `CliEmbeddedLogger`).

---

## 14. Маскирование по схеме

Если у payload есть известные чувствительные поля, маскированию СЛЕДУЕТ учитывать схему.

Маскирование централизовано в `SecretRedactor` (`codelab_client_acp`); правила — требование spec `approval-safety` «Редактирование секретов», решения — design.md change `extend-secret-name-redaction` (D1–D7):

* **Секретные слова в имени** (регистр не важен): `api_key`, `auth`, `authorization`, `bearer`, `cookie`, `credential`, `jwt`, `pass`/`password`, `private_key`, `secret`, `session_token`/`session_cookie`/`session_secret`/`session_key`, `token`. Голое `session` (`sessionId`) — корреляционный идентификатор, не секрет.
* **Признаки `key`**: последний сегмент `_key`/`-key` (`OPENAI_KEY`, `X-Functions-Key`, `Ocp-Apim-Subscription-Key`), `access_key` в любом месте (`AWS_ACCESS_KEY_ID`, `accessKeyId`), camelCase `…Key` (`openaiKey`). Имя `key` целиком, `keyboard`, `monkey`, `key_count`, `KEY_ID` секретами не считаются; `cache_key`, `primary_key`, `public_key`, `hotKey` скрываются осознанно.
* **Счётчики токенов**: число под именем `tokens`, `tokens_*`, `*_tokens` видно, если остаток имени не секретный и не содержит сегмента-стоп-слова (`access`, `refresh`, `id`, `csrf`, `otp`, `pin`, `session`, `key`).
* **Текст**: PEM-блок приватного ключа (без строки `END` — до конца текста), значение заголовка авторизации (`Bearer …`), userinfo адреса (`postgres://user:pass@host` → `postgres://<redacted>@host`, любая схема с `://`), значение присваивания `имя=значение` / `имя: значение` с секретным именем по тем же словам и признакам `key`.
* Пары `{name, value}` (`HttpHeader`, `EnvVariable`) сверяют `name` с тем же правилом имён, отдельного списка нет (правило пары вводит change `redesign-protocol-pane`).
* Все шаблоны работают за линейное время по длине текста: маскируются большие payload, и квадратичный откат на длинной строке без разделителей недопустим.

### 14а. Секрет в паре `name`/`value`

Источник — change [`redesign-protocol-pane`](../../openspec/changes/redesign-protocol-pane/design.md), D4.

* Централизованное маскирование клиента — `SecretRedactor` (`codelab_client_acp`). Оно скрывает значение по имени **ключа**. В ACP заголовки HTTP и переменные окружения MCP-серверов — объекты `{name, value}` (`HttpHeader`, `EnvVariable`, `docs/protocols/acp/protocol/17-Schema.md`): имя секрета лежит в значении поля `name`, а сам секрет — под нейтральным ключом `value`. Правило по ключу такой секрет не видит.
* Поэтому правило имён применяется и к паре: если у объекта есть строковое `name`, подпадающее под правило секретных имён (с тем же исключением для счётчиков токенов), и есть ключ `value`, значение `value` заменяется на `<redacted>`. Остальные поля объекта маскируются как раньше. Пример: `{"name": "Authorization", "value": "<redacted>"}`, `{"name": "GITHUB_TOKEN", "value": "<redacted>"}`, а `{"name": "PATH", "value": "/usr/bin"}` остаётся открытым.
* Это расширение существующего правила, а не второй набор правил: оно действует везде, где уже работает `SecretRedactor`, — записи журнала, диагностика, кадры панели Protocol (§27а).
* Пара выбрана по схеме ACP. Другие пары (`key`/`val`) не трогаются — в ACP их нет. ЗАПРЕЩЕНО маскировать `value` любого объекта с `name`: кадры потеряли бы безвредные данные (`ResourceLink`, переменная `PATH`) и стали бы бесполезны для отладки.
* Цена: слово из правила имён внутри безвредного имени (`AUTHOR` содержит `auth`) скрывает значение. Это свойство общего правила имён, отдельных исключений нет.

---

## 15. Журналирование вызовов инструментов

Для вызовов инструментов полезно журналировать:

* имя инструмента или возможность;
* id вызова инструмента;
* id сессии и запроса;
* жизненный цикл;
* исход проверки разрешения.

НЕ СЛЕДУЕТ по умолчанию журналировать полный payload аргументов.

В коде вызовы инструментов журналирует агент: события `permission.asked` и `permission.denied` (§16) несут `tool_call_id` и имя инструмента `tool`, `permission.decided` — `tool_call_id` и `decision`; аргументов нет. Клиент отдельных записей о вызовах инструментов не пишет — они видны в трассе протокола (`protocol_message`, кадры).

---

## 16. Журналирование разрешений

Для потока разрешений полезно журналировать:

```text
permission_requested
permission_auto_allowed
permission_auto_denied
permission_user_allowed
permission_user_denied
permission_stale
```

с корреляционными идентификаторами.

В коде имена другие. Агент (`codelab_agent_core/lib/src/permissions/policy.dart`): `permission.asked` (`debug`; `tool_call_id`, `tool`, `tier`, `critical`), `permission.decided` (`debug`; `tool_call_id`, `decision`), `permission.denied` (`info`; `tool_call_id`, `tool`, `reason`). Клиент: диагностика `Pending permission request dropped: <reason>` (`warning`, `source: application.permission`) при снятии одобрения оборванного соединения и `Resolved approval <id> (<status>).` ядра клиента (`WorkspaceDiagnostic` с `source: approval`).

---

## 17. Действия, значимые для безопасности

Для опасных операций СЛЕДУЕТ журналировать минимум:

* тип действия;
* краткое описание цели;
* решение;
* корреляцию;
* исход.

Но журнал НЕ ДОЛЖЕН превращаться в копию чувствительного payload.

---

## 18. Решение пользователя

Решение пользователя СЛЕДУЕТ журналировать как факт:

```text
decision=allow
scope=once
```

без лишних персональных подробностей.

---

## 19. Журналирование потоков

НЕ СЛЕДУЕТ журналировать каждый текстовый токен на обычных уровнях `debug` и `info`.

Для высокочастотного потока полезнее:

```text
request_id=r-42
event=chunk_received
seq=18
size=124
```

на уровне `trace`, если трассировка включена.

В коде так устроена запись `protocol_message`: одна запись `trace` на кадр с `direction`, `kind`, `method`, `size` и корреляцией (§48а).

---

## 20. Повторное событие

Повторное или устаревшее событие полезно журналировать:

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

Это критично для диагностики гонок при переподключении.

В коде: `event_ignored` с `reason: stale_generation`, `kind` (например, `inbound_message`, `transport_event`, `send_prompt_result`, `operation_result`; для ответов на `terminal/*` — `terminal_create_result`, `terminal_response` с `method` и `request_id`) и поколением события; ответ без ожидающего запроса — `response_ignored` с `reason: no_pending_request`. Оба на уровне `debug` (§8).

---

## 21. Контекст ошибки

Запись об ошибке ДОЛЖНА содержать контекст, достаточный для поиска причины.

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

## 22. Стек исключения

Стек СЛЕДУЕТ сохранять для неожиданных внутренних исключений.

Ожидаемый типизированный сбой не всегда требует стека.

В коде порт `Logger` клиента параметра для стека не имеет; у порта агента он есть (`stack` в `Logger.log`, `LogRecord.stack`). Подробности — `error-handling.md` §21.

---

## 23. Разделение ошибок

Логгер ДОЛЖЕН различать:

```text
ожидаемый сбой приложения
неожиданное исключение
ошибку программиста
```

НЕ СЛЕДУЕТ писать стек для каждого сбоя проверки.

---

## 24. Отчёты о сбоях

Если используется система отчётов о сбоях, она ДОЛЖНА получать:

* нормализованную ошибку;
* стек;
* версию приложения;
* платформу;
* нечувствительный корреляционный контекст.

ЗАПРЕЩЕНО автоматически прикладывать полный payload ACP.

В коде системы отчётов о сбоях нет.

---

## 25. Хлебные крошки

Полезные хлебные крошки (breadcrumbs):

```text
connected
session_created
prompt_sent
tool_requested
permission_allowed
connection_lost
reconnect_started
```

Они помогают понять контекст сбоя без полной трассы.

---

## 26. Корреляция с сессией

Если сбой происходит во время сессии, к отчёту МОЖНО прикладывать идентификатор сессии, если это безопасно.

Идентификатор сам по себе НЕ ДОЛЖЕН содержать чувствительных данных.

---

## 27. Панель отладочной диагностики

В отладочной сборке МОЖЕТ существовать панель диагностики.

Она МОЖЕТ показывать:

* состояние соединения;
* id текущей сессии;
* id запросов;
* активные вызовы инструментов;
* поколение соединения;
* недавние события протокола.

НЕ СЛЕДУЕТ включать такую панель в release без решения продукта.

### 27а. Панель Protocol desktop-клиента: решение продукта

Источник — change [`redesign-protocol-pane`](../../openspec/changes/redesign-protocol-pane/design.md), D3, D5, D17; решение пользователя 2026-11-22 (Q7).

Панель Protocol (кадры ACP соединения и вид Log над журналом app) **есть в release-сборке**. Это и есть решение продукта, которого требует абзац выше. Его условия:

* **По умолчанию в release — только метаданные кадра**: направление, вид, метод, id, `session_id`, поколение соединения, краткая подробность из полей схемы, код ошибки, размер. Payload кадра не строится и в памяти не хранится; текст `error.message` агента тоже не хранится — в нём бывают пути и фрагменты данных. Политику задаёт хост (§48а).
* **Полные payload кадров в release — только в режиме Trace**: явное включение в самой панели, не сохраняется между запусками (§49а). Debug-сборка хранит payload всегда.
* **Секреты маскируются до хранения при любой политике** (§13, §14, §14а). Copy и Export берут только замаскированное.
* **Память ограничена** (§28, §29): буфер кадров `ProtocolFrameLog` (`codelab_client_core`) — 2000 кадров и 8 MiB payload; буфер один на рабочее пространство (`ClientWorkspace`), а не на сессию, и переподключение его не очищает — кадры несут поколение соединения (Q6). Payload больше 256 KiB не хранится. Буфер живёт только в памяти.
* **Вид Log** показывает тот же `LogBuffer`, что и полноэкранный просмотр; содержимое записей `protocol_message` определяет базовая политика (§48а), Trace его не меняет.

---

## 28. Кольцевой буфер

Для недавних отладочных событий полезен кольцевой буфер с пределом.

Например:

```text
последние 500 событий
```

вместо бесконечного списка.

В коде: `AcpClientApplication` хранит последние 500 записей `DiagnosticEntry` (`_maxDiagnostics`), `LogBuffer` окна журнала app — 500 записей (ёмкость по умолчанию `structured_log_flutter`), `ProtocolFrameLog` — 2000 кадров и 8 MiB payload (§27а).

---

## 29. Пределы памяти

Буфер диагностики ДОЛЖЕН быть ограничен по памяти.

Особенно ЗАПРЕЩЕНО хранить:

* все потоковые чанки;
* все сырые payload;
* бесконечную историю событий транспорта.

В коде, кроме буферов §28, есть неограниченный список: `_recordDiagnostic` дописывает каждую запись `DiagnosticEntry` в `AcpSession.diagnostics` всех известных сессий, и этот список не усекается. На диске: `protocol.log` ротируется (10 MiB, 5 копий), а `application.log` release-сборки desktop и файл `--log-file` бинаря агента дописываются без ротации.

---

## 30. Производительность

Журналирование НЕ ДОЛЖНО заметно влиять на производительность потоков и отрисовки.

Для высокочастотных событий СЛЕДУЕТ:

* понижать уровень;
* агрегировать;
* делать выборку;
* форматировать поля лениво.

---

## 31. Ленивая сериализация

НЕ СЛЕДУЕТ сериализовать большой payload только ради журнала, если текущий уровень журнала выключен.

---

## 32. `print` и `debugPrint`

Рабочий код НЕ ДОЛЖЕН использовать:

```dart
print(...)
debugPrint(...)
```

как основной механизм журналирования.

Использовать логгер проекта.

В коде правило `avoid_print` включено в корневом `analysis_options.yaml`.

---

## 33. Абстракция логгера

Логгер ДОЛЖЕН предоставляться через общую абстракцию ядра или установленный механизм проекта.

Код приложения НЕ ДОЛЖЕН без необходимости зависеть от конкретной реализации журнала.

В коде это порты `Logger` клиента (`codelab_client_acp`) и агента (`codelab_agent_core`); от `structured_log` зависят только `codelab_client_acp` (адаптер `StructuredLogLogger`) и `apps/codelab_desktop` (настройка sinks).

---

## 34. Внедрение логгера

Если логгер — зависимость, его СЛЕДУЕТ передавать через DI и composition root.

НЕ СЛЕДУЕТ создавать новый экземпляр логгера в каждой feature.

В коде `AcpClientApplication` и `ClientWorkspace` принимают `Logger` параметром; без него берут `StructuredLogLogger` (`codelab_client_acp`, `codelab_client_core`), который читает глобальную настройку `structured_log` — осознанное исключение из запрета глобального локатора (design.md change `add-structured-logging`, D7). Логгеры app с `component` создаёт composition root (`app_scope.dart`).

---

## 35. Категории и компоненты

Полезные категории журнала:

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

Это помогает фильтровать диагностику.

В коде ключ `category` различает только два канала — `application` и `protocol` (по нему sinks выбирают записи, §48а); область записи задаёт ключ `component` (§3).

`terminal` — панель Terminal десктопа (терминал пользователя; change [`add-integrated-terminal`](../../openspec/changes/archive/2026-11-22-add-integrated-terminal/design.md), D9), логгер `codelab_desktop.terminal`. Ввод и вывод терминала **не логируются вовсе**: их нет в журнале, `LogBuffer`, debug log, пересылке логов, диагностике рабочего места и инспекторе. Редакция секретов (§13–§14) к ним не применяется, потому что редактировать нечего — содержимое не покидает экран. События — только метаданные:

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
* `app.exit_timeout` (компонент `app`, `warning`) — `timeout_ms`, `pending` (имена всех незавершённых шагов, в том числе не начатых, из закрытого набора `terminal`, `cubits`, `workspace`, `embedded`, `migration_offer`, `transport`, `client`, `language`; `language` — только если в root scope есть `AppLanguageCubit`, change `add-desktop-localization`, D2): предел выхода истёк, app всё равно выходит;
* `app.shutdown_step_failed` (компонент `app`, `error`) — `step`, `error_type`: шаг закрытия root scope бросил, следующие шаги выполняются.

События `app.exit_*` и `app.shutdown_step_failed` — change [`add-client-process-shutdown-on-exit`](../../openspec/changes/archive/2026-11-13-add-client-process-shutdown-on-exit/design.md), D6. Протокольный клиент (`AcpClientApplication`) пишет `terminal_processes_killed` — `count`, `reason` (`connection_closed` | `dispose`), без команд, путей и идентификаторов терминалов; событие пишется после отправки сигналов, сбой журнала не мешает завершению процессов. Ответ на `terminal/*`, не отправленный из-за смены соединения или закрытия ядра, виден как `event_ignored {reason: stale_generation, kind}` (`kind`: `terminal_create_result` или `terminal_response`; §20, D15 change).

Уведомление `_codelab/session/usage` (change `add-usage-extension`, D14, D21 Т5, D22): клиентский слой `codelab_client_acp` пишет DEBUG `usage.received` — `session_id`, `seq`, `trigger` (только `step`, `turn` или `compaction`, любое другое значение — `other`; без токенов и денег; payload — только в трассировке `category=protocol`) и DEBUG `usage.dropped` — `reason` (уведомление без строкового `sessionId` отброшено до ядра клиента; без payload). Ядро клиента (`ClientWorkspace`, необязательный `Logger`) пишет DEBUG `usage.stale` — `session_id`, `seq`, `last_seq`, `connection_generation` (дубль или опоздание по правилу `seq`), DEBUG `usage.unknown_session` — `session_id`, `connection_generation` (снимок сессии, которой нет в рабочем пространстве) и WARNING `usage.decode_failed` — `session_id`, `field`, `reason`, `connection_generation`, не чаще раза на сессию и поле. Сумм, цен и текста уведомления в записях нет.

Путей, окружения, аргументов и `toString()` исключений в них нет (§43–§45).

---

## 36. Длительность операций

Для значимых операций полезно журналировать длительность:

* подключения;
* создания сессии;
* переподключения;
* завершения запроса;
* сохранения данных;
* запуска процесса.

Например:

```text
operation=connect
duration_ms=482
outcome=success
```

В коде `duration_ms` пишут, например, `app.exit_closed` (app), `acp.usage.ledger` и `acp.usage.seeded` (ACP-проекция агента).

---

## 37. Метрики производительности

Если появится подсистема метрик, её СЛЕДУЕТ отделять от обычных журналов.

Метрики подходят для:

* задержек;
* числа переподключений;
* доли сбоев;
* длительности запросов.

Журналы — для диагностического контекста.

В коде подсистемы метрик нет. Учёт токенов, стоимости и длительности хода (usage) агент передаёт клиенту не журналом, а расширением `_codelab/session/usage` (`12-observability-and-errors.md` §12.6).

---

## 38. Журналирование повторов

Повтор СЛЕДУЕТ журналировать с номером попытки.

Например:

```text
event=reconnect_attempt
attempt=2
max_attempts=5
```

НЕ СЛЕДУЕТ записывать один и тот же стек на каждой попытке, если это создаёт шум.

В коде у клиента автоматических повторов переподключения нет (`error-handling.md` §79). Агент пишет `llm.retry` (`info`; `attempt`, `class`, `delay_ms`, `provider`, `model`, без `max_attempts`).

---

## 39. Окончательный сбой повторов

Когда политика повторов исчерпана, итоговая ошибка ДОЛЖНА быть явно видна.

Например:

```text
event=reconnect_failed
attempts=5
outcome=terminal
```

---

## 40. Журналирование завершения

Штатное завершение полезно журналировать:

```text
shutdown_started
session_closed
transport_closed
agent_process_terminated
shutdown_completed
```

Это помогает находить ресурсы, оставшиеся без владельца.

В CodeLab desktop эту роль играют `app.exit_requested` (shutdown_started), `terminal.close_all` и `terminal_processes_killed` (процессы закрыты), `embedded.close_timeout` и `app.exit_closed` / `app.exit_timeout {pending}` (shutdown_completed или что не успело); см. события компонента `app` выше.

---

## 41. Неожиданное завершение

Неожиданное завершение процесса или транспорта ДОЛЖНО отличаться от намеренного завершения.

Иначе диагностика будет путать штатное закрытие со сбоем.

---

## 42. Контекст платформы

При ошибке платформы полезно включать:

* ОС;
* операцию;
* возможность;
* адаптер.

Лишние идентификаторы машины журналировать не нужно.

---

## 43. Пути файлов

Путь в файловой системе может содержать чувствительную информацию.

СЛЕДУЕТ решить, что можно журналировать:

* полный путь;
* базовое имя;
* путь относительно рабочей папки;
* замаскированный путь.

По умолчанию предпочтителен минимально достаточный вариант.

### 43а. Путь проекта в desktop-клиенте

Источник — change [`add-empty-project-screen`](../../openspec/changes/archive/2026-11-22-add-empty-project-screen/design.md), D4, D7.

* Путь выбранной папки проекта **не считается чувствительным полем**. Пользователь выбрал его сам, он виден в интерфейсе, а диагностика — журнал app на этой машине. Поэтому полный путь пишется в диагностику (`WorkspaceDiagnostic`): `Selected project: <path>.`, `Project folder not found: <path>. …`, `Dropped item rejected (<reason>): <path>.`.
* События структурированного журнала app о выборе проекта путей и имён папок **не содержат**: `project.drop {outcome, reason?, count}`, `project.picker_failed {error_class}`. Структурированный журнал может пересылаться на dev-сервер (`structured_log_remote_sync`, `technology-stack.md` §17.2), поэтому в нём — минимально достаточные поля (§43).
* Строка, брошенная в окно и не прошедшая проверку «абсолютный локальный путь» (URI со схемой, относительный путь), **не пишется никуда** — ни в диагностику, ни в журнал, ни в состояние. В такой строке бывают userinfo и токены (`https://user:token@…`). Диагностика отказа в этом случае — `Dropped item rejected (unsupported).` без пути.
* Текст исключений порта выбора папки не пишется: в нём может быть путь или ответ платформы. Пишется только класс ошибки.

---

## 44. Команды

Запись команд оболочки может раскрыть чувствительные данные.

В рабочей сборке лучше журналировать:

```text
executable=git
operation=process_run
```

чем полную командную строку, если аргументы могут содержать секреты.

---

## 45. Окружение

Журналировать переменные окружения целиком ЗАПРЕЩЕНО.

---

## 46. Сетевые адреса

Хост и порт обычно МОЖНО журналировать, если они не чувствительны.

Заголовки авторизации, токены и секреты в строке запроса журналировать ЗАПРЕЩЕНО.

---

## 47. Методы ACP

Метод или тип сообщения ACP обычно полезно журналировать.

Например:

```text
direction=inbound
method=session/update
request_id=r-42
```

при условии, что имя метода само по себе не чувствительно.

---

## 48. Debug и release

СЛЕДУЕТ иметь явную разницу.

### Debug

* более подробные журналы;
* трасса протокола;
* панель диагностики;
* переходы состояния.

### Release

* ограниченные структурные журналы;
* замаскированный payload;
* без полной выгрузки протокола;
* без диагностики только для разработчиков.

В коде desktop в debug пишет записи `application` в консоль, в release — в `application.log` (JSON Lines); файл трассы `protocol.log` выключен по умолчанию в обоих режимах; пересылка на dev-сервер создаётся, только если при сборке заданы `CODELAB_LOG_SERVER_URL` и `CODELAB_LOG_SERVER_KEY` (`CodeLabLoggingModule`, `technology-stack.md` §17.2). CLI без `--verbose` молчит, кроме `secrets.lookup` встроенного агента при `--debug-secrets` (§13).

### 48а. Политика payload протокола у хоста клиента

Источник — change [`redesign-protocol-pane`](../../openspec/changes/redesign-protocol-pane/design.md), D3.

* Разницу debug и release для протокола задаёт **базовая политика payload** `ProtocolPayloadPolicy` (`full` или `metadataOnly`) — параметр конструктора `AcpClientApplication(protocolPayloads: …)`. Значение по умолчанию — `metadataOnly`: хост, забывший параметр, не открывает полный payload в release.
* Пакет — чистый Dart и не знает режима сборки, поэтому политику выбирает composition root, как и выходы `configureCodeLabLogging`:
  * desktop — `full` только при `kDebugMode`, иначе `metadataOnly` (`apps/codelab_desktop/lib/app/app_scope.dart`);
  * CLI — `full` только с `--verbose`, иначе `metadataOnly` (`apps/codelab_cli/lib/src/composition_root.dart`); без `--verbose` логгер CLI и так молчит.
* Одна базовая политика на процесс задаёт **и кадры, и запись журнала `protocol_message`** — во всех sinks категории `protocol`: во встроенном журнале app (`debug-panel`) и в файле `protocol.log` (пересылка на dev-сервер категорию `protocol` не получает). При `metadataOnly` запись несёт `direction`, `kind`, `method`, `request_id`, `size` и корреляцию `session_id`, `connection_generation`, но не `payload`. Sink встроенного журнала по-прежнему принимает категорию `protocol`: видимость — фильтр категории, содержимое — политика.
* То же правило действует на диагностику ядра в ветках ошибок (сбой декодирования или обработки ответа и запроса, пропуск неподдерживаемого `sessionUpdate`): при `metadataOnly` в контексте только метаданные — метод, id, сессия, размер, класс ошибки, — без сырых `params`, `result` и `payload` (решение пользователя 2026-11-23). Текст причины сбоя (`cause`) при `metadataOnly` пишется только классом ошибки в любой записи диагностики ядра, включая вложенную причину сбоя транспорта в `context['inner_cause']` (`_causeDetail`; D3). Обычная запись журнала `attempt_superseded` (debug, `_requireCurrentAttempt`) при `metadataOnly` тоже несёт только `error_class` и `error_code`, без текста ошибки вытесненной попытки.
* **Текст ответа-ошибки агента** (`error.message`, `error.data`) — тоже payload, и не только для кадров (§27а), но и для диагностики и журнала (D3, «Текст ошибки агента»). При `metadataOnly` `DiagnosticEntry` ядра, `WorkspaceDiagnostic` kit и записи `ShellDiagnostics` app о сбое несут метод, id, сессию, код ошибки (`error_code`), стандартное имя кода, класс ошибки (`error_class`) и постоянный текст CodeLab — по единому правилу `describeFailureMetadata` (`codelab_client_acp`); без `error.message`, `error.data` и текста исключения, в которое они вложены. При `full` — замаскированный текст, как прежде.
* Текст для пользователя отделён от текста журнала: сообщение хода в транскрипте (`PromptTurn.failureMessage`), баннер соединения и вывод CLI (`describeFailure`) несут текст агента при любой политике, после `SecretRedactor`, — пользователь видит причину отказа. Это состояние, а не запись журнала.
* Политику kit и app читают у ядра (`AcpClientApplication.protocolPayloads`, порт `AgentBackend.protocolPayloads`), а не получают вторым параметром: источник один.
* В записи журнала диагностики ключ `cause` — только причина самой диагностики (`DiagnosticEntry.cause`), вложенная причина сбоя транспорта — ключ `inner_cause`; значения не перекрывают друг друга.
* Поверх базовой политики для **кадров** действует runtime-режим Trace (§49а): действующая политика кадров — `full`, если базовая `full` или Trace включён. Запись `protocol_message` Trace не меняет: `LogBuffer` не умеет снять поле с уже записанных записей, и payload пережил бы выключение Trace.

---

## 49. Включение диагностики во время работы

Если полную диагностику можно включить во время работы, это ДОЛЖНО быть явным действием пользователя или разработчика.

ЗАПРЕЩЕНО автоматически включать трассировку чувствительных данных после любой ошибки.

### 49а. Режим Trace панели Protocol

Источник — change [`redesign-protocol-pane`](../../openspec/changes/redesign-protocol-pane/design.md), D17; решение пользователя 2026-11-22 (Q7, Q8).

Trace — единственный способ включить полные payload кадров в release-сборке desktop. Он удовлетворяет требованиям этого раздела так:

* **Явное действие пользователя.** Переключатель `Trace` в шапке панели Protocol; есть только в release-сборке (в debug payload и так полные). Сочетания клавиш и пункта палитры нет: включение — осознанное действие в самой панели.
* **Никогда автоматически.** Ни ошибка, ни переподключение, ни сохранённые настройки Trace не включают.
* **Не сохраняется между запусками.** При каждом старте Trace выключен: согласие хранить промпты и содержимое файлов даётся в том запуске, где данные собираются. Переподключение и смена профиля в том же процессе Trace не выключают.
* **Только память.** Trace меняет политику кадров в ядре клиента (`AcpClientApplication.setFrameTrace`, через `AgentBackend` и `ProtocolFrameLog.setTrace`). Файл `protocol.log`, его выключенность по умолчанию и запись `protocol_message` в журнале он **не трогает** (§48а). Поэтому для этой цели не годится существующий `setProtocolTracingEnabled`: он включает файл, и данные пережили бы процесс. Не годится и минимальный уровень журнала `trace`: это фильтр показа, а не согласие на сбор.
* **Выключение снимает payload.** Ядро сразу возвращается к `metadataOnly`, буфер снимает payload со всех кадров, app — с выбранного кадра и снимка паузы. Кадр, построенный до выключения, но доставленный после, payload не приносит.
* **Видимая индикация**: нажатый переключатель и предупреждение `Trace on: full payloads.` в панели выбранного кадра.
* **Маскирование секретов действует всегда** (§14а). Экспорт набора с payload требует подтверждения (§50).
* Наблюдаемость самого режима: info `protocol_pane.trace {enabled}` в app, info `protocol_frames.policy {policy, reason}` в ядре клиента, debug `protocol_frames.payloads_dropped {count}` в kit при выключении.

---

## 50. Экспорт диагностики

Если приложение позволяет экспортировать набор диагностики, оно ДОЛЖНО:

* маскировать секреты;
* предупреждать о возможных чувствительных данных;
* ограничивать объём;
* включать версию приложения и платформы;
* включать корреляционные данные.

В коде экспорт есть только у панели Protocol: файл JSON Lines с видимыми кадрами или записями журнала (`protocol_export.dart`, D10 change `redesign-protocol-pane`). Заголовок файла несёт `build`, `app_version`, `platform`, `session_id`; данные берутся из буферов уже замаскированными; объём ограничен буферами (§28); если среди кадров есть payload, экспорт сначала спрашивает подтверждение (`exportHasPayload`, `ProtocolPaneCubit.exportActive`).

---

## 51. Набор диагностики

Возможное содержимое:

```text
версия приложения
платформа
недавние события жизненного цикла
недавние метаданные протокола
сводки ошибок
сводка конфигурации
```

не обязательно:

```text
все промпты
содержимое всех файлов
все переменные окружения
```

---

## 52. Тестирование наблюдаемости

СЛЕДУЕТ проверять тестами как минимум:

* секреты замаскированы;
* устаревшее событие несёт корреляцию;
* переход жизненного цикла даёт ожидаемое структурное событие;
* запись отладочного payload выключена в конфигурации release;
* решение о разрешении журналируется без секретного payload.

В коде такие проверки, например, в `secret_redaction_test.dart`, `structured_logging_test.dart` и `payload_policy_diagnostics_test.dart` (`codelab_client_acp`).

---

## 53. Тесты логгера

Проверять каждое сообщение журнала дословно не нужно.

Тестировать СЛЕДУЕТ смысловые поля, если они — важный контракт диагностики.

---

## 54. Тесты отчётов об ошибках

Неожиданное исключение ДОЛЖНО сохранять:

* тип;
* стек;
* корреляционный контекст.

Ожидаемый отказ НЕ ДОЛЖЕН ошибочно считаться аварийным сбоем.

---

## 55. Не журналировать дважды

Если нижний слой уже записал ошибку транспорта с полным техническим контекстом, верхний слой МОЖЕТ записать переход состояния приложения, но повторять тот же стек не обязательно.

Например:

```text
транспорт:
ProcessExited(exitCode=1)

приложение:
SessionState → reconnecting
```

Это полезнее двух одинаковых записей об ошибке.

---

## 56. Пример владения журналом

Хороший поток:

```text
codelab_acp_transports
    → транспорт закрыт

codelab_client_acp
    → состояние соединения: connected → reconnecting

presentation
    → показан баннер переподключения
```

Не нужно, чтобы каждый слой писал:

```text
ERROR: CONNECTION LOST!!!
```

---

## 57. Журнал аудита

Если продукту понадобится журнал аудита безопасности, для него ДОЛЖНЫ быть созданы отдельный документ и модель (или модель в документе).

Журнал аудита ДОЛЖЕН определять:

* какие действия фиксируются;
* неизменяемы ли записи;
* срок хранения;
* экспорт;
* приватность;
* целостность.

Обычный журнал приложения этого не гарантирует.

---

## 58. Персональные и пользовательские данные

Содержимое, созданное пользователем, СЛЕДУЕТ считать потенциально чувствительным.

НЕ СЛЕДУЕТ журналировать:

* промпты;
* ответы;
* имена файлов;
* вывод инструментов;

целиком без явной диагностической необходимости.

---

## 59. Выборка

Выборку (sampling) МОЖНО применять к высокочастотным информационным событиям.

НЕ СЛЕДУЕТ применять выборку к критическим ошибкам и решениям безопасности.

---

## 60. Согласованность корреляции

Один идентификатор ДОЛЖЕН называться одинаково во всех слоях.

Например, НЕ СЛЕДУЕТ использовать одновременно:

```text
req
request
requestId
request_id
```

в структурных журналах.

Логгер проекта ДОЛЖЕН иметь согласованное соглашение об именах.

В коде ключи `withCorrelation` согласованы (snake_case, §61), но контекст части записей диагностики `AcpClientApplication` использует camelCase рядом с ними: `sessionId`, `approvalId`, `toolCallId` (снятие одобрения), `sessionUpdate`, `toolKind` (незнакомый вид инструмента).

---

## 61. Рекомендуемые имена полей

СЛЕДУЕТ использовать snake_case:

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

## 62. Основные инварианты

### OBS-001 — Значимый жизненный цикл диагностируем

Переходы соединения, сессии и запроса имеют структурный контекст.

### OBS-002 — Секреты замаскированы

Чувствительные значения не попадают в журнал в открытом виде.

### OBS-003 — Корреляция явная

События можно связать через стабильные идентификаторы и поколение соединения.

### OBS-004 — Отладочная трасса ограничена

Подробная трассировка не приводит к неограниченному росту памяти или журнала.

### OBS-005 — Release не содержит полной выгрузки протокола по умолчанию

Трассировка сырого payload — только для разработчика.

### OBS-006 — Слои журналируют свою семантику

Транспорт не журналирует UX, UI не дублирует внутренности протокола.

---

## 63. Чек-лист перед добавлением записи в журнал

Перед новым событием журнала определить:

1. Зачем оно нужно?
2. Какой слой владеет событием?
3. Какой уровень правильный?
4. Какие корреляционные поля нужны?
5. Есть ли чувствительные данные?
6. Нужен ли стек?
7. Может ли событие происходить часто?
8. Нужны ли выборка или ограничение частоты?
9. Дублирует ли оно запись нижнего уровня?
10. Полезно ли оно для реальной диагностики?

---

## 64. Основная модель

Хорошая наблюдаемость позволяет восстановить поток:

```text
подключение
  ↓
сессия создана
  ↓
запрос начат
  ↓
поток обновлений
  ↓
вызов инструмента
  ↓
разрешение получено
  ↓
завершение
```

через структурные события и корреляционные идентификаторы, без хранения полного чувствительного payload.

Если для расследования любой ошибки приходится добавлять `print()` в десяток мест, архитектура наблюдаемости недостаточна.
