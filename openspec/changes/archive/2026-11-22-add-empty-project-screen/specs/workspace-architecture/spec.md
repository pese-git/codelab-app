## ADDED Requirements

### Requirement: Плагин перетаскивания из ОС только в адаптере платформы
В `apps/codelab_desktop/lib` импорт `package:desktop_drop/` SHALL быть разрешён только файлу `core/platform/os_drop_region.dart` (адаптер `OsDropRegion`). Остальной код app получает от него список путей и колбэки входа и выхода перетаскивания. Типы плагина (`DropTarget`, `DropDoneDetails`, `XFile` плагина) за пределы адаптера НЕ SHALL выходить (AGENTS.md §11, `platform-integration.md` §8, §37; design.md change `add-empty-project-screen`, D3). Нарушение SHALL ловить сторож `codelab_architecture_tests` (`melos run guard`) правилом в `test/support/rules.dart`. `packages/flutter/codelab_ui` от плагина НЕ SHALL зависеть.

#### Scenario: Плагин в виджете рабочего места
- **WHEN** файл `apps/codelab_desktop/lib/features/workbench/presentation/widgets/open_project_screen.dart` импортирует `package:desktop_drop/desktop_drop.dart`
- **THEN** `melos run guard` сообщает нарушение и называет файл и импорт

#### Scenario: Плагин в адаптере
- **WHEN** импорт `package:desktop_drop/desktop_drop.dart` есть только в `apps/codelab_desktop/lib/core/platform/os_drop_region.dart`
- **THEN** `melos run guard` нарушений этого правила не находит
