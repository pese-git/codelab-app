## Why

`agent-workbench-ui` уже требует command palette / slash-команды (`/new`, `/plan`, `/permissions`, `/logs`, `/compact`, `/reconnect`), доступные по клавиатурному шорткату (см. `openspec/changes/define-codelab-mvp/specs/agent-workbench-ui/spec.md`, Requirement "Keyboard-first desktop UX" и "Agent workbench interaction patterns"). UI-организм `AcpCommandPaletteSurface` для этого полностью реализован в `packages/flutter/acp_ui`, а шорткат `Ctrl/Cmd+K` привязан в `AcpWorkbenchShortcuts`. Но `CodeLabShellCubit.openCommandPalette()` (`apps/codelab_app/lib/features/workbench/application/shell_cubit.dart:697-698`) — заглушка, которая только пишет диагностическую строку и не открывает палитру. Пользователь нажимает документированный шорткат — ничего не происходит, без объяснения. Это расхождение было найдено при верификации `define-codelab-mvp` (задача 6.8 отмечена выполненной, но код не соответствует требованию) и снято с чек-листа этого change.

## What Changes

- `CodeLabShellCubit.openCommandPalette()` реально показывает `AcpCommandPaletteSurface` поверх workbench вместо no-op заглушки; палитра закрывается по `Esc` или после выбора команды.
- Все шесть команд (`/new`, `/plan`, `/permissions`, `/logs`, `/compact`, `/reconnect`) видны и выбираемы в палитре (сценарий "CodeLab presents core actions..." из `agent-workbench-ui`).
- Команды с уже существующей опорой в кубите выполняют реальное действие: `/new` → `createSession()`, `/reconnect` → `reconnect()`, `/logs` → делает видимым `AcpDebugLogPanel` в инспекторе (в узком layout, где инспектор скрыт `Offstage`, — временно раскрывает его).
- **Важное уточнение по факту проверки кода**: в `CodeLabShellState`/`CodeLabShellCubit` нет ни permission-mode selector, ни plan-mode, ни compact-transcript механизма — это не "не подключено", а отсутствует как фича целиком. Реализовывать их с нуля внутри этого change означало бы протащить три отдельные крупные фичи под видом "подключить палитру", что нарушает scope discipline (`AGENTS.md` §19). Поэтому `/plan`, `/permissions`, `/compact` в этом change: видны в палитре, но при выборе показывают явное состояние "недоступно, скоро" — **не** тихий no-op (это тот же анти-паттерн fake-интерактивности, который и стал причиной этого change, только теперь честно обозначенный, а не замаскированный под "готово"). Полная реализация каждой из трёх фич выносится в отдельные будущие OpenSpec changes.
- Поиск/фильтрация команд по названию — уже поддержана `AcpCommandAction.filter()`, переиспользуется без изменений.
- **Палитра дополнительно показывает команды, объявленные самим агентом.** `packages/dart/acp_protocol` уже моделирует `SessionUpdate.availableCommandsUpdate(availableCommands: List<AvailableCommand>)` (`session_update.dart:196`) — агент сообщает клиенту список доступных ему slash-команд (имя, описание, опциональный hint аргумента). Сейчас это обрабатывается только как debug-запись в инспекторе (`shell_cubit.dart:1111-1117`, "N commands") — ни в палитру, ни куда-либо ещё эти данные не попадают. Шесть client-native команд (`/new`, `/plan`, `/permissions`, `/logs`, `/compact`, `/reconnect`) остаются обязательными по `define-codelab-mvp` — они не заменяются агентскими, а дополняются: палитра показывает оба набора одновременно, визуально разделёнными (например, секцией/подписью "From agent"), чтобы не путать client-native действия с тем, что предложил конкретный агент.
- Выбор агентской команды **не выполняется как RPC** — у `AvailableCommand` нет отдельного метода "invoke" в протоколе, только объявление. Выбор вставляет `/name ` (плюс `input.hint`, если есть, как подсказку) в текст композера и закрывает палитру — пользователь дописывает аргументы и отправляет как обычный prompt через `session/prompt`, агент сам разбирает текст. Это отличается от `/new`/`/reconnect`/`/logs`, которые выполняют локальное действие клиента напрямую.
- **Второй триггер палитры — inline, из поля ввода промпта.** Если пользователь вводит `/` как первый символ нового слова (в начале поля или сразу после пробела/переноса строки) в `AcpPromptComposer`, CodeLab открывает ту же палитру, привязанную по позиции к композеру (не по центру экрана, как при `Ctrl/Cmd+K`), с фильтрацией по тексту, набираемому после `/`, — без переключения фокуса на отдельное поле поиска палитры: пользователь продолжает печатать в самом композере, список фильтруется вживую.
- Добавляются widget-тесты на открытие/закрытие палитры и на поведение каждой команды (включая "недоступно" state для трёх незавершённых), по аналогии с существующим покрытием reconnect в `apps/codelab_app/test/widget_test.dart`.

## Capabilities

### New Capabilities

_(нет — command palette уже описан в `agent-workbench-ui`)_

### Modified Capabilities

- `agent-workbench-ui`: требование "Agent workbench interaction patterns" и сценарий "User opens command palette" сейчас специфицированы, но не реализованы в `apps/codelab_app`; эта delta-спека уточняет наблюдаемое поведение (что именно происходит при выборе каждой команды), не меняя сам текст требования из `define-codelab-mvp`. Дополнительно добавляется новое ADDED Requirement про рендер `AvailableCommand` от агента — `define-codelab-mvp` этого не описывал (протокольные данные `SessionUpdate.availableCommandsUpdate` уже существовали в `acp_protocol`, но ни одна спека не требовала их показывать пользователю).

## Impact

- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — реализация `openCommandPalette()` и обработчиков команд.
- `apps/codelab_app/lib/features/workbench/presentation/workbench_shell.dart` — отображение `AcpCommandPaletteSurface` в дереве виджетов при активном состоянии палитры (по центру для `Ctrl/Cmd+K`, `Positioned` над композером для inline-триггера).
- `apps/codelab_app/lib/features/workbench/presentation/widgets/` — детектирование "`/` в начале слова" в композере, обработка `↑`/`↓`/`Enter` в inline-режиме.
- `apps/codelab_app/test/widget_test.dart` — новые тесты.
- `packages/flutter/acp_ui/lib/src/organisms/acp_command_palette_surface.dart` — новый опциональный параметр для inline-режима (`showSearchField`/`queryOverride`), остальная логика не меняется.
- `packages/flutter/acp_ui/lib/src/molecules/acp_command_action.dart` — `AcpCommandAction` получает поле для различения client-native/agent-sourced команд (используется для визуального разделения секций).
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — `AvailableCommandsUpdate` из `_inspectorEntryForUpdate` (или соседний обработчик `session/update`) дополнительно маппится в список `AcpCommandAction` в `CodeLabShellState`, заменяется целиком при каждом новом `availableCommandsUpdate` (аналогично `PlanEntry`/`add-plan-progress-checklist`), очищается при смене/потере активной сессии.
