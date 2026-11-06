## Why

Настроить модель встроенного агента в codelab-app сегодня нельзя: страницы Providers и MCP servers нет, провайдера и ключ можно задать только правкой `~/.codelab/config.yaml` или командами `codelab provider add` / `codelab secret set` с полным набором флагов. Встроенный агент без провайдера не подключается, и пользователь видит только текст ошибки конфига. В CLI тоже нет мастера: `codelab provider add` без `--kind`, `--model` и `--context-window` даёт код `64`. Токен WebSocket-профиля можно взять только из переменной окружения, а app, запущенное из Finder, переменных оболочки не видит.

Change `add-app-settings-shell` (A, архив `2026-11-05-add-app-settings-shell`) построил оболочку настроек и страницу «Connection» и явно передал этому change (B) остальное (design.md A, D13, D18; `delivery-roadmap.md` §10.1, §10.3). Решения пользователя 2026-11-04: два change, A затем B. В B входят:
- страницы Providers и MCP servers;
- мастер провайдера;
- хранение токенов профилей в хранилище секретов агента («Use stored secret», «Store a new token»);
- зависимость app от `codelab_setup`;
- в CLI — мастер и `/settings`.

Устройство уже описано в `dart-agent-and-clients` §12.4.2–§12.4.6, §12.4.8, §12.4.9, SETUP-1…SETUP-22. Reference UI/UX — холст `docs/design/claude-design/`: артборды `Providers`, `Wizard`, `Mcp`, `AddProfile`, `Connection`, `CliSetup`, `CliSettings`. Отступления от холста перечислены в design.md (D24) и согласуются с пользователем.

## What Changes

- **Мост `codelab_setup`** получает потребителей и состав §12.4.2:
  - основной барель: `SecretValue`, `SettingsAccess`/`resolveSettingsAccess`, порт `AgentConfigStore` с `AgentConfigSnapshot` и `ConfigSaveOutcome`, модели представления (`ProviderEntryView`, `KeyStatusView`, `McpServerEntryView`), `McpServerDraft`, мастер `ProviderSetupFlow` с пресетами, `ProviderCheck`/`HttpProviderCheck`, `ProviderSetupCommitter`, `ProviderReadiness`, реэкспорт чистых типов ядра (`ConfigEdit`, `ConfigSnapshot`, `ConfigTarget`, `SettingsRegistry`, `SecretNames` и др.);
  - `io.dart`: `FileAgentConfigStore`, клиентский доступ к секретам `ClientSecretAccess`, `ioProviderCheck()`;
  - в allowlist моста добавляется `http`.
- **`codelab_agent_io`**: `ClientSecretAccess` — выбор бэкенда по `secrets.backend` пользовательского слоя, запись и удаление через `SecretAdmin`, чтение без кэша с переопределением `CODELAB_SECRET_*`, как у резолвера агента.
- **Ядро и `codelab_embedded`**: поток состояний MCP-серверов сессии и API встроенного агента «состояние MCP и переподключение сервера» для живой таблицы страницы (OQ4 `17-5-agent-setup.md`). ACP не меняется.
- **Kit `codelab_client_core`**:
  - вторая форма ссылки на токен `secret:<имя>` в `ProfileTokenRef`;
  - порт `ProfileSecrets` и `SecretText`;
  - запись профиля с новым токеном в порядке «секрет → профиль» с откатом (`ProfileCommitter`);
  - проверка нового токена до записи;
  - чтение `secret:`-ссылки в `ProfileSecretSource`.
- **codelab-app**:
  - страница «Providers»: список провайдеров с источником и статусом ключа, «Default model», «Key storage», Check, Edit, Remove, состояние только для чтения у удалённого и стороннего агента;
  - мастер `ProviderWizardDialog`;
  - страница «MCP servers»: состав из конфига, редактор с секретными заголовками и `env`, Remove, «Disable here» для проектного слоя, панель «Agent status»;
  - «Add connection profile» получает «Use stored secret» и «Store a new token»;
  - «Remove» профиля предлагает удалить собственный секрет токена;
  - строка WebSocket-профиля показывает секрет и его наличие.
