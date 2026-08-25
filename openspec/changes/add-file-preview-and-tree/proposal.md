## Why

Верификация UX/UI и сверка с референсами (Zed) выявили два связанных пробела:

1. У инспектора/транскрипта есть карточки tool call (`read_file`, `edit_file` и т.п.) с указанием файла, но нет способа посмотреть его содержимое, не выходя из CodeLab — только сырые обрезанные `rawOutput`/`rawInput` в инспекторе (до 8 строк, `inspector_pane.dart:224`).
2. У CodeLab нет вообще никакого способа обзора файловой структуры проекта — только строка текущего пути (`WorkingDirectoryProvider.currentPath`, `working_directory_provider.dart`), без listing.

Оба пробела закрываются одной UI-сущностью — read-only панелью просмотра файла — с двумя точками входа: клик по tool call (контент уже есть у агента) и клик по узлу в дереве каталогов (CodeLab читает файл сам). Это первый случай, когда CodeLab получает прямой доступ к файловой системе для отображения — раньше единственный принцип был "показываем только то, что вернул агент"; это решение сознательно его расширяет для дерева/превью, но не создаёт возможности редактирования.

## What Changes

- Добавляется read-only **File Preview** — панель поверх workbench (по паттерну уже принятых `EditProfileDialog`/`CommandPalette`: overlay, не route), показывающая содержимое файла с номерами строк, подсветкой конкретной строки/диапазона (если известен `ToolCallLocation`), и явной пометкой источника: "from agent's tool call" либо "read directly from disk".
- Точка входа 1: иконка предпросмотра рядом с tool call карточками в транскрипте/инспекторе — контент берётся из уже полученного `ContentBlock` (протокол это уже поддерживает, `packages/dart/acp_protocol/lib/src/acp/prompt.dart:100-140`, новых зависимостей не требует).
- Добавляется вкладка **"Files"** рядом с "Sessions" в левой панели (`AcpSessionSidebar`/`WorkbenchCommandBar`-соседний виджет) — переключает содержимое панели на дерево каталогов текущего working directory. Не отдельный слот в `AcpWorkbenchLayout` — swap контента существующего слота.
- Дерево — ленивое (раскрытие по запросу, не eager recursive), с базовой фильтрацией шумных директорий (`.git`, `.dart_tool`, `build`, `node_modules` и т.п.) для MVP.
- Клик по файлу в дереве открывает тот же File Preview, вариант "read directly from disk" — новое, ранее не существовавшее чтение файловой системы приложением.
- Toggle "Following" в панели превью — держит панель синхронизированной с последним `ToolCallLocation` активной сессии (актуально только для варианта "from tool call").
- **BREAKING**: нет. Contracts ACP не меняются.

## Capabilities

### New Capabilities

- `workspace-file-browser`: read-only просмотр содержимого файла (из tool call или напрямую с диска) и ленивое дерево каталогов рабочей директории.

### Modified Capabilities

_(нет — `agent-workbench-ui` не трогаем текстово, новая capability самодостаточна)_

## Impact

- `apps/codelab_app/lib/core/platform/` — новый reader для directory listing (`Directory.list()`, ленивый, с игнор-листом) и file read, за infrastructure-boundary (presentation не трогает `dart:io` напрямую, `AGENTS.md` §11).
- `packages/flutter/acp_ui/lib/src/organisms/` — новый `AcpFilePreviewPanel` (переиспользуется для обоих источников) и `AcpDirectoryTree`.
- `apps/codelab_app/lib/features/workbench/presentation/widgets/` — вкладка Sessions/Files, точка входа предпросмотра у tool call карточек в inspector/main pane.
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — команды открытия/закрытия preview, состояние выбранного узла дерева (ephemeral UI state — см. design.md по аналогии с решением для command palette/dialog).
- `apps/codelab_app/test/widget_test.dart` — тесты на оба источника preview и на дерево.
