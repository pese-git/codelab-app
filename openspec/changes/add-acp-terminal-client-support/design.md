## Context

ACP определяет `terminal/create`, `terminal/output`, `terminal/wait_for_exit`, `terminal/kill`, `terminal/release` как запросы **agent → client** (см. `docs/acp/protocol/10-Terminal.md`, `docs/acp/protocol/17-Schema.md#terminal-create`). Протокол задаёт explicit lifecycle (create → output/wait_for_exit* → kill? → release), но не определяет никакого permission-handshake вокруг `terminal/create` — единственный permission-механизм ACP, `session/request_permission`, явно `MAY` для агента и не упомянут ни разу в `10-Terminal.md`.

Как и в `add-acp-fs-client-support` (которому этот change симметричен по позиции относительно approval), здесь есть прямое противоречие между буквой ACP (permission — опционально, дело агента) и `docs/architecture/permissions.md §10`/`AGENTS.md §10` (shell/process execution — permission-sensitive, deny-by-default). **Решение по этому change (та же позиция, что и для fs, принятая владельцем продукта после разбора конфликта)**: приоритет — протокольная точность; CodeLab НЕ вводит собственный approval-гейт для `terminal/create`. Правка `docs/architecture/permissions.md`/`AGENTS.md §10` уже запланирована в `add-acp-fs-client-support/tasks.md` и покрывает оба change одной формулировкой (`fs/*` и `terminal/*` вместе) — здесь она не дублируется отдельной задачей, только упоминается в Impact.

Ключевое архитектурное отличие terminal от fs — **stateful процесс с явным жизненным циклом**, а не одноразовая операция: `terminal/create` возвращает `TerminalId` немедленно, не дожидаясь завершения команды; последующие вызовы адресуются к этому `TerminalId`. Это требует session-scoped registry процессов и explicit disposal — decisions ниже посвящены в основном этому, а не approval (approval-вопрос закрыт symmetric-но с fs).

`apps/codelab_app/lib/core/platform/` уже не будет первым местом, работающим с `Process` в проекте — `packages/dart/acp_transports/lib/src/stdio_acp_transport.dart` запускает `Process.start` для самого agent-процесса (относится к ACP-транспорту, не к terminal use case). `add-integrated-terminal` вводит свой `TerminalProcessFactory` для **интерактивной PTY-панели человека**, независимый от того, что реализуется здесь.

## Goals / Non-Goals

**Goals:**
- Client-side реализация `terminal/create`, `terminal/output`, `terminal/wait_for_exit`, `terminal/kill`, `terminal/release`, зарегистрированная в `acpMethodRegistry`.
- Честная отправка `ClientCapabilities.terminal = true` в `initialize`, отражающая то, что реально реализовано.
- `terminal/create` запускает процесс сразу после проверки working directory, без собственного client-side approval — та же позиция, что в `add-acp-fs-client-support`.
- Явный process lifecycle: session-scoped registry `TerminalId → process state`, корректная семантика `kill` (не убивает registry entry) vs `release` (убивает и освобождает), buffered output с `outputByteLimit`/truncation-семантикой из спеки.
- Working directory запускаемой команды ограничен рабочей директорией сессии — как и для fs, это остаётся в силе независимо от решения по approval.
- Все активные terminal-процессы этой capability завершаются при disconnect/dispose сессии или приложения (`AGENTS.md §9`, §12).

**Non-Goals:**
- Не реализуется интерактивный PTY/stdin после `create` — остаётся зоной `add-integrated-terminal`.
- Не переиспользуется `TerminalProcessFactory` из `add-integrated-terminal` "как есть" — назначения разные.
- Не проектируется embedding terminal в `ToolCallContent::Terminal` для live-отображения в транскрипте — за пределами MVP.
- Не вводится client-side approval/permission UI для terminal-операций — см. Context.
- Не вводится timeout/watchdog на стороне клиента для зависших процессов — таймаут остаётся зоной ответственности агента (`terminal/kill` + таймер, см. `10-Terminal.md`).

## Decisions

### 1. Никакого client-side approval для terminal/create
CodeLab запускает процесс сразу после прохождения security-проверки working directory, не создавая `ApprovalRequest` и не блокируясь на решении пользователя — симметрично decision №1 из `add-acp-fs-client-support/design.md`, той же мотивацией (протокол не требует approval, введение собственного гейта противоречило бы протокольным ожиданиям строго ACP-совместимых агентов).
- Альтернатива (отклонена, был исходный design этого change): approval через синтезированный `ToolCallRecord` (`kind: execute`). Отклонена по явному решению, синхронизированному с fs-change.
- Альтернатива (отклонена): approval только на `terminal/create`, но не на `kill`/`release` (частичный approval). Отклонена вместе с полным approval-гейтом — раз create не требует approval, промежуточные методы тем более не требуют.

