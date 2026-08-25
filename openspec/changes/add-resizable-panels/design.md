## Context

`AcpWorkbenchLayout._buildDesktopBody()` (`acp_workbench_layout.dart:72-100`) рендерит `Row[sessionsPane(width: sessionsPaneWidth), gap, mainPane(Expanded), gap, inspectorPane(width: inspectorPaneWidth)]` — ширины приходят из полей конструктора самого `AcpWorkbenchLayout` (`sessionsPaneWidth = 280`, `inspectorPaneWidth = 320` — значения по умолчанию, не переопределяются нигде в `apps/codelab_app` сегодня). Нет ни одного место в коде, где пользователь мог бы изменить эти значения.

## Goals / Non-Goals

**Goals:**
- Перетаскивание границы между sessions/main и между main/inspector в режиме `desktop` меняет ширину в реальном времени.
- Min/max-ограничения не дают панели схлопнуться до нуля или поглотить весь main pane.
- Изменённая ширина сохраняется в `CodeLabShellState` — переживает пересборку виджета (не персистентна между перезапусками приложения в этом MVP).

**Non-Goals:**
- Не решается resize для режима `medium` (вертикальный сплит main/inspector) — тот же примитив можно переиспользовать позже, но не в этом change.
- Не решается resize терминал-панели из `add-integrated-terminal` — тот change, когда будет реализован, должен переиспользовать `AcpResizeHandle`, но это его собственная задача, не часть этого change.
- Не решается полноценная система drag-to-rearrange (докинг панелей в произвольном порядке, как в некоторых десктоп-IDE) — пользователь просил именно resize существующих границ, не перекомпоновку.
- Не решается persistence ширин между перезапусками приложения — вынесено в Open Questions.

## Decisions

- **`AcpResizeHandle` — новый atomic в `acp_ui`, не сторонний пакет.** Тонкий (например, 4-6px) вертикальный hit-target с `MouseRegion(cursor: SystemMouseCursors.resizeColumn)` и `GestureDetector.onPanUpdate`, отдающий delta наружу через колбэк `onDelta(double dx)` — сам виджет не хранит состояние ширины, только сообщает об изменении; экономит на architecture decision по внешней зависимости (`AGENTS.md` §4) и не тянет непроверенный пакет ради простого drag-хендла.
- **Ширины — параметры `AcpWorkbenchLayout`, не внутреннее состояние.** Layout остаётся stateless-ориентированным (как сейчас) — `sessionsPaneWidth`/`inspectorPaneWidth` приходят от родителя вместе с колбэками `onSessionsPaneWidthChanged`/`onInspectorPaneWidthChanged`; сам layout не решает, где хранить актуальное значение — это подтверждает существующее разделение (`docs/architecture/layers-and-dependencies.md`) между `acp_ui` (presentation-агностик) и `apps/codelab_app` (владеет state).
- **Min/max — константы на уровне `apps/codelab_app`**, не хардкод внутри `acp_ui`-виджета: `AcpResizeHandle`/`AcpWorkbenchLayout` не навязывают конкретные числа — clamp применяется в кубите при обработке `resizeSessionsPane(width)`/`resizeInspectorPane(width)`, чтобы значения min/max были специфичны для CodeLab, а не зашиты в переиспользуемый `acp_ui`-примитив.
- **Курсор меняется на `SystemMouseCursors.resizeColumn` при наведении на хендл**, не только во время активного drag — стандартный десктопный паттерн обнаружения перетаскиваемой границы до начала действия.

## Risks / Trade-offs

- [Частые `setState`/`emit` на каждый pixel движения мыши во время drag может создавать лишние rebuild'ы всего `BlocBuilder<CodeLabShellCubit, CodeLabShellState>` дерева (тот же паттерн производительности, что уже отмечен как smell для transport-полей)] → рассмотреть локальный `ValueNotifier`/throttling ширины во время активного drag, финальный `emit` в state — только по завершении жеста (`onPanEnd`), не на каждый `onPanUpdate`; решается на этапе задач, не блокирует дизайн.
- [Пользователь может не заметить, что граница перетаскиваемая, если курсор не меняется вовремя] → `MouseRegion` покрывает достаточно широкую hit-зону вокруг тонкой визуальной линии (например, визуально 1px, hit-area 6-8px) — стандартная практика для точных resize-хендлов.
- [Отсутствие persistence между перезапусками может расстраивать пользователей, привыкших к IDE, где размеры панелей запоминаются] → осознанно не в scope MVP, см. Open Questions.

## Open Questions

- Нужна ли persistence ширин панелей между перезапусками приложения (например, через `shared_preferences`-подобное хранилище) — не блокирует эту реализацию, отдельное решение при появлении реального запроса.
