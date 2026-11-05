Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В каждой итерации сначала пишутся красные тесты, затем код. В скобках — требование спецификации этого change (`capability` «Requirement») или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `codelab_embedded` и мост `codelab_setup`: мост держит схему агента и реэкспорт его типов, его ведёт исполнитель стороны агента, как в changes `add-agent-configuration` и `add-config-writer-and-reload` (design.md, D2);
- `[client]` — `codelab_client_core`, `codelab_client_io`, `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, документы app;
- `[protocol]` — задач нет: ACP и транспорты не меняются (SETUP-14).

Итерации — каждая отдельным PR в `develop` (design.md, D23):
- 0 — документы;
- 1 — токены профилей в хранилище секретов, ребро `codelab_desktop → codelab_setup`, сторож;
- 2 — Providers: просмотр, «Default model», Check, Remove, только для чтения;
- 3 — мастер провайдера в app;
- 4 — CLI: мастер `provider add`, первый запуск, `/provider`, `/settings` в REPL (4a) и оверлеи `--ui tui` — мастер и экран `CliSettings` (4b);
- 5 — MCP servers и «Agent status»;
- 6 — правки UX после ручного прогона, документы и Definition of Done.

Зависимости: 2 ← 1; 3 ← 2; 4 ← 3; 5 ← 2; 6 ← все. Итерации 4 и 5 независимы.

Вопросы Q1–Q7 решены пользователем 2026-11-05 (design.md, «Open Questions»); отступления D24 согласованы. Q8 решён: вариант (i), на экране `/settings` TUI только ключи реестра.

Проверки каждой задачи — только для затронутого (AGENTS.md §21):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` / `fvm flutter analyze` пакета;
- `fvm dart test` / `fvm flutter test` пакета;
- `fvm dart run melos run guard` — при правке импортов и `pubspec.yaml`;
- `fvm dart run melos run web-compile` — при правке `codelab_client_core` и основного бареля `codelab_setup`.

Тесты — на Dart VM и widget-тесты. Интеграционные `integration_test/*` app в `feature/*` только компилируются (`fvm flutter analyze`), на устройстве их запускает `release/<version>` (D22). Временные `CODELAB_HOME` и `shared_preferences` (`SharedPreferences.setMockInitialValues`); процессные и PTY-тесты — с `Timeout(Duration(seconds: 60))`; хранилище секретов в тестах — `file` во временном `CODELAB_HOME` или тестовое хранилище `CODELAB_TEST_SECRET_STORE` (§12.4.13). Маркер утечки — `sk-test-leak-0123456789`.

## 0. Документы (итерация 0)

- [x] 0.1 `[desktop]` Ответы пользователя на Q1–Q7 внесены в design.md («Open Questions», D1, D3, D12, D16, D17, D24), спеки и задачи (2026-11-05).
- [x] 0.1a `[desktop]` Ответ на Q8 (i, 2026-11-05) внесён в design.md (D17, D24) и, если это не (i), — в спеки `codelab-cli`, `codelab-tui` и итерацию 4.
- [x] 0.2 `[desktop]` `12-4-first-run-and-settings.md`:
  - §12.4.2: пресеты MVP в мосте (D2), `ClientSecretAccess` вместо прямого `openSecretStore` (D4), `ioProviderCheck` (D8), `SecretText` и порт `ProfileSecrets` kit (D13);
  - §12.4.4: существующий секрет — «Use the stored key» / «Replace it», проверка без редиректов (D7, D8);
  - §12.4.5: пустое состояние, «applies after Restart agent», «Connect» после записи без агента (D9, D10);
  - §12.4.6: проверка после записи локальной загрузкой вместо `/config check`, статус вне процесса по кнопке (D11, D12);
  - §12.4.9: шаги 4–8 «Add profile» — форма `secret:<имя>`, четыре варианта токена, `tokenSecretExists`, удаление только собственного секрета (D13, D14); `/settings` — список и пикер в REPL, экран `CliSettings` в TUI (D17); `12-2-cli-display-and-input.md` §12.2.7 — модальные экраны TUI (мастер, `/settings`), фокус и одобрения под ними (D17);
  - §12.4.3: первый запуск только на TTY, при ключе без записываемого хранилища — обычный старт (D16);
  - §12.4.11: SETUP-23 (проверочный запрос не следует редиректам), SETUP-24 (секрет провайдера, MCP-сервера и профиля удаляется только после успешного удаления записи, которая на него ссылается); уточнения SETUP-7 (без TTY поведение прежнее — Q4) и SETUP-11 (статус вне процесса только по действию пользователя — Q2);
  - §12.4.13 — тесты этого change (имена из задач ниже).
