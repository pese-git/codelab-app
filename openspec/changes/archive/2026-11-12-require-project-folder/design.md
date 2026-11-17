## Context

### Источник папки сегодня

Папку проекта в desktop отдаёт геттер `SettingsCubit.projectDirectory` (`apps/codelab_desktop/lib/features/workbench/application/settings_cubit.dart`). Он возвращает `selectedProjectPath`, а если проект не выбран — `WorkingDirectoryProvider.currentPath`. Потребители (сверено с `develop`, коммит `938a5efc`):

| Место | Что получает | Что происходит с `/` сейчас |
|---|---|---|
| `ConnectionCubit.connect` / `reconnect` → `ClientWorkspace.connect` / `reconnect(projectDirectory:)` | папка подключения | `WorkspaceState.projectDirectory = /`, `session/list` по `/`, снимок пишет проект `/` |
| `ConnectionCubit.connectOnStart` → `connect` | то же, после `projectRestored` | старт из Finder без снимка подключается к `/` |
| `SettingsCubit.missingProjectDirectory` | проверка существования (кроме WebSocket) | `/` существует |
| `ConfigTransportResolver.open` (kit) | `StdioAcpTransportConfig.cwd` при `runInProjectDirectory` | процесс stdio стартует в `/` |
| `EmbeddedTransportResolver._openSerialized` → `localEmbeddedAgentOpener(cwd:)` | корень встроенного агента | `ConfigLoader.load(cwd: /)` (`local_opener.dart:57`), `LocalExecutionEnv`, `FileConfigSource` от `/` |
| `SessionsCubit.createSession` → `ClientWorkspace.newSession(cwd:)` | `cwd` в `session/new` | сессия в `/` |
| `AddProfileCubit`, `ConnectionSettingsCubit` → `ProfileProbe.probe` | spawn-cwd проверки stdio | проверка в `/` |
| `ProviderSettingsCubit`, `McpSettingsCubit` `_accessOf` | `cwd` для `resolveSettingsAccess` | проектные слои из `/.codelab/` |

### Агент и папка сегодня

Подключение — отдельный шаг: «Connect», «Connect on start», строка профиля на странице «Connection». ACP позволяет одному агенту обслуживать сессии любых папок: `cwd` «MUST be used for the session regardless of where the Agent subprocess was spawned» (`docs/protocols/acp/protocol/03-Session Setup.md`, «Working Directory»).

Что Dart-агент уже делает на сессию:
- `AGENTS.md` и файлы проекта — `_loadProjectFiles` по `cwd` сессии (`agent_runtime.dart`, около строки 1026);
- окружение исполнения — `localEnv(sessionCwd)` (`local_opener.dart:122`, `BoundedEnv.wrap(..., cwd)`).

Что делается на процесс: проектные слои конфигурации читаются один раз, для корня запуска (`local_opener.dart:57`; spec agent-binary «Конфиг бинаря…»: «проектные слои — для корня запуска»). Сессия вне корня получает `CoreConfig.withoutProject` — снимок без проектных слоёв (spec agent-runtime «Конфигурация сессии вне корня запуска»). Значит, запреты её собственного проекта (`permissions.deny`, ужесточённый режим, `permissions.tools.*`) к ней не применяются.

Ключи уже разделены спецификацией agent-runtime:
- **ключи сессии** — модель по умолчанию, `effort`, режим и правила разрешений, бюджет хода, пороги сжатия, MCP-серверы конфигурации, `redact`;
- **ключи сборки** — каталог провайдеров, capability, сужение профиля — общие для процесса (D21 переносит каталог провайдеров в ключи сессии).

### Kit

`ClientWorkspace` (`codelab_client_core`) держит одно соединение. `connect` и `reconnect` вытесняют прежнюю попытку по номеру `_attempt` (§9). После подключения kit:
- загружает заново открытые сессии (`_reattachSessions`);
- запрашивает первую страницу `session/list` по `WorkspaceState.projectDirectory`;
- при первом подключении в запуске восстанавливает снимок (`WorkspaceRestorer`).

`selectProject` меняет только `projectDirectory` и снимок, `session/list` при этом не перезапрашивается. `detached`-сессию снова загружает только переподключение.

### Код перед итерацией B (сверено с `develop` `b06a4192`, после итераций A и C)

Таблица «Источник папки сегодня» описывает состояние до итерации A. После A и C для B важно следующее.

**Kit (`codelab_client_core`).**
- `ClientWorkspace.connect(profile, projectDirectory:)` пишет в состояние и профиль, и `projectDirectory`; `reconnect({profile, projectDirectory})` тоже перезаписывает `projectDirectory` переданной папкой. Поля «корень процесса» нет: `TransportResolver.open(profile, projectDirectory:)` получает ту же папку.
- Номер попытки `_attempt` закрытый. Публичного «поколения соединения» нет; `Future` идущей попытки не хранится (для single-flight его нужно завести).
- `newSession({cwd})` всегда делает новую сессию активной в `WorkspaceState.activeSessionId`. По `activeSessionId` kit (а не по фокусу desktop) работают панель Files (`projectFolderOf`) и терминал (`TerminalTabsCubit._resolveOwner`).
- `_listFirstPage` и `loadMoreSessions` запрашивают `session/list` с `cwd: WorkspaceState.projectDirectory`; без папки ACP вернул бы сессии всех папок. Номера запроса списка нет, поздний ответ дописывается в `_listed` через `putIfAbsent`.
- `loadSession` для `detached`-сессии уже отправляет `session/load` (`_load` → `_track` → `reload`), но связь `_Link.detached` не снимается: статус остаётся `detached`, промпты отклоняются, очередь не сливается.
- `WorkspaceRestorer.restoreAfterConnect` (итерация A) не грузит активную сессию снимка вне его проекта; `observe` отменяет восстановление при выборе другого проекта.
- Реализации интерфейса `ClientWorkspace` вне kit: `FakeWorkspace` в `apps/codelab_desktop/test/support/fake_provider_settings.dart` (`implements`, ломается при новом методе) и `FakeClientWorkspace` там же в `test/support/fake_client_workspace.dart` (`extends Fake`, не ломается).

**Desktop.**
- `ConnectionCubit`: `connect([profile])`, `reconnect()`, `connectOnStart()` (вызов — `lib/app/codelab_app_widget.dart`, после первого кадра), `connectAfterProviderSetup` (повтор встроенного агента после мастера из баннера «Add provider»), `_rejectWithoutProject` с событием `connection.connect_rejected`, `_failIfProjectDirectoryMissing` с текстом `… and connect again.`. Реализует `ConnectionCommands` (`connect`, `reconnect`, `restartTarget`) для страницы «Connection».
- `SettingsCubit`: `awaitProject()`, `projectRestoreFinished`, `projectRestored`, `selectProject`, `browseForProject`, `missingProjectDirectory`.
- `SessionsCubit.createSession` после `awaitProject` без проекта открывает выбор папки, а без соединения пишет `Connect an ACP agent before creating a session.`. `_select` спрашивает подтверждение D24 только для строк `notLoaded`; `detached`-сессия при выборе только активируется. `_handleSessionChange` делает показываемой любую изменившуюся сессию, пока показываемой нет.
- Вход в «подключиться» и «переподключиться» вне `ConnectionCubit`: экран подключения (`main_pane.dart`, `CodeLabConnectionScreen` с `onConnect`/`onReconnect`), баннер (`onReconnect`), бейдж app bar (`onConnect`, `onRetry` в `workbench_shell.dart`), пункт палитры `reconnect` (`shell_cubit.dart`, `selectCommand`), «Restart agent» баннера переноса секретов (`SecretMigrationBanner(onRestart:)`), строка профиля «Connect» и «Restart agent» страницы «Connection» (`ConnectionSettingsCubit.connect`, `restartAgent`), кнопка «Connect» баннера страницы «Providers» после записи без агента (`ProviderSettingsCubit.connectAgent`, текст `Saved. Connect to start the agent with the new provider.`).
- Подсказка «Remove» у текущего профиля — `Disconnect first` (`connection_page.dart`).
- `ConnectionPreferences` хранит и профиль по умолчанию, и «Connect on start»; удаляются только методы второго.

**Панели, которые уже следуют за сессией.**
- **Files** (`add-file-preview-and-tree`). Папка — `projectFolderOf(WorkspaceState)`: `cwd` активной сессии kit, а для `notLoaded`/`detached` и без сессии — `projectDirectory`. Доступность — `sessionFolderIsLocal(ConnectionCubit.state.profile)`. До старта агента с выбранным проектом панель показывает проект; без проекта — пустое состояние. Неявной папки нет.
- **Терминал** (`add-integrated-terminal`). Владелец — `(WorkspaceState.profile.id, activeSessionId)`, папка — `SessionHandle.cwd`, `WorkingDirectoryProvider` не используется (Q19 того change). Без `SessionHandle` активной сессии — подсказка `Open a session to use the terminal`, shell не стартует (Q17). Правило «нет неявной папки» соблюдено; от соединения терминал не зависит. Итерация B его не ломает: `detached`-сессия держит `SessionHandle`, а `notLoaded` получает его после загрузки по фокусу.

### Решения пользователя

1. **«Без проекта — нет папки».** Проект выбирается только явно: «Open folder…», недавние проекты или восстановленный снимок.
2. **Агент как в OpenCode** (ответ на Q2/Q3). Один агент на окно обслуживает сессии любых папок и при смене папки не перезапускается. Ходы других сессий при переключении продолжаются. Сессия не должна терять запреты своего проекта, поэтому Dart-агент загружает проектный слой конфигурации по `cwd` каждой сессии. Сторонний stdio-агент сам отвечает за свои проектные настройки.
3. **Без кнопки Connect** (Q4). Экрана и кнопки Connect в рабочем месте нет, «Disconnect» не вводится. Агент стартует сам. Профиль на странице «Connection» выбирается и применяется к следующему старту. «Restart agent» остаётся для восстановления после сбоя и для смены профиля. Перезапуск при идущих ходах требует подтверждения — это единственный оставшийся случай перезапуска.
4. **Триггеры старта агента** (Q8 (b), Q5 (a), Q9 (a), Q10 (a)): выбор проекта (в том числе восстановленного при запуске), «New session», фокус на `notLoaded`- или `detached`-сессии. Сессии и перезапуска выбор проекта не вызывает, `session/list` идёт сразу. «Connect on start» удаляется. «New session» без проекта открывает системный выбор папки. WebSocket подключается при первом триггере, одно соединение на все папки.
6. **Q11–Q13.**
   - Q11: провайдеры, каталог и модель — на сессию, из слоёв её папки, как в OpenCode. Секреты — из общего хранилища процесса.
   - Q12: правка проекта применяется к следующему `session/new` или `session/load` его папки; живая перезагрузка — после 1.0.
   - Q13: после сбоя любой триггер снова пытается стартовать агента, с защитой от петли и спама.
5. **Остальное.** Q1 (b): проект-корень снимка не восстанавливается, сессии в `/` открываются только явным кликом. Q6 (a): CLI вне охвата. Q7 (a): `add-integrated-terminal` учтёт правило при своей реализации.

## Goals / Non-Goals

**Goals:**
- Ни агент, ни сессия, ни снимок не получают папку, которую пользователь не выбирал.
- К каждой сессии Dart-агента применяется конфигурация её проекта — запреты, модель, провайдеры, — независимо от папки, в которой стартовал процесс, и без утечки ключей на чужие адреса.
- Нет отдельного шага «подключиться»: агент стартует по триггерам решения 4.
- Переключение сессий и проектов не прерывает чужие ходы.
- Гонки старта, поздние результаты и перезапуск при смене профиля обработаны явно (§9, §12).

