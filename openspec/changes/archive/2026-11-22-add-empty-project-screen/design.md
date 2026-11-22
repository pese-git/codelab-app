## Context

Change `require-project-folder` (архив 2026-11-12, D1–D24) ввёл правило «без проекта нет папки агента и сессий». Агент стартует на триггерах D13: выбор проекта, «New session» в проекте, фокус на сессии, «Retry». «New session» без проекта открывает системный выбор папки. Восстановление проекта ждёт не дольше 2 с (D3, D19). Change `add-app-onboarding` (D5) отложил старт до конца onboarding. Всё это реализовано.

Вид состояния «проект не выбран» остался временным. Сейчас в `apps/codelab_desktop/lib/features/workbench/presentation/widgets/main_pane.dart` (`_startScreen`, ветка `project == null`) рисуется `CodeLabStartScreen` из `packages/flutter/codelab_ui/lib/src/organisms/codelab_start_screen.dart` с текстом `Open a project to start a session.` и кнопкой «Open folder…» (`cubit.browseForProject()`). Бейдж соединения пишет `Disconnected`. Сайдбар (`CodeLabSessionSidebar` в `workbench_shell.dart`) при пустом списке проектов ничего не показывает в группе «Projects», а «Open folder…» стоит внизу рядом с «Settings».

Источник вида — кадр 11a холста Claude Design: `docs/design/claude-design/ProjectsEmpty.dc.html` (светлая тема), `ProjectsEmpty-dark.dc.html` (тёмная тема), строка 11a в `README.md` экспорта, заметка ряда «Открытие проекта» (R-22) в `canvas.json` и граф `NavProject.dc.html`. Холст — только reference: разметка и код холста не копируются (корневой `AGENTS.md` §5, `codelab_ui/AGENTS.md`).

По сравнению со сборкой кадр добавляет пять вещей:
1. объяснение и карточку агента окна;
2. зону перетаскивания папки — нового поведения в spec нет;
3. подсказку Ctrl+O, а привязки Cmd/Ctrl+O в сборке нет: spec app-settings прямо перечисляет её среди непривязанных;
4. статус бейджа `No project · agent not started`;
5. в сайдбаре — `No recent projects yet.` и «Open folder…» с подсказкой внутри группы «Projects».

Прочитаны:
- корневой `AGENTS.md`, `apps/codelab_desktop/AGENTS.md`, `packages/flutter/codelab_ui/AGENTS.md`;
- `docs/architecture/permissions.md`, `platform-integration.md` (§7, §8, §16, §37–§39, §80), `layers-and-dependencies.md`, `technology-stack.md` (§12, §20з, §24–§27);
- `12-3-desktop-display.md` §12.3.6, `delivery-roadmap.md` (пункт о `desktop_drop`);
- spec `agent-workbench-ui`, `app-settings` («Keyboard»), `app-onboarding` («Permissions»), `workspace-architecture`;
- архивные changes `require-project-folder`, `add-app-keyboard-page`, `add-app-onboarding`, `add-app-appearance-page` (D7 — образец новой платформенной зависимости).

Активные changes (`add-agent-os-secret-backends`, `add-app-skills-page`, `add-file-preview-and-tree`, `add-integrated-terminal`, `switch-default-agent-to-dart`) эти требования не меняют.

## Goals / Non-Goals

**Goals:**
- экран без проекта по кадру 11a в светлой и тёмной теме;
- приём папки перетаскиванием как ещё один явный выбор проекта, с отказами для файла, нескольких элементов и пропавшего пути. Решение «папка ли это» принимает application;
- Cmd/Ctrl+O — «Open folder…», чтобы подсказка кадра соответствовала привязке;
- бейдж и сайдбар без проекта по кадру;
- поведение `require-project-folder` и `add-app-onboarding` не меняется.

**Non-Goals:**
- смартфон и планшет (P22, T16): мобильных целей у app нет до этапа 10, модель проекта там другая (§12.8.4, §12.8.7);
- диалог «Project picker» (кадр 11);
- вид кадров 11b–11f;
- перетаскивание на рабочее место с проектом и вложения (D-12);
- песочница macOS (P-13);
- любые изменения ACP.

## Decisions

### D1. Новый организм кита `CodeLabOpenProjectScreen`, а не расширение `CodeLabStartScreen`

`CodeLabStartScreen` — экран одного действия: текст, кнопка, индикатор старта. Его использует и ветка «проект выбран» (кадр 11c в этом change не меняется). У кадра 11a шесть блоков: герой, пояснение, кнопка с подсказкой, зона, карточка агента, InfoBar. Если добавить их в `CodeLabStartScreen` необязательными параметрами, у виджета появятся две несвязанные раскладки под флагами. Поэтому вводится организм `packages/flutter/codelab_ui/lib/src/organisms/codelab_open_project_screen.dart`. Его параметры — готовые строки и колбэки:
- `title`, `description`, `openLabel`, `openShortcut`, `onOpen`;
- `dropLabel`, `dropHint`, `dropActive`, `dropMessage` (`String?`);
- `agentName`, `agentDetail`, `agentNote`, `settingsLinkLabel`, `onOpenSettings`;
- `infoTitle`, `infoBody`.

