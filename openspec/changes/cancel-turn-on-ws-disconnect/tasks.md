## 1. Красные тесты

- [x] 1.1 `apps/codelab_agent/test/agent_host_test.dart`: у `--ws` `detachGrace` ноль (spec agent-binary «Команда serve»).
- [x] 1.2 `codelab_client_acp/test/application/interrupted_turn_test.dart` (spec acp-protocol-client «Ход, прерванный заменой транспорта»): прерванный ход `cancelled` после `session/load`; позднее обновление не открывает ход; загрузка без прерывания не меняется; отметка переживает неудачную загрузку и применяется один раз.
- [x] 1.3 E2E `session_list_load_flow_test.dart` «Reconnect over WebSocket cancels the running turn…» в режиме `dart` (`E2eAgent.startWebSocketAgent`, `llm_scripts/reconnect_mid_turn.json`); сценарий проверяется `llm_scripts_load_test.dart` (spec testing-quality «Интеграционный тест Reconnect посреди хода»).

## 2. Реализация

- [x] 2.1 `agent_host.dart`: `detachGrace: Duration.zero` для обоих транспортов (D1).
- [x] 2.2 `AcpClientApplication`: отметка прерванных ходов в `_replaceTransport`, пометка последнего хода реплея в `loadSession`, снятие в `sendPrompt` (D2); лог `turn_interrupted` с `session_id`.
- [ ] 2.3 `melos run check` зелёный; e2e `session_list_load_flow_test.dart` в режиме `dart` на macOS вручную (`AGENTS.md` §21).

## 3. Документы

- [x] 3.1 `09-09-stage-4-acp-adapter.md`: `detachGrace` бинаря — ноль и для WebSocket.
- [x] 3.2 `agent-core/13-acp-adapter.md` §13.10: бинарь MVP не ждёт переподключения; возобновление хода — после MVP.
- [x] 3.3 `docs/architecture/session-lifecycle.md` §30: прерванный заменой транспорта ход отменён, после `session/load` показан `cancelled`.
