## Исполнители

- `[agent]` — мост `codelab_setup` (мост агентской стороны, как в changes `add-provider-setup-ui` и `add-app-skills-page`): одно значение `ProviderWizardEntry.onboarding`;
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, правило сторожа app;
- `[client]` — задач нет: `codelab_client_core` и `codelab_client_io` не меняются;
- `[protocol]` — задач нет: ACP, модели и фикстуры не меняются;
- `[site]` — задач нет: руководство app публикуется сайтом без копий, его проверяет джоб `site` в CI.

Задачи документации без метки выполняет `codelab-architect` (`docs/architecture/`) или `docs-writer` (продуктовые документы), как указано в задаче.

TDD (`packages/dart/codelab_agent_core/AGENTS.md` §2): красный тест — отдельная задача до кода; коммит красного теста — отдельно и только по просьбе пользователя. Задача реализации ссылается на свой красный тест.

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` или `fvm flutter analyze` пакета;
- тесты пакета;
- `guard` — при правке `rules.dart` и импортов между пакетами;
- `web-compile` — при правке основного бареля `codelab_setup`;
- `l10n:check` — при правке ARB.

Интеграционный тест app в `feature/*` только компилируется.

## 0. Документы и решения

- [x] 0.0 Пользователь ответил на Q1–Q7 (2026-11-20): Q1–Q6 — (а), Q7 — (б), веха M4. `codelab-architect` закрепил ответы в design.md (раздел «Решения пользователя 2026-11-20», D17 «Веха M4») и proposal.md.
- [x] 0.1 `codelab-architect`: `12-4-first-run-and-settings.md` — §12.4.9, абзац «Onboarding app» (флаг D2, шаги, D5–D10, ветка навигации — решение Q1, веха M4, ссылка на change); §12.4.1, строка D-11. Попутно: `12-3-desktop-display.md` A13 (ветку Onboarding вводит этот change), `09-14-stage-9-switch-default.md` задача 9.6.
- [x] 0.2 `codelab-architect`: `delivery-roadmap.md` — таблицы определений продукта и вех (Could D-11 в M4), схема вех, §4.5 (объём и критерий выхода), §6.1 (абзац «Could в 1.0 — onboarding app»), §10.1 строка 07 (колонка M4), §10.3 (строки `add-app-navigation-shell` без Onboarding и `add-app-onboarding` — создан, M4).
- [x] 0.3 `codelab-architect`: `state-management.md` §63в «Onboarding app»; `concurrency.md` §47в «Onboarding app: факты, запись флага, отложенный старт агента».
- [x] 0.4 `codelab-architect`: `l10n-glossary.md`, раздел «Onboarding» (предложение; вычитка — задача 3.4).
- [x] 0.5 `codelab-architect`: `agent-parity-goals.md` — строка D-11 (change, spec, веха M4, приоритет Could сохранён); строка D-18 — ссылки шага «Privacy» включает второй из changes `add-app-onboarding` и `add-privacy-policy`.

## 1. Итерация 1 — флаг, навигация, значение `entry`

- [x] 1.1 `[agent]` Красный: `packages/dart/codelab_setup/test/provider_setup_flow_test.dart` — `ProviderSetupFlow(entry: ProviderWizardEntry.onboarding)` пишет `provider_wizard.started {entry: onboarding}`; переходы автомата совпадают с `entry: app` на одном сценарии (D11).
- [x] 1.2 `[agent]` Реализация 1.1: значение `onboarding('onboarding')` в `ProviderWizardEntry`; строка в `codelab_setup/AGENTS.md`. 1.1 зелёный, `web-compile` зелёный.
- [x] 1.3 `[desktop]` Красный: `apps/codelab_desktop/test/core/platform/onboarding_preferences_test.dart`. Spec app-onboarding «Показ onboarding при первом запуске»: нет ключа → показать; `true` → нет; «Повреждённое значение флага» (не перезаписан, `storedValueInvalid`); «Хранилище не читается» (`readFailure` — имя типа); `markDone` пишет `true`, ошибка записи пробрасывается (D2).
- [x] 1.4 `[desktop]` Реализация 1.3: `lib/core/platform/onboarding_preferences.dart` (`OnboardingPreferences`, `OnboardingLoad`, `SharedPreferencesOnboardingPreferences`). 1.3 зелёный.
- [x] 1.5 `[desktop]` Красный: `test/app/navigation/navigation_cubit_test.dart` — начальное `OnboardingDestination`; `openSettings` на onboarding ничего не меняет (`settings.open_skipped`); `finishOnboarding` → `WorkbenchDestination`, из других назначений — ничего; прежние сценарии навигации зелёные (spec app-onboarding «Шаги onboarding и переходы», сценарий «Esc и настройки на onboarding»; D1).
- [x] 1.6 `[desktop]` Реализация 1.5: `OnboardingDestination` в `app_destination.dart`, параметр `initial` и `finishOnboarding` у `NavigationCubit`. 1.5 зелёный.
- [x] 1.7 `[desktop]` Красный: `packages/dart/codelab_architecture_tests` — фикстура или проверка правила: `dart:io` в `apps/codelab_desktop/lib/features/onboarding/` — нарушение (spec workspace-architecture «Onboarding app без dart:io», оба сценария; D15).
- [x] 1.8 `[desktop]` Реализация 1.7: `PackageRule('apps/codelab_desktop/lib/features/onboarding', forbidden: ['dart:io'])` в `test/support/rules.dart`. 1.7 зелёный, `guard` зелёный.

## 2. Итерация 2 — `OnboardingCubit` и факты

- [x] 2.1 `[desktop]` Красный: `test/features/onboarding/application/onboarding_cubit_test.dart` на фиктивных часах и двойниках `OnboardingProbe`, `OnboardingPreferences`, `NavigationCubit`. Сценарии spec app-onboarding:
  - «Шаги onboarding и переходы»: «Проход без пропуска», «Back при пропущенном шаге модели»; таблица переходов D4 целиком; Next на шаге 2 при `Pending` ждёт итога, повторное нажатие не даёт второго перехода;
  - «Пропуск шага выбора модели»: «Провайдер уже настроен», «Внешний агент по умолчанию», «Медленное хранилище» (таймаут 5 с; поздний итог отброшен; итог после `close()` не даёт `emit`);
  - «Шаг «Choose a model» и мастер провайдера»: состояния `Choose(none|keyMissing|configBroken|unavailable)`, `Saved(summary)` из `Done(plan, committed)` без значения ключа (`toString()` состояния не содержит `sk-test-leak-…`), «Set up later», отмена мастера не меняет шаг;
  - «Завершение onboarding и старт рабочего места»: «Двойное нажатие», «Флаг не записался»;
  - события D13: набор и поля, без путей и имён секретов.
- [x] 2.2 `[desktop]` Реализация 2.1: `features/onboarding/application/` — `OnboardingCubit`, `OnboardingState` и закрытые иерархии D4, порт `OnboardingProbe` и `OnboardingFacts`, `OnboardingSavedSummary`. 2.1 зелёный.
- [x] 2.3 `[desktop]` Красный: `test/app/onboarding_probe_test.dart` на временном `CODELAB_HOME` (образец — `provider_setup_probe_test.dart`). Spec app-onboarding «Пропуск шага выбора модели» и «Шаг «Permissions»»:
  - пустой дом → `NoProviderConfigured`, режим `standard`, бэкенд `env`;
  - провайдер с `api_key_env` и заданной переменной → `ProviderReady`;
  - `api_key_secret` без секрета при `secrets.backend: file` → `ProviderKeyMissing`, бэкенд `file`;
  - `budget.max_steps: 0` → `ConfigBroken`;
  - `permissions.mode: bypass` → режим `bypass`;
  - WebSocket-профиль по умолчанию → `external`, конфиг не читается;
  - подписи путей с `~`;
  - значения ключей не читаются (двойник `ProviderKeys` без `read`).
- [x] 2.4 `[desktop]` Реализация 2.3: `lib/app/onboarding_probe.dart` поверх `DefaultProfileResolver`, `resolveSettingsAccess`, `ClientSecretAccess`, `FileAgentConfigStore`, `checkProviderReadiness`, `sessionDefaultsOf`, `homePathLabel` (D6). 2.3 зелёный.

## 3. Итерация 3 — экран, мастер, старт рабочего места

- [ ] 3.1 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_setup_steps_test.dart` — подписи, `✓` у пройденных, выделение текущего, перенос по ширине, семантика списка и текущего шага (D12).
- [ ] 3.2 `[desktop]` Реализация 3.1: `lib/src/molecules/codelab_setup_steps.dart`, экспорт, пример в превью кита, строка в `AGENTS.md` кита. 3.1 зелёный.
- [ ] 3.3 `[desktop]` Красный: widget-тесты `test/features/onboarding/presentation/onboarding_screen_test.dart` на `OnboardingCubit` с двойниками. Spec app-onboarding:
  - «Шаг «What CodeLab does»» — «Нет обещания связки ключей»;
  - «Шаг «Permissions»» — «Режим по умолчанию», «Режим из общего с CLI конфига», внешний профиль;
  - «Шаг «Choose a model» и мастер провайдера» — карточки по таблице пресетов мастера, «Только переменная окружения», «Битый конфиг» (кнопки неактивны), «Ключ не найден»;
  - «Шаг «Privacy»» — «Ключи из переменных окружения», «Ключи в файле», «Нечего принимать» (нет ссылок на документы);
  - «Локализация и доступность onboarding» — «Русский интерфейс», «Узкое окно», фокус на заголовке шага;
  - ключи тестов `onboarding-*`.
- [ ] 3.4 `[desktop]` Реализация 3.3: `features/onboarding/presentation/` — `OnboardingScreen`, виджеты шагов, тексты по фактам (D9), ARB `en` и `ru` (`onboarding*`). 3.3 зелёный, `l10n:check` зелёный; русские тексты вычитывает пользователь по разделу «Onboarding» `l10n-glossary.md`.
- [ ] 3.5 `[desktop]` Красный: `test/features/onboarding/presentation/onboarding_wizard_test.dart` на временном `CODELAB_HOME` с `secrets.backend: file` и тестовым сервером `/models` (образец — тесты мастера страницы Providers). Spec app-onboarding «Шаг «Choose a model» и мастер провайдера», сценарии «Провайдер с ключом в файле» (диалог начинается с «Base URL», `entry: onboarding`, «Make default» неснимаемый, нет «This project only»; маркер ключа не в журнале и не в состоянии onboarding) и «Отмена мастера».
- [ ] 3.6 `[desktop]` Реализация 3.5: `OnboardingWizardOpener` в `app_scope.dart` (общий код с `EmbeddedWizardOpener`, `entry: onboarding`), `PresetChosen` после открытия, закрытие Cubit мастера после диалога (D8). 3.5 зелёный.
- [ ] 3.7 `[desktop]` Красный: `test/app/codelab_app_onboarding_test.dart`. Spec app-onboarding:
  - «Показ onboarding при первом запуске» — «Первый запуск» (в дереве нет `CodeLabShell`), «Onboarding пройден»;
  - «Завершение onboarding и старт рабочего места» — «Проект восстановлен, агент ждёт конца onboarding»: двойник открывателя встроенного агента не вызван до «Start using CodeLab», после — один раз с `/work/app`;
  - spec agent-workbench-ui «Агент стартует сам» — «Восстановленный проект при первом показе onboarding»;
  - без шва `onboarding:` прежние тесты рабочего места зелёные.
- [ ] 3.8 `[desktop]` Реализация 3.7: чтение флага в `main.dart` до `runApp`, шов `createCodeLabRootScope(onboarding:)` и `CodeLabTestBinding(onboarding:)`, модуль с событиями чтения, ветка `OnboardingDestination` в `_CodeLabHome`, `startOnLaunch` при первом `WorkbenchDestination` (D3, D5). 3.7 зелёный.
- [ ] 3.9 `codelab-architect` (условная): если к началу итерации 3 change `add-privacy-policy` уже влит и страница «Settings › Legal» есть в сборке, до кода дополнить design.md решением о переходе «onboarding → Legal → onboarding» в `NavigationCubit` и спецификацию шага «Privacy» сценариями ссылок (D10, D17); иначе ссылки включает `add-privacy-policy`, и задача закрывается без правок.

## 4. Итерация 4 — интеграция, документация, проверки

- [ ] 4.1 `[desktop]` Красный: `integration_test/onboarding_flow_test.dart` — полный проход по spec app-onboarding «События журнала onboarding без секретов и путей», сценарий «Полный проход без утечек»: пустой `CODELAB_HOME`, мастер на тестовом сервере, «Start using CodeLab», агент стартует при выборе проекта без баннера «Add provider». В `feature/*` только компилируется (§21); прогон на устройстве — приёмка выпуска 1.0 в `release/*` (веха M4, design.md D17).
- [ ] 4.2 `[desktop]` Реализация 4.1: правки по итогам прогона на Dart VM в составе widget-тестов; сам интеграционный прогон на устройстве — в `release/*`.
- [ ] 4.3 `docs-writer`: `apps/codelab_desktop/doc/user-guide.md`, раздел «Первый запуск» — четыре шага, «Set up later», шаг пропускается при готовом провайдере, повторно onboarding не показывается; снимки экрана шагов (светлая тема) в `doc/images/`; ссылка из раздела «Подключить провайдера модели». `apps/codelab_desktop/README.md` — строка возможностей.
- [ ] 4.4 `docs-writer`: `apps/codelab_desktop/AGENTS.md` — раздел «Onboarding» (флаг, `OnboardingCubit`, порт и адаптер, отложенный старт, правило сторожа, ключи тестов, события; ссылки на D1–D15).
- [ ] 4.5 `docs-writer`: раздел выпуска `CHANGELOG.md` (Unreleased) по proposal.md, «Для раздела выпуска».
- [ ] 4.6 `check-runner`: проверки затронутого — format, analyze и тесты `codelab_setup`, `codelab_ui`, `codelab_desktop`; `guard`; `web-compile`; `l10n:check`; `openspec validate add-app-onboarding --strict`. Полный `melos run check` — только по просьбе пользователя.
- [ ] 4.7 `architecture-reviewer` и `acp-safety-reviewer`: двойное ревью (`/codelab-review add-app-onboarding`); особое внимание — D5 (гонка старта), D8 (ключ только в мастере), D9 (тексты о хранении ключей).