- [x] 0.3 `[agent]` `agent-core/17-5-agent-setup.md`: OQ4 закрыт — `McpSessionTools.changes` и `AgentRuntime.mcpStatus` (D12); `ClientSecretAccess` рядом с `SecretAdmin` (D4).
- [x] 0.4 `[desktop]` `delivery-roadmap.md` §10.1 (строки 05, 05b, 06, 20) и §10.3 (строка `add-provider-setup-ui`: состав и итерации); `09-12-stage-7-embedded.md` (Should-часть 7.5 → этот change), `09-14-stage-9-switch-default.md` (9.6 — онбординг CLI и D-05 этим change; app-онбординг D-11 — Q3).
- [x] 0.5 `[desktop]` `agent-parity-goals.md`: ссылки на change в строках D-05, L-24, E-13, U-17, U-19, R-12, U-06 без изменения статуса (статусы — в 6.3).
- [ ] 0.6 `[desktop]` Вложенные `AGENTS.md` — правила, которые вводят итерации; каждый исполнитель правит свой файл в начале своей итерации:
  - `codelab_setup/AGENTS.md` §1–§3 (`[agent]`, итерации 1–3, 5): состав барелей, `http`, «что придёт позже» сокращается;
  - `codelab_agent_io/AGENTS.md` (`[agent]`, итерация 1): `ClientSecretAccess`;
  - `codelab_embedded/AGENTS.md` (`[agent]`, итерация 5): `mcpStatus`;
  - `codelab_client_core/AGENTS.md` (`[client]`, итерация 1): `SecretTokenRef`, `ProfileSecrets`, `SecretText`, `ProfileCommitter`;
  - `apps/codelab_desktop/AGENTS.md` (`[desktop]`, итерация 1): раздел «Секреты» и «Профили подключения» — токен `secret:`, `codelab_setup/io.dart` только в `lib/app/`; итерации 2, 5 — страницы;
  - `apps/codelab_cli/AGENTS.md` (`[client]`, итерация 4): мастер, первый запуск, `/provider`, `/settings`, источник токена.

## 1. Токены профилей в хранилище секретов (итерация 1)

Красные тесты:
- [x] 1.1 `[agent]` `codelab_agent_io/test/secrets/client_secret_access_test.dart` (agent-secrets «Клиентский доступ к секретам»; D4): все четыре сценария — порядок «переменная, затем бэкенд», без кэша, бэкенд по пользовательскому слою (`file`, битый YAML → `env` с причиной), маркер не утекает. `codelab_setup/test/client_secret_access_exports_test.dart` — `ClientSecretAccess` строится через один `io.dart`. `secret_read_only_hint_test.dart` — подсказка бэкенда только для чтения одна для `SecretCommands`, app и мастера (D3); вывод `codelab secret set` не меняется (`secret_commands_test.dart` зелёный).
- [x] 1.2 `[client]` `codelab_client_core/test/connection/profile_token_ref_test.dart` (acp-client-kit «Ссылка на токен профиля»): сценарии «Формы ссылки», «Без порта хранилища», «Замена секрета видна при следующем подключении»; `secret:Bad Name`, `secret:a/../b` — неподдерживаемые; `toString()` неподдерживаемой ссылки маскирован.
- [x] 1.3 `[client]` `test/connection/profile_secrets_test.dart` и `profile_commit_test.dart` (acp-client-kit «Порт хранилища секретов профилей», «Запись профиля с новым токеном»; D13): `SecretText` не печатает значение; секрет до профиля и откат; `Exists` → `tokenSecretExists` без записи; «Use stored secret» — только `save`; удаление с собственным секретом, чужой и общий секрет не удаляются; ошибка удаления секрета не восстанавливает профиль; перечитывание id до записи секрета.
- [x] 1.4 `[client]` `test/connection/profile_probe_test.dart` — «Новый токен проверяется без записи» (acp-client-kit «Проверка нового токена до записи»).
- [x] 1.5 `[desktop]` Сторож (workspace-architecture «Автоматический сторож границ пакетов»; D20): `pubspec_allowlist_test.dart` — `codelab_setup` в `desktopAllowlist`, `codelab_agent_io` у app — нарушение; `import_guard_test.dart` — сценарии «IO-барель моста настроек вне composition root app» и «dart:io в presentation настроек».
- [x] 1.6 `[desktop]` `apps/codelab_desktop/test/features/settings/application/add_profile_cubit_test.dart` и `presentation/add_profile_dialog_test.dart` (app-settings «Диалог «Add connection profile»», сценарии «Варианты токена», «Хранилище только для чтения», «Новый токен сохраняется в хранилище», «Use stored secret», «Секрет с тем же именем уже есть», «Откат секрета при отказе записи профиля»; правила подтверждения `ws://` для «Use stored secret» и «Store a new token», сброс подтверждения при смене секрета и значения; `Unauthorized: the agent rejected the token` для найденного секрета). Ключи D14.
- [x] 1.7 `[desktop]` `connection_page_test.dart`, `connection_settings_cubit_test.dart` (app-settings «Список профилей на странице «Connection»», сценарий «Секрет токена в строке»; «Rename» и «Remove» профиля», сценарии «Удаление профиля с собственным секретом», «Чужой секрет не удаляется»; события `connection_profile.token_*` — «События журнала настроек без секретов»).
- [x] 1.8 `[client]` `apps/codelab_cli/test/profiles/profile_token_test.dart`, `profiles_command_test.dart` и e2e `test/e2e/connect_profiles_test.dart` (codelab-cli «Профили подключения CLI», сценарий «Токен из хранилища секретов»; `profiles show` — `token: secret <имя> (set|missing)`, `token: env <NAME>`).

