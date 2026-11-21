## Context

Onboarding app (D-11) описан в §12.4.9 [`12-4-first-run-and-settings.md`](../../../docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md):
- флаг `onboarding_done` в `shared_preferences`;
- шаги «What CodeLab does» → «Permissions» → «Choose a model» (тот же `ProviderSetupFlow` в `ProviderWizardDialog`; шаг пропускается при `ProviderReady`) → «Privacy»;
- onboarding показывается после `BootReady` и не входит в шаги сторожа;
- шаг 4 не просит принять условия и не пишет запись о согласии (D-29).

Макеты — `docs/design/claude-design/`: граф `NavOnboarding`, артборды `OnboardingWelcome` (07b), `Onboarding` (07), `OnboardingModel` (07c), `OnbWizardUrl/Key/Model/Review` (07c.1–07c.4), `OnboardingModelDone` (07c.5), `OnboardingPrivacy` (07a) и тёмные копии.

Что есть в коде (develop, 2026-11-20):
- `AppDestination` — закрытая иерархия из двух веток: `WorkbenchDestination` и `SettingsDestination`. `NavigationCubit` стартует с `WorkbenchDestination`. Иерархия закрытая (`sealed`), чтобы следующие changes добавляли ветки (change `add-app-settings-shell`, D1);
- `add-app-navigation-shell` ещё не создан. По дорожной карте (§10.3) он вводит остальные ветки (Boot, Onboarding, ProjectPicker, оверлеи) «вместе с их экранами»;
- сторожа запуска (D-15, `BootHost`, `BootReady`) нет. `main` читает язык и оформление до `runApp` и передаёт их швами `AppLanguageStart` и `AppAppearanceStart`;
- агент стартует сам по триггерам рабочего места (change `require-project-folder`, D11–D19). При запуске триггер — `CodeLabShellCubit.startOnLaunch()`, который `_CodeLabHome` вызывает после первого кадра;
- мастер провайдера: автомат `ProviderSetupFlow` моста `codelab_setup`, `ProviderWizardCubit`, `ProviderWizardDialog`. Для баннера «Add provider» есть `EmbeddedWizardOpener` (`forceDefault: true`, цель `user`). Готовность — `checkProviderReadiness` моста; по снимку проверяет `provider_setup_probe.dart` в `lib/app/`;
- хранилище секретов в 1.0: `env` (только чтение, по умолчанию) или `file` (`$CODELAB_HOME/secrets.yaml`, только явным `secrets.backend: file`). Хранилища ОС — черновик после 1.0 (`add-agent-os-secret-backends`);
- `PRIVACY.md`, `TERMS.md` и страница «Settings › Legal» появились в develop 2026-11-21 вместе с change `add-app-legal-page` (архив `2026-11-20-add-app-legal-page`): ассеты `assets/legal/PRIVACY*.md`, `TERMS*.md`, `LegalPageCubit`, `LegalPageHost`, `LegalTab`, язык документа по интерфейсу (`legalAssetOf`). На момент первой редакции этого design их не было, отсюда D10 в редакции 2026-11-20;
- первый запуск CLI (U-17, §12.4.3) реализован change `add-provider-setup-ui` (итерация 4a). App на нём не строится: у CLI нет шагов 1, 2, 4, а мастер общий через мост.

## Goals / Non-Goals

**Goals:**
- показать четыре шага при первом запуске до рабочего места, не ломая порядок старта, язык и оформление первого кадра;
- настроить провайдера тем же мастером и с теми же гарантиями записи (SETUP-1…SETUP-6, SETUP-8, SETUP-24);
- не допускать в текстах шагов обещаний, которых нет в сборке (связка ключей ОС, web-инструменты);
- не запускать агента до конца onboarding.

**Non-Goals:**
- смартфон, планшет и узкая раскладка этапа 10;
- сторож запуска;
- изменения страницы «Legal», кроме параметра начальной вкладки хозяина (D10);
- повторный показ onboarding;
- изменения ACP;
- изменения автомата мастера, кроме значения `entry`.

## Decisions

### D1. Ветка `OnboardingDestination` вводится здесь, а не в `add-app-navigation-shell`

`AppDestination` получает ветку `OnboardingDestination` без полей: шаг — состояние `OnboardingCubit`, а не навигации. `NavigationCubit` получает начальное назначение параметром конструктора (`initial`) и метод `finishOnboarding()`. Метод переводит `OnboardingDestination` → `WorkbenchDestination`, из других назначений ничего не делает. Пока открыт onboarding, `openSettings` ничего не делает (журнал `settings.open_skipped` уровня debug с `reason: onboarding`; поле обязательно — ревью 2026-11-21, п. 5, исправляется в коде, решение не меняется). Поэтому Cmd/Ctrl+, и пункт меню macOS «Preferences…» не уводят с onboarding.

Почему здесь: в дорожной карте (§10.3) `add-app-navigation-shell` — не отдельный шаг перед экранами, а «остальные ветки … вместе с их экранами». Пустых веток «на вырост» нет (AGENTS.md §13, SETUP-17). Значит, ветку Onboarding вводит change экрана onboarding, а Boot и ProjectPicker остаются своим changes. Решение Q3 `add-provider-setup-ui` («после `add-app-navigation-shell`») требовало `OnboardingDestination`, и этот change его вводит (решение пользователя 2026-11-20, Q1 (а)). Строка `add-app-navigation-shell` в §10.3 дорожной карты больше не содержит ветку Onboarding (задача 0.2).

