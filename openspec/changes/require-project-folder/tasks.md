Три итерации:
- **A** — нет неявной папки. `[desktop]` и одно условие kit `[client]` (A1.10, A2.9, HIGH-1); закрывает дефект, выходит отдельно.
- **C** — конфигурация Dart-агента на сессию: провайдеры, модель, запреты, привязка ключа к адресу. `[agent]` и `[protocol]` для ACP-сервера; выходит отдельно и не зависит от A и B.
- **B** — агент стартует сам. `[client]`, затем `[desktop]`; выходит после C: иначе сессии других папок в одном агенте остались бы без запретов своего проекта.

Красные тесты коммитятся отдельно до кода — только по явной просьбе пользователя (TDD, вложенные `AGENTS.md`). Q14 (a) и Q15 (a) решены (design.md, «Открытые вопросы»).

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

### C1. Красные тесты

- [ ] C1.1 `[agent]` `packages/dart/codelab_agent_core/test/runtime/config_outside_root_test.dart` — переписать на новую семантику; прежние ожидания `withoutProject` переходят в группу «без порта». Фейковые `ProjectConfigLoader` (карта «папка → `ConfigLoadResult`», счётчик, управляемый `Completer`) и `modelsFor` (запись конфигураций, по которым строился каталог). Сценарии:
  - запрет доверенного `/B` действует, правила `/A` не применяются;
  - недоверенный `/B` — смягчение режима и провайдер отброшены;
  - провайдер `local` из `/B` — модель сессии `local/m`, в каталоге сессии `/A` его нет;
  - серверы `/A` не попадают в `/B`;
  - ключи процесса (`sessions.dir`, `logging.level`) из `/B` проигнорированы с `config.session.process_keys_ignored` без значений;
  - проблемы загрузки, `validateSnapshot` и исключение `modelsFor` — `ProjectConfigException`, сессии нет;
  - вторая сессия `/B` после смены результата загрузчика получает новые правила, первая — прежние (кэша нет);
  - `reloadConfig()` корня не меняет модель сессии `/B`;
  - остановка рантайма во время `loadForProject` — сессии нет, MCP не стартовал;
  - `/A/sub` — своя папка;
  - сессия в корне — загрузчик не вызван;
  - `session/load` вне корня тоже загружает;
  - без порта — `withoutProject` и `config.session.outside_root`;
  - порт без `modelsFor` — `HostWiringException`.

  (agent-runtime «Конфигурация сессии вне корня запуска», все сценарии; D21.) Красный.
- [ ] C1.2 `[agent]` Гонки в том же файле, порядок через `Completer`:
  - два параллельных `session/new` в `/B` и `/C` — у каждой сессии своя конфигурация и модель, без перекрёстного смешения;
  - `session/new` в `/B` во время `reloadConfig()` корня — сессия `/B` строится по своей загрузке, применённый снимок корня заменяется атомарно (agent-runtime «Живая перезагрузка конфигурации», «Замена»);
  - `session/set_config_option model` сессии `/B` во время хода другой сессии — меняет только `/B`.

  Красный.
- [ ] C1.3 `[agent]` `packages/dart/codelab_agent_core/test/config/` — правило D23 в разрешении конфигурации:
  - группа адреса берётся целиком из проектного слоя;
  - ссылка из `config.yaml` с чужим origin — `key_unbound`;
  - ссылка из `config.local.yaml` доверенного проекта — разрешена;
  - ссылка, связанная глобально с тем же origin, — разрешена;
  - `${secret:…}` и `${ENV}` в `headers` — по тому же правилу;
  - недоверенный проект — отброшен;
  - правило действует и для корня процесса.

  (agent-secrets «Ключ проектного провайдера привязан к адресу», все сценарии; D23.) Красный.
- [ ] C1.4 `[agent]` `packages/dart/codelab_agent_core/test/` (функция модели / ключ провайдера при запросе) — утечка. Фейковый `SecretResolver` с `codelab/anthropic = sk-test-leak-0123456789`, считает чтения; фейковый HTTP-клиент считает запросы. Для провайдера с непривязанной ссылкой:
  - HTTP-запросов 0, чтений секрета 0;
  - текст ошибки хода, все записи журнала (захват `configureCodeLabLogging`), `configOptions` и диагностика не содержат `sk-test-leak-0123456789`;
  - origin в тексте — без пути и userinfo.

  Красный.
- [ ] C1.5 `[agent]` `packages/dart/codelab_agent_io/test/config/file_config_source_test.dart`:
  - `loadForProject('/B')` читает слои папки, доверие — по закреплённому `initial`;
  - база сравнения наблюдателя не сдвигается;
  - несуществующая папка — результат без проектных слоёв;
  - ссылки `.codelab` наружу — проблема по правилу «Ссылки проектных слоёв при чтении»;
  - происхождение слоя (`project` или `projectLocal`) сохраняется для D23.

  (D21, D23.) Красный.
