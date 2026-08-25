## 1. AcpResizeHandle (acp_ui)

- [ ] 1.1 Реализовать atomic `AcpResizeHandle`: `MouseRegion(cursor: SystemMouseCursors.resizeColumn)` + `GestureDetector.onPanUpdate` → `onDelta(double dx)`, без внутреннего состояния ширины
- [ ] 1.2 Визуальная линия ~1px, hit-area ~6-8px вокруг неё
- [ ] 1.3 Widget-тест: drag вызывает `onDelta` с ожидаемым значением

## 2. AcpWorkbenchLayout — интеграция

- [ ] 2.1 Добавить `AcpResizeHandle` между `sessionsPane` и `mainPane` в `_buildDesktopBody()`
- [ ] 2.2 Добавить `AcpResizeHandle` между `mainPane` и `inspectorPane` в `_buildDesktopBody()`
- [ ] 2.3 `sessionsPaneWidth`/`inspectorPaneWidth` остаются параметрами конструктора (значения по умолчанию не меняются), добавляются колбэки `onSessionsPaneWidthChanged`/`onInspectorPaneWidthChanged`

## 3. State и кубит

- [ ] 3.1 Добавить `sessionsPaneWidth`/`inspectorPaneWidth` в `CodeLabShellState` (начальные значения = текущие дефолты 280/320)
- [ ] 3.2 Реализовать `resizeSessionsPane(width)`/`resizeInspectorPane(width)` в `CodeLabShellCubit` — clamp по min/max (константы уровня `apps/codelab_app`, например sessions 220–480, inspector 260–520)
- [ ] 3.3 Не эмитить новое состояние на каждый `onPanUpdate` пиксель — throttling/локальный `ValueNotifier` во время активного drag, финальный `emit` на `onPanEnd` (см. design.md Risks)

## 4. Тесты

- [ ] 4.1 Widget-тест: drag границы sessions/main меняет ширину sessions pane
- [ ] 4.2 Widget-тест: drag границы main/inspector меняет ширину inspector pane
- [ ] 4.3 Widget-тест: drag за пределы min — ширина не падает ниже минимума
- [ ] 4.4 Widget-тест: drag за пределы max — ширина не растёт выше максимума
- [ ] 4.5 Widget-тест: ширина сохраняется при пересборке дерева после несвязанного изменения state

## 5. Проверка

- [ ] 5.1 `fvm dart run melos run format`
- [ ] 5.2 `fvm dart run melos run analyze`
- [ ] 5.3 `fvm dart run melos run test`