Альтернативы:
- *сначала отдельный `add-app-navigation-shell` со всеми ветками* — отклонено: ветки Boot и ProjectPicker остались бы без экранов;
- *показывать onboarding модальным диалогом поверх рабочего места* — отклонено: рабочее место пришлось бы строить и не запускать агента; диалог не задуман как экран (макет — полноэкранный, с шапкой «Welcome to CodeLab»); фокус и Esc диалога противоречат правилу «закрыть нельзя».

### D2. Флаг `codelab.app.onboarding_done`

- Ключ — `codelab.app.onboarding_done`, по образцу `codelab.app.language` и `codelab.app.appearance`. Имя `onboarding_done` из §12.4.9 становится суффиксом.
- Значение — только `true`. Ключ пишется один раз, при «Start using CodeLab», и не удаляется.
- Порт — `OnboardingPreferences` в `lib/core/platform/` (`load()` не бросает, `markDone()` бросает). Реализация — `SharedPreferencesOnboardingPreferences`, по образцу `SharedPreferencesAppLanguagePreferences`.
- Результат `load()` — `OnboardingLoad(done, storedValueInvalid, readFailure)`.

Правила чтения (целостность данных важнее UX, AGENTS.md §2):

| Что в ключе | Показ onboarding | Ключ |
|---|---|---|
| нет ключа | да | не трогается до «Start using CodeLab» |
| `true` | нет | — |
| другое значение или тип | нет, событие `onboarding.flag_invalid` | НЕ перезаписывается |
| сбой хранилища | нет, событие `onboarding.flag_unreadable {error_type}` | — |

Почему при сбое onboarding не показывается: если хранилище не читается, оно, скорее всего, и не пишет. Тогда onboarding показывался бы при каждом запуске и заслонял бы рабочее место. Рабочее место без onboarding остаётся полностью рабочим: баннер «Add provider» никуда не делся.

Альтернатива *хранить флаг в `$CODELAB_HOME`* отклонена. Флаг — настройка окна app, а не агента и не CLI. У CLI свой первый запуск по готовности провайдера, без флага (§12.4.3).

### D3. Чтение флага до `runApp` и шов composition root

`main` читает флаг вместе с языком и оформлением и передаёт результат швом `createCodeLabRootScope(onboarding: OnboardingStart)`. `OnboardingStart` несёт признак показа и диагностику чтения. События пишет модуль после настройки журнала, как `app.locale_resolved` (`add-desktop-localization`, D13). Без шва (тесты) onboarding не показывается: прежние тесты рабочего места не меняются. Тесты onboarding передают шов явно, `CodeLabTestBinding(onboarding:)`.

Почему до `runApp`: первый кадр сразу рисует нужный экран. Иначе рабочее место мигнуло бы и успело вызвать триггер старта агента (D5).

### D4. Шаги и переходы — `OnboardingCubit`

`OnboardingCubit` (`features/onboarding/application/`) — владелец шага и данных шагов. Состояние — `OnboardingState`:

- `step: OnboardingStep` (`welcome | permissions | model | privacy`);
- `facts: OnboardingFactsState` — закрытая иерархия `Loading | Loaded(OnboardingFacts) | Unavailable`;
- `model: OnboardingModelStep` — закрытая иерархия:
  - `Pending` — готовность ещё не известна;
  - `Skipped(reason)`, где `reason` — `ready | external`;
  - `Choose(notice)`, где `notice` — `none | keyMissing | configBroken | unavailable`;
  - `Saved(summary)`;
- `finishing: bool`.

Набора независимых флагов нет (AGENTS.md §8).

Переходы:

| Из | Действие | В |
|---|---|---|
| welcome | Next | permissions |
| permissions | Back | welcome |
| permissions | Next | model, если шаг не `Skipped`; иначе privacy |
| model | Back | permissions |
| model | Next (только в `Saved`) или «Set up later» | privacy |
| privacy | Back | model, если шаг не `Skipped`; иначе permissions |
| privacy | Start using CodeLab | конец (D5) |

Back на шаге 4 при пропущенном шаге 3 ведёт на шаг 2 (граф `NavOnboarding`). Back на шаге 4 при `Saved(summary)` возвращает на шаг 3 в том же `Saved`: сводка сохранённого провайдера не сбрасывается, «Next» остаётся активной. Повторное сохранение через «Set up again…» заменяет сводку новой (последний `Done` побеждает); прежний провайдер остаётся в конфиге (D8).

В событии `onboarding.completed` поле `model_step` принимает три значения (D13): `skipped` — шаг 3 пропущен (`Skipped`); `saved` — на шаг 4 ушли из `Saved`; `later` — любой выход на шаг 4 из `Choose(…)` («Set up later» при любом `notice`). Строка шагов показывает пропущенный шаг 3 отмеченным, как пройденный: пользователь видит четыре шага, а не три.

Next на шаге 2 при `model: Pending` ждёт итога готовности. Кнопка показывает индикатор, повторное нажатие не даёт второго перехода. Ожидание ограничено таймаутом D6, поэтому зависнуть оно не может.

Esc и закрытие окна onboarding не завершают. Закрытие окна — обычный выход app (`app_exit_handler`): флаг не пишется, и при следующем запуске onboarding покажется снова (граф `NavOnboarding`, «Quitting before the last step shows onboarding again next start»).

### D5. Рабочее место и старт агента откладываются до конца onboarding

Пока назначение — `OnboardingDestination`, `_CodeLabHome` не строит рабочее место (`CodeLabShell`), а `startOnLaunch()` не вызывается. Корневые Cubit-ы (`CodeLabShellCubit` и другие) создаются, как раньше. Восстановление проекта из снимка (`_restoreProject`) тоже идёт, как раньше: оно читает снимок, но агента не запускает. Агента запускает только `startOnLaunch` (change `require-project-folder`, D19).

