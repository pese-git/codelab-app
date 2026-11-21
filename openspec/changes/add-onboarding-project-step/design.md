## Context

Onboarding первого запуска (change `add-app-onboarding`, архив 2026-11-21, D1–D17) состоит из четырёх шагов: «What CodeLab does», «Permissions», «Choose a model», «Privacy». Последний заканчивается кнопкой «Start using CodeLab» (`onboarding-finish`). `OnboardingCubit.finish()` пишет флаг `codelab.app.onboarding_done` и вызывает `NavigationCubit.finishOnboarding()`. При первом `WorkbenchDestination` `_CodeLabHome` один раз вызывает `CodeLabShellCubit.startOnLaunch()` (D5). Пока показан onboarding, рабочее место не строится, а агент не стартует. Корневые Cubit-ы (`CodeLabShellCubit`, `SettingsCubit`, `ConnectionCubit`) при этом живут, и восстановление проекта из снимка идёт (`SettingsCubit._restoreProject`). Агента запускает только `startOnLaunch`.

Change `require-project-folder` (D1, D13, D19) сделал правило «без проекта нет агента» поведением. Выбор проекта — триггер 1 старта агента: `SettingsCubit._selectProject` вызывает `_onProjectSelected`, привязанный к `ConnectionCubit.startAgent`. Старт при запуске ждёт восстановления не дольше 2 с (`awaitProject`).

