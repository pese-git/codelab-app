## Why

Экран 07 дорожной карты ([`delivery-roadmap.md`](../../../docs/architecture/proposals/delivery-roadmap.md) §10.1) — onboarding codelab-app, цель D-11 ([`agent-parity-goals.md`](../../../docs/architecture/proposals/agent-parity-goals.md), Could, этап 9+). Решением пользователя 2026-11-20 (Q7 (б)) onboarding поднят из M5 в M4 — продукт 1.0: первый публичный `stable` ставят люди, которые впервые видят агента с доступом к файлам и командам, и app должен встретить их так же, как CLI (U-17) (design.md, D17). Поведение описано в [`12-4-first-run-and-settings.md`](../../../docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md) §12.4.9, абзац «Onboarding app». При первом запуске app показывает четыре шага: «What CodeLab does», «Permissions», «Choose a model» и «Privacy». Шаг «Choose a model» использует тот же `ProviderSetupFlow` в `ProviderWizardDialog` и пропускается при `ProviderReady`. По решению Q3 change `add-provider-setup-ui` onboarding вынесен в отдельный change.

Сейчас новый пользователь видит пустое рабочее место. Он открывает папку, агент стартует и падает, и только тогда баннер «No model provider is configured for the embedded agent.» предлагает «Add provider» (spec agent-workbench-ui «Встроенный агент без провайдера»). Ни объяснения, что агент делает в папке и где спрашивает, ни сведений о том, что уходит с компьютера, app до первого хода не даёт. У CLI первый запуск есть (U-17, §12.4.3), у app — нет.

Макеты — экспорт холста `docs/design/claude-design/` от 2026-11-20: граф `NavOnboarding`, артборды 07b, 07, 07c, 07c.1–07c.5 и 07a. Часть их текстов не совпадает со сборкой 1.0, поэтому change их уточняет (design.md, D9).

## What Changes

- **Новый экран app — onboarding** (`OnboardingDestination` в закрытой иерархии `AppDestination`). Его показывают при первом запуске, пока в `shared_preferences` не записан флаг `codelab.app.onboarding_done`. Флаг читается в `main` до `runApp`, как язык и оформление, поэтому первый кадр уже нужный и рабочее место не мигает (design.md, D2, D3).
- **Четыре шага со строкой шагов**, кнопками «Back» и «Next», «Start using CodeLab» на последнем шаге. Закрыть onboarding Esc нельзя. Выход из app до последнего шага покажет onboarding снова (граф `NavOnboarding`, D4).
- **Рабочее место во время onboarding не строится, и агент не стартует.** Триггер «проект, восстановленный при запуске» срабатывает после завершения onboarding. Поэтому провайдер, сохранённый на шаге 3, используется уже при первом старте агента, а баннер «Add provider» не появляется (D5; MODIFIED spec agent-workbench-ui «Агент стартует сам»).
- **Шаг «Permissions»** рассказывает о правилах режима `standard` встроенного агента. Если в конфиге задан другой режим новой сессии, InfoBar называет этот режим. Если профиль по умолчанию — внешний агент, InfoBar говорит, что у агента свои правила (D7).
- **Шаг «Choose a model»** строит карточки пресетов по таблице пресетов мастера. Кнопка «Set up <preset>…» открывает `ProviderWizardDialog` с уже выбранным пресетом и неснимаемым «Make default». Ключ, как и раньше, сохраняется только через хранилище секретов агента и порядок «секрет → конфиг» (SETUP-1, SETUP-5). Готовность провайдера проверяет функция моста `checkProviderReadiness`, с таймаутом. Шаг пропускается при `ProviderReady` и при профиле по умолчанию, который не настраивается из app. Для `ProviderKeyMissing` и `ConfigBroken` шаг показывает пояснение и файл не переписывает. «Set up later» позволяет пройти дальше без провайдера (D6, D8).
- **Шаг «Privacy»** перечисляет, что уходит с компьютера и что остаётся на нём. Пути и способ хранения ключей берутся из сборки, а не из макета: в 1.0 нет связки ключей ОС, есть только `env` или файл `secrets.yaml` (D9). Шаг ничего не просит принять и не пишет запись о согласии (D-29, §12.7.7а). Ссылки «Read the privacy policy» и «Terms of use» скрыты, пока нет страницы «Settings › Legal» и документов `PRIVACY.md` и `TERMS.md` (change `add-privacy-policy`; SETUP-17, D10).
- **Мост `codelab_setup`**: новое значение `ProviderWizardEntry.onboarding` (`onboarding`) для события `provider_wizard.started` (D11).
- **`codelab_ui`**: молекула `CodeLabSetupSteps` — горизонтальная строка нумерованных шагов с отметкой пройденных (D12).
- **Локализация**: все тексты — ARB `en` и `ru` по глоссарию. Имена пресетов, id провайдеров и моделей, пути и имена бэкендов не переводятся.
- **Наблюдаемость**: события `onboarding.*` (логгер `codelab_desktop.onboarding`) без путей, имён секретов, адресов и текстов исключений (D13).

### Для раздела выпуска `CHANGELOG.md`

