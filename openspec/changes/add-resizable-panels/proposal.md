## Why

`AcpWorkbenchLayout` (`packages/flutter/acp_ui/lib/src/organisms/acp_workbench_layout.dart`) сегодня задаёт ширины панелей константами конструктора (`sessionsPaneWidth = 280`, `compactSessionsPaneWidth = 176`, `inspectorPaneWidth = 320`) — фиксированными, без возможности пользователю подвинуть границу. Референсы (Claude Code Desktop, Codex, OpenCode) дают перетаскивать границы панелей мышью. Готового сплиттер-виджета в `fluent_ui` нет (`grep` по пакету не дал совпадений), но и не требуется — это решается стандартными Flutter-примитивами (`GestureDetector`/`MouseRegion`), без новой внешней зависимости и без architecture decision по `AGENTS.md` §4.

## What Changes

- Между `sessionsPane`/`mainPane` и между `mainPane`/`inspectorPane` в `AcpWorkbenchLayout` (режим `desktop`) появляется тонкий перетаскиваемый разделитель — курсор меняется на resize при наведении, drag меняет ширину соответствующей панели в реальном времени.
- Ширины ограничены min/max (например, sessions: 220–480px, inspector: 260–520px) — перетащить панель до нуля или до поглощения всего экрана нельзя.
- Ширины панелей — часть `CodeLabShellState` (переживают пересборку виджета в рамках текущего запуска приложения), обновляются через новые методы кубита.
- **Не входит в этот change**: режим `medium` (вертикальный сплит main/inspector), терминал-панель из `add-integrated-terminal` (получит свой resize-хендл отдельно, переиспользуя тот же примитив — см. design.md), persistence ширин между перезапусками приложения (Open Question).
- **BREAKING**: нет. Значения по умолчанию (280/320) не меняются — просто становятся начальными, а не единственными.

## Capabilities

### New Capabilities

_(нет)_

### Modified Capabilities

- `agent-workbench-ui`: уточняет desktop-layout (уже специфицированный в `define-codelab-mvp` как "command bar, sessions pane, transcript/prompt area, inspector") — границы между этими зонами становятся перетаскиваемыми, ранее это поведение нигде не было специфицировано.

## Impact

- `packages/flutter/acp_ui/lib/src/atomics/` — новый `AcpResizeHandle` (или аналогичное имя): тонкая полоса с hover/drag-курсором, min/max-ограничения, колбэк на изменение.
- `packages/flutter/acp_ui/lib/src/organisms/acp_workbench_layout.dart` — интеграция `AcpResizeHandle` между слотами в `_buildDesktopBody()`, ширины становятся управляемыми параметрами (значения приходят от родителя, не хранятся внутри layout-виджета).
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — новые поля состояния и методы `resizeSessionsPane(width)`/`resizeInspectorPane(width)`.
- `packages/flutter/acp_ui/test/` — тесты на drag, на применение min/max ограничений.