Логики в организме нет (`codelab_ui/AGENTS.md` §2): он не знает профилей, не решает, какой текст показать, и не принимает перетаскивание (D3). Зона и карточка — приватные части организма. Новых атомов нет: второго употребления у них пока нет (§3 кита, корневой §13).

Ключи: `open-project-screen`, `start-open-project` (ключ кнопки сохранён, на него опираются тесты `agent_start_screens_test.dart`), `open-project-drop-zone`, `open-project-drop-message`, `open-project-agent`, `open-project-agent-settings`, `open-project-info`.

Индикатор `busyLabel` в организм не переносится: без проекта агент не стартует (триггеры D13 `require-project-folder` требуют папку; «Restart agent» без проекта отклоняется). Индикатору нечего показывать.

*Альтернативы:* (а) расширить `CodeLabStartScreen` — отклонено, см. выше; (б) собрать экран в app из виджетов Fluent — отклонено, вёрстка рабочего места живёт в ките (`codelab_ui/AGENTS.md` §1).

### D2. Где строится экран в app

`main_pane.dart`: ветка `project == null` в `_startScreen` строит `WorkbenchOpenProjectScreen` (новый файл `features/workbench/presentation/widgets/open_project_screen.dart`). Это `StatefulWidget`, который:
- держит только состояние «элементы над экраном» (`dropActive`) — временное состояние просмотра в `State`, допустимое по корневому `AGENTS.md` §8 и `codelab_ui/AGENTS.md` §2. Источником истины оно не является;
- оборачивает организм адаптером `OsDropRegion` (D3) и передаёт ему колбэки `cubit.openDroppedPaths` и `cubit.clearDropRejection`;
- собирает тексты по `context.l10n` из типизированных данных `ShellState` (D5, D6, D11).

Условие показа прежнее: панель показывает стартовый экран, когда лента пуста и соединение не `connected`; сбой и потеря соединения дают экран сбоя. Меняется только содержимое ветки без проекта.

### D3. Зависимость для перетаскивания из ОС — `desktop_drop`, за адаптером `OsDropRegion`

Flutter-фреймворк не отдаёт на десктопе события перетаскивания внешних файлов: `DragTarget` и `Draggable` работают только внутри дерева виджетов. `file_selector` (уже в стеке, §12.1) покрывает только диалоги. Своего решения в проекте нет: поиск по `apps/`, `packages/` и `docs/architecture/` нашёл только строку `desktop_drop` в таблице новых зависимостей `12-3-desktop-display.md` §12.3.6 («остаются до D-12») и открытый пункт `delivery-roadmap.md` «новые зависимости десктопа (`desktop_drop`, `pasteboard`) — архитектурное решение и проверка лицензии до D-12». Этот change принимает решение по `desktop_drop` раньше D-12. Он же — первый потребитель адаптера; D-12 переиспользует адаптер для композера. `pasteboard` не затрагивается.

**Итог ворот 1.1 (2026-11-22).** Проверка пройдена, пользователь принял `desktop_drop` с точным пином **0.8.4** (0.9.x требует Flutter `>=3.47.7`). В Flutter 3.47.0 API внешнего перетаскивания нет. Транзитивно добавляются `universal_platform` 1.1.0 (MIT) и `dbus` 0.7.15 (MPL-2.0, только Linux) — `dbus` допущен явным решением пользователя 2026-11-22. Сборка macOS с пакетом проходит локально; Linux и Windows — CI после задачи 5.4. Открытые issues пакета не просмотрены (GitHub API недоступен). Подробности — `technology-stack.md` §20и.

Проверка по `technology-stack.md` §24–§25 — задача 1.1, до правки `pubspec.yaml`. Результат записывается в новый §20и `technology-stack.md` (образец — §20з `system_theme`):
1. **Нет ли этого в SDK.** Проверить, не появился ли в Flutter 3.47 (`.fvmrc`) API приёма внешнего перетаскивания на десктопе. Если появился, change использует SDK без зависимости, адаптер остаётся тем же (§25 п. 2).
2. **Платформы и нативная часть** (`desktop_drop`, федеративный плагин; регистрирует генератор плагинов Flutter):
   - macOS — `NSView` окна Flutter регистрируется на типы файловых URL. App собран без песочницы (`com.apple.security.app-sandbox` = `false` в `DebugProfile.entitlements` и `Release.entitlements`), поэтому новых entitlements не нужно, и путь доступен процессу агента. Если песочницу включат (P-13), брошенный URL даст только временный security-scoped доступ процессу app, а не дочернему процессу агента. Тогда решение пересматривается (риски);
   - Windows — OLE drop target окна. Перетаскивание из Проводника в app, запущенный с повышенными правами, Windows блокирует (UIPI). Это известное ограничение, оно документируется, а не обходится;
   - Linux — GTK drag-dest на виджете Flutter (`text/uri-list`), X11 и Wayland через GTK. Проверить сборку CI Linux и `linux/packaging`.