Реализация:
- [x] 1.9 `[agent]` `ClientSecretAccess` в `codelab_agent_io/lib/src/secrets/`; `secretReadOnlyHint` вынесен из `SecretCommands._readOnlyHint`; реэкспорт обоих в `codelab_setup/lib/io.dart`; doc-комментарии «почему / для чего / как». 1.1 зелёный.
- [x] 1.10 `[client]` Kit: `SecretTokenRef`, `ProfileSecrets` с результатами, `SecretText`, `ProfileSecretSource(stored:)` без кэша, `ProfileCommitter` (`save`, `remove`), `ProfileProbe(token:)`; экспорт в барель kit. 1.2–1.4 зелёные; `web-compile`.
- [x] 1.11 `[desktop]` `apps/codelab_desktop/pubspec.yaml` += `codelab_setup`; правила `rules.dart` и `desktopAllowlist`; комментарий «stage 7» заменён правилом; `README.md` — ребро `desktop --> setup` и пояснение. 1.5 зелёный, `melos run guard` зелёный.
- [x] 1.12 `[desktop]` `lib/app/`: `ClientSecretAccess.open` с `CODELAB_HOME` и окружением `ConnectionEnvironment`; адаптер `ProfileSecrets` поверх него; `ProfileSecretSource(Platform.environment, stored: …)` в `ConfigTransportResolver` и `ProfileProbe`. Событие `secrets.client.backend`.
- [x] 1.13 `[desktop]` `AddProfileCubit`/`AddProfileState`: варианты токена D14, `SecretText` в черновике (сброс при закрытии), проверка с новым токеном, запись через `ProfileCommitter`; `AddProfileDialog` — «Use stored secret» (ComboBox), «Store a new token» (`PasswordBox`), подписи и подсказки D3, D14. `ConnectionSettingsCubit` — строка токена `secret:` (`isSet`), «Remove» с флажком собственного секрета через `ProfileCommitter.remove`; события D18. 1.6, 1.7 зелёные.
- [x] 1.14 `[client]` CLI: `run.dart` собирает `ProfileSecrets` поверх `ClientSecretAccess` и передаёт его в `ProfileSecretSource`; `profiles show` печатает источник токена. 1.8 зелёный.
- [x] 1.15 `[desktop]` `integration_test/connection_profiles_flow_test.dart` — вариант «Store a new token»: токен лежит в тестовом хранилище, `profiles.json` содержит `secret:` и не содержит значения (§12.4.13). В `feature/*` — только `fvm flutter analyze`.

