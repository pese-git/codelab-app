## Исполнители

- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`.
- `[client]` — задач нет: `codelab_client_core`, `codelab_client_io`, `codelab_client_acp` не меняются (design.md D9).
- `[protocol]` — задач нет: ACP, модели и фикстуры не меняются.
- `[agent]` — задач нет: ядро, мосты `codelab_setup` и `codelab_embedded` не меняются.
- `[site]` — задач нет: руководство app публикуется сайтом без копий, его проверяет джоб `site` в CI.

Задачи документации без метки выполняет `codelab-architect` (`docs/architecture/`) или `docs-writer` (продуктовые документы): исполнитель указан в задаче. Правки `AGENTS.md` приложения и кита (0.1, 0.4) — `[desktop]`: эти файлы в зоне desktop-engineer. Задачи раздела U выполняет пользователь.

Предусловие: PR #426 (`add-empty-project-screen`) влит в develop. Ветка — `feature/add-onboarding-project-step` от develop после merge.

TDD (`packages/dart/codelab_agent_core/AGENTS.md` §2): красный тест — отдельная задача до кода. Коммит красного теста — отдельно и только по просьбе пользователя. Задача реализации ссылается на свой красный тест.

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21):
- `fvm dart format` изменённых файлов;
- `fvm flutter analyze` в `apps/codelab_desktop` и `packages/flutter/codelab_ui`;
- тесты изменённых файлов (`fvm flutter test` в пакете);
- `l10n:check` — при правке ARB;
- `guard` — не нужен: `pubspec.yaml`, правила сторожа и импорты между пакетами не меняются. Если исполнитель всё же добавит импорт между пакетами, `guard` запускается;
- `test:e2e:cli:dart-agent`, `web-compile`, `conformance:*` — не нужны: клиентский слой, web-безопасные пакеты и ACP не меняются.

Все тесты — на Dart VM (`flutter test`). `integration_test/onboarding_flow_test.dart` обновляется в этом change, но на устройстве запускается только в `release/*` (`AGENTS.md` §21).

## 0. Документы

- [x] 0.1 `[desktop]` `apps/codelab_desktop/AGENTS.md`, раздел «Onboarding» — пятый шаг (design.md D1), порядок завершения «выбор → флаг → навигация → старт» (D2), порт `OnboardingProjectPort` и удержание триггера выбора в `SettingsCubit` (D5). Абзац «Старт агента (D5)» дополнить: удержание снимает `CodeLabShellCubit.startOnLaunch`, не возвращать старт агента внутрь onboarding.
- [x] 0.2 `codelab-architect`: `docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` §12.4.9 — список шагов onboarding app (пятый шаг, ссылка на change); `docs/architecture/proposals/delivery-roadmap.md`, строка 07 таблицы экранов — «пять шагов, последний — выбор проекта».
- [x] 0.3 `codelab-architect`: `docs/architecture/l10n-glossary.md` — `Skip for now`, `Last project`, `Continue in <folder>` (предложение; вычитка `ru` — задача 5.3).
- [x] 0.4 `[desktop]` `packages/flutter/codelab_ui/AGENTS.md` — если там перечислены организмы, добавить `CodeLabOpenProjectBody` рядом с `CodeLabOpenProjectScreen` (D4).

## 1. Кит `codelab_ui`

- [x] 1.1 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_open_project_screen_test.dart` — новая группа `CodeLabOpenProjectBody`. Тело рисует пояснение, «Open folder…» с подсказкой, зону и карточку с прежними ключами. Без `settingsLinkLabel`/`onOpenSettings` ссылки `open-project-agent-settings` нет. Задан только один из двух параметров — `assert`. В неограниченной по высоте колонке (`SingleChildScrollView` снаружи) тело строится без ошибок раскладки. Прежние тесты `CodeLabOpenProjectScreen` не меняются и остаются зелёными (design.md D4; spec app-onboarding «Шаг «Open a project»», п. 4–6).
- [x] 1.2 `[desktop]` Реализация 1.1: `CodeLabOpenProjectBody` в `lib/src/organisms/codelab_open_project_screen.dart` (или соседнем файле, экспорт в `organisms.dart`). `CodeLabOpenProjectScreen` строится из тела. Пример в `codelab_organism_previews.dart`: тело без ссылки и без InfoBar. Doc-комментарии по §15. 1.1 зелёный.

## 2. Application app

- [x] 2.1 `[desktop]` Красный: `test/features/workbench/application/project_start_hold_test.dart`. Spec agent-workbench-ui «Агент стартует сам», сценарии «Папка, выбранная на шаге onboarding» и «Выбор после onboarding — обычный триггер»; design.md D5:
  - `SettingsCubit(projectStartHeld: true)`: `selectProject`, принятый `browseForProject` и принятый `openDroppedPaths` меняют `selectedProjectPath`, пишут недавние и `Selected project: …`, но не вызывают привязанный триггер; журнал app содержит `project.start_held` без пути;
  - после `releaseProjectStart()` следующий выбор вызывает триггер; сам `releaseProjectStart()` триггер не вызывает;
  - `CodeLabShellCubit.startOnLaunch()` снимает удержание до `ConnectionCubit.startOnLaunch()`: выбор под удержанием даёт ровно один старт с этой папкой;
  - без удержания (`projectStartHeld: false`) поведение прежнее.
- [x] 2.2 `[desktop]` Красный: дополнить `test/features/workbench/application/project_drop_test.dart` и тест выбора папки. `browseForProject()` возвращает принятую папку или `null` (отмена, сбой порта); общий `_picking` возвращает тот же результат второму вызывающему. `openDroppedPaths()` возвращает принятую папку или `null` при каждом отказе, пустом списке и устаревшем результате (design.md D5, D6).
- [x] 2.3 `[desktop]` Реализация 2.1–2.2: `SettingsCubit` (`projectStartHeld`, `releaseProjectStart`, результаты методов), передача признака через сборку частей (`CodeLabShellParts`), снятие удержания в `CodeLabShellCubit.startOnLaunch`. 2.1, 2.2 и прежние тесты `SettingsCubit`, `project_drop_test.dart`, `create_session_project_test.dart` зелёные.
- [x] 2.4 `[desktop]` Красный: `test/features/onboarding/application/onboarding_cubit_project_test.dart` с подделкой `OnboardingProjectPort` и `OnboardingPreferences`. Spec app-onboarding «Шаги onboarding и переходы», «Шаг «Open a project»», «Завершение onboarding и старт рабочего места»; design.md D1, D2, D6:
  - «Next» на `privacy` → `project`, «Back» на `project` → `privacy`; `onboarding.step_shown {step: project}`;
  - `finish()` без аргумента и с шага, отличного от `project`, ничего не делает;
  - `openFolder()`: принятая папка → `markDone` вызван после ответа порта → `onFinished` один раз, `onboarding.completed {project: picker}`; `null` → шаг на месте, `markDone` не вызван, `onboarding.project_pick_cancelled`;
  - `openDropped(paths)`: принятая → `project: drop`; `null` → шаг на месте, флаг не пишется;
  - `openRecent(path)` → `project: recent`;
  - `continueWithProject()` при `selectedProject != null` → `project: restored`; при `null` — ничего;
  - `skip()` при `selectedProject == null` → `project: skipped`;
  - пока порт не ответил (`ProjectStepPhase.choosing`), `back`, `skip`, `continueWithProject`, `openFolder`, `openDropped`, `openRecent` игнорируются, порт вызван один раз;
  - двойной `skip()` → одна запись флага, один `onFinished`, одно `onboarding.completed`;
  - сбой `markDone` → `onboarding.save_failed`, затем `onboarding.completed` и `onFinished`;
  - закрытие Cubit-а во время ответа порта и во время `markDone` → без `onFinished`, без событий, без исключений;
  - `onboarding.completed` по-прежнему содержит `model_step`.
- [x] 2.5 `[desktop]` Реализация 2.4: `OnboardingStep.project`, `ProjectStepPhase`, `OnboardingProjectExit`, `OnboardingState.project`, порт `features/onboarding/application/onboarding_project_port.dart`, методы `OnboardingCubit`. Новый обязательный параметр конструктора `project:`. Существующие тесты `OnboardingCubit` переходят на поддельный порт; их проверки `finish()` на `privacy` переписываются на переход «Next» (spec «Шаги onboarding и переходы»). 2.4 и обновлённые тесты зелёные.

## 3. Presentation и composition root

- [x] 3.1 `[desktop]` Красный: `test/features/onboarding/presentation/onboarding_project_step_test.dart`. Виджет-тесты экрана onboarding с подделками порта и состояния рабочего места. Spec app-onboarding «Шаг «Open a project»» — сценарии «Новая установка», «Проект восстановлен из снимка», «Не более пяти недавних», «Внешний профиль», «Брошенный файл не завершает onboarding», «Несколько элементов», «Бросок на другом шаге», «Навигация во время выбора», «Сочетание на других шагах», «Русский интерфейс и низкое окно»:
  - строка шагов — пять подписей; на `privacy` — `onboarding-next`, ключа `onboarding-finish` нет нигде;
  - фокус при показе шага — на заголовке;
  - `OsDropRegion` есть только на шаге `project`; колбэки найденного адаптера вызываются напрямую, как в `open_project_screen_test.dart`;
  - Ctrl+O и ⌘O вызывают выбор только на шаге `project` и не при открытом документе;
  - тёмная тема, 800×600, `ru` — без переполнения.
- [x] 3.2 `[desktop]` Реализация 3.1: шаг в `features/onboarding/presentation/` (`onboarding_steps.dart` или новый `onboarding_project_step.dart`), кнопки шага в `OnboardingNavigation`, привязка `CodeLabShortcut.openFolder` и `OsDropRegion` на экране при шаге `project`. Тексты — ARB `en`/`ru` с префиксом `onboardingProject*` и `@key.description`; `onboardingFinish` удаляется. Функции текста профиля и отказов переиспользуются из `features/workbench/presentation/widgets/open_project_screen.dart` (при необходимости вынести в `open_project_texts.dart` без изменения содержания; D5). 3.1 зелёный, `l10n:check` зелёный.
- [x] 3.3 `[desktop]` Красный: тест композиции onboarding (`test/app/` рядом с существующими тестами onboarding или `test/widget_test.dart`) через `CodeLabTestBinding(onboarding:)` с настоящим графом рабочего места и поддельным открывателем встроенного агента. Spec app-onboarding «Завершение onboarding и старт рабочего места» — сценарии «Папка с шага стартует агента после перехода», «Проект восстановлен, агент ждёт конца onboarding», «Закрытие во время записи флага», «Флаг не записался», «Выбор не принят — флаг не пишется»; spec agent-workbench-ui «Агент стартует сам», сценарии «Восстановленный проект при первом показе onboarding» и «Папка, выбранная на шаге onboarding»; spec app-onboarding «Шаг «Open a project»», сценарии «Пропуск шага» и «Пропуск при незавершённом восстановлении». Проверка: открыватель не вызывается до `WorkbenchDestination`, после — ровно один раз с нужной папкой; после «Skip for now» без проекта показан `open-project-screen`.
- [x] 3.4 `[desktop]` Реализация 3.3: адаптер `lib/app/onboarding_project_port.dart` поверх фасада `CodeLabShellCubit`; привязка порта и `projectStartHeld` (из `OnboardingStart.show`) в `app_scope.dart` (`CodeLabOnboardingModule` и сборка частей рабочего места). `_CodeLabHome` и `NavigationCubit` не меняются (D5). 3.3 зелёный; прежние тесты onboarding и рабочего места зелёные.
- [x] 3.5 `[desktop]` Красный, затем реализация: тест журнала onboarding — spec app-onboarding «События журнала onboarding без секретов и путей», сценарий «Полный проход без утечек» с папкой `/tmp/codelab-project-marker` (D8). Реализация — только если тест выявил утечку.
- [x] 3.6 `[desktop]` Красный, затем реализация: тест шага «What CodeLab does» (`test/features/onboarding/presentation/onboarding_screen_test.dart` или соседний) — spec app-onboarding «Шаг «What CodeLab does»», сценарий «Сноска называет пять шагов» (`en` и `ru`). Реализация — `onboardingWelcomeFootnote` в `lib/l10n/app_en.arb` (`Setup takes five short steps. You can change every choice later in Settings.`) и `app_ru.arb` (`Настройка занимает пять коротких шагов. Любой выбор можно изменить позже в настройках.`; `l10n-glossary.md`, раздел «Onboarding»), перегенерация `app_localizations*.dart`. Ключи записей недавних `onboarding-project-recent-<i>` проверяются в 3.1 (сценарий «Не более пяти недавних»). Тест зелёный, `l10n:check` зелёный.
- [x] 3.7 `[desktop]` Красный, затем реализация: при восстановленном проекте (кадр 07d.2) кнопка «Open folder…» (`start-open-project`) — вторичная, основная — «Continue in <папка>» (`onboarding-project-continue`); без восстановленного проекта «Open folder…» остаётся основной. Кит: параметр выделения кнопки у `CodeLabOpenProjectBody`, API `CodeLabOpenProjectScreen` не меняется (решение пользователя 2026-11-22 по итогам сверки 7.1).

## 4. Сценарий приложения

- [x] 4.1 `[desktop]` Обновить `integration_test/onboarding_flow_test.dart`: после «Privacy» — «Next», на шаге «Open a project» — выбор папки через тестовый порт выбора папки (как в `open_project_flow_test.dart`). Встроенный агент стартует один раз в выбранной папке после перехода. Запуск на устройстве — только в `release/*` (§21). В feature-ветке файл проверяется `fvm flutter analyze`.

## 5. Продуктовая документация (`docs-writer`)

- [x] 5.1 `docs-writer`: `apps/codelab_desktop/doc/user-guide.md`:
  - «Приветственные шаги» — пять шагов, шаг 5 «Open a project» (выбор папки, перетаскивание, недавние, `Continue in …`, `Skip for now`, ⌘O);
  - «Когда экран показывается» — флаг пишется в конце шага 5;
  - «Агент стартует после onboarding» — агент стартует в папке, выбранной на шаге;
  - «Первый запуск» — экран «Open a project» в рабочем месте появляется после «Skip for now» и в других случаях без проекта;
  - маркер снимка `doc/images/onboarding-project.png`.
- [x] 5.2 `docs-writer`: `apps/codelab_desktop/README.md` — «четыре приветственных шага» → пять, последний — выбор папки проекта; шаг «первый запуск» в разделе начала работы.
- [x] 5.3 `docs-writer`: вычитка `ru`-строк ARB шага по `l10n-glossary.md` (после 0.3 и 3.2).

## 6. Проверки

- [x] 6.1 `check-runner`: `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm flutter analyze` в `apps/codelab_desktop` и `packages/flutter/codelab_ui`; `fvm flutter test` в обоих пакетах (или затронутые файлы); `melos run l10n:check`. Полный `melos run check` — только по просьбе пользователя.
- [x] 6.2 `codelab-architect`: `openspec validate add-onboarding-project-step --strict`.

## 7. Сверка с канвасом

- [x] 7.1 `codelab-architect`: после нового экспорта (U.2) сверить тексты, порядок блоков и переходы spec-дельт этого change с кадрами шага и графом `NavOnboarding`. Расхождения — правка spec-дельты с согласия пользователя или задача пользователю на канвас. Блокирует архивацию (design.md D10). Итог 2026-11-22: расхождений в требованиях нет (класса «правка spec» нет). Решения пользователя 2026-11-22: устаревший граф `NavProject` («07b–07a Onboarding», переход «Start using CodeLab») и уточнения правил `NavOnboarding` (отказ броска и отмена диалога остаются на 07d; выход до выбора папки снова показывает onboarding), лишняя подсказка зоны в 07d.3 — отдельная задача пользователю на канвас вне этого change; «Open folder…» вторичная при восстановленном проекте — задача 3.7.


## U. Задачи пользователя

- [x] U.1 Пользователь: в канвасе Claude Design добавить кадры шага onboarding «Open a project» (рабочее название 07d; светлая и тёмная тема; состояния «новая установка», «есть недавние», «проект восстановлен — `Continue in …`», «отказ броска»). На 07a заменить «Start using CodeLab» на «Next». В графе `NavOnboarding`: 07a «Next» → 07d; 07d → рабочее место с проектом; «Skip for now» → 11a; «Back» → 07a.
- [x] U.2 Пользователь: снять экспорт канваса заново в `docs/design/claude-design/` (экспорт односторонний: правки каталога в канвас не уходят) и обновить строки 07a, 07d и `NavOnboarding` в `README.md` экспорта. Сделано 2026-11-22 (U.1 и U.2): кадры 07d, 07d.1–07d.3 со светлой и тёмной темой, 07a «Next», граф `NavOnboarding`, экспорт и `README.md` экспорта — PR #438.
- [x] U.3 Пользователь: ответить на Q1–Q5 design.md. `codelab-architect` закрепляет ответы в design.md (раздел «Решения пользователя») и, если ответ меняет поведение, — в spec-дельтах до начала раздела 2. Ответы 2026-11-22 — варианты (а) Q1–Q5, spec-дельты не менялись.