`OnboardingCubit.finish()`:
1. ставит `finishing` (повторное нажатие игнорируется);
2. пишет флаг через `markDone()`;
3. при сбое записи пишет `onboarding.save_failed {error_type}` и не останавливается: onboarding покажется при следующем запуске, а это лучше, чем запереть пользователя на шаге 4;
4. зовёт `NavigationCubit.finishOnboarding()` (в Cubit — колбэк `onFinished`) при любом исходе записи, в том числе после сбоя шага 3.

Закрытие во время записи (ревью 2026-11-21, п. 7): после `await markDone()` при `isClosed` метод выходит без `onFinished` и без событий — итог записи после закрытия не публикуется (CON-005). Отдельно `NavigationCubit.finishOnboarding()` на закрытом Cubit — no-op, без `emit`: колбэк может пережить владельца экрана при закрытии root scope.

Когда назначение впервые становится `WorkbenchDestination`, `_CodeLabHome` вызывает `startOnLaunch()` ровно один раз за жизнь app: так же, как сейчас после первого кадра при запуске без onboarding.

Почему: провайдер, сохранённый на шаге 3, должен действовать при первом же старте агента. Иначе агент восстановленного проекта стартовал бы под onboarding без провайдера и упал бы, а пользователь вернулся бы к баннеру «Add provider». Живое перечитывание конфига (§17.5.6) тут не помогает: агент без провайдера не открывается совсем.

Это меняет требование agent-workbench-ui «Агент стартует сам» (триггер 1, «проект, восстановленный при запуске»), поэтому его дельта — MODIFIED.

### D6. Факты для шагов — порт `OnboardingProbe`

Шагам 2–4 нужны сведения, которые лежат за IO:
- готовность провайдера;
- бэкенд секретов (`SecretBackendInfo`: `id`, `writable`);
- действующий режим новой сессии;
- подписи путей.

Порт `OnboardingProbe` (`features/onboarding/application/`) — одна операция `Future<OnboardingFacts> read()`. Адаптер `lib/app/onboarding_probe.dart` собирает факты так:

1. Профиль по умолчанию — `DefaultProfileResolver`; доступ — `resolveSettingsAccess` моста без папки проекта (`cwd: null`): при первом запуске проекта нет, проектные слои применяются только к доверенному проекту, а onboarding его не выбирает. Не `EditableSettings` (внешний stdio-агент, WebSocket) → `OnboardingFacts.external`: шаг 3 `Skipped(external)`, шаг 2 — D7.
2. `EditableSettings` → `ClientSecretAccess.open`, `FileAgentConfigStore.snapshot(cwd: access.paths.codelabHome)` и `checkProviderReadiness(snapshot, providerKeysOf(...), environment)`. Это то же правило, что у первого запуска CLI и баннера D26. Второй копии правила нет (SETUP-8).
3. Режим — `sessionDefaultsOf(snapshot, access).mode` моста, правило страницы «Agents & modes».
4. Подпись пути — `homePathLabel` для `CODELAB_HOME` доступа. Каталог логов app в факты не входит (D9, п. 4 ревью).

**Только user-слой (ревью 2026-11-21, п. 3).** Снимок зонда берётся с `cwd: access.paths.codelabHome` — тем же, что у `openWizard` (`_access.cwd ?? codelabHome`), а не с пустой строкой: иначе загрузчик прочитал бы `<cwd процесса>/.codelab/config*.yaml` как проектный слой, и шаг 3 судил бы о готовности по чужому конфигу. Под «без папки проекта» понимается именно это: проектного слоя в снимке нет.

**Один доступ для зонда и мастера (ревью 2026-11-21, п. 2).** `OnboardingFacts` несёт `EditableSettings` (тип основного бареля моста, без IO), по которому прочитан снимок. `OnboardingWizardOpener` получает этот доступ параметром (`({required String presetId, required EditableSettings access})`) и открывает сессию настроек по нему, а не по встроенному профилю. Поэтому для stdio-профиля `codelab-agent` со своим `CODELAB_HOME` или `--config` шаг 3 проверяет и мастер пишет один и тот же конфиг — как страница «Providers», которая тоже работает по профилю по умолчанию. Альтернатива *считать такой профиль `Skipped(external)`* отклонена: `codelab-agent` настраивается из app (`EditableSettings`), и пользователь потерял бы мастер без причины.

`OnboardingCubit` вызывает `read()` один раз, при создании, с таймаутом 5 с. Это время шага `stores` сторожа (§12.4.7), а хранилище секретов в худшем случае отвечает не дольше 10 с. Итоги:

| Итог `read()` | Шаг 3 |
|---|---|
| `ProviderReady` | `Skipped(ready)` |
| внешний профиль | `Skipped(external)` |
| `NoProviderConfigured` | `Choose(none)` |
| `ProviderKeyMissing` | `Choose(keyMissing)` |
| `ConfigBroken` | `Choose(configBroken)` |
| таймаут или исключение | `Choose(unavailable)`, `facts: Unavailable`; событие `onboarding.facts_unavailable {error_type \| timeout}` |

Итог принимается один раз: признак `_factsResolved` ставит первый из исходов (факты, ошибка, таймаут), и поздний итог после него только пишется событием `onboarding.facts_late`; после `close()` итог отбрасывается по `isClosed` (CON-002). Номера попытки нет: чтение одно. `close()` завершает ожидание фактов (`_factsDone`), чтобы `next()`, ждущий его на шаге 2, вышел по `isClosed`, а не висел (ревью 2026-11-21, п. 8). Повторного чтения нет: onboarding — однократный экран.

