## Why

В `apps/codelab_desktop`, пока проект не выбран явно, папкой проекта считается текущая папка процесса CodeLab: геттер `SettingsCubit.projectDirectory` возвращает `selectedProjectPath ?? WorkingDirectoryProvider.currentPath`. Это Decision 1 change `add-open-project-picker`, закреплённый сценарием «No project selected falls back to the current process directory» в `openspec/specs/agent-workbench-ui/spec.md`.

Если `.app` запущен из Finder или через `open`, текущая папка процесса — `/`. Тогда:

- подключение, в том числе «Connect on start», и встроенный агент получают `/` (`localEmbeddedAgentOpener(cwd: /)`);
- stdio-агент с «Run in the project folder» стартует в `/`;
- новая сессия получает `cwd` `/`;
- `/` попадает в снимок рабочего пространства: проектом и `cwd` сессий;
- «Providers» и «MCP servers» читают проектные слои из `/`.

У пользователя: снимок с реальным проектом и `openSessions` с `"cwd":"/"`; активная сессия в `/`, и панель Files (change `add-file-preview-and-tree`) показывает корень диска.

Вторая проблема глубже. Агент в desktop запускается отдельным шагом «Connect» и живёт в одной папке. Dart-агент читает проектные слои конфигурации один раз, для корня запуска (`codelab_embedded/lib/src/io/local_opener.dart:57`). Сессии других папок получают «снимок без проекта» (spec agent-runtime «Конфигурация сессии вне корня запуска»), и запреты их собственного проекта (`permissions.deny`, режим, `permissions.tools.*`) не действуют.

`docs/architecture/platform-integration.md` §54: «Process working directory должен быть explicit. Не следует полагаться на current process directory как implicit workspace».

Решения пользователя:
1. **«Без проекта — нет папки».**
2. **Агент как в OpenCode.** Один агент на окно обслуживает сессии любых папок и при смене папки не перезапускается. Ходы других сессий продолжаются. Dart-агент загружает проектный конфиг по `cwd` каждой сессии. Модель Claude Code (процесс на папку) — после 1.0.
3. **Нет Connect.** Агент стартует сам: выбор проекта (в том числе восстановленного), «New session», фокус на `notLoaded`/`detached`-сессии. Профиль на странице «Connection» выбирается для следующего старта. «Restart agent» — для восстановления и смены профиля, с подтверждением при идущих ходах. «Connect on start» и «Disconnect» не нужны.
4. Остальное:
   - проект-корень снимка не восстанавливается, сессии в `/` открываются только кликом;
   - «New session» без проекта открывает выбор папки;
   - WebSocket подключается первым триггером;
   - CLI вне охвата.

## What Changes

**Итерация A — нет неявной папки (desktop и одно условие в kit, выходит отдельно)**
- `SettingsCubit.projectDirectory` → `String?`; `WorkingDirectoryProvider` уходит из desktop (D1). Это заменяет Decision 1 и запасной spawn-cwd Decision 2 change `add-open-project-picker`.
- Без проекта агент не стартует, «New session» открывает выбор папки, одна папка на намерение (D2, D3, D5).
- «Test connection» без проекта — stdio без переопределения папки (D7). Providers и MCP без проекта — без проектных слоёв (D8). Встроенный резолвер отказывает с пустой папкой (D9).
- Проект-корень снимка не восстанавливается. Активная сессия снимка грузится при старте, только если её `cwd` равен проекту снимка — правило kit `WorkspaceRestorer`, `[client]` в итерации A (D10, HIGH-1 ревью).
- Открытие сессии с `cwd` в корне диска — только после подтверждения `Open` (D24).
- `connect`, `reconnect` и `createSession` ждут восстановления проекта с таймаутом; отказ без проекта — событие `connection.connect_rejected` (D3).

**Итерация C — проектный конфиг Dart-агента на сессию (агент, выходит отдельно)**
- Новый порт ядра `ProjectConfigLoader`. `AgentRuntime` строит для сессии вне корня процесса полный `CoreConfig` её папки: провайдеры, каталог, модель по умолчанию, функцию модели (`modelsFor`), `permissions.*`, `budget.*`, `compaction.*`, `mcp.servers`, `redact.*`. Ключи процесса — `HostSettings` (секреты и их бэкенд, журнал, логи, `config.*`, профиль), `exec.*`, `compaction.enabled`, `trusted_projects`, capability (D21). Провайдер «This project only» работает в сессиях своего проекта без перезапуска.
- `secret migrate` (и «Move secrets») переносит провайдера закоммиченного `config.yaml` с найденным ключом в `config.local.yaml` доверенного проекта: иначе ссылка в `config.yaml` по D23 не разрешалась бы (D26).
- Ключ проектного провайдера привязан к адресу: группа адреса и аутентификации берётся целиком из одного слоя, а ссылки на ключ из закоммиченного `config.yaml` разрешаются только для origin, с которым их связывают глобальные слои (D23, Q14).
- Битый конфиг папки сессии — отказ `session/new` / `session/load` (`-32603`, `data.codelab.reason: "projectConfigInvalid"`), а не тихий снимок без проекта.
- Порт подключают `localEmbeddedAgentOpener` и `codelab-agent serve --stdio`; `serve --ws` сохраняет снимок без проекта, как файлы проекта (Q18 (a)).

