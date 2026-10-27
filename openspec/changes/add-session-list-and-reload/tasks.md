## 1. session/list и таймаут запросов в codelab_client_acp (5.2, итерация 1)

- [x] 1.1 Тесты `packages/dart/codelab_client_acp/test/application/session_list_test.dart`:
  - `listSessions` с `cwd` и курсором возвращает страницу и `nextCursor`;
  - курсор отправляется без изменений, отсутствие `nextCursor` — конец списка;
  - без `sessionCapabilities.list` — типизированная ошибка, кадр не отправляется.

  Источник: acp-protocol-client «Исходящий session/list».
- [x] 1.2 Тесты `request_timeout_test.dart`:
  - `session/new` без ответа дольше `requestTimeout` — `AcpRequestTimeoutException` с методом;
  - поздний ответ не меняет состояние;
  - `session/prompt` таймаутом не ограничен;
  - таймаут `session/load` отбрасывает буфер реплея.

  Источник: acp-protocol-client «Таймаут исходящих запросов».
- [x] 1.3 `AcpClientApplication.listSessions`, `SessionListPage`, параметр `requestTimeout` (60 с по умолчанию), `AcpRequestTimeoutException`, событие лога `request_timeout` (D1, D2) — 1.1 и 1.2 зелёные. PR итерации 1.

## 2. Список и загрузка сессий в codelab_client_core (итерация 2)

- [x] 2.1 Тесты `test/sessions/session_list_test.dart`:
  - после `connect()` первая страница в `WorkspaceState.sessions` со статусом `notLoaded`, заголовком и `updatedAt`;
  - открытая сессия не дублируется;
  - `loadMoreSessions()` добавляет следующую страницу, повторный вызов в полёте игнорируется, `hasMoreSessions` гаснет после последней страницы;
  - без `list` запросов нет;
  - ошибка списка — диагностика.

  Источник: acp-client-kit «Список и загрузка сессий проекта».
- [x] 2.2 Тесты `test/sessions/load_session_test.dart`:
  - `loadSession` строит транскрипт из реплея и регистрирует `SessionHandle`;
  - повторный вызов в полёте не шлёт второй `session/load`;
  - без `loadSession` у агента — `ClientWorkspaceException` без кадра;
  - ошибка — строка остаётся `notLoaded`;
  - реплей с теми же id ходов (`turn-1`) после повторной загрузки — проекция с нуля (D4).
- [x] 2.3 `AgentBackend.listSessions`/`loadSession`, `SessionSummaryView.title`/`updatedAt`, `SessionStatusView.notLoaded`, `WorkspaceState.hasMoreSessions`, `ClientWorkspace.loadSession`/`loadMoreSessions`, сброс проекции в `TranscriptProjector` (D3, D4) — 2.1 и 2.2 зелёные. Попутно: в `codelab_client_acp` ответ агента с ошибкой, пришедший, пока кадр запроса ещё отправляется, больше не становится необработанной ошибкой (`test/application/early_response_test.dart`). PR итерации 2.

## 3. Сессии после переподключения (итерация 3)

- [x] 3.1 Тесты `test/sessions/reconnect_reload_test.dart`:
  - `reconnect()` к агенту с `loadSession` загружает открытые сессии, сначала активную, транскрипт заменяется реплеем;
  - агент без `loadSession` — `detached` и `NoticeItem(kind: detached)` с текстом D5;
  - ошибка `session/load` одной сессии — `detached` только у неё;
  - промпт в `detached` сессию — `PromptFailed` без кадра, очередь не сливается;
  - после `reconnect()` список запрашивается заново;
  - неудачный `reconnect()` — одна попытка, `attempt: 1`.

  Источник: acp-client-kit «Сессии после переподключения», «Явный автомат соединения».
- [x] 3.2 `SessionStatusView.detached`, `NoticeKind.detached`/`reconnected`, перезагрузка сессий в `reconnect()`, запрет отправки и слива очереди у `detached` (D5) — 3.1 зелёный. Пока идёт переподключение, сессии ставят промпты в очередь и не сливают её: иначе ход, оборванный заменой транспорта, отправил бы очередь в новое соединение до `session/load`. Новые виды `NoticeKind` в `ui_mappers.dart` — диагностическая запись `Session` (исчерпывающий `switch`; тест в `ui_mappers_test.dart`). PR итерации 3.

## 4. Восстановление после перезапуска (5.12, итерация 4)

- [x] 4.1 Тесты `test/restore/workspace_restorer_test.dart`, по случаю на шаги D6:
  - нет снимка — обычный старт;
  - битый снимок и неизвестная версия — диагностика, снимок удалён;
  - проект снимка отдаётся хосту до подключения;
  - агент с `loadSession` — активная сессия загружена, остальные `notLoaded`;
  - агент без `loadSession` — `session/new` с уведомлением;
  - ошибка `session/load` — `session/new`, id удалён из снимка;
  - восстановление один раз за запуск;
  - без отправки промптов и ответов на одобрения.

  Источник: acp-client-kit «Восстановление после перезапуска».
- [x] 4.2 Тесты записи снимка:
  - после `newSession`, `loadSession`, `activate` и смены проекта;
  - записи не накладываются: синхронная серия изменений — одна запись, изменения во время записи — одна следующая; `dispose` дожидается последней записи;
  - ошибка записи — диагностика;
  - в снимке нет курсора, транскрипта, очереди и секретов.
