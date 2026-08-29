## Context

Сейчас repository содержит project guidance, официальную ACP protocol
documentation и `docs/codelab-spec.md`, но реализованного Dart/Flutter monorepo
еще нет. Поэтому MVP должен сначала зафиксировать architecture: package
boundaries, protocol ownership, transport adapters, application state,
desktop UI, dependency injection и test strategy.

CodeLab — desktop-first ACP client. Он должен работать с официальным
ACP JSON-RPC 2.0 protocol, поддерживать local stdio agents и предоставлять
компактный agent workbench UI для sessions, streaming updates, tool calls,
permissions, cancellation, diagnostics и review-first changes.

Первый конкретный stdio compatibility target:
`https://github.com/pese-git/codelab-agent`, default запуск:
`codelab serve --stdio`.

## Goals / Non-Goals

**Goals:**

- Bootstrap Dart/Flutter/FVM/Melos monorepo с четкими package boundaries.
- Сохранить protocol и core logic как pure Dart, независимые от Flutter.
- Реализовать ACP client behavior через typed models, codecs, validation и
  state machines.
- Поддержать stdio и WebSocket transports через заменяемые ports/adapters.
- Предоставить Fluent UI desktop workbench с sessions, transcript, inspector,
  inline approvals, permission modes, view modes и keyboard ergonomics.
- Использовать CherryPick v4.x.x для dependency injection в composition root.
- Использовать Bloc/Cubit только во Flutter presentation layer.
- Использовать `fpdart` и `freezed` для typed outcomes и immutable/union models.
- Протестировать protocol, state, transport, approvals, cancellation и
  reference agent compatibility.

**Non-Goals:**

- Local LLM inference в client.
- Mobile-first или web-parity implementation в MVP.
- SSE transport в MVP.
- Local transcript persistence в MVP.
- Полный ACP `authenticate` workflow в MVP.
- Bypass/full-access permission mode.
- Копирование visual trade dress из Codex, Claude Code, OpenCode или других
  tools.

## Decisions

### 1. Использовать Clean Architecture с hexagonal boundaries

CodeLab использует слои Presentation, Application, Domain и Infrastructure.
Dependencies направлены внутрь: UI зависит от application/domain contracts, а
domain/application не зависят от Flutter, Bloc, `fluent_ui`, `dart:io` или
concrete transports.

Alternatives considered:

- Feature-first Flutter architecture: быстрее для небольшого app, но повышает
  риск смешать ACP protocol parsing, UI и process management.
- Service-layer architecture: проще по naming, но слабее по dependency direction
  и легче превращается в god services.

Rationale: ACP correctness, permissions, cancellation и transport lifecycles
нуждаются в стабильных boundaries и testable pure Dart behavior.

### 2. Разделить monorepo на protocol, transports, core, testing, UI и app

Packages:

- `packages/dart/acp_protocol`: ACP DTOs, JSON-RPC codec, schema validation и
  protocol errors.
- `packages/dart/acp_transports`: stdio, WebSocket и fake transport adapters.
- `packages/dart/acp_client_core`: sessions, prompt turns, approvals,
  cancellation, connection workflows, policies и application use cases.
- `packages/dart/acp_testing`: mock agents, fake transports, fixtures и
  conformance helpers.
- `packages/flutter/acp_ui`: Fluent UI widgets, организованные как `atomics`,
  `molecules` и `organisms`.
- `apps/codelab_app`: composition root, DI, routing, platform wiring и
  desktop application shell.

Alternatives considered:

- One package app: быстрее на старте, но усложняет reuse и testing для
  protocol/core.
- Более дробные packages по features: слишком много overhead до того, как
  implementation подтвердит границы.

Rationale: это разделение соответствует причинам изменений и удерживает Flutter
вне lower layers.

### 3. Считать официальные ACP docs источником истины по protocol

`docs/acp/protocol/` и `docs/acp/protocol/17-Schema.md` определяют wire
contract. `acp_protocol` должен encode/decode и validate сообщения по этому
contract. Custom extensions должны использовать ACP `_meta`, а custom methods
должны начинаться с `_`.

Alternatives considered:

- Определить local provisional protocol: больше не нужно, потому что official
  ACP docs уже добавлены.
- Использовать raw JSON maps во всем app: быстрее сначала, но небезопасно для UI
  и core state transitions.

Rationale: protocol correctness — один из главных project priorities, а typed
models уменьшают coupling UI/core к wire format.

### 4. Реализовать transports как replaceable adapters

`acp_transports` предоставляет общий transport port для inbound message streams,
outbound sends, lifecycle events и graceful shutdown. Stdio использует child
process stdout для ACP messages и stderr для diagnostics. WebSocket
поддерживает remote agents. Fake transport используется в tests.

Alternatives considered:

- Встроить stdio напрямую в core: проще, но мешает transport substitution и
  clean testing.
- Использовать только WebSocket: теряется основной local desktop ACP workflow.

Rationale: stdio обязателен для local `codelab-agent`, а WebSocket оставляет
architecture готовой к remote agents.

### 5. Использовать `codelab-agent` как reference stdio integration

App предоставляет built-in editable profile:

```json
{
  "name": "Codelab Agent",
  "type": "custom",
  "command": "codelab",
  "args": ["serve", "--stdio"],
  "env": {
    "CODELAB_LOG_LEVEL": "DEBUG"
  }
}
```

Alternatives considered:

