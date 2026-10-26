## 1. session/list и таймаут запросов в codelab_client_acp (5.2, итерация 1)

- [ ] 1.1 Тесты `packages/dart/codelab_client_acp/test/application/session_list_test.dart`:
  - `listSessions` с `cwd` и курсором возвращает страницу и `nextCursor`;
  - курсор отправляется без изменений, отсутствие `nextCursor` — конец списка;
  - без `sessionCapabilities.list` — типизированная ошибка, кадр не отправляется.

  Источник: acp-protocol-client «Исходящий session/list».
- [ ] 1.2 Тесты `request_timeout_test.dart`:
  - `session/new` без ответа дольше `requestTimeout` — `AcpRequestTimeoutException` с методом;
  - поздний ответ не меняет состояние;
  - `session/prompt` таймаутом не ограничен;
  - таймаут `session/load` отбрасывает буфер реплея.

  Источник: acp-protocol-client «Таймаут исходящих запросов».
- [ ] 1.3 `AcpClientApplication.listSessions`, `SessionListPage`, параметр `requestTimeout` (60 с по умолчанию), `AcpRequestTimeoutException`, событие лога `request_timeout` (D1, D2) — 1.1 и 1.2 зелёные. PR итерации 1.

## 2. Список и загрузка сессий в codelab_client_core (итерация 2)

- [ ] 2.1 Тесты `test/sessions/session_list_test.dart`:
  - после `connect()` первая страница в `WorkspaceState.sessions` со статусом `notLoaded`, заголовком и `updatedAt`;
  - открытая сессия не дублируется;
  - `loadMoreSessions()` добавляет следующую страницу, повторный вызов в полёте игнорируется, `hasMoreSessions` гаснет после последней страницы;
  - без `list` запросов нет;
  - ошибка списка — диагностика.

  Источник: acp-client-kit «Список и загрузка сессий проекта».
- [ ] 2.2 Тесты `test/sessions/load_session_test.dart`:
  - `loadSession` строит транскрипт из реплея и регистрирует `SessionHandle`;
  - повторный вызов в полёте не шлёт второй `session/load`;
  - без `loadSession` у агента — `ClientWorkspaceException` без кадра;
  - ошибка — строка остаётся `notLoaded`;
  - реплей с теми же id ходов (`turn-1`) после повторной загрузки — проекция с нуля (D4).
- [ ] 2.3 `AgentBackend.listSessions`/`loadSession`, `SessionSummaryView.title`/`updatedAt`, `SessionStatusView.notLoaded`, `WorkspaceState.hasMoreSessions`, `ClientWorkspace.loadSession`/`loadMoreSessions`, сброс проекции в `TranscriptProjector` (D3, D4) — 2.1 и 2.2 зелёные. PR итерации 2.

## 3. Сессии после переподключения (итерация 3)

- [ ] 3.1 Тесты `test/sessions/reconnect_reload_test.dart`:
  - `reconnect()` к агенту с `loadSession` загружает открытые сессии, сначала активную, транскрипт заменяется реплеем;
  - агент без `loadSession` — `detached` и `NoticeItem(kind: detached)` с текстом D5;
  - ошибка `session/load` одной сессии — `detached` только у неё;
  - промпт в `detached` сессию — `PromptFailed` без кадра, очередь не сливается;
  - после `reconnect()` список запрашивается заново;
  - неудачный `reconnect()` — одна попытка, `attempt: 1`.

  Источник: acp-client-kit «Сессии после переподключения», «Явный автомат соединения».
- [ ] 3.2 `SessionStatusView.detached`, `NoticeKind.detached`/`reconnected`, перезагрузка сессий в `reconnect()`, запрет отправки и слива очереди у `detached` (D5) — 3.1 зелёный. PR итерации 3.

## 4. Восстановление после перезапуска (5.12, итерация 4)

- [ ] 4.1 Тесты `test/restore/workspace_restorer_test.dart`, по случаю на шаги D6:
  - нет снимка — обычный старт;
  - битый снимок и неизвестная версия — диагностика, снимок удалён;
  - проект снимка отдаётся хосту до подключения;
  - агент с `loadSession` — активная сессия загружена, остальные `notLoaded`;
  - агент без `loadSession` — `session/new` с уведомлением;
  - ошибка `session/load` — `session/new`, id удалён из снимка;
  - восстановление один раз за запуск;
  - без отправки промптов и ответов на одобрения.

  Источник: acp-client-kit «Восстановление после перезапуска».
