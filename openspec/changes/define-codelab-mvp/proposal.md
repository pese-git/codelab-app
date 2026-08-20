## Why

CodeLab нужен формальный MVP contract до начала реализации, потому что проект
объединяет protocol correctness, desktop UX, security approvals и
multi-package architecture. Фиксация этого в OpenSpec позволит держать ACP
client, Flutter UI, DI setup и reference agent integration согласованными во
время bootstrap monorepo.

## What Changes

- Определить CodeLab как desktop-first ACP client для работы с local и remote
  AI agents.
- Зафиксировать layered monorepo architecture для `acp_protocol`,
  `acp_transports`, `acp_client_core`, `acp_testing`, `acp_ui` и
  `codelab_app`.
- Сделать обязательными Clean Architecture с hexagonal boundaries, SOLID, KISS,
  DRY и явные ограничения по design patterns.
- Требовать ACP JSON-RPC 2.0 compatibility на основе официальной документации в
  `docs/acp/protocol/`.
- Определить MVP transports: stdio для local agents и WebSocket для remote
  agents.
- Требовать stdio compatibility с `https://github.com/pese-git/codelab-agent`
  через default profile `codelab serve --stdio`.
- Определить session lifecycle, prompt turns, streaming updates, permissions,
  cancellation, disconnect/reconnect и observability expectations.
- Определить conservative approval policy и MVP permission modes:
  `readOnly`, `ask`, `plan`, `autoEdits`.
- Требовать Flutter desktop UI на базе `fluent_ui`, а не Material/Cupertino как
  base design framework.
- Определить agent workbench UX: command bar, sessions pane,
  transcript/prompt area, inspector, inline approvals, view modes,
  command palette/slash commands и keyboard-first ergonomics.
- Требовать Atomic Design organization для UI widgets:
  `atomics`, `molecules`, `organisms`.
- Требовать Bloc/Cubit для Flutter state management и CherryPick v4.x.x для DI.
- Стандартизировать `fpdart` и `freezed` для typed functional primitives,
  immutable state, DTOs и union models.

## Capabilities

### New Capabilities

- `workspace-architecture`: определяет monorepo packages, Clean Architecture
  boundaries, dependency rules, DI, allowed patterns и engineering principles.
- `acp-protocol-client`: определяет ACP JSON-RPC client contract,
  initialization, sessions, prompt turns, streaming updates, permissions,
  cancellation, errors и compatibility с официальной ACP documentation.
- `agent-transports`: определяет stdio и WebSocket transport behavior,
  reference `codelab-agent` stdio integration, process lifecycle, diagnostics и
  test requirements.
- `agent-workbench-ui`: определяет Fluent UI desktop UX, sessions/task
  navigation, transcript, inspector, inline approvals, permission/view modes,
  command palette, keyboard ergonomics и Atomic Design widget structure.
- `approval-safety`: определяет risk levels, permission modes, approval UI,
  read-only policy, destructive action handling, secret redaction и safety
  constraints.
- `testing-quality`: определяет unit, conformance, integration, Flutter и
  Definition of Done requirements для MVP.

### Modified Capabilities

Нет.

## Impact

- Добавляет OpenSpec artifacts для CodeLab MVP до начала реализации.
- Затрагивает будущие root workspace files: `pubspec.yaml`, `melos.yaml`,
  `analysis_options.yaml`, `.fvm/fvm_config.json` и package `pubspec.yaml`
  files.
- Затрагивает будущие packages в `packages/dart/` и `packages/flutter/`, а также
  app в `apps/codelab_app`.
- Добавляет dependency expectations для `fluent_ui`, Bloc/Cubit,
  CherryPick v4.x.x, `fpdart`, `freezed`, build_runner/codegen и ACP protocol
  schemas.
- Требует integration testing с `codelab-agent` через stdio.
- Не добавляет production code; этот change устанавливает implementation
  contract и acceptance criteria.
