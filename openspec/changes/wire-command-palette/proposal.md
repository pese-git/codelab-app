## Why

`agent-workbench-ui` уже требует command palette / slash-команды (`/new`, `/plan`, `/permissions`, `/logs`, `/compact`, `/reconnect`), доступные по клавиатурному шорткату (см. `openspec/changes/define-codelab-mvp/specs/agent-workbench-ui/spec.md`, Requirement "Keyboard-first desktop UX" и "Agent workbench interaction patterns"). UI-организм `AcpCommandPaletteSurface` для этого полностью реализован в `packages/flutter/acp_ui`, а шорткат `Ctrl/Cmd+K` привязан в `AcpWorkbenchShortcuts`. Но `CodeLabShellCubit.openCommandPalette()` (`apps/codelab_app/lib/features/workbench/application/shell_cubit.dart:697-698`) — заглушка, которая только пишет диагностическую строку и не открывает палитру. Пользователь нажимает документированный шорткат — ничего не происходит, без объяснения. Это расхождение было найдено при верификации `define-codelab-mvp` (задача 6.8 отмечена выполненной, но код не соответствует требованию) и снято с чек-листа этого change.

## What Changes

- `CodeLabShellCubit.openCommandPalette()` реально показывает `AcpCommandPaletteSurface` поверх workbench вместо no-op заглушки; палитра закрывается по `Esc` или после выбора команды.
- Все шесть команд (`/new`, `/plan`, `/permissions`, `/logs`, `/compact`, `/reconnect`) видны и выбираемы в палитре (сценарий "CodeLab presents core actions..." из `agent-workbench-ui`).
- Команды с уже существующей опорой в кубите выполняют реальное действие: `/new` → `createSession()`, `/reconnect` → `reconnect()`, `/logs` → делает видимым `AcpDebugLogPanel` в инспекторе (в узком layout, где инспектор скрыт `Offstage`, — временно раскрывает его).
- **Важное уточнение по факту проверки кода**: в `CodeLabShellState`/`CodeLabShellCubit` нет ни permission-mode selector, ни plan-mode, ни compact-transcript механизма — это не "не подключено", а отсутствует как фича целиком. Реализовывать их с нуля внутри этого change означало бы протащить три отдельные крупные фичи под видом "подключить палитру", что нарушает scope discipline (`AGENTS.md` §19). Поэтому `/plan`, `/permissions`, `/compact` в этом change: видны в палитре, но при выборе показывают явное состояние "недоступно, скоро" — **не** тихий no-op (это тот же анти-паттерн fake-интерактивности, который и стал причиной этого change, только теперь честно обозначенный, а не замаскированный под "готово"). Полная реализация каждой из трёх фич выносится в отдельные будущие OpenSpec changes.
- Поиск/фильтрация команд по названию — уже поддержана `AcpCommandAction.filter()`, переиспользуется без изменений.
- Добавляются widget-тесты на открытие/закрытие палитры и на поведение каждой команды (включая "недоступно" state для трёх незавершённых), по аналогии с существующим покрытием reconnect в `apps/codelab_app/test/widget_test.dart`.

## Capabilities

### New Capabilities

_(нет — command palette уже описан в `agent-workbench-ui`)_

### Modified Capabilities

- `agent-workbench-ui`: требование "Agent workbench interaction patterns" и сценарий "User opens command palette" сейчас специфицированы, но не реализованы в `apps/codelab_app`; эта delta-спека уточняет наблюдаемое поведение (что именно происходит при выборе каждой команды), не меняя сам текст требования из `define-codelab-mvp`.

## Impact

- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — реализация `openCommandPalette()` и обработчиков команд.
- `apps/codelab_app/lib/features/workbench/presentation/workbench_shell.dart` — отображение `AcpCommandPaletteSurface` в дереве виджетов при активном состоянии палитры.
- `apps/codelab_app/test/widget_test.dart` — новые тесты.
- `packages/flutter/acp_ui` не меняется — переиспользуется существующий `AcpCommandPaletteSurface`/`AcpCommandAction`.