Правки по двойному ревью итерации 1 (решения пользователя и оркестратора 2026-11-05; design.md D3, D4, D13, D14, D18, Risks):
- [x] 1.16 `[client]` Красные: `selectable_profile_token_secrets_test.dart` (acp-client-kit «Порт хранилища секретов профилей», сценарий «Фильтр имён для «Use stored secret»»: только `codelab/profiles/*`, принятые `ProfileTokenRef`, по алфавиту, без повторов); `profile_commit_test.dart` — «Id занят во время записи секрета», «Имя секрета появилось между проверкой и записью», «Тип ошибки без текста»; `profile_probe_test.dart` — «Пустой новый токен»; `profile_token_ref_test.dart` — «Проверка наличия секрета без чтения значения».
- [x] 1.17 `[client]` Реализация kit: `selectableProfileTokenSecrets`; `errorType` в `ProfileSaveFailed` и `RemoveFailed`; повторная проверка id перед `save` с откатом секрета; явный отказ проверки при пустом `NewSecretToken`; метод `ProfileSecretSource.isSecretMissing` (по `isSet`, без чтения значения) и `secretMissingWarning`. 1.16 зелёный, `web-compile`.
- [x] 1.18 `[client]` Красные CLI: `profile_token_test.dart`, `e2e/connect_profiles_test.dart` — сценарии codelab-cli «Незаданный секрет токена» (stderr и событие `connection_profile.token_secret_missing` с `--verbose`, только `profile_id`), «test-scenario читает секрет профиля»; адаптер `ProfileSecrets` CLI: `SecretUpdated` → `Exists`.
- [x] 1.19 `[client]` Реализация CLI: предупреждение перед подключением во всех режимах, `test-scenario` получает тот же `ProfileSecretSource`, адаптер CLI выровнен с адаптером app (`SecretUpdated` → `Exists`, `configProblem`). 1.18 зелёный.
- [x] 1.20 `[agent]` Красный `client_secret_access_test.dart` — сценарии agent-secrets «Бэкенд по пользовательскому слою» (`configProblem`) и «Обычный auto без проблемы конфига»; реализация `ClientSecretAccess.configProblem`. Зелёный.
- [x] 1.21 `[desktop]` Красные: `client_profile_secrets_test.dart` (переоткрытие по фабрике `openSecrets`, `SecretUpdated` → `Exists`, причина `configProblem`, поле `reason` у `secrets.client.backend`); `add_profile_cubit_test.dart`, `add_profile_dialog_test.dart` (состояние `OpeningSecrets`, фильтр «Use stored secret», сценарии app-settings «Ключ провайдера не предлагается как токен», «Битый config.yaml»); `connection_page_test.dart`, `connection_settings_cubit_test.dart` («Правка secrets.backend без перезапуска», «Подключение с незаданным секретом»); события `token_*` с `backend`.
- [x] 1.22 `[desktop]` Реализация: `ReopenableProfileSecrets` и фабрика `openSecrets` в `lib/app/` (переоткрытие при открытии «Connection» и «Add connection profile»; D3, D4); состояние `OpeningSecrets` диалога; предупреждение `secretMissingWarning` и событие `connection_profile.token_secret_missing` в `ConnectionCubit`; причина `configProblem` в UI вместо совета про `secrets.backend: file`, поле `reason` в `secrets.client.backend`; `backend` во всех `connection_profile.token_*`; `FailureRecordingStore` удалён; `SecretUpdated` → `Exists`. 1.21 зелёный.

## 2. Providers: просмотр, «Default model», Check, Remove (итерация 2)

Красные тесты:
- [ ] 2.1 `[agent]` `codelab_setup/test/settings_access_test.dart` (client-agent-setup «Доступ к настройкам агента»): оба сценария; `CODELAB_HOME` из `env` stdio-профиля; без папки проекта `projectLocal` не предлагается.
- [ ] 2.2 `[agent]` `codelab_setup/test/io/file_agent_config_store_test.dart` (client-agent-setup «Снимок и запись конфига агента»): каждое исключение `ConfigWriter` → свой исход, `ConfigInlineSecret` раньше `ConfigRejected`; «Конфликт не перезаписывает файл»; «Литеральный секрет»; источники ключей по слоям.
- [ ] 2.3 `[agent]` `codelab_setup/test/views/provider_entry_view_test.dart` — статус ключа без чтения значения (`in <backend>`, `missing`, `env (set|not set)`, `No key`), `editable == false` для слоя 3, `--config` и окружения.
- [ ] 2.4 `[agent]` `codelab_setup/test/http_provider_check_test.dart` (client-agent-setup «Проверка списка моделей»): «Заголовки и пути» (`MockClient`), 401/403/404/таймаут/TLS → виды отказа, «Тело ошибки скрыто», «Редирект не выполняется» (`HttpServer` loopback через `ioProviderCheck`), закрытие соединения по таймауту; `pubspec_allowlist_test.dart` — `http` в `setupAllowlist`, негативный тест переходит на `dio`; `import_guard_test.dart` — сценарий «http в мосте настроек».
- [ ] 2.5 `[agent]` `codelab_setup/test/provider_remove_test.dart` — `RemoveTable` и новая модель по умолчанию одним `apply`, последнего провайдера удалить нельзя, секрет удаляется только после `ConfigSaved` (SETUP-24).
- [ ] 2.6 `[desktop]` `features/settings/application/provider_settings_cubit_test.dart` (app-settings «Страница «Providers»», «Доступ к настройкам агента на страницах Providers и MCP servers»): строки по слоям, `editable`, статус ключа без чтения значения (SETUP-1), «Check с неверным ключом», «Закрытие страницы во время Check» (номер проверки), «Удаление провайдера модели по умолчанию», «Последний провайдер», «Конфликт записи», `Unreadable` для битого `config.yaml`, `ReadOnly` для WebSocket и стороннего агента без чтения файла, пустое состояние, «Active in this session» по `WorkspaceState`.
- [ ] 2.7 `[desktop]` `presentation/providers_page_test.dart` — разметка D10 и ключи; `settings_shell_test.dart` — сценарии «Три страницы группы Agent» (в этой итерации — Connection и Providers) и «Поиск ключа API».
- [ ] 2.8 `[desktop]` `codelab_ui`: `codelab_key_value_list_test.dart` (D19).

