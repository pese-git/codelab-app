## Why

Требование "Agent workbench interaction patterns" (`openspec/changes/define-codelab-mvp/specs/agent-workbench-ui/spec.md:37`) уже перечисляет "progress checklist" как обязательный паттерн workbench. Протокол полностью готов к этому: `Plan`/`PlanEntry` с `priority` (`high`/`medium`/`low`) и `status` (`pending`/`in_progress`/`completed`) смоделированы в `packages/dart/acp_protocol/lib/src/acp/session_update.dart:77-192`. Но нигде в `apps/codelab_app` или `packages/flutter/acp_ui` `PlanEntry` не используется — ни в кубите, ни в state, ни в UI (проверено `grep`, ноль совпадений). Требование специфицировано, но не реализовано ни на сколько процентов.

## What Changes

- Добавляется `AcpProgressChecklist` — organism в `acp_ui`, показывающий список `PlanEntry` с индикатором статуса (empty circle=`pending`, half-clock=`in_progress`, checkmark=`completed`), бейджем приоритета (`high`/`medium`/`low`) и агрегированным прогрессом ("N of M done" + progress bar).
- `CodeLabShellCubit` обрабатывает `SessionUpdate` варианта `plan` (если такой существует в `session_update.dart` — уточняется в design.md) и хранит текущий `Plan` в `CodeLabShellState`.
- В `WorkbenchMainPane` добавляется компактная сводка чеклиста над транскриптом (текущий активный шаг + "N of M"), разворачиваемая в полный список.
- Чеклист скрыт полностью, если у активной сессии нет плана (агент не прислал `plan` update) — не показываем пустой/фиктивный чеклист.
- **BREAKING**: нет. Contracts ACP не меняются — используется уже существующая часть протокола.

## Capabilities

### New Capabilities

_(нет)_

### Modified Capabilities

- `agent-workbench-ui`: конкретизирует ранее нереализованный паттерн "progress checklist" из "Agent workbench interaction patterns" — как именно он рендерится и на основе каких данных.

## Impact

- `packages/flutter/acp_ui/lib/src/organisms/` — новый `AcpProgressChecklist`.
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — обработка `SessionUpdate.plan`, добавление `currentPlan` в `CodeLabShellState`.
- `apps/codelab_app/lib/features/workbench/presentation/widgets/main_pane.dart` — интеграция компактной сводки + полного чеклиста.
- `apps/codelab_app/test/widget_test.dart` — тесты на обновление плана, скрытие при отсутствии плана.
