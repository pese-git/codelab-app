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

- [x] 5.1 В `apps/codelab_app/lib/features/workbench/presentation/widgets/inspector_pane.dart` убрать `SizedBox(height: 260, child: AcpDebugLogPanel(...))` из `ListView`; `WorkbenchInspectorPane` продолжает рендерить только `state.inspectorEntries` (Decision 2). Заодно убран орфанный заголовочный "Clear diagnostics" `AcpIconButton`, который относился к удаляемой панели, а не к содержимому Inspector'а
- [x] 5.2 Создать `apps/codelab_app/lib/features/workbench/presentation/widgets/debug_log_pane.dart` — `WorkbenchDebugLogPane`: собственный `DecoratedBox`/заголовок "Debug log" + кнопка "Expand"; тело — `structured_log_fluent`'s embeddable `FluentLogViewer` as-is (поиск/уровень/категория/pause/clear — из пакета, см. §11.3)
- [x] 5.3 В `workbench_shell.dart` (родительский layout) добавить `WorkbenchDebugLogPane` как sibling `WorkbenchInspectorPane` внутри `Column` в `inspectorPane:`-слоте `_ResizableWorkbenchLayout` — обе панели видны одновременно без вложенности
- [x] 5.4 Обновить `apps/codelab_app/test/widget_test.dart` — базовый smoke-тест теперь проверяет `find.byType(WorkbenchDebugLogPane)`/`find.text('Debug log')` отдельно от Inspector'а

## 6. Полноэкранный log viewer

- [x] 6.1 Реализовать `DebugLogViewerDialog` (`apps/codelab_app/lib/features/workbench/presentation/widgets/debug_log_viewer_dialog.dart`) — обёртка вокруг `FluentLogViewerPage`, открываемая через fluent_ui's `showDialog` (сам пушит route → `Navigator.canPop` истинен → `FluentLogViewerPage` сам рисует back-button; `showDialog`'s дефолты `dismissWithEsc: true`/тёмный `barrierColor` закрывают требования Esc/затемнения без дополнительного кода), без потери state workbench под ним
- [x] 6.2 Detail-панель (`LogEntryDetailPane`, из `structured_log_fluent`, переиспользуется как есть) показывает весь контекст записи как key/value, включая `component`/`category`/`connection_generation`/`session_id`/`request_id`/`tool_call_id`, когда они присутствуют
- [x] 6.3 Единая точка открытия — `DebugLogViewerDialog.show(context, logBuffer)`, вызываемая и из `WorkbenchDebugLogPane.onExpand`, и из `selectPaletteCommand`'s `/logs`-ветки (не два независимых пути, Decision 4)

## 7. Командная палитра `/logs`

- [x] 7.1 `selectPaletteCommand` (`workbench_shell.dart`) теперь принимает `BuildContext` и для `action.id == 'logs'` вызывает `DebugLogViewerDialog.show` в дополнение к существующему `cubit.selectCommand(action)` (который по-прежнему поднимает Inspector на narrow-layout — не связанная с логированием, существовавшая ранее функциональность, намеренно не тронута)
- [x] 7.2 Обновлён/переименован widget-тест "selecting /logs opens the full-screen log viewer" — проверяет открытие `DebugLogViewerDialog`/`FluentLogViewerPage` и закрытие по `Esc` без изменения state workbench

## 8. Секреты и маскирование в viewer'е

- [x] 8.1 Маскирование гарантировано архитектурно: `secretRedactionProcessor` — единственный processor для ВСЕЙ `StructlogConfiguration` (не per-sink), поэтому применяется к каждой записи до попадания в любой sink, включая `LogBuffer`; regression-покрытие уже существует в `packages/dart/acp_client_core/test/structured_logging_test.dart` ("masks secrets in structured log output") и не дублируется отдельным UI-тестом (см. spec.md сценарий "Секреты замаскированы...", который явно ссылается на существующее правило, не заводит новое)

## 9. Финальная проверка

