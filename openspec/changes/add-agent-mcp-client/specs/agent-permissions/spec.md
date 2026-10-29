## ADDED Requirements

### Requirement: MCP-вызов только после решения политики
Вызов MCP-инструмента SHALL доходить до MCP-сервера (`tools/call`) только после того, как `PermissionPolicy` первым звеном `beforeToolCall` его разрешила (P-01, TOOL-1, PERM-1).

Правила:
- до решения ни одно сообщение этого вызова НЕ SHALL отправляться серверу;
- при отказе, отмене вопроса и отказе режима (`plan`, «спросить» без `interactiveApproval`) сервер НЕ SHALL получать `tools/call`;
- уровень MCP-инструмента всегда `exec`, поэтому в режимах `standard` и `accept-edits` вызов спрашивается, в `plan` — отклоняется без вопроса, а `allow_always` действует только для того же канонического JSON аргументов (§7.5).

Аннотации сервера НЕ SHALL влиять на решение.

#### Scenario: Политика до сервера
- **WHEN** в режиме `standard` модель вызывает `mcp__fake__delete_issue`, а gate отвечает `reject_once`
- **THEN** `session/request_permission` отправлен до любого обращения к серверу, итог вызова `rejected`, `FakeMcpServer.calls` пуст, ход продолжается (`packages/dart/codelab_agent_mcp/test/mcp_tool_goes_through_policy_test.dart: MCP tool is not executed without a permission decision`; фикстура `acp/mcp-tool-permission`)

#### Scenario: Все инструменты и отказывающий gate
- **WHEN** реестр сессии содержит все встроенные и fake MCP-инструменты, режим `ask`, gate отвечает `reject_once`, и модель вызывает каждый
- **THEN** ни один `execute` не вызван, fake-сервер не получил ни одного `tools/call` (`core/no-tool-bypasses-gate`, `no_bypass_test.dart`)

#### Scenario: Режим plan и ложная аннотация
- **WHEN** в режиме `plan` модель вызывает MCP-инструмент `mcp__fake__write_note` с аннотацией `readOnlyHint: true`
- **THEN** вызов отклонён без `session/request_permission`, сервер вызова не получил (фикстура `acp/set-mode-plan-rejects-mcp-write`)
