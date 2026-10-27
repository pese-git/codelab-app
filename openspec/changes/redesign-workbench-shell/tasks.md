## 1. Основа раскладки

- [ ] 1.1 Спайк: проверить на текущей версии `fluent_ui`, что `NavigationView` не подходит как каркас (владение `body`, пороги 640/1008), и снять метрики `NavigationPaneTheme` для своего сайдбара; итог записать в design D3
- [ ] 1.2 `CodeLabLayoutClass { phone, narrow, medium, wide }` и `CodeLabLayoutClass.of(windowWidth)` в `codelab_ui`; тесты порогов 640/641/899/900/1279/1280
- [ ] 1.3 `CodeLabWorkbenchLayout` перевести на класс по ширине окна и слоты app bar / сайдбар / панель сессии / док; стабильные `GlobalKey` ленты и композера (MOB-3); убрать пороги 720/1100 и слот инспектора

## 2. Организмы codelab_ui

- [ ] 2.1 `CodeLabAppBar`: заголовок, кнопка-поле «Search or run a command» с подсказкой сочетания, переключатели панелей (`ToggleButton`), бейдж соединения со статусами и Retry/Connect; превью и widget-тесты
- [ ] 2.2 Переписать `CodeLabSessionSidebar`: New session, фильтр, группы проектов (`Expander`), строки сессий со статусами и Load more, Open folder…, Settings; режимы `open`/`compact`; превью и widget-тесты
- [ ] 2.3 `ToolPane` и `CodeLabToolDock`: вкладки с крестиком, активная вкладка, колонка с `CodeLabResizeHandle` (280–560 px) или выдвижная панель (Esc, клик мимо); превью и widget-тесты
- [ ] 2.4 `CodeLabSessionPaneHeader`: название, чип проекта с подсказкой полного пути, чип режима; превью и widget-тест
- [ ] 2.5 Удалить `CodeLabProjectPicker` и его превью/тесты

## 3. Состояние в desktop

- [ ] 3.1 `LayoutCubit`: `sidebarCollapsed`, `openPanes`, `activePane`, `dockWidth`, `dockOpenInOverlay` с методами переключения; unit-тесты переходов
- [ ] 3.2 Хранилище дока в `shared_preferences` (`codelab.dock.*`) по образцу `SharedPreferencesRecentProjectsStore`; чтение при старте, запись при изменении; тест перезапуска на моке `SharedPreferences`
- [ ] 3.3 Маппинг для сайдбара: группы проектов из `SessionsState` и `RecentProjectsStore`, фильтр по названию; раскрытие группы вызывает `selectProject`; тесты маппера
- [ ] 3.4 Маппинг бейджа соединения и шапки сессии (имя папки из `cwd`, режим из config options); тесты маппера

## 4. Сборка каркаса

- [ ] 4.1 `workbench_shell.dart`: собрать `CodeLabAppBar`, новый сайдбар, панель сессии и док; удалить `command_bar.dart`
- [ ] 4.2 Панель сессии: `CodeLabSessionPaneHeader` вместо `CurrentSessionPanel`, лента, баннер соединения, activity bar и композер без изменений поведения
- [ ] 4.3 Панель Plan — полный `CodeLabProgressChecklist`; панель Protocol — разделы протокола (бывший `InspectorPane`) и debug log (бывший `DebugLogPane`, с Expand)
- [ ] 4.4 Сочетания Cmd/Ctrl+N (новая сессия) и Cmd/Ctrl+B (сайдбар); `/logs` в палитре открывает панель Protocol; поле поиска в app bar открывает палитру
- [ ] 4.5 «Settings» внизу сайдбара открывает существующий диалог подключения

## 5. Тесты и перенос существующих проверок

- [ ] 5.1 Widget-тесты сценариев спецификации: зоны при 1440 px, пороги классов, док колонкой только при ≥ 1280, сохранение текста композера и прокрутки при 1440 → 820 → 1440 (MOB-3), Cmd/Ctrl+N, Cmd/Ctrl+B
- [ ] 5.2 Перевести widget- и e2e-тесты с ключей `acp-workbench-inspector-pane`, `WorkbenchCommandBar`, `CodeLabProjectPicker`, карточки Debug log на ключи A13 шаг 8 (`tool-pane-<pane>`, `tool-toggle-<pane>`, `sidebar-project-<project>`)
- [ ] 5.3 Размеры из плана проверки: 390×844, 820×1180, 1180×820, 1440×900 — без переполнения, композер и отмена видны

## 6. Проверка

- [ ] 6.1 `fvm dart format`, `fvm exec melos analyze`
- [ ] 6.2 `fvm exec melos run check` (интеграционные тесты — только Dart VM, §21)
- [ ] 6.3 Ручная проверка сборки macOS при 1440, 1100 и 820 px со скриншотами; сравнение с артбордами Main и Turn в отчёте сверки
- [ ] 6.4 `openspec validate redesign-workbench-shell --strict`
