## Why

Onboarding первого запуска (change `add-app-onboarding`, архив 2026-11-21) заканчивается кнопкой «Start using CodeLab» на шаге «Privacy». Она ведёт в рабочее место, где на новой установке проекта нет. Агент без папки не стартует (change `require-project-folder`, D13), поэтому первое, что видит пользователь после onboarding, — экран 11a «Open a project» (change `add-empty-project-screen`, PR #426). Получается два экрана подряд: onboarding рассказывает, что агент работает в папке проекта, но выбрать папку не даёт, а рабочее место потом просит выбрать её отдельно.

Если выбор проекта сделать последним шагом onboarding, первый запуск заканчивается в рабочем месте с проектом и запущенным агентом. Экран 11a при этом остаётся для всех остальных случаев без проекта: закрыты все проекты, папка пропала (11d), восстановление не успело за 2 с. Там нужен сайдбар с недавними проектами, а onboarding его не показывает.

## Зависимость

Change опирается на PR #426 (change `add-empty-project-screen`), влитый в develop merge-коммитом `dc171ebe`. Используются:
- организм кита `CodeLabOpenProjectScreen`;
- адаптер перетаскивания `OsDropRegion` (`desktop_drop` 0.8.4);
- `SettingsCubit.openDroppedPaths`, `browseForProject` и состояние `dropRejection`;
- порт `LocalPathKindOf` и проверка `isLocalAbsolutePath`;
- запись каталога `CodeLabShortcut.openFolder` (⌘O/Ctrl+O);
- требования agent-workbench-ui «Экран без выбранного проекта», «Открытие папки перетаскиванием», «Cmd/Ctrl+O открывает выбор папки».

Реализация начинается после merge #426. Архивировать этот change можно только после архивации `add-empty-project-screen`: дельта agent-workbench-ui изменяет требования, которые добавляет он.

## What Changes

- **Пятый шаг onboarding «Open a project»** (`onboarding-step-project`), после «Privacy» (design.md D1). Строка шагов показывает пять подписей. На «Privacy» вместо «Start using CodeLab» стоит «Next». Кнопка `onboarding-finish` и текст «Start using CodeLab» уходят.
- **Состав шага** (D4, D5). То же, что на экране 11a: заголовок `Open a project`, пояснение по профилю окна, «Open folder…» с подсказкой ⌘O/Ctrl+O, зона перетаскивания папки, карточка агента окна. Отличия от 11a:
  - у карточки нет ссылки `Change in Settings › Connection`: настройки на onboarding не открываются;
  - InfoBar про Cmd/Ctrl+N нет: на onboarding такой привязки нет;
  - есть блок недавних проектов, если они есть (D3).

  Организм `CodeLabOpenProjectScreen` делится на тело `CodeLabOpenProjectBody` и обёртку экрана. Шаг использует тело внутри раскладки onboarding.
- **Выбор папки завершает onboarding** (D2, D6). Папка из системного диалога, брошенная папка или недавний проект становится выбранным проектом сразу: недавние, снимок рабочего пространства, диагностика. Агент при этом не стартует, пока показан onboarding: `SettingsCubit` держит триггер старта до перехода на рабочее место. Затем пишется флаг `codelab.app.onboarding_done`, навигация переходит на рабочее место, и триггер старта при запуске (`startOnLaunch`) стартует агента в выбранной папке ровно один раз.
- **«Skip for now»** (D2). Шаг можно пропустить: флаг пишется, рабочее место открывается с экраном 11a, если проекта нет.
- **Проект прошлого запуска** (D3). Если при onboarding из снимка восстановлен проект (флаг сброшен, переустановка, обновление с версии без onboarding), шаг показывает `Continue in <folder name>` вместо «Skip for now». Выбрать другую папку можно и в этом случае.
- **Ошибки и отмена** (D6). Закрытый без выбора диалог, сбой диалога, брошенный файл, несколько элементов, пропавший путь и не-локальный путь оставляют шаг на месте, флаг не пишется. Тексты отказов и записи диагностики — те же, что на экране 11a.
- **Клавиатура** (D7). ⌘O/Ctrl+O на шаге «Open a project» открывает выбор папки. На остальных шагах onboarding сочетание по-прежнему ничего не делает. Пока выбор идёт, «Back», «Skip for now», «Continue…» и повторный выбор не действуют.
- **Журнал** (D8). У `onboarding.completed` появляется поле `project` (`picker`, `drop`, `recent`, `restored`, `skipped`). Новые события: `onboarding.project_pick_cancelled` и `project.start_held`. Путей в событиях нет.

### Для раздела выпуска `CHANGELOG.md`

- Первый запуск заканчивается выбором папки проекта: последний шаг приветствия предлагает открыть папку, перетащить её в окно или взять недавний проект, и рабочее место открывается уже с запущенным агентом. Шаг можно пропустить.

## Не входит

- **Экран 11a в рабочем месте** (`WorkbenchOpenProjectScreen`). Его вид, сайдбар и правила остаются как в `add-empty-project-screen`.
- **Диалог 11 «Project picker»**. ⌘O на шаге, как и на рабочем месте, открывает системный выбор папки.
- **Повторный показ onboarding**, сброс флага из настроек.
- **Смартфон и планшет** (P17–P20, T11–T14, этап 10).
- **Правка канваса Claude Design.** Экспорт в `docs/design/claude-design/` односторонний: кадр шага и граф `NavOnboarding` меняет пользователь в канвасе, затем экспорт снимается заново (tasks.md, раздел U). Этот change экспорт не правит.
- **Страница «Keyboard».** Строка `open-folder` остаётся с «Where» `Workbench` (D7).
- **ACP.** Новых методов, полей и `_meta` нет. Порядок «старт агента → `session/list`» и отсутствие `session/new` при выборе проекта не меняются.
- **Новые ключи хранения.** Флаг прежний. Недавние проекты и снимок пишутся существующими хранилищами.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `app-onboarding`:
  - ADDED «Шаг «Open a project»»;
  - MODIFIED «Шаги onboarding и переходы»: пять шагов, «Next» на «Privacy», «Back» с шага проекта;
  - MODIFIED «Шаг «Privacy»»: сценарии с «Start using CodeLab» переписаны на «Next»;
  - MODIFIED «Завершение onboarding и старт рабочего места»: завершение только на шаге проекта, порядок «выбор → флаг → навигация → старт», удержание триггера выбора;
  - MODIFIED «События журнала onboarding без секретов и путей»: поле `project`, пути проекта в событиях нет.
- `agent-workbench-ui`:
  - MODIFIED «Агент стартует сам»: выбор проекта на шаге onboarding — триггер 1, который срабатывает только после перехода на рабочее место;
  - MODIFIED «Cmd/Ctrl+O открывает выбор папки»: сочетание действует и на шаге onboarding «Open a project».

## Impact

- **Код** (`[desktop]`):
  - `packages/flutter/codelab_ui`: `CodeLabOpenProjectBody` (тело экрана 11a), `CodeLabOpenProjectScreen` строится из него; ссылка настроек у карточки необязательна;
  - `apps/codelab_desktop`:
    - `features/onboarding/application/`: `OnboardingStep.project`, состояние шага проекта, порт `OnboardingProjectPort`, `OnboardingCubit`;
    - `features/onboarding/presentation/`: шаг «Open a project», кнопки шага, ⌘O, `OsDropRegion` на шаге;
    - `features/workbench/application/`: удержание триггера выбора в `SettingsCubit`, результат `browseForProject` и `openDroppedPaths`, снятие удержания в `CodeLabShellCubit.startOnLaunch`;
    - `lib/app/`: адаптер `OnboardingProjectPort` поверх фасада рабочего места, привязка в `app_scope.dart`;
    - ARB `en`/`ru`.
- **Зависимости**: новых нет. Рёбер между пакетами `codelab_*` нет, граф в `README.md` не меняется. Allowlist ядра (PKG-2) не затронут. Web-безопасные пакеты не меняются.
- **Сторож**: новых правил нет. `features/onboarding` по-прежнему без `dart:io`, `desktop_drop` — только в `core/platform/os_drop_region.dart` (правило `add-empty-project-screen`).
- **ACP**: без изменений.
- **Данные пользователя**: новых ключей нет. Выбранная на шаге папка попадает в недавние и в снимок так же, как выбранная в «Open folder…». Флаг пишется в конце шага 5, а не шага 4.
- **Безопасность**: выбор на шаге — явное действие пользователя, как на экране 11a. Containment (`BoundedEnv`, проверка `fs/*`/`terminal/*`) и проверка «папка есть» перед стартом не меняются. Агент не стартует, пока показан onboarding (D5 `add-app-onboarding` сохраняется).
- **Канвас**: кадр шага и граф `NavOnboarding` правит пользователь, затем снимает экспорт заново (tasks.md, раздел U).
- **Документация**:
  - `apps/codelab_desktop/AGENTS.md`, раздел «Onboarding»;
  - `12-4-first-run-and-settings.md` §12.4.9;
  - `delivery-roadmap.md`, строка 07;
  - `l10n-glossary.md`;
  - для `docs-writer`: `apps/codelab_desktop/doc/user-guide.md` («Приветственные шаги», «Когда экран показывается», «Агент стартует после onboarding») и `apps/codelab_desktop/README.md` (первый запуск).
