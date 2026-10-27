## Why

Сверка с артбордами Claude Design от 27 октября 2026 года (Main, Turn, States) показала, что каркас окна codelab_desktop не совпадает с макетом. Фаза 1 и этап 5 закрыли дефекты и состояния, но сам каркас остался прежним:

- шапка с путём к бинарю агента;
- выпадающий список проектов над плоским списком сессий;
- постоянные колонки Inspector и Debug log;
- пороги раскладки 720 и 1100 px, не совпадающие с документами.

Каркас макета описан в `dart-agent-and-clients` §12.3 A13, шаг 0: app bar, сайдбар сессий по проектам, панель сессии и док панелей инструментов справа. Классы раскладки по ширине окна — в §12.8.3. Change `add-file-preview-and-tree` и `add-integrated-terminal` уже рассчитывают на док инструментов, которого нет. Каркас нужно заложить до того, как этап 7 принесёт новые панели.

## What Changes

- **Классы раскладки по ширине окна** (§12.8.3): телефон < 641, узкий 641–899, средний 900–1279, широкий ≥ 1280. Они заменяют пороги 720 / 1100 в `CodeLabWorkbenchLayout`.
  - Реализуются широкий, средний и узкий классы.
  - Класс «телефон» пока раскладывается как узкий; отдельные экраны телефона — этап 10.
  - Смена класса не теряет текст композера и позицию прокрутки ленты (MOB-3).
- **App bar** вместо `WorkbenchCommandBar`:
  - поле «Search or run a command», открывающее палитру по клику и Cmd/Ctrl+K;
  - переключатели панелей дока;
  - бейдж соединения: статус, при потере или ошибке — Reconnect;
  - путь к бинарю агента и кнопка Connect при активном соединении из шапки уходят.
- **Сайдбар сессий в стиле `NavigationView`:**
  - New session (Cmd/Ctrl+N);
  - фильтр сессий по названию;
  - группа текущего проекта с его сессиями и статусами;
  - недавние проекты свёрнутыми группами — выбор переключает проект;
  - «Open folder…» и Settings внизу;
  - сворачивание по Cmd/Ctrl+B.

  Выпадающий список `CodeLabProjectPicker` удаляется.
- **Док панелей инструментов `CodeLabToolDock`** вместо колонок Inspector и Debug log:
  - вкладки открытых панелей, каждая закрывается крестиком;
  - первые панели — Plan (полный чек-лист) и Protocol (бывший Inspector и Debug log);
  - при ширине ≥ 1280 док стоит колонкой с перетаскиваемой границей, уже — выдвигается поверх ленты;
  - набор открытых панелей и ширина хранятся в `shared_preferences`.
- **Шапка панели сессии:** название, чип проекта, режим. Rename, Fork и Split — не здесь (см. Non-Goals в design).
- **BREAKING (UI):** удаляются `CodeLabProjectPicker`, `WorkbenchCommandBar`, постоянная колонка Inspector и отдельная карточка Debug log. Их функции переходят в сайдбар, app bar и док.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-workbench-ui`:
  - заменяется требование «Layout workbench»;
  - «Границы панелей перетаскиваются мышью» относится к сайдбару и доку;
  - «Debug log — отдельная докнутая панель» становится панелью Protocol дока;
  - «"Open Project" offers native browse and recent projects» переходит в сайдбар;
  - в «Клавиатурный десктопный UX» добавляются Cmd/Ctrl+N и Cmd/Ctrl+B;
  - новые требования: классы раскладки по ширине, app bar с бейджем соединения, сайдбар по проектам, док панелей, шапка панели сессии.

## Impact

- **`packages/flutter/codelab_ui`:**
  - новые организмы `CodeLabAppBar`, `CodeLabToolDock`, `CodeLabSessionPaneHeader`;
  - `CodeLabSessionSidebar` переписан под группы по проектам;
  - `CodeLabWorkbenchLayout` — классы по ширине и док вместо инспектора;
  - удаляется `CodeLabProjectPicker`;
  - новые превью и widget-тесты.
- **`apps/codelab_desktop`:**
  - `LayoutCubit` получает состояние сайдбара и дока с сохранением в `shared_preferences`;
  - `workbench_shell.dart` и `main_pane.dart` собирают новый каркас;
  - `inspector_pane.dart` и `debug_log_pane.dart` становятся содержимым панели Protocol;
  - `command_bar.dart` удаляется;
  - сочетания Cmd/Ctrl+N и Cmd/Ctrl+B.
- **`codelab_client_core`:** `ConfigOptionView` получает `category` из ACP (`SessionConfigOption.category`), чтобы шапка сессии нашла опцию режима без угадывания по `id` (design D7).
- **Не затронуты:** `codelab_client_acp`, протокол ACP.
- **Зависимости:** новых нет, только `fluent_ui`.
- **Следующие change встраиваются в этот док:** `add-file-preview-and-tree` (панель Files) и `add-integrated-terminal` (панель Terminal).