- [ ] 9.1 `melos format`
- [ ] 9.2 `melos analyze`
- [ ] 9.3 `melos test`
- [ ] 9.4 Ручной прогон `fvm flutter run -d macos` из `apps/codelab_app`: проверить, что Inspector и Debug log — видимые sibling-панели, докнутая панель фильтрует/ищет (в том числе category-селектор после §11), кнопка Expand и команда `/logs` открывают один и тот же полноэкранный viewer, закрытие не теряет state workbench
- [ ] 9.5 `openspec validate replace-debug-log-panel-with-fluent --strict`

## 10. Protocol-trace в in-app viewer'е — первая итерация, toggle-based (СУПЕРСЕДЕНА §11)

Пользователь запросил видеть `protocol.log`-события в Debug Log "аналогичным образом" (тем же viewer'ом), а не только в файле — реверсирует изначальный Non-Goal design.md (см. design.md Decision 5). **Эта итерация (toggle) заменена §11 (category-селектор) по прямому запросу пользователя сразу после реализации** — оставлено как история решения, код toggle'а в репозитории больше не существует.

- [x] 10.1 ~~`configureCodeLabLogging()`: условный `inAppViewerProtocolTraceSinkName` sink~~ — заменён безусловным единым sink'ом, см. 11.1
- [x] 10.2 ~~`setProtocolTracingEnabled(bool)` переключает оба protocol-sink'а~~ — in-app viewer больше не гейтится этой функцией, см. 11.1
- [x] 10.3 Тест в `structured_logging_test.dart`, подтвердивший toggle-поведение — переписан под always-capture, см. 11.2
- [x] 10.4 ~~`WorkbenchDebugLogPane`: `ToggleSwitch` "Protocol"~~ — удалён, см. 11.3
- [x] 10.5 design.md/spec.md для toggle-варианта — переписаны под итоговый вариант, см. 11.4
- [x] 10.6 ~~Widget-тест на тап по "Protocol"~~ — заменён тестом на category-селектор, см. 11.5

## 11. Protocol-trace в in-app viewer'е — итоговая версия: always-capture + category-селектор (по запросу пользователя)

Пользователь предложил заменить toggle на "селектор по типу (SinkName?)" — реализовано поверх уже существующей инфраструктуры `LogViewerController.categoryFilter`, которой не хватало готового UI. Заодно отправлено ТЗ автору `structured_log_fluent` (пользователю) на generic-версию такого селектора для самого пакета — принято и опубликовано как `LogCategoryComboBox` в `0.1.0-dev.3`, вместе с новым embeddable-виджетом `FluentLogViewer` (`0.1.0-dev.3`/`.4`), на который в итоге полностью перешла докнутая панель.

- [x] 11.1 `configureCodeLabLogging()`: `debug-panel`-sink принимает ОБЕ категории безусловно (`categories: {applicationLogCategory, protocolTraceLogCategory}`, `minLevel: LogLevel.trace`, без своего `enabled`) — файловый `protocol`-sink остаётся отдельным, со своим независимым `enabled`/`setProtocolTracingEnabled`/`isProtocolTracingEnabled`
- [x] 11.2 Тест в `structured_logging_test.dart`: in-app viewer получает обе категории всегда, независимо от состояния файлового sink'а
- [x] 11.3 Зависимости подняты до `structured_log_flutter: 0.1.0-dev.3`, `structured_log_fluent: 0.1.0-dev.4`; `WorkbenchDebugLogPane` переписан — весь toolbar/список/пустое состояние делегированы `FluentLogViewer` (embeddable-виджет пакета), собственный код панели сведён к заголовку ("Debug log" + кнопка "Expand")
- [x] 11.4 design.md (Decisions 3-5) и spec.md (сценарий "Селектор типа фильтрует записи по категории, когда их несколько") переписаны под итоговое поведение; `openspec validate` проходит
- [x] 11.5 Widget-тест: `LogCategoryComboBox` скрыт при одной категории, появляется и содержит "All types" после того как в буфере оказались обе категории (`application`+`protocol`)