3. **Лицензия** — разрешительная, совместимая с MIT; транзитивные пакеты (`cross_file` уже в lock через `file_selector`). Зависимости pub.dev в `THIRD_PARTY_NOTICES.md` не вносятся (вводная часть файла, §20з п. 8). Если лицензия не подходит, задача 1.1 останавливает change и возвращает вопрос пользователю.
4. **Пин** — точная версия, как у `url_launcher` и `system_theme` (§20е, §20з). Выбрана в задаче 1.1: `0.8.4`.
5. **Сопровождение** — дата последнего выпуска и открытые проблемы по трём ОС, записать в §20и.
6. **Безопасность.** Плагин отдаёт только пути, которые пользователь сам бросил в окно. Содержимое файлов он не читает. Путь — недоверенный вход, его вид проверяет application (D4).

**Адаптер** — `apps/codelab_desktop/lib/core/platform/os_drop_region.dart`: виджет `OsDropRegion({required child, onEntered, onExited, required onDropped})`. `onDropped` получает `List<String?>`: путь каждого элемента или `null`, если у элемента нет локального пути (пустая строка `XFile.path`). Адаптер — единственный файл, где разрешён `package:desktop_drop/` (правило сторожа, spec workspace-architecture). Никакой логики, кроме перевода событий плагина в эти колбэки, в нём нет. Тест адаптера проверяет перевод через события канала плагина в `TestDefaultBinaryMessenger` (по образцу теста адаптера `system_theme`). Тесты экрана вызывают колбэки найденного `OsDropRegion` напрямую.

`codelab_ui` от плагина не зависит: зона в ките только рисует состояние `dropActive` и `dropMessage`.

*Альтернативы:*
- (а) `super_drag_and_drop` — богаче (перетаскивание наружу, буфер), но тянет нативное расширение на Rust (`super_native_extensions`). Сборка требует Rust toolchain или скачивания готовых бинарей во время сборки, а это новая нагрузка на CI macOS, Windows и Linux. Нужен только приём путей — отклонено (§13, §25 п. 7);
- (б) свой платформенный канал на трёх ОС — три нативные реализации и их поддержка ради одного события. Отклонено по образцу D7 `add-app-appearance-page`;
- (в) без перетаскивания: только «Open folder…» и Ctrl+O, отступление от кадра 11a. Это запасной путь, если задача 1.1 отклонит зависимость: решение пользователя Q2 (а) — экран без зоны, перетаскивание отдельным change.

**ADR** не нужен: узкая платформенная зависимость за адаптером, архитектура не меняется (прецедент §20е, §20з; `technology-stack.md` §26).

### D4. Где решается «папка ли это»: `SettingsCubit` и порт `LocalPathKindOf`

Корневой `AGENTS.md` §6 и §11, `platform-integration.md` §37 требуют, чтобы перетаскивание превращалось в нормализованную модель application до обработки. Виджет не решает, можно ли открыть элемент. Файловая система — инфраструктура.

- **Порт** — `apps/codelab_desktop/lib/core/platform/local_path_kind.dart`:
  - `enum LocalPathKind { directory, file, missing, other }`;
  - `typedef LocalPathKindOf = Future<LocalPathKind> Function(String path)`;
  - реализация `ioLocalPathKind` на `FileSystemEntity.type(path, followLinks: true)`.

  Ошибку проверки реализация не бросает наружу, а возвращает `other`. Порт живёт рядом с `ProjectFolderPicker` в `core/platform/`, а не в `codelab_client_io`: второго потребителя нет, CLI перетаскивания не принимает (§13). `DirectoryExists` из `codelab_client_io` не подходит: он не отличает файл от пропавшего пути.
- **Решение** — метод `SettingsCubit.openDroppedPaths(List<String?> paths)`. Состояние `SettingsState.dropRejection` — закрытая иерархия `ProjectDropRejection`: `DropNotAFolder(path)`, `DropMultiple(count)`, `DropMissing(path)`, `DropUnsupported(path?)`. Это разовое сообщение, хранится типом, текст строит presentation (`apps/codelab_desktop/AGENTS.md`, «Локализация», вид 3). Порядок:
  1. пустой список — ничего;
  2. больше одного элемента — `DropMultiple`, вид путей не проверяется;
  3. `null` или пустой после `trim` путь — `DropUnsupported(null)`;
  3а. путь, который не является абсолютным путём файловой системы ОС app (`package:path`, контекст текущей платформы: `/…` на macOS и Linux, `C:\…` и UNC `\\server\share\…` на Windows), — `DropUnsupported(null)` без проверки вида. На Windows нужен корень с буквой диска или UNC: путь от корня текущего диска (`\dir`) отклоняется, потому что он зависит от текущего диска процесса app. Строка со схемой URI (`<scheme>://`, схема из двух и более символов) путём не считается. Проверка — чистая функция `isLocalAbsolutePath(path, {p.Context? context})` в `project_drop.dart`: на Windows `rootPrefix(path).length > 1`, на POSIX `isAbsolute`. Тесты для стилей POSIX и Windows — `local_absolute_path_test.dart`. Причина (ревью итерации 1, находка safety MEDIUM): `desktop_drop` на Linux отдаёт не-файловые URI (`https://user:token@…`, `smb://…`) как «путь», а в них бывают userinfo и токены. Такой текст не должен попасть ни в состояние, ни на экран, ни в диагностику, ни в событие. Относительный путь тоже отклоняется: он разрешался бы от `cwd` процесса app — неявной папки, которую D1 `require-project-folder` запрещает;
  4. иначе `await kindOf(path)`: `directory` — `selectProject(path)` (тот же путь, что после выбора в «Open folder…»: недавние, `ClientWorkspace.selectProject`, триггер старта через `_onProjectSelected`); `file` — `DropNotAFolder`; `missing` — `DropMissing`; `other` — `DropUnsupported`.

  Путь не канонизируется и не раскрывается по ссылкам, как путь из `file_selector`. Containment обеспечивает агент (`BoundedEnv`, realpath) и клиентская проверка `fs/*`/`terminal/*` по папке сессии (корневой §10; `permissions.md` §28–§30). Проверка `missingProjectDirectory` перед стартом агента (D3 `require-project-folder`) остаётся: между проверкой вида и стартом папку могут удалить.
