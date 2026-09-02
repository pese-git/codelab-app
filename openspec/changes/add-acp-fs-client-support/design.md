## Context

ACP определяет `fs/read_text_file` и `fs/write_text_file` как запросы **agent → client** (см. `docs/acp/protocol/09-File System.md`, `docs/acp/protocol/17-Schema.md#fs-read_text_file`). Оба метода принимают только `sessionId`, `path` (+ `line`/`limit` для read, `content` для write) — протокол не определяет никакого permission-handshake вокруг них. Единственный permission-механизм ACP — `session/request_permission` (`docs/acp/protocol/08-Tool Calls.md#requesting-permission`), и он явно `MAY` для агента ("The Agent **MAY** request permission... before executing a tool call"), привязан к `ToolCallUpdate`, и ни разу не упомянут в разделах про `fs/*`/`terminal/*`.

Проектная модель permission в `docs/architecture/permissions.md` относит "filesystem write/delete" к permission-sensitive operations с deny-by-default для неизвестных опасных capability, а `AGENTS.md §10` формулирует это как ОБЯЗАН. Это создаёт прямое противоречие с буквой ACP-протокола: если следовать протоколу строго (permission — дело агента, не клиента), CodeLab не должен вводить собственный approval-гейт для `fs/write_text_file`; если следовать `permissions.md` буквально, обязан.

**Явное решение по этому change (принято владельцем продукта после разбора конфликта, см. обсуждение в openspec-истории)**: приоритет отдаётся протокольной точности — CodeLab НЕ вводит собственный approval-гейт для `fs/write_text_file`/`fs/read_text_file`, доверяя решению агента о необходимости permission через его собственный (опциональный) вызов `session/request_permission`. Это сознательное, документированное отступление от `docs/architecture/permissions.md §10`, а не молчаливое упрощение реализации — соответствующая правка `permissions.md`/`AGENTS.md §10` включена в tasks.md этого change, чтобы документация и код не разошлись незаметно (`AGENTS.md §17`).

Компенсирующий контроль, который остаётся в силе независимо от решения по approval — working-directory containment: агент не может прочитать/записать файл за пределами рабочей директории сессии, даже без approval.

## Goals / Non-Goals

**Goals:**
- Client-side реализация `fs/read_text_file` и `fs/write_text_file`, зарегистрированная в `acpMethodRegistry`.
- Честная отправка `ClientCapabilities.fs` в `initialize`, отражающая то, что реально реализовано.
- `fs/read_text_file`/`fs/write_text_file` выполняются напрямую после проверки working directory, без собственного client-side approval — соответствие протокольной модели, где permission — ответственность агента.
- Path traversal/escape за пределы working directory сессии блокируется на уровне application, до похода в infrastructure — эта проверка не является approval и не заменяется/не отменяется решением не требовать permission.
- Изоляция `dart:io` за platform-boundary (`AGENTS.md §11`), без утечки в `acp_protocol`/`domain`.

**Non-Goals:**
- Не проектируется UI file preview/tree для человека — это отдельный change `add-file-preview-and-tree`.
- Не решается вопрос доступа к бинарным файлам — `fs/read_text_file`/`fs/write_text_file` в ACP оперируют только текстом.
- Не вводится client-side approval/permission UI для fs-операций — см. Context; это намеренно исключено этим change.
- Не меняется существующий `session/request_permission`/`ApprovalRequest`/`ApprovalPolicy` — этот change их не касается и не расширяет.

## Decisions