- [ ] C1.6 `[protocol]` `packages/dart/codelab_agent_acp/test/`:
  - `ProjectConfigException` на `session/new` / `session/load` → `-32603` с `data.codelab.reason: "projectConfigInvalid"`, без значений секретов; соединение и другие сессии живы; сессии нет в `session/list`;
  - `configOptions` `model` двух сессий разных папок различаются; `set_config_option` с моделью чужого каталога → `-32602`.

  (agent-acp-server «Ошибка проектного конфига сессии», «Модели сессии по её каталогу».) Красный.
- [ ] C1.7 `[agent]` `packages/dart/codelab_embedded/test/` (IO-тесты открывателя на временных папках): агент открыт для `/A`; доверенный `/B` задаёт `permissions.tools.exec: deny` и провайдера в `config.local.yaml` — в сессии `/B` `exec` запрещён, модель — провайдера `/B`; `scriptedEmbeddedAgentOpener` порт не передаёт (embedded-agent «Проектный конфиг сессий встроенного агента»). Красный.
- [ ] C1.8 `[agent]` `apps/codelab_agent/test/` (тесты `serve`): `serve --stdio` в `/A`, доверенный `/B` с `budget.max_steps: 3` — бюджет сессии `/B` равен 3, флаги `--model` / `--provider` входят в её слои; `--llm-script` порт не получает (agent-binary «Проектный конфиг сессий в serve»). Красный.

### C2. Реализация

- [ ] C2.1 `[agent]` `codelab_agent_core`:
  - порт `ProjectConfigLoader` и поле `AgentCoreServices.projectConfig` (экспорт из бареля);
  - `ProjectConfigException {cwd, issues}`;
  - проверка «порт без `modelsFor`» в `buildAgentCore`.

  Doc-комментарии на русском: почему `CoreConfig` на сессию, а `HostSettings` на процесс; почему fail closed (§2, приоритет 1); ссылка на D21.
- [ ] C2.2 `[agent]` Правило D23 в разрешении конфигурации (`resolveConfig`: происхождение полей группы по слоям, группа целиком, привязка к origin, признак `keyUnbound` у провайдера) и в построении запроса (ошибка без HTTP и без чтения секрета). Комментарий с угрозой и ссылкой на D23. C1.3, C1.4 зелёные.
- [ ] C2.3 `[agent]` `AgentRuntime._sessionConfig` и создание сессии: шаги D21 по порядку; функция модели и каталог сессии хранятся в сессии; `select_session_model` получает каталог сессии; события `config.session.project` и `config.session.process_keys_ignored`; отмена через `_shutdown`; без порта — прежний путь. C1.1, C1.2 зелёные; `config_reload_test.dart`, `project_files_runtime_test.dart`, `config_default_model_test.dart` остаются зелёными.
- [ ] C2.4 `[agent]` `codelab_agent_io`: `FileConfigSource implements ProjectConfigLoader` (тот же `ConfigLoader`, окружение, флаги, `extraConfig`, закреплённое доверие, происхождение слоёв, без сдвига базы наблюдателя). C1.5 зелёный.
- [ ] C2.5 `[protocol]` `codelab_agent_acp`: отображение `ProjectConfigException`; `configOptions` `model` и проверка `set_config_option` по каталогу сессии. C1.6 зелёный.
- [ ] C2.6 `[agent]` Подключение порта:
  - `codelab_embedded/lib/src/io/local_opener.dart` — `source` как `projectConfig`; `modelsFor` строит функцию модели для любой папки на общих HTTP-клиенте и резолвере секретов;
  - `apps/codelab_agent/lib/src/host/serve_config.dart` и сборка `serve` — то же.

  Doc-комментарии открывателя и `serve`: что берётся от папки запуска, а что от сессии. C1.7, C1.8 зелёные.
- [ ] C2.7 `[agent]` Проверить, что `/config check` в сессии вне корня ведёт себя как раньше. Если команда должна показывать проблемы папки сессии — записать вопрос, поведение не менять.

### C3. Проверки

- [ ] C3.1 `[agent]` `fvm dart format`, `fvm dart analyze`, `fvm dart test` в `codelab_agent_core`, `codelab_agent_io`, `codelab_embedded`, `apps/codelab_agent`; `[protocol]` — то же в `codelab_agent_acp`. Затем:
  - `melos run guard` — allowlist ядра не меняется, прогон-подтверждение;
  - `melos run web-compile`;
  - `melos run conformance:agent`;
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