- **CLI**:
  - `codelab provider add` на TTY без обязательных флагов запускает мастер; клиентские флаги `--preset`, `--skip-check`, `--yes` проводят тот же автомат без вопросов;
  - мастер первого запуска для встроенного агента на TTY (U-17);
  - `/provider add|list|remove` и `/settings` в REPL (список и пикер по реестру) и в `--ui tui` (мастер на том же автомате по артборду `CliSetup` и экран `CliSettings` по ключам реестра);
  - токен профиля `secret:<имя>` читается из того же хранилища, что у app.
- **Сторож:**
  - `codelab_setup` в allowlist app;
  - `package:codelab_setup/io.dart` в app — только из `lib/app/`;
  - `dart:io` запрещён в `features/settings/presentation/` (SETUP-9).

**BREAKING:** нет. Формат `profiles.json` (`version: 1`) и `config.yaml` прежний; старые профили с `env:` работают как раньше. Изменения поведения CLI:
- `codelab provider add <id>` на TTY без флагов вместо кода `64` открывает мастер; без TTY — прежний код `64`;
- `codelab` со встроенным агентом без провайдера на TTY открывает мастер вместо подключения, которое кончалось ошибкой конфига. Без TTY и в `-p` поведение прежнее (решение Q4).

## Не входит

- Хранилища секретов ОС (`keychain-macos`, Secret Service, Windows Credential Manager) — активный черновик `add-agent-os-secret-backends` после 1.0. B работает с бэкендами 1.0 (`env` и `file`) и не меняет их; подключение хранилищ ОС меняет только `openSecretStore` (§12.4.2, «Хранилище в 1.0»), и UI B получает их без правок.
- Onboarding app (D-11, артборд `Onboarding`) — отдельный change вместе с `OnboardingDestination` из `add-app-navigation-shell` (решение Q3).
- Вход по подписке (L-17, `SignIn`, OAuth) и пресеты после MVP (§17.10.2: Gemini, Kimi, MiniMax, Z.AI) — решение Q5.
- Остальные страницы групп Agent и App (Agents & modes, Permissions & tools, Redaction, Skills & extensions, Code & web, General, Appearance, Keyboard).
- Сторож запуска (`add-app-boot-watchdog`) и `ClientWorkspace.restart`.
- Правка команды, URL и токена существующего профиля: в 1.0 у профиля есть только «Rename» и «Remove» (§12.4.9, шаг 8).
- Агентские команды `/mcp enable|disable` и `/tools` (артборд `CliMcp`): это команды агента, клиент их только отправляет.
- Смартфон и планшет (`PhoneProviders`, `PhoneSettings`, `TabletSettings`): мобильной сборки нет (§12.8).
- Никаких изменений ACP: новых методов, полей и `_meta` нет (SETUP-14).

## Capabilities

### New Capabilities
- `client-agent-setup`: общая для CLI и app логика настройки Dart-агента в мосте `codelab_setup`:
  - доступ к настройкам по профилю (`SettingsAccess`);
  - снимок и запись конфига (`AgentConfigStore`);
  - мастер провайдера с проверкой `/models` и порядком «секрет → конфиг»;
  - готовность провайдера;
  - черновик MCP-сервера;
  - клиентский доступ к секретам.

### Modified Capabilities
- `app-settings`:
  - ADDED: страницы «Providers» и «MCP servers», мастер провайдера, доступ только для чтения, события журнала Providers и MCP;
  - MODIFIED: «Add connection profile» (токен из хранилища секретов), строка профиля (источник `secret:`), «Rename» и «Remove» (удаление собственного секрета), события журнала настроек.
- `acp-client-kit`:
  - MODIFIED: ссылка на токен профиля (форма `secret:<имя>`);
  - ADDED: запись профиля с новым токеном и откатом, проверка нового токена из памяти, отказ рукопожатия из-за токена (D25).