**Non-Goals:**
- CLI (`apps/codelab_cli`), ACP.
- Процесс агента на папку или сессию (модель Claude Code) — после релиза 1.0 (D12).
- Живая перезагрузка проектных слоёв папок, отличных от корня процесса, у уже открытых сессий — после 1.0 (Q12).
- Формат снимка, «закрыть сессию», «Disconnect».
- Удаление «Test connection» — отдельный change после этого; здесь D7 временное.

## Заменяемые решения прежних changes

| Change (архив) | Решение | Что меняется |
|---|---|---|
| `2026-09-04-add-open-project-picker` | Decision 1, часть `selectedProjectPath ?? currentPath`; Goal про `WorkingDirectoryProvider.currentPath` | Запасной папки нет (D1) |
| `2026-09-04-add-open-project-picker` | Decision 2, spawn-cwd `selectedProjectPath ?? currentPath` | Агент без папки не стартует (D2) |
| `2026-11-05-add-app-settings-shell` | D8 «Connect on start» | Удаляется (D19) |
| `2026-11-05-add-app-settings-shell` | D6 (`ConnectionCubit` подключает профиль по «Connect»), D9 («Restart agent» — переподключение цели) | Профиль выбирается для следующего старта; «Restart agent» применяет выбранный профиль с подтверждением (D18) |
| `2026-10-27-add-session-list-and-reload` | D6, шаги восстановления «внутри первого успешного `connect()`» | Первый старт агента — по восстановленному проекту (D13, D19); активная сессия снимка вне его проекта не грузится (D16) |
| `2026-10-27-add-connection-and-error-states` | Экран подключения как состояние пустой ленты | Стартовый экран; экран сбоя старта с «Retry» (D18) |
| `2026-10-30-add-agent-configuration` | D9 — сессия вне корня получает `withoutProject` | Сессия получает проектные слои своего `cwd` (D21) |

Затронутые спецификации:
- `agent-workbench-ui`, `app-settings`, `acp-client-kit` (клиент);
- `agent-runtime`, `agent-acp-server`, `agent-secrets`, `embedded-agent`, `agent-binary` (агент).

`client-agent-setup` и правила доверия `agent-configuration` не меняются: доверие применяется к проектным слоям любой папки так же, как к корню запуска. Привязку ключа к адресу задаёт новое требование `agent-secrets` (D23). Его следствие для конфликта источников ключа R8-6 меняет `agent-configuration` «Секреты только ссылками» и `agent-secrets` «Подкоманда secret migrate» (оба MODIFIED, D25).

## Decisions

Номера D4, D6 и D14 из прежних редакций сняты. Их заменили D18, D19 и D22 после ответов пользователя.

### Часть A — нет неявной папки

#### D1. `projectDirectory` — `String?` без запасного варианта

`SettingsCubit.projectDirectory` возвращает выбранный проект (после `trim`; пустая строка — не проект) или `null`. Параметр `workingDirectoryProvider` удаляется из `SettingsCubit`, `CodeLabShellParts.build`, обоих конструкторов `CodeLabShellCubit` и из привязки в `app_scope.dart`. Файл-прослойка `lib/core/platform/working_directory_provider.dart` удаляется. Порт в `codelab_client_io` остаётся: это публичный API пакета (§19).

- Отклонено: оставить `String` с пустой строкой как маркером «нет проекта». `Process.start(workingDirectory: '')` падает на `chdir`, а `ConfigLoader.load(cwd: '')` читает относительные пути.
- Отклонено: домашняя папка как запасной вариант. Это та же неявная папка (решение 1, `platform-integration.md` §54).

#### D2. Агент без папки не стартует

Любой старт агента требует папку триггера: выбранный проект или `cwd` сессии. Без проекта нечего передать, и агент не стартует ни для одного типа профиля. Для WebSocket «старт» — открытие соединения. Проверка «папки нет на диске» остаётся для локальных профилей. Сообщение: `Project folder not found: <path>. Choose an existing folder with Open folder….`

#### D3. Папка читается один раз на намерение

Сейчас `connect` читает папку дважды: в `missingProjectDirectory()` до `await` проверки диска и в `_workspace.connect` после неё. Каждое намерение (выбор проекта, новая сессия, фокус, перезапуск) берёт папку один раз. Это же значение получают проверка диска, старт агента и `session/new` / `session/load`.

**Ожидание восстановления проекта** (ревью итерации A). Проект прошлого запуска выбирается асинхронно (`SettingsCubit.projectRestored`). Действие пользователя в первые миллисекунды после старта не должно получать отказ «нет проекта», пока проект ещё восстанавливается. Поэтому `connect`, `reconnect` и `createSession` вызывают одну функцию `SettingsCubit.awaitProject()`:
- если восстановление уже завершено, она сразу возвращает текущий проект или `null`;
- иначе ждёт `projectRestored` не дольше `projectRestoreTimeout` (2 с);
- после таймаута или ошибки восстановления возвращает выбранный к этому моменту проект или `null`.

`connect` и `reconnect` ставят статус `connecting` / `reconnecting` до ожидания, чтобы повторное нажатие во время ожидания не запустило второе подключение. Номер намерения проверяется после ожидания (§9). Если после ожидания проекта нет — отказ до обращения к workspace:
- диагностика `warning` `Open a project before connecting: choose a folder with Open folder….`;
- событие журнала `connection.connect_rejected {reason: no_project, profile_id}` без пути.

`createSession` после ожидания без проекта открывает выбор папки (D5).

#### D5. «New session» без проекта открывает выбор папки

Без проекта `createSession` вызывает `SettingsCubit.browseForProject()`, сессию не создаёт и агенту ничего не шлёт. Выбор папки — триггер старта агента (D13), но сессию он не создаёт. Повторное «New session» создаёт её.

#### D7. Проверка профиля без проекта

`AddProfileCubit` и `ConnectionSettingsCubit` получают `String? Function() projectDirectory`. Если папки нет, stdio-профиль с `runInProjectDirectory` уходит в `ProfileProbe.probe` как `profile.copyWith(runInProjectDirectory: false)`. Проверка — только `initialize`, без `session/new`, папка ей не нужна. Kit не меняется.

- Отклонено: запрещать проверку без проекта — это ломает «Add connection profile» новому пользователю.
- Отклонено: передавать `''` как рабочую папку процесса — ложный `Unreachable` из-за `chdir`. Допустимо `''` в параметре `projectDirectory` только вместе со сброшенным `runInProjectDirectory`: kit тогда папку не читает.

**D7 временное.** Пользователь решил убрать «Test connection» совсем — отдельным change после этого (`ProfileProbe` в UI, кнопки в строке профиля и в диалоге «Add connection profile»). До него D7 держит проверку корректной без проекта. Change удаления D7 снимает вместе со сценарием «Test connection without a selected project» в agent-workbench-ui.

#### D8. Providers и MCP servers

Источник папки — `String? Function()`: папка сессии в фокусе, иначе выбранный проект. Без того и другого — `cwd: null`: проектных слоёв нет, а `projectLocal` не предлагается (spec client-agent-setup). Источник выбран по D21: провайдеры, модель и запреты — ключи сессии, поэтому страница показывает конфигурацию той папки, с которой работает пользователь. Ключи хоста (`secrets.backend`) берутся из той же загрузки; страница их только показывает.

#### D9. Встроенный резолвер отказывает без папки

`EmbeddedTransportResolver.open` с пустой папкой завершается `ClientWorkspaceException('Open a project to start the embedded agent.')`. Открыватель не вызывается, поколение не сдвигается. Это защита в глубину.

#### D10. Снимок старой версии (Q1 (b))