- **Сброс сообщения** — `clearDropRejection()` при входе перетаскивания на экран, а также в `selectProject` (любой выбор проекта).
- **Поздний результат** (корневой §9, §12). У `SettingsCubit` есть счётчик явных намерений выбора `_projectIntent`. Его увеличивают `selectProject` (кроме вызова из самого броска), `browseForProject` и `openDroppedPaths`. Бросок запоминает свой номер до `await kindOf` и после ожидания применяет результат, только если номер не изменился и Cubit не закрыт (`isClosed`). Восстановление проекта прошлого запуска — не явное намерение. Оно уже уступает выбору пользователя (`state.selectedProjectPath != null`), поэтому бросок, завершившийся после восстановления, всё равно применяется: пользователь бросил папку на экран без проекта.
- **Наблюдаемость** (корневой §16). При отказе — диагностика `warning` с источником `project` и путём (как `Selected project: <path>`; диагностика — журнал app на этой машине). У `DropUnsupported(null)` (нет пути или путь не абсолютный, п. 3, 3а) — `Dropped item rejected (unsupported).` без пути. Событие логгера app (`_appLogger`, компонент `app`): `project.drop {outcome: opened | rejected, reason?: not_a_folder | multiple | missing | unsupported, count}`, без путей и имён. Успешный бросок дополнительно пишет то же, что выбор проекта (`Selected project: …`).

Фасад `CodeLabShellCubit` получает `openDroppedPaths` и `clearDropRejection`, `ShellState` — поле `dropRejection`.

*Альтернативы:*
- (а) проверять вид в адаптере `OsDropRegion` — правило «что можно открыть» уехало бы в инфраструктуру, а тест правила потребовал бы плагина. Отклонено;
- (б) проверять в виджете через `dart:io` — нарушает §6 и §11. Отклонено;
- (в) принимать первую папку из нескольких — неочевидно для пользователя, кадр явно говорит «only a folder». Отклонено (решение пользователя Q4 (а)).

### D5. Карточка агента окна: данные из `ConnectionCubit`, текст в presentation

Профиль окна — `ConnectionCubit.shownProfile` (выбранный профиль, пока агента не было). Имя — существующее `profileLabel` (`localizedProfileTitle`: встроенный агент переводится, профиль пользователя — никогда). Деталь — существующее `connectionDetail`: команда stdio без аргументов или `scheme://host:port` WebSocket без userinfo, пути и query (D17 `add-app-settings-shell`, находка L1). Значит, на экран не попадают аргументы, `env` и токен.

Вид транспорта `ShellState` отдаёт типом `ProfileTransportKind { embedded, stdio, webSocket }` — новое поле рядом с `transportLabel`. Подписи `in-process · profile of this window`, `stdio · <detail> · profile of this window`, `WebSocket · <detail> · profile of this window` и пояснения `Starts…`/`Connects…` строит presentation по типу (вид 2 раздела «Локализация» `apps/codelab_desktop/AGENTS.md`). `stdio` и `WebSocket` — названия протоколов, не переводятся (D7 `add-desktop-localization`).

Для WebSocket «Starts when you open a folder» неверно: агент уже работает где-то ещё, app только подключается при первом триггере (требование «Агент стартует сам», пункт WebSocket). Поэтому пояснение — `Connects when you open a folder. Nothing connects before that.`

Ссылка `Change in Settings › Connection` — `NavigationCubit.openSettings(page: SettingsPage.connection, source: SettingsOpenSource.startScreen)`. Новое значение `startScreen` (`start_screen` в событии `settings.opened`) нужно, чтобы журнал отличал источник от баннера (корневой §16).

### D6. Пояснение о границе папки — только для встроенного агента

Кадр обещает: `The agent can't read or write outside it.` Для встроенного агента это обеспечивает `BoundedEnv` рабочей папки (`platform-integration.md` §80; spec app-onboarding «Шаг «Permissions»» показывает то же правило — `Anything outside the project folder` → `Blocked`). Для внешнего агента (stdio, WebSocket) CodeLab этого не гарантирует. Клиентская проверка `fs/*` и `terminal/*` ограничивает только запросы к клиенту, а собственный доступ процесса агента к диску — нет. Обещать это пользователю внешнего профиля — неверная информация о безопасности (приоритет 1 корневого §2).

Поэтому три варианта пояснения (spec «Экран без выбранного проекта», п. 2):
- для внешнего профиля вместо фразы о границе — `An external agent applies its own rules to files outside it.`, по образцу текста onboarding `It applies its own rules`;
- для WebSocket без `The agent starts in it`: агент не стартует в папке, папку получают только сессии.

