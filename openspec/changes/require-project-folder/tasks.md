Три итерации:
- **A** — нет неявной папки. `[desktop]` и одно условие kit `[client]` (A1.10, A2.9, HIGH-1); закрывает дефект, выходит отдельно.
- **C** — конфигурация Dart-агента на сессию: провайдеры, модель, запреты, привязка ключа к адресу. `[agent]` и `[protocol]` для ACP-сервера; выходит отдельно и не зависит от A и B.
- **B** — агент стартует сам. `[client]`, затем `[desktop]`; выходит после C: иначе сессии других папок в одном агенте остались бы без запретов своего проекта.

Красные тесты коммитятся отдельно до кода — только по явной просьбе пользователя (TDD, вложенные `AGENTS.md`). Q14–Q20 решены, все (a) (design.md, «Открытые вопросы»).

## Итерация A — нет неявной папки

### A0. Обвязка

- [x] A0.1 `[desktop]` `apps/codelab_desktop/test/support/test_app_scope.dart`: `CodeLabTestBinding` получает необязательный стартовый проект — подложенный снимок `WorkspaceSnapshotStore`, восстанавливается обычным `restoreProject`. Харнесс `test/features/workbench/application/shell_cubit_characterization/harness.dart` стартует с временной папкой-проектом. До правок кода всё зелёное (D20). Правки характеризационных тестов (D20, `codelab_client_core/AGENTS.md` §5):
  - `harness.dart`:
    - новый `projectReady()` — ждёт `SettingsCubit.projectRestored`;
    - `connect()` вызывает его перед `cubit.connect()`.

    Причина: стартовый проект приходит из подложенного снимка асинхронно, а без проекта подключение отклоняется. Утверждения не меняются.
  - `sessions_test.dart`, тест `createSession() before connecting sends nothing`: перед `createSession()` добавлено `await h.projectReady()`. Причина: без проекта `createSession` открывает выбор папки (D5), а тест проверяет прежний смысл — без соединения агенту ничего не уходит. Ожидания не меняются.

### A1. Красные тесты

- [x] A1.1 `[desktop]` `test/features/workbench/application/missing_project_folder_test.dart` (или новый `project_required_test.dart`), `SettingsCubit`: без проекта и снимка `projectDirectory == null`; `selectProject('/work/app')` — `/work/app`; `selectProject('  ')` — `null` (agent-workbench-ui «No project selected — no implicit directory»; D1). Красный.
- [x] A1.2 `[desktop]` Там же, без проекта: `ConnectionCubit.connect` и `reconnect` для встроенного, stdio (переключатель вкл. и выкл.) и WebSocket-профилей не вызывают фабрики транспорта, открыватель и `ClientWorkspace.connect`; `WorkspaceState.projectDirectory` остаётся `null`; диагностика `Open a project before connecting: choose a folder with Open folder….` (D2). Тест итерации A: в B кнопки Connect нет, и он переписывается в B2.6. Красный.
- [x] A1.3 `[desktop]` Там же: выбран `/work/a`, проверка `DirectoryExists` висит на `Completer`, за это время выбран `/work/b`; `ClientWorkspace.connect` получил `/work/a` (agent-workbench-ui «Проект сменили во время проверки папки»; D3). Красный.
- [x] A1.4 `[desktop]` `createSession` без проекта (рядом с `session_list_test.dart`): вызван `ProjectFolderPicker.pickFolder`, `newSession` не вызван, агенту ничего не отправлено; после выбора проект — `/work/app`, сессий не прибавилось; проверка проекта идёт раньше проверки соединения (agent-workbench-ui «New session без проекта открывает выбор папки»; D5). Красный.
- [x] A1.5 `[desktop]` `test/features/workbench/application/workspace_restore_test.dart`: снимок `{projectDirectory: "/", activeSessionId: s1, openSessions: [{s1, "/"}]}` — проект не выбран, предупреждение `project`; после `selectProject('/work/app')` и подключения `session/load` для `s1` нет, следующий снимок без `s1`. Юнит-тест функции «корень ФС»: `/` и `C:\` (через `p.Context(style: windows)`) — корень, `/work` — нет (agent-workbench-ui «Snapshot project at the filesystem root is not restored»; D10). Красный.
- [x] A1.6 `[desktop]` `add_profile_cubit_test.dart`, `connection_settings_cubit_test.dart`: без проекта «Test connection» stdio с `runInProjectDirectory: true` отдаёт в `ProfileProbe` профиль с `false`; с проектом — исходный профиль и папку; WebSocket не меняется (agent-workbench-ui «Test connection without a selected project»; D7). Красный.
- [x] A1.7 `[desktop]` `provider_settings_cubit_test.dart`, `mcp_settings_cubit_test.dart`: без проекта и агента — `EditableSettings` без папки, `projectLocal` среди целей нет (app-settings «Настройки без выбранного проекта»; D8). **Регрессионный** (решение ревью): `_accessOf` уже переводил пустую папку в `cwd: null`, поэтому тест зелёный и до кода. Он закрепляет поведение после смены типа источника на `String?`.
- [x] A1.8 `[desktop]` `test/app/embedded_transport_resolver_test.dart`: `open` с `''` и `'   '` — `ClientWorkspaceException`, открыватель не вызван; следующий `open` с папкой работает (agent-workbench-ui «Встроенный резолвер без папки»; D9). Красный.
- [x] A1.9 `[desktop]` `test/widget_test.dart`: ожидание `containsPair('cwd', workingDirectoryProvider.currentPath)` → `cwd` выбранного проекта; добавить проверку, что без проекта `createSession` не шлёт `session/new` (D20). Красный после замены.

- [x] A1.10 `[client]` `packages/dart/codelab_client_core/test/restore/` (HIGH-1). Снимок `{projectDirectory: /work/app, activeSessionId: s1, openSessions: [{s1, "/"}]}`, первое подключение к агенту:
  - с `loadSession` — `session/load` и `session/new` не отправлены, `s1` в списке `notLoaded`, активной сессии нет;
  - без `loadSession` — новая сессия с уведомлением не создаётся;
  - снимок с `s1` в `/work/app` грузится как раньше.

  (acp-client-kit «Восстановление после перезапуска»: «Активная сессия снимка в другой папке», «Активная сессия в другой папке у агента без loadSession»; D10.) Красный.
- [x] A1.11 `[desktop]` `test/features/workbench/application/workspace_restore_test.dart`: тот же снимок через `CodeLabTestBinding` — `/work/app` выбран, после подключения в `transport.sentMessages` нет `session/load` с `cwd` `/`, `s1` — строка `notLoaded` (agent-workbench-ui «Active session with root cwd under a real project», часть итерации A; D10). Красный до A2.9.
- [x] A1.12 `[desktop]` `SessionsCubit` (рядом с `session_list_test.dart`), D24:
  - выбор `notLoaded`-сессии с `cwd` `/` — состояние «ждёт подтверждения» с нормализованным `cwd`, `session/load` не отправлен;
  - `Open` — `session/load` с `cwd` `/` и фокус;
  - `Cancel` — фокус и статус прежние, ничего не отправлено;
  - выбор другой сессии во время диалога закрывает его как `Cancel`, и та открывается без подтверждения;
  - повторный клик по той же сессии игнорируется;
  - `cwd` `/tmp/..` и `//` — диалог; `/work/app` — без диалога;
  - событие `session.root_open` с `decision`, без пути.

  Виджет-тест диалога (текст `This session runs in the disk root (/). The agent gets access to the whole disk. Open anyway?`, кнопки `Open` и `Cancel`) — в `workbench_shell_test.dart`. (agent-workbench-ui «Подтверждение открытия сессии в корне диска», все сценарии.) Красный.
