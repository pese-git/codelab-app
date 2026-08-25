## Context

`CodeLabShellCubit` уже хранит state приложения (`CodeLabShellState`) и управляет единственным экраном `CodeLabShell` через `BlocBuilder`. `AcpCommandPaletteSurface` (organism в `acp_ui`) — самодостаточный виджет с поиском/фильтрацией по `AcpCommandAction.filter()`, но нигде не смонтирован в дереве `apps/codelab_app`. `openCommandPalette()` — единственный метод, который должен переключать видимость палитры, сейчас no-op.

## Goals / Non-Goals

**Goals:**
- Палитра открывается по `Ctrl/Cmd+K` и закрывается по `Esc` или после выбора команды; все шесть команд видны и выбираемы.
- `/new`, `/reconnect`, `/logs` выполняют реальное действие через уже существующие методы `CodeLabShellCubit` (`createSession()`, `reconnect()`, раскрытие `AcpDebugLogPanel`) — новых use cases не создаётся.
- `/plan`, `/permissions`, `/compact` при выборе явно показывают "недоступно" вместо тихого no-op — честное отражение реального состояния, а не имитация готовности.
- Видимость палитры — часть `CodeLabShellState`, а не отдельный boolean флаг вне state machine (см. `docs/architecture/state-management.md`).

**Non-Goals:**
- Не реализуется permission-mode selector, plan-mode или compact-transcript механизм — в кубите/state для них нет ни одного поля (проверено: `grep` по `permissionMode|planMode|compact` в `shell_cubit.dart` не дал совпадений), это отдельные фичи вне scope палитры. Каждая — предмет собственного будущего OpenSpec change.
- Не меняется набор команд и не добавляются новые.
- Не меняется `AcpCommandPaletteSurface`/`AcpCommandAction` в `acp_ui` — переиспользуются как есть.
- Не реализуется полноценный `editProfile()` или WebSocket reconnect — это отдельный change `complete-transport-setup-actions`.

## Decisions

- **Видимость палитры — поле `isCommandPaletteOpen` в `CodeLabShellState`**, переключаемое через `openCommandPalette()`/`closeCommandPalette()` в кубите. Альтернатива (локальный `StatefulWidget`-флаг в `workbench_shell.dart`) отклонена: presentation не должен быть source of truth для session/UI state (`docs/architecture/state-management.md`), а `Esc`-обработчик в `AcpWorkbenchShortcuts` уже привязан к кубиту, а не к локальному widget state.
- **Рендер палитры — `Overlay`/условный виджет поверх `AcpWorkbenchLayout` в `workbench_shell.dart`**, а не отдельный route: в приложении нет роутинга (единственный экран), поэтому палитра — модальный слой, а не push route.
- **Команды с реальной опорой маппятся на существующий публичный метод кубита**: `/new` → `createSession()`, `/reconnect` → `reconnect()`, `/logs` → делает видимым `AcpDebugLogPanel` (снимает `Offstage` инспектора, если layout узкий).
- **`/plan`, `/permissions`, `/compact` помечаются как `AcpCommandAction` с `isAvailable: false`** (или аналогичным явным флагом) — палитра показывает их неактивными/с пометкой "coming soon" вместо выполнения и вместо скрытия. Скрывать их из списка нельзя: спека требует, чтобы палитра "presents core actions such as ... /plan, /permissions, ... /compact ...", то есть они обязаны быть видны как часть набора команд — просто честно как ещё не реализованные, а не имитировать выполнение.
- **Закрытие по выбору команды** — синхронно в том же методе, что выполняет действие (для `/new`, `/reconnect`, `/logs`); для недоступных команд палитра не закрывается автоматически, чтобы не создавать впечатление, что действие произошло.

## Risks / Trade-offs

- [Пользователь может продолжать считать `/plan`/`/permissions`/`/compact` "почти готовыми", раз они видны в палитре] → явная надпись "coming soon"/disabled-стиль вместо просто серого текста, плюс отдельные будущие changes на каждую из трёх фич, на которые можно сослаться из UI-подсказки при необходимости.
- [Overlay поверх `AcpWorkbenchLayout` может конфликтовать с существующими `CallbackShortcuts` из `AcpWorkbenchShortcuts`, если фокус не передаётся палитре] → добавить widget-тест, что после открытия палитры `Esc` закрывает именно её, а не триггерит `onCancel` шелла.
