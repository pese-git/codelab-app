## Why

Dart-агент не отменяет идущий ход, когда закрывается WebSocket: он держит ход `detachGrace` (30 с). Если сессию загружают с нового соединения, агент продолжает ход и шлёт его `session/update` уже после ответа на `session/load`. Итог хода он передаёт расширением `_meta.codelab.turnEnded` в `session_info_update` (agent-acp-server, §13.5 шаг 9 `agent-core/13-acp-adapter.md`; расширение введено change `add-dart-agent-acp-server`, D10).

Клиент этого не поддерживает. После `session/load` ядро закрывает все ходы реплея (acp-protocol-client «Загруженная сессия показывает повторённую историю»). Поздний `agent_message_chunk` приходит в сессию без активного хода и отбрасывается, а `_meta.codelab.turnEnded` никто не разбирает. В итоге после `Reconnect` посреди хода пользователь теряет ответ агента: в ленте остаётся реплика и «Completed with stopReason unknown.». Это воспроизводит e2e задачи 5.6 change `add-session-list-and-reload`, перенесённой сюда.

## What Changes

- Замена транспорта (`Reconnect`, повторное подключение) запоминает сессии, у которых в этот момент шёл ход: такой ход **прерван**.
- После успешного `session/load` прерванной сессии клиент ждёт продолжения. Первое обновление уровня хода (`agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`), запрос `session/request_permission` или `turnEnded` при отсутствии активного хода **возобновляет** последний ход реплея: он снова выполняется, и обновления применяются к нему как к живому ходу.
- Пока ход не возобновлён, он показан завершённым, как сейчас: без подтверждения агента клиент не показывает ход выполняющимся (`session-lifecycle.md` §51).
- `session_info_update` с `_meta.codelab.turnEnded` завершает возобновлённый ход: `{"stopReason"}` — как ответ на `session/prompt`, `{"error": {message, …}}` — ход завершается с ошибкой. Если `turnEnded` пришёл первым, ход возобновляется и сразу закрывается: итог не теряется.
- Отмена возобновлённого хода — обычный `session/cancel`. Повторно отправленный агентом запрос разрешения создаёт новое одобрение для того же `toolCallId`, старое решение не применяется (`session-lifecycle.md` §52, PERM-4).
- Отметка снимается после возобновления, после нового `session/prompt`, после неудачного `session/load` и при следующей замене транспорта. Агент, который не продолжает ход (stdio — новый процесс, истёк `detachGrace`, агент не CodeLab), оставляет сессию в прежнем виде.
- E2E `session_list_load_flow_test.dart` в режиме `dart`: ход переживает `Reconnect` по WebSocket (тест уже в ветке, красный).

Не входит:
- показ «ход, возможно, продолжается» до первого обновления агента;
- возобновление хода после перезапуска app: клиент не знает о прерванном ходе прошлого процесса;
- `steerReturned` в `turnEnded` (после MVP, §17.7).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities
- `acp-protocol-client`: новое требование «Ход, переживший переподключение» — возобновление прерванного хода по поздним обновлениям после `session/load` и его завершение по `_meta.codelab.turnEnded`.
- `testing-quality`: новое требование «Интеграционный тест хода, пережившего переподключение».

## Impact

- `packages/dart/codelab_client_acp`: `SessionStateMachine` (возобновление хода реплея), `AcpClientApplication` (отметка прерванных ходов, разбор `_meta.codelab.turnEnded`, запросы разрешений возобновлённого хода); тесты `state_machines_test.dart` и `test/application/resumed_turn_test.dart`.
- `packages/dart/codelab_client_core` и `apps/codelab_desktop/lib` не меняются: занятость сессии и кнопка отмены уже следуют за активным ходом.
- `apps/codelab_desktop/integration_test`: `session_list_load_flow_test.dart`, `support/e2e_agent.dart` (`startWebSocketAgent`), `llm_scripts/reconnect_mid_turn.json`; `apps/codelab_agent/test/llm_scripts_load_test.dart`.
- Документы: `agent-core/13-acp-adapter.md` §13.12 (кто читает `turnEnded`), `docs/architecture/session-lifecycle.md` §30.
- ACP-контракт агента и зависимости не меняются: клиент начинает читать уже введённое расширение.