- [x] A1.13 `[desktop]` Юнит-тест `isFilesystemRoot`:
  - корень: `/`, `//`, `/.`, `/tmp/..`, `C:\` и `C:\.` (через `p.Context(style: windows)`);
  - не корень: `/work`, `C:\work`, пустая строка.

  Нормализация — через `p.normalize` (D10). Красный.
- [x] A1.14 `[desktop]` `missing_project_folder_test.dart` (или `project_required_test.dart`), D3:
  - восстановление проекта висит на `Completer`, пользователь нажимает «Connect»: статус `connecting` ставится сразу, после завершения восстановления подключение идёт с восстановленной папкой;
  - восстановление висит дольше таймаута (`fakeAsync`): отказ без обращения к workspace, диагностика `Open a project before connecting…`, событие `connection.connect_rejected {reason: no_project, profile_id}` без пути;
  - повторное нажатие во время ожидания второго подключения не начинает;
  - `createSession` во время восстановления ждёт ту же функцию и создаёт сессию в восстановленном проекте;
  - после таймаута без проекта `createSession` открывает выбор папки.

  (agent-workbench-ui «Действие во время восстановления проекта», «Восстановление не завершилось за таймаут».) Красный.

### A2. Реализация

- [x] A2.1 `[desktop]` `settings_cubit.dart`: `projectDirectory` → `String?`. `workingDirectoryProvider` удалить по цепочке `CodeLabShellParts.build`, оба конструктора `CodeLabShellCubit`, `app_scope.dart`. Удалить `lib/core/platform/working_directory_provider.dart`. Doc-комментарии на русском со ссылкой на D1 и `platform-integration.md` §54. A1.1 зелёный.
- [x] A2.2 `[desktop]` `connection_cubit.dart`: снимок папки в начале `connect`/`reconnect`; без проекта — `_rejectBeforeConnect` (диагностика `warning`, источник `project`); снимок уходит в проверку диска и в `ClientWorkspace` (D2, D3). `connectOnStart` без проекта пропускает подключение с событием `connection.connect_on_start_skipped` (временно, до B). A1.2, A1.3 зелёные.
- [x] A2.3 `[desktop]` `sessions_cubit.dart`, `createSession`: проект проверяется раньше соединения; без проекта — `browseForProject()` и диагностика `info` (D5). A1.4 зелёный.
- [x] A2.4 `[desktop]` `settings_cubit.dart`, `_restoreProject`: проект-корень не выбирается — чистая функция на `package:path`, предупреждение (D10). A1.5 зелёный.
- [x] A2.5 `[desktop]` `add_profile_cubit.dart`, `connection_settings_cubit.dart`, `provider_settings_cubit.dart`, `mcp_settings_cubit.dart`: тип `String? Function()`; правила D7 и D8 (до B источник — выбранный проект); замыкания в `app_scope.dart`. A1.6, A1.7 зелёные.
- [x] A2.6 `[desktop]` `app/embedded_transport_resolver.dart`: отказ с пустой папкой до очереди и поколения (D9). A1.8 зелёный.
- [x] A2.7 `[desktop]` `test/widget_test.dart`, `connection_cubit_test.dart` (`_FixedDirectory`), `integration_test/*`: проект — через обвязку A0.1. A1.9 зелёный; интеграционные тесты компилируются.
- [x] A2.8 `[desktop]` `rg 'currentPath|WorkingDirectoryProvider' apps/codelab_desktop/lib` — пусто; каждый потребитель `projectDirectory` в `lib/` обрабатывает `null` явно.

- [x] A2.9 `[client]` `packages/dart/codelab_client_core/lib/src/restore/workspace_restorer.dart`, `restoreAfterConnect`: активная сессия снимка загружается, только если её `cwd` равен проекту снимка; иначе — ни `session/load`, ни `newSessionWithNotice`, ни активации, сессия остаётся в `_pending` строкой `notLoaded`. Doc-комментарий на русском: почему (HIGH-1, Q1 (b), D10). A1.10, A1.11 зелёные. Затем: `fvm dart analyze` и `fvm dart test` в `codelab_client_core`, `melos run web-compile`, `melos run conformance:client`.
- [x] A2.10 `[desktop]` `isFilesystemRoot` — чистая функция с `p.normalize` (например, `lib/features/workbench/application/project_paths.dart`). `_restoreProject` переходит на неё (D10). A1.13 зелёный.
- [x] A2.11 `[desktop]` `sessions_cubit.dart`, `_loadAndSelect` / `selectSession`: подтверждение D24 — состояние в `SessionsState`, методы `confirmRootSession` и `cancelRootSession`, вытеснение новым фокусом, событие. Виджет диалога в `workbench_shell.dart` по состоянию, без решения об опасности в виджете. A1.12 зелёный.
- [x] A2.12 `[desktop]` `settings_cubit.dart`: `awaitProject()` с таймаутом `projectRestoreTimeout` (2 с, параметр конструктора для тестов). В `connection_cubit.dart`:
  - `connect` и `reconnect` ставят `connecting` / `reconnecting`, затем ждут `awaitProject()` и проверяют номер намерения;
  - без проекта — `_rejectBeforeConnect` с событием `connection.connect_rejected {reason: no_project, profile_id}`.

  `sessions_cubit.dart`, `createSession`: та же `awaitProject()` (D3). A1.14 зелёный, A1.2 и A1.3 остаются зелёными.
- [x] A2.13 `[desktop]` Прогон A3.1 после A2.9–A2.12.

### A3. Проверки

- [x] A3.1 `[desktop]` `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm flutter analyze` и `fvm flutter test` в `apps/codelab_desktop`.

## Итерация C — конфигурация Dart-агента на сессию

Сверено с кодом `develop` после PR #286 (2026-11-12). Порядок и зависимости:

- C0.1 — первой (правило «сначала документ»).
- Ветка D23: C1.3, C1.4 → C2.2. Не зависит от порта, её можно делать параллельно с веткой D21.
- Ветка D21: C1.1, C1.2 → C2.1 → C2.3.
- C1.5 → C2.4 — после C2.1 (тип порта).
- C1.6 → C2.5 `[protocol]` — после C2.1 (`ProjectConfigException`) и C2.3 (`AgentSession.models`). C2.3 ломает компиляцию фейка `AgentSession` в `codelab_agent_acp/test/session_bridge_echo_test.dart`, поэтому первый пункт C2.5 идёт сразу за C2.3.
- C1.7, C1.8 → C2.6 — после C2.3, C2.4 и C2.2 (сценарии с провайдером из `config.local.yaml`).
- C2.8 (развязка `skip` R8-6/R8-10, D25) — после C2.2; до ответа Q21 переписываются только тесты, не зависящие от наследования адреса (см. задачу).
- По ревью итерации C: C2.9 (D26, мигратор) — после C2.8; C5.1–C5.4 `[agent]` и C5.5 `[protocol]` независимы друг от друга, C5.1 — до C2.9 и C5.6 (мигратор опирается на привязку ссылок); C5.6 — после C2.9.
- C2.7 и C3.1 — последними; C3.1 повторяется после C2.9 и C5.

### C0. Документы

- [x] C0.1 `[agent]` Документы ядра до кода (`codelab_agent_core/AGENTS.md`: «сначала дополняется документация»):
  - `docs/architecture/proposals/agent-core/10-core-assembly-and-profiles.md` — абзац «Снимка на каждый `cwd` сессии нет…»: порт `ProjectConfigLoader`, тройка сессии, `withoutProject` только без порта;
  - `17-5-agent-setup.md` — отступление 8.10 «Один корень на хост» и раздел «Снимок — на корень запуска хоста»: единица перезагрузки остаётся корнем, сессии других папок держат снимок открытия (D21, Q12, Q19);
  - `15-configuration.md` §15.2–§15.3 — группа провайдера и привязка ссылки к origin (D23).

  Ссылки на D21, D23 change `require-project-folder`.

### C1. Красные тесты

- [x] C1.1 `[agent]` `packages/dart/codelab_agent_core/test/runtime/config_outside_root_test.dart` — переписать на новую семантику. Прежние ожидания `withoutProject` и `config.session.outside_root` (корень, другой корень, подкаталог, сравнение по компонентам, `loadSession`, symlink) переходят в группу «без порта». Фейки:
  - `ProjectConfigLoader`: карта «папка → `ConfigLoadResult`», счётчик вызовов, записанные пути, управляемый `Completer`;
  - `modelsFor`: запись конфигураций, по которым строился каталог.

  Сценарии:
  - запрет доверенного `/B` действует, правила `/A` не применяются;
  - недоверенный `/B` — смягчение режима и провайдер отброшены (результат фейка построен через `CoreConfig.fromLayers` с проектными слоями);
  - провайдер `local` из `/B` — модель сессии `local/m`, `AgentSession.models` сессии `/B` содержит `local/m`, сессии `/A` — нет;
  - серверы `/A` не попадают в `/B`;
  - ключи процесса (`sessions.dir`, `logging.level`) из `/B` проигнорированы с `config.session.process_keys_ignored` без значений;
  - проблемы загрузки, `validateSnapshot` и исключение `modelsFor` — `ProjectConfigException`, сессии нет; `listSessions()` её не возвращает; лог `config.session.project_invalid` без текстов проблем;
  - `loadSession` вне корня с битым конфигом — `ProjectConfigException`, записей в журнале не прибавилось;
  - вторая сессия `/B` после смены результата загрузчика получает новые правила, первая — прежние (кэша нет);
  - `reloadConfig()` корня не меняет модель сессии `/B`;
  - остановка рантайма во время `loadForProject` — сессии нет, MCP не стартовал;
  - `/A/sub` — своя папка;
  - сессия в корне — загрузчик не вызван;
  - `cwd` через symlink: `/L → /A` — загрузчик не вызван; `/M → /B` — загрузчик получил `/B`;
  - `session/load` вне корня тоже загружает, модель журнала разрешается по каталогу сессии;
  - без порта — `withoutProject` и `config.session.outside_root`;
  - порт без `modelsFor` — `HostWiringException`; порт без `ConfigSource`, но с `modelsFor` — сборка проходит (сейчас `buildAgentCore` отбрасывает `modelsFor` без `services.config`).

  (agent-runtime «Конфигурация сессии вне корня запуска», все сценарии; D21.) Красный.
- [x] C1.2 `[agent]` Гонки и перезагрузка корня в том же файле, порядок через `Completer`:
  - два параллельных `session/new` в `/B` и `/C` — у каждой сессии своя конфигурация и модель, без перекрёстного смешения;
  - `session/new` в `/B` во время `reloadConfig()` корня — сессия `/B` строится по своей загрузке, применённый снимок корня заменяется атомарно (agent-runtime «Живая перезагрузка конфигурации», «Замена»);
  - `session/set_config_option model` сессии `/B` во время хода другой сессии — меняет только `/B`;
  - перезагрузка корня, добавившая модель: `ModelOptionsChanged` получает сессия `/A`, сессия `/B` — нет; серверы конфигурации сессии `/B` не заменяются (шаг 7а), бюджет на границе хода — из её конфигурации.

  (agent-runtime «Сессии других папок при перезагрузке корня»; Q19 (a).) Красный.
- [x] C1.3 `[agent]` `packages/dart/codelab_agent_core/test/config/config_provider_key_binding_test.dart` — правило D23 в `CoreConfig.fromLayers`:
  - группа адреса берётся целиком из проектного слоя, включая `api_key` и `auth_header`;
  - литеральный `api_key` глобального слоя не наследуется адресом проекта;
  - ссылка из `config.yaml` с чужим origin — проблема провайдера в `providerProblems` с текстом правила и предупреждение `config.provider.key_unbound` без значения;
  - ссылка из `config.local.yaml` доверенного проекта — разрешена;
  - ссылка, связанная глобально с тем же origin (в том числе порт по умолчанию и `base_url` по умолчанию для `kind`), — разрешена; другой порт или схема — нет;
  - `${secret:…}` и `${ENV}` в `headers` и `api_key` — по тому же правилу; непривязанный `${ENV}` не раскрыт (значения нет в `ProviderConfig.headers`) и `config.provider.key_missing` для непривязанного `api_key_env` нет;
  - несколько слоёв задают группу (Q17 (a)): `config.yaml` задаёт `base_url`, `config.local.yaml` — `api_key_secret` — группа целиком из `config.local.yaml`, `base_url` из `config.yaml` не применяется; проектный `base_url` и ключ в `--config` выше — группа из `--config`;
  - `${ENV}` в `base_url` проектного слоя (Q16 (a)): в `config.yaml` не раскрывается — `key_unbound` с `reference_kind: env`; в `config.local.yaml` доверенного проекта — раскрывается;
  - недоверенный проект — отброшен;
  - правило действует и для корня процесса;
  - `implicitDefaultModel` непривязанного провайдера не выбирает.

  (agent-secrets «Ключ проектного провайдера привязан к адресу», все сценарии; D23.) Красный.
- [x] C1.4 `[agent]` `packages/dart/codelab_agent_core/test/llm/routed_stream_function_key_binding_test.dart` — утечка. Конфиг строится `CoreConfig.fromLayers`, функция модели — `createConfiguredStreamFunction`. Фейки:
  - `SecretResolver` с `codelab/anthropic = sk-test-leak-0123456789`, считает чтения;
  - HTTP-клиент `MockClient`, считает запросы.

  Для провайдера с непривязанной ссылкой:
  - HTTP-запросов 0, чтений секрета 0;
  - текст ошибки хода (класс `auth`), все записи лога (`RecordingLogger` из `package:codelab_agent_core/testing.dart`; `configureCodeLabLogging` — клиентский, в ядре его нет), `configOptions` и диагностика не содержат `sk-test-leak-0123456789`;
  - origin в тексте — без пути и userinfo.

  Красный.
- [x] C1.5 `[agent]` `packages/dart/codelab_agent_io/test/config/file_config_source_test.dart`:
  - `loadForProject('/B')` читает слои папки, доверие — по закреплённому `initial`;
  - относительный `--config` разрешается от корня процесса, а не от `/B`;
  - база сравнения наблюдателя не сдвигается;
  - несуществующая папка — результат без проектных слоёв;
  - ссылки `.codelab` наружу — проблема по правилу «Ссылки проектных слоёв при чтении» (spec agent-configuration);
  - `config.local.yaml` папки доходит до ядра слоем `projectLocal`: провайдер со ссылкой в нём получает ключ, тот же провайдер в `config.yaml` — `key_unbound` (D23);
  - предупреждения загрузки (`config.project.untrusted_key`, `config.provider.key_unbound`) пишутся в лог `logConfigWarnings`.

  (D21, D23.) Красный.
- [x] C1.6 `[protocol]` `packages/dart/codelab_agent_acp/test/project_config_test.dart` — отдельный файл, а не правки `session_new_test.dart`, `session_load_test.dart`, `config_options_test.dart`, `config_reload_notifications_test.dart`: сценариям нужен общий стенд (фейк рантайма с `ProjectConfigException` и разными `AgentSession.models` у сессий одного соединения), которого у тех файлов нет:
  - `ProjectConfigException` на `session/new` / `session/load` → `-32603` с `data.codelab.reason: "projectConfigInvalid"`, без значений секретов; соединение и другие сессии живы; новой сессии нет в `session/list`;
  - `configOptions` `model` двух сессий разных папок различаются (фейк рантайма с разными `AgentSession.models`); `set_config_option` с моделью чужого каталога → `-32602`;
  - перезагрузка корня: `config_option_update` только сессии корня.

  (agent-acp-server «Ошибка проектного конфига сессии», «Модели сессии по её каталогу»; Q20 (a).) Красный.
- [x] C1.7 `[agent]` `packages/dart/codelab_embedded/test/io/local_opener_test.dart` (IO-тесты открывателя на временных папках, HTTP — `MockClient`):
  - агент открыт для `/A`; доверенный `/B` задаёт `permissions.tools.exec: deny` и провайдера в `config.local.yaml` — в сессии `/B` `exec` запрещён, модель — провайдера `/B`;
  - `scriptedEmbeddedAgentOpener` порт не передаёт.

  (embedded-agent «Проектный конфиг сессий встроенного агента».) Красный.
- [x] C1.8 `[agent]` `apps/codelab_agent/test/agent_host_project_config_test.dart` (в процессе: `AgentHost` со швами `httpClient` и `modelsFor`; по процессу без `--llm-script` нужен настоящий провайдер):
  - `serve --stdio` в `/A`, доверенный `/B` с `budget.max_steps: 3` — бюджет сессии `/B` равен 3, флаги `--model` / `--provider` входят в её слои;
  - `--llm-script` порт не получает;
  - `serve --ws` порт не получает: сессия `/B` — `withoutProject` и `config.session.outside_root` (Q18 (a)).

  (agent-binary «Проектный конфиг сессий в serve», оба сценария.) Красный.

### C2. Реализация

- [x] C2.1 `[agent]` `codelab_agent_core`:
  - порт `ProjectConfigLoader` и поле `AgentCoreServices.projectConfig`;
  - `ProjectConfigException {cwd, issues}`;
  - экспорт из бареля и `test/public_api_test.dart`;
  - `buildAgentCore`: порт без `modelsFor` — `HostWiringException`; `modelsFor` передаётся рантайму при `services.config` или `services.projectConfig`.

  Doc-комментарии на русском: почему `CoreConfig` на сессию, а `HostSettings` на процесс; почему fail closed (§2, приоритет 1); ссылка на D21.
- [x] C2.2 `[agent]` Правило D23 в `codelab_agent_core/lib/src/config/resolve.dart`:
  - группа целиком — шаг до слияния, рядом с правилом `providers.cli` (`merge.dart`) или с `_applyTrust`;
  - привязка к origin — в `_Builder._provider` до `_interpolate` заголовков и `api_key` и до проверки переменной `api_key_env`; происхождение поля — `_Builder._origin`;
  - ссылки глобальных слоёв для условия (b) — из исходных деревьев слоёв;
  - непривязанный провайдер — запись в `providerProblems` с текстом правила, без ссылки и шаблонов заголовков; предупреждение `config.provider.key_unbound`.

  Функцию модели менять не нужно: `createRoutedStreamFunction` отвечает по `unavailable` без HTTP и без резолвера. Комментарий с угрозой и ссылкой на D23. C1.3, C1.4 зелёные; `test/config/` и `test/llm/` остаются зелёными.
- [x] C2.3 `[agent]` `AgentRuntime` (`codelab_agent_core/lib/src/runtime/agent_runtime.dart`):
  - `_sessionConfig` возвращает тройку «`CoreConfig`, каталог, функция модели»: шаги D21 по порядку, ожидание `loadForProject` прерывает `_shutdown`;
  - в `createSession` шаги D21 и канонизация `cwd` — до `_store.create`, id сессии генерируется раньше;
  - тройка сессии вместо `start`: `_selectModel`, `_resolve`, модель журнала и `_agentBaseOf` в `loadSession`, `_open(catalog:)`;
  - `_Session`: `catalogOf`, `streamOf`, `settingsOf`, `replaceMcp` — из тройки;
  - `AgentSession.models` (каталог сессии);
  - `_notifySessions` и шаг 7а (`_applyConfigMcp`) пропускают сессии другой папки;
  - события `config.session.project`, `config.session.process_keys_ignored`, `config.session.project_invalid`;
  - без порта — прежний путь.

  C1.1, C1.2 зелёные; `config_reload_test.dart`, `project_files_runtime_test.dart`, `session_model_selection_test.dart`, `load_session_test.dart`, `test/config/config_default_model_test.dart` остаются зелёными.
- [x] C2.4 `[agent]` `codelab_agent_io`: `FileConfigSource implements ProjectConfigLoader`:
  - тот же `ConfigLoader`, окружение, флаги, предконфигурация, `extraConfig` (абсолютный от корня процесса), известные переменные, закреплённое доверие;
  - без `rebase` наблюдателя;
  - предупреждения — `logConfigWarnings`.

  C1.5 зелёный.
- [x] C2.5 `[protocol]` `codelab_agent_acp`:
  - сразу после C2.3 — геттер `models` у фейка `AgentSession` в `test/session_bridge_echo_test.dart`;
  - `_sessionNew` / `_sessionLoad` ловят `ProjectConfigException` → `AcpRequestError(jsonRpcInternalErrorCode, …, data: {'codelab': {'reason': 'projectConfigInvalid'}})`, строка `message` — одна строка, все проблемы через `; ` (`<source>:<line>:<column>: <key>: <message>`, Q20 (a));
  - `SessionBridge(catalog:)` и проверка `set_config_option` `model` — по `AgentSession.models`, а не `_server._runtime.models` (`agent_server.dart`, `_wire`, `_setConfigOption`).

  C1.6 зелёный; `conformance_test.dart` зелёный.
- [x] C2.6 `[agent]` Подключение порта:
  - `codelab_embedded`: поле `EmbeddedHostServices.projectConfig` (`lib/src/embedded_agent_config.dart`), передача в `AgentCoreServices` (`lib/src/assemble.dart`), `modelsFor` при порте (`lib/src/create_embedded_agent.dart`), `lib/src/io/local_opener.dart` — `source` как `projectConfig`; `modelsFor` строит функцию модели для любой папки на общих HTTP-клиенте и резолвере секретов;
  - `apps/codelab_agent/lib/src/host/agent_host.dart` — `serveConfigSource` (`serve_config.dart`) как `projectConfig` только при `--stdio` и без `--llm-script`; `--ws` порт не передаёт (Q18 (a), как `ProjectFilesLoader`).

  Doc-комментарии открывателя и `AgentHost`: что берётся от папки запуска, а что от сессии. C1.7, C1.8 зелёные.
- [x] C2.7 `[agent]` Проверить, что `/config check` в сессии вне корня ведёт себя как раньше: команда проверяет конфигурацию корня (`AgentRuntime.checkConfig`). Если команда должна показывать проблемы папки сессии — записать вопрос, поведение не менять.
- [x] C2.8 `[agent]` Развязка пропущенных тестов R8-6/R8-10 (D25; спецификации agent-configuration «Секреты только ссылками» и agent-secrets «Подкоманда secret migrate», MODIFIED). Пропусков `skip` с причиной D23 после задачи не остаётся:
  - `packages/dart/codelab_agent_io/test/secrets/secret_migrator_test.dart`, «только user: отказ до любой записи с текстом про --all» — переписать на сценарий «Перенос одного слоя, когда другой слой задаёт свой ключ»: код `0`, пользовательский слой перенесён, проектный файл не изменён, итог загружается без проблем, ключ `lm` — литерал проектного слоя, `config.secret.in_file` остаётся, вывод без значений; `--dry-run` — тот же план, код `0`;
  - там же, «отказ R8-10 случается до единого чтения хранилища» — перенести на `CODELAB_CONFIG`: литерал `providers.lm.api_key` в файле `CODELAB_CONFIG` и в `user`, `secret migrate --all` — код `1` с текстом `(CODELAB_CONFIG keeps its own)`, `store.reads` пуст (сценарий «Источник ключа в CODELAB_CONFIG»);
  - `packages/dart/codelab_agent_io/test/config/config_writer_test.dart`, «без pending правка одного слоя даёт конфликт…» — сохранить смысл (`validate(pending:)` проверяет итог с соседним файлом), но на другой межслойной зависимости: правка `user` удаляет провайдера `p`, а `agent.default_model: p/m` задаёт `project`; без `pending` — проблема «not in the model catalog», с `pending` соседнего файла, который снимает `default_model`, — чисто;
  - фикстуры, в которые при реализации C2.2 дописаны `kind`/`base_url` проектного слоя (`secret_migrator_test.dart`: провайдер `lm` в `twoLayers`, группы «итог слияния» и «повтор после сбоя») — при ответе Q21 (a) вернуть к прежнему виду (проект задаёт только ключ провайдера пользователя): тесты снова проверяют исходный случай, а загрузка проходит за счёт наследования адреса из непроектного слоя; `kind`/`base_url` оставить только там, где тест намеренно задаёт другой адрес. При ответе (b) или (c) фикстуры остаются как есть, а сценарии agent-secrets «Проект меняет только ключ провайдера пользователя» и agent-configuration «Ключ проектного слоя не образует пары…» правятся архитектором;
  - `packages/dart/codelab_agent_core/test/config/config_secret_in_file_test.dart` — перенос теста «два источника» на слой `extra` верен (D25); добавить тест на сценарий agent-configuration «Ключ проектного слоя не образует пары с ключом пользователя» (литерал в `user`, `api_key_secret` в `config.local.yaml` доверенного проекта — проблемы нет, ключ — ссылка проекта);
  - `packages/dart/codelab_agent_core/test/config/config_provider_key_binding_test.dart` — сценарии правила «поля, которые верхний слой не задаёт» (D23): проект задаёт только `base_url` — `kind` из `user`; проект задаёт только `api_key_secret` — адрес из `user`; `config.local.yaml` задаёт только ключ, `config.yaml` — `base_url` — адрес не из `config.yaml` (из `user`, а без провайдера в `user` — проблема `base_url`);
  - тексты R8-6/R8-10 в `docs/architecture/proposals/agent-core/15-configuration.md` и `17-5-agent-setup.md` — оговорка D25 (вместе с C0.1).

  Файлы `codelab_agent_acp` задача не трогает. `fvm dart test` в `codelab_agent_io` и `codelab_agent_core` зелёные без новых `skip`.

- [x] C2.9 `[agent]` `secret migrate` переносит провайдера закоммиченного `config.yaml` в `config.local.yaml` (D26; agent-secrets «Подкоманда secret migrate», сценарии «Провайдер закоммиченного конфига переносится в config.local.yaml», «Ключ к провайдеру пользователя из закоммиченного конфига», «Сбой между записью config.local.yaml и config.yaml», «config.local.yaml уже задаёт провайдера иначе», а также правленые «Одно имя у двух находок», «Ключ одного провайдера в двух слоях с --all», «--force называет ссылающиеся ключи», «Повтор после сбоя записи второго файла», «Ручная пара источников ключа», «Имя занято тем же провайдером»).
  - Красный: `packages/dart/codelab_agent_io/test/secrets/secret_migrator_test.dart` — сценарии выше; во всех: вывод и отчёт без значений, после запуска `ConfigLoader().load` итога без проблем и без `config.provider.key_unbound`; `--dry-run` — тот же план без записи и хранилища; недоверенный проект — прежняя строка, ни один файл проекта не записан.
  - Реализация: `packages/dart/codelab_agent_io/lib/src/secrets/secret_migrator.dart` — правки провайдера `config.yaml` (сейчас `_Unit.edits`, `_UnitKind.providerKey`, ~768–777) идут в цель `ConfigTarget.projectLocal(cwd)`: все поля группы D23, которые задаёт `config.yaml`, с литералами, заменёнными ссылками; в `config.yaml` — `UnsetValue` этих полей. Файл `config.local.yaml` добавляется в список записываемых даже без `--local`; доверие писателя проверяется для него до хранилища; порядок записи `user`, `local`, `project`; итог — через `pending` всех файлов (R8-10). Совпадающая группа в `config.local.yaml` (повтор после сбоя) — только удаление из `config.yaml`; отличающаяся — строка `not migrated: providers.<id> in <path>: config.local.yaml already defines its address or key; move it by hand`, без записи и хранилища для провайдера. Строка вывода `Moved providers.<id> (address and key) from <config.yaml> to <config.local.yaml>` — новый тип пункта отчёта. Doc-комментарий с угрозой и ссылкой на D23, D26.
  - «Move secrets» desktop и `codelab secret migrate` вызывают тот же движок — отдельных правок нет; `apps/codelab_cli` и `codelab_embedded` — `fvm dart analyze` (меняется публичный тип отчёта, если пункт добавлен в барель).

### C5. Исправления по ревью итерации C

- [x] C5.1 `[agent]` **[MAJOR]** `packages/dart/codelab_agent_core/lib/src/config/resolve.dart` (~528): `ProviderKeyBinding.fromLayers` строить по `sourceLayers` — непроектным слоям до правила группы, а не по слоям после него. Иначе правило группы уже вытеснило группу пользователя с тем же id, связка «ссылка — origin» глобального слоя теряется, и ссылка проекта, которую пользователь связал с тем же адресом, получает ложный `key_unbound` (условие (b) D23). Красный в `test/config/config_provider_key_binding_test.dart`: пользователь задаёт провайдера `<id>` с `api_key_secret: codelab/<id>` и `base_url` origin `O`; `config.yaml` доверенного проекта задаёт для того же `<id>` ту же ссылку `codelab/<id>` — проблемы нет, ключ — `SecretKeyRef('codelab/<id>')`; вариант: проект задаёт и `base_url` с тем же origin `O` (другой путь) — тоже без проблемы; с другим origin — `key_unbound`.
- [x] C5.2 `[agent]` **[MAJOR]** Тест сценария agent-runtime «Ключ процесса задаёт только корень»: `packages/dart/codelab_agent_core/test/runtime/config_outside_root_test.dart` — снимок корня с `logging.level` из `config.local.yaml` корня (`rootLocal`), загрузка `/B` этот ключ не задаёт — лога `config.session.process_keys_ignored` нет. Если тест красный — правка сравнения в `AgentRuntime._sessionConfig` по D21.
- [x] C5.3 `[agent]` Мигратор по D26 — задача C2.9 (тесты и код).
- [x] C5.4 `[agent]` MINOR и NIT:
  - `packages/dart/codelab_agent_core/lib/src/runtime/agent_runtime.dart` (~2354–2366): съехавшие doc-комментарии полей `_Session`; doc `_settingsOf` и `_catalogOf` — источник у сессии папки (её тройка, D21), а не применённый снимок;
  - doc `ProjectConfigException.issues`: проблемы без значений секретов и подставленных переменных (CFG-2);
  - `packages/dart/codelab_embedded/lib/src/io/local_opener.dart:46` — перенос doc-строки;
  - `packages/dart/codelab_embedded/test/io/local_opener_test.dart`, тест «broken config of B» — проверять причину (`ProjectConfigException` с проблемой и путём файла `/B/.codelab/config.yaml`), а не любую ошибку;
  - `packages/dart/codelab_agent_io/test/secrets/secret_migrator_test.dart`, тест «конфликт источников без правок» — проверять текст R8-6 (`providerKeySourcesConflictMessage`); вернуть удалённую пустую строку (~1113);
  - `agent_runtime.dart:641`: загрузка папки, завершившаяся после остановки рантайма, пишет `debug`-лог с классом ошибки (`error_class`, без текста), а не теряет её (§12).
- [x] C5.5 `[protocol]` `packages/dart/codelab_agent_acp/lib/src/agent_server.dart` (375–379): лог `acp.session.project_config_invalid` получает `cwd`, а для `session/load` — ещё `session_id` (§16); тест в `test/project_config_test.dart`.
- [x] C5.6 `[agent]` **[приоритет 1]** Мигратор не переносит провайдера с непривязанной ссылкой в группе (D26, «Чужие ссылки группы не переносятся»; agent-secrets «Подкоманда secret migrate», четыре сценария «Непривязанная ссылка в группе не переносится»).
  - Красные тесты в `packages/dart/codelab_agent_io/test/secrets/secret_migrator_test.dart`, по одному на вид ссылки: `api_key_secret`, `${secret:…}` в заголовке, `api_key_env`, `${ENV}` в `base_url`; приманка — литерал в заголовке; хранилище и окружение содержат маркер `sk-test-leak-0123456789`. После `migrate --project` и `--dry-run`:
    - в `config.local.yaml` нет непривязанной ссылки, оба файла побайтно не изменены;
    - строка `not migrated: providers.<id> in <path>: <reference> is not bound to this address by the user config; move it by hand`, без значений;
    - `ConfigLoader().load` итога по-прежнему даёт `config.provider.key_unbound` для провайдера;
    - ход с его моделью через `createConfiguredStreamFunction` на `MockClient` — HTTP-запросов 0;
    - маркера нет в выводе, отчёте, файлах и логе.
  - Контрольный тест: ссылка, привязанная глобальными слоями к тому же origin, — перенос идёт.
  - Код: `packages/dart/codelab_agent_io/lib/src/secrets/secret_migrator.dart`, `_planMoves` (~1016–1037) — проверка ссылок, которые мигратор не создаёт сам, до планирования, через привязку ядра по непроектным слоям (`ProviderKeyBinding`, C5.1); отмена переноса провайдера целиком.
  - NIT из ревью:
    - `packages/dart/codelab_agent_core/lib/src/config/resolve.dart:524-525` — doc-комментарий: привязка строится по `sourceLayers` (непроектные слои до правила группы);
    - `secret_migrator.dart:978` — опечатка `apiKey` в регулярке `_groupProviderOf` и doc метода (возвращает id провайдера находки в поле группы или `null`);
    - `secret_migrator_test.dart` ~1446 — вернуть удалённую пустую строку в тесте «битый YAML».

### C3. Проверки

- [x] C3.1 `[agent]` `fvm dart format`, `fvm dart analyze`, `fvm dart test` в `codelab_agent_core`, `codelab_agent_io`, `codelab_embedded`, `apps/codelab_agent`; `[protocol]` — то же в `codelab_agent_acp`. Публичный API ядра и `codelab_embedded` меняется, поэтому ещё `fvm dart analyze` в `codelab_setup` и `apps/codelab_cli`. Затем:
  - `melos run guard` — allowlist ядра не меняется, прогон-подтверждение;
  - `melos run web-compile` (`codelab_agent_core`, `codelab_embedded`);
  - `melos run conformance:agent` и `melos run protocol-conformance`;
  - `melos run prompts:check`, если тронуты тексты для модели;
  - `melos run test:e2e:cli:dart-agent`.

## Итерация B — агент стартует сам

### B0. Красные тесты kit

- [ ] B0.1 `[client]` `packages/dart/codelab_client_core/test/workspace/ensure_agent_test.dart` (новый; `FakeAcpTransport`, фейковый резолвер с `Completer` и записью папки):
  - `Connected` — no-op для любой папки;
  - первый старт задаёт `agentDirectory`, не трогает `projectDirectory`, запрашивает `session/list`;
  - повтор во время попытки — один `open` с папкой первого вызова;
  - без профиля — `ClientWorkspaceException`;
  - после `ConnectionFailed` — новая попытка;
  - путь CLI (`connect`) задаёт обе папки, `reconnect` загружает все сессии.

  Порядок завершений задаётся явно (`concurrency.md` §69–§70); acp-client-kit «Агент по требованию хоста»; D15. Красный.
- [ ] B0.2 `[client]` Там же или в тестах списка: `selectProject` при `Connected` — `session/list` нового проекта, поздний ответ прежнего не меняет список; без `sessionCapabilities.list` запроса нет (acp-client-kit «Смена проекта перезапрашивает список»). Красный.
- [ ] B0.3 `[client]` Тесты переподключения: сессии разных папок загружаются каждая со своим `cwd`; `loadSession` для `detached` — загрузка и слив очереди после неё (acp-client-kit «Сессии после переподключения», новые сценарии; D16). Красный — вторая часть.
- [ ] B0.4 `[client]` Перенесено в A1.10 (HIGH-1). В B — только регрессия: тесты A1.10 остаются зелёными после `ensureAgent`.

### B1. Реализация kit

- [ ] B1.1 `[client]` `workspace_state.dart`: `agentDirectory`; `client_workspace.dart`: `ensureAgent` (D15), `connect`/`reconnect` задают `agentDirectory`, `selectProject` с номером запроса списка, `loadSession` для `detached`. Doc-комментарии на русском (§15); экспорт из бареля. B0.1–B0.3 зелёные.
- [ ] B1.2 `[client]` Перенесено в A2.9. В B `workspace_restorer.dart` правило активной сессии не меняет.
- [ ] B1.3 `[client]` Проверки kit: `fvm dart format`, `fvm dart analyze`, `fvm dart test` в `codelab_client_core`; `melos run web-compile`; `melos run conformance:client`; `melos run test:e2e:cli:dart-agent`; `fvm dart analyze` в `apps/codelab_cli` и `apps/codelab_desktop` (публичный API kit расширен).

### B2. Красные тесты desktop

- [ ] B2.1 `[desktop]` `test/features/workbench/application/agent_starts_itself_test.dart` (новый; `CodeLabTestBinding` с фейковыми открывателем и stdio-фабрикой):
  - выбор проекта стартует агента без сессии и запрашивает список;
  - восстановленный проект стартует агента при запуске;
  - «New session» и фокус на `notLoaded` / `detached` стартуют агента, если его нет; для `detached` с `cwd` в корне диска — подтверждение D24 (та же функция, что в A2.11);
  - сессия другой папки при идущем ходе — без перезапуска, ход завершается своим ответом;
  - WebSocket — одно соединение на две папки;
  - после сбоя любой триггер (выбор проекта, «New session», фокус, «Retry») снова стартует агента; без действия пользователя повторов нет (фейковые часы: время идёт — новых `open` нет); одинаковый сбой три раза подряд — одна запись в диагностике, на экране `Failed again (2)`, в журнале `connection.start_failed` с `repeat`; другой текст ошибки — новая запись;
  - исчезнувшая папка сессии — `session/load` не отправлен.

  (agent-workbench-ui «Агент стартует сам», «Selecting a not-loaded session restores its transcript», «Switching project keeps the agent and other sessions running», «Исчезнувшая папка сессии»; D13.) Красный.
- [ ] B2.2 `[desktop]` Там же, гонки D17 (принудительный порядок через `Completer`):
  - выбор проекта и два «New session» во время старта — один `open`, фокус у последнего намерения, сессия первого в списке;
  - `s1` → `s2` во время `session/load` `s1` — фокус у `s2`, ошибок `error` нет;
  - быстрая смена проекта — список последнего.

  Красный.
- [ ] B2.3 `[desktop]` `test/features/settings/application/connection_settings_cubit_test.dart` и тест `ConnectionCubit`:
  - «Use» — метка «Selected», агент не тронут;
  - подпись `Restart <title> to use it.`;
  - «Restart agent» без работы — без диалога, с новым профилем;
  - при ходе, ждущем одобрении или отмене — состояние «ждёт подтверждения» с названиями; «Cancel» ничего не меняет; «Restart agent» перезапускает без `session/cancel`, очередь сохранена;
  - повторный перезапуск при открытом диалоге игнорируется;
  - строки «Connect on start» нет, ключ `true` не подключает;
  - корень перезапуска — папка сессии в фокусе, иначе проект.

  A1.2 переписывается сюда: Connect больше нет. (app-settings «Список профилей…», «Блок «Behavior»…», все сценарии; D18, D19, D22.) Красный.
- [ ] B2.4 `[desktop]` `workspace_restore_test.dart`: активная сессия в папке проекта загружается при запуске без Connect; активная `s2` с `cwd` `/` под `/work/app` — агент стартует в `/work/app` без Connect, стартовый экран. Правило «`s2` не грузится» уже проверяет A1.11; здесь — только клик по `s2`: подтверждение D24, после `Open` загрузка без перезапуска (agent-workbench-ui «Restart restores the previous session», «Active session with root cwd under a real project»; D16, D19). Красный.
- [ ] B2.5 `[desktop]` Виджет-тесты `test/features/workbench/presentation/workbench_shell_test.dart`:
  - стартовый экран без проекта (`start-open-project`) и с проектом (`start-new-session`, `Starting <title>…`);
  - экран сбоя с «Retry»;
  - диалог подтверждения D22 по состоянию Cubit-а;
  - в app bar нет «Connect»;
  - Cmd/Ctrl+N доступно при выбранном проекте без соединения.

  (agent-workbench-ui «Empty session after connecting», «Агент стартует сам» — сочетания; D18.) Красный.

### B3. Реализация desktop

- [ ] B3.1 `[desktop]` `settings_cubit.dart`, `sessions_cubit.dart`: триггеры D13 через `ensureAgent`; номер намерения фокуса и проверка после каждого `await`; событие `session.focus_superseded` (D17); после сбоя триггер стартует заново (D13); схлопывание одинаковых сбоев в диагностике и счётчик повторов в состоянии экрана сбоя. B2.1, B2.2 зелёные.
- [ ] B3.2 `[desktop]` `connection_cubit.dart`:
  - удалить `connect` как ручной старт, `connectOnStart` и чтение ключа (у `ConnectionPreferences` удалить методы `connect_on_start`, если других читателей нет);
  - профиль окна по «Use» и метка «Selected»;
  - `restart()` с корнем по D18 и подтверждением D22 (состояние, droppable, событие `connection.restart`);
  - «Retry» повторяет намерение, вызвавшее старт.

  B2.3 зелёный.
- [ ] B3.3 `[desktop]` Старт приложения: восстановленный проект — триггер 1 (D19). B2.4 зелёный.
- [ ] B3.4 `[desktop]` `main_pane.dart`, `workbench_shell.dart`, страница «Connection»: стартовый экран, экран сбоя, диалог подтверждения, «Use» вместо «Connect» (ключ `connection-profile-use-<id>`), без «Connect on start», без «Connect» в app bar. Виджеты только отображают и передают действия (§6). При необходимости — `CodeLabStartScreen` в `codelab_ui` без логики, с превью в `codelab_organism_previews.dart`. Providers/MCP: источник папки — папка сессии в фокусе, иначе выбранный проект (D8). B2.5 зелёный.
- [ ] B3.5 `[desktop]` Харнесс характеризационных тестов: `connect()` → ожидание старта по проекту (D20). Каждый изменённый характеризационный тест перечислить в описании задачи с причиной (`codelab_client_core/AGENTS.md` §5). Интеграционные тесты: «Connect → New session» → «Open folder → New session» (компилируются; на устройстве — только в `release/*`).
- [ ] B3.6 `[desktop]` Текст исчезнувшей папки → `Project folder not found: <path>. Choose an existing folder with Open folder….` (без `and connect again`: в рабочем месте нет Connect, D2). Сейчас в коде `connection_cubit.dart` — `… and connect again.`. Сначала тесты (красные): `missing_project_folder_test.dart:74–75`, `connection_cubit_test.dart:653`; затем код.

### B4. Проверки

- [ ] B4.1 `[desktop]` `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm flutter analyze` и `fvm flutter test` в `apps/codelab_desktop` и, если тронут, в `packages/flutter/codelab_ui`.
- [ ] B4.2 `[desktop]` Ручная проверка на macOS (не условие merge):
  - `.app` через `open` без снимка;
  - со снимком из отчёта пользователя;
  - две папки со встроенным агентом: ход в одной не прерывается переходом в другую, запрет проекта второй папки действует;
  - «Use» другого профиля и «Restart agent» во время хода — диалог.
- [ ] B4.3 `openspec validate require-project-folder --strict`.
