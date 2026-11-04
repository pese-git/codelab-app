## Why

У codelab-app нет экрана настроек. Подключение настраивает модальный `ConnectionSetupDialog` — форма из одного профиля, которая живёт только в памяти и пропадает при перезапуске. Кнопка «Settings» в сайдбаре открывает этот же диалог. CLI уже хранит профили в `~/.codelab/profiles.json`, app этим файлом не пользуется. В итоге профиль, настроенный в одном клиенте, не виден в другом, а для каждой будущей страницы настроек (Providers, MCP servers — change `add-provider-setup-ui`) негде появиться.

Документы уже описывают целевое состояние:
- `dart-agent-and-clients` §12.4.9 — навигация настроек, страница «Connection» и диалог «Add connection profile», инварианты SETUP-17, SETUP-19…SETUP-22;
- §12.3 A13 и DSK-24 — `AppDestination`, `NavigationCubit`;
- холст Claude Design — артборды `Connection` (20), `AddProfile` (20a), `General` (26), `Components` (00).

Этот change — первый из двух по настройкам: он вводит оболочку и первую настоящую страницу. Без них второй change `add-provider-setup-ui` встраивать некуда.

## What Changes

- **Навигация app.** В `apps/codelab_desktop/lib/app/navigation/` появляются `AppDestination` (`WorkbenchDestination`, `SettingsDestination(page)`) и `NavigationCubit`. Настройки открываются сочетанием Cmd/Ctrl+, и кнопкой «Settings» в сайдбаре; Esc и «Back» возвращают в workbench к той же сессии. Открывается последняя страница (`codelab.settings.last_page`), при первом открытии — «Connection». Остальные экраны A13 и сочетания (палитра «Go to», Cmd/Ctrl+O, …) в этот change не входят: `add-app-navigation-shell` сужается до них.
- **Оболочка настроек.** `NavigationView` с поиском «Find a setting» и группами «Agent» и «App» в фиксированном порядке §12.4.9. Показываются только страницы, у которых в сборке есть содержимое (SETUP-17): в этом change это только «Connection». Ключи тестов — `settings-nav-<page>`. В окне уже 760 px навигация переходит наверх.
- **Страница «Connection».** Список профилей: встроенный агент всегда первым и в `profiles.json` не сохраняется, далее профили из `ProfileStore` (`~/.codelab/profiles.json`, общий с CLI). Строка профиля: выбор профиля по умолчанию, «Test connection», «Connect», «Rename», «Remove». Блок «Behavior»: переключатель «Connect on start» и «Restart agent» — повторное подключение текущим профилем через существующий `ClientWorkspace.reconnect`. Для WebSocket-профиля, пока он подключён, показывается InfoBar «только чтение» о настройках агента. **BREAKING (UI):** `ConnectionSetupDialog`, `TransportSetupPanel` и переключатель типа подключения удаляются; кнопки «Configure connection» ведут на эту страницу.
- **Диалог «Add connection profile».**
  - Типы — по зарегистрированным `TransportResolver` (SETUP-22).
  - stdio: «Command», «Arguments» (`parseShellWords`), «Run in the project folder», «Environment» с отказом для секретоподобных ключей.
  - WebSocket: «URL» (`ws`/`wss`), предупреждение о `ws://` к нелокальному хосту, «Token» — «No token» или «From environment variable» (`tokenRef: env:<NAME>`).
  - Кнопки «Test connection» (только `initialize`, SETUP-20) и «Save» / «Save without test», флажок «Use by default», экран «Profile saved».
  - Логика диалога — `ProfileDraft` и `ProfileProbe` в `codelab_client_core`; app только рисует её.
- **Ссылка на токен.** App и CLI понимают `tokenRef` одинаково — общий `ProfileTokenRef`/`ProfileSecretSource` в kit. В этом change поддерживается только `env:<NAME>` для любой переменной. Значение токена app не принимает и не хранит. Хранение токенов в хранилище секретов агента — change `add-provider-setup-ui`.
- **Виджеты `codelab_ui`.** Без бизнес-логики, по Atomic Design: `CodeLabSettingsNavigation` (organism), `CodeLabSettingsRow` и `CodeLabSettingsSection` (molecules). Строка профиля переиспользует `CodeLabExpanderCard`, `CodeLabBadge` и `CodeLabStatusIndicator`.
- **Профиль по умолчанию.** Без явного выбора — встроенный агент, и в app, и в CLI (решение пользователя 2026-11-04). Это закрывает задачу 9.3 в части профиля по умолчанию.
- **CLI без `--agent` и `-a default`.** **BREAKING (CLI):** `codelab` без `--agent` всегда запускает встроенный агент; `default` — алиас `embedded`, и `-a default` тоже запускает встроенный агент (design.md, D21).
  - Id `default` зарезервирован: `profiles add default …` и `profiles add x default` дают код `64`.
  - Старая запись `default` в `profiles.json` больше не используется: CLI и app предупреждают о ней, файл не перезаписывается, удалить её можно `codelab profiles remove default`.
  - Правило одно для REPL, `--ui tui`, `-p` и `test-scenario`.
  - Без `--agent` CLI не читает `profiles.json`, поэтому битый файл ему не мешает; код `64` за битый файл — только при `-a <id>`.
  - Подсказки о смене правила нет: Dart CLI ещё не выпущен.
  - CLI также переходит на общие `isValidProfileId` и `ProfileSecretSource`.
- **Наблюдаемость.** События `settings.*` и `connection_profile.*` без значений секретов, с `profile_id` и `operation_id`.