Почему один порт, а не три: все факты читаются из одного снимка и одного открытого хранилища, а `codelab_setup/io.dart` пускается только в `lib/app/` (D20 `add-provider-setup-ui`, SETUP-9). Отдельные порты дали бы три открытия хранилища.

### D7. Шаг «Permissions»: правда о действующем режиме

Таблица шага описывает режим `standard` по артборду 07:
- чтение без вопроса;
- правки с диффом спрашиваются;
- команды с полной командой и папкой спрашиваются;
- всё вне папки проекта заблокировано.

Это совпадает с `permissions.md` (раздел о режимах: «Новая сессия стартует в `standard`») и containment `BoundedEnv`. InfoBar под таблицей (ревью 2026-11-21, п. 1):
- факты ещё читаются (`FactsLoading`) → InfoBar режима нет; на его месте строка с индикатором `Reading the agent settings…`. Утверждать режим до чтения нельзя;
- факты недоступны (`FactsUnavailable`) → нейтральный текст `Agent settings could not be read. The mode for new sessions is shown in Settings › Agents & modes.` Без утверждения `standard`: в общем конфиге может быть `bypass`;
- режим `standard` → `New sessions start in standard mode` (текст артборда);
- `EditableSettings` с другим режимом → `New sessions start in <mode> mode`. Режим назван по подписи страницы «Agents & modes», к ней добавлено `Your config sets this; the table above describes standard mode.` и та же ссылка на «Settings › Agents & modes»;
- внешний профиль по умолчанию → `Your default connection is an external agent. It applies its own rules; approvals still appear in the conversation.`

Почему: `config.yaml` общий с CLI (`~/.codelab`). Пользователь CLI мог задать `bypass`, и текст «Asks each time» был бы для него неправдой (AGENTS.md §2: безопасность выше UX). Перестраивать таблицу под каждый из пяти режимов — лишняя сложность для однократного экрана. Достаточно честной пометки. По той же причине при непрочитанных фактах шаг не называет режим вовсе: неизвестное нельзя выдавать за умолчание (AGENTS.md §2).

### D8. Шаг «Choose a model» и мастер

- **Карточки** — пресеты из той же таблицы, что шаг «API type» мастера (`ChoosingPreset.presets`; пресеты моста с `wizard: true`). Подписи — те же функции, что у мастера (`wizardPresetLabel`). Второго списка пресетов в app нет. Подпись под именем — хост `baseUrl` пресета и требование ключа (`key`, `Local, no key`, `Your server URL, optional key`). Выбор карточки — состояние presentation, а не `OnboardingCubit`.
- **«Set up <preset>…»** открывает мастер функцией composition root `OnboardingWizardOpener`. Это тот же код, что `EmbeddedWizardOpener`:
  - доступ встроенного профиля, цель `user`;
  - `forceDefault: true`: шаг называется «Choose where the model runs… saves the choice as your default»;
  - `entry: ProviderWizardEntry.onboarding` (D11).

  Сразу после открытия presentation отправляет автомату `PresetChosen(<id>)`, и диалог начинается с «Base URL» с отмеченным «API type» (артборд 07c.1). «Back» на «Base URL» возвращает в «API type» внутри диалога, как в автомате. Это отступление от артборда, где Back с первого шага не показан: автомат не меняется (SETUP-8).
- **«This project only»** не показывается: папки проекта на onboarding нет. Диалог уже скрывает переключатель без папки (spec app-settings «Мастер провайдера в app»).
- **После `ConfigSaved`** (`Done(plan, committed)`) шаг переходит в `Saved(summary)` (артборд 07c.5). `summary` — `OnboardingSavedSummary`: id провайдера, модель по умолчанию `<id>/<m>` и способ хранения ключа (`secret <имя> in <backend.id>`, `env <VAR>` или `no key`). Значения ключа в сводке нет (SETUP-1). Next активна. «Set up again…» открывает мастер снова; прежний провайдер остаётся в конфиге (текст артборда). Баннер `saved` страницы «Providers» и кнопки «Retry»/«Connect» на onboarding не показываются: агент ещё не стартовал и стартует после onboarding (D5).
- **Мастер и навигация шага (ревью 2026-11-21, п. 6).** Открытие мастера асинхронно: composition root открывает хранилище секретов и снимок. `OnboardingCubit` получает переход `wizardStarted()` → `wizardEnded()`; между ними шаг модели помечен активным мастером (поле `wizard: idle | active` у `Choose` и `Saved`, а не отдельный флаг состояния). Пока мастер активен, «Back», «Next» и «Set up later» игнорируются Cubit-ом и неактивны в UI; повторное «Set up <preset>…» тоже. Если открыватель вернул Cubit мастера, а шаг уже не «Choose a model» или onboarding закрыт, диалог НЕ показывается, Cubit мастера сразу закрывается — ничего не записано. Поэтому провайдер не может записаться, пока onboarding на другом шаге и затем быть проигнорирован с `model_step: later`.
- **Cancel, Esc, закрытие диалога** — шаг остаётся в прежнем состоянии, ничего не записано. Это свойство мастера (spec app-settings «Мастер провайдера в app»). Cubit мастера закрывает `OnboardingScreen` после диалога, как `addProviderFromBanner`.
- **«Set up later»** (`onboarding-model-later`) доступна в любом `Choose(…)` и ведёт на шаг 4 без записи. Отступление от артборда, где выхода без провайдера нет. Без этой кнопки пользователь внешнего агента или без ключа под рукой не прошёл бы onboarding, а закрыть его нельзя (D4). Баннер «Add provider» рабочего места остаётся запасным путём.
- **`Choose(keyMissing)`** — InfoBar по ссылке (тексты по образцу §12.4.3, п. 4):
  - `secret <имя>` → `Provider "<id>" is set up, but its key "<имя>" is not in <backend.id>. Add it in Settings › Providers › Edit.`;
  - `env <VAR>` → `Provider "<id>" reads its key from <VAR>, which is not set where CodeLab was started.`

  Карточки и «Set up <preset>…» доступны: пользователь может добавить другого провайдера. Мастер правки отсюда не открывается (proposal, «Не входит»).
