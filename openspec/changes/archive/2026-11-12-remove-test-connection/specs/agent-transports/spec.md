## MODIFIED Requirements

### Requirement: Ошибка запуска stdio transport без аргументов
Если дочерний процесс не запускается, `StdioAcpTransport.start()` SHALL отдавать наружу — и брошенным исключением, и полем `cause` ошибки `AcpTransportException(startFailed)` в событии `AcpTransportFailure` — `ProcessException` без аргументов команды: `executable`, `message` и `errorCode` исходной ошибки сохраняются, `arguments` пусты (design.md change `redact-cli-stdio-profile-args`, D8). Аргументы могут нести секрет, а `ProcessException.toString()` печатает их строкой `Command: <executable> <arguments>`, и этот текст попадает в журналы и вывод клиентов. Тип ошибки и `errorCode` SHALL оставаться прежними: по ним клиенты могут классифицировать сбой без разбора текста (design.md change `remove-test-connection`, D2). Ошибки запуска другого типа SHALL передаваться без изменений.

#### Scenario: Аргументы не попадают в ошибку запуска
- **WHEN** `StdioAcpTransport` с командой `/nonexistent/agent` и аргументами `--api-key`, `sk-test-leak-0123456789`, `sk-test-leak-0123456789` вызывает `start()`
- **THEN** `start()` бросает `ProcessException` с `executable` `/nonexistent/agent`, пустыми `arguments`, тем же `errorCode` и `message`, что у ошибки ОС; событие `AcpTransportFailure` несёт `AcpTransportException` с кодом `startFailed` и той же ошибкой в `cause`; `toString()` обеих не содержит `sk-test-leak-0123456789` и `--api-key`
