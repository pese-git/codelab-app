## Why

Бинарь `codelab-agent` со сценарием `--llm-script` держит сессии в памяти: capability `sessionPersistence` сужена, `initialize` объявляет `loadSession: false` и не объявляет `sessionCapabilities.list` (agent-binary «Сценарий --llm-script»). Поэтому клиент по ACP не вправе вызывать `session/list` и `session/load`, и e2e-тесты `codelab_desktop` в режиме `CODELAB_E2E_AGENT=dart` не могут проверить список, загрузку и восстановление сессий (change `add-session-list-and-reload`, D8, задачи 5.5 и 5.6). Сейчас `session_list_load_flow_test.dart` идёт только на scripted-агенте `codelab_acp_testing`, а сценарий «ход пережил переподключение по WebSocket» (5.6) заблокирован: его можно проверить только на Dart-агенте с `detachGrace` и `SessionBridge.reattach`.

## What Changes

- Скрытый тестовый флаг бинаря `--sessions-dir <path>`: вместе с `--llm-script` журналы сессий пишутся в `JsonlSessionStore(root: <path>)` (`codelab_agent_io`), capability `sessionPersistence` включена, `initialize` объявляет `loadSession: true` и `sessionCapabilities.list`. Сессии переживают перезапуск процесса.
- `$CODELAB_HOME` с `--llm-script` по-прежнему не создаётся и не читается: каталог журналов задаёт только флаг.
- `--sessions-dir` без `--llm-script` — ошибка использования (код `64`): журнал провайдера живёт в `$CODELAB_HOME/sessions`, второй источник пути до конфига этапа 8 не нужен.
- `CwdTrackingStore` бинаря оборачивает любое хранилище и узнаёт рабочую папку сессии не только при `create`, но и при `open`: `${cwd}` сценария верен и для сессии, загруженной после перезапуска.
- Без флага поведение `--llm-script` не меняется: сессии в памяти, `loadSession: false`.
- E2E `codelab_desktop` в режиме `dart`: сценарий `integration_test/llm_scripts/with_session_list.json`, флаги режима `withSessionList` с `--sessions-dir` во временной папке теста; тег `scripted-only` снимается с `session_list_load_flow_test.dart`. Сценарий задачи 5.6 change `add-session-list-and-reload` (ход, переживший переподключение по WebSocket) опирается на этот агент; сам сценарий и исправление клиента — change `add-resumed-turn-after-reload`.

Не входит:
- YAML-конфиг и ключ `sessions.dir` — этап 8;
- изменения `AcpAgentServer`, `JsonlSessionStore` и ядра: они уже поддерживают `session/list` и `session/load` при включённой `sessionPersistence`.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities
- `agent-binary`: «Сценарий --llm-script» — флаг `--sessions-dir` и сессии на диске со сценарием; «Минимальный конфиг из флагов» — `--sessions-dir` без `--llm-script` — ошибка использования.

## Impact

- `apps/codelab_agent`: `serve_args.dart` (флаг), `agent_host.dart` (выбор хранилища), `llm_script.dart` (`CwdTrackingStore` над любым хранилищем), тесты `serve_flags_test.dart`, `agent_host_test.dart`, `stdio_process_test.dart`.
- `apps/codelab_desktop/integration_test`: `support/e2e_agent.dart`, `llm_scripts/with_session_list.json`, `session_list_load_flow_test.dart` (после итерации 5 change `add-session-list-and-reload`).
- Документы: `agent-core/15-configuration.md` §15.6 (строка `--llm-script`), `09-09-stage-4-acp-adapter.md` (флаги бинаря).
- Зависимости и ACP-контракты не меняются.