Реализация:
- [ ] 2.9 `[agent]` `codelab_setup`: `SecretValue`, `SettingsAccess`/`resolveSettingsAccess`, `AgentConfigStore`/`AgentConfigSnapshot`/`ConfigSaveOutcome`, модели представления, `ProviderCheck`/`HttpProviderCheck`, реэкспорт типов ядра; `io.dart` — `FileAgentConfigStore`, `ioProviderCheck`; `pubspec.yaml` += `http`; `setupAllowlist` += `http`. 2.1–2.5 зелёные, `web-compile`, `guard`.
- [ ] 2.10 `[desktop]` `codelab_ui`: `CodeLabKeyValueList` с превью. 2.8 зелёный.
- [ ] 2.11 `[desktop]` `lib/app/`: сборка `FileAgentConfigStore`, `ioProviderCheck` и адаптера Check (ключ читается и сразу передаётся проверке); `ProviderSettingsCubit`; `ProvidersPage` (`settings-providers`); `SettingsPage.providers` в `default_settings_pages.dart`; ключевые слова поиска; события `provider_settings.*`. 2.6, 2.7 зелёные.
- [ ] 2.12 `[desktop]` `integration_test/embedded_provider_settings_flow_test.dart`, шаги 2, 5, 6 §12.4.13 (Check с неверным ключом, Remove с флажком, WebSocket-профиль только для чтения). В `feature/*` — только `fvm flutter analyze`.

## 3. Мастер провайдера в app (итерация 3)

Красные тесты:
- [ ] 3.1 `[agent]` `codelab_setup/test/provider_setup_flow_test.dart` (client-agent-setup «Мастер провайдера», «Значение секрета в памяти клиента»): «От пресета до записи», read-only бэкенд без `StoreSecret` с причиной, «Отказ проверки без пропуска», `SkipCheck` только после подтверждения с предупреждением (SETUP-4), `notFound` → ручная модель и вариант с `/v1`, неизвестное окно → `EnteringModelDetails`, id custom-хоста и суффиксы, «Поздний результат проверки», «Существующий секрет», `http://` к нелокальному хосту требует подтверждения и сбрасывается правкой, событие не к месту игнорируется, «Значение не печатается», «Один автомат для двух клиентов» (общий набор событий).
- [ ] 3.2 `[agent]` `codelab_setup/test/provider_setup_commit_test.dart` (client-agent-setup «Порядок записи провайдера»): «Откат созданного секрета», «Ранее существовавший секрет сохраняется», «Хранилище отказало».
- [ ] 3.3 `[agent]` `codelab_setup/test/provider_readiness_test.dart` (client-agent-setup «Готовность провайдера»).
- [ ] 3.4 `[desktop]` `features/settings/application/provider_wizard_cubit_test.dart` и `presentation/provider_wizard_dialog_test.dart` (app-settings «Мастер провайдера в app»): шаги и строка шагов, блокировка Cancel/Esc в `Saving`, «Esc во время проверки», «Только переменная при read-only бэкенде», баннеры после записи (`applies after Restart agent`, `Connect to start the agent…`), конфликт → «Review» с баннером, «This project only» только с папкой проекта, «Маркер не утекает из мастера».
- [ ] 3.5 `[desktop]` `codelab_ui`: `codelab_step_breadcrumb_test.dart` (D19).