## Не входит

- Страницы Providers, MCP servers и остальные страницы групп Agent и App, мастер провайдера, `SettingsAccess`, `AgentConfigStore`, CLI-мастер и `/settings` — change `add-provider-setup-ui` и следующие. Оболочка оставляет для них точки расширения (design.md, D3).
- `ClientWorkspace.restart` с `session/cancel` и завершением процесса (§12.6.7, U-26, Could) — отдельный change. Здесь «Restart agent» — существующее переподключение.
- Сторож запуска (`add-app-boot-watchdog`). «Connect on start» выполняется после первого кадра, без шагов сторожа.
- D-10 «Join a session started in the CLI» как функция: lease и `_meta.codelab.lease` не вводятся. На странице — только статичная справка (D9).
- Хранение токенов в хранилище секретов агента — переходит в change `add-provider-setup-ui`:
  - «Use stored secret», «Store a new token»;
  - порт `ProfileSecrets` поверх `ClientSecretAccess` (`codelab_setup/io.dart`), `SecretText`;
  - порядок записи «секрет → профиль» с откатом и удаление `codelab/profiles/<id>/token` при «Remove»;
  - зависимость app от `codelab_setup` и правило сторожа для её `io.dart`.
- Хранилища ключей ОС (`add-agent-os-secret-backends`, после 1.0).
- Редактирование команды, URL и токена существующего профиля: в 1.0 есть только «Rename» и «Remove» (§12.4.9, шаг 8). `codelab profiles add` в виде диалога CLI — тоже не здесь.
- Никаких изменений ACP: новых методов, полей и `_meta` нет.

## Capabilities

### New Capabilities
- `app-settings`: навигация настроек codelab-app (`AppDestination`/`NavigationCubit` в части настроек), оболочка с группами и поиском, страница «Connection» с профилями, диалог «Add connection profile», «Connect on start», «Restart agent», события лога настроек.

### Modified Capabilities
- `agent-workbench-ui`: удаляется требование «Connection profile is edited in a modal dialog»; «Тип подключения «Встроенный агент»» и «Project selection is independent of the connection type» переписываются под профили: встроенный агент — первая строка списка, а не тип в форме; «Run in the project folder» — поле stdio-профиля.
- `acp-client-kit`: черновик профиля `ProfileDraft` с правилами id и полей, проверка `ProfileProbe`, ссылка на токен `ProfileTokenRef` (только `env:<NAME>`) и источник `ProfileSecretSource`, классификатор `classifyProbeFailure`. `ProfileStore` теперь используют и CLI, и app.
- `codelab-cli`:
  - без `--agent` и с `-a default` — встроенный агент, `profiles.json` при этом не читается;
  - id `default` зарезервирован, а о старой записи `default` выводится предупреждение;
  - токен — через общий `ProfileSecretSource` (любая `env:<NAME>`, как раньше делал `EnvSecretSource`);
  - правило id `profiles add` совпадает с `ProfileDraft`;
  - старые профили читаются как прежде.
- `cli-scenario-driver`: `test-scenario` без `--agent` и с `--agent default` — встроенный агент.

## Impact

- **Код:**
  - `apps/codelab_desktop`:
    - `lib/app/navigation/`;
    - новая feature `lib/features/settings/` (`application/connection_settings_cubit.dart`, `application/add_profile_cubit.dart`, `presentation/`);
    - `ConnectionCubit` переходит с формы на выбранный профиль;
    - удаляются `connection_setup_dialog.dart` и `transport_setup_panel.dart`;
    - `lib/app/app_scope.dart` — `JsonFileProfileStore` и `ProfileSecretSource` вместо `InMemorySecretSource`.
  - `packages/dart/codelab_client_core/lib/src/connection/` — `profile_draft.dart`, `profile_probe.dart`, `profile_token_ref.dart`.
  - `packages/dart/codelab_client_io` — классификатор ошибок проверки.
  - `packages/flutter/codelab_ui` — три виджета.
  - `apps/codelab_cli` — `profile_arg.dart` (без `--agent` — встроенный агент), справка `--agent` в `cli_args.dart`, `ProfileSecretSource` вместо `EnvSecretSource`, `isValidProfileId` в `profiles add`.
- **Зависимости:** новых нет; allowlist и правила сторожа не меняются. Граф пакетов прежний.
- **Данные пользователя:**
  - `profiles.json` формата `version: 1` остаётся прежним; app пишет его тем же `JsonFileProfileStore`, что CLI;
  - форма подключения app сегодня нигде не сохраняется, переносить из `shared_preferences` нечего (design.md, D7);
  - новые ключи `shared_preferences`: `codelab.settings.last_page`, `codelab.connection.default_profile`, `codelab.connection.connect_on_start`.
- **Тесты:** integration-тесты app, которые настраивают подключение через диалог, переходят на тестовый `profiles.json` и выбор профиля. Прогон на устройстве — только в `release/*` (AGENTS.md §21).
- **Документы:**
  - `12-4-first-run-and-settings.md` (§12.4.9, §12.4.13);
  - `12-3-desktop-display.md` (A13);
  - `12-6-cli-desktop-extras.md` (§12.6.7);
  - `09-11-stage-6-cli-mvp.md`, `09-12-stage-7-embedded.md` (пометки), `09-14-stage-9-switch-default.md` (9.3);
  - `delivery-roadmap.md` §10;
  - `agent-parity-goals.md` (U-06, D-04, R-12, U-26, D-10);
  - `apps/codelab_desktop/AGENTS.md`, `codelab_client_core/AGENTS.md`.
