## Why

ACP определяет семейство `terminal/*` (`create`, `output`, `wait_for_exit`, `kill`, `release`) как методы, которыми **агент** может попросить клиента выполнить non-interactive команду от имени активной сессии и получить её вывод/статус завершения. CodeLab уже моделирует `ClientCapabilities.terminal` в протокольном слое ([initialize.dart](../../../packages/dart/acp_protocol/lib/src/acp/initialize.dart)), но `InitializeRequest` сегодня отправляется вовсе без `clientCapabilities` ([acp_client_application.dart:344-351](../../../packages/dart/acp_client_core/lib/src/application/acp_client_application.dart#L344)), а `acpMethodRegistry` не содержит ни одного из этих методов ([acp_method_codec.dart:188-198](../../../packages/dart/acp_protocol/lib/src/acp/acp_method_codec.dart#L188)) — если бы агент их вызвал, клиент ответил бы `unknownMethod`. CodeLab заявляет протокол, которого фактически нет.

Это отдельная capability от уже существующего `add-integrated-terminal`: тот change добавляет **локальную** интерактивную PTY-панель для человека-пользователя, сознательно вне ACP ([add-integrated-terminal/proposal.md](../add-integrated-terminal/proposal.md)). Этот change — про то, что **агент** может запросить выполнение команды у клиента через ACP; это non-interactive process execution (без PTY, без stdin после `create`).

## What Changes

- Добавляются client-side ACP методы `terminal/create`, `terminal/output`, `terminal/wait_for_exit`, `terminal/kill`, `terminal/release` в `acp_protocol`/`acp_client_core`: типизированные request/response модели, регистрация в `acpMethodRegistry`, обработчик входящих запросов агента.
- `AcpClientApplication` при `initialize` отправляет `clientCapabilities.terminal = true` только когда все пять методов реализованы, вместо неявного `false` по умолчанию.
- `terminal/create` запускает процесс сразу после проверки working directory, **без собственного approval-запроса**. По протоколу ACP `session/request_permission` — это `MAY` для агента, а не `MUST` (`docs/acp/protocol/08-Tool Calls.md#requesting-permission`), и `10-Terminal.md` не связывает `terminal/*` с permission вообще. CodeLab не дублирует эту проверку собственной политикой и доверяет решению агента о необходимости permission — та же позиция, что принята в `add-acp-fs-client-support` для `fs/write_text_file`.
- Это — явное, документированное отступление от `docs/architecture/permissions.md §10` ("deny-by-default для permission-sensitive operations", где shell/process execution числится в списке) и от буквы `AGENTS.md §10`. Отступление фиксируется здесь и требует правки этих документов (уже запланированной в `add-acp-fs-client-support/tasks.md`; этот change ссылается на ту же правку, не дублируя её).
- Процесс, запущенный через `terminal/create`, ДОЛЖЕН иметь явный lifecycle: буферизация вывода до `terminal/output`, завершение через `wait_for_exit`, принудительное завершение через `kill`, освобождение ресурсов через `release`; висящие процессы ДОЛЖНЫ завершаться при disconnect/dispose сессии. Это отдельный, не связанный с approval контроль.
- Working directory запускаемого процесса ограничивается рабочей директорией активной сессии (`stdioCwd`/session `cwd`) — попытка выполнить команду вне неё отклоняется как protocol/security error. Тоже не связано с approval.
- Новая infrastructure-реализация (`dart:io` Process) размещается за platform-boundary согласно `AGENTS.md §11`, а не в `acp_protocol` (pure Dart, wire-protocol only) и не в presentation; переиспользует существующий паттерн процесса из `packages/dart/acp_transports/lib/src/stdio_acp_transport.dart`, не смешиваясь с transport-слоем.
- **BREAKING**: нет — добавление ранее не поддерживаемых методов и capabilities; агенты, не использующие `terminal/*`, не затронуты.

## Capabilities

### New Capabilities
- `acp-terminal-client`: client-side реализация ACP `terminal/create`, `terminal/output`, `terminal/wait_for_exit`, `terminal/kill`, `terminal/release` — non-interactive выполнение команд по запросу агента в рамках активной сессии, включая lifecycle и security-ограничения по working directory. Без собственного client-side approval — см. Why.

### Modified Capabilities
- `acp-protocol-client`: `initialize` начинает отправлять реальный `ClientCapabilities.terminal`, отражающий фактическую поддержку `terminal/*`, вместо неявного `false` по умолчанию.

## Impact

- `packages/dart/acp_protocol/lib/src/acp/` — новый файл моделей (`terminal.dart`, по аналогии с существующими `permission.dart`/`session.dart`) + регистрация методов в `acp_method_codec.dart`.
- `packages/dart/acp_client_core/lib/src/application/acp_client_application.dart` — обработка входящих server→client запросов `terminal/*`, отправка `clientCapabilities.terminal` при `initialize`.
- `packages/dart/acp_client_core/lib/src/domain/` — типизированные ошибки/результаты и state machine для terminal-процессов (running, exited, killed, released).
- `apps/codelab_app/lib/core/platform/` — новый infrastructure-адаптер для process execution, независимый от `TerminalProcessFactory` из `add-integrated-terminal`.
- `docs/architecture/concurrency.md` — вероятно требует уточнения про lifecycle terminal-процессов.
- `docs/architecture/permissions.md`/`AGENTS.md §10` — правка про исключение `fs/*`/`terminal/*` из client-side approval уже запланирована в `add-acp-fs-client-support/tasks.md`; если тот change реализуется раньше, здесь достаточно проверить, что формулировка покрывает и `terminal/*`, а не дублировать правку.
- Тесты: `acp_testing` fake agent/transport должны получить возможность симулировать `terminal/*` запросы для integration-тестов.