### 2. terminal/create обрабатывается независимо от наличия активного prompt turn
Симметрично decision №2 из `add-acp-fs-client-support`: без approval нет причины привязывать операцию к `PromptTurnId`. `terminal/create` обрабатывается при любом состоянии сессии, в котором ACP допускает входящие запросы агента.

### 3. Session-scoped `TerminalId` registry — новая domain-модель
Вводится новая domain-модель `TerminalSession`/`TerminalProcessState` (имя — на усмотрение реализации) со state machine `running → exited`, отдельно от `killed`/`released` как флагов, а не булевых полей (`AGENTS.md §8`: запрет на независимые boolean flags, допускающие невозможные состояния). `TerminalId` живёт в скоупе `SessionId`; обращение к неизвестному или уже `released` `TerminalId` возвращает типизированную ACP-ошибку, а не падение.

### 4. Буферизация output и `outputByteLimit` — в infrastructure adapter, ограничение по границе символа
`CreateTerminalRequest.outputByteLimit` (если задан) применяется adapter'ом при накоплении stdout+stderr: при превышении лимита буфер обрезается **с начала**, граница обрезки — по границе допустимого UTF-8 символа (протокольное требование, `17-Schema.md#terminal-create`). `terminal/output` возвращает `truncated: bool`, отражающий, применялась ли обрезка.

### 5. Working directory и security — переиспользование решения из `add-acp-fs-client-support`
`cwd` из `CreateTerminalRequest` (если задан) резолвится и проверяется на принадлежность working directory сессии тем же application-level механизмом, что и для fs; отсутствие `cwd` в запросе означает использование `cwd` сессии по умолчанию. Escape отклоняется до старта процесса. Эта проверка не связана с approval-решением и остаётся обязательной.

### 6. Disposal — завершение процессов при disconnect/dispose, отдельно от `add-integrated-terminal`
Все `TerminalSession` активной ACP-сессии убиваются (`kill`-семантика) при disconnect/dispose этой сессии или shutdown приложения, независимо от closure интерактивного `TerminalProcessFactory` из `add-integrated-terminal` — два независимых реестра процессов с независимым lifecycle (`AGENTS.md §9`: subscription/process ДОЛЖЕН иметь явного owner).

## Risks / Trade-offs

- [Агент может выполнять произвольные shell-команды (в пределах working directory) без единого запроса подтверждения] → working-directory containment (decision №5) и обязательный `terminal/release`/disposal — единственные компенсирующие контроли; риск принят осознанно, симметрично `add-acp-fs-client-support`. Рекомендуется логировать каждый `terminal/create` (команда, аргументы, cwd) в диагностику для post-hoc наблюдаемости (`AGENTS.md §16`).
- [Документ `docs/architecture/permissions.md` и `AGENTS.md §10` формально противоречат этой реализации, пока не обновлены] → правка запланирована в `add-acp-fs-client-support/tasks.md` и покрывает оба change; если этот change реализуется первым/независимо, соответствующую задачу нужно перенести сюда явно, а не считать её выполненной по умолчанию.
- [Долгоживущий процесс, для которого агент никогда не вызвал `release` (нарушение MUST из спеки на стороне агента)] → процесс всё равно убивается при disconnect/dispose сессии (decision №6); в рамках активной сессии он остаётся как resource leak до явного `release`/`kill`.
- [Race между `terminal/kill` (агент) и естественным завершением процесса] → adapter должен атомарно проверять текущее состояние перед kill (уже `exited` → no-op, не ошибка).
- [`outputByteLimit`-обрезка по границе символа для multi-byte UTF-8 вывода усложняет buffer-management] → покрыть отдельным unit-тестом на буфер с multi-byte граничным символом.
- [Два независимых process-реестра (этот change и `add-integrated-terminal`) могут разойтись в паттернах] → зафиксировать общий низкоуровневый паттерн в `docs/architecture/concurrency.md`, если `add-integrated-terminal` реализуется позже.

## Open Questions

- Нужно ли в этом MVP поддерживать `env`-переменные из `CreateTerminalRequest` без ограничений, или CodeLab должен фильтровать/маскировать чувствительные переменные окружения перед их использованием (`AGENTS.md §16`)? Вопрос становится более значимым в отсутствие approval-гейта — команда с произвольным `env` выполнится немедленно.
- Учитывая отсутствие client-side approval, стоит ли рассмотреть отдельным будущим change client-side блок-лист заведомо деструктивных команд (`rm -rf`, `git push --force` и т.п.), не как approval, а как hard deny? Вне scope этого change, но стоит явно зафиксировать как нерешённое.