**Корень диска.** Функция `isFilesystemRoot(path)` (`apps/codelab_desktop`, чистая, `package:path`) сначала нормализует путь (`p.normalize`), затем сравнивает `p.rootPrefix(n) == n`. Поэтому `/`, `//`, `/.`, `/tmp/..` и `C:\` считаются корнем, а `/work` — нет. Ею пользуются D10 и D24.

`SettingsCubit._restoreProject` не выбирает проект-корень (`isFilesystemRoot`). Вместо этого пишется предупреждение `Project folder from the last run is the filesystem root: <path>. Choose a folder with Open folder….`. Сессии такого снимка убирает существующее правило kit: выбор другого проекта отменяет восстановление. Явный выбор `/` через «Open folder…» не запрещается.

**Активная сессия снимка грузится только в папке проекта снимка** (HIGH-1 ревью безопасности, перенесено из D16 в итерацию A). Пример: снимок `{projectDirectory: /work/app, activeSessionId: s1, openSessions: [{s1, "/"}]}`. Сейчас первое подключение восстанавливает `/work/app` и делает `session/load(s1, cwd: "/")`. Агент получает весь диск без действия пользователя — это противоречит Q1 (b).

Правило: `WorkspaceRestorer.restoreAfterConnect` загружает активную сессию снимка, только если её `cwd` равен проекту снимка (точное равенство строк). Записи снимка пишет kit из `SessionView.cwd` и `projectDirectory`; при несовпадении записи выбирается отказ, а не загрузка. Иначе сессия остаётся строкой `notLoaded`: без `session/load`, без `session/new` с уведомлением и без активации. Открыть её можно только кликом с подтверждением D24.

Место — kit, `[client]` в итерации A. Desktop не видит активную сессию снимка до `restoreAfterConnect`, а вводить для этого новый API (`restoredActiveSession`) — шире, чем одно условие в `WorkspaceRestorer`. Правило не зависит от модели агента и в B не меняется.

#### D24. Подтверждение открытия сессии в корне диска (решение пользователя)

Клик по сессии `notLoaded` или `detached`, чей `cwd` — корень диска (`isFilesystemRoot`), сначала показывает диалог:

`This session runs in the disk root (/). The agent gets access to the whole disk. Open anyway?`

с заголовком `Open session in the disk root?` (у `ContentDialog` без заголовка хуже доступность) и кнопками `Open` и `Cancel`. В тексте подставляется нормализованный `cwd`. Корень проверяется в обоих стилях путей (`p.posix` и `p.windows`): `cwd` удалённого агента может быть путём другой ОС. Вопрос снимается как `Cancel`, если строка сессии исчезла из списка (потеря соединения, смена проекта); `decision: open` пишется только при фактической загрузке. Поздняя загрузка ранее выбранной сессии не снимает открытый вопрос — снимает только новое действие пользователя (D17). `session/load` идёт только после `Open`. `Cancel` и закрытие диалога ничего не меняют: фокус прежний, строка в прежнем статусе, агенту ничего не отправлено.

- **Владелец** состояния «ждёт подтверждения» — `SessionsCubit`, как у остальных решений о сессии. Виджет показывает диалог и возвращает решение (§10: widget не решает, что опасно).
- **Вытеснение.** Новое действие фокуса во время диалога закрывает его как `Cancel` (D17). Повторный клик по той же сессии при открытом диалоге игнорируется.
- **Событие** `session.root_open {decision: open|cancel}` без пути.
- **Охват итерации A** — строки `notLoaded`: только они сейчас загружаются кликом (`SessionsCubit._loadAndSelect`). Для `detached` диалог включается в B вместе с загрузкой `detached` по фокусу (D16), той же функцией.
- **Не для новых сессий.** Создать новую сессию в `/` можно только явным выбором проекта `/`, и это отдельное осознанное действие.

### Часть B — агент стартует сам и обслуживает все папки

#### D11. Модель: один агент на окно, любой `cwd`

Окно держит не больше одного агента (процесс stdio, встроенный агент или соединение WebSocket) с профилем окна. Агент обслуживает сессии любых папок, как разрешает ACP. Каждая сессия получает свой `cwd` в `session/new` / `session/load`. **Корень процесса** (`WorkspaceState.agentDirectory`) — папка триггера, которым агент стартовал. Из неё:
- stdio-процесс с «Run in the project folder» получает рабочую папку;
- встроенный агент и `codelab-agent` берут ключи процесса (`HostSettings`, D21) и конфигурацию сессий этой папки.

Смена проекта, фокус и новые сессии других папок агента не перезапускают.

#### D12. Процесс на папку — отложенная альтернатива

Модель Claude Code (процесс агента на папку или сессию) отложена до выхода 1.0. Она требует многосвязного `ClientWorkspace`: несколько бэкендов, маршрутизацию сессий, одобрений, `fs/*` и `terminal/*` по соединению. Плюсы модели — полная изоляция ключей сборки по проекту и сбоев по процессу. Минусы — память и время старта на каждую папку. Пока изоляцию ключей сессии даёт D21.

- Отклонено: перезапуск агента при смене папки (прежняя редакция D12). Он прерывает ходы других сессий, а это прямо противоречит требованию пользователя.

#### D13. Триггеры старта агента

Агент стартует, если он не работает, на любом из триггеров:

1. **Выбор проекта** — «Open folder…», недавний проект, проект, восстановленный при запуске. Сессия не создаётся. После подключения kit запрашивает `session/list` выбранного проекта. Если агент уже работает, выбор проекта его не трогает, но `session/list` нового проекта запрашивается сразу (D15).
2. **«New session»** в выбранном проекте `P`: старт агента в `P`, если его нет, затем `session/new` с `cwd: P` и фокус.
3. **Фокус на сессии `notLoaded` или `detached`**: старт агента в `cwd` сессии, если его нет, затем `session/load` с этим `cwd` и фокус. Для сессии в корне диска корень процесса — выбранный проект, а корень диска — только без проекта (Q27 (a)). Для `detached`-сессии у работающего агента без `loadSession` загрузки нет: сессия показывается для чтения (Q26 (a)).
4. **«Retry»** экрана или баннера сбоя: повторяет намерение, вызвавшее старт.

   Уточнение при сверке (2026-11-12). Намерение, вызвавшее старт, хранит владелец старта (`ConnectionCubit`) как функцию-повтор: «выбран проект `P`», «новая сессия в `P`», «открыть `S`». Баннер `lost` (агент работал и упал) неудачного намерения не имеет; его «Retry» — новый старт по D15 (`ensureAgent` с прежним корнем процесса `agentDirectory` и профилем окна). Открытые сессии kit при этом загружает заново, как после переподключения. Бейдж app bar в `lost`/`failed` делает то же, что «Retry» баннера. Повтор после мастера «Add provider» из баннера встроенного агента (`connectAfterProviderSetup`) — тоже «Retry» той же функцией, с прежней защитой от чужой попытки (метка `ProviderSetupNotice`).

Ни кнопки Connect, ни «Connect on start» нет. Cmd/Ctrl+N и пункт палитры `new` доступны при выбранном проекте.

**После сбоя старта** (Q13) любой триггер снова пытается стартовать агента. Защита от петли и спама:
- **single-flight** — одна попытка на окно в каждый момент, параллельные триггеры ждут её (`ensureAgent`, D15);
- **без автоповторов** — попытка начинается только действием пользователя (клик, выбор, «Retry») или восстановлением проекта при запуске. Таймеров, повторов по `ConnectionLost` и повторов после сбоя внутри одной попытки нет (`session-lifecycle.md` §35–§38: retry policy явная);
- **без дублей в диагностике** — сбой с тем же профилем, корнем процесса и текстом, что предыдущий, новой записи в диагностике не создаёт. Счётчик повторов растёт в состоянии экрана сбоя (`Failed again (n)`), в журнал уходит `connection.start_failed {profile_id, repeat}` уровня `debug`. Другой текст, профиль или корень — новая запись уровня `error`. Счётчик сбрасывает успешный старт.

#### D15. Kit: `ensureAgent`, `agentDirectory`, список при выборе проекта

Новая операция kit:

```dart
/// Агент профиля окна: ничего не делает, если он подключён или подключается;
/// иначе открывает соединение с корнем процесса [directory] (D11, D13).
Future<void> ensureAgent(String directory, {ConnectionProfile? profile});
```

1. Профиль — `profile` или профиль текущего / последнего соединения. Без профиля — `ClientWorkspaceException`.
2. `Connected` — no-op. Идёт попытка (`Connecting`, `Reconnecting`) — возвращается её `Future` (single-flight; `concurrency.md` §29–§30, `session-lifecycle.md` §10). Папка повторного вызова при этом не важна: корень процесса задаёт первый триггер.
3. Иначе (`Disconnected`, `ConnectionFailed`, `ConnectionLost`) — новая попытка путём `connect`. Отличие одно: `projectDirectory` (выбранный проект, снимок) не перезаписывается. `agentDirectory` становится `directory`. После сбоя `ensureAgent` вызывает любой триггер D13, но только по действию пользователя; сам kit попытки не повторяет.
4. `connect(profile, projectDirectory:)` остаётся для CLI и задаёт обе папки. Поведение CLI не меняется.

`selectProject(path)` при `Connected` запрашивает первую страницу `session/list` нового проекта. Прежний список и курсор сбрасываются, как после подключения. Поздний ответ списка прежнего проекта отбрасывается: номер запроса сравнивается после `await`.

**Технические уточнения при сверке с кодом (2026-11-12).** Поведения сверх D11–D17 они не добавляют.
- **Single-flight.** Kit хранит `Future` идущей попытки (`connect`, `reconnect` или `ensureAgent`) и отдаёт его повторному `ensureAgent`. Вытесненная попытка по-прежнему завершается без ошибки (контракт `connect`), поэтому вызывающий читает итог из `WorkspaceState.connection`.
- **Перезапуск не трогает проект.** Сейчас `reconnect(projectDirectory:)` перезаписывает `projectDirectory`, и «Restart agent» с корнем из папки сессии в фокусе (D18) сменил бы выбранный проект и список. Поэтому `reconnect` получает именованный параметр `agentDirectory`: он задаёт только корень процесса. `projectDirectory` по-прежнему задаёт обе папки (путь CLI). Без обоих параметров корень — прежний `agentDirectory`, а без него — `projectDirectory`. Desktop вызывает `reconnect(profile:, agentDirectory:)`.
- **Резолвер.** `TransportResolver.open(profile, projectDirectory:)` получает корень процесса (`agentDirectory`). Имя параметра не меняется: это публичный API kit и CLI (§19).
- **Список без проекта.** Если `projectDirectory` не задан, `session/list` не запрашивается ни после `ensureAgent`, ни после переподключения: ACP без `cwd` вернул бы сессии всех папок, а сайдбар показывает список проекта.
- **Номер запроса списка** покрывает и первую страницу после подключения, и `selectProject`, и `loadMoreSessions`. Ответ с устаревшим номером не трогает `_listed`, курсор и `hasMoreSessions`. Защита `_listing` от повторного `loadMoreSessions` не блокирует запрос нового проекта.
- **Новая сессия без активации.** `newSession({cwd, activate = true})`. С `activate: false` сессия попадает в список и снимок, но `activeSessionId` не меняется. Это нужно для D17: по `activeSessionId` kit работают Files и терминал, и сессия устаревшего намерения не должна переключать их мимо фокуса чата.

#### D16. Kit: восстановление и `detached`

- **Перезагрузка** открытых сессий после подключения — без изменений: загружаются все открытые сессии с их `cwd`, ведь один агент обслуживает любые папки.
- **Восстановление снимка** — правило активной сессии реализовано в итерации A (D10); B его не меняет.
- **`loadSession` для `detached`.** `loadSession` принимает и `detached`-сессию: после загрузки она снова принимает промпты и сливает очередь. Это нужно для триггера 3 D13: фокус на `detached`-сессии не должен ждать ручного перезапуска. В коде это одна правка: после успешного `_load` для существующего handle вызвать `resume()` (сейчас `_Link.detached` остаётся). Ошибка загрузки оставляет сессию `detached` с прежним уведомлением.

#### D17. Гонки (§9, §12)

- **Старт агента.** Параллельные триггеры (выбор проекта и сразу «New session», двойной клик) дают одну попытку: single-flight в `ensureAgent`. Намерения после неё продолжаются каждое своим шагом.
- **Последнее намерение фокуса побеждает.** `SessionsCubit` ведёт номер намерения фокуса («новая сессия», «открыть `S`»). После каждого `await` (`ensureAgent`, `session/new`, `session/load`) намерение проверяет, что оно ещё последнее. Устаревшее не меняет фокус и пишет `info` `session.focus_superseded`. Сессия, созданная устаревшим `session/new`, остаётся в списке без фокуса: агент её создал, терять её нельзя.
- **Фокус на сессии во время её загрузки** — повторный `loadSession` возвращает тот же `Future` (уже есть в kit).
- **Список при быстрой смене проекта** — номер запроса `session/list` (D15).
- **Перезапуск** (D22) вытесняет всё, что ждало старое соединение. Намерения, начатые до перезапуска, проверяют поколение соединения и не применяют поздние ответы. Поколение — номер попытки `ConnectionCubit` (сейчас `_attempt`), открытый `SessionsCubit` геттером. Kit публичного поколения не вводит: его номер попытки нужен только ему.
- **Сессия устаревшего намерения не забирает фокус** ни в kit, ни в desktop. Устаревший `session/new` вызывается с `newSession(activate: false)` или, если намерение устарело уже после ответа, фокус kit возвращается `activate` последнего намерения. В `SessionsCubit._handleSessionChange` правило «нет показываемой — показать изменившуюся» не применяется к сессии устаревшего намерения, пока ждёт последнее.

#### D18. Рабочее место без Connect

- **Стартовый экран.** Без сессии в фокусе панель сессии показывает стартовый экран:
  - без проекта — `Open a project to start a session.` и «Open folder…» (ключ `start-open-project`);
  - с проектом — `Start a new session in <folder name>.` и «New session» (ключ `start-new-session`).

  Пока агент стартует, рядом показывается индикатор `Starting <profile title>…`.
- **Сбой старта.** Если старт агента упал, панель показывает причину (`CodeLabConnectionScreen` с `description` и `extraAction`), «Retry» (повторяет намерение, вызвавшее старт) и «Connection settings». Баннер над непустой лентой (`lost`, `failed`, `reconnecting`) остаётся, его действие — «Retry».
- **App bar.** Бейдж соединения остаётся, действия «Connect» нет.
- **Страница «Connection».**
  - «Connect» в строке профиля заменяется на «Use». Он делает профиль профилем окна для следующего старта агента и не меняет профиль по умолчанию. Строка получает метку «Selected».
  - Если агент работает с другим профилем, строка «Restart agent» блока «Behavior» показывает `Restart <title> to use it.`.
  - «Current» остаётся у профиля работающего агента.
  - Ручного подключения и «Disconnect» нет.
- **«Restart agent» / «Reconnect»** перезапускает агента с выбранным профилем окна (D22). Корень процесса — папка сессии в фокусе, иначе выбранный проект, иначе прежний корень. Без проекта и без прежнего корня строка недоступна с подсказкой `Starts when you open a project.`. Папка сессии в корне диска берётся корнем, только если других кандидатов нет (Q27 (a)).

**Технические уточнения при сверке с кодом (2026-11-12).**
- **Два профиля окна.** `ConnectionCubit` различает выбранный профиль («Selected», для следующего старта) и профиль работающего агента («Current», сейчас `_accepted`). Подписи экрана старта и сбоя (`Starting <title>…`) — по выбранному. Доступность Files (`sessionFolderIsLocal`) и подпись бейджа — по профилю работающего агента, а до первого старта — по выбранному. Иначе «Use» WebSocket-профиля при работающем встроенном агенте скрыл бы Files его сессий.
- **`ConnectionCommands`** страницы «Connection»: `connect(profile)` заменяется на `use(profile)`, `reconnect()` — на `restart()` с подтверждением D22; `restartTarget` — выбранный профиль.
- **Диалог D22** рисуется по состоянию `ConnectionCubit` и над рабочим местом, и над настройками: «Restart agent» нажимают на странице «Connection», а баннер переноса секретов и палитра — в рабочем месте. Значит, виджет диалога живёт на уровне `CodeLabApp` (`lib/app/codelab_app_widget.dart`), а не в `workbench_shell.dart`.
- **Подсказка «Remove»** у профиля работающего агента и у выбранного — `Use another profile first.` вместо `Disconnect first` (дельта app-settings).
- **`codelab_ui`.** `CodeLabAppBar.onConnect` и `CodeLabConnectionScreen.onConnect` уже необязательны; desktop их не передаёт. Экран сбоя — `CodeLabConnectionScreen` с `description`, `extraAction` и `onReconnect` как «Retry». Подпись кнопки «Reconnect» в `CodeLabConnectionBanner` и `CodeLabConnectionScreen` — параметр (по умолчанию прежняя), desktop передаёт `Retry`. Стартового экрана в ките нет: `CodeLabStartScreen` без логики, с превью в `codelab_organism_previews.dart`.
- **Остальные тексты с «Connect»** заменяются по Q22 (a); пункт палитры `/reconnect` — «Restart agent» с подтверждением (Q24 (a)); «Restart agent» доступна и во время старта, вытесняя попытку (Q25 (a)).

#### D19. Старт приложения и «Connect on start»

«Connect on start» удаляется: строка из блока «Behavior» и чтение ключа из `ConnectionCubit`. Ключ `codelab.connection.connect_on_start` больше не читается и не пишется. При запуске восстановленный проект — триггер 1 D13: агент стартует в его папке. Kit восстанавливает снимок по D16, а активная сессия в папке проекта загружается и получает фокус. Без восстановленного проекта агент не стартует.

**Сохранённый ключ (сверено 2026-11-12).** Ключ не мигрируется и не удаляется: app не пишет `shared_preferences` без действия пользователя, а значение больше ничего не значит. Следствие решения Q8 (b): пользователь с прежним `false` (значение по умолчанию) теперь получает старт агента при восстановленном проекте. Порт `ConnectionPreferences` остаётся (профиль по умолчанию), из него уходят `loadConnectOnStart` и `saveConnectOnStart`, из `ConnectionSettingsState` — поле `connectOnStart`.

**Где срабатывает триггер запуска.** Как сейчас `connectOnStart`: `CodeLabApp` после первого кадра вызывает один раз метод фасада (рабочее имя `startOnLaunch`). Он ждёт `SettingsCubit.projectRestored` и, если проект выбран, вызывает тот же старт, что триггер 1. Выбор проекта пользователем — триггер в `SettingsCubit.selectProject`, а восстановление (`_restoreProject`) старт само не вызывает. Почему так: тесты Cubit-ов без виджета приложения не стартуют агента сами, и харнесс управляет стартом явно (D20); иначе каждый `CodeLabTestBinding(project:)` запускал бы агента при сборке графа.

Итерация A выходит раньше B. До B «Connect» и «Connect on start» ещё существуют, но без проекта отказывают: ручной Connect — по D2, а «Connect on start» пропускается с событием `connection.connect_on_start_skipped`. Дельты спецификаций описывают итоговое состояние после всех итераций; промежуточное поведение A фиксируют её задачи и тесты.

#### D20. Тесты и обвязка

- `test/support/test_app_scope.dart` (`CodeLabTestBinding`) получает необязательный стартовый проект — подложенный снимок `WorkspaceSnapshotStore`. Харнесс характеризационных тестов стартует с временной папкой-проектом. С ним агент стартует сам, поэтому метод харнесса `connect()` превращается в ожидание старта.
- Тексты характеризационных тестов меняются только там, где они проверяют подключение без проекта или кнопкой Connect. Каждое такое место перечисляется в задаче с причиной (`codelab_client_core/AGENTS.md` §5). Изменения итерации A:
  - `shell_cubit_characterization/harness.dart`: новый `projectReady()` (ждёт `SettingsCubit.projectRestored`), и `connect()` вызывает его перед `cubit.connect()`. Причина: стартовый проект теперь приходит из подложенного снимка асинхронно, а без проекта подключение отклоняется (D1, D2). Утверждения харнесса не меняются.
  - `shell_cubit_characterization/sessions_test.dart`, тест `createSession() before connecting sends nothing`: перед `createSession()` добавлено `await h.projectReady()`. Причина: без проекта `createSession` теперь открывает выбор папки (D5), а тест проверяет прежний смысл — без соединения агенту ничего не уходит — при выбранном проекте. Ожидания не меняются.
- `widget_test.dart`: ожидание `cwd == currentPath` заменяется на `cwd` выбранного проекта.
- Интеграционные тесты app: «Connect → New session» → «Open folder → New session». Они компилируются в `feature/*`, а на устройстве запускаются только в `release/*` (§21).
- Тесты kit и агента используют принудительный порядок завершений (`concurrency.md` §69–§70).
- **Принятые тестовые швы (итерация B).** `CodeLabApp(startOnLaunch:)` (по умолчанию `true`) отключает триггер запуска в виджет-тестах страниц, которым старт агента при восстановленном проекте мешает; `SettingsCubit.bindProjectStart(null)` отключает старт при выборе проекта в тестах, которые стартуют агента явно. Перенос выключателя в обвязку потребовал бы регистрации в scope для каждого виджет-теста; шов выбран как меньшее зло.

**Объём миграции тестов в итерации B (сверено 2026-11-12).**
- **Харнесс** (`shell_cubit_characterization/harness.dart`): `connect()` вызывает триггер запуска фасада (`startOnLaunch`, D19) и ждёт `connected`. Остальные шаги не меняются.
- **Характеризационные тесты**, которые меняются, с причиной (`codelab_client_core/AGENTS.md` §5):
  - `connection_test.dart`: `connect() goes connecting → connected over stdio` — старт по триггеру; начальное `disconnected` сохраняется, потому что без виджета агент не стартует сам. `connect() without a stdio command…`, `connect() over WebSocket without an endpoint…`, `a WebSocket connect failure is reported without the bearer token` — профиль выбирается «Use», старт — триггером: ручного `connect(profile)` нет (D18). Ожидания исхода не меняются.
  - `reconnect_test.dart`: `reconnect()` → «Restart agent» без идущих ходов, без диалога D22. Ожидания не меняются.
  - `sessions_test.dart`, `createSession() before connecting sends nothing`: при выбранном проекте «New session» теперь стартует агента (D13). Тест переписывается на «до ответа на `initialize` `session/new` не уходит, после — уходит один».
- **Остальные тесты desktop**, которые зовут ручной `connect`, «Connect on start» или ключи кнопок Connect: около 30 файлов, больше всего — `connection_cubit_test.dart`, `widget_test.dart`, `connection_settings_cubit_test.dart`. Замена механическая: `connect(profile)` → «Use» и триггер, `reconnect()` → `restart()`, `connectOnStart()` → `startOnLaunch()`. Тесты итерации A на ручной Connect (`project_required_test.dart`, `missing_project_folder_test.dart`: A1.2, A1.3, A1.14) переписываются на триггеры старта с теми же ожиданиями.
- **Интеграционные тесты** (`integration_test/`, 14 файлов). Все подключаются через `connectProfileViaSettings` в `support/e2e_agent.dart` (`E2eLaunch.connect`, `E2eWebSocketAgent.connect`), а проект выбирают через `ensureProject` или `selectProject` до подключения. После B порядок обратный: сначала «Use» профиля теста на странице «Connection», затем выбор проекта (триггер старта). Иначе выбор проекта стартовал бы профиль по умолчанию (встроенный агент), а не агента теста. Тесты на кнопку Connect в строке (`connection_profiles_flow_test.dart`, `stdio_connect_flow_test.dart`) переходят на «Use» и выбор проекта.

#### D22. Единственный перезапуск — «Restart agent», подтверждение при работе

Перезапуск агента — только «Restart agent» / «Reconnect» (страница «Connection», диалог переноса секретов). Если хотя бы одна сессия окна в ходе, ждёт одобрения или отменяется, сначала показывается диалог:

`Restart <title>? This interrupts <n> running session(s): <titles>. Queued prompts stay.`

с кнопками «Restart agent» и «Cancel».

- **«Cancel»** ничего не меняет.
- **«Restart agent»** вызывает kit `reconnect(profile: выбранный, agentDirectory: корень по D18)` — выбранный проект при этом не меняется (D15). Ходы обрываются, как сейчас: `session/cancel` перед заменой транспорта kit не шлёт (`codelab_client_core/AGENTS.md`). Ждущие одобрения снимаются, очередь сохраняется. Открытые сессии загружаются заново.

Без работы в сессиях диалога нет: это восстановление после сбоя или смена профиля в покое. Владелец состояния «ждёт подтверждения» — `ConnectionCubit`; виджет показывает диалог и возвращает решение (§10: widget не решает, что опасно). Пока диалог открыт, другие перезапуски игнорируются (droppable, `concurrency.md` §62). Событие `connection.restart {reason: failure|profile_changed|manual, interrupted: n}` пишется без пути.

### Часть C — проектный конфиг Dart-агента на сессию

#### D21. Конфигурация сессии из слоёв её `cwd`, включая провайдеров

Сейчас сессия вне корня запуска получает `CoreConfig.withoutProject` (spec agent-runtime). Теперь `AgentRuntime` строит для такой сессии полный `CoreConfig` **её** папки и свою функцию модели (как в OpenCode, ответ на Q11). Слои папки: `user`, `<cwd>/.codelab/config.yaml`, `<cwd>/.codelab/config.local.yaml`, `--config`, окружение и флаги. Загрузчик тот же, доверие закреплено (`trusted_projects` из `initial`).

**Деление ключей** — по типу, а не по списку (таблица — уточнение при реализации, 2026-11-12: `exec.*`, `compaction.enabled`, `profile.*` отнесены к процессу по коду `buildAgentCore` и схемы):

| Область | Что | Источник |
|---|---|---|
| Сессия | всё, что входит в `CoreConfig`: `providers.*`, `model_catalog.*`, `agent.default_model`, `effort`, `permissions.*`, `budget.*`, пороги `compaction.*`, `mcp.servers`, `redact.*`, `tools.project_context.max_bytes`, а также функция модели (`StreamFunction`) и каталог сессии — через `modelsFor(CoreConfig сессии)` | слои папки сессии |
| Процесс | `HostSettings` (`secrets.*`, включая бэкенд; `sessions.*`; `logging.*`; `config.*`; `profile.*` — сужение профиля), `exec.*` (ключи схемы без потребителя, `applied: false`), `compaction.enabled` (выключает capability `compaction` в `buildAgentCore`), `trusted_projects`, capability, хранилище секретов (`SecretResolver`), HTTP-клиент, журнал сессий, память последней модели | корень процесса, как сейчас |

- **Порт.** `ProjectConfigLoader { Future<ConfigLoadResult> loadForProject(String canonicalCwd); }` в `AgentCoreServices` (поле `projectConfig`). Реализует его `FileConfigSource` (`codelab_agent_io`). Если порт передан, `buildAgentCore` требует `modelsFor` (`HostWiringException`): без него функцию модели сессии не построить. Сейчас `buildAgentCore` передаёт рантайму `modelsFor` только при `services.config` (`modelsFor: services.config == null ? null : modelsFor`); условие расширяется на `services.projectConfig`, то же — в `createEmbeddedAgent` (`services.configSource == null ? null : modelsFor`). Порт отдельный от `ConfigSource`: у хоста может быть одно без другого.
- **Когда читается.** На каждый вызов `AgentRuntime.createSession` и `AgentRuntime.loadSession` сессии вне корня процесса, без кэша (Q12): правка проекта применяется к следующей сессии этой папки. `session/load` уже открытой в соединении сессии рантайм не вызывает (`AcpAgentServer` переиспользует живой мост и меняет только MCP-серверы клиента), поэтому её конфигурация не перечитывается — это и есть «без живой перезагрузки». Порядок: канонизация `cwd`, затем `loadForProject`, затем проверка снимка (`validateSnapshot`), затем `modelsFor`, затем выбор модели сессии (`selectSessionModel`, с памятью последней модели процесса), затем файлы проекта и MCP. Сессия в корне процесса получает применённый снимок и функцию модели процесса, как сейчас.
- **Журнал — после конфигурации.** Сейчас `createSession` вызывает `_store.create(header)` до `_sessionConfig`, а у `SessionStore` нет удаления. Чтобы отказ по конфигурации не оставлял журнал (сессия появилась бы в `session/list`), шаги D21 идут до `_store.create`; id сессии генерируется раньше (`newSessionId`), он нужен логам. `loadSession` журнал до конфигурации только открывает (`_store.open`), записи `model_change` и `codelab.cwd_changed` пишутся после неё — отказ журнал не меняет.
- **Что сессия держит сама.** Сейчас `_Session` читает конфигурацию, каталог и функцию модели из применённого снимка процесса замыканиями `settingsOf: () => _applied.config.forSessionCwd(...)`, `catalogOf: () => _applied.catalog`, `streamOf: () => _applied.stream`, а `replaceMcp` — тоже `_applied.config.forSessionCwd(...)`. У сессии другой папки эти четыре источника — её собственная тройка «`CoreConfig`, каталог, функция модели», построенная при открытии. Те же значения получают выбор модели (`_selectModel`, `_resolve`, модель журнала в `loadSession`, `_agentBaseOf`) и разбор определений агентов (`_open(catalog:)`) вместо `start.catalog`.
- **Перезагрузка корня и сессии других папок.** `_notifySessions` (закрепление модели `_afterCatalogReplaced`, событие `ModelOptionsChanged`) и шаг 7а (`_applyConfigMcp`) перезагрузки корня пропускают сессии другой папки: их снимок не меняется до следующего открытия (Q12, Q19 (a)). Сессии в корне и сессии хоста без порта (`withoutProject`) ведут себя как сейчас.
- **Модель сессии.** Каталог, `configOptions` `model` и смена модели (`session/set_config_option`) — по каталогу сессии. `AgentSession` получает геттер `ModelCatalog get models` — каталог этой сессии; ACP-сервер берёт из него варианты `model` и проверку `set_config_option` (сейчас `_server._runtime.models`, `agent_server.dart`, `_wire` и `_setConfigOption`). Провайдер «This project only» проекта `B` работает в сессиях `B` без перезапуска. Модель из памяти последней модели, которой нет в каталоге сессии, выбирается по существующему правилу (`DefaultModelSource`).
- **Ключи процесса из проекта сессии** (строка «Процесс» таблицы) не применяются. Сравниваются только ключи процесса, которые есть в `ConfigLoadResult.values` загрузки папки и отличаются от `values` применённого снимка (по разделам таблицы); ключ, который задаёт только корень (например, `logging.level` в `config.local.yaml` корня), а папка не задаёт, предупреждения не даёт — папка ничего не задавала. Ложное срабатывание возможно, если глобальный файл правили после старта без применённой перезагрузки: `values` папки тогда новее применённого снимка; это допустимо, значения в лог не попадают. По одному разу на папку пишется предупреждение `config.session.process_keys_ignored {session_id, keys}` — только ключи показа, без значений. Из проектных слоёв такие ключи может дать только доверенный `config.local.yaml`: `secrets` и `trusted_projects` отбрасывает доверие всегда, `sessions`, `logging`, `exec`, `config` — у `config.yaml` всегда (`applyProjectTrust`).
- **Предупреждения загрузки папки** (`config.project.untrusted_key`, `config.provider.key_unbound`, `config.provider.key_missing`) пишет реализация порта той же функцией `logConfigWarnings`, что пишет предупреждения стартовой загрузки (`codelab_agent_io`): формат один, копии в ядре нет. Пишутся на каждую загрузку.
- **Те же параметры загрузки, что у корня.** `loadForProject` вызывает тот же `ConfigLoader` с окружением, флагами, предконфигурацией, `--config`, известными переменными и закреплённым доверием (`initial.config.trustedProjects`), меняется только `cwd`. Относительный `--config` / `CODELAB_CONFIG` загрузчик сейчас разрешает от `cwd` (`'$root/$extraPath'`), поэтому `FileConfigSource` один раз делает его абсолютным от корня процесса: иначе сессия `/B` читала бы другой файл. `loadForProject` не сдвигает базу наблюдателя (`rebase` не вызывается).
- **Секреты** разрешает общий `SecretResolver` процесса при запросе, как сейчас. Ссылки проектного провайдера проходят правило D23.
- **Отмена и гонки.** Загрузка и сборка идут внутри `session/new` / `session/load`. `_shutdown` рантайма прерывает ожидание, и сессия не создаётся. Параллельные `session/new` одной папки независимы (кэша нет). Перезагрузка конфигурации корня (`reloadConfig`) не меняет функцию модели сессий других папок: у каждой своя, построенная при открытии. Функция модели сессии живёт, пока жива сессия; ресурсов сверх общего HTTP-клиента она не держит.
- **Ошибка конфигурации папки** (синтаксис, схема, `validateSnapshot`, исключение `modelsFor`) — fail closed: `ProjectConfigException {cwd, issues}`. ACP-сервер отвечает `-32603` с `data.codelab.reason: "projectConfigInvalid"`. Соглашение существующее: `AcpRequestError` (`codelab_agent_acp/lib/src/connection/acp_error.dart`) своих кодов не вводит, причину уточняет `data.codelab.reason` (`sessionBusy`, `turnActive` у `-32602`; `data.codelab` у `-32603` итога хода). `data` в схеме ACP — произвольное значение реализации (`17-Schema.md`, `Error.data`), поэтому полей ACP это не добавляет. Ловить исключение нужно явно в `_sessionNew` / `_sessionLoad`: общий обработчик маршрутизатора отвечает `-32603` `Internal error` без `data`. Именованного конструктора `-32603` у `AcpRequestError` нет, используется общий с `jsonRpcInternalErrorCode`. `message` — одна строка: все проблемы через `; ` в форме `<source>:<line>:<column>: <key>: <message>`, без значений секретов и без новых полей в `data` (Q20 (a); схема ACP: `message` SHOULD быть одной фразой). Сессия без своего проекта и его запретов не создаётся (§2, приоритет 1). Методов и полей ACP не добавляется.
- **Лог.** `config.session.outside_root` заменяется на `config.session.project {session_id, cwd, config_root, trusted}` уровня `info`, по одному на папку (как сейчас `_outsideRootLogged`). Отказ пишется `config.session.project_invalid {cwd, issues}` уровня `error`; `issues` — в той же форме, что у `config.reload.failed` (`source`, `line`, `column`, `key`, `kind`), без текстов и значений (§16).
- **Подкаталог** `/A/sub` — своя папка со своими слоями, как и сейчас: сравнивается равенство, а не вложенность.
- **Без порта** (сторонние хосты, сценарный открыватель, `serve --llm-script`, `serve --ws` — Q18 (a)) — прежнее поведение `withoutProject`.
- **Сторонний stdio-агент** сам отвечает за свои проектные настройки: клиент передаёт `cwd` сессии, перезапуска нет.
- **Живая перезагрузка** проектных слоёв папок, отличных от корня процесса, у уже открытых сессий отложена до выхода 1.0 (Q12). Наблюдатель следит только за файлами корня процесса.

Отклонено: только ключи сессии без провайдеров (прежняя редакция D21) — провайдер проекта работал бы только после перезапуска (решение пользователя по Q11). Отклонено: кэш конфигурации по папке — без наблюдателя всех папок он устаревает, а чтение двух YAML на открытие сессии дёшево.

#### D23. Ключ проектного провайдера привязан к адресу (приоритет 1)

**Угроза.** Проектные слои — файлы в рабочей папке. `config.yaml` обычно лежит в репозитории, и его пишет не пользователь. Провайдер из проектного слоя мог бы сослаться на секрет процесса (`api_key_secret: codelab/anthropic`, `${secret:…}` в `headers`) или на переменную с ключом (`api_key_env: ANTHROPIC_API_KEY`) и указать свой `base_url`. Тогда ключ пользователя ушёл бы на чужой адрес. Сейчас это закрывает только доверие (`trusted_projects`). Но доверие к проекту означает «разрешить его правила и серверы», а не «отдать ему мои ключи». С провайдерами на сессию риск касается любой открытой папки, а не одного корня.

**Правило.** Применяется в ядре при разрешении конфигурации, одинаково для корня процесса и для папки сессии:
1. **Доверие.** Без доверия `providers.*` проектных слоёв отбрасываются, как сейчас (§15.3).
2. **Группа адреса и аутентификации целиком из одного слоя.** Группа — это `kind`, `base_url`, `headers`, `api_key`, `api_key_env`, `api_key_secret`, `auth_header`. Если проектный слой меняет любое поле группы провайдера, заданного ниже, группа берётся из проектного слоя целиком: ключ нижнего слоя к новому адресу не наследуется. Так же уже работает слой флагов для `providers.cli` (`mergeLayers`, spec agent-binary). `api_key` и `auth_header` входят в группу потому, что `api_key` — тоже источник ключа (литерал, `${ENV}` или `${secret:…}`, R8-8 `_Builder._provider`): без него литеральный `api_key` пользователя ушёл бы на `base_url` проекта. Если поля группы задают несколько слоёв (`config.yaml` и `config.local.yaml`; проектный и глобальный выше него) и среди них есть проектный, группа целиком берётся из верхнего слоя, который задаёт хоть одно её поле (Q17 (a); обобщение правила `providers.cli`). Ключ из `config.local.yaml` поэтому не уйдёт на `base_url`, который позже поменяет `git pull` в `config.yaml`; мастер «This project only» пишет провайдера целиком.

   **Поля, которые верхний слой не задаёт** (уточнение при реализации, 2026-11-12; подтверждено пользователем, Q21 (a)). Пусть `T` — верхний слой, задающий хоть одно поле группы. Поля аутентификации (`headers`, `api_key`, `api_key_env`, `api_key_secret`, `auth_header`) берутся ровно из `T`: чего `T` не задал, того нет. Поля адреса (`kind`, `base_url`), которых `T` не задал, берутся из слияния **непроектных** слоёв ниже `T` (умолчания, `user`, `appStorage`, а для `T` выше проекта — и глобальные слои между ними). Почему так:
   - буквальное «группа целиком из `T`» ломает загрузку обычного конфига: проект, переопределивший только ключ (`api_key_secret`) или только `base_url` провайдера пользователя, дал бы `kind: required` / `base_url: required for openai-compatible providers`, и не стартовал бы даже корень. Цена D23 (Q14) такого не объявляла;
   - адрес из **проектного** слоя ниже `T` не наследуется: иначе ключ из `config.local.yaml` ушёл бы на `base_url` закоммиченного `config.yaml` — ровно то, что закрывает Q17 (a);
   - ссылки на ключ судятся правилом 3 по origin итогового адреса, поэтому унаследованный адрес пользователя не даёт проекту отправить на него чужой секрет без условия (a) или (b).

   Следствие для R8-6: поля аутентификации слоёв ниже проектного к нему не наследуются, поэтому пары «литерал `api_key` в `user` + `api_key_secret` в `project`» больше нет. Конфликт источников остаётся между глобальными слоями (`user` и `--config`/`CODELAB_CONFIG`) и внутри одного слоя (spec agent-configuration «Секреты только ссылками», MODIFIED).
3. **Ссылки на ключ из проектного слоя привязаны к origin.** Ссылки на ключ в группе из проектного слоя — `api_key_secret`, `api_key_env`, `${secret:…}` и `${ENV}` в `headers` и `api_key` — разрешаются, только если выполнено одно из двух условий:
   - **(a)** ссылка задана в `config.local.yaml` (слой `projectLocal`: локальный файл пользователя, его пишет мастер «This project only», он не коммитится), а проект доверенный;
   - **(b)** глобальные слои (`user`, `appStorage`, `--config`, окружение, флаги) связывают ту же ссылку с тем же origin (`scheme://host:port`) `base_url`. «Та же ссылка» — тот же вид (секрет или переменная) и то же имя, в каком бы поле группы она ни стояла: адрес назначения тот же, утечки нет. Origin сравнивается по `scheme`, `host` (без учёта регистра) и `port` (порт по умолчанию схемы подставляется), `base_url` по умолчанию для `kind` (`anthropic`, `gemini`) учитывается.

   `${ENV}` в `base_url` группы из проектного слоя — тоже ссылка правила 3 (Q16 (a)): значение переменной иначе ушло бы в URL. В `config.yaml` без условия (a) или (b) переменная не раскрывается, провайдер остаётся в каталоге с ошибкой правила 3, `config.provider.key_unbound {reference_kind: env}`.

   Иначе провайдер остаётся в каталоге, но ключ не разрешается. Ход с его моделью завершается ошибкой провайдера `Provider <id> from <file> cannot use <reference>: the key is bound to another address. Move the provider to config.local.yaml or to the user config.` без HTTP-запроса. При загрузке пишется предупреждение `config.provider.key_unbound {provider, source, reference_kind}`: имя ссылки — без значения, адрес — только origin.
4. Значение секрета никогда не попадает в лог, ошибку, `configOptions` и диагностику. Маркер утечки в тестах — `sk-test-leak-0123456789`.

**Где проверяется (сверено с кодом).** Одно место — сборка провайдера в `_Builder._provider` (`codelab_agent_core/lib/src/config/resolve.dart`) и шаг до слияния для правила 2 (рядом с правилом `providers.cli` в `mergeLayers` или с `_applyTrust`). Происхождение поля по слоям уже есть: `_Builder._origin(segments)` возвращает слой (`ConfigTree.kind`, `source`), задавший итоговое значение. Проверка должна стоять до `_interpolate` заголовков и `api_key` (`${ENV}` раскрывается при загрузке, значение переменной попадает в `ProviderConfig.headers` / `apiKey`) и до проверки `environment[api_key_env]` (`config.provider.key_missing`). Непривязанный провайдер получает вместо ссылки запись в `CoreConfig.providerProblems` с текстом правила 3; `createRoutedStreamFunction` по `unavailable` уже отвечает ошибкой класса `auth` без HTTP-запроса и без обращения к `SecretResolver`, а `implicitDefaultModel` такой провайдер не выбирает. Отдельной проверки в функции модели не нужно. Для условия (b) нужны ссылки глобальных слоёв в исходном виде: в собранном снимке `${ENV}` заголовков уже раскрыт, поэтому ссылки собираются из деревьев слоёв `user`, `appStorage`, `extra`, `environment`, `flags`.

**Цена.** Существующий доверенный проект, чей закоммиченный `config.yaml` задаёт провайдера со своим `base_url` и глобальным ключом, перестанет получать ключ. Пользователь переносит провайдера в `config.local.yaml` или в `user`; подсказка в тексте ошибки. Решено: Q14 (a).

- Отклонено: только доверие (сегодняшнее поведение). Доверие не означает согласия отдать ключи, а с провайдерами на сессию поверхность атаки растёт.
- Отклонено: отдельное пространство имён секретов на проект (`projects/<hash>/…`). Это меняет хранилище, мастер и CLI ради того же результата, который даёт привязка к origin.

#### D25. R8-6 и отказ R8-10 после правила группы D23

**Что изменилось.** R8-6 (change `add-config-literal-secrets-and-migrate`) — проблема загрузки, если у провайдера после слияния слоёв два источника ключа (литеральный `api_key` и `api_key_env`/`api_key_secret`). На нём держится отказ R8-10 `secret migrate`: если перенос выбранных слоёв оставил бы литерал в невыбранном слое рядом с новой ссылкой, команда отказывает кодом `1` до записи и до хранилища (`secret_migrator.dart`). По правилу 2 D23 проектный слой не наследует поля аутентификации слоёв ниже. Поэтому пара «литерал в `user` + ссылка в `project`/`local`» (и наоборот, и `project` + `local`) двух источников больше не даёт. Ветка отказа `… (<layer> keeps its own); run with --all` для файловых слоёв `migrate` становится недостижимой. Ветка `… (CODELAB_CONFIG keeps its own); remove the key from CODELAB_CONFIG` достижима по-прежнему: `CODELAB_CONFIG`/`--config` — глобальный слой, `migrate` его не правит, и R8-6 с `user` у него остаётся.

**Решение — следствие D23, отдельного выбора не требует:**
- R8-6 остаётся правилом слитого дерева, а слитое дерево теперь учитывает правило группы. Конфликт — только между глобальными слоями (`user`, `appStorage`, `--config`/`CODELAB_CONFIG`, окружение) или внутри одного слоя.
- Код R8-10 и R8-11 не меняется. Проверка итога слияния всех слоёв остаётся общей и защищает от любого конфликта, который даст итог, в том числе с `CODELAB_CONFIG`. Ветку с текстом `run with --all` не удаляем: она — та же общая проверка, выбор текста по слою, а не отдельный механизм (§13: не плодим особый случай ради удаления).
- Наблюдаемое изменение `secret migrate` (только `user`) при литерале в проекте: раньше код `1` с `run with --all`, теперь код `0`. Пользовательский слой переносится, проектный литерал остаётся ключом сессий проекта, `config.secret.in_file` для него не пропадает. Это прямое следствие Q14/Q17: итог больше не противоречив, отказывать не в чем. «Move secrets» desktop и «This project only» вызывают тот же движок и наследуют то же.
- Тесты, державшиеся на паре `user`/`project`, переписываются на эквивалент, а не пропускаются (задача C2.8): отказ R8-10 — на `CODELAB_CONFIG`, межфайловый `pending` писателя — на другой межслойной зависимости.

- Отклонено: убрать R8-10 целиком — остаётся достижимый случай `CODELAB_CONFIG`, и спецификация его называет.
- Отклонено: вернуть межслойный R8-6 для `user`/`project` поверх D23 — противоречит правилу 2: литерал пользователя к группе проекта не относится.

#### D26. `secret migrate` переносит провайдера закоммиченного конфига в `config.local.yaml` (решение пользователя по ревью безопасности итерации C)

**Пробел.** Сейчас `secret migrate --project`, `--all` и «Move secrets» превращают литерал ключа провайдера в `.codelab/config.yaml` в ссылку `api_key_secret` **в том же файле** (`_Unit.edits`, `_UnitKind.providerKey` в `secret_migrator.dart`). По правилу 3 D23 ссылка из `config.yaml` не привязана: провайдер проекта после переноса перестаёт работать (`key_unbound`), а команда возвращает код `0`.

**Решение.** Для провайдера `providers.<id>` из `config.yaml` доверенного проекта, у которого есть находка в поле группы D23 (литерал в `api_key`, `api_key_env`, `api_key_secret`, `headers`), мигратор переносит **все поля группы, которые задаёт `config.yaml`** (`kind`, `base_url`, `headers`, `api_key`, `api_key_env`, `api_key_secret`, `auth_header`), в `config.local.yaml` того же проекта. Литерал при переносе становится ссылкой на секрет, как раньше: `api_key` → `api_key_secret`, заголовок → `${secret:…}`. Поля вне группы (`models`, сроки, повторы, `reasoning_format`) остаются в `config.yaml`: это общая для команды часть, к ключу она не относится. Провайдер продолжает работать: `config.local.yaml` — верхний слой группы (Q17 (a)), его ссылка разрешается по условию (a) правила 3. Секрет уходит из репозитория. Это совпадает с подсказкой текста ошибки D23 (`Move the provider to config.local.yaml…`).

**Детали (технические, сверены с мигратором и писателем):**
- **Провайдер без своего `base_url`.** Если `config.yaml` переопределяет только ключ провайдера пользователя, переносится только то, что он задаёт. Адрес группы в `config.local.yaml` тогда наследуется из непроектных слоёв (Q21 (a)), и провайдер работает с адресом пользователя и ключом проекта.
- **Выбор слоёв.** Перенос — часть обработки находок слоя `project`. Поэтому `--project` (и `--all`, «Move secrets») пишет и `config.local.yaml`, даже без `--local`; строка вывода называет оба файла. `--local` один `config.yaml` не трогает. Доверие писателя проверяется для обоих файлов до хранилища.
- **Порядок записи.** Секреты всех файлов сохраняются до первой записи конфига, как сейчас (L7). Файлы пишутся в порядке `user`, `local`, `project`: `config.local.yaml` с группой и ссылкой — раньше, чем группа удаляется из `config.yaml`. Сбой между двумя записями оставляет рабочий конфиг: `config.local.yaml` — верхний слой группы, литерал в `config.yaml` не используется, но остаётся в файле. Код `1`, stderr называет сохранённые секреты и оставшийся файл. Обратный порядок оставил бы провайдера без адреса и ключа. Итог обоих файлов проверяется вместе (`pending`) до хранилища (R8-10), откат не нужен: каждая запись атомарна, а промежуточное состояние рабочее.
- **Повтор после сбоя (R8-11).** Если `config.local.yaml` уже задаёт поля группы провайдера и они совпадают с тем, что записал бы перенос (те же поля и значения, ссылка — на секрет с тем же значением, `Reused secret`), перенос завершается: из `config.yaml` удаляются поля группы, `config.local.yaml` не меняется.
- **Чужие ссылки группы не переносятся (решение пользователя по повторному ревью, приоритет 1).** Перенос в `config.local.yaml` снимает с ссылок проверку origin (условие (a) правила 3 D23). Поэтому перед планированием мигратор проверяет каждую ссылку группы провайдера в `config.yaml`, которую он **не создаёт сам из литерала**: `api_key_secret`, `api_key_env`, `${secret:…}` и `${ENV}` в `headers` и `api_key`, `${ENV}` в `base_url`. Ссылка допустима, только если её привязывают глобальные слои по условию (b) — та же ссылка, тот же origin итогового адреса (`ProviderKeyBinding` по непроектным слоям, C5.1). Если хоть одна ссылка не привязана, перенос этого провайдера отменяется: строка `not migrated: providers.<id> in <path>: <reference> is not bound to this address by the user config; move it by hand` (`<reference>` — вид и имя ссылки, `secret codelab/anthropic` или `variable ANTHROPIC_API_KEY`, без значения). Файлы этого провайдера и хранилище не меняются, литерал-находка остаётся в `config.yaml`, провайдер по-прежнему заблокирован D23 (`key_unbound`). Остальные находки переносятся, код — по общим правилам, как у строк `not migrated`. Пример атаки, которую это закрывает: литерал-приманка в заголовке, `api_key_secret: codelab/anthropic` и `base_url: https://evil.example` в `config.yaml`; «Move secrets» иначе перенёс бы всё в `config.local.yaml`, и ключ пользователя ушёл бы на `evil.example`.
- **В `config.local.yaml` уже есть этот провайдер с другой группой.** Группы не сливаются молча. Провайдер не переносится, строка `not migrated: providers.<id> in <config.yaml>: config.local.yaml already defines its address or key; move it by hand`, оба файла этого провайдера не меняются, значение в хранилище не попадает. Это та же форма отказа по провайдеру, что у недоверенного проекта: остальные находки переносятся, код по общим правилам. Для сессий проекта литерал `config.yaml` и так не действует: группа берётся из `config.local.yaml`.
- **Недоверенный проект** — как сейчас: `not migrated: <path> is an untrusted project config`, значения в хранилище не попадают, ни один файл проекта не пишется.
- **`--dry-run`** показывает тот же план, что запуск (строки ниже), без хранилища и записи; отказ R8-10 и строки `not migrated` — те же.
- **Вывод.** Для каждой находки перенесённого провайдера — `Moved <key> in <config.yaml> to secret <name>` (или `Reused secret …`); затем одна строка на провайдера: `Moved providers.<id> (address and key) from <config.yaml> to <config.local.yaml>`. Значений в выводе нет (CFG-2).
- **MCP-серверы** закоммиченного `config.yaml` переносятся в том же файле, как сейчас: D23 для `mcp.servers` — отдельный change (Q15 (a)).
- **`.gitignore`** мигратор не меняет. Закоммиченный `config.local.yaml` — остаточный риск (Risks).

- Отклонено: оставлять ссылку в `config.yaml` (сейчас) — провайдер ломается молча, код `0`.
- Отклонено: перенести провайдера без чужих ссылок (удалить непривязанные ссылки из переносимой группы). Получится провайдер с адресом репозитория и без части аутентификации, собранный мигратором молча; пользователь не видит, что адрес и ссылки писал репозиторий. Решение пользователя — не переносить и сказать об этом.
- Отклонено: отказ кодом `1` для провайдеров `config.yaml` — секрет остаётся в репозитории, а пользователь получает работу руками, которую команда может сделать сама.

### Затронутые пакеты и зависимости

- `codelab_agent_core` (агент, слой `core`): порт `ProjectConfigLoader` и поле `AgentCoreServices.projectConfig`, `ProjectConfigException`, `AgentSession.models`, `AgentRuntime._sessionConfig` и тройка «конфигурация, каталог, функция модели» сессии, пропуск сессий других папок в `_notifySessions` и шаге 7а, правило D23 в `resolve.dart`, события. Новые публичные символы — в барель и `test/public_api_test.dart`. Allowlist зависимостей ядра (PKG-2) не меняется: новых пакетов нет, IO остаётся в порте. Узкий публичный экспорт из `provider_binding.dart` через `show`: `ProviderKeyBinding`, `ProviderReference`, `ProviderReferenceKind`, `providerOrigin`, `providerReferences`, `referencesIn` — одна копия правила D23 для мигратора (D26, C5.6), без второй реализации в `codelab_agent_io`. `applyProviderGroupRule` и `providerEntry` остаются внутренними; это проверяет `test/public_api_test.dart`.
- `codelab_agent_io`: `FileConfigSource implements ProjectConfigLoader`; мигратор `secret migrate` по D26 и C5.6 (`secret_migrator.dart`) и новый вариант отчёта `SecretProviderMovedItem`, который экспортируется также из `codelab_setup/io.dart` и `codelab_embedded/io.dart`; `http` в `dev_dependencies` — `MockClient` для теста «0 HTTP-запросов» (C5.6). Allowlist ядра (PKG-2) это не затрагивает: зависимость тестовая и в другом пакете.
- `codelab_agent_acp`: ответ `-32603` с `reason: projectConfigInvalid` на `ProjectConfigException`; каталог моста `SessionBridge` и проверка `set_config_option` — по `AgentSession.models` (`agent_server.dart`); фейк `AgentSession` в `test/session_bridge_echo_test.dart` получает геттер.
- `codelab_embedded`: поле `EmbeddedHostServices.projectConfig` (`embedded_agent_config.dart`, публичный API основного бареля — тип ядра, web-безопасно), передача в `AgentCoreServices` (`assemble.dart`), `modelsFor` при порте (`create_embedded_agent.dart`), открыватель передаёт `FileConfigSource` (`lib/src/io/local_opener.dart`). Сценарный открыватель (`lib/src/testing/scripted_opener.dart`) порт не передаёт.
- `apps/codelab_agent`: `AgentHost` (`lib/src/host/agent_host.dart`) передаёт `serveConfigSource` (`lib/src/host/serve_config.dart`) как порт только при `--stdio` и без `--llm-script`. `serve --ws` порт не получает и сохраняет `withoutProject` (Q18 (a)): по WebSocket `cwd` называет клиент, файлы идут через его ФС, а файлы проекта бинарь по WebSocket тоже не читает (D2 change `add-agent-project-files`).
- Документы ядра (правило «сначала документ» `codelab_agent_core/AGENTS.md`): `docs/architecture/proposals/agent-core/10-core-assembly-and-profiles.md` (абзац «Снимка на каждый `cwd` сессии нет…») и `17-5-agent-setup.md` («Один корень на хост», «Снимок — на корень запуска хоста») прямо откладывают чтение конфига чужого `cwd` до отдельного change — это он; `15-configuration.md` §15.2–§15.3 — группа провайдера D23. Правятся задачей C0.1 до кода.
- `codelab_client_core`: `ensureAgent`, `agentDirectory`, `reconnect(agentDirectory:)`, `newSession(activate:)`, `session/list` при `selectProject` с номером запроса, `loadSession` для `detached`. Остаётся web-безопасным. Публичный API расширяется без удаления: код `apps/codelab_cli` не меняется, только `fvm dart analyze`; наблюдаемое изменение CLI — снятие одобрений, следующий пункт.
- `codelab_client_acp` (клиент, слой `acp`; дефекты найдены в итерации B, задачи B1.4, B1.5 и B1.6): метод `AcpClientApplication._dropPendingApprovals`. При замене транспорта (`replaceTransport`, то есть kit `reconnect` — в desktop «Restart agent» и «Reconnect», D22) и при потере соединения (`AcpTransportFailure` при `wasReady` или `wasInitializing`) каждое ждущее одобрение каждой сессии переходит в `cancelled` через `SessionStateMachine.cancelApproval`, и ход выходит из `awaitingApproval`. В диагностику пишется предупреждение `Pending permission request dropped: <reason>` с id сессии, одобрения и tool call, без `rawInput` (§16). Поздний `respondToPermission` по снятому id бросает `StateTransitionException` и ничего не отправляет. Очередь промптов не трогается, ход пересобирает следующий `session/load`.
  - **Зачем.** Раньше ждущее одобрение `detached`-сессии (агент без `loadSession` или ошибка загрузки) висело без адресата, а ответ на него ушёл бы в соединение, где этого запроса нет. Это расходилось с D22 («Ждущие одобрения снимаются, очередь сохраняется») и с требованием agent-workbench-ui «Workbench честно отражает спонтанную потерю соединения» (при `lost` очищается `pendingApproval`): desktop выполнял их только отображением, а состояние kit оставалось ждущим. Требование kit — acp-client-kit MODIFIED «Одобрения привязаны к вызову».
  - **Порядок при замене (B1.5).** Одобрения и карты запросов снимаются синхронно сразу после `_generation++`, до первого `await` в `_replaceTransport`. `_sendPermissionResponse` меняет `_handledPermissionRequests` только при неизменном поколении. Иначе ответ, отправленный во время замены, записал бы старый id в набор нового соединения, и запрос нового соединения с тем же JSON-RPC id был бы проглочен (id JSON-RPC уникальны только в пределах соединения).
  - **Ранняя метка прерванного хода (B1.6).** Встроенный агент выгружается внутри фабрики транспорта (`EmbeddedTransportResolver._openSerialized`, `await previous?.dispose()`) ещё до `_replaceTransport` и сам завершает идущий ход `cancelled`; реплей `session/load` не несёт `stopReason`, и без метки ход показывался «Completed with stopReason unknown.» вместо отменённого (D22; `acp-protocol-client` «Ход, прерванный заменой транспорта»). Поэтому `AcpClientApplication.reconnect` помечает идущие ходы синхронно до `createTransport()`. Метку снимает только ответ хода со `stopReason`, отличным от `cancelled` (ход честно закончен); ошибка хода в этом окне считается прерыванием. При сбое фабрики метка снимается лишь у сессий, чей ход ещё идёт. ACP и публичный API не меняются.
  - **ACP** не меняется: ни методов, ни полей, ни кадров. На запрос оборванного соединения ответа нет, потому что адресата нет. Публичный API пакета не меняется.
  - **Что меняется в CLI** (пакет общий, код CLI не меняется). REPL и TUI после `/reconnect` или падения агента больше не показывают запрос одобрения, на который некому ответить, и клавиша выбора ничего не отправляет. Если ответ совпал с заменой транспорта, CLI печатает существующую строку `codelab: cannot answer the permission request: …` вместо молчаливой отправки в старое соединение. Headless `-p` отвечает политикой `--approve` сразу, поэтому для него меняется только та же гонка с потерей соединения: строка в stderr. Очередь промптов в CLI сохраняется, как и в desktop.
- `apps/codelab_desktop`: части A и B.
- `codelab_ui`: организм `CodeLabStartScreen` без логики; параметр подписи кнопки повтора у `CodeLabConnectionBanner` и `CodeLabConnectionScreen` (D18).
- Направление зависимостей не меняется. Новых зависимостей и правил сторожа в `codelab_architecture_tests/test/support/rules.dart` нет. Граф в `README.md` не меняется.
- Проверки: `web-compile` (kit, `codelab_embedded`), `conformance:agent` и `conformance:client` (в том числе для `codelab_client_acp`), `test:e2e:cli:dart-agent` (CLI и бинарь используют изменённые ядро и kit).

## Risks / Trade-offs

- **Утечка ключа (§2, §10).** Провайдеры на сессию расширяют поверхность: правило D23 (группа целиком, привязка к origin), тесты с маркером `sk-test-leak-0123456789`. `HostSettings` и хранилище секретов остаются ключами процесса.
- **Закоммиченный `config.local.yaml` (остаточный риск, принят в Q17).** Правило 3 D23 разрешает ссылки из `config.local.yaml` доверенного проекта без привязки к origin: файл считается локальным файлом пользователя. Если проект по ошибке или злому умыслу коммитит `config.local.yaml`, D23 его не судит — защита держится на доверии к проекту (`trusted_projects`) и на том, что файл обычно в `.gitignore`. Мигратор (D26) `.gitignore` не меняет.
- **Совместимость D23** (Q14): доверенные проекты с провайдером в закоммиченном `config.yaml` и глобальным ключом теряют ключ.
- **Живая перезагрузка** отложена до 1.0 (Q12, решено). Правка `.codelab/` папки применяется к её следующему `session/new` или `session/load`.
- **Гонки и поздние события (§9, §12):** single-flight `ensureAgent`, номер намерения фокуса, номер запроса списка, поколение соединения при перезапуске (D17, D22); ждущие одобрения снимаются синхронно до первого `await` замены, ответ меняет набор обработанных запросов только при неизменном поколении (`codelab_client_acp`, B1.5).
- **Переход A → B → A во время старта.** Агент стартует один раз с корнем первого триггера (`A`), список запрашивается для проекта на момент ответа (`A`), поздний список `B` отбрасывается. Восстановление снимка `A` отменяется уже первым переходом в `B` и при возврате в `A` не возобновляется: так работает правило kit «выбор другого проекта отменяет восстановление» (`WorkspaceRestorer.observe`). Сессии снимка тогда видны, только если их вернёт `session/list` проекта, и открываются кликом. Это принятое поведение kit, B его не меняет.
- **Синхронное чтение конфига папки (§12).** `ConfigLoader.load` синхронный; `FileConfigSource.load` уже выполняет его в isolate ядра, а встроенный агент живёт в UI-isolate (`InProcessAcpLink`, spec embedded-agent «Нагрузка встроенного агента на UI-isolate»). D21 добавляет это чтение (два YAML до 1 МиБ) на каждый `session/new` / `session/load` другой папки. Для обычных размеров это дёшево; если замер покажет заметную задержку, чтение СЛЕДУЕТ перенести в `Isolate.run` внутри реализации порта, как разбор журнала.
- **Перезагрузка корня и сессии других папок** (Q19 (a), принято). Сейчас сессия вне корня получает `withoutProject` из применённого снимка, и правка глобальных слоёв (модели, бюджет, выключение MCP-сервера) доходит до неё со следующего шага. С портом её снимок фиксируется при открытии: такие правки доходят только до следующего открытия. Права (`permissions.*`) и сейчас ждут перезапуска (R0-1), поэтому запреты это не ослабляет.
- **Permissions (§10):** запреты проекта теперь применяются к сессии любой папки (D21). Конфиг с ошибкой — отказ сессии, а не тихий снимок без проекта. Перезапуск снимает ждущие одобрения только после подтверждения.
- **ACP и совместимость вперёд:** сообщения не меняются. Ошибка `session/new` — существующая ошибка JSON-RPC.
- **CLI:** вызывает `connect` и `newSession` как раньше. Он тоже получает D21: сессии `--cwd` и так в корне процесса. Из kit CLI получает снятие ждущих одобрений при `/reconnect` и потере соединения (`codelab_client_acp`, «Затронутые пакеты»).
- **Повторы после сбоя** (D13, Q13 решено): любой триггер повторяет старт, но без автоповторов. Single-flight и схлопывание одинаковых ошибок защищают от петли и спама.
- **Устаревшая подпись в соседнем требовании.** Требование app-settings «Диалог «Add connection profile»» упоминает «Connect» в строке сохранённого профиля (правило подтверждения `ws://`). После этого change там «Use», который не подключает: правило выполняется тривиально, а текст поправят при архивировании этого change. Полную копию большого требования ради одного слова в дельту не вносим.
- **Временное D7.** «Test connection» будет удалена отдельным change. До него проверка stdio без проекта наследует папку процесса CodeLab — это осознанное исключение для `initialize` без сессии (D7).
- **Корень диска по клику.** Сессия в `/` открывается только после подтверждения D24; без него — даже по клику.
- **Объём.** Change большой, поэтому задачи разбиты на итерации: A (только desktop, закрывает дефект, выходит отдельно), C (агент, независима от B, выходит отдельно), B (клиент и desktop, опирается на C, иначе сессии чужих папок без запретов своего проекта).

## Отложено отдельными changes

- **Удаление «Test connection»** (решение пользователя): отдельный change после этого — уходят кнопки в строке профиля и в диалоге «Add connection profile» и, при отсутствии других пользователей, `ProfileProbe` в UI. До него действует временное D7.

## Открытые вопросы

Решены:
- Q1 (b), Q2/Q3 (модель OpenCode), Q4, Q5 (a), Q6 (a), Q7 (a), Q8 (b), Q9 (a), Q10 (a);
- Q11 — провайдеры на сессию (D21);
- Q12 — следующая сессия папки, живая перезагрузка после 1.0;
- Q13 — любой триггер повторяет старт с защитой от петли (D13);
- Q14 (a) — правило D23 для корня процесса и для папок сессий; провайдер с чужим адресом переносится в `config.local.yaml` или `user`;
- Q15 (a) — D23 для `mcp.servers` проектных слоёв отдельным change после этого.

- Q16 (a) — `${ENV}` в `base_url` группы из проектного слоя подчиняется правилу 3 D23: раскрывается только в `config.local.yaml` доверенного проекта (или при привязке глобальными слоями к тому же origin), иначе `key_unbound` без HTTP;
- Q17 (a) — если среди слоёв, задающих поля группы «адрес и аутентификация», есть проектный, группа целиком берётся из верхнего слоя, задающего хоть одно её поле;
- Q18 (a) — порт `ProjectConfigLoader` только у встроенного агента и `serve --stdio`; `serve --ws` сохраняет `withoutProject`, как `ProjectFilesLoader` (D2 change `add-agent-project-files`);
- Q19 (a) — снимок сессии другой папки фиксирован до её следующего открытия; перезагрузка корня его не меняет;
- Q20 (a) — `message` ошибки `projectConfigInvalid` — одна строка, все проблемы через `; ` в форме `<source>:<line>:<column>: <key>: <message>`, без новых полей в `data`.

- Q21 (a) — поля аутентификации группы берутся ровно из верхнего слоя, поля адреса, которых он не задал, — из непроектных слоёв ниже него (решение пользователя 2026-11-12, D23);
- D25 принято пользователем 2026-11-12: `secret migrate` одного слоя при своём ключе в другом проектном слое проходит с кодом 0; отказ R8-10 остаётся для конфликта с `CODELAB_CONFIG`.

Решены (сверка итерации B с кодом, 2026-11-12; ответ пользователя — рекомендованные варианты, все записаны как (a)). Дельты по ним внесены задачей B0.0.

- **Q22. Тексты и кнопки «Connect» вне рабочего места.** После B ручного подключения нет, но остаются:
  1. баннер «Providers» после записи без работающего агента — `Saved. Connect to start the agent with the new provider.` с кнопкой «Connect» (`providers-banner-connect`, spec app-settings «Мастер провайдера в app»);
  2. экран «Profile saved» диалога «Add connection profile» — `The current connection is unchanged. Use Connect in the profile row to switch now.`;
  3. подсказка профиля по умолчанию в диалоге — `Used when CodeLab starts and by Connect on start.`;
  4. заметка ленты о потерянном ходе — `Reconnect to continue working with the agent.`;
  5. подпись строки сессии без фокуса — `Create a session after connecting.`.

  Варианты для п. 1: (a) текст `Saved. The agent uses it the next time it starts.` без кнопки, а если последний старт упал — кнопка «Retry» (триггер 4 D13); (b) кнопка «Start agent», которая стартует агента в выбранном проекте (новый триггер, расширяет D13); (c) убрать баннер. Для пп. 2–5 — заменить на тексты без «Connect»: `Select it with Use in the profile row; Restart agent applies it.`, `Used when the agent starts.`, `Retry to continue working with the agent.`, `Open a project to start a session.`. **Решено: (a)** и предложенные тексты — без новых триггеров. Кнопка «Retry» баннера «Providers» — ключ `providers-banner-retry` (spec app-settings «Мастер провайдера в app»). Тексты пп. 2–5 в коде; в спецификации — только п. 2 (spec app-settings «Диалог «Add connection profile»», текст `The running agent is unchanged. Select it with Use in the profile row; Restart agent applies it.`).

- **Q23. Открытые сессии других папок в сайдбаре.** Сейчас все открытые сессии kit показываются под текущим проектом (`sidebarProjectsOf`). После B при переходе из `/work/a` (идёт ход) в `/work/b` сессия `/work/a` окажется под заголовком `b`. Варианты: (a) открытая сессия показывается в группе проекта, чей путь равен её `cwd` (группа недавнего проекта раскрывается со статусом хода), а сессия без такой группы — под текущим проектом с подписью папки; (b) как сейчас — все открытые под текущим; (c) только сессии текущего проекта, остальные видны после выбора их проекта. **Решено: (a)** — spec agent-workbench-ui «Sessions sidebar grouped by project» (MODIFIED): точное равенство пути группы и `cwd`; группа недавнего проекта с открытыми сессиями показывает их со статусом и раскрыта, пока одна из них идёт, ждёт одобрения или упала; строки `session/list` этого проекта появляются только после его выбора.

- **Q24. Пункт палитры `/reconnect`.** D22 называет перезапуск только на странице «Connection» и в диалоге переноса секретов, а палитра (spec agent-workbench-ui «Командная палитра…», сценарий «Выбор /reconnect…») переподключает напрямую. Варианты: (a) `/reconnect` — то же, что «Restart agent», с подтверждением D22 и подписью по типу профиля («Restart agent» / «Reconnect»); (b) убрать пункт из палитры; (c) оставить «Retry» (новый старт) только в `lost`/`failed`, иначе пункт недоступен. **Решено: (a)** — spec agent-workbench-ui «Командная палитра открывается и выполняет доступные действия» (MODIFIED).

- **Q25. Прервать зависший старт.** Дельта app-settings «Блок «Behavior»» делает «Restart agent» недоступной во время подключения, а её же сценарий «Поздняя попытка» перезапускает, пока `slow` подключается. Сейчас зависший старт (встроенный агент долго открывает MCP-серверы, stdio-агент молчит на `initialize`) прерывает повторный Connect (L4 change `add-embedded-agent-mode`). Без Connect и с недоступным перезапуском прервать его нечем, кроме перезапуска app. Варианты: (a) «Restart agent» доступна и во время старта: вытесняет попытку (kit это умеет), диалога D22 нет, ходов ещё нет; (b) недоступна, а сценарий «Поздняя попытка» убрать; (c) отдельная «Cancel» у индикатора `Starting <title>…`. **Решено: (a)** — spec app-settings «Блок «Behavior»…» (доступна во время старта, сценарии «Поздняя попытка», «Зависший старт прерывается перезапуском»), agent-workbench-ui «Тип подключения «Встроенный агент»», acp-client-kit «Агент по требованию хоста» (вытеснение `ensureAgent`).

- **Q26. Фокус на `detached`-сессии у агента без `loadSession`.** Сейчас такая сессия по клику показывается с уведомлением о потере связи. По D13 и дельте «Selecting a not-loaded session…» фокус пытается загрузить её, а при сбое фокус не меняется, — и сессию у такого агента нельзя даже открыть для чтения. Варианты: (a) если работающий агент не объявил `loadSession`, сессия показывается как сейчас, без попытки и без диагностики; если агент не работает — старт по D13, затем то же правило; (b) всегда попытка, при отказе — фокус прежний и диагностика. **Решено: (a)** — spec agent-workbench-ui «Selecting a not-loaded session restores its transcript», исключение и сценарий «Detached session with an agent without loadSession». Признак `loadSession` desktop берёт из `AcpClientApplication.connectionState` (`ClientConnectionReady.capabilities`), kit не меняется.

- **Q27. Корень процесса в корне диска.** По D11/D13 агент стартует в папке триггера, а по D18 «Restart agent» берёт папку сессии в фокусе. Если в фокусе сессия `/`, открытая после подтверждения D24, корнем процесса становится `/`: stdio-агент с «Run in the project folder» стартует в `/`, встроенный читает `HostSettings` из `/.codelab/`. Подтверждение D24 говорило о сессии, а не о процессе. Варианты: (a) корень диска не берётся корнем процесса, пока есть другой кандидат: для триггера 3 — выбранный проект; для «Restart agent» — папка сессии в фокусе, если она не корень диска, затем выбранный проект, затем прежний корень; корень диска — только если кандидата нет, после подтверждения D24; (b) как в D11/D18. **Решено: (a)** — spec agent-workbench-ui «Агент стартует сам» (исключение для триггера 3, сценарий «Сессия в корне диска не делает корень диска корнем процесса»), app-settings «Блок «Behavior»…» (порядок корня, сценарий «Корень перезапуска при сессии в корне диска»). Сессия загружается со своим `cwd` в любом случае.