Формулировки приняты пользователем 2026-11-22 (Q1 (а), раздел «Решения пользователя 2026-11-22»).

### D7. Cmd/Ctrl+O — запись каталога `openFolder`

Spec app-settings «Сочетания app и страница «Keyboard» не расходятся» требует, чтобы короткая подсказка на рабочем месте показывала клавиши существующей привязки. Сейчас Cmd/Ctrl+O явно числится непривязанным. Подсказку кадра можно было бы просто убрать, но кадр 11a, сайдбар всех кадров ряда «Открытие проекта», граф `NavProject` («11 Project picker · Ctrl+O») и `12-3-desktop-display.md` (строка 11: «Cmd/Ctrl+O»; §3 «Сочетания»: «Cmd/Ctrl+O — выбор проекта») предполагают это сочетание. Поэтому change его вводит по правилу «новое сочетание — в одном change» (`apps/codelab_desktop/AGENTS.md`, «Страница «Keyboard»»):
- запись `CodeLabShortcut.openFolder(CodeLabShortcutGroup.global, [CodeLabKeyCombo(LogicalKeyboardKey.keyO, primary: true)])` в `codelab_shortcuts.dart` после `newSession`;
- колбэк `CodeLabWorkbenchShortcuts.onOpenFolder` и привязка `CodeLabShortcut.openFolder.bind(...)`;
- app передаёт `cubit.browseForProject`; в настройках и onboarding рабочего места нет, и привязки там тоже нет;
- строка `open-folder` на странице «Keyboard»: Action `Open a folder as the project`, Where `Workbench`; тексты ARB `settingsKeyboardActionOpenFolder` (`en`/`ru`); ветки исчерпывающих `switch` в `keyboard_page.dart`;
- проверки нажатием в сторожах `codelab_shortcut_bindings_test.dart` (кит) и `keyboard_bindings_test.dart` (app).

Ctrl+O открывает системный выбор папки, а не диалог 11 «Project picker»: диалога в сборке нет, это отдельный change (решение пользователя Q3 (а)). Когда диалог появится, сочетание сменит цель без смены клавиш.

Нативное меню macOS (`MainMenu.xib`) пункта с ⌘O не имеет — проверено поиском `keyEquivalent`. Поэтому сочетание не «съедается» меню (`platform-integration.md` §8а). Задача 3.6 проверяет это повторно.

**Один диалог за раз.** С Ctrl+O появляется третий путь к `browseForProject` (сайдбар, «New session» без проекта, сочетание). Повторное нажатие, пока системный диалог открыт, могло бы открыть второй диалог: на Linux диалог `file_selector` не всегда модален для событий клавиатуры Flutter. `SettingsCubit` хранит незавершённый `Future` выбора: повторный `browseForProject` ждёт его и не вызывает порт второй раз. Явного флага нет: незавершённый `Future` — единственный источник истины.

**Ошибка системного диалога** (ревью итерации 1, находка LOW). Если порт `ProjectFolderPicker.pickFolder` бросает, `browseForProject` не пробрасывает ошибку вызывающим: сочетание и кнопки зовут его без `await`, и ошибка потерялась бы (корневой §12). Вместо этого он пишет диагностику `warning` с источником `project` без текста исключения — в тексте может быть путь или ответ платформы — и событие журнала app `project.picker_failed {error_class}`, где `error_class` — `runtimeType` ошибки. Проект не меняется, а `_picking` сбрасывается, так что следующий запрос открывает диалог заново. Контракт порта (бросает или нет) сверяет исполнитель. Если порт по контракту не бросает, достаточно защитного `catch` с той же диагностикой. Текст диагностики — `Failed to open the folder picker.` (строка журнала, не интерфейса).

### D7а. Cmd/Ctrl+N и пункт палитры `new` без проекта

Ручная проверка 2026-11-22 нашла расхождение. InfoBar экрана (`workbenchOpenProjectInfoBody`), кадр 11a и заметка R-22 холста обещают, что Cmd/Ctrl+N без проекта открывает тот же выбор папки. А spec «Агент стартует сам» (пункт «Сочетания») и сборка привязывали Cmd/Ctrl+N только при выбранном проекте: в `workbench_shell.dart` `onNewSession` равен `null` без проекта. Решение пользователя 2026-11-22: привязать Cmd/Ctrl+N всегда, к тому же действию, что кнопка «New session» сайдбара.

- **Действие** — `cubit.createSession()`. Без проекта он уже открывает `browseForProject()` (правило «New session» без проекта, D3 и D19 `require-project-folder`): агент до выбора не стартует, сессия после выбора не создаётся, ожидание восстановления проекта (≤ 2 с) сохраняется. Нового пути в application нет, меняется только привязка в presentation.
- **Один диалог** — общий `_picking` из D7: повторный Cmd/Ctrl+N, «Open folder…» или Cmd/Ctrl+O при открытом диалоге второй диалог не открывают.
- **Пункт палитры `new`** уже согласован. В сборке он доступен без проекта: `isAvailable` из `CodeLabCommandAction.defaults` равен `true`, а `selectCommand('new')` зовёт `createSession()`, то есть без проекта открывает выбор папки. Spec до этого change говорила «доступны, когда выбран проект», и пункт палитры ей не соответствовал. Решение — палитра ведёт себя как Cmd/Ctrl+N и кнопка, код палитры не меняется, spec приведена к сборке.
- **Страница «Keyboard».** У строки `new-session` колонка «Where» становится `Workbench` (`settingsKeyboardWhereWorkbench`) вместо `Workbench, when a project is selected`: сочетание действует на всём рабочем месте. Сообщение `settingsKeyboardWhereWorkbenchProject` других потребителей не имеет и удаляется из `app_en.arb`/`app_ru.arb`. Spec-дельта app-settings («Страница «Keyboard»: строки таблицы») изменена.
- **В настройках и onboarding** Cmd/Ctrl+N, как и раньше, ничего не делает: рабочего места там нет.