- **`Choose(configBroken)`** — InfoBar `The agent's config has <n> problems. Fix them in Settings › Providers or run codelab config check.` Карточки неактивны: мастер не пишет поверх битого файла (как D26 и §12.4.3, п. 2). Доступна только «Set up later».
- **Итог мастера при `Choose(configBroken)` и `Choose(unavailable)`** игнорируется: если `Done` всё же пришёл (мастер открыт в обход неактивной кнопки или гонкой), `OnboardingCubit` не переходит в `Saved`, шаг остаётся в прежнем `Choose(…)`. Защита в Cubit, а не только в виджете: кнопка — представление, а правило «не писать и не признавать запись поверх битого или непрочитанного конфига» — application (AGENTS.md §6, §10).
- **`Choose(unavailable)`** — InfoBar `Agent settings could not be read. You can set up a provider later in Settings › Providers.` Карточки неактивны, доступна «Set up later».

### D9. Тексты шагов 1 и 4 — по сборке, а не по макету

Артборды обещают «Keys go to the system keychain» (07b) и «API keys in the system keychain» (07a), а также «Config, sessions and logs in ~/.codelab». В сборке 1.0 хранилища ОС нет (`add-agent-os-secret-backends` — после 1.0). Логи app лежат в `<support>/logs`, а не в `~/.codelab`. Поэтому:

- **07b, карточка «Your model, your key»** — `Connect a cloud provider or a local model. The key stays on this computer.` Без названия хранилища: факты на шаге 1 могут ещё читаться.
- **07a, строка «Stays here»** — из `OnboardingFacts`:
  - `Config and sessions in <home>; app logs in <logs>;` (`<home>` — из фактов, `<logs>` — из composition root) и подпись ключей по `SecretBackendInfo.id`:
    - `env` → `API keys are read from environment variables; CodeLab does not store them`;
    - `file` → `API keys in <home>/secrets.yaml, an unencrypted file`;
    - `keychain-*`, `secret-service`, `wincred` (после 1.0) → `API keys in the system keychain (<id>)`;
    - другой → `API keys in the agent's secret store (<id>)`;
  - внешний профиль → `Config and sessions of the external agent are managed by that agent; app logs in <logs>`;
  - факты недоступны → `App logs in <logs>; the agent's config and keys stay on this computer`.

  Каталог логов app (`<logs>`) не зависит от IO-зонда: его подпись composition root передаёт экрану отдельно (зависимость `onboardingAppLogsLabel` в `CodeLabDependencies`, вычисляется из `logDirectoryPath` `main` и `homePathLabel`), поэтому он есть во всех трёх вариантах строки, в том числе при недоступных фактах (ревью 2026-11-21, п. 4).
- **07a, строки сети** — по `PRIVACY.md` §2 сборки, а не по артборду (редакция 2026-11-21: в сборке нет web-инструментов, `PRIVACY.md` §2 — «no update check and no web tools»):
  - «Your model provider» — каждый ход: промпт, история сессии, файлы и вывод команд, которые прочитал агент; тег `Every turn`;
  - «MCP servers» — `Client information, the tool list request and the headers from your configuration, including tokens, each time a session starts or reconnects; the arguments of every tool call` с тегом `Each session` (редакция 2026-11-21, ревью безопасности раздела 6: по `PRIVACY.md` §2 при создании и загрузке сессии уходят `initialize`, `tools/list` и заголовки из конфигурации, включая токены, даже без вызова инструментов; прежний тег `When used` это скрывал). Вместо артбордных «MCP servers and web tools» и «a URL or a search query — web access asks you first»;
  - телеметрия, отчёты о сбоях, аналитика — никогда (E-21, `PRIVACY.md` §1).

  Полный перечень (проверка `/models`, «Show image», внешний ACP-агент) — в политике, на которую ведёт ссылка D10; шаг его не повторяет.
- **07a, вводный текст** — `Only what the agent needs for the work you ask for, sent to services you set up or to addresses you choose to open. CodeLab itself collects nothing. The privacy policy lists every request.` вместо артбордного `…and only to services you set up.` (редакция 2026-11-21): «Show image» уходит на хост, который выбрала модель, а не пользователь, поэтому «только настроенным сервисам» было бы неправдой. Вводная называет обе категории — настроенные сервисы (провайдер, в том числе проверка `/models`, MCP-серверы, внешний ACP-агент) и адреса, которые пользователь открывает сам («Show image»), — и отсылает к политике за полным перечнем, не дублируя его. Текст шага 2 `Reads run freely; edits, commands and web access ask.` теряет `web access` по той же причине: `Reads run freely; edits and commands ask.`
- **07c, InfoBar «Opens the provider wizard»** — `The key is stored in <backend.id> or read from an environment variable.` По `writable` бэкенда; при `writable == false` — `The key is read from an environment variable.`

Почему: приватность и безопасность выше соответствия макету (AGENTS.md §2). Неверное обещание о хранении ключа — дефект безопасности, а не текста. Канвас — референс; при расхождении источник истины — §12.x и `openspec/` (README канваса).

### D10. Ссылки на документы на шаге 4 — просмотр внутри onboarding

