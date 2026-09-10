## 1. Сверка реального API пакетов

- [x] 1.1 Прочитать реальный исходник `structured_log_flutter` (`pese-git/structured_log` на GitHub — монорепозиторий, `structured_log_flutter`/`structured_log_fluent` публикуются из него, ветка `develop`, версия `0.1.0-dev.2`): точные конструкторы/API `LogBuffer` (capacity, `capture`/output-совместимость, `ValueListenable`-интерфейс) и `LogViewerController` (фильтры по level/category/search, pause, clear)
- [x] 1.2 Прочитать реальный исходник `structured_log_fluent` (тот же репозиторий, `0.1.0-dev.2`): точные конструкторы/параметры `FluentLogViewerPage`, `LogEntryTile`, `LogEntryDetailPane`, `LogViewerEmptyState` — обязательные параметры, поддержка embedding/кастомной ширины, светлая/тёмная тема
- [x] 1.3 Зафиксировать в design.md (Open Questions → снять или уточнить) фактические расхождения с предположениями design.md, если найдены; при расхождении — скорректировать план разделов 4-6 ниже до начала реализации

## 2. Зависимости и расширение logging-инфраструктуры

- [x] 2.1 Добавить `structured_log_flutter` и `structured_log_fluent` в `apps/codelab_app/pubspec.yaml` (не в `packages/flutter/acp_ui/pubspec.yaml` — Decision 1)
- [x] 2.2 Выполнить `melos bootstrap`
- [x] 2.3 Добавить опциональный параметр `inAppViewerOutput` в `configureCodeLabLogging()` (`packages/dart/acp_client_core/lib/src/infrastructure/structured_log_logger.dart`) и третий `LogSink` (`name: 'debug-panel'`, `categories: {applicationLogCategory}`) — по образцу Decision 3 design.md, без изменения контракта двух существующих sink'ов
- [x] 2.4 Обновить/добавить тесты в `packages/dart/acp_client_core/test/structured_logging_test.dart`: новый sink получает те же `application`-события, что и `application`-sink, и не получает `protocol`-события

## 3. Wiring `LogBuffer` в `codelab_app`

- [x] 3.1 В `CodeLabLoggingModule` (`apps/codelab_app/lib/app/app_scope.dart`) создать один `LogBuffer` (bounded ring buffer, независимый лимит от `_maxDiagnostics=500`), передать `buffer.capture` как `inAppViewerOutput` в `configureCodeLabLogging()`
- [x] 3.2 Забиндить `LogBuffer` в CherryPick-scope как singleton (`CodeLabDependencies.logBuffer`) — единый источник данных для докнутой панели и полноэкранного viewer'а; **уточнение к первоначальной формулировке** (см. design.md Decision 4, скорректирован после сверки реального API §1): не единый `LogViewerController`, а два независимых `LogViewerController` instance, каждый со своим фильтром/pause-состоянием, оба построены поверх этого общего `LogBuffer` — создаются на месте потребления (§5.2, §6), а не биндятся в DI
- [x] 3.3 Добавить/обновить тест в `apps/codelab_app/test/app_scope_logging_test.dart`, проверяющий, что `LogBuffer` резолвится из scope и что событие, залогированное через `Logger`, попадает в него

## 4. Удаление `AcpDebugLogPanel`/`AcpDebugLogEntry` из `acp_ui`

- [x] 4.1 Удалить `packages/flutter/acp_ui/lib/src/organisms/acp_debug_log_panel.dart` и его экспорт из `acp_ui.dart` (через `organisms.dart`)
- [x] 4.2 Убрать usage/preview из `packages/flutter/acp_ui/lib/src/organisms/acp_organism_previews.dart` и её вызов в `test/acp_previews_test.dart`
- [x] 4.3 Убрать/обновить тесты в `packages/flutter/acp_ui/test/acp_organisms_test.dart`, ссылающиеся на `AcpDebugLogPanel`
- [x] 4.4 Прогнать `dart analyze`/`flutter test` для `acp_ui` — 81/81 тестов проходят, пакет собирается без ссылок на удалённый organism

## 5. Разделение `WorkbenchInspectorPane` на два sibling-виджета

- [ ] 5.1 В `apps/codelab_app/lib/features/workbench/presentation/widgets/inspector_pane.dart` убрать `SizedBox(height: 260, child: AcpDebugLogPanel(...))` из `ListView`; `WorkbenchInspectorPane` продолжает рендерить только `state.inspectorEntries` (Decision 2)
- [ ] 5.2 Создать `apps/codelab_app/lib/features/workbench/presentation/widgets/debug_log_pane.dart` — `WorkbenchDebugLogPane`: собственный `DecoratedBox`/заголовок "Debug log", докнутая компактная панель на базе `LogEntryTile`/`LogViewerController` (см. §1), поле поиска, выбор минимального уровня, кнопка "Expand" в заголовке
- [ ] 5.3 В родительском layout workbench (там, где сегодня размещается `WorkbenchInspectorPane`) добавить `WorkbenchDebugLogPane` как sibling в `Column`/`Flex` с отступом — обе панели видны одновременно без вложенности
- [ ] 5.4 Обновить `apps/codelab_app/test/widget_test.dart:2256` (`expect(find.byType(AcpDebugLogPanel), ...)`) на проверку нового `WorkbenchDebugLogPane`

## 6. Полноэкранный log viewer

- [ ] 6.1 Реализовать обёртку вокруг `FluentLogViewerPage`, открываемую как overlay поверх притемнённого workbench (`showDialog`/аналог без добавления в navigation history — Decision 4), закрытие по кнопке и `Esc`, без потери state workbench под ним
- [ ] 6.2 Detail-панель выбранной записи показывает `component`/`category`/`connection_generation` и, где применимо, `session_id`/`request_id`/`tool_call_id` как key/value (спека "Полноэкранный log viewer — master-detail", сценарий про correlation-поля)
- [ ] 6.3 Завести единую точку открытия viewer'а (например, метод на `CodeLabShellCubit` или общий widget-level callback), вызываемую и из `/logs`, и из кнопки "Expand" `WorkbenchDebugLogPane` — не два независимых пути (Decision 4)

## 7. Командная палитра `/logs`

- [ ] 7.1 Обновить обработчик команды `/logs` (там, где сегодня реализовано её текущее поведение "raising panel inside inspector") — вызывать единую точку открытия из §6.3 вместо старого поведения
- [ ] 7.2 Обновить/добавить widget-тест на сценарий "Выбор /logs открывает полноэкранный log viewer" (spec.md, MODIFIED Requirement "Командная палитра...")

## 8. Секреты и маскирование в viewer'е

- [ ] 8.1 Убедиться (тестом), что записи, отображаемые в `WorkbenchDebugLogPane` и в полноэкранном viewer'е, уже прошли через `secretRedactionProcessor` (общий для `StructlogConfiguration`, Decision 3) — добавить явный regression-тест с секретоподобным полем, проверяющий маскирование и в списке, и в detail-панели полноэкранного viewer'а (spec.md, сценарий "Секреты замаскированы и в списке, и в detail-панели")

## 9. Финальная проверка

- [ ] 9.1 `melos format`
- [ ] 9.2 `melos analyze`
- [ ] 9.3 `melos test`
- [ ] 9.4 Ручной прогон `fvm flutter run -d macos` из `apps/codelab_app`: проверить, что Inspector и Debug log — видимые sibling-панели, докнутая панель фильтрует/ищет, кнопка Expand и команда `/logs` открывают один и тот же полноэкранный viewer, закрытие не теряет state workbench
- [ ] 9.5 `openspec validate replace-debug-log-panel-with-fluent --strict`
