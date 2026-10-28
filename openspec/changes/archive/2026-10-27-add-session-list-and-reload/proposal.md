## Why

Сайдбар `codelab_desktop` показывает только сессии, созданные в текущем запуске. Сессии, которые агент хранит в журнале, недоступны. После переподключения или перезапуска app открытая сессия теряет транскрипт, и продолжить её нельзя. Это строка Must D-03 матрицы паритета (`agent-parity-goals.md`) и последний блок этапа 5 (`09-10-stage-5-client-kit.md`, задачи 5.2, 5.10, 5.12). Протокол (`session/list`, `session/load`) и Dart-агент это уже поддерживают; не хватает клиента.

## What Changes

- `codelab_client_acp`:
  - `listSessions({cwd, cursor})` — `session/list` только при `sessionCapabilities.list`; страница `SessionListPage(sessions, nextCursor)`, курсор непрозрачен и не сохраняется;
  - таймаут JSON-RPC запроса клиента (`requestTimeout`, по умолчанию 60 с, без таймаута для `session/prompt`) с типизированной ошибкой.
- `codelab_client_core`:
  - список сессий проекта в `WorkspaceState` (сессии агента и открытые в этом запуске) с подгрузкой следующей страницы;
  - `ClientWorkspace.loadSession(id, cwd)` — загрузка сессии из списка через `session/load`, транскрипт строится из реплея;
  - после `reconnect()` открытые сессии загружаются заново; агент без `loadSession` или ошибка загрузки — статус сессии `detached` и уведомление в транскрипте;
  - восстановление после перезапуска app: порт `WorkspaceSnapshotStore` и `WorkspaceRestorer`. Снимок хранит проект, активную и открытые сессии. Восстановление выполняется при первом успешном подключении после старта.
- `codelab_desktop`:
  - сайдбар показывает сессии проекта из `session/list` и кнопку подгрузки следующей страницы;
  - выбор незагруженной сессии загружает её;
  - уведомления в ленте о восстановлении;
  - реализация `WorkspaceSnapshotStore` на `shared_preferences`.
- `codelab_acp_testing`: режим scripted-агента `withSessionList` с `session/list` и `session/load`.
- Новый интеграционный тест `apps/codelab_desktop/integration_test/session_list_load_flow_test.dart`. Он проверяет список, загрузку, переподключение и сценарий перезапуска app.

Вне объёма:
- повторы переподключения с паузами и отмена попыток — отдельный change автопереподключения;
- автоподключение при старте и `ProfileStore` в app — change сторожа запуска `add-app-boot-watchdog` (задача 5.11);
- поиск по сессиям и закрытие сессии.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `acp-protocol-client`:
  - исходящий `session/list` с курсорной пагинацией только при объявленной capability;
  - таймаут исходящих запросов клиента.
- `acp-client-kit`:
  - переподключение загружает открытые сессии заново (а не «одна попытка без `session/load`»);
  - список сессий проекта и загрузка сессии через рабочее пространство;
  - восстановление после перезапуска по снимку.
- `agent-workbench-ui`:
  - сайдбар показывает сессии проекта от агента с подгрузкой;
  - выбор незагруженной сессии восстанавливает её транскрипт;
  - восстановление после переподключения и перезапуска app видно пользователю.
- `testing-quality`: интеграционный тест списка и загрузки сессий на scripted- и Dart-агенте.

## Impact

- Код:
  - `packages/dart/codelab_client_acp` (`AcpClientApplication`, модели команд);
  - `packages/dart/codelab_client_core` (`AgentBackend`, `ClientWorkspace`, `WorkspaceState`, новый `lib/src/restore/`);
  - `packages/dart/codelab_acp_testing` (scripted-агент);
  - `apps/codelab_desktop` (`SessionsCubit`, `ActiveSessionCubit`, `ui_mappers.dart`, хранилище снимка, граф cherrypick);
  - `packages/flutter/codelab_ui` (строка «не загружена» и кнопка подгрузки в `CodeLabSessionSidebar`).
- ACP: новых методов и полей нет — только `session/list` и `session/load` по `docs/protocols/acp/protocol/04-Session List.md` и `03-Session Setup.md`.
- Данные пользователя: новый ключ `shared_preferences` `codelab.workspace.snapshot` (версионированный JSON без секретов и транскриптов).
- Зависимости не добавляются.
- Документы:
  - `09-10-stage-5-client-kit.md` — уточнение алгоритма восстановления: без автоподключения и `ProfileStore`, без повторов;
  - матрица паритета, строка D-03 — доказательство.