- [x] 4.3 `WorkspaceSnapshot`, порт `WorkspaceSnapshotStore`, `InMemoryWorkspaceSnapshotStore` для тестов и хостов без хранилища, `WorkspaceRestorer` в `lib/src/restore/`; `ClientWorkspace(snapshots:)`, `restoreProject()`, `selectProject()`, `flushSnapshot()` (D6) — 4.1 и 4.2 зелёные.
- [x] 4.4 Тест и реализация `SharedPreferencesWorkspaceSnapshotStore` в `apps/codelab_desktop/lib/core/platform/` (ключ `codelab.workspace.snapshot`, версия 1). Привязка в графе cherrypick: `SettingsCubit` получает проект из снимка при старте и сообщает выбор проекта рабочему пространству (`test/features/workbench/application/workspace_restore_test.dart`); `CodeLabTestBinding(preferences:)`. `integration_test/flutter_test_config.dart` удаляет снимок перед каждым e2e-тестом (D8) — без этого запись снимка из этой итерации переносила бы состояние между тестами на macOS. В `open_project_flow_test.dart` ожидание после перезапуска сменилось с «проект не выбран» на «выбран проект прошлого запуска»: прежнее поведение было вне рамок `add-open-project-picker`, а новое задаёт требование «Workbench restores sessions after reconnect and restart». Тесты фасада и `widget_test.dart` зелёные. PR итерации 4.

## 5. Сайдбар и интеграционный тест (5.10, итерация 5)

- [x] 5.1 Тесты `codelab_ui`: `CodeLabSessionSidebar` показывает статусы `notLoaded` и `detached`, а кнопку `sessions-load-more` — только при `onLoadMore` (D7).
- [x] 5.2 Тесты `ui_mappers_test.dart` и widget-тесты app:
  - строки сайдбара из `WorkspaceState.sessions` в прежнем порядке для открытых сессий;
  - выбор `notLoaded` вызывает загрузку и активирует сессию;
  - ошибка загрузки не меняет активную сессию;
  - `NoticeItem` `detached`/`reconnected` — диагностическая запись ленты.

  Источник: agent-workbench-ui «Sessions sidebar lists the project's sessions from the agent», «Selecting a not-loaded session restores its transcript».
- [x] 5.3 `CodeLabSessionStatus.notLoaded`/`detached` и `onLoadMore` в `codelab_ui`; `SessionsCubit` берёт неоткрытые сессии, `detached` и `hasMoreSessions` из `WorkspaceState`, а строки открытых — по-прежнему из `sessionChanges`; `sessionListItemOfSummary` в `ui_mappers.dart`; `CodeLabShellState.hasMoreSessions` и `CodeLabShellCubit.loadMoreSessions()` (D7) — 5.1 и 5.2 зелёные. В характеризационном `reconnect_test.dart` ожидание «лента пустая» после `reconnect()` сужено до «позднего текста в ленте нет»: агент без `loadSession` теперь оставляет уведомление `detached` (D5).
- [x] 5.4 Режим scripted-агента `withSessionList` в `codelab_acp_testing` (D8) с тестом пакета на Dart VM:
  - `loadSession` и `list` в `initialize`;
  - страницы по 2 с курсором;
  - реплей на `session/load`;
  - сессии в файле переживают перезапуск процесса.
- [x] 5.5 `session_list_load_flow_test.dart` (очистка снимка перед тестами — 4.4) проверяет:
  - список и выбор сессии;
  - `Reconnect` перезагружает активную сессию;
  - перезапуск корневого scope с теми же `SharedPreferences`.

  Тест шёл как `scripted-only`, пока Dart-агент с `--llm-script` держал сессии в памяти (D8); тег снят в change `add-llm-script-session-store` (флаг `--sessions-dir`). Источник: testing-quality «Интеграционный тест списка и загрузки сессий». Прогон в feature-ветке — `analyze`, на macOS — только в `release/*` (`AGENTS.md` §21). PR итерации 5.
- [x] 5.6 Перенесено в change `add-resumed-turn-after-reload`: ход, переживший Reconnect по WebSocket. Красный e2e воспроизвёл дефект клиента: после `session/load` ядро закрывает ходы реплея, поздний `agent_message_chunk` продолжения хода отбрасывается, а `_meta.codelab.turnEnded` не читается. Исправление меняет поведение клиента (acp-protocol-client «Загруженная сессия показывает повторённую историю») и требует отдельного change.

## 6. Документы и Definition of Done

- [ ] 6.1 Документы:
  - `09-10-stage-5-client-kit.md`: алгоритм восстановления — момент первого подключения, без `profileId` и `ProfileStore`; повторы переподключения вынесены (D5, D6);
  - `agent-parity-goals.md`: строка D-03 — доказательство `app:session_list_load_flow_test.dart`;
  - `AGENTS.md` пакета `codelab_client_core`: восстановление и снимок.
- [ ] 6.2 Definition of Done:
  - `fvm dart run melos run check` и `melos run guard` зелёные;
  - тесты `codelab_client_acp`, `codelab_client_core`, `codelab_acp_testing` зелёные;
  - интеграционные тесты собираются;
  - тексты прежних 8 интеграционных тестов не изменены, кроме ожидания проекта после перезапуска в `open_project_flow_test.dart` (4.4).
- [ ] 6.3 Перед архивированием: `openspec validate add-session-list-and-reload --strict`.