**Редакция 2026-11-21.** Первая редакция (2026-11-20) скрывала ссылки до страницы «Legal» и отдавала их включение тому change, который вливается вторым. `add-app-legal-page` влит раньше, поэтому ссылки включает этот change, до PR (решение пользователя 2026-11-21).

**Что на шаге 4.** Под строками — ссылки «Read the privacy policy» (`onboarding-privacy-policy`) и «Terms of use» (`onboarding-terms-of-use`), тексты артборда 07a. InfoBar — текст артборда: заголовок `Nothing to agree to`, тело `These links open the documents inside the app and work offline; Back returns to this step. You can find them later in Settings › Legal.` Это согласуется с `TERMS.md` («There is nothing to sign, no checkbox and no step that asks for your consent») и с D-29: шаг по-прежнему ничего не просит принять и согласия не пишет.

**Переход — просмотр документа внутри экрана onboarding** (вариант (а)):
- `OnboardingState` получает поле `document: LegalTab?` и переходы `openDocument(LegalTab)` / `closeDocument()`. Открыть документ можно только на шаге «Privacy», без активного мастера; на другом шаге вызов ничего не делает. Пока документ открыт, Back/Next/«Start using CodeLab» шага игнорируются.
- Экран onboarding при `document != null` показывает поверх шага полноэкранную панель «документа» в пределах окна: шапка с кнопкой «Back» (`onboarding-document-back`, подпись `Back to setup`) и тело — `LegalPage` того же change `add-app-legal-page` под своим хозяином. `LegalPageHost` получает необязательный параметр начальной вкладки (`initialTab`), который при наличии перекрывает `SettingsDestination.legalTab`; это единственная правка Legal-кода. Поэтому текст документа, четыре вкладки, язык по интерфейсу, политика ссылок D8 и офлайн-чтение — те же, что на странице настроек, а второго рендера правовых текстов нет (§12.7.7а: «один текст не живёт в двух местах»).
- `LegalPageCubit` создаётся при открытии панели и закрывается при её закрытии (D7 `add-app-legal-page`); вкладка и запрос поиска не переживают панель.
- «Back», Esc и системный «назад» закрывают панель (`closeDocument`) и возвращают шаг «Privacy» в прежнем виде; фокус возвращается на ссылку, которой панель открыли. При открытии фокус — на кнопке «Back» панели. Состояние `OnboardingCubit` (шаг модели, сводка, факты) не меняется: `_OnboardingHost` не перестраивается, назначение навигации остаётся `OnboardingDestination`.
- Журнал: `onboarding.document_opened {tab}` и `onboarding.document_closed {tab}` (debug для закрытия) логгера `codelab_desktop.onboarding`; события `legal.*` пишет `LegalPageCubit`, как на странице (D11 `add-app-legal-page`). Путей, текстов и запросов поиска в событиях нет.

**Почему не переход в настройки (вариант (б)).** Пришлось бы открыть настройки из onboarding вопреки D1, научить `SettingsDestination` возвращать на `OnboardingDestination` и не закрывать `_OnboardingHost` со всем состоянием шагов (D5), а пользователь первого запуска оказался бы в навигации настроек с поиском и одиннадцатью страницами. Граф `NavOnboarding` требует только «Legal pages open inside the window; Back returns to 07a» — вариант (а) это и делает.

Альтернативы:
- *открывать документы в браузере по адресу сайта* — отклонено: адреса `<сайт>/privacy` и `<сайт>/terms` не определены (§11), это сетевой запрос не из перечня `PRIVACY.md` §2, а документы должны читаться офлайн;
- *отдельный простой просмотр одного документа (`CodeLabMarkdown` без вкладок)* — отклонено: ссылки внутри `TERMS.md` ведут на `LICENSE` и `PRIVACY.md` (D8 `add-app-legal-page`), и без вкладок их пришлось бы гасить или повторять политику ссылок.

### D11. `ProviderWizardEntry.onboarding`

В мосте `codelab_setup` появляется значение `onboarding('onboarding')`. Событие `provider_wizard.started {entry: onboarding}` отделяет мастер onboarding от страницы (`app`), баннера (`banner`) и первого запуска CLI (`first_run`). Поведение автомата от `entry` не зависит (проверено: значение используется только в журнале).

Альтернатива *переиспользовать `firstRun`* отклонена: в журнале нельзя было бы отличить CLI от app без логгера-источника, а сводки событий в `observability.md` идут по `entry`.

### D12. Строка шагов — молекула кита `CodeLabSetupSteps`

Горизонтальная строка из кружков с номером или `✓` и подписей; текущий шаг полужирный, с рамкой акцента (артборды 07*). Это не `CodeLabStepBreadcrumb` мастера: тот — строка текста с `›`. Молекула только рисует: подписи, индекс текущего шага и набор пройденных передаёт app. Логики onboarding в ней нет (AGENTS.md §5, `codelab_ui`). Доступность: `Semantics` со списком и пометкой текущего шага (`aria-current="step"` артборда). Строка переносится по ширине.

Почему в ките: строка нужна и следующим многошаговым экранам (onboarding смартфона и планшета этапа 10). По этой же причине `CodeLabStepBreadcrumb` вынесен в кит (D19 `add-provider-setup-ui`). Остальная вёрстка шагов — существующие атомы кита и Fluent (`InfoBar`, `Button`, `FilledButton`, теги `CodeLabBadge`) внутри `features/onboarding/presentation/`.

### D13. Наблюдаемость

Логгер `codelab_desktop.onboarding`, компонент `onboarding`:

