Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В каждой итерации сначала пишутся красные тесты, затем код. В скобках — требование спецификации этого change или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, документы app;
- `[client]` — `codelab_client_core`, `codelab_client_io`, `apps/codelab_cli`.

Задач `[agent]` нет: хранилище секретов агента переходит в change `add-provider-setup-ui` (решение Q2). Задача `[protocol]` появляется только при условии задачи 3.3.

Итерации — каждая отдельным PR в `develop`:
- 0 — документы;
- 1 — навигация, оболочка, виджеты;
- 2 — страница «Connection», ссылка на токен, переход `ConnectionCubit`, CLI (в том числе правило без `--agent`, D21);
- 3 — «Add connection profile», «Test connection», «Rename», «Remove»;
- 4 — документы и Definition of Done.

Зависимости: 2 ← 1; 3 ← 2; 4 ← все. Вопросы Q1–Q5 решены 2026-11-04 (design.md, «Open Questions»).

Проверки каждой задачи — только для затронутого (AGENTS.md §21):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` / `fvm flutter analyze` пакета;
- `fvm dart test` / `fvm flutter test` пакета;
- `fvm dart run melos run guard` — при правке импортов и `pubspec.yaml`;
- `fvm dart run melos run web-compile` — при правке `codelab_client_core`.

Тесты — на Dart VM и widget-тесты. Интеграционные `integration_test/*` в `feature/*` только компилируются (`fvm flutter analyze`); на устройстве их запускает `release/<version>` (D19). Временные `CODELAB_HOME` и `shared_preferences` (`SharedPreferences.setMockInitialValues`); процессные тесты — с `Timeout(Duration(seconds: 60))`.

## 0. Документы (итерация 0)

- [x] 0.1 `[desktop]` `12-4-first-run-and-settings.md` §12.4.9 — решения, которые уточняют раздел:
  - навигация — только видимые страницы, порог 760 px, ключи `settings-nav-<page>` (D3);
  - строка профиля: профиль по умолчанию против «Connect» (D5);
  - «Restart agent» = `reconnect` до `ClientWorkspace.restart` (D9);
  - справка D-10 без lease (D10);
  - токен в A — только `env:<NAME>`, хранилище секретов и связанные шаги переходят в `add-provider-setup-ui` (D13);
  - «Not tested» вне файла (D14);
  - «Test connection» без встроенного агента (D12).
  
  §12.4.13 — тесты этого change.
- [x] 0.2 `[desktop]` `12-3-desktop-display.md` A13: `AppDestination` вводится двумя changes; `navigation_cubit_test.dart` частично — этот change.
- [x] 0.3 `[desktop]` `delivery-roadmap.md` §10.1 и §10.3: строка `add-app-settings-shell`; `add-app-navigation-shell` сужен; в B перенесено хранение токенов профилей.
- [x] 0.4 `[desktop]` `agent-parity-goals.md`: ссылки на change в строках U-06, D-04, R-12, U-26, D-10 без изменения статуса. `12-6` §12.6.7 — кнопка app до `restart()`. `09-14` 9.3 — часть для app закрывает этот change.
- [x] 0.5 `[desktop]` `apps/codelab_desktop/AGENTS.md`: профили — `JsonFileProfileStore` в `$CODELAB_HOME` (D7), токен профиля — только ссылка `env:` (D13), feature `settings`. `codelab_client_core/AGENTS.md` §1: `ProfileDraft`, `ProfileProbe`, `ProfileTokenRef`, `ProfileSecretSource`. Doc-комментарий порта `ProfileStore` («App этот порт не использует») меняется вместе с кодом в задаче 2.8. Выполняется в начале итерации 2.

## 1. Навигация, оболочка и виджеты (итерация 1)

Красные тесты:
- [x] 1.1 `[desktop]` `apps/codelab_desktop/test/app/navigation/navigation_cubit_test.dart` (app-settings «Переход в настройки и обратно»; D2):
  - `openSettings` без сохранённой страницы → `connection`;
  - сохранённая видимая страница → она;
  - скрытая или неизвестная страница → `connection`;
  - `back()` → `WorkbenchDestination` и `returnTo` активной сессии;
  - ошибка `SettingsPageStore` → предупреждение и `connection`;
  - *новое:* `openSettings` принимает named `page` и required `source`;
  - *новое:* `returnTo` с двумя сессиями — `B` закрыта до `back()` → активной остаётся `A`, а пока `B` открыта, `back()` возвращает к ней;
  - *новое:* повторный `openSettings` при открытых настройках не меняет `returnTo`;
  - *новое:* явная страница во время чтения `last_page` перекрывает поздний результат (номер попытки);
  - *новое:* значение ключа `codelab.settings.last_page` — slug (`mcp-servers`), не имя enum; неизвестный slug → как отсутствие;
  - *новое:* без видимой `connection` → первая видимая; пустой набор → состояние не меняется, событие `settings.open_skipped`;
  - *новое:* ошибки чтения и записи → `settings.last_page_load_failed` / `settings.last_page_save_failed` с `error_type`;
  - *новое:* `back(toSession: id)` активирует сессию с запросом разрешения.
- [x] 1.2 `[desktop]` `apps/codelab_desktop/test/features/settings/presentation/settings_shell_test.dart` с тестовым набором `available` (app-settings «Навигация настроек»; D3):
  - порядок §12.4.9 при любом порядке регистрации;
  - нет заголовка пустой группы;
  - ключи `settings-nav-<page>`;
  - поиск `token` оставляет «Connection», `zzz` даёт `No settings match "zzz"`;
  - ширина 700 px → навигация сверху (`PaneDisplayMode.top`), 800 px → слева (`PaneDisplayMode.expanded`);
  - у каждой страницы `available` есть построитель;
  - *новое:* при первом открытии выбран пункт `settings-nav-connection`;
  - *новое:* заголовки групп — `PaneItemWidgetAdapter`, у пустой группы заголовка нет;
  - *новое:* `SettingsShell` — свой `FocusScope`, Tab и Shift+Tab не выходят за пределы настроек.
- [x] 1.3 `[desktop]` `apps/codelab_desktop/test/features/workbench/presentation/workbench_shell_test.dart` (app-settings «Переход в настройки и обратно», «Рабочее место недоступно с клавиатуры из настроек»; DSK-24, D2/H1):
  - Cmd/Ctrl+, и «Settings» при непустом `available` открывают экран настроек;
  - Esc возвращает к той же сессии с прежним текстом композера;
  - Esc на рабочем месте во время хода отменяет ход;
  - *новое:* Cmd+, (`meta`, macOS) и Ctrl+, (`control`, другие ОС) — оба сочетания по `defaultTargetPlatform`;
  - *новое:* повторное Cmd/Ctrl+, на экране настроек ничего не меняет;
  - *новое:* Esc в настройках во время хода → `back()`, `session/cancel` не отправлен (`FakeAcpTransport` не видит кадра);
  - *новое:* при ожидающей карточке одобрения Tab, Space и Enter в настройках не отправляют ответ на `session/request_permission`;
  - *новое:* ввод текста, Enter и Cmd/Ctrl+Enter в настройках не отправляют `session/prompt`, текст композера не меняется;
  - *новое:* после «Back» фокус в том же `FocusNode`, что до ухода (композер); если узел удалён — в композере активной сессии.
- [x] 1.4 `[desktop]` `packages/flutter/codelab_ui/test/` (D16):
  - `codelab_settings_navigation_test.dart` — группы, выбранный пункт, поиск, режимы `left`/`top`, «Back»;
  - `codelab_settings_row_test.dart`, `codelab_settings_section_test.dart` — заголовок, описание, `trailing`, ключ.

Реализация:
- [x] 1.5 `[desktop]` `codelab_ui`: `CodeLabSettingsNavigation` (`organisms/`), `CodeLabSettingsRow`, `CodeLabSettingsSection` (`molecules/`), экспорт в барель, превью. Без бизнес-логики, doc-комментарии «почему / для чего / как» (AGENTS.md §15).
- [x] 1.6 `[desktop]` `lib/app/navigation/`: `AppDestination` (`WorkbenchDestination`, `SettingsDestination`), `SettingsPage`, `NavigationCubit`, порт `SettingsPageStore` с реализацией на `shared_preferences` (`codelab.settings.last_page`) рядом с Cubit-ом (D2). Workbench остаётся смонтированным.
  - *новое (ревью итерации 1):* `openSettings({page, required source})`, номер попытки против позднего чтения, slug в ключе, первая видимая страница и no-op при пустом наборе, `back({toSession})`, `returnTo` по варианту (а), события `settings.last_page_*_failed` и `settings.open_skipped` (D2, D17).
- [x] 1.7 `[desktop]` `features/settings/presentation/settings_shell.dart`:
  - *новое (ревью итерации 1, H1):* workbench под настройками в `ExcludeFocus` или `Visibility(maintainState: true)`, `SettingsShell` — свой `FocusScope`/`FocusTraversalGroup`, Esc → `back()`, восстановление фокуса; `PaneDisplayMode.expanded`/`top`, заголовки групп — `PaneItemWidgetAdapter` (D2, D3);
  - оболочка, `settingsPageBuilders`, `SettingsSearchIndex`;
  - Cmd/Ctrl+, в `CodeLabWorkbenchShortcuts`;
  - `CodeLabAppWidget` рисует экран по `NavigationCubit`.
  
  В этой итерации `available` пуст, «Settings» открывает прежний диалог (design.md, Migration Plan, п. 2).

- [x] 1.8 `[desktop]` InfoBar ожидающего одобрения (app-settings «Ожидающее одобрение видно из настроек»; D2, D17; решение пользователя 2026-11-04).
  - Красный тест `apps/codelab_desktop/test/features/settings/presentation/settings_pending_approval_test.dart`, ключ `settings-pending-approval`:
    - запрос в фоновой сессии `B` при активной `A` → InfoBar показан, настройки не закрылись;
    - `Back to session` → рабочее место с сессией `B` и карточкой одобрения;
    - при двух сессиях с запросом выбирается активная;
    - запрос снят (ход отменён или соединение потеряно) → InfoBar исчез;
    - в настройках нет кнопок вариантов ответа;
    - автовозврата нет;
    - `settings.pending_approval_shown` пишется один раз, `settings.back_to_approval` — при нажатии, без id запроса и имени инструмента.
  - Реализация:
    - `SettingsShell` читает ожидающие одобрения из `WorkspaceState`/`SessionView` через Cubit рабочего места — без своего источника;
    - InfoBar с кнопкой вызывает `NavigationCubit.back(toSession: id)`;
    - события D17.

## 2. Страница «Connection» (итерация 2)

Красные тесты:
- [x] 2.1 `[client]` `codelab_client_core/test/connection/profile_token_ref_test.dart` (acp-client-kit «Ссылка на токен профиля»; D15):
  - `env:CODELAB_AGENT_TOKEN`, `env:DEVBOX_TOKEN`, пустая и отсутствующая переменная;
  - имя секрета → неподдерживаемая ссылка, `null`;
  - недопустимое имя переменной.
- [x] 2.2 `[desktop]` `apps/codelab_desktop/test/features/settings/application/connection_settings_cubit_test.dart` на временном `profiles.json` (app-settings «Список профилей на странице «Connection»»; D4, D5):
  - встроенный агент первым, остальные в порядке файла;
  - профиль по умолчанию — встроенный агент без явного выбора (D5, D21) и сброс несуществующего id;
  - «Connect» не меняет профиль по умолчанию;
  - `Unreadable` для `version: 2`, файл не изменён;
  - «Current connection (not saved)»;
  - «Remove» недоступна у текущего и отклоняется Cubit-ом и при прямом вызове;
  - источник токена в строке: `No token` / `From $NAME` / не задана / не поддерживается.
- [x] 2.3 `[desktop]` Тот же файл и `connection_cubit_test.dart` (app-settings «Блок «Behavior»», «Предупреждение и справка для удалённого агента»; D8–D10):
  - «Connect on start» вкл/выкл — одно подключение / ни одного;
  - «Restart agent» = `reconnect` текущего профиля, для WebSocket — «Reconnect»;
  - кнопка недоступна без профиля и при `connecting`;
  - InfoBar WebSocket без пути, query и userinfo;
  - неподдерживаемая ссылка на токен — подключение без токена и предупреждение в диагностике.
- [x] 2.4 `[desktop]` Характеризационные тесты (D6):
  - `shell_cubit_characterization/connection_test.dart`, `connection_cubit_test.dart`, `missing_project_folder_test.dart`, `stdio_args_quotes_test.dart` — вызовы формы заменены выбором профиля, исходы прежние;
  - `connection_setup_dialog_embedded_test.dart` заменён на `connection_page_embedded_test.dart`: «Connect» в строке «Embedded agent» подключает встроенного агента, на новой установке «Connect» экрана подключения выбирает встроенного (agent-workbench-ui «Тип подключения «Встроенный агент»»).
- [x] 2.5 `[desktop]` `apps/codelab_desktop/test/features/settings/presentation/connection_page_test.dart`, ключи:
  - строка профиля — `connection-profile-row-<id>`, `connection-profile-default-<id>`, `connection-profile-connect-<id>`, `connection-profile-test-<id>`, `connection-profile-rename-<id>`, `connection-profile-remove-<id>`, `connection-profile-token-<id>`;
  - страница — `connection-add-profile`, `connection-connect-on-start`, `connection-restart-agent`, `connection-remote-read-only`, `connection-join-cli-help`, `connection-profiles-unreadable`.
  
  Случаи:
  - у встроенного нет `test`, `rename`, `remove`;
  - справка D-10 свёрнута и не содержит «Fork».
- [x] 2.6 `[desktop]` `apps/codelab_desktop/test/app/app_scope_profiles_test.dart`:
  - `profiles.json` из `CODELAB_HOME` шва `environment`;
  - `ProfileSecretSource` вместо `InMemorySecretSource`;
  - события `settings.*` без значений.
- [x] 2.7 `[client]` `apps/codelab_cli/test/profiles/` (codelab-cli «Профили подключения CLI»; D15):
  - `profile_token_test.dart` — `env:DEVBOX_TOKEN` и `env:CODELAB_AGENT_TOKEN` через `ProfileSecretSource`, значение не печатается;
  - `profiles_command_test.dart` — `profiles add Dev …` → `64`, файл не изменён; прежний профиль `Old` с заглавной буквой выбирается `-a Old` с токеном.

- [x] 2.13 `[client]` CLI: без `--agent` и с `-a default` — встроенный агент; `default` зарезервирован (D21). Сценарии — codelab-cli «Профили подключения CLI»: «-a default — встроенный агент», «default зарезервирован в profiles add», «Старая запись default в списке», «Удаление старой записи default», «Без --agent битый profiles.json не мешает встроенному агенту», «profiles.json неверной структуры при -a <id>»; cli-scenario-driver «Команда test-scenario»; acp-client-kit «Записи профилей с зарезервированным id».

  Тесты, которые опираются на `default` как профиль из файла, переписываются явно:
  - `test/profiles/profile_arg_test.dart`:
    - «without --agent the profile is "default"» → «without --agent the embedded agent is chosen and the store is not read»;
    - «without --agent and without "default"…» объединяется с ним;
    - новые случаи: `-a default` → встроенный и предупреждение при старой записи, битый файл без `--agent`;
  - `test/profiles/profiles_command_test.dart`:
    - `add default …` и `add x default` → `64` с `default is the built-in agent; use --agent embedded`;
    - `list` и `show default` при старой записи — одно предупреждение без команды записи;
    - `remove default` удаляет запись;
  - `test/run_embedded_test.dart` — «without --agent the "default" profile beats the embedded agent» → встроенный агент и без `--agent`, и с `-a default`;
  - `test/e2e/embedded_agent_test.dart`:
    - «the "default" profile beats the embedded agent» → то же;
    - «-a embedded beats the "default" profile» сохраняется;
  - `test/e2e/connect_profiles_test.dart`, `test/e2e/headless_print_basic_test.dart` («the default profile is used without --agent») — профиль сохраняется под другим id и выбирается `-a <id>`;
  - `test/e2e/codelab_home_tilde_test.dart` — `profiles add default stdio:agent` теперь `64`, тест переходит на другой id;
  - `test/e2e/support/e2e_agent.dart` — хелпер `profiles add default <агент>` переходит на явный id и `-a <id>`;
  - `test/scenario/test_scenario_command_test.dart` — новые случаи:
    - со старой записью `default` без `--agent` и с `--agent default` — встроенный агент;
    - битый `profiles.json` без `--agent` — не `64`.
- [x] 2.15 `[desktop]` `connection_settings_cubit_test.dart` и `connection_page_test.dart` (app-settings «Старая запись default», «Удаление старой записи default из app»):
  - запись `default` не показывается строкой;
  - InfoBar `connection-profiles-ignored-default` без команды записи;
  - «Remove» в InfoBar удаляет запись после подтверждения;
  - событие `connection_profile.default_ignored` без полей записи.

Реализация:
- [x] 2.14 `[client]` `apps/codelab_cli`:
  - `lib/src/profiles/profile_arg.dart`:
    - в `resolveAgentProfile` при `value == null`, `embedded` и `default` возвращать встроенный профиль до обращения к хранилищу;
    - убрать `final id = value ?? defaultProfileId;` и `defaultProfileId`;
    - выбор из файла — через `usableStoredProfiles`;
    - предупреждение о старой записи `default` при `-a default`;
  - `lib/src/profiles/profiles_command.dart`:
    - резерв `default` через `isReservedProfileId` с текстом `default is the built-in agent; use --agent embedded`;
    - `list` и `show default` — без записи и с одним предупреждением;
    - `remove default` работает как прежде;
  - `lib/src/cli_args.dart`: справка `--agent` (~строка 186, «default: profile "default" if it exists, else …») → «default: the embedded agent», doc-комментарий ~строка 112;
  - `test/e2e/support/e2e_agent.dart`: явный id вместо `default`, doc-комментарий `needsStoredProfile`;
  - флаг `provider add --default` не трогать — он про модель.
- [x] 2.8 `[client]` `codelab_client_core`: `ProfileTokenRef`, `ProfileSecretSource`, `isValidProfileId`, `reservedProfileIds`/`isReservedProfileId`, `usableStoredProfiles`; `codelab_client_io`: `JsonFileProfileStore.save` отклоняет зарезервированный id; обновлён doc-комментарий `ProfileStore`; `melos run web-compile`.
- [x] 2.9 `[client]` `apps/codelab_cli`: `ProfileSecretSource` из kit вместо `EnvSecretSource` (класс удалён), `profiles add` проверяет id через `isValidProfileId`.
- [x] 2.10 `[desktop]` `lib/app/`:
  - `JsonFileProfileStore('$CODELAB_HOME/profiles.json')`;
  - `ProfileSecretSource(environment)` в `ConfigTransportResolver`, `InMemorySecretSource` удалён;
  - `SettingsPages(available: {connection})`;
  - «Connect on start» после первого кадра;
  - `ConnectionPreferences` (`codelab.connection.default_profile`, `codelab.connection.connect_on_start`) в `lib/core/platform/` — потребители: настройки, workbench, composition root.
- [x] 2.11 `[desktop]` Workbench и страница:
  - InfoBar старой записи `default` с «Remove» (D5, задача 2.15);
  - `ConnectionCubit` на профилях реализует `ConnectionCommands` (D4, D6), из `SettingsCubit` удалён переключатель папки;
  - `ConnectionSettingsCubit` (`features/settings/application/`) и страница `connection_page.dart`;
  - «Configure connection» и «Settings» ведут в `NavigationCubit.openSettings(connection)`;
  - удалены `connection_setup_dialog.dart` и `transport_setup_panel.dart`.
- [x] 2.12 `[desktop]` Интеграционные тесты, которые настраивали подключение диалогом, переходят на хелпер `support/` «временный `CODELAB_HOME` с `profiles.json` + выбор профиля»: `stdio_connect_flow_test.dart`, `fs_flow_test.dart`, `permission_flow_test.dart`, `prompt_queue_flow_test.dart`, `multi_session_concurrency_flow_test.dart`, `open_project_flow_test.dart`, `plan_progress_checklist_flow_test.dart`, `terminal_flow_test.dart`, а также `command_palette_flow_test.dart` и `session_list_load_flow_test.dart` (дописаны ревью итерации 2). В `feature/*` — только `fvm flutter analyze` (D19).

- [x] 2.16 Исправления ревью итерации 2. Пункты — по сообщению ревью, решения — в design.md:
  - [x] 2.16.1 `[client]` `[desktop]` Ссылка на токен не вида `env:`: значение нигде не выводится. UI и `profiles show` пишут `unrecognized token reference (not supported in this version)`, диагностика — `The token-reference format of profile <id> is not supported in this version; connecting without a token.` (только `profile_id`; формулировка не попадает под `SecretRedactor` `\bToken\s+…`). Тест с маркером `sk-test-leak-…` в `tokenRef` — app-settings «Неподдерживаемая ссылка на токен», codelab-cli «Ссылка не вида env: не выводится» (D13, п. 1 ревью).
  - [x] 2.16.2 `[client]` `-a default`: запись не используется для выбора агента, файл читается только ради предупреждения, ошибка чтения игнорируется. Тест «-a default при битом profiles.json»; синхронизированы specs codelab-cli и cli-scenario-driver, D21 и `apps/codelab_cli/AGENTS.md` (п. 2).
  - [x] 2.16.3 `[desktop]` design.md приведён к коду (п. 3):
    - D4: `connection` — `ConnectionView`, `failure` вместо `banner`, `lastProbes` — итерация 3;
    - `ConnectionCommands` без `current`;
    - D11/D21: API id в `profile_ids.dart`.
    
    Проверить, что код совпадает.
  - [x] 2.16.4 `[client]` `[desktop]` `resolveCodelabHome` в `codelab_client_io`: тесты `codelab_client_io` и обёртки CLI `CodelabHome.resolve`, расхождение с `codelabHomeOf` без `HOME` принято (D7) (`~user/…`, `~` без `HOME` — ошибка); CLI и app используют её; в app недопустимое значение даёт `ConnectionSettingsUnreadable` — сценарий «Недопустимый CODELAB_HOME» (D7, п. 4).
  - [x] 2.16.5 `[desktop]` Строка профиля (D4, п. 5):
    - бейдж `connection-profile-status-<id>` (`Connecting…`/`Connected`/`Failed`, без текста ошибки);
    - заголовок `label` в одну строку с многоточием и подсказкой, `id` при пустом `label` или при `label` вида `stdio:`/`ws://`/`wss://`;
    - сценарии «Заголовок строки», «Бейдж состояния текущего профиля».
  - [x] 2.16.6 `[desktop]` «Restart agent» переподключает профиль последнего принятого подключения (уточнено в 2.16.11); профиль окна меняется только после принятого подключения; номер попытки после каждого `await` — сценарии «Restart agent после неудачного Connect», «Поздняя попытка Connect» (D6, D9, п. 6).
  - [x] 2.16.7 `[desktop]` Блок «Behavior» виден и работает в `ConnectionSettingsUnreadable` (D4, п. 7).
  - [x] 2.16.8 `[desktop]` События D17 (п. 8):
    - `connection_profile.default_unresolved` (warning, `error_type`);
    - `connection_profile.default_reset` (info);
    - `connection_profile.default_ignored` — один раз за жизнь страницы;
    - диагностика stdio — только команда, без аргументов.
  - [x] 2.16.9 `[client]` `JsonFileProfileStore`: уникальный временный файл (pid и случайный суффикс), атомарная запись; тест двух записей без общего `.tmp` (Risks, п. 9).

  - [x] 2.16.10 `[desktop]` MEDIUM-B: до первого принятого подключения профиль окна — последний выбранный, экран подключения и Reconnect работают с ним; после — меняется только после принятия; `ConnectionFormState` → `WindowConnectionState`. Сценарий «Первый Connect не удался» (D6, повторное ревью, п. 1).
  - [x] 2.16.11 `[desktop]` MEDIUM-A: `ConnectionCommands.restartTarget` — один источник для «Restart agent» (подпись, доступность), метки «Current» и бейджа. Сценарий «Connect к B не удался при живом A: Current и Restart — A» (D4, D6, D9, п. 2).
  - [x] 2.16.12 `[desktop]` Safety LOW: отказ Connect до подключения (пустая команда, нет папки) при живом соединении оставляет `connected`, причина — в `connectionMessage` и диагностике, потеря даёт `lost`. Сценарий «Отказ до подключения при живом соединении» (D6, п. 3).
  - [x] 2.16.13 `[client]` `UnsupportedTokenRef.toString()` → `UnsupportedTokenRef(<redacted>)`; тест с маркером `sk-test-leak-…` (D15, п. 6).
  - [x] 2.16.14 `[desktop]` `title` (label или id по правилу заголовка) в подтверждении «Remove» и в подписи профиля на экране подключения и в баннере, вместо сырого `label` (app-settings «Список профилей…», «Rename» и «Remove» профиля»; п. 7).
  - [x] 2.16.15 `[client]` Тест codelab-cli «Ссылка не вида env: не выводится»: `codelab -a devbox -p hi --verbose` с `tokenRef: sk-test-leak-…` — ни stdout, ни stderr не содержат маркера.
  - [x] 2.16.16 `[desktop]` «Current» только у принятого профиля в `Connected`/`Reconnecting`; бейдж попытки у строки `ConnectionCommands.attemptProfile`; подпись «Restart agent» называет цель (`Reconnects <title>…`). Сценарии «Бейдж состояния текущего профиля», «Бейдж после принятого подключения», «Connect к несуществующему бинарю разрывает встроенного агента» (D4, D6, D9; решение пользователя 2026-11-05).
  - [x] 2.16.17 `[desktop]` Гонка: отказ до обращения к workspace не меняет номер попытки и не вытесняет попытку в kit; при живом соединении причина только в диагностике, `connectionMessage` не меняется. Сценарии «Отказ до kit не вытесняет попытку в kit», «Connect к B отклонён до обращения к workspace при живом A», «Отказ до подключения при живом соединении» (D6; safety MEDIUM и nit).

  Родитель 2.16 отмечается, когда выполнены все подзадачи.

## 3. «Add connection profile», «Rename», «Remove» (итерация 3)

Красные тесты:
- [ ] 3.1 `[client]` `codelab_client_core/test/connection/profile_draft_test.dart` (acp-client-kit «Черновик профиля подключения»; SETUP-19, SETUP-21, SETUP-22):
  - id из имени;
  - пустой, занятый без учёта регистра, зарезервированные `embedded` и `default` (в том числе из имени «Default»), `a:b`;
  - аргументы с кавычками и незакрытая кавычка (незакрытая кавычка в аргументах stdio проверяется здесь, а не в итерации 2);
  - секретоподобный ключ `env` без значения в тексте, `toProfile` профиль не строит;
  - `ws://` к нелокальному хосту → предупреждение;
  - `EnvToken('DEVBOX_TOKEN')` → `tokenRef: env:DEVBOX_TOKEN`, `EnvToken('1BAD')` → проблема;
  - `profileKindsFor` без stdio-фабрики → только WebSocket.
- [ ] 3.2 `[client]` `codelab_client_core/test/connection/profile_probe_test.dart` на `FakeAcpTransport` (acp-client-kit «Проверка профиля без сессии»; SETUP-20):
  - успешный `initialize` → `Reachable` с `agentInfo`, агент получил только `initialize`;
  - молчание → `TimedOut`, транспорт закрыт;
  - отмена → транспорт закрыт, исхода нет;
  - несовместимая версия → `NotAcp`;
  - токен из `env:` попадает в конфигурацию транспорта.
- [ ] 3.3 `[client]` `codelab_client_io/test/probe_failure_test.dart` — настоящие процессы и WebSocket-сервер на loopback:
  - `/nonexistent/agent` → `CommandNotFound`;
  - закрытый порт → `Unreachable`;
  - сервер отвечает 401 на рукопожатие → `Unauthorized`.
  
  Если `WebSocketAcpTransport` теряет статус рукопожатия, тест фиксирует `Unreachable`, а сюда добавляется задача 3.3a `[protocol]` — типизированный статус в `codelab_acp_transports`. Классифицировать по тексту запрещено (D12).
- [ ] 3.4 `[desktop]` `apps/codelab_desktop/test/features/settings/application/add_profile_cubit_test.dart` (app-settings «Диалог «Add connection profile»», «События журнала настроек без секретов»; D12, D14, D17):
  - состояния `Editing → Probing → Editing`, `ConfirmingPlaintext`, `Saving → Saved | SaveFailed`;
  - номер проверки, поздний исход отброшен (`connection_profile.probe_discarded`), закрытие диалога отменяет проверку;
  - «Save» / «Save without test», метка «Not tested»;
  - «Use by default» пишет `codelab.connection.default_profile`, текущее подключение не меняется;
  - события и тексты без маркера `sk-test-leak-0123456789` (значение переменной токена, URL, текст исключения), `u:p`, `/acp`, `t=`.
- [ ] 3.5 `[desktop]` `apps/codelab_desktop/test/features/settings/presentation/add_profile_dialog_test.dart`, ключи:
  - тип и имя — `add-profile-type-<stdio|websocket>`, `add-profile-name`, `add-profile-id`;
  - stdio — `add-profile-command`, `add-profile-args`, `add-profile-run-in-project`, `add-profile-env`;
  - WebSocket — `add-profile-url`, `add-profile-token-<none|env>`, `add-profile-token-env-name`;
  - проверка — `add-profile-test`, `add-profile-probe-result`;
  - сохранение — `add-profile-save`, `add-profile-save-anyway`, `add-profile-use-by-default`;
  - итог — `add-profile-saved`, `add-profile-done`, `add-profile-add-another`.
  
  Случаи:
  - без stdio-резолвера нет переключателя типа (SETUP-22);
  - у WebSocket ровно два варианта токена, поля для значения нет, есть подсказки D13;
  - незаданная переменная → `<NAME> is not set in CodeLab's environment.`;
  - Esc без записи.
- [ ] 3.6 `[desktop]` `connection_page_test.dart`, новые случаи (app-settings «Rename» и «Remove» профиля»):
  - «Rename» меняет только `label`;
  - «Remove» удаляет только запись в файле — *уже сделано в итерации 2 вместе с подтверждением*;
  - удаление профиля по умолчанию сбрасывает ключ — *уже сделано в итерации 2*.

Реализация:
- [ ] 3.7 `[client]` `codelab_client_core`: `ProfileDraft` (`validate`, `toProfile`), `suggestProfileId`, `profileKindsFor`, `ProfileProbe` (временный `AcpClientApplication`, номер и отмена); `codelab_client_io`: `classifyProbeFailure`; `melos run web-compile`.
- [ ] 3.8 `[desktop]` Диалог и подтверждения:
  - `AddProfileCubit` и `add_profile_dialog.dart`, экран «Profile saved»;
  - подтверждения «Save anyway» и «Remove profile <label>?» (подтверждение «Remove» уже сделано в итерации 2);
  - встроенный «Rename».
  
  Виджеты не видят файлов и окружения: подсказку «not set» даёт Cubit по порту окружения из composition root.
- [ ] 3.9 `[desktop]` Интеграционные сценарии — компилируются в `feature/*`, запускаются в `release/*`:
  - `integration_test/settings_navigation_flow_test.dart`: Cmd/Ctrl+, → «Connection» при первом запуске, последняя страница после, Esc назад к сессии;
  - `integration_test/connection_profiles_flow_test.dart`:
    - WebSocket на scripted-агента с `env:DEVBOX_TOKEN` → `Reachable` → «Save»;
    - `tokenRef: env:DEVBOX_TOKEN` без значения в `profiles.json`, `codelab profiles list` видит профиль;
    - «Remove» у активного недоступна;
    - stdio с несуществующей командой → `Command not found` и «Not tested».

## 4. Документы и Definition of Done (итерация 4)

- [ ] 4.1 `[desktop]` Сверка документов с кодом:
  - 12-4 §12.4.9 и §12.4.13 — имена тестов и ключей;
  - 12-3 A13;
  - `delivery-roadmap.md` §10.1 — строка 20 «U-06, D-04, R-12» закрыта этим change в части без хранилища секретов;
  - `apps/codelab_desktop/AGENTS.md`, `codelab_client_core/AGENTS.md`, `codelab_client_io/AGENTS.md`, `apps/codelab_cli/AGENTS.md`.
- [ ] 4.2 `[desktop]` `agent-parity-goals.md`:
  - статусы U-06 (app) и D-04 (страница) — по факту реализации и тестов;
  - R-12 в app — «частично»: токен только из переменной окружения;
  - U-26 и D-10 остаются «— / нет» со ссылкой на D9 и D10.
- [ ] 4.3 `[desktop]` DoD:
  - задачи 1–3 выполнены, тесты зелёные, `guard` и `web-compile` прошли;
  - `ConnectionSetupDialog`, `TransportSetupPanel`, `InMemorySecretSource` в app и `EnvSecretSource` в CLI удалены, ссылок на них нет;
  - тестовый маркер не найден в логах тестов;
  - ревью `architecture-reviewer` и `acp-safety-reviewer`;
  - пункт ревью: из холста (`dc-runtime.js`, разметка артбордов) ничего не скопировано (AGENTS.md §5).
- [ ] 4.4 `[desktop]` Ручная проверка на macOS-сборке разработчика (не CI, не условие merge):
  - app, запущенное из терминала с `DEVBOX_TOKEN`, подключается к WebSocket-профилю;
  - из Finder строка показывает «not set»;
  - тот же профиль работает в `codelab -a <id>`.
