## Why

Требование "Agent workbench interaction patterns" (`openspec/changes/define-codelab-mvp/specs/agent-workbench-ui/spec.md:37`) уже перечисляет "progress checklist" как обязательный паттерн workbench. Протокол полностью готов к этому: `Plan`/`PlanEntry` с `priority` (`high`/`medium`/`low`) и `status` (`pending`/`in_progress`/`completed`) смоделированы в `packages/dart/acp_protocol/lib/src/acp/session_update.dart:77-192`. Но нигде в `apps/codelab_app` или `packages/flutter/acp_ui` `PlanEntry` не используется — ни в кубите, ни в state, ни в UI (проверено `grep`, ноль совпадений). Требование специфицировано, но не реализовано ни на сколько процентов.

## What Changes

- Добавляется `AcpActivityBar` — новый переиспользуемый organism в `acp_ui`: docked-контейнер под транскриптом, вплотную над композером, со списком секций, разделённых линией (в этом change зарегистрирована только одна секция — Plan; "Edited files"/"Queue" — зарезервированные точки расширения без реализации, см. `design.md`). Место размещения сверено с реальным кодом Zed (`crates/agent_ui/src/conversation_view/thread_view.rs`), а не придумано на глаз.
- Добавляется `AcpProgressChecklist` — organism в `acp_ui`, показывающий список `PlanEntry` с индикатором статуса (empty circle=`pending`, half-clock=`in_progress`, checkmark=`completed`), бейджем приоритета (`high`/`medium`/`low`) и текстовой сводкой ("Current: <шаг>" + "N left", либо "N Tasks"/"N/M" — без прогресс-бара). Разворачивается по клику на всю строку сводки в список с фиксированной максимальной высотой и внутренним скроллом.
- `CodeLabShellCubit` обрабатывает `SessionUpdate` варианта `plan` и хранит текущий `Plan` в `CodeLabShellState`; добавляется `dismissPlan()` — локальное клиентское действие "очистить план с экрана" (кнопка "✕" в сводке), не протокольная операция.
- Чеклист (и вся секция `AcpActivityBar`) скрыт полностью, если у активной сессии нет плана (агент не прислал `plan` update, либо план был явно отклонён через `dismissPlan()`) — не показываем пустой/фиктивный чеклист.
- **BREAKING**: нет. Contracts ACP не меняются — используется уже существующая часть протокола.

## Capabilities

### New Capabilities

_(нет)_

### Modified Capabilities

- `agent-workbench-ui`: конкретизирует ранее нереализованный паттерн "progress checklist" из "Agent workbench interaction patterns" — как именно он рендерится и на основе каких данных.

## Impact

- `packages/flutter/acp_ui/lib/src/organisms/` — новый `AcpActivityBar` (docked-контейнер, секции) и новый `AcpProgressChecklist` (содержимое секции Plan).
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — обработка `SessionUpdate.plan`, добавление `currentPlan` в `CodeLabShellState`, новый метод `dismissPlan()`.
- `apps/codelab_app/lib/features/workbench/presentation/widgets/main_pane.dart` — `AcpActivityBar` вставляется между транскриптом и композером (не над транскриптом).
- `apps/codelab_app/test/widget_test.dart` — тесты на обновление плана, скрытие при отсутствии плана, `dismissPlan()`.