*Альтернатива* — убрать фразу о Cmd/Ctrl+N из InfoBar и оставить привязку только с проектом. Это отступление от кадра 11a и R-22, отклонено пользователем.

### D8. Бейдж без проекта

`CodeLabAppBar` получает необязательный `connectionLabel` (`String?`): `null` — подпись по статусу, как раньше; строка — показывается вместо неё с тоном статуса `idle`, как у `disconnected` (серая точка; в кадре 11a — обычный тег без модификатора тона). Так в ките устроены параметры с текстом по умолчанию (`codelab_ui/AGENTS.md` §6). Решение «проекта нет и агент не запущен» принимает application: геттер `ShellState.awaitingProject` — `selectedProjectPath == null` и статус `idle` или `disconnected`. Presentation по нему берёт тексты ARB `workbenchBadgeNoProject` и `workbenchBadgeNoProjectTooltip`. В сбое и потере (`failed`, `lost`) бейдж прежний, с «Retry». Без проекта таких состояний в рабочем месте нет, но правило их явно не перекрывает.

### D9. Сайдбар

В `CodeLabSessionSidebar` (открытый вид) «Open folder…» переносится из нижнего блока в конец `ListView` группы «Projects», после групп проектов. Так он стоит во всех кадрах ряда «Открытие проекта» (11a, 11b, 11e, 11f). Новые параметры:
- `openFolderShortcut` (`String?`) — подсказка справа, как у «New session»;
- `noProjectsLabel` (`String?`) — `null` даёт текст кита `No recent projects yet.` (`codeLabSidebarNoRecentProjects`). Показывается, когда `projects` пуст.

Группы строит `sidebarProjectsOf` (`features/workbench/application/ui_mappers.dart`). Раньше без выбранного проекта он всегда строил первую группу `workbenchNoProject` («No project»), поэтому `projects` не бывал пустым и подпись кадра 11a не появилась бы. Решение (реализация 2026-11-22, принято при сверке с кадром `ProjectsEmpty.dc.html`, где в «Projects» только `No recent projects yet.` и «Open folder…»): если проект не выбран, недавних нет и открытых сессий нет, `sidebarProjectsOf` возвращает пустой список. Если есть недавние проекты или открытые сессии, группа «No project» остаётся, как до change: в ней видны сессии без группы, а подпись «пока нет» была бы неправдой. Открытая сессия без выбранного проекта по правилу «без проекта нет сессий» практически не возникает, условие о сессиях — защита от неверного вида.

Ключ `CodeLabSessionSidebar.openFolderKey` сохраняется. Компактный вид (иконки) не меняется: подсказки там нет, кнопка остаётся внизу рядом с «Settings». Порядок требования «Sessions sidebar grouped by project» сохраняется: группы, затем «Open folder…», затем «Settings».

### D10. Тёмная тема и ширина

Организм берёт цвета только из `FluentTheme` (`resources`, `accentColor`) и `CodeLabPalette.of(theme)`:
- фон героя — слабый акцент;
- рамка зоны — штрих `strong` темы, пунктир; в состоянии `dropActive` — сплошная рамка цвета акцента;
- текст отказа — тон `warning` палитры с иконкой: смысл не передаётся только цветом (`codelab_ui/AGENTS.md` §5).

Кадр `-dark` получается той же вёрсткой в тёмной теме. Своих цветов в организме нет. Колонка — `maxWidth` 620, как в кадре, внутри `SingleChildScrollView`: в минимальном окне app (800 px; узкий класс раскладки с сайдбаром-оверлеем) экран прокручивается, а не переполняется.

### D11. Тексты и локализация

Все строки экрана, бейджа и отказов — ARB `app_en.arb`/`app_ru.arb` с префиксом `workbenchOpenProject*` и `workbenchBadgeNoProject*`, у каждого `@key.description`. Эталон `en` совпадает со spec символ в символ. Сообщение `workbenchOpenProjectHint` (`Open a project to start a session.`) удаляется. При реализации оказалось, что у него есть второй потребитель: `SessionsCubit` кладёт его в `currentSessionDetail`, пока сессии в фокусе нет (конструктор и `_handleLanguage`). Но шапка панели (`_SessionHeader` в `main_pane.dart`) берёт `currentSessionDetail` только при `activeSessionId != null` и только если это путь. Без сессии в фокусе подпись не видна ни с проектом, ни без него. Кадр 11a в шапке её тоже не показывает. Значит, это мёртвая строка, а не видимый текст, и при выбранном проекте она ещё и неверна. Решение: удалить ключ из `app_en.arb`/`app_ru.arb`, а `currentSessionDetail` без сессии в фокусе — пустая строка (задача 4.7). Видимое поведение не меняется. Текст `Open a project to start a session.` уходит и из spec: требование «Empty session after connecting» изменено в spec-дельте этого change. Подсказки клавиш — `CodeLabShortcut.openFolder.combos.single.compactFor(defaultTargetPlatform)` и то же для `newSession`. В InfoBar подсказка подставляется плейсхолдером `{shortcut}`, склейки нет. Каталог кита получает `codeLabSidebarNoRecentProjects` (`en`/`ru`). Новых Cubit-ов с текстом в состоянии нет: `dropRejection` и `ProfileTransportKind` — типы, поэтому список D12 `add-desktop-localization` и `cubit_text_list_test.dart` не меняются. Русские формулировки — по `l10n-glossary.md`; задача 0.3 добавляет в глоссарий «перетащить», «бросить папку», «зона перетаскивания».