- [ ] 4.2 Тесты записи снимка:
  - после `newSession`, `loadSession`, `activate` и смены проекта;
  - склейка не чаще раза в секунду, `dispose` дожидается последней записи;
  - ошибка записи — диагностика;
  - в снимке нет курсора, транскрипта, очереди и секретов.
- [ ] 4.3 `WorkspaceSnapshot`, порт `WorkspaceSnapshotStore`, `InMemoryWorkspaceSnapshotStore` для тестов и хостов без хранилища, `WorkspaceRestorer` в `lib/src/restore/` (D6) — 4.1 и 4.2 зелёные.
- [ ] 4.4 Тест и реализация `SharedPreferencesWorkspaceSnapshotStore` в `apps/codelab_desktop/lib/core/platform/` (ключ `codelab.workspace.snapshot`, версия 1). Привязка в графе cherrypick: `SettingsCubit` получает проект из снимка при старте. Тесты фасада и `widget_test.dart` зелёные. PR итерации 4.

## 5. Сайдбар и интеграционный тест (5.10, итерация 5)

- [ ] 5.1 Тесты `codelab_ui`: `CodeLabSessionSidebar` показывает статусы `notLoaded` и `detached`, а кнопку `sessions-load-more` — только при `onLoadMore` (D7).
- [ ] 5.2 Тесты `ui_mappers_test.dart` и widget-тесты app:
  - строки сайдбара из `WorkspaceState.sessions` в прежнем порядке для открытых сессий;
  - выбор `notLoaded` вызывает загрузку и активирует сессию;
  - ошибка загрузки не меняет активную сессию;
  - `NoticeItem` `detached`/`reconnected` — диагностическая запись ленты.

  Источник: agent-workbench-ui «Sessions sidebar lists the project's sessions from the agent», «Selecting a not-loaded session restores its transcript».
- [ ] 5.3 `CodeLabSessionStatus.notLoaded`/`detached` и `onLoadMore` в `codelab_ui`; `SessionsCubit` на `WorkspaceState.sessions`; маппинг в `ui_mappers.dart` (D7) — 5.1 и 5.2 зелёные.
- [ ] 5.4 Режим scripted-агента `withSessionList` в `codelab_acp_testing` (D8) с тестом пакета на Dart VM:
  - `loadSession` и `list` в `initialize`;
  - страницы по 2 с курсором;
  - реплей на `session/load`;
  - сессии в файле переживают перезапуск процесса.
- [ ] 5.5 `integration_test/support` очищает ключ снимка перед каждым тестом. `session_list_load_flow_test.dart` проверяет:
  - список и выбор сессии;
  - `Reconnect` перезагружает активную сессию;
  - перезапуск корневого scope с теми же `SharedPreferences`.

  Сценарий Dart-агента — `llm_scripts/session_list_load.json`. Источник: testing-quality «Интеграционный тест списка и загрузки сессий». Прогон в feature-ветке — `analyze`, на macOS — только в `release/*` (`AGENTS.md` §21). PR итерации 5.

## 6. Документы и Definition of Done

- [ ] 6.1 Документы:
  - `09-10-stage-5-client-kit.md`: алгоритм восстановления — момент первого подключения, без `profileId` и `ProfileStore`; повторы переподключения вынесены (D5, D6);
  - `agent-parity-goals.md`: строка D-03 — доказательство `app:session_list_load_flow_test.dart`;
  - `AGENTS.md` пакета `codelab_client_core`: восстановление и снимок.
- [ ] 6.2 Definition of Done:
  - `fvm dart run melos run check` и `melos run guard` зелёные;
  - тесты `codelab_client_acp`, `codelab_client_core`, `codelab_acp_testing` зелёные;
  - интеграционные тесты собираются;
  - тексты прежних 8 интеграционных тестов не изменены.
- [ ] 6.3 Перед архивированием: `openspec validate add-session-list-and-reload --strict`.