| Событие | Уровень | Поля |
|---|---|---|
| `onboarding.shown` | info | — |
| `onboarding.flag_invalid` | warning | — |
| `onboarding.flag_unreadable` | warning | `error_type` |
| `onboarding.facts_loaded` | debug | `access` (`editable`, `external`), `readiness` (`ready`, `no_provider`, `key_missing`, `config_broken`), `backend` (`backend.id`), `duration_ms` |
| `onboarding.facts_unavailable` | warning | `error_type` или `timeout: true` |
| `onboarding.facts_late` | debug | `duration_ms` |
| `onboarding.step_shown` | debug | `step` |
| `onboarding.model_step_skipped` | info | `reason` (`ready`, `external`) |
| `onboarding.model_saved` | info | — (id провайдера пишет `provider_wizard.saved` моста) |
| `onboarding.completed` | info | `model_step`: `skipped` (шаг 3 пропущен), `saved` (выход из `Saved`), `later` (любой выход на шаг 4 из `Choose(…)`); пишется и при сбое записи флага |
| `onboarding.save_failed` | warning | `error_type` |
| `onboarding.document_opened` | info | `tab` (`privacy_policy`, `terms_of_use`) |
| `onboarding.document_closed` | debug | `tab` — вкладка в момент закрытия |

В событиях нет путей, имён секретов и переменных, адресов, id моделей и текстов исключений (только `runtimeType`), как в событиях настроек (D17 `add-app-settings-shell`). События мастера пишет мост (`provider_wizard.*`, D18 `add-provider-setup-ui`); onboarding их не дублирует.

### D14. Локализация, клавиатура, ширина

- Все тексты шагов — ARB `en` и `ru`, префикс `onboarding*`. Термины — по `l10n-glossary.md`; новые термины (`onboarding`, «Set up later») добавляет задача 0.4.
- Тексты, построенные по фактам (D9), — функции presentation «(факты, язык)», а не строки в состоянии Cubit-а. Поэтому смена языка не нужна: языка на onboarding не выбрать, но язык системы применяется с первого кадра.
- Не переводятся: имена пресетов, id провайдеров и моделей, `backend.id`, имена переменных и секретов, пути, имена режимов (`standard`) — как на страницах настроек.
- Порядок Tab — сверху вниз, потом «Back», «Next». Фокус при показе шага — на заголовке шага, чтобы экранный диктор прочитал его. Enter на сфокусированной кнопке нажимает её; глобального «Enter = Next» нет: Enter в карточке пресета выбирает её.
- Контент шага ограничен шириной 920 px и центрирован (артборды). Уже 900 px он прокручивается по вертикали, строка шагов переносится. Отдельной узкой раскладки нет (D-21, этап 10).

### D15. Пакеты, слои, сторож, граф

| Пакет (ADR-0002) | Что меняется | Слой |
|---|---|---|
| `codelab_setup` (мост агентской стороны, `[agent]`) | `ProviderWizardEntry.onboarding` | основной барель, web-безопасен |
| `codelab_ui` (`[desktop]`) | `CodeLabSetupSteps` | molecules |
| `codelab_desktop` (`[desktop]`) | `core/platform/onboarding_preferences.dart` | infrastructure (порт и адаптер `shared_preferences`) |
| | `app/onboarding_probe.dart`, `app/app_scope.dart`, `main.dart` | composition root |
| | `app/navigation/` | application (навигация) |
| | `features/onboarding/application/` | application |
| | `features/onboarding/presentation/` | presentation |

Направление зависимостей не меняется:
- `features/onboarding/presentation` → `application` → порт `OnboardingProbe`;
- адаптер в `lib/app/` → `codelab_setup/io.dart`.

Presentation не обращается к файлам, связке ключей и HTTP (SETUP-9). Сторож:
- `codelab_setup/io.dart` в `apps/codelab_desktop/lib` уже разрешён только в `app/` (правило D20 `add-provider-setup-ui`), и адаптер `lib/app/onboarding_probe.dart` под него попадает;
- новое правило одно: `PackageRule('apps/codelab_desktop/lib/features/onboarding', forbidden: ['dart:io'])` по образцу правила `features/settings/presentation`. Onboarding весь — application и presentation; файлы и хранилище он получает только портами. Правило вводится вместе с каталогом (корневой `AGENTS.md` §5);
- `shared_preferences` сторож не ограничивает. Порт флага кладётся в `lib/core/platform/` по соглашению app (AGENTS.md app, раздел «Профили подключения и настройки»), отдельное правило ради одного ключа не нужно.

Новых рёбер и пакетов нет, граф `README.md` не меняется. `codelab_agent_*` в `apps/codelab_desktop` не появляется. Allowlist ядра (PKG-2), `clientCoreAllowlist` и `desktopAllowlist` не меняются.

### D16. Итерации

1. Флаг, ветка навигации, значение `entry` моста.
2. `OnboardingCubit` и адаптер `OnboardingProbe`.
3. Кит, экран, мастер из шага 3, отложенный старт рабочего места, ARB.
4. Интеграционный сценарий, документация, проверки.

### D17. Веха M4 (1.0)

Решение пользователя 2026-11-20 (Q7 (б)): onboarding app входит в продукт 1.0 (M4), а не в 1.x. Приоритет цели D-11 в матрице остаётся Could: меняется веха, а не обязательность цели. В счёт Should 1.0 (§6.1 дорожной карты) D-11 не входит, как и частичная D-25.

Почему 1.0: первый `stable`-релиз ставят люди, которые впервые видят агента с доступом к файлам и командам. Без onboarding они узнают о провайдере только из сбоя старта, а о том, где агент спрашивает и что уходит с компьютера, не узнают вовсе. U-17 решает это для CLI; D-11 — то же для app.