### D12. Пакеты, слои, сторож, граф

| Пакет (ADR-0002) | Слой | Что меняется |
|---|---|---|
| `codelab_ui` (`packages/flutter`) | organisms, atomics | `CodeLabOpenProjectScreen`; параметры сайдбара и app bar; `CodeLabShortcut.openFolder`, `onOpenFolder` |
| `codelab_desktop` (`apps/`) | `core/platform` | `OsDropRegion` (единственный импорт `desktop_drop`), `LocalPathKindOf`/`ioLocalPathKind` |
| `codelab_desktop` | `features/workbench/application` | `SettingsCubit.openDroppedPaths`, `ProjectDropRejection`, `_projectIntent`, один диалог выбора; `ShellState.dropRejection`, `awaitingProject`, `transportKind`; фасад |
| `codelab_desktop` | `features/workbench/presentation`, `features/settings/presentation` | `WorkbenchOpenProjectScreen`, `main_pane.dart`, `workbench_shell.dart`; строка `open-folder` страницы «Keyboard» |
| `codelab_desktop` | `app/` | шов `localPathKind:` в `createCodeLabRootScope` и привязка в графе (рядом с `directoryExists`); `SettingsOpenSource.startScreen` |

`codelab_client_*`, `codelab_agent_*`, `codelab_acp_*`, `codelab_embedded`, `codelab_setup` не меняются.

Направление зависимостей прежнее: presentation → application → `core/platform`-порты; адаптеры в `core/platform` знают плагин, application — только тип порта. Application рабочего места использует `LocalPathKindOf` так же, как уже использует `ProjectFolderPicker` и `DirectoryExists`.

**Сторож:** новое правило в `packages/dart/codelab_architecture_tests/test/support/rules.dart` — `PackageRule('apps/codelab_desktop/lib', forbidden: ['package:desktop_drop/'], exclude: ['core/platform/os_drop_region.dart'], sealExclude: false)`, по образцу `system_theme`. Правило для `codelab_ui` не нужно: у кита нет зависимости от плагина в `pubspec.yaml`, импорт не соберётся (`codelab_ui/AGENTS.md` §1).

**Граф в `README.md`** не меняется: новых рёбер между пакетами `codelab_*` нет. **PKG-2** (allowlist ядра) не затронут. **Web-безопасность**: web-безопасные барели (`codelab_acp_transports`, `codelab_embedded`, `codelab_client_core`) не меняются; `web-compile` не нужен.

### D13. Итерации и исполнители

Все кодовые задачи — `[desktop]` (`apps/codelab_desktop`, `packages/flutter/codelab_ui`, правило сторожа app). `[client]`, `[protocol]`, `[agent]`, `[site]` — задач нет. Порядок:
0. документы;
1. проверка зависимости — ворота;
2. кит;
3. application app;
4. presentation, сочетание и страница «Keyboard»;
5. адаптер, плагин и сторож;
6. продуктовая документация (`docs-writer`).

Если ворота 1.1 закрыты (зависимость отклонена), итерация 5 и сценарии перетаскивания откладываются, а зона на экране не показывается (решение пользователя Q2 (а)). Тогда этот change до архивации убирает из spec-дельты agent-workbench-ui п. 4 требования «Экран без выбранного проекта» и требование «Открытие папки перетаскиванием», из spec-дельты workspace-architecture — требование о плагине, а из tasks.md — итерацию 5; перетаскивание уходит в отдельный change.

## Risks / Trade-offs

- **Песочница macOS (P-13).** С включённой песочницей брошенный URL доступен только процессу app по временному security-scoped доступу. Дочерний процесс stdio-агента его не получит, а при перезапуске доступ пропадёт. → Сейчас песочницы нет. Задача 9.11 дорожной карты (модель угроз) должна учесть `desktop_drop` и `file_selector` вместе. Запись в §20и.
- **UIPI на Windows.** В app, запущенный от администратора, перетаскивание из Проводника не работает. → Документируется в руководстве; кнопка и Ctrl+O остаются.
- **Гонки** (корневой §9, §12):
  - поздний результат проверки вида — номер намерения и `isClosed` (D4);
  - бросок во время восстановления — бросок побеждает, восстановление уже уступает выбору пользователя;
  - повторный бросок той же папки, пока агент стартует, — правило «параллельные триггеры — один транспорт» `ConnectionCubit` (D17 `require-project-folder`);
  - второй системный диалог — общий `Future` (D7).