- Требовать ручную настройку каждого agent: гибко, но плохо для MVP onboarding и
  не дает compatibility target.
- Hard-code profile без редактирования: проще, но хрупко для local
  environments.

Rationale: default profile делает MVP сразу полезным, сохраняя возможность
переопределить command, cwd, args и env под окружение пользователя.

### 6. Моделировать sessions и prompt turns как state machines

Core state явно моделирует connection, initialization, ready, running,
awaiting approval, completed, failed, cancelled и disconnected states.
Prompt turn cancellation отправляет `session/cancel`, отвечает на pending
`session/request_permission` через `cancelled`, принимает late `session/update`
до response на исходный `session/prompt` и подтверждает cancellation через
`stopReason: cancelled`.

Alternatives considered:

- Напрямую отображать streamed updates без state machine: меньше усилий, но
  хрупко для duplicate events, approvals и cancellation.

Rationale: agent streams асинхронны и могут содержать duplicate, late или
interleaved events. Для стабильного UX нужны idempotent state transitions.

### 7. Использовать CherryPick v4.x.x в composition root

Dependency injection использует CherryPick v4.x.x. App root отвечает за root
scope creation и shutdown. Feature/session scopes создаются явно, если их
lifecycle короче app lifecycle. Core/application classes получают dependencies
через constructors или factories, а не через произвольный service locator
access.

Alternatives considered:

- Только manual wiring: приемлемо на раннем этапе, но плохо масштабируется между
  transport, protocol, core и UI modules.
- `get_it`/service locator: удобно, но конфликтует с желаемыми Clean
  Architecture constraints.

Rationale: CherryPick дает structured modules/scopes и при этом не протаскивает
DI в domain logic.

### 8. Строить desktop UI как Fluent agent workbench

UI использует `fluent_ui` и workbench layout:

- command bar для agent, transport, cwd, status, modes, cancel/reconnect;
- sessions pane для tasks/sessions;
- transcript и prompt composer как main work area;
- inspector для approvals, diffs, raw input/output, logs и diagnostics.

Widgets в `acp_ui` организованы как `atomics`, `molecules` и `organisms`.

Alternatives considered:

- Material/Cupertino: привычно для Flutter, но явно отклонено для desktop Fluent
  target.
- Chat-only layout: недостаточно для approvals, diffs, logs и tool diagnostics.

Rationale: coding-agent UX требует surfaces для review, context и control, не
перегружая transcript.

### 9. Принять conservative approval и permission modes

MVP modes: `readOnly`, `ask`, `plan`, `autoEdits`. Bypass/full-access не входит
в MVP. Approvals scoped к active session/turn и показывают command, cwd, diff,
risk, reason и available options до approval.

Alternatives considered:

- Один approval mode: проще, но менее удобно для planning и iteration.
- Bypass mode: быстро, но небезопасно без отдельного security design.

Rationale: это балансирует productivity и explicit control над write, terminal,
network и destructive operations.

### 10. Использовать `freezed` и `fpdart` для typed state и failures

`freezed` используется для immutable state, DTOs и union models там, где это
повышает type safety. `fpdart` используется для typed `Option`/`Either`/result
flows в pure Dart layers.

Alternatives considered:

- Plain classes и nullable/error flows: меньше dependencies, но больше
  boilerplate и слабее failure modeling.

Rationale: protocol и state-machine code выигрывают от explicit unions,
immutability и typed recoverable failures.

## Risks / Trade-offs

- CherryPick v4.x.x может отставать от stable package releases -> перед
  implementation проверить package versions и явно закрепить compatible
  prerelease/stable versions.
- Fluent UI может не покрыть все нужные widgets -> недостающие controls строить
  в `acp_ui` atomics, сохраняя Fluent behavior и styling.
- ACP schema docs могут измениться -> держать protocol models generated или
  validated against `docs/acp/protocol/17-Schema.md` и добавить conformance
  tests.
- Stdio process management может зависеть от platform -> изолировать process
  launch за transport adapter и тестировать process exit, stderr, invalid JSON и
  cancellation.
- Permission modes могут быть неочевидны -> держать labels короткими,
  показывать current mode рядом с composer и использовать clear approval copy.
- Отсутствие local transcript persistence в MVP ограничивает recovery после app
  restart -> использовать `session/load` только если agent поддерживает это, а
  local persistence вынести в future change.

## Migration Plan

1. Держать `docs/codelab-spec.md` как product/architecture reference, пока
   создаются OpenSpec artifacts.
2. Создать specs для каждой capability из proposal.
3. Создать implementation tasks на основе specs и design.
4. Bootstrap monorepo structure и root tooling.
5. Реализовать pure Dart protocol/core/transports до Flutter app shell.
6. Добавить Fluent UI workbench после появления typed core state и transport
   contracts.
7. Validate через unit, conformance, stdio integration и Flutter tests.

Rollback до начала implementation является documentation-level: revert
OpenSpec change или обновить capability specs до apply tasks.

## Open Questions

- Какие exact CherryPick v4.x.x package versions нужно pin при старте
  implementation?
- Нужно ли генерировать ACP models напрямую из `17-Schema.md`, или сначала
  написать их вручную с conformance tests?
- Какие WebSocket framing details CodeLab должен поддержать для remote agents в
  MVP?
- Какие keyboard shortcuts должны быть зарезервированы за CodeLab, а какие
  унаследованы из platform conventions?
