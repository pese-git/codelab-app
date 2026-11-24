## MODIFIED Requirements

### Requirement: Logger-абстракция вместо print/debugPrint
CodeLab SHALL писать значимые lifecycle- и diagnostic-события production-кода через порт `Logger` клиента (`codelab_client_acp`) или агента (`codelab_agent_core`), а не через `print`. Адаптер клиента на `structured_log` — `StructuredLogLogger`. Запись SHALL быть structured-событием: имя события в поле `event`, компонент-источник в поле `component` (требование «Логирование по слоям согласно ownership»), корреляция (требование «Correlation-идентификаторы на значимых событиях») и поля контекста события. Вызов `print` в коде пакетов и приложений SHALL отклоняться статическим анализом (правило `avoid_print` в `analysis_options.yaml`).

Выбор адаптера и sinks, внедрение логгера и имена полей — `docs/architecture/observability.md` §7, §33, §34, §61.

#### Scenario: Смена состояния соединения — structured-запись
- **WHEN** `AcpClientApplication` переходит в состояние готовности после переподключения
- **THEN** журнал получает запись с `event` `connection_state_changed`, полями `from` и `to` (имена состояний), `component` `client` и `connection_generation` (`structured_logging_test.dart`, «reconnect logs the current connection_generation»)

#### Scenario: print в рабочем коде
- **WHEN** файл `lib/` пакета или приложения вызывает `print`
- **THEN** `fvm dart analyze` сообщает `avoid_print`

### Requirement: Маскирование секретов в structured-выводе
CodeLab SHALL маскировать секреты в каждом structured-событии клиента до того, как оно попадёт в любой sink: процессор `secretRedactionProcessor` в настройке `configureCodeLabLogging` применяет `SecretRedactor` к тексту события и полям контекста. Правила распознавания секретов задаёт одно требование — approval-safety «Редактирование секретов»; отдельного набора правил для журнала SHALL NOT быть.

#### Scenario: Секрет в context-поле маскируется
- **WHEN** структурное событие содержит в context-поле значение с ключом, распознаваемым как секрет (например, `token`, `password`, `api_key`)
- **THEN** значение этого поля в итоговом structured-выводе заменено на `<redacted>`

#### Scenario: Секрет внутри свободного текста сообщения маскируется
- **WHEN** транспорт сообщает диагностику с текстом `Authorization: Bearer transport-token`
- **THEN** поле `event` записи журнала — `Authorization: Bearer <redacted>`, как и текст `DiagnosticEntry` этого события (`structured_logging_test.dart`, «masks secrets in structured log output»)

### Requirement: Логирование по слоям согласно ownership
CodeLab SHALL помечать structured-события клиента компонентом-источником в поле `component`. `codelab_acp_protocol` и `codelab_acp_transports` сами не журналируют: протокол сообщает об ошибках исключениями, транспорт — событиями `AcpTransportEvent`. Запись о них SHALL писать `AcpClientApplication` с `component` `protocol` (ошибки разбора и отправки сообщений) или `transport` (диагностика и сбои транспорта, устаревшие события старого поколения); собственные события протокольного клиента — с `component` `client`. Логгеры app получают `component` в composition root (`observability.md` §3).

#### Scenario: Transport diagnostic-событие помечено своим компонентом
- **WHEN** транспорт эмитит `AcpTransportEvent.diagnostic` из stderr агента
- **THEN** запись журнала несёт `component` `transport` и `category` `application` (`structured_logging_test.dart`, «tags transport diagnostics with component=transport»)

#### Scenario: Сбой отправки запроса помечен компонентом protocol
- **WHEN** отправка `session/new` падает с `AcpTransportException`
- **THEN** запись журнала уровня `error` с `event` `Failed to send ACP request session/new.` несёт `component` `protocol` (`structured_logging_test.dart`, «tags protocol send failures with component=protocol»)

### Requirement: Ограниченная (bounded) история diagnostic-событий
CodeLab SHALL хранить in-memory историю diagnostic-событий протокольного клиента только в одном ограниченном буфере — `AcpClientApplication.diagnostics` на 500 записей `DiagnosticEntry`; при превышении вытесняются самые старые записи. Снимок сессии `AcpSession` диагностику SHALL NOT нести: запись диагностики SHALL NOT менять снимки сессий и SHALL NOT публиковать `sessionChanges`. Поток `AcpClientApplication.diagnosticChanges` публикует каждую запись для хостов, но в app и CLI подписчиков у него нет: до пользователя диагностика протокольного клиента доходит через журнал (окно журнала desktop, `--verbose` CLI). `ClientWorkspace.diagnostics` — отдельный поток `WorkspaceDiagnostic` ядра клиента, записи `DiagnosticEntry` он не пересылает. Structured-вывод в журнал от предела SHALL NOT зависеть: каждое событие пишется в журнал.