### 1. Никакого client-side approval для fs/read_text_file и fs/write_text_file
CodeLab выполняет оба метода сразу после прохождения security-проверки working directory, не создавая `ApprovalRequest` и не блокируясь на решении пользователя. Решение о необходимости permission остаётся полностью на стороне агента (его собственный, опциональный `session/request_permission` для tool call, если агент сочтёт нужным).
- Альтернатива (отклонена, был исходный design этого change): approval через синтезированный `ToolCallRecord`, переиспользующий existing `ApprovalPolicy`/`ApprovalRequest`. Отклонена по явному решению — протокол не требует approval для fs, и введение собственного гейта создавало бы поведение, которое агенты, рассчитывающие на строгое ACP-соответствие, не ожидают (лишний RPC/UI trip там, где спецификация обещает прямое выполнение).
- Альтернатива (отклонена): approval только если агент сам не запросил `session/request_permission`. Отклонена — протокол не даёт способа надёжно связать конкретный `session/request_permission` (привязанный к `toolCallId`) с последующим `fs/write_text_file` (у которого нет `toolCallId`); эвристическая корреляция добавила бы сложность без протокольной опоры.

### 2. fs-запросы обрабатываются независимо от наличия активного prompt turn
Поскольку approval больше не привязывает операцию к `PromptTurnId` (в `ApprovalRequest` этого требования больше нет — approval не создаётся), `fs/read_text_file`/`fs/write_text_file` обрабатываются при любом состоянии сессии, в котором ACP допускает входящие запросы агента, без искусственного требования "активный turn". Это соответствует протоколу: `ReadTextFileRequest`/`WriteTextFileRequest` скоупятся только `sessionId`, не turn'ом.

### 3. Path resolution и ограничение working directory — в application, не в infrastructure
`path` из `ReadTextFileRequest`/`WriteTextFileRequest` — абсолютный (по ACP-контракту). Перед вызовом infrastructure-адаптера application-слой (`acp_client_core`) резолвит canonical path и проверяет, что он находится внутри `cwd` сессии (сохранённого при `session/new`), отклоняя escape (`..`, symlink за пределы cwd) типизированной ошибкой до похода в файловую систему. Это остаётся в силе независимо от decision №1 — это защита от вырвавшегося за пределы проекта пути, а не permission/approval.
- Альтернатива (отклонена): доверить проверку infrastructure-адаптеру. Отклонена — security policy (что считается допустимым путём) принадлежит application/security boundary (`docs/architecture/permissions.md §3`), а не конкретному adapter'у.

### 4. Infrastructure — новый узкий adapter, без `FooRepository`/`FooManager`
Новый `TextFileReader`/`TextFileWriter`-подобный adapter (точное имя — на усмотрение реализации, следуя `AGENTS.md §13`) в `apps/codelab_app/lib/core/platform/`, инкапсулирующий `dart:io` File — читает/пишет по уже провалидированному abolute path, возвращает типизированный результат (`Either`/явная ошибка `fpdart`) на IO-ошибки (`FileSystemException`).

## Risks / Trade-offs

- [Агент может писать в файлы пользователя (в пределах working directory) без единого запроса подтверждения, если сам не решит спросить permission] → working-directory containment (decision №3) — это единственный компенсирующий контроль; риск принят осознанно как часть решения по протокольной точности, а не проглядели. Рекомендуется логировать каждый `fs/write_text_file` в диагностику (correlation по `session_id`) для post-hoc наблюдаемости, см. `AGENTS.md §16`.
- [Документ `docs/architecture/permissions.md` и `AGENTS.md §10` формально противоречат этой реализации, пока не обновлены] → задача обновления документов включена в tasks.md; до её выполнения change не считается полностью согласованным с проектной документацией — это должно быть сделано в рамках той же реализации, не отложено.
- [Path canonicalization на разных ОС (symlink, case-insensitive FS на macOS/Windows) может дать false positive/negative на escape-проверке] → использовать `Directory`/`File`-канонизацию из `dart:io` (`resolveSymbolicLinksSync`) и покрыть тестами кейсы symlink-escape отдельно на каждой поддерживаемой платформе, где это возможно в CI.
- [Отсутствие approval для fs может быть пересмотрено позже, если реальные агенты окажутся недостаточно ответственными] → архитектурно это изолированное решение (decision №1), пересмотр не потребует переписывать protocol-модели или infrastructure adapter — только вернуть approval-гейт в application-слое.