Реализация:
- [ ] 3.6 `[agent]` `codelab_setup`: `ProviderPreset` и таблица (D2), `ProviderSetupFlow`, `ProviderSetupPlan`, `ProviderSetupCommitter`, `ProviderReadiness`/`checkProviderReadiness`; подсказка окна из каталога моделей ядра (реэкспорт функции поиска). 3.1–3.3 зелёные, `web-compile`.
- [ ] 3.7 `[desktop]` `codelab_ui`: `CodeLabStepBreadcrumb` с превью. 3.5 зелёный.
- [ ] 3.8 `[desktop]` `ProviderWizardCubit`, `ProviderWizardDialog` (`provider-wizard`, разметка артборда `Wizard`), «Add provider» и «Edit» страницы; `ProviderSetupCommitter` поверх `ClientSecretAccess.admin` и `FileAgentConfigStore`; события `provider_wizard.*`. 3.4 зелёный.
- [ ] 3.9 `[desktop]` `integration_test/embedded_provider_settings_flow_test.dart`, шаги 1, 3, 4 §12.4.13 (мастер до «Save» с ключом в тестовом хранилище и моделью в селекторе композера; «Edit» с `KeepStoredSecret`; конфликт). В `feature/*` — только `fvm flutter analyze`.

## 4. CLI: мастер, первый запуск, `/provider`, `/settings` (итерация 4)

Итерация идёт двумя PR: 4a — подкоманда, первый запуск и REPL (4.1–4.8); 4b — оверлеи `--ui tui` (4.9–4.16). 4b ← 4a.

### 4a. Подкоманда, первый запуск, REPL

Красные тесты:
- [ ] 4.1 `[client]` `apps/codelab_cli/test/setup/provider_wizard_cli_test.dart` на фейковом терминале (codelab-cli «Подкоманды codelab provider и codelab mcp»): вопросы и тексты артборда `CliSetup` с реальным бэкендом, скрытый ввод ключа (Ctrl+R, Ctrl+U), Ctrl+C → `130` без записи, read-only бэкенд без варианта «Store…», клиентские флаги (`--preset`, `--yes`, `--skip-check`) → те же события, недостающий флаг с `--yes` → `64`.
- [ ] 4.2 `[client]` `test/setup/first_run_test.dart` (codelab-cli «Мастер первого запуска CLI»): ветки `ProviderReady`, `ConfigBroken`, `NoProviderConfigured`, `ProviderKeyMissing` (записываемый и read-only бэкенд); без TTY и в `-p` готовность не вычисляется; внешний агент — без мастера; в `--ui tui` первый запуск построчный и идёт до старта экрана (D17).
- [ ] 4.3 `[client]` `test/repl/commands/provider_test.dart`, `settings_test.dart` (codelab-cli «Команды /provider и /settings в REPL и TUI», сценарии «Изменение настройки», «Секретный ключ не редактируется», «Удалённый агент»): `--local`, `--reset`, пометка `(applies after restart)`, `PickerSpec` списка и значений, слой 3 не пишется.
- [ ] 4.4 `[client]` PTY-e2e `test/e2e/` (REPL и подкоманда): `cli/onboarding-no-key`, `cli/onboarding-headless-no-key` (прежний код `64` и stderr, Q4), `cli/onboarding-broken-config`, `cli/provider-wizard-writes-config` (golden `test/e2e/golden/provider_add_config.yaml`, `config_option_update` и новая модель в `/model`), `cli/provider-wizard-check-unauthorized`, `cli/provider-add-noninteractive`, `cli/settings-remote-read-only` (§12.4.13); сценарии «provider add без флагов без TTY», «Мастер provider add на TTY», «Флаги без пропуска проверки», «Ключ мастера не утекает».

Реализация:
- [ ] 4.5 `[client]` `lib/src/setup/`: построчный мастер поверх `ProviderSetupFlow` (только основной барель моста), выбор стрелками, скрытый ввод. `run.dart`: `provider add` с TTY и клиентскими флагами, порт `SetupCommands` для REPL и TUI, `ClientSecretAccess`, `FileAgentConfigStore`, `ioProviderCheck`. 4.1 зелёный.
- [ ] 4.6 `[client]` `composition_root.dart`: первый запуск по D16. 4.2 зелёный.
- [ ] 4.7 `[client]` REPL: `/provider add|list|remove`, `/settings` через `PickerSpec`; модель строк `SettingFieldView` и выбор слоя записи — общие для REPL и TUI (`lib/src/setup/settings_rows.dart`, без `dart_tui`); справка `/help`, `codelab --help`. 4.3 зелёный.
- [ ] 4.8 `[client]` 4.4 зелёный; тексты `codelab provider add` без клиентских флагов совпадают с `codelab-agent` (`test/e2e/config_write_command_test.dart` зелёный).

### 4b. Оверлеи `--ui tui`

