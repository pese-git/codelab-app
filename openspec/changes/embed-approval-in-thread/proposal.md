## Why

`openspec/specs/agent-workbench-ui/spec.md` уже требует: *"approval появляется inline в transcript"* (Requirement "Паттерны взаимодействия agent workbench", scenario "Показывается ожидающий approval"). Фактическая реализация этому не соответствует:

- `CodeLabShellCubit._agentTranscriptEntries` ([shell_cubit.dart:1338-1401](../../../apps/codelab_app/lib/features/workbench/application/shell_cubit.dart#L1338)) строит записи transcript **только** из `AgentMessageChunk`/`AgentThoughtChunk` — `SessionUpdate.toolCall`/`toolCallUpdate` полностью игнорируются. Ни один tool call сегодня не попадает в transcript вообще, хотя `AcpTranscriptEntryKind.toolCall` и `AcpTranscriptEntryKind.approval` уже существуют и полностью отрисовываются в `acp_ui` ([acp_transcript_panel.dart:6](../../../packages/flutter/acp_ui/lib/src/organisms/acp_transcript_panel.dart#L6)) — это неиспользуемая capability виджета, а не намеренное решение.
- Единственное место, где approval виден пользователю в основном окне — фиксированная панель между `AcpTranscriptPanel` и `AcpPromptComposer` ([main_pane.dart:69-79](../../../apps/codelab_app/lib/features/workbench/presentation/widgets/main_pane.dart#L69)), управляемая единственным глобальным `state.pendingApproval`/`CodeLabShellCubit._pendingApprovalFor` ([shell_cubit.dart:1179](../../../apps/codelab_app/lib/features/workbench/application/shell_cubit.dart#L1179)) — не частью прокручиваемой ленты, а отдельным закреплённым слотом снаружи неё.
- Это также структурно не масштабируется на параллельные tool calls: `docs/architecture/streaming.md:650` явно допускает, что "если tool call ждёт permission, это не обязательно terminal pause всего session stream" (возможны параллельные tool calls, `streaming.md:656`), но единственный глобальный `pendingApproval`-слот физически не может показать больше одного ожидающего approval одновременно.

Референс — Zed (и Claude Code Desktop, уже упомянутые как референсы в `add-integrated-terminal/proposal.md`): approval — часть карточки того tool call, к которому относится, живёт в потоке диалога, после решения не исчезает, а схлопывается в маркер решения на своём месте.

Это исправление существующего, уже сформулированного в спецификации требования, а не новая capability — этим change реализуется requirement, которого implementation до сих пор не достигала.

## What Changes

- `CodeLabShellCubit._transcriptEntriesForSession`/`_agentTranscriptEntries` ДОЛЖНЫ учитывать `SessionUpdate.toolCall`/`toolCallUpdate` из `turn.updates`, вставляя tool-call запись transcript в хронологическую позицию потока (там, где агент создал tool call), а не игнорировать их. Текущий статус/содержимое каждого tool call берётся из `turn.toolCalls[id]` (уже живой read model, обновляемый по `toolCallUpdate`), а не заново парсится из потока обновлений.
- Каждая tool-call запись transcript, для которой есть `ApprovalRequest` в `turn.approvals` со статусом `pending`, ДОЛЖНА рендерить интерактивную approval-карточку (риск, причина, детали, опции с callback) непосредственно внутри этой записи — а не в отдельном слоте.
- После того как approval получает решение (`ApprovalStatus.selected`/`cancelled`), запись ДОЛЖНА схлопываться в компактный resolved-маркер на том же месте (например, "✓ Allowed once"), оставаясь в истории транскрипта, а не исчезать и не сбрасываться в чистый tool-call без следа решения.
- Фиксированная панель `state.pendingApproval` в `main_pane.dart` УДАЛЯЕТСЯ — approval больше не имеет отдельного глобального слота вне ленты.
- Лента (`AcpTranscriptPanel`) ДОЛЖНА автоматически прокручиваться к новой approval-записи, когда она появляется, если пользователь не проскроллил вручную выше (не выдёргивать фокус, если пользователь читает историю).
- Существующие клавиатурные шорткаты approve/reject (`Ctrl/Cmd+Enter`/`Escape`, `CallbackShortcuts` в `AcpApprovalOptionGroup`) ДОЛЖНЫ продолжать работать для approval, видимого на экране, независимо от того, что теперь их может быть несколько в ленте одновременно — привязка к конкретному approval, а не к глобальному состоянию.
- `acp_ui`: `AcpTranscriptEntry`/`AcpTranscriptPanel` получают возможность нести approval-данные для tool-call записи (интерактивные — pending, или resolved-маркер) — расширение существующей `organisms`-модели, не новый widget с нуля.
- **BREAKING**: нет для внешних потребителей `acp_protocol`/ACP contracts — ACP wire protocol не меняется. Внутри приложения меняется presentation-модель transcript (`AcpTranscriptEntry` получает новые опциональные поля) и убирается публичный use case `state.pendingApproval` в `CodeLabShellState` — оба принадлежат presentation/application слоям приложения, не публичному API пакетов.

## Capabilities

### Modified Capabilities
- `agent-workbench-ui`: уточняется и наконец реализуется существующее требование "approval появляется inline в transcript" — сценарий переписывается так, чтобы однозначно требовать embedded-в-записи рендеринг (а не допускать текущее прочтение через отдельную закреплённую панель), плюс новые сценарии: несколько параллельных pending approval одновременно видимы каждый на своём месте, resolved approval остаётся в истории как маркер, автоскролл к новому approval.

## Impact

- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — `_transcriptEntriesForSession`/`_agentTranscriptEntries` учитывают tool-call updates из `turn.updates`; `_pendingApprovalFor`/`CodeLabPendingApproval`/`state.pendingApproval` удаляются или перерабатываются в per-entry данные, передаваемые через записи transcript.
- `apps/codelab_app/lib/features/workbench/presentation/widgets/main_pane.dart` — убирается блок `if (state.pendingApproval case ...)` ([main_pane.dart:69](../../../apps/codelab_app/lib/features/workbench/presentation/widgets/main_pane.dart#L69)); `AcpPromptComposer` остаётся, но состояние "решение ожидается" не блокируется отдельным виджетом снаружи ленты.
- `packages/flutter/acp_ui/lib/src/organisms/acp_transcript_panel.dart` — `AcpTranscriptEntry` получает поля для approval-карточки (options/callback/risk/резолюция); строка записи рендерит `AcpApprovalPanel`/аналог inline, когда они заданы; добавляется auto-scroll-to-new-approval поведение.
- `packages/flutter/acp_ui/lib/src/organisms/acp_approval_panel.dart` — переиспользуется как есть или адаптируется под компактный inline-контекст (без внешней рамки/фона, если запись transcript уже её даёт).
- Виджет-тесты `acp_ui`/`shell_cubit` — покрытие на: tool call появляется в transcript в правильной позиции; approval рендерится в записи, а не отдельно; resolved-маркер остаётся после решения; два параллельных approval видимы независимо; автоскролл к новому approval.
