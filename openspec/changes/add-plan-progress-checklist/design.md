## Context

`SessionUpdate.plan({required List<PlanEntry> entries})` (`packages/dart/acp_protocol/lib/src/acp/session_update.dart:191-195`) — один из вариантов sealed class `SessionUpdate`, наравне с уже обрабатываемыми `userMessageChunk`/`agentMessageChunk`/`toolCall`/`toolCallUpdate`. `CodeLabShellCubit` уже обрабатывает `SessionUpdate` для построения транскрипта и инспектора (см. `_handleSessionChange`/маппинг session updates) — `plan` в этой обработке отсутствует полностью.

`PlanEntry` (`session_update.dart:130-165`) несёт `priority: PlanEntryPriority` (`high`/`medium`/`low`) и `status: PlanEntryStatus` (`pending`/`in_progress`/`completed`) плюс контентное поле (описание шага).

## Goals / Non-Goals

**Goals:**
- Обработка `SessionUpdate.plan` в кубите — последний полученный `Plan` для активной сессии хранится в state.
- `AcpProgressChecklist` рендерит список `PlanEntry` 1:1 по протокольным `priority`/`status`, без изобретения новых промежуточных статусов.
- Компактная сводка (текущий `in_progress` шаг + "N of M done") встроена в main pane, полный список — по разворачиванию.
- Чеклист отсутствует (не рендерится вообще), если `plan` update ещё не приходил для сессии — не показываем пустую заглушку.

**Non-Goals:**
- Не добавляется возможность пользователю самому редактировать/переупорядочивать план — это read-only отражение того, что прислал агент.
- Не решается, как несколько последовательных `plan` updates за одну сессию визуально анимируются/сравниваются — на MVP просто заменяем текущий список новым.
- Не связывается с `session/cancel`/`stopReason` напрямую — план остаётся видимым независимо от того, продолжается ли prompt turn.

## Decisions

- **Один `Plan` на сессию, полная замена по каждому update.** `SessionUpdate.plan` несёт полный список entries (не diff/patch) — так что state просто хранит последний полученный `List<PlanEntry>` целиком, без попытки мержить/diff'ить предыдущий список вручную.
- **Статус/приоритет — прямой проброс enum, без промежуточного UI-enum** (в отличие от `add-approval-option-kinds`, где потребовался отдельный `AcpApprovalOptionKind` в `acp_ui`, чтобы не тянуть протокольный пакет в UI-слой) — здесь `AcpProgressChecklist` в `acp_ui` получит свои собственные presentation-enum'ы (`AcpPlanEntryStatus`/`AcpPlanEntryPriority`), 1:1 зеркалящие протокольные, по той же причине разделения границ пакетов.
- **Компактная сводка показывает первый entry со статусом `in_progress`** (если есть), иначе — последний `pending` шаг, иначе — ничего (весь план завершён, сводка не показывается, но полный список остаётся доступен по клику, если нужно посмотреть историю выполнения).
- **State — `CodeLabShellState.currentPlan: List<CodeLabPlanEntry>?`** (presentation view-model, не протокольный `PlanEntry` напрямую — маппинг в кубите, тот же паттерн, что уже используется для `CodeLabInspectorEntry`).

## Risks / Trade-offs

- [Агент может не присылать `plan` updates вовсе — это опционально по ACP] → чеклист просто не появляется (Goals), не считается ошибкой/отсутствующим состоянием.
- [Долгий план с большим числом entries может визуально перегрузить main pane, если полный список всегда развёрнут] → компактная сводка по умолчанию, полный список — по явному действию пользователя (см. Decisions).
- [Несколько последовательных `plan` updates подряд (агент часто уточняет план) могут создать "мерцание" UI при каждой полной замене списка] → не решается сложной diff-анимацией в этом MVP; если станет реальной проблемой после использования — предмет отдельного follow-up change.