Change `add-empty-project-screen` (PR #426, влит в develop merge-коммитом `dc171ebe`) добавил экран 11a «Open a project» в рабочее место:
- организм `CodeLabOpenProjectScreen` (Center, прокрутка, герой, заголовок, пояснение, кнопка, зона, карточка агента, InfoBar);
- `WorkbenchOpenProjectScreen` в app;
- адаптер `OsDropRegion` (`desktop_drop` 0.8.4);
- `SettingsCubit.openDroppedPaths` с отказами `ProjectDropRejection`, порт `LocalPathKindOf`, `isLocalAbsolutePath`;
- один системный диалог за раз (общий `_picking`);
- ⌘O/Ctrl+O (`CodeLabShortcut.openFolder`) на рабочем месте, ⌘N без проекта — выбор папки (D7а).

Его spec прямо говорит: «в onboarding приёма перетаскивания этим требованием нет» и «в onboarding сочетание ничего не делает».

Пользователь одобрил направление: выбор проекта становится пятым шагом onboarding на весь экран, а экран 11a остаётся для остальных случаев без проекта.

Прочитаны:
- корневой `AGENTS.md`, `apps/codelab_desktop/AGENTS.md` (разделы «Onboarding», «Локализация», «Тесты»);
- spec `app-onboarding`, `agent-workbench-ui` (требования «Агент стартует сам», «Без выбранного проекта нет папки агента и сессий», «Project selection is independent of the connection type»);
- архивные changes `add-app-onboarding` (design D1–D17, решения пользователя и ревью) и `require-project-folder` (D1, D3, D13, D19);
- артефакты `add-empty-project-screen` в `629f3c11` (proposal, design D1–D13, spec-дельты, tasks);
- код `features/onboarding/` (`OnboardingCubit`, `OnboardingState`, `OnboardingScreen`, `onboarding_steps.dart`), `lib/app/codelab_app_widget.dart` (`_CodeLabHome`, `_OnboardingHost`), `navigation_cubit.dart`, `ConnectionCubit.startOnLaunch`, `SettingsCubit` в develop и в `629f3c11`, `open_project_screen.dart` и `codelab_open_project_screen.dart` в `629f3c11`;
- `docs/design/claude-design/README.md` (строки 07–07c.5, 11a, `NavOnboarding`, `NavProject`; экспорт односторонний);
- правила сторожа для `apps/codelab_desktop` в `codelab_architecture_tests/test/support/rules.dart`.

Активные changes (`add-agent-os-secret-backends`, `add-file-preview-and-tree`, `add-integrated-terminal`, `remove-recent-projects-migration`, `switch-default-agent-to-dart`) требования onboarding и экрана без проекта не меняют. `remove-recent-projects-migration` трогает хранилище недавних проектов, но не их чтение через `SettingsCubit`.

## Goals / Non-Goals

**Goals:**
- первый запуск заканчивается в рабочем месте с выбранным проектом и одним стартом агента;
- шаг переиспользует правила экрана 11a (выбор, перетаскивание, отказы, карточка агента), а не копирует их;
- флаг onboarding не теряется: он пишется только после принятого выбора или явного пропуска;
- агент не стартует, пока показан onboarding (D5 `add-app-onboarding` сохраняется).

**Non-Goals:**
- вид и поведение экрана 11a в рабочем месте;
- диалог 11 «Project picker»;
- повторный показ onboarding;
- смартфон и планшет;
- правка экспорта канваса (её делает пользователь, раздел U tasks.md);
- любые изменения ACP.

## Decisions

### D1. Шаг «Open a project» — пятый, последний шаг onboarding

`OnboardingStep` получает значение `project` после `privacy`. Строка шагов (`CodeLabSetupSteps`) показывает пять подписей: `What CodeLab does`, `Permissions`, `Choose a model`, `Privacy`, `Open a project`. Ключ шага — `onboarding-step-project`.

Переходы (дополняют таблицу D4 `add-app-onboarding`):

| Из | Действие | В |
|---|---|---|
| privacy | Next | project |
| project | Back | privacy |
| project | папка принята (диалог, бросок, недавний) | конец (D2) |
| project | Continue in `<name>` (проект восстановлен, D3) | конец |
| project | Skip for now (проекта нет) | конец |

На «Privacy» вместо «Start using CodeLab» (`onboarding-finish`) стоит «Next» (`onboarding-next`). Ключ `onboarding-finish` и строка ARB `onboardingFinish` удаляются: у них нет других потребителей. «Back» на «Privacy» работает по прежней таблице (на «Choose a model» или «Permissions»). Ограничение просмотра документа (D10 `add-app-onboarding`) распространяется на «Next»: пока документ открыт, «Next» не действует.

Почему последним, а не сразу после «Welcome»: шаг «Choose a model» должен записать провайдера до первого старта агента (D5 `add-app-onboarding`). Выбор папки — момент старта, поэтому он последний. «Privacy» до выбора папки тоже уместен: пользователь узнаёт, что уйдёт с компьютера, до того как что-то запустится.

*Альтернативы:*
- (а) оставить onboarding из четырёх шагов, а после «Start using CodeLab» показывать 11a в рабочем месте — текущее поведение. Пользователь видит два экрана подряд, и первый не даёт сделать то, о чём рассказывает. Отклонено направлением пользователя;
- (б) выбирать папку на шаге «Privacy» — смешивает информационный шаг с действием, а у «Privacy» есть свой просмотр документа поверх. Отклонено;
- (в) показывать 11a в рабочем месте модальным продолжением onboarding — рабочее место пришлось бы строить под onboarding, что противоречит D5 `add-app-onboarding`. Отклонено.

### D2. Завершение: выбор → флаг → навигация → старт; «Skip for now»

Onboarding завершается только на шаге «Open a project». Способов три:
1. **Папка принята.** Системный диалог вернул папку, бросок прошёл проверки D4 `add-empty-project-screen` или пользователь нажал недавний проект (D3).
2. **`Continue in <folder name>`** — проект восстановлен из снимка (D3).
3. **`Skip for now`** — проекта нет, пользователь откладывает выбор.

Публичного `finish` у `OnboardingCubit` нет: завершить onboarding можно только действием шага (`openFolder`, `openDropped`, `openRecent`, `continueWithProject`, `skip`; D5). Каждое из них после принятого выбора или проверенного условия вызывает приватный `_complete(OnboardingProjectExit exit)` (закрытая иерархия: `ProjectChosen(source)` с `source` = `picker | drop | recent`, `ProjectRestored`, `ProjectSkipped`). Так исход нельзя заявить снаружи без выбора: флаг пишется только после того, как `SettingsCubit` принял папку, или после проверки D5. `_complete` сохраняет порядок D5 `add-app-onboarding`:
1. ставит `finishing`: повторное нажатие и повторный выбор игнорируются;
2. пишет флаг через `markDone()`;
3. при сбое записи пишет `onboarding.save_failed {error_type}` и не останавливается;
4. если Cubit закрыт после `await`, выходит без `onFinished` и без событий;
5. пишет `onboarding.completed {model_step, project}` (D8) и вызывает `onFinished`: навигация переходит на рабочее место, `_CodeLabHome` один раз вызывает `startOnLaunch()`.

**Когда пишется флаг (атомарность).** Флаг пишется только после того, как выбор принят, то есть `SettingsCubit` уже сделал папку выбранным проектом. Отмена диалога, сбой диалога и отказ броска не трогают флаг, и шаг остаётся на месте. Отсюда три исхода сбоев:
- app закрыли между выбором и записью флага — при следующем запуске onboarding покажется снова, а проект, скорее всего, восстановится из снимка, и шаг предложит `Continue in <name>` (D3). Онбординг не потерян, выбор пользователя тоже;
- запись флага упала — рабочее место всё равно открывается с выбранным проектом (правило D5 `add-app-onboarding`: не запирать пользователя), onboarding покажется при следующем запуске;
- старт агента упал (папку удалили после проверки вида, битый конфиг) — это уже рабочее место: экран сбоя старта с «Retry» (`require-project-folder`, D18). Onboarding считается завершённым: шаг сделал свою работу, а повтор старта — работа рабочего места.

*Альтернативы порядка:*
- (а) сначала флаг, потом выбор — если выбор не удался (отмена диалога), onboarding уже «пройден», и пользователь попадает в рабочее место без проекта, хотя хотел выбрать. Отклонено;
- (б) выбор, старт агента, потом флаг — агент стартует под onboarding, нарушая D5 `add-app-onboarding`. Отклонено.

**Пропуск.** «Skip for now» (`onboarding-project-skip`) пишет флаг и открывает рабочее место. Без проекта там экран 11a с сайдбаром недавних проектов. Пропуск не отменяет восстановление проекта прошлого запуска: если снимок вернёт проект за 2 с после перехода, `startOnLaunch` стартует агента в нём, как при обычном запуске. Пропуск означает «не выбирать сейчас», а не «запустить без проекта».

*Альтернативы пропуска:*
- (а) пропуска нет, onboarding завершается только выбором папки. Пользователь без подходящей папки (хочет осмотреться, открыть настройки) заперт: закрытие app снова покажет onboarding. Отклонено, как и для шага модели («Set up later», Q3 `add-app-onboarding`);
- (б) пропуск без записи флага — onboarding показывался бы при каждом запуске до первого выбора папки, все пять шагов. Экран 11a уже решает задачу «нет проекта». Отклонено;
- (в) пропуск — одна из кнопок, а не отдельный исход: «Start using CodeLab» осталась бы на «Privacy», шаг 5 стал бы необязательным ответвлением. Тогда шаг 5 легко пропустить нечаянно, а это противоречит направлению «выбор проекта — последний шаг». Отклонено.

### D3. Недавние проекты и проект прошлого запуска

Шаг показывается всегда, когда показан onboarding: пятью шагами, без условного пропуска. Его вид зависит от состояния `SettingsCubit` (`selectedProjectPath`, `recentProjects`), которое шаг читает через фасад рабочего места:

- **Проект восстановлен** (в снимке была папка, она существует, настройка «Reopen last project» включена). Обычно это значит, что флаг сброшен, app переустановлено или обновлено с версии без onboarding. Над «Open folder…» шаг показывает строку `Last project: <folder name>` с путём, а среди кнопок вместо «Skip for now» — `Continue in <folder name>` (`onboarding-project-continue`, основная кнопка). Нажатие завершает onboarding с этим проектом (`ProjectRestored`). «Open folder…», бросок и недавние по-прежнему выбирают другую папку.
- **Недавние проекты есть.** Блок `Recent projects` (`onboarding-project-recents`) показывает до пяти записей в порядке `recentProjects` (последний выбор — первым), без восстановленного проекта: он уже показан строкой выше. Запись — имя папки и путь. Нажатие — выбор проекта, как в сайдбаре (`SettingsCubit.selectProject`), затем завершение (`ProjectChosen(recent)`). Существование папки до завершения не проверяется, как и у недавнего проекта в сайдбаре. Если папки нет, рабочее место покажет `Project folder not found…` (проверка перед стартом, D3 `require-project-folder`).
- **Нет ни того, ни другого** (новая установка) — шаг как экран 11a без InfoBar, с «Skip for now».

Восстановление асинхронно и может завершиться, пока шаг уже показан: строка `Last project` и `Continue…` появляются, когда `selectedProjectPath` становится непустым. Если пользователь успел выбрать папку сам, восстановление уступает его выбору (существующее правило `SettingsCubit._restoreProject`). «Skip for now», нажатый до конца восстановления, ведёт себя по D2 (восстановленный проект откроется после перехода).

Почему шаг не пропускается при восстановленном проекте:
- строка шагов не меняет длину в зависимости от асинхронного результата: у шага модели пропуск решают факты, известные до шага 3, а восстановление может закончиться в любой момент;
- пользователь видит, в какой папке стартует агент, и может выбрать другую до первого старта. Это важно после переустановки, когда снимок мог остаться от другого сценария.

*Альтернативы:*
- (а) пропускать шаг, если проект восстановлен: «Privacy» снова с «Start using CodeLab». Кнопка «Privacy» и длина строки шагов зависели бы от гонки с восстановлением, а пользователь не узнал бы, где стартует агент. Отклонено;
- (б) не показывать недавние на шаге — у шага нет сайдбара, и после переустановки пользователю пришлось бы снова искать папку в диалоге. Отклонено;
- (в) показывать все недавние — список может быть длинным, а шаг должен помещаться в окно 800×600 без потери кнопок. Число пять — решение пользователя 2026-11-22 (Q2).

### D4. Переиспользование организма: тело `CodeLabOpenProjectBody` и обёртка экрана

Организм `CodeLabOpenProjectScreen` (`add-empty-project-screen`, D1) сам центрирует колонку, прокручивает её (`SingleChildScrollView`) и рисует героя, заголовок и InfoBar. Внутри onboarding так нельзя:
- onboarding уже прокручивает весь экран, и вложенная вертикальная прокрутка без ограничения высоты падает при раскладке;
- заголовок шага onboarding — `Focus` с узлом `titleFocus` (D14 `add-app-onboarding`): экранный диктор читает его первым;
- InfoBar про Cmd/Ctrl+N на onboarding неверен: там нет такой привязки;
- ссылка `Change in Settings › Connection` на onboarding ничего бы не сделала: `openSettings` там — no-op.

Решение — разделить организм на две части:
- `CodeLabOpenProjectBody` (новый публичный организм в том же файле или рядом): пояснение, строка «Open folder…» с подсказкой, зона перетаскивания, карточка агента. Без прокрутки, центрирования, героя, заголовка и InfoBar. Параметры `settingsLinkLabel` и `onOpenSettings` необязательны и задаются только вместе (`assert`): без них ссылки в карточке нет. Ключи `start-open-project`, `open-project-drop-zone`, `open-project-drop-message`, `open-project-agent`, `open-project-agent-settings` переходят в тело;
- `CodeLabOpenProjectScreen` — прежний публичный API: Center, прокрутка, герой, заголовок, `CodeLabOpenProjectBody`, InfoBar. Его параметры и ключи не меняются, тесты экрана 11a остаются зелёными.

Строка `Last project` и блок `Recent projects` — раскладка шага в app (`features/onboarding/presentation/`) из существующих атомов кита и Fluent. Второго употребления у них пока нет, в кит они не выносятся (корневой §13, `codelab_ui/AGENTS.md` §3).

*Альтернативы:*
- (а) флаг `embedded: bool` у `CodeLabOpenProjectScreen` — две раскладки под флагом, то, от чего D1 `add-empty-project-screen` уже отказался. Отклонено;
- (б) новый организм шага — копия зоны и карточки с риском расхождения текстов, цветов и ключей. Отклонено;
- (в) встроить `CodeLabOpenProjectScreen` целиком в `SizedBox` фиксированной высоты — ломает прокрутку onboarding в низком окне и даёт второй заголовок. Отклонено.

### D5. Где живёт логика шага: `OnboardingCubit`, порт `OnboardingProjectPort` и удержание триггера в `SettingsCubit`

Правило «принятый выбор завершает onboarding» — политика application, а не виджета (корневой §6, §8). Само «что считается принятой папкой» уже есть в `SettingsCubit` (D4, D7 `add-empty-project-screen`), второй копии не будет.

**Порт** `OnboardingProjectPort` (`features/onboarding/application/onboarding_project_port.dart`), по образцу `OnboardingProbe` (D6 `add-app-onboarding`):
- `Future<String?> pickFolder()` — системный выбор папки; путь принятой папки или `null` (отмена, сбой диалога);
- `Future<String?> openDropped(List<String?> paths)` — бросок; путь принятой папки или `null` (отказ: его текст уже в состоянии `SettingsCubit`);
- `Future<String?> openRecent(String path)` — недавний проект;
- `String? get selectedProject` — выбранный (восстановленный) проект.

Адаптер — `lib/app/onboarding_project_port.dart` поверх фасада `CodeLabShellCubit`, привязка в `app_scope.dart`. Почему порт, а не прямой импорт `CodeLabShellCubit` в `OnboardingCubit`:
- application onboarding не зависит от application рабочего места;
- тест Cubit-а — с одной подделкой порта, без графа рабочего места.

**API шага в `OnboardingCubit`.** Публичные действия — `openFolder()`, `openDropped(paths)`, `openRecent(path)`, `continueWithProject()`, `skip()`; публичного `finish` нет (D2). Первые три вызывают порт через общий приватный `_choose` (фаза `choosing`, D6) и, только если порт вернул путь, вызывают `_complete` с `ProjectChosen(picker | drop | recent)`. Проверку «есть проект / нет проекта» делают сами действия, а не виджет:
- `continueWithProject()` завершает с `ProjectRestored`, только если `selectedProject` порта непуст; иначе вызов ничего не делает;
- `skip()` завершает с `ProjectSkipped`, только если `selectedProject` пуст; иначе вызов ничего не делает: при выбранном проекте шаг предлагает `Continue…`, а не пропуск, и пропуск не может записать `project: skipped` при проекте, который стартует агента.

Presentation шага читает `CodeLabShellState` (профиль окна, вид транспорта, недавние, `dropRejection`) через `BlocBuilder<CodeLabShellCubit>` и вызывает `clearDropRejection` при входе перетаскивания. Это чтение готового состояния, политики в нём нет. Тот же импорт уже есть у `features/usage/presentation`. Функции текста (`openProjectDescriptionOf`, `agentCardDetailOf`, `projectDropRejectionText`) переиспользуются из `features/workbench/presentation/widgets/open_project_screen.dart`. Если импорт тянет лишнее, исполнитель выносит их в `open_project_texts.dart` рядом, без изменения содержания.

**Изменения `SettingsCubit`:**
- `browseForProject()` возвращает `Future<String?>` — принятую папку или `null`. Общий `_picking` (один диалог, D7 `add-empty-project-screen`) получает тот же тип. Вызывающие с `unawaited` не меняются;
- `openDroppedPaths()` возвращает `Future<String?>` — принятую папку или `null` при отказе, пустом списке и устаревшем результате;
- **удержание триггера выбора.** Конструктор получает `projectStartHeld` (из `OnboardingStart.show`, через сборку частей). Пока удержание действует, `_selectProject` делает всё, кроме вызова `_onProjectSelected`: состояние, `ClientWorkspace.selectProject`, недавние, диагностику `Selected project: …`. Вместо вызова триггера пишется событие `project.start_held` уровня debug без пути. `releaseProjectStart()` снимает удержание и сам агента не стартует.

`CodeLabShellCubit.startOnLaunch()` первым шагом вызывает `releaseProjectStart()`, затем `ConnectionCubit.startOnLaunch()`. Тот ждёт `awaitProject()` и стартует агента в выбранной папке: восстановленной или выбранной на шаге. Значит:
- старт агента после onboarding один, и это прежний триггер D5 `add-app-onboarding`;
- `_CodeLabHome` и `NavigationCubit` не меняются;
- выбор после перехода на рабочее место — обычный триггер 1: удержание уже снято.

Почему удержание в `SettingsCubit`, а не проверка «показан ли onboarding» в `ConnectionCubit`: на onboarding единственный достижимый триггер — выбор проекта. «New session», фокус сессии и «Retry» живут в рабочем месте, которое не строится. Держать нужно ровно этот вызов, а Cubit соединения не должен знать о навигации.

*Альтернативы:*
- (а) шаг вызывает `SettingsCubit` как есть, а `OnboardingCubit` по изменению `selectedProjectPath` завершает onboarding. Агент стартовал бы под onboarding до записи флага (нарушение D5 `add-app-onboarding`), а восстановление из снимка нельзя было бы отличить от выбора пользователя. Отклонено;
- (б) `OnboardingCubit` сам вызывает `ProjectFolderPicker` и `LocalPathKindOf` и передаёт путь в рабочее место после перехода. Правила отказов броска пришлось бы вынести из `SettingsCubit` или скопировать, недавние и снимок писались бы позже выбора, а при закрытии app между выбором и переходом выбор терялся бы. Отклонено;
- (в) отвязать `bindProjectStart` на время onboarding и привязать заново при переходе. Привязка — единственная связь частей, её перепривязка из навигации размазывает правило по сборке. Именованное удержание с событием в журнале проверяется тестом. Отклонено.

### D6. Ошибки, отмена и гонки

- **Отмена системного диалога** — `pickFolder()` возвращает `null`. Шаг остаётся, флаг не пишется. Пишется `onboarding.project_pick_cancelled` (debug).
- **Сбой диалога** — исключение платформы ловит `SettingsCubit`: пишет диагностику `Failed to open the folder picker.` и `project.picker_failed {error_class}` (D7 `add-empty-project-screen`) и возвращает `null`. Для порта и `OnboardingCubit` это неотличимо от отмены: шаг остаётся, флаг не пишется, пишется `onboarding.project_pick_cancelled`. Значит, `onboarding.project_pick_cancelled` означает «диалог не вернул папку» (отмена или сбой), а сбой дополнительно отмечен `project.picker_failed`. Отдельного текста на шаге нет, как и на экране 11a. Повтор — снова «Open folder…».
- **Исключение адаптера порта.** Порт по контракту не бросает. Если адаптер всё же бросил (`pickFolder`, `openDropped` или `openRecent`), `OnboardingCubit` считает это непринятым выбором: фаза возвращается в `idle`, шаг остаётся, флаг не пишется. Пишется `onboarding.project_port_failed {error_type}` (warning) — только имя типа, без текста ошибки и путей. `onboarding.project_pick_cancelled` при этом НЕ пишется: это не исход диалога, а дефект адаптера, и смешивать их в журнале нельзя.
- **Файл, несколько элементов, пропавший путь, не-локальный или относительный путь, элемент без пути** — отказы `SettingsCubit.openDroppedPaths` с теми же текстами в зоне (`open-project-drop-message`), той же диагностикой и событием `project.drop`. Шаг остаётся, флаг не пишется. Текст отказа снимается новым входом перетаскивания или выбором.
- **Папка недоступна (нет прав).** Вид пути определяет `FileSystemEntity.type`. Если каталог существует, но не читается, бросок принимается как папка, как и выбор в диалоге. Ошибку доступа покажет старт агента в рабочем месте. Отдельной проверки прав шаг не вводит: её нет и у «Open folder…».
- **Один выбор за раз.** Пока выполняется `pickFolder`, `openDropped` или `openRecent`, состояние шага — `ProjectStepPhase.choosing`. «Open folder…», «Back», «Skip for now», `Continue…`, записи недавних, повторный бросок и ⌘O не действуют, и кнопки это показывают. То же — во время записи флага (`finishing`): кнопка «Open folder…» неактивна, как и остальные действия шага. Повторный ⌘O второй диалог не откроет и сам по себе: общий `_picking` `SettingsCubit`.
- **Поздний результат.** Если `OnboardingCubit` закрыт, пока порт отвечает (выход из app), результат отбрасывается по `isClosed`. Выбор, уже применённый `SettingsCubit`, остаётся, и при следующем запуске шаг предложит `Continue…` (D2, D3).
- **Восстановление и выбор.** Выбор пользователя побеждает восстановление: `_restoreProject` не перезаписывает `selectedProjectPath`.

Состояние шага — поле `project: ProjectStepPhase` (`idle | choosing`) в `OnboardingState`, по образцу `ModelWizard { idle, active }`. Завершение по-прежнему отмечает `finishing`. Независимых флагов, дающих невозможные состояния, нет: `choosing` и `finishing` не пересекаются, потому что `_complete` вызывается только после того, как выбор вернул путь, и сам переводит фазу в `idle` вместе с `finishing`.

### D7. Клавиатура, фокус и перетаскивание на шаге

- При показе шага фокус — на заголовке `Open a project` (D14 `add-app-onboarding`). Порядок Tab: «Open folder…», ссылки недавних, «Back», затем «Skip for now» или `Continue…`.
- ⌘O/Ctrl+O (`CodeLabShortcut.openFolder.bind`) действует только на шаге «Open a project». Привязку ставит экран onboarding, когда шаг — `project`, и пока нет просмотра документа. На остальных шагах сочетание ничего не делает, как раньше.
- Подсказка у «Open folder…» строится из той же записи каталога (`compactFor(defaultTargetPlatform)`). Требование app-settings «Сочетания app и страница «Keyboard» не расходятся» выполняется: подсказка соответствует действующей привязке. Строка `open-folder` на странице «Keyboard» остаётся с «Where» `Workbench`. Onboarding — разовый экран, страница «Keyboard» с него недоступна, и другие сочетания onboarding там тоже не перечислены. Решение пользователя 2026-11-22 (Q3): страница «Keyboard» не меняется.
- ⌘N на onboarding по-прежнему не привязан. Поэтому InfoBar 11a на шаге не показывается.
- Esc не закрывает onboarding, ⌘, не открывает настройки (без изменений).
- `OsDropRegion` оборачивает экран onboarding, пока показан шаг `project`: бросить папку можно в любой точке экрана, как на 11a. На остальных шагах региона нет, и бросок ничего не делает. Состояние «элементы над экраном» (`dropActive`) — временное состояние `State`, как в `WorkbenchOpenProjectScreen`.

### D8. Наблюдаемость

Логгер `codelab_desktop.onboarding` (D13 `add-app-onboarding`) получает:

| Событие | Уровень | Поля |
|---|---|---|
| `onboarding.step_shown` | debug | `step` — добавляется значение `project` |
| `onboarding.project_pick_cancelled` | debug | — |
| `onboarding.project_port_failed` | warning | `error_type` — имя типа исключения адаптера порта (D6) |
| `onboarding.completed` | info | `model_step` (как раньше), `project`: `picker`, `drop`, `recent`, `restored`, `skipped` |

`onboarding.project_pick_cancelled` пишется только для системного диалога («Open folder…», ⌘O), когда он не вернул папку — отмена или сбой (D6). Для броска и недавних его нет: отказ броска уже даёт `project.drop` с исходом от `SettingsCubit`, а недавний проект без результата отдельного события не пишет. `onboarding.project_port_failed` пишется для любого действия выбора, если адаптер порта бросил исключение, и не сопровождается `onboarding.project_pick_cancelled`.

Логгер app (`_appLogger`, компонент `app`) получает от `SettingsCubit` событие `project.start_held` (debug) без полей. События `project.drop`, `project.picker_failed` и диагностика `Selected project: <path>` остаются прежними: шаг их не дублирует.

В событиях onboarding нет путей и имён папок. Путь проекта есть только в диагностике app (`Selected project: …`), как при выборе на экране 11a.

### D9. Пакеты, слои, сторож, граф

| Пакет (ADR-0002) | Слой | Что меняется |
|---|---|---|
| `codelab_ui` (`packages/flutter`) | organisms | `CodeLabOpenProjectBody`; `CodeLabOpenProjectScreen` строится из него; ссылка настроек карточки необязательна |
| `codelab_desktop` (`apps/`) | `features/onboarding/application` | `OnboardingStep.project`, `ProjectStepPhase`, `OnboardingProjectExit`, порт `OnboardingProjectPort`, `OnboardingCubit` |
| `codelab_desktop` | `features/onboarding/presentation` | шаг «Open a project», кнопки, ⌘O, `OsDropRegion` на шаге |
| `codelab_desktop` | `features/workbench/application` | результат `browseForProject`/`openDroppedPaths`, удержание триггера выбора, снятие удержания в `CodeLabShellCubit.startOnLaunch` |
| `codelab_desktop` | `app/` | адаптер `onboarding_project_port.dart`, привязка в `app_scope.dart`, `projectStartHeld` при сборке частей |

`codelab_client_*`, `codelab_agent_*`, `codelab_acp_*`, `codelab_embedded`, `codelab_setup` не меняются.

Направление зависимостей:
- `features/onboarding/presentation` → `features/onboarding/application` → порт;
- адаптер в `lib/app/` → фасад рабочего места;
- presentation onboarding → `features/workbench/application` (только чтение состояния) и `core/platform/os_drop_region.dart`.

**Сторож:** новых правил нет.
- `PackageRule('apps/codelab_desktop/lib/features/onboarding', forbidden: ['dart:io'])` остаётся в силе: шаг получает файлы и диалог только через порт и адаптер;
- `package:desktop_drop/` по-прежнему импортирует только `core/platform/os_drop_region.dart` (правило `add-empty-project-screen`); onboarding импортирует адаптер, а не плагин.

**Граф в `README.md`** не меняется: новых рёбер между пакетами нет. **PKG-2** не затронут. **Web-безопасность:** web-безопасные барели не меняются, `web-compile` не нужен.

### D10. Канвас Claude Design

Кадра шага «Open a project» в onboarding в канвасе нет. Граф `NavOnboarding` ведёт из 07a «Start using CodeLab» в рабочее место. Экспорт `docs/design/claude-design/` односторонний: правки в каталоге в канвас не уходят (`README.md` экспорта). Поэтому:
- этот change экспорт не меняет;
- источник вида шага до нового экспорта — кадр 11a (`ProjectsEmpty.dc.html`, `-dark`) для тела и кадры 07* для раскладки onboarding (шапка, строка шагов, кнопки внизу);
- пользователь добавляет в канвас кадры шага (рабочее название 07d, светлый и тёмный; состояния «новая установка», «есть недавние», «проект восстановлен», «отказ броска»), правит граф `NavOnboarding` (07a «Next» → 07d; 07d → рабочее место с проектом, «Skip for now» → 11a, «Back» → 07a) и снимает экспорт заново (tasks.md, раздел U);
- после экспорта `codelab-architect` сверяет spec-дельты с кадрами (задача 7.1). Расхождения в текстах решаются до архивации change.

### D11. Итерации и исполнители

Все кодовые задачи — `[desktop]` (`apps/codelab_desktop`, `packages/flutter/codelab_ui`). Задач `[protocol]`, `[agent]`, `[client]` нет. Порядок:
0. документы: `docs/architecture/` — `codelab-architect`, `AGENTS.md` приложения и кита — `[desktop]`;
1. кит (тело организма);
2. application (`SettingsCubit`, порт, `OnboardingCubit`);
3. presentation и composition root;
4. сценарий приложения и интеграционный тест;
5. продуктовая документация (`docs-writer`);
6. проверки;
7. сверка с канвасом.

Канвас (раздел U) делает пользователь параллельно; он блокирует только задачу 7.1 и архивацию.

## Risks / Trade-offs

- **[Гонка восстановления и пропуска]** «Skip for now» до конца восстановления открывает рабочее место, а восстановленный проект стартует агента. → Это прежнее поведение запуска, D2 его фиксирует, сценарий «Пропуск при восстановлении» в spec.
- **[Агент под onboarding]** Ошибка в удержании запустит агента до записи флага. → Красные тесты 2.1 и 4.1: открыватель встроенного агента не вызывается до перехода на рабочее место, после — ровно один раз.
- **[Двойной старт]** Выбор на шаге и `startOnLaunch` могли бы стартовать агента дважды. → Удержание: выбор под onboarding триггер не вызывает, стартует только `startOnLaunch`. Правило «параллельные триггеры — один транспорт» (`require-project-folder`, D17) остаётся второй линией.
- **[Недавний проект без папки]** Нажатие на исчезнувший недавний проект завершает onboarding, а рабочее место показывает `Project folder not found`. → Так же ведёт себя сайдбар. Проверку до завершения пользователь отклонил 2026-11-22 (Q2).
- **[Удержание без снятия]** При `CodeLabApp(startOnLaunch: false)` (только тесты) `startOnLaunch` не вызывается, и удержание триггера выбора (D5) не снимается: выбор после onboarding агента не стартует. → Флаг существует только для тестов; в сборке app он всегда `true`.
- **[Канвас отстаёт]** До нового экспорта вид шага собирается из 11a и 07*. → Задача 7.1 и блокировка архивации (D10).
- **[Порядок архивации]** Дельта agent-workbench-ui изменяет требования, которые добавляет `add-empty-project-screen`. → Архивация строго после него (proposal, «Зависимость»).
- **[Существующие пользователи]** Пользователь, у которого флага ещё нет (обновление с версии без onboarding), увидит пять шагов. Если проект восстановлен, последний шаг — один клик `Continue in <name>`.

## Migration Plan

Миграции данных нет. Ключ `codelab.app.onboarding_done` прежний, значение то же. Пользователь, прошедший onboarding из четырёх шагов, шаг 5 не увидит: флаг уже записан. Откат change возвращает «Start using CodeLab» на «Privacy». Флаг и недавние проекты при этом остаются совместимыми.

## Решения пользователя

Пользователь одобрил change и предложенные варианты Q1–Q5 2026-11-22. Ни один ответ не меняет поведение, описанное в spec-дельтах, поэтому дельты не правятся.

| # | Решение | Где отражено |
|---|---|---|
| Q1 | (а) подпись пропуска — `Skip for now` / «Пока пропустить» | D2; spec app-onboarding; `l10n-glossary.md` §Onboarding (задача 0.3) |
| Q2 | (а) до пяти недавних, без проверки существования папки, как в сайдбаре | D3; Risks «Недавний проект без папки» |
| Q3 | (а) страница «Keyboard» не меняется: строка `open-folder` остаётся с «Where» `Workbench`, MODIFIED spec app-settings нет | D7 |
| Q4 | (а) реализация идёт параллельно с правкой канваса; сверка 7.1 блокирует архивацию | D10; tasks.md 7.1, раздел U |
| Q5 | (а) строка `Last project` — имя папки и полный путь, как в сайдбаре | D3; spec app-onboarding «Шаг «Open a project»» |

## Open Questions

Открытых вопросов нет: Q1–Q5 закрыты решениями пользователя 2026-11-22 (раздел выше).
