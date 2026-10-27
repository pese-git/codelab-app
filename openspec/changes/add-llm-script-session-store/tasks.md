## 1. Флаг и хранилище сценария (D1, D2, D3)

- [x] 1.1 Красные тесты `apps/codelab_agent`:
  - `serve_flags_test.dart`: `--sessions-dir` разобран в `ServeOptions.sessionsDir`, без `--llm-script` — `UsageError`, в справке флага нет;
  - `agent_host_test.dart`: с `--sessions-dir` — `loadSession: true` и `sessionCapabilities.list`, журнал в каталоге флага, `CODELAB_HOME` не создан; второй хост над тем же каталогом отдаёт сессию в `session/list`, повторяет историю на `session/load`, `${cwd}` хода загруженной сессии — её папка; без флага — прежнее поведение;
  - `stdio_process_test.dart`: сессия процесса с `--sessions-dir` загружается следующим процессом.
- [x] 1.2 `ServeOptions.sessionsDir`, флаг `--sessions-dir` (скрыт), ошибка использования без `--llm-script`; `CwdTrackingStore(inner)` с запоминанием `cwd` на `open`; выбор хранилища и capability в `AgentHost.build` — 1.1 зелёный.
- [x] 1.3 Документы: `agent-core/15-configuration.md` §15.6 (строка `--llm-script`), `09-09-stage-4-acp-adapter.md` (флаги задачи 4.6).
- [x] 1.4 `fvm dart run melos run check` зелёный.

## 2. E2E codelab_desktop на Dart-агенте (D4)

Зависит от итерации 5 change `add-session-list-and-reload` (режим `withSessionList`, `session_list_load_flow_test.dart`).

- [x] 2.1 `integration_test/llm_scripts/with_session_list.json` и ветка `withSessionList` в `_dartFlags` (`--sessions-dir <tempDir>/agent-sessions`); сценарий проверяется `apps/codelab_agent/test/llm_scripts_load_test.dart`.
- [x] 2.2 Снять тег `scripted-only` с `session_list_load_flow_test.dart`; прогон `melos run test:e2e:app:dart-agent` на macOS вручную (`AGENTS.md` §21).
- [x] 2.3 Перенесено в change `add-resumed-turn-after-reload` вместе с задачей 5.6 change `add-session-list-and-reload`: сценарий ход-через-Reconnect красный из-за клиента (поздние `session/update` после `session/load`), исправление — отдельное поведение клиента.