Красные тесты (ядро экрана `lib/src/tui/core/` — чистые тесты кадров без `dart_tui` и `dart:io`, TUI-5):
- [ ] 4.9 `[client]` `test/tui/core/tui_overlay_test.dart`: `TuiModel.overlay` — закрытая иерархия `PickerOverlay | ProviderWizardOverlay | SettingsOverlay`; прежние тесты пикеров `/model`, `/mode`, `/sessions` зелёные без изменения поведения (codelab-tui «Команды и пикеры TUI»).
- [ ] 4.10 `[client]` `test/tui/core/provider_wizard_overlay_test.dart` (codelab-cli «Команды /provider и /settings в REPL и TUI»; codelab-tui «Кадр TUI», сценарий «Маска ключа в кадре»): шаги и тексты `CliSetup` для каждого `ProviderSetupState`; маска `*` по числу рун, Ctrl+R показывает и прячет, Ctrl+U очищает; буфер поля пуст после отправки шага, `Cancel` и закрытия; вставка идёт в поле; ни одна строка кадра, история композера и строка статуса не содержат маркера; `Saving` блокирует Esc; фильтр моделей и `Enter model id manually`; read-only бэкенд без варианта «Store…».
- [ ] 4.11 `[client]` `test/tui/core/overlay_focus_test.dart` (codelab-cli, сценарии «Esc в мастере TUI не отменяет ход», «Одобрение при открытом мастере»; codelab-tui «Одобрение в TUI», сценарий «Запрос при открытом мастере»): Enter не отправляет промпт, Esc и Ctrl+C закрывают оверлей и не отменяют ход, `y`/`n` не отвечают на запрос, строка статуса `approval pending · esc to answer`, после закрытия — зона одобрения.
- [ ] 4.12 `[client]` `test/tui/core/settings_overlay_test.dart` (сценарии «Экран настроек в TUI», «Ключ проектного слоя в TUI»): разметка `CliSettings` — шапка с путями слоёв, разделы реестра без Display/Input/Updates, таблица `key · value · source`, полоса клавиш; ↑↓, Tab, ←→, Enter, `r`, `ctrl+u`, Esc; ключ слоя 3 пишется в `projectLocal` с подсказкой D17; `secret`/`secretName` — `Use codelab secret set <name>`; только чтение для удалённого агента.
- [ ] 4.13 `[client]` PTY-e2e `test/e2e/tui_setup_test.dart` с `--ui tui` (`Timeout(Duration(seconds: 60))`): `cli/tui-provider-wizard` — сценарий «Мастер в TUI» (маркер `sk-test-leak-0123456789` не найден ни в снимке экрана PTY после каждого шага, ни в `cli_history`, ни в логе `--verbose`; ключ только в тестовом хранилище; новая модель в `/model`); `cli/tui-settings` — сценарий «Экран настроек в TUI»; `cli/tui-wizard-approval` — запрос разрешения при открытом мастере не отвечается его клавишами.

Реализация:
- [ ] 4.14 `[client]` `lib/src/tui/core/`: `TuiOverlay`, `ProviderWizardOverlay` (кадры по `ProviderSetupState`, поле ввода с маской), `SettingsOverlay`; маршрутизация клавиш в оверлей и строка статуса одобрения. 4.9–4.12 зелёные.
- [ ] 4.15 `[client]` `lib/src/tui/`: адаптер — события автомату и `states` обратно как `TuiMsg`, `SecretValue` создаётся из буфера при отправке шага ключа; `/provider add` и `/settings` в `tui_command_context.dart` открывают оверлеи; запись через порт `SetupCommands`. 4.13 зелёный.
- [ ] 4.16 `[client]` `apps/codelab_cli/AGENTS.md` §2: модальные экраны TUI, правило «значение секрета в кадре — только маска» и фокус под оверлеем; сторож — `lib/src/tui/core/` по-прежнему без `dart_tui` и `dart:io` (`melos run guard` зелёный).

## 5. MCP servers и «Agent status» (итерация 5)

