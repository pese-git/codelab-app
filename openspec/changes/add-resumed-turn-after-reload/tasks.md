## 1. Красные тесты

- [x] 1.1 `state_machines_test.dart`: `SessionStateMachine.resumeTurn` открывает последний завершённый ход (`running`, без `stopReason`/`completedAt`, сессия `runningTurn`); без ходов — новый ход без промпта; с активным ходом — отклонение.
- [x] 1.2 `test/application/resumed_turn_test.dart` на `FakeAcpTransport` (spec acp-protocol-client «Ход, переживший переподключение»): ответ после переподключения попадает в ход; `turnEnded` со `stopReason`, с `error`, неизвестной формы; `turnEnded` первым; повторный запрос разрешения; агент не продолжает ход; позднее обновление без прерванного хода; новый промпт снимает ожидание; ошибка `session/load` снимает отметку.
- [x] 1.3 E2E `session_list_load_flow_test.dart` «a turn survives Reconnect over WebSocket…» в режиме `dart` (`E2eAgent.startWebSocketAgent`, `llm_scripts/reconnect_mid_turn.json`); сценарий проверяется `llm_scripts_load_test.dart` (spec testing-quality «Интеграционный тест хода, пережившего переподключение»).

## 2. Реализация

- [x] 2.1 `SessionStateMachine.resumeTurn` (D2).
- [x] 2.2 `AcpClientApplication`: отметки прерванных и ожидающих сессий (D1, D4), возобновление по признакам хода в `_handleSessionUpdate` и `_handlePermissionRequest` (D2, D5), разбор `_meta.codelab.turnEnded` (D3); логи `turn_resumed` и `turn_ended_extension` с `session_id`.
- [ ] 2.3 `melos run check` зелёный; e2e `session_list_load_flow_test.dart` в режиме `dart` на macOS вручную (`AGENTS.md` §21).

## 3. Документы

- [x] 3.1 `agent-core/13-acp-adapter.md` §13.12: строка `turnEnded` — клиент CodeLab читает расширение (change `add-resumed-turn-after-reload`).
- [x] 3.2 `docs/architecture/session-lifecycle.md` §30: выбранная семантика для ACP — прерванный ход ждёт продолжения после `session/load`.