- **TOCTOU** между проверкой вида и стартом. Папку удалили — сработает существующая проверка `missingProjectDirectory`, агент не стартует (сценарий «Папка исчезла после проверки вида»). Папку подменили на ссылку — containment агента работает по realpath (`permissions.md` §29–§30). Права агента не шире, чем при выборе в диалоге.
- **Пакеты macOS (`.app`) — тоже каталоги.** Брошенный `Foo.app` будет принят как папка, хотя системный диалог выбора папки такой пакет не выбирает. → Принимаем как папку: вреда нет, агент работает в каталоге пакета (решение пользователя Q5 (а); сценарий «Пакет macOS принимается как папка»).
- **Корень диска.** Брошенный `/` выбирается проектом, как и через `file_selector` сейчас. Восстановление из снимка корень не выбирает, а загрузка сессии в корне требует подтверждения. → Поведение то же, что у «Open folder…»; ужесточение для обоих путей — отдельный change (решение пользователя Q6 (а)).
- **Обещание о границе папки** для встроенного агента касается файловых инструментов. Команды `exec` идут через одобрение, но процесс команды может читать вне папки. Формулировка унаследована от onboarding (шаг «Permissions»). → Принята пользователем для встроенного агента (Q1 (а)); уточнение обещания для `exec` — вместе с моделью угроз (задача 9.11 дорожной карты), вне этого change.
- **Новая нативная зависимость** утяжеляет сборку на трёх ОС. → Ворота 1.1 и сборка CI (Linux, Windows, macOS) до merge. Запасной путь — D3 (в).
- **Мигание бейджа.** Первые ≤ 2 с, пока восстанавливается проект прошлого запуска, бейдж пишет `No project · agent not started`. Это правда о текущем состоянии; экран без проекта так же показывается и сейчас. Отдельного состояния «восстанавливается» change не вводит.

## Migration Plan

Миграции данных нет: ключей `shared_preferences` и файлов не добавляется. Обновление app меняет вид экрана без проекта, место «Open folder…» в сайдбаре и добавляет Ctrl+O. Откат — откат кода и удаление зависимости из `pubspec.yaml`.

## Решения пользователя 2026-11-22

Пользователь одобрил change и принял все предложения.
- Q1 (а) — пояснение зависит от профиля: у встроенного агента — текст кадра с фразой `The agent can't read or write outside it.`; у stdio и WebSocket вместо неё — `An external agent applies its own rules to files outside it.`; у WebSocket нет `The agent starts in it` (D6; spec «Экран без выбранного проекта», п. 2 — уже по предложению).
- Q2 (а) — если ворота 1.1 отклонят `desktop_drop`, экран строится без зоны перетаскивания, остальное по кадру; перетаскивание — отдельный change (D3 (в), D13).
- Q3 (а) — Cmd/Ctrl+O сейчас открывает системный выбор папки; диалог 11 «Project picker» — отдельный change позже (D7).
- Q4 (а) — несколько брошенных элементов дают отказ `Drop one folder at a time.` (D4; сценарий «Несколько элементов отклоняются»).
- Q5 (а) — пакеты macOS (`.app` и т. п.) принимаются как папка: вид пути решает файловая система, отдельной проверки пакета нет (D4; сценарий «Пакет macOS принимается как папка» добавлен в spec-дельту agent-workbench-ui).
- Ворота 1.1 — `desktop_drop` принят, пин `0.8.4`; транзитивный `dbus` 0.7.15 под MPL-2.0 (только Linux) допущен (D3; `technology-stack.md` §20и).
- Q6 (а) — корень диска принимается, как сейчас у «Open folder…»; ужесточение для обоих путей — отдельный change (риски; абзац о проверках сверх вида пути в требовании «Открытие папки перетаскиванием»).

## Open Questions

Нет: Q1–Q6 решены пользователем 2026-11-22 (раздел «Решения пользователя 2026-11-22»). Исходные формулировки:

- **Q1. Текст пояснения для профилей.** (а) Три варианта D6: фраза о границе только у встроенного агента, у внешнего — `An external agent applies its own rules to files outside it.`, у WebSocket — без `The agent starts in it` (предложение). (б) Текст кадра для всех профилей. (в) Убрать фразу о границе для всех.
- **Q2. Если ворота 1.1 отклонят `desktop_drop`.** (а) Экран без зоны перетаскивания, остальное по кадру; перетаскивание — отдельный change (предложение). (б) Остановить change до выбора другого решения.
- **Q3. Цель Cmd/Ctrl+O.** (а) Системный выбор папки сейчас, диалог 11 «Project picker» позже (предложение). (б) Не вводить сочетание и убрать подсказки кадра.
- **Q4. Несколько брошенных элементов.** (а) Отказ `Drop one folder at a time.` (предложение). (б) Открыть единственную папку среди элементов, файлы проигнорировать.
- **Q5. Пакеты macOS (`.app` и т. п.).** (а) Принимать как папку (предложение). (б) Отклонять как `not_a_folder`.
- **Q6. Корень диска как проект.** (а) Как сейчас у «Open folder…»: принимается (предложение для этого change). (б) Отклонять корень и в броске, и в «Open folder…» — отдельное требование безопасности, лучше отдельным change.