Красные тесты:
- [ ] 5.1 `[agent]` `codelab_agent_core/test/mcp/mcp_session_changes_test.dart` (agent-mcp-client «Поток состояний серверов сессии»): «Сбой и восстановление сервера», «Поток закрывается с сессией», без повтора последнего значения; `test/runtime/mcp_status_port_test.dart` — `mcpStatus` для сессии без MCP и закрытой сессии — `null`.
- [ ] 5.2 `[agent]` `codelab_embedded/test/embedded_mcp_status_test.dart` (embedded-agent «Состояние MCP-серверов для хоста»): «Статус без промпта», «Закрытие агента»; реэкспорт без `dart:io` — `web-compile` основного бареля.
- [ ] 5.3 `[agent]` `codelab_setup/test/mcp_server_draft_test.dart` (client-agent-setup «Черновик MCP-сервера»): «Секретный заголовок», «Ошибки черновика», значение «не менять» при правке, `${VAR}` и `Bearer ${secret:…}` остаются текстом; `McpServerEntryView` маскирует `args`, `env`, `headers` как `codelab mcp list`.
- [ ] 5.4 `[desktop]` `features/settings/application/mcp_settings_cubit_test.dart` (app-settings «Страница «MCP servers»», «Панель «Agent status» страницы MCP servers»): «Сервер с секретным заголовком», «Отклонённый агентом конфиг» (локальная загрузка, промпта нет), «Сервер проектного слоя», «Удаление с секретами», toggle `enabled`, read-only бэкенд — флажок «Secret» неактивен, существующий секрет — «Replace it»; живая таблица из потока, одна подписка, отмена при смене сессии и `close()`; вне процесса — `/mcp list` только по кнопке, неактивно во время хода, поздний ответ отброшен; `unavailable` без сессии и без `/mcp`.
- [ ] 5.5 `[desktop]` `presentation/mcp_page_test.dart` — разметка артборда `Mcp` и ключи D11; `settings_shell_test.dart` — «Три страницы группы Agent» полностью.
- [ ] 5.6 `[desktop]` `codelab_ui`: `codelab_status_table_test.dart`, `codelab_atomics_test.dart` (`CodeLabMonospaceBlock`) (D19).

Реализация:
- [ ] 5.7 `[agent]` Ядро: `McpSessionTools.changes`, `AgentRuntime.mcpStatus`; `codelab_embedded`: `EmbeddedAgent.mcpStatus`, реэкспорт `McpServerSummary`, `McpServerState`. 5.1, 5.2 зелёные; allowlist ядра (PKG-2) не изменён.
- [ ] 5.8 `[agent]` `codelab_setup`: `McpServerDraft`, `McpServerEntryView`. 5.3 зелёный.
- [ ] 5.9 `[desktop]` `codelab_ui`: `CodeLabStatusTable` (с превью), `CodeLabMonospaceBlock`. 5.6 зелёный.
- [ ] 5.10 `[desktop]` `lib/app/`: `EmbeddedTransportResolver.currentAgent`, порт `EmbeddedMcpStatusSource`; `McpSettingsCubit`, `McpPage` (`settings-mcp`); `SettingsPage.mcpServers` в `default_settings_pages.dart`; ключевые слова поиска; события `mcp_settings.*`. 5.4, 5.5 зелёные.
- [ ] 5.11 `[desktop]` `integration_test/mcp_settings_flow_test.dart`, шаги 1–5 §12.4.13 (в шаге 3 для stdio-агента — `/mcp reload` по кнопке). В `feature/*` — только `fvm flutter analyze`.

## 6. Документы и Definition of Done (итерация 6)

- [ ] 6.1 `[desktop]` Правки UX после ручного прогона итераций 1–5 на macOS-сборке разработчика — подзадачами с красным тестом и реализацией, как задача 4.0 change A; каждое новое отступление от холста — строкой D24 с решением пользователя.
- [ ] 6.2 `[desktop]` Сверка документов с кодом: §12.4.2–§12.4.6, §12.4.9, §12.4.13 (имена тестов и ключей), `17-5` OQ4, roadmap §10, вложенные `AGENTS.md` (каждый исполнитель — свой файл), `README.md`.
- [ ] 6.3 `[desktop]` `agent-parity-goals.md`: статусы D-05, L-24 (без «Sign in»), E-13, U-17, U-19, R-12 (app — токен из хранилища), U-06 — по факту реализации и тестов; D-11 и L-17 — без изменения.
- [ ] 6.4 `[desktop]` DoD:
  - задачи 1–5 выполнены, тесты зелёные, `guard` и `web-compile` прошли;
  - маркер `sk-test-leak-0123456789` не найден в логах тестов, состояниях Cubit-ов, выводе CLI, `config.yaml` и `profiles.json`;
  - ревью `architecture-reviewer` и `acp-safety-reviewer`;
  - пункт ревью: из холста (`dc-runtime.js`, разметка артбордов) ничего не скопировано (AGENTS.md §5).
- [ ] 6.5 `[desktop]` Ручная проверка на macOS-сборке разработчика (не CI, не условие merge):
  - app из Finder с `secrets.backend: file`: «Store a new token» → `codelab -a <id>` подключается тем же токеном;
  - мастер провайдера с настоящим ключом → ход встроенного агента без перезапуска;
  - MCP-сервер stdio → живая таблица, «Reconnect»;
  - `codelab` на пустом `CODELAB_HOME` в терминале → мастер первого запуска;
  - `codelab --ui tui`: `/provider add` с настоящим ключом (маска, Ctrl+R) и `/settings` в iTerm2 и Terminal.app.
