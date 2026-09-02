## Why

ACP определяет `fs/read_text_file` и `fs/write_text_file` как методы, которыми **агент** может попросить клиента прочитать/записать файл от имени активной сессии (например, вместо собственного tool call). CodeLab уже моделирует `ClientCapabilities.fs` в протокольном слое ([initialize.dart](../../../packages/dart/acp_protocol/lib/src/acp/initialize.dart)), но `InitializeRequest` сегодня отправляется вовсе без `clientCapabilities` ([acp_client_application.dart:344-351](../../../packages/dart/acp_client_core/lib/src/application/acp_client_application.dart#L344)), а `acpMethodRegistry` не содержит этих методов ([acp_method_codec.dart:188-198](../../../packages/dart/acp_protocol/lib/src/acp/acp_method_codec.dart#L188)) — если бы агент их вызвал, клиент ответил бы `unknownMethod`. CodeLab заявляет протокол, которого фактически нет.

Это отдельная capability от уже существующего `add-file-preview-and-tree`: тот change даёт **человеку** read-only просмотр файлов в UI, сознательно вне ACP. Этот change — про то, что **агент** может запросить у клиента через ACP.

## What Changes

- Добавляются client-side ACP методы `fs/read_text_file` и `fs/write_text_file` в `acp_protocol`/`acp_client_core`: типизированные request/response модели, регистрация в `acpMethodRegistry`, обработчик входящих запросов агента.
- `AcpClientApplication` при `initialize` отправляет `clientCapabilities.fs` с честными значениями (`readTextFile`, `writeTextFile`), соответствующими фактически реализованным обработчикам, вместо неявного `false` по умолчанию.
- `fs/read_text_file` и `fs/write_text_file` выполняются CodeLab сразу после проверки working directory, **без собственного approval-запроса**. По протоколу ACP `session/request_permission` — это `MAY` для агента, а не `MUST` (`docs/acp/protocol/08-Tool Calls.md#requesting-permission`), и ни `09-File System.md`, ни `17-Schema.md` не связывают `fs/*` с permission вообще. CodeLab не дублирует эту проверку собственной политикой и доверяет решению агента о необходимости permission — сознательный приоритет протокольной минимальности для этой конкретной capability.
- Это — явное, документированное отступление от `docs/architecture/permissions.md §10` ("deny-by-default для permission-sensitive operations", где filesystem write числится в списке) и от буквы `AGENTS.md §10` ("Опасные действия agent ДОЛЖНЫ проходить через application-level permission policy"). Отступление зафиксировано здесь и требует правки этих документов (см. Impact), чтобы не создавать молчаливое расхождение между архитектурной документацией и реализацией (`AGENTS.md §17` запрещает менять spec под реализацию неявно).
- Все fs-операции ограничиваются рабочей директорией активной сессии (`stdioCwd`/session `cwd`) — путь, выходящий за её пределы, отклоняется как protocol/security error, а не выполняется молча. Это отдельный, не связанный с approval security-контроль, который остаётся в силе независимо от решения по permission.
- Новая infrastructure-реализация (`dart:io` File) размещается за platform-boundary согласно `AGENTS.md §11`, а не в `acp_protocol` (pure Dart, wire-protocol only) и не в presentation.
- **BREAKING**: нет — добавление ранее не поддерживаемых методов и capabilities; агенты, не использующие `fs/*`, не затронуты.

## Capabilities

### New Capabilities
- `acp-fs-client`: client-side реализация ACP `fs/read_text_file` и `fs/write_text_file` — обработка входящих запросов агента на чтение/запись файлов в рамках активной сессии, включая security-ограничения по working directory. Без собственного client-side approval — см. Why.

### Modified Capabilities
- `acp-protocol-client`: `initialize` начинает отправлять реальный `ClientCapabilities.fs`, отражающий фактически поддерживаемые методы, вместо неявного `false` по умолчанию.

## Impact

- `packages/dart/acp_protocol/lib/src/acp/` — новый файл моделей (`fs.dart`, по аналогии с существующими `permission.dart`/`session.dart`) + регистрация методов в `acp_method_codec.dart`.
- `packages/dart/acp_client_core/lib/src/application/acp_client_application.dart` — обработка входящих server→client запросов `fs/*`, отправка `clientCapabilities.fs` при `initialize`.
- `packages/dart/acp_client_core/lib/src/domain/` — типизированные ошибки/результаты для fs-операций (path escape, IO failure).
- `apps/codelab_app/lib/core/platform/` — новый infrastructure-адаптер для файлового I/O (переиспользование существующего platform-boundary паттерна, см. `docs/architecture/platform-integration.md`).
- `docs/architecture/permissions.md` — требует явного уточнения: `fs/read_text_file`/`fs/write_text_file` (и симметрично `terminal/*` из `add-acp-terminal-client-support`) — исключение из deny-by-default policy, с обоснованием (протокольная минимальность, working-directory containment как компенсирующий контроль). Без этой правки документ и реализация будут противоречить друг другу.
- `AGENTS.md §10` — формулировка "Опасные действия agent ДОЛЖНЫ проходить через application-level permission policy" нуждается в явной сноске/исключении для ACP `fs/*`/`terminal/*` RPC-методов, либо в переформулировке, признающей working-directory containment достаточной policy для этого случая.
- Тесты: `acp_testing` fake agent/transport должны получить возможность симулировать `fs/*` запросы для integration-тестов.