Влияние:
- **критерий выхода M4** не меняется по форме: строка 07 §10.1 получает D-11 в колонке M4, а приёмка — сценарии spec `app-onboarding` и прогон `integration_test/onboarding_flow_test.dart` на устройстве в `release/*` (§21);
- **зависимость от страницы «Legal»** (`add-app-legal-page`, влит 2026-11-21) — снята: ссылки шага 4 включает этот change (D10, редакция 2026-11-21);
- **`add-app-navigation-shell`** не нужен для 1.0: ветку Onboarding вводит этот change (D1). Boot (D-15, M2) и ProjectPicker остаются своим changes;
- **этап 10** (смартфон, планшет) по-прежнему M5: onboarding P17–P20 и T11–T14 в 1.0 не входит.

## Risks / Trade-offs

- **[Гонка старта агента]** Если `startOnLaunch` вызовется раньше `finishOnboarding` (например, по старому пути первого кадра), агент стартует без провайдера. → Красный тест 3.7: при `OnboardingDestination` открыватель встроенного агента не вызывается до «Start using CodeLab», а после — ровно один раз.
- **[Поздний итог фактов]** Медленное хранилище ответит после таймаута. → Номер попытки и `isClosed`: поздний итог только пишется в журнал на уровне debug (`onboarding.facts_late`) и состояние не меняет (CON-002).
- **[Мастер и закрытие onboarding]** Диалог модальный, поэтому «Start using CodeLab» при открытом мастере недостижима. Cubit мастера закрывается после диалога, и закрытие отменяет проверку и сбрасывает ключ (свойство мастера).
- **[Существующие пользователи]** После обновления onboarding покажется всем один раз (флага нет; решение пользователя Q2 (а)). Если провайдер готов, шаг 3 пропускается, так что это три экрана.
- **[Документ поверх шага]** Панель документа живёт внутри экрана onboarding; если её владелец перестроится, `LegalPageCubit` закроется вместе с хозяином, а `OnboardingCubit` не пострадает. → Тесты раздела 6: возврат на шаг 4 с прежним состоянием, `close` Cubit-а документа.
- **[Тексты про хранилище]** После `add-agent-os-secret-backends` id бэкенда станет `keychain-macos` и т. п., и подпись D9 уже это учитывает. Добавить новый id без строки D9 — значит получить общую подпись, не ложную.
- **[Телеметрия]** Строка «Never» опирается на E-21. Сторож SDK аналитики (`pubspec_allowlist_test.dart`) в сборке пока не введён (задача 9.4). До него утверждение держится на ревью зависимостей; новых зависимостей change не добавляет.
- **[Сеть]** Onboarding открывает сеть только через проверку мастера: на введённый `base_url`, без редиректов (SETUP-10, SETUP-23).

## Migration Plan

Миграции данных нет. Новый ключ `shared_preferences` создаётся при первом «Start using CodeLab». Откат change оставляет ключ неиспользованным и безвредным.

## Решения пользователя 2026-11-20

| Вопрос | Решение | Где учтено |
|---|---|---|
| Q1. Порядок с `add-app-navigation-shell` | (а) этот change вводит только ветку `OnboardingDestination`; остальные ветки — их changes | D1; §10.3 дорожной карты; §12.3 A13; §12.4.9 |
| Q2. Onboarding для обновивших app | (а) показывать один раз по отсутствию флага | D2; Risks |
| Q3. «Set up later» на шаге 3 | (а) добавить (отступление от артборда) | D8; spec app-onboarding |
| Q4. Ссылки на документы на шаге 4 | (а) скрыты до страницы «Legal»; после её влития (2026-11-21) пользователь решил включить ссылки в этом change | D10 (редакция 2026-11-21), D17 |
| Q5. Тексты о хранении ключей | (а) по фактическому бэкенду секретов | D9 |
| Q6. Режим не `standard` на шаге 2 | (а) InfoBar называет действующий режим | D7 |
| Q7. Веха | (б) M4 (1.0), против рекомендации (а) | D17; §4.5, §6.1, §10.1, §10.3 дорожной карты; строка D-11 матрицы |

## Решения по двойному ревью 2026-11-21

| № | Замечание | Решение | Где |
|---|---|---|---|
| 1 | Шаг 2 утверждает `standard` при непрочитанных фактах | `FactsLoading` — индикатор без режима; `FactsUnavailable` — нейтральный текст со ссылкой на «Agents & modes» | D7; spec «Шаг «Permissions»» |
| 2 | Зонд и мастер видят разные конфиги | мастер открывается по тому же `EditableSettings`, что у зонда (поле `OnboardingFacts`) | D6, D8; spec «Шаг «Choose a model» и мастер провайдера» |
| 3 | Зонд читает проектный слой `cwd` процесса | снимок зонда с `cwd: codelabHome`, как у мастера: только слои без проекта | D6; spec «Пропуск шага выбора модели» |
| 4 | Нет пути логов при недоступных фактах | подпись каталога логов — из composition root, вне фактов | D9; spec «Шаг «Privacy»» |
| 5 | `settings.open_skipped` без `reason` | design не меняется, код приводится к D1 | D1 |
| 6 | Мастер появляется после ухода с шага 3 | `wizardStarted`/`wizardEnded`: навигация шага блокируется; диалог не показывается, если шаг уже другой | D8; spec «Шаг «Choose a model» и мастер провайдера» |
| 7 | `onFinished` после `close()` | после `await` при `isClosed` — выход; `finishOnboarding` на закрытом Cubit — no-op | D5; spec «Завершение onboarding…» |
| 8 | Формулировки о позднем итоге и `close()` | признак `_factsResolved` + `isClosed`; `close()` завершает ожидание фактов | D6; `concurrency.md` §47в |

## Open Questions

Открытых вопросов нет.