- `codelab-cli`:
  - MODIFIED: профили подключения (токен `secret:`, `profiles show`), подкоманды `provider` и `mcp` (мастер на TTY, клиентские флаги);
  - ADDED: мастер первого запуска, `/provider` и `/settings` в REPL и TUI, отказ подключения из-за токена (D25).
- `agent-secrets`: ADDED — клиентский доступ к секретам `ClientSecretAccess`.
- `agent-mcp-client`: ADDED — поток состояний серверов сессии.
- `embedded-agent`: ADDED — состояние MCP-серверов встроенного агента для хоста.
- `codelab-tui`: MODIFIED — кадр TUI (модальный экран мастера и `/settings`, маска секрета) и одобрение в TUI (клавиши зоны одобрения не работают под модальным экраном).
- `agent-workbench-ui`: ADDED — понятная причина отказа подключения из-за токена в баннере и диагностике (D25); баннер «встроенный агент без провайдера» с «Add provider» и переподключением после записи (D26).
- `workspace-architecture`: MODIFIED — сторож: `http` у `codelab_setup`, `codelab_setup` у app, границы `codelab_setup/io.dart` и `dart:io` в app.

## Impact

- **Код:**
  - `packages/dart/codelab_setup` — `lib/src/access/`, `config/`, `provider/`, `mcp/`, `views/`, `lib/src/io/`;
  - `packages/dart/codelab_agent_io/lib/src/secrets/client_secret_access.dart`;
  - `codelab_agent_core` — поток состояний `McpSessionTools`, доступ рантайма к нему;
  - `codelab_embedded` — API состояния MCP;
  - `codelab_client_core/lib/src/connection/` — `profile_token_ref.dart`, `profile_secrets.dart`, `profile_commit.dart`, `profile_probe.dart`;
  - `apps/codelab_desktop/lib/features/settings/` — Cubit-ы и страницы Providers и MCP, мастер, правка `AddProfileCubit` и `ConnectionSettingsCubit`;
  - `apps/codelab_desktop/lib/app/` — сборка `codelab_setup/io.dart`;
  - `packages/flutter/codelab_ui` — виджеты D19;
  - `apps/codelab_cli` — мастер, первый запуск, `/provider`, `/settings`, источник токена.
- **Зависимости:**
  - `codelab_setup` += `http` (уже в allowlist ядра);
  - `apps/codelab_desktop` += `codelab_setup`;
  - сторонних пакетов нет; граф в `README.md` получает ребро `codelab_desktop → codelab_setup`.
- **Данные пользователя:**
  - `config.yaml` пишется только через `ConfigWriter` в слои `user` и `projectLocal` (SETUP-2, SETUP-3);
  - секреты — в бэкенде `secrets.backend` (в 1.0 запись — только в `file`);
  - `profiles.json` — та же версия `1`, новая форма значения `tokenRef: secret:<имя>`. Старая сборка показывает её как неподдерживаемую ссылку без значения (D15 change A).
- **Тесты:**
  - Dart VM и widget-тесты;
  - PTY-e2e CLI на Dart VM;
  - интеграционные тесты app (`embedded_provider_settings_flow_test.dart`, `mcp_settings_flow_test.dart`, дополнение `connection_profiles_flow_test.dart`) в `feature/*` только компилируются, на устройстве их запускает `release/*` (AGENTS.md §21).
- **Документы:**
  - `12-4-first-run-and-settings.md` §12.4.2–§12.4.6, §12.4.9, §12.4.11, §12.4.13;
  - `17-5-agent-setup.md` (OQ4);
  - `delivery-roadmap.md` §10;
  - `agent-parity-goals.md` (D-05, L-24, E-13, U-17, U-19, R-12, U-06);
  - `09-12`, `09-14` (9.6);
  - вложенные `AGENTS.md`: `codelab_setup`, `codelab_agent_io`, `codelab_embedded`, `codelab_client_core`, `apps/codelab_desktop`, `apps/codelab_cli`;
  - `README.md` (граф).