**Итерация B — агент стартует сам (клиент и desktop, после C)**
- Kit: `ClientWorkspace.ensureAgent` (single-flight, `projectDirectory` не трогает), `WorkspaceState.agentDirectory`, `session/list` при `selectProject`, `loadSession` для `detached`, восстановление активной сессии только в папке проекта снимка (D15, D16).
- Desktop: триггеры старта (D13); стартовый экран и экран сбоя с «Retry» вместо экрана Connect (D18); «Use» вместо «Connect» в строке профиля; «Restart agent» с подтверждением при работе (D22); удаление «Connect on start» (D19); гонки намерений фокуса (D17).

## Не входит

- `apps/codelab_cli`: вызывает `connect` один раз на папку запуска, его поведение kit сохраняет; код CLI не меняется. Единственное наблюдаемое изменение — общий kit снимает ждущие одобрения при `/reconnect` и потере соединения (design.md, `codelab_client_acp`). Изменения ядра (итерация C) CLI получает автоматически: его сессии и так в корне запуска.
- Процесс агента на папку или сессию (модель Claude Code) — после 1.0 (D12).
- Живая перезагрузка проектного конфига других папок у открытых сессий — после 1.0 (Q12); правка применяется к следующей сессии папки.
- Правило D23 для MCP-серверов проектных слоёв (Q15).
- ACP: методов и полей не добавляется.
- Формат снимка, «закрыть сессию», «Disconnect», запрет выбирать `/` вручную.
- Удаление «Test connection» (решение пользователя) — отдельный change после этого. Здесь проверка без проекта лишь временно остаётся корректной (D7).
- Панель Files (PR #283) — следует за сессией в фокусе и уже имеет пустое состояние без папки.
- Change `add-integrated-terminal` — учтёт правило при своей реализации.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-workbench-ui`:
  - MODIFIED: «Project selection is independent of the connection type», «Workbench restores sessions after reconnect and restart», «Selecting a not-loaded session restores its transcript», «Empty session after connecting»;
  - ADDED: «Без выбранного проекта нет папки агента и сессий», «Агент стартует сам» (повтор старта любым триггером после сбоя, без автоповторов и дублей).
- `app-settings`, MODIFIED: «Список профилей на странице «Connection»» («Use», «Selected»), «Блок «Behavior» страницы «Connection»» (без «Connect on start», «Restart agent» с подтверждением), «Доступ к настройкам агента на страницах Providers и MCP servers».
- `acp-client-kit`: MODIFIED «Сессии после переподключения» (`loadSession` для `detached`), «Одобрения привязаны к вызову» (замена и потеря транспорта снимают ждущие одобрения, найдено в итерации B); ADDED «Агент по требованию хоста».
- `agent-runtime`, MODIFIED: «Конфигурация сессии вне корня запуска» (ключи сессии из папки сессии); ADDED: «Сессии других папок при перезагрузке корня».
- `agent-acp-server`, ADDED: «Ошибка проектного конфига сессии», «Модели сессии по её каталогу».
- `agent-secrets`, ADDED: «Ключ проектного провайдера привязан к адресу»; MODIFIED: «Подкоманда secret migrate» (R8-10 после правила группы, D25).
- `agent-configuration`, MODIFIED: «Секреты только ссылками» (R8-6 после правила группы, D25).
- `embedded-agent`, ADDED: «Проектный конфиг сессий встроенного агента».
- `agent-binary`, ADDED: «Проектный конфиг сессий в serve».

## Impact

- Агент:
  - `codelab_agent_core` — порт, `AgentRuntime._sessionConfig`, `AgentSession.models`, правило D23 в `resolve.dart`; узкий экспорт `provider_binding.dart` через `show` (`ProviderKeyBinding`, `ProviderReference`, `ProviderReferenceKind`, `providerOrigin`, `providerReferences`, `referencesIn`) — одна копия правила D23 для мигратора (D26); `applyProviderGroupRule` и `providerEntry` внутренние (`public_api_test.dart`);
  - `codelab_agent_io` — `FileConfigSource`; мигратор по D26 и новый вариант отчёта `SecretProviderMovedItem` (экспорт также из `codelab_setup/io.dart` и `codelab_embedded/io.dart`); `http` в `dev_dependencies` для `MockClient`;
  - `codelab_agent_acp` — код ошибки, опции `model` по каталогу сессии;
  - `codelab_embedded` — `EmbeddedHostServices.projectConfig`, передача порта;
  - `apps/codelab_agent` — `agent_host.dart`, `serve_config.dart`.
  Allowlist ядра (PKG-2) не меняется.
- Клиент:
  - `codelab_client_core` — `client_workspace.dart`, `workspace_state.dart`, `workspace_restorer.dart`;
  - `codelab_client_acp` — `acp_client_application.dart`: снятие ждущих одобрений при замене и потере транспорта;
  - `apps/codelab_desktop` — `features/workbench`, `features/settings`, `app/`;
  - `codelab_ui` — только при нехватке атома для стартового экрана.
- Тесты: пакеты выше; харнесс характеризационных тестов desktop; интеграционные тесты app (компилируются, на устройстве — в `release/*`).
- Зависимости, правила сторожа, граф в `README.md`: без изменений.
- Документация: общие правила lifecycle и concurrency в `docs/architecture/` соблюдены и не меняются. Документы ядра `proposals/agent-core/10-core-assembly-and-profiles.md`, `17-5-agent-setup.md` и `15-configuration.md` откладывают чтение конфига чужого `cwd` до отдельного change; итерация C правит их до кода (задача C0.1). Заменяемые решения прежних changes — в design.md.
