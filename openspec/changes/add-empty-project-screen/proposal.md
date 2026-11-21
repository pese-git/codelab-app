## Why

Change `require-project-folder` (архив 2026-11-12) сделал правило «без проекта нет агента» поведением: агент не стартует без папки, «New session» без проекта открывает выбор папки, восстановление проекта ждёт не дольше 2 с. Экран этого состояния остался временным: при `project == null` панель сессии показывает `CodeLabStartScreen` с одной строкой `Open a project to start a session.` и кнопкой «Open folder…». Пользователь не узнаёт, зачем нужна папка, какой агент стартует и когда. Бейдж соединения пишет `Disconnected`, хотя ничего не отключалось. В сайдбаре при пустом списке проектов нет ни строчки.

Холст Claude Design (экспорт 2026-11-22) задаёт кадр «11a Open project — first start, no project»: `docs/design/claude-design/ProjectsEmpty.dc.html` и `ProjectsEmpty-dark.dc.html`, строка 11a в `README.md` экспорта, заметка ряда «Открытие проекта» в `canvas.json` (R-22) и граф `NavProject.dc.html`. Кадр добавляет то, чего в сборке нет:

- объяснение, что даёт папка;
- карточку агента окна;
- подсказки сочетаний;
- приём папки перетаскиванием из файлового менеджера ОС.

## What Changes

- **Экран без проекта (кадр 11a).** Новый организм кита `CodeLabOpenProjectScreen` заменяет `CodeLabStartScreen` в ветке «проект не выбран» (D1, D2). Состав экрана:
  - иконка-герой, заголовок `Open a project` и пояснение. Фраза о границе папки показывается только для встроенного агента, где её обеспечивает `BoundedEnv`; для внешнего профиля текст другой (D6);
  - кнопка «Open folder…» с подсказкой Cmd/Ctrl+O;
  - зона перетаскивания `Drop a folder here to open it` / `Files are not accepted — only a folder`;
  - карточка агента окна: имя профиля, подпись транспорта (`in-process · profile of this window` для встроенного агента, своя подпись для stdio и WebSocket), `Starts when you open a folder. Nothing runs before that.` и ссылка `Change in Settings › Connection`;
  - InfoBar `New session needs a folder`.

  Экран с выбранным проектом (`CodeLabStartScreen` с «New session») не меняется.
- **Папка перетаскиванием — новое поведение** (D3–D5). Перетащенная на экран без проекта папка — то же намерение, что выбор папки в «Open folder…»:
  - она становится проектом, это триггер 1 старта агента профиля окна;
  - агент стартует в этой папке (с проверкой «папка есть»), затем `session/list`; `session/new` не отправляется.

  Файл, несколько элементов, исчезнувший путь и элемент без локального пути отклоняются. Отказ виден в зоне текстом причины, пишется в диагностику (`warning`, источник `project`) и событием журнала без пути. Что перед нами — папка или файл, решает application (`SettingsCubit`) через порт `LocalPathKindOf` из `lib/core/platform/`, а не виджет.
- **Новая зависимость app — `desktop_drop`** (D3). Она уже названа кандидатом в `12-3-desktop-display.md` (§12.3.6) для вложений D-12. Пакет принимает перетаскивание из ОС на macOS, Windows и Linux. Импорт разрешён только адаптеру `OsDropRegion` в `lib/core/platform/`, это проверяет правило сторожа. Перед добавлением задача 1.1 проверяет лицензию, платформы, нативную сборку и то, нет ли такого API в Flutter SDK 3.47. Результат записывается в `technology-stack.md` §20и.
- **Сочетание Cmd/Ctrl+O — «Open folder…»** (D7). Кадр показывает подсказку Ctrl+O у кнопки и в сайдбаре. Требование «Сочетания app и страница «Keyboard» не расходятся» запрещает подсказку без привязки. Поэтому change вводит запись каталога `CodeLabShortcut.openFolder`, привязку на рабочем месте (системный выбор папки, как «Open folder…» сайдбара) и строку `open-folder` на странице «Keyboard». Это меняет spec app-settings: в таблице 21 строка, и O больше нет в списке непривязанных клавиш.
- **Бейдж соединения без проекта** (D8). Пока проект не выбран и агент не запущен, бейдж пишет `No project · agent not started` с подсказкой `No project is selected, so no agent is running`, а не `Disconnected`.
- **Сайдбар** (D9). При пустом списке проектов группа «Projects» показывает `No recent projects yet.`. Пункт «Open folder…» с подсказкой сочетания стоит в конце списка проектов, как во всех кадрах ряда «Открытие проекта». «Settings» остаётся внизу. Узкий (компактный) сайдбар не меняется.
- **Тёмная тема** — по кадру `-dark`: цвета берутся только из `FluentTheme` и `CodeLabPalette`, своих цветов в ките нет (D10).
- **Локализация**: тексты в ARB `en` и `ru` (app) и в каталоге кита (`No recent projects yet.`). Подсказки клавиш строятся по каталогу `CodeLabShortcut` для платформы (D11).

### Для раздела выпуска `CHANGELOG.md`

- Окно без проекта объясняет, зачем нужна папка, и показывает, какой агент стартует при её открытии. Папку можно перетащить в окно из Finder, Проводника или файлового менеджера Linux. «Open folder…» открывается сочетанием Cmd/Ctrl+O.

## Не входит

