## Context

Бинарь `codelab-agent` (change `add-codelab-agent-binary`, D3) со сценарием `--llm-script` собирает ядро над `CwdTrackingStore` — обёрткой `MemorySessionStore`, которая запоминает рабочую папку сессии для `${cwd}` сценария. Capability `sessionPersistence` сужена с причиной `--llm-script`, поэтому `AcpAgentServer` объявляет `loadSession: false` и не объявляет `sessionCapabilities.list` (`agent_server.dart`, `_persistent`). Обещание спецификации — со сценарием в `$CODELAB_HOME` ничего не пишется.

С провайдером из флагов тот же бинарь работает над `JsonlSessionStore($CODELAB_HOME/sessions)` и уже отвечает на `session/list` и `session/load`. Ядру и серверу для сценария менять нечего — не хватает только выбора хранилища в хосте.

Потребитель — e2e `codelab_desktop` в режиме `CODELAB_E2E_AGENT=dart` (change `add-session-list-and-reload`, D8, задачи 5.5 и 5.6): тест перезапускает app и, значит, процесс агента, а сессии должны остаться.

Источники: `agent-core/08-sessions.md` (§8.5 раскладка JSONL), `agent-core/15-configuration.md` §15.6 (флаги), `09-09-stage-4-acp-adapter.md` (задача 4.6), спецификация `agent-binary`.

## Goals / Non-Goals

**Goals:**
- Со сценарием — журнал на диске по явному флагу, `loadSession` и `sessionCapabilities.list`.
- Сессии переживают перезапуск процесса; `${cwd}` верен для загруженной сессии.
- Без флага поведение `--llm-script` и провайдера не меняется.
- E2E списка и загрузки сессий и сценарий задачи 5.6 на Dart-агенте.

**Non-Goals:**
- Ключ конфига `sessions.dir` и смена корня журнала у провайдера — этап 8.
- Изменения `AcpAgentServer`, `JsonlSessionStore`, ядра.

## Decisions

### D1. Флаг `--sessions-dir <path>`, только со сценарием

Скрытый в справке флаг, как `--llm-script`: это поверхность тестов, а не продукта. Значение — корень `JsonlSessionStore` (раскладка `<root>/<cwdSlug>/<created>_<id>.jsonl`, §8.5). Каталог создаёт хранилище при первой записи.

С `--provider` флаг — ошибка использования `--sessions-dir requires --llm-script`: у провайдера журнал уже на диске в `$CODELAB_HOME/sessions`, а второй способ задать корень до конфига этапа 8 расходился бы с §15.6.

Альтернативы:
- писать журнал сценария в `$CODELAB_HOME/sessions` — отклонено: нарушает обещание «`$CODELAB_HOME` не создаётся», а e2e app передаёт агенту только команду и аргументы профиля; окружение пришлось бы задавать отдельно;
- переменная `CODELAB_SESSIONS_DIR` — отклонено: §15.6 не знает такой переменной, а тестовая поверхность бинаря — флаги (`--llm-script`);
- новый режим scripted-агента вместо Dart-агента — отклонено: сценарий 5.6 проверяет поведение процесса Dart-агента при обрыве WebSocket (`detachGrace`, `SessionBridge`), которого у scripted-агента нет.

### D2. `CwdTrackingStore` над любым хранилищем

`CwdTrackingStore(inner)` получает внутреннее хранилище: `MemorySessionStore` без флага, `JsonlSessionStore` с флагом. Рабочую папку он запоминает при `create` (новая сессия) и при `open` — из `SessionSnapshot.header.cwd`: `session/load` открывает журнал через `open`, и после перезапуска процесса `create` для этой сессии не вызывается. Иначе `${cwd}` загруженной сессии подставлялся бы пустым.

Проверка сборки ядра (`buildAgentCore`: `sessionPersistence` требует не `MemorySessionStore`) обёртку не различает, поэтому capability включает хост: без флага он сужает её с прежней причиной, с флагом — не сужает.

### D3. Шаги сценария после перезапуска

Шаги общие для процесса и расходуются по порядку запросов (D3 change `add-codelab-agent-binary`). Новый процесс начинает их с первого шага: сценарий e2e пишется так, чтобы каждый запуск агента расходовал свои шаги. `session/load` шагов не расходует — реплей идёт из журнала.

### D4. E2E на Dart-агенте

`E2eAgent.launch(tempDir, mode: withSessionList)` в режиме `dart` добавляет `--sessions-dir <tempDir>/agent-sessions`: перезапуск app внутри теста поднимает новый процесс с тем же каталогом, а следующий тест получает чистую папку. Сценарий `llm_scripts/with_session_list.json` повторяет видимое поведение режима `withSessionList` scripted-агента. Тег `scripted-only` снимается с тестов, которые проходят на обоих агентах.

Сценарий задачи 5.6 (ход, переживший переподключение) требует WebSocket: по stdio `detachGrace` равен нулю, и закрытие соединения — конец процесса. Тест режима `dart` запускает `codelab-agent serve --ws --port 0 --sessions-dir …` сам, подключает app профилем WebSocket и нажимает `Reconnect` посреди хода со `waitForCancel`/долгим шагом. Если поздние `session/update` после `session/load` применяются неверно, исправление идёт в `codelab_client_acp`/`codelab_client_core` в рамках change `add-session-list-and-reload` (задача 5.6). Итог: задача 5.6 перенесена в change `cancel-turn-on-ws-disconnect` — бинарь получил `detachGrace` ноль и для WebSocket, сценарий проверяет отмену хода при Reconnect.

## Risks / Trade-offs

- **[Тестовый флаг становится продуктовым]** → флаг скрыт в справке и допустим только с `--llm-script`; продуктовый корень журнала — ключ конфига этапа 8.
- **[Журнал сценария копится между прогонами e2e]** → каталог внутри временной папки теста, которую тест удаляет.
- **[Шаги сценария после перезапуска начинаются сначала]** → это свойство теста (D3), описано в спецификации.

## Migration Plan

Новых данных у пользователей нет: флаг скрыт и нужен только тестам. Откат — revert: без флага поведение прежнее.

## Open Questions

Нет.