- При первом запуске app показывает четыре шага настройки: что делает CodeLab, где агент спрашивает разрешения, выбор модели (тот же мастер провайдера, что в «Settings › Providers») и что уходит с компьютера. Пользователи, обновившие app, увидят эти шаги один раз; если провайдер уже настроен, шаг выбора модели пропускается.

## Не входит

- **Onboarding смартфона и планшета** (P17–P20, P11a–P11h, T11–T14, T13a–T13i). Раскладка по ширине и профиль `mobile` приходят на этапе 10 (§12.8, D-21). Экраны отказа проверки P11e–P11h и T13f–T13i на десктопе уже покрыты диалогом мастера (артборд `Wizard`).
- **Страница «Settings › Legal»** — change `add-privacy-policy` (D-18, D-29, тоже M4). Ссылки шага 4 включает тот из двух changes, который вливается вторым (D10, D17); выпуск 1.0 этим не блокируется, но к первому `stable` ссылки включены.
- **Остальные ветки `AppDestination` из `add-app-navigation-shell`**: Boot (сторож запуска D-15), ProjectPicker, оверлеи. Change вводит только ветку Onboarding (D1).
- **Сторож запуска (D-15) и `BootReady`.** В сборке сторожа нет. Onboarding показывается после первого кадра app, а когда сторож появится, — после `BootReady` (§12.4.9).
- **Повторный показ onboarding по команде** (пункт меню, палитры или настроек). Все решения меняются на страницах настроек, на которые ссылаются шаги.
- **Мастер правки провайдера из шага 3 при `ProviderKeyMissing`.** Шаг показывает пояснение и путь «Settings › Providers › Edit» (D8).
- **Согласие с условиями** — его нет по решению D-29.
- **Телеметрия.** Её нет (E-21). Шаг 4 только сообщает об этом и ничего не отправляет.
- **Изменения ACP**: новых методов, полей и `_meta` нет (SETUP-14).

## Capabilities

### New Capabilities

- `app-onboarding` — onboarding codelab-app: показ при первом запуске и флаг, шаги и переходы, пропуск шага модели, мастер провайдера из onboarding, содержание шагов, завершение и старт рабочего места, локализация, события журнала.

### Modified Capabilities

- `agent-workbench-ui` — MODIFIED «Агент стартует сам»: триггер «проект, восстановленный при запуске» срабатывает только после завершения onboarding.
- `workspace-architecture` — ADDED «Onboarding app без dart:io» (правило сторожа).

## Impact

- **Код:**
  - `packages/dart/codelab_setup` — значение `ProviderWizardEntry.onboarding` (`[agent]`);
  - `packages/flutter/codelab_ui` — молекула `CodeLabSetupSteps` (`[desktop]`);
  - `apps/codelab_desktop` (`[desktop]`):
    - `lib/app/navigation/` — `OnboardingDestination`, начальное состояние и `finishOnboarding` у `NavigationCubit`;
    - `lib/core/platform/onboarding_preferences.dart` — порт флага;
    - `lib/app/onboarding_probe.dart` — адаптер: готовность провайдера, бэкенд секретов, действующий режим, подписи путей;
    - `lib/features/onboarding/` — `application/` (`OnboardingCubit`, состояние, порт `OnboardingProbe`), `presentation/` (`OnboardingScreen` и шаги);
    - `main.dart`, `lib/app/app_scope.dart`, `lib/app/codelab_app_widget.dart`, ARB.
- **Зависимости:** новых нет, рёбер графа тоже. Адаптер в `lib/app/` использует `codelab_setup/io.dart` по существующему правилу D20 `add-provider-setup-ui`. Правило сторожа одно новое: `dart:io` запрещён в `apps/codelab_desktop/lib/features/onboarding` (`[desktop]`; design.md, D15). Граф в `README.md` не меняется, allowlist ядра (PKG-2) не затронут.
- **ACP:** без изменений.
- **Данные пользователя:**
  - новый ключ `shared_preferences` — `codelab.app.onboarding_done` (только `true`);
  - `config.yaml` и хранилище секретов пишет только мастер провайдера, по прежним правилам (SETUP-1…SETUP-6, SETUP-24);
  - `profiles.json` не меняется.
- **Безопасность и приватность:**
  - ключ вводится только в мастере: в `PasswordBox` без подглядывания и внутри `SecretValue`. В состояние onboarding, события и журнал он не попадает;
  - тексты шагов 1 и 4 не обещают того, чего нет в сборке: связки ключей ОС, ссылок на документы и т. п. (D9, D10);
  - onboarding не открывает сетевых соединений, кроме проверки `/models` в мастере (SETUP-10, SETUP-23).
- **Документация:**
  - §12.4.9 (абзац «Onboarding app») и §12.4.1 `dart-agent-and-clients`;
  - строка 07 и §10.3 `delivery-roadmap.md`, строка D-11 `agent-parity-goals.md`;
  - `state-management.md` §63в, `concurrency.md` §47в;
  - `apps/codelab_desktop/doc/user-guide.md` (раздел «Первый запуск»), `AGENTS.md` и `README.md` app;
  - `codelab_setup/AGENTS.md` (значение `onboarding`), `l10n-glossary.md`.