- **Смартфон и планшет** (P22, T16 и их графы). Мобильных целей у app нет до этапа 10 (§12.8). Модель проекта там другая: «New project» — подпапка `Documents › CodeLab`, системного выбора папки нет.
- **Кадр 11 «Project picker»** — диалог со списком недавних проектов по Ctrl+O. Cmd/Ctrl+O в этом change открывает системный выбор папки, как «Open folder…» сайдбара. Диалог 11 — отдельный change (Q3).
- **Кадры 11b–11f** (старт агента в папке, «готов, сессий нет», «папки нет», второй проект). Их поведение уже реализовано change `require-project-folder`, вид не меняется.
- **Перетаскивание на рабочее место с выбранным проектом** и в композер. Вложения перетаскиванием — цель D-12; она переиспользует адаптер `OsDropRegion`, но остаётся отдельным change.
- **Перетаскивание в onboarding**: пока показан onboarding, рабочее место не строится (change `add-app-onboarding`, D5), и зоны нет.
- **Песочница macOS** (P-13, задача 9.11). App собирается без `com.apple.security.app-sandbox`. Если песочницу включат, приём перетаскивания пересматривается: нужны security-scoped URL (D3, риски).
- **ACP**: новых методов, полей и `_meta` нет. Порядок `session/list` и `session/new` не меняется.
- **Правило «Restart agent» без проекта, ожидание восстановления, onboarding-гейт** — без изменений.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-workbench-ui`:
  - ADDED «Экран без выбранного проекта», «Открытие папки перетаскиванием», «Cmd/Ctrl+O открывает выбор папки»;
  - MODIFIED «Project selection is independent of the connection type» и «Агент стартует сам» — в перечень явных выборов проекта (триггер 1) добавлена перетащенная папка;
  - MODIFIED «App bar with palette search and connection badge» — бейдж без проекта;
  - MODIFIED «Sessions sidebar grouped by project» — пустой список проектов, место «Open folder…» и подсказка сочетания.
  - MODIFIED «Empty session after connecting» — без проекта панель показывает экран «Экран без выбранного проекта», текст `Open a project to start a session.` уходит; шапка без сессии в фокусе — без подписи (D11).
- `app-settings` — MODIFIED «Страница «Keyboard»: строки таблицы»: строка `open-folder`, 21 строка, Cmd/Ctrl+O убран из списка непривязанных.
- `workspace-architecture` — ADDED «Плагин перетаскивания из ОС только в адаптере платформы» (правило сторожа).

## Impact

- **Код** (`[desktop]`):
  - `packages/flutter/codelab_ui`:
    - организм `CodeLabOpenProjectScreen`;
    - параметры `CodeLabSessionSidebar.openFolderShortcut` и `noProjectsLabel`, перенос «Open folder…» в список проектов;
    - `CodeLabAppBar.connectionLabel`;
    - запись `CodeLabShortcut.openFolder` и `CodeLabWorkbenchShortcuts.onOpenFolder`;
    - строка каталога кита `codeLabSidebarNoRecentProjects`;
    - комментарий `CodeLabStartScreen`;
  - `apps/codelab_desktop`:
    - `lib/core/platform/os_drop_region.dart` (адаптер `desktop_drop`);
    - `lib/core/platform/local_path_kind.dart` (порт `LocalPathKindOf` и `dart:io`-реализация);
    - `SettingsCubit.openDropped`, состояние `ProjectDropRejection`;
    - поля `ShellState`, фасад `CodeLabShellCubit`;
    - `features/workbench/presentation/widgets/open_project_screen.dart`, `main_pane.dart`, `workbench_shell.dart`;
    - страница «Keyboard»;
    - `SettingsOpenSource.startScreen`;
    - `app_scope.dart` (шов `localPathKind:`);
    - ARB `en`/`ru`, `pubspec.yaml`.
- **Зависимости**: новая сторонняя — `desktop_drop` в `apps/codelab_desktop` (точный пин после проверки 1.1). Рёбер между пакетами `codelab_*` нет, граф в `README.md` не меняется. Allowlist ядра (PKG-2) не затронут. Новое правило сторожа: `package:desktop_drop/` в `apps/codelab_desktop/lib` — только в `core/platform/os_drop_region.dart`.
- **ACP**: без изменений.
- **Данные пользователя**: новых ключей и файлов нет. Перетащенная папка, как выбранная в «Open folder…», попадает в недавние проекты (`RecentProjectsStore`) и в снимок рабочего пространства.
- **Безопасность**: перетаскивание — явное действие пользователя, такое же, как выбор в системном диалоге. Права агента в папке те же. Containment (`BoundedEnv`, проверка `fs/*`/`terminal/*` по папке сессии) не меняется. Перед стартом агента папка проверяется ещё раз (D3 `require-project-folder`). Путь перетащенного элемента не попадает в журнал `structured_log`, только в диагностику app (как `Selected project: <path>`).
- **Документация**:
  - `docs/architecture/technology-stack.md` §20и и таблица стека;
  - `platform-integration.md` §37;
  - `12-3-desktop-display.md` §12.3.6 (строка `desktop_drop`);
  - `delivery-roadmap.md` (пункт о новых зависимостях десктопа);
  - `l10n-glossary.md`;
  - `apps/codelab_desktop/AGENTS.md` (раздел «Экран без проекта»), `packages/flutter/codelab_ui/AGENTS.md` (новый организм);
  - для `docs-writer`: `apps/codelab_desktop/README.md` (шаги первого запуска), `apps/codelab_desktop/doc/user-guide.md` (разделы «Первый запуск», «Проекты», список сочетаний) и снимок `doc/images/first-launch-no-project.png`.