#### Scenario: Превышение лимита вытесняет старые записи
- **WHEN** транспорт эмитит 520 диагностик подряд
- **THEN** `AcpClientApplication.diagnostics` содержит 500 записей от `diag-20` до `diag-519`, а журнал получил все 520 событий (`structured_logging_test.dart`, «bounds in-memory diagnostics while structured output stays complete»)

#### Scenario: Диагностика не меняет снимок сессии
- **WHEN** при открытой сессии транспорт эмитит диагностику
- **THEN** запись есть в `AcpClientApplication.diagnostics`, снимок `AcpSession` этой сессии не меняется, а `sessionChanges` не публикует ни одного события (`structured_logging_test.dart`, «diagnostics do not change the session snapshot»)

## ADDED Requirements

### Requirement: Маршрутизация категорий журнала по sink
Запись журнала клиента SHALL нести поле `category`: `application` — обычные события, `protocol` — трасса протокола. Настройка `configureCodeLabLogging` SHALL направлять категории по sink так:
- sink приложения (консоль, `application.log`) SHALL получать только `application`;
- sink встроенного журнала app (`inAppViewerOutput`) SHALL получать `application` и `protocol` всегда, без отдельного переключателя: видимость — фильтр категории в окне журнала, полноту payload задаёт политика payload (требование «Protocol tracing выключен по умолчанию в release»);
- файловый sink трассы (`protocol.log`) SHALL получать только `protocol` и SHALL быть выключен, пока его явно не включит `setProtocolTracingEnabled(true)`.

#### Scenario: Файл трассы выключен по умолчанию
- **WHEN** клиент без явного включения трассы создаёт сессию
- **THEN** ни один sink приложения и трассы не получает записей `category` `protocol` (`structured_logging_test.dart`, «protocol tracing sink is off by default»)

#### Scenario: Встроенный журнал получает обе категории
- **WHEN** настроен `inAppViewerOutput`, файл трассы выключен, транспорт эмитит диагностику и клиент создаёт сессию
- **THEN** встроенный журнал получил записи `application` и `protocol`, а sink приложения записей `protocol` не получил (`structured_logging_test.dart`, «in-app viewer sink always captures both application and protocol-trace events…»)

### Requirement: Причина сбоя в диагностике по политике payload
Текст причины сбоя SHALL следовать базовой политике payload ядра клиента (требование «Protocol tracing выключен по умолчанию в release»). Правило SHALL действовать для поля `DiagnosticEntry.cause` и для вложенной причины в `context['cause']`, например внутренней причины `AcpTransportException`:
- при `metadataOnly` — только имя класса ошибки, без её `toString()`;
- при `full` — текст `toString()` после маскирования секретов.

Запись журнала берёт причину из той же записи диагностики и второго варианта текста не строит.

#### Scenario: Причина сбоя транспорта при metadataOnly
- **WHEN** при политике `metadataOnly` транспорт падает с `AcpTransportException(code: protocolViolation)`, внутренняя причина которой — исключение с данными агента в тексте
- **THEN** `context['code']` диагностики — `protocolViolation`, `context['cause']` — имя класса внутренней причины, а ни диагностика, ни журнал не содержат её текста (`payload_policy_diagnostics_test.dart`, «внутренняя причина сбоя транспорта», «metadataOnly: code и класс причины, без её текста»)

#### Scenario: Причина сбоя при full
- **WHEN** тот же сбой происходит при политике `full`
- **THEN** `context['cause']` содержит замаскированный текст внутренней причины (`payload_policy_diagnostics_test.dart`, «full: замаскированный текст причины, как прежде»)

#### Scenario: Причина сбоя адаптера при metadataOnly
- **WHEN** при политике `metadataOnly` адаптер чтения файла бросает при обработке `fs/read_text_file` исключение, текст которого содержит данные
- **THEN** `DiagnosticEntry.cause` содержит имя класса исключения, но не его текст, и журнал этого текста тоже не содержит (`payload_policy_diagnostics_test.dart`, «metadataOnly: только класс ошибки, без cause.toString()»)
