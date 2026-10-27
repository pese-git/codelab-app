## Why

`codelab-agent serve --ws` держит ход закрытого соединения `detachGrace` (30 с) и переподключает его, если сессию загружают с нового соединения (agent-binary «Команда serve», agent-acp-server). Для MVP это даёт две проблемы:

- **Клиент не видит продолжения хода.** После `session/load` ядро закрывает ходы реплея, поздние `session/update` отбрасываются, итог `_meta.codelab.turnEnded` клиент не читает. Это воспроизвёл e2e на Dart-агенте (задача 5.6 change `add-session-list-and-reload`, перенесённая сюда).
- **Ход без клиента не может работать с проектом.** Файлы и команды исполняет клиент (`fs/*`, `terminal/*`, `AcpClientExecutionEnv`), поэтому за время разрыва каждый такой вызов агента получает `client connection lost`.

Возобновление хода требует доработки и клиента, и агента. Для MVP проще и предсказуемее поведение stdio: обрыв соединения отменяет ход. WebSocket в MVP — по сути loopback (`serve.ws.non_loopback` предупреждает об ином), случайных обрывов мало, а Reconnect — явное действие пользователя.

## What Changes

- `serve --ws`: `detachGrace` — ноль, как у `serve --stdio`. Закрытие WebSocket посреди хода отменяет ход, ожидающие разрешения → `cancelled` (поведение `AcpAgentServer` при нулевом grace уже определено в agent-acp-server). Механизм `detach`/`reattach` сервера и расширение `_meta.codelab.turnEnded` не меняются: бинарь просто их не задействует.
- Клиент: если замена транспорта прервала идущий ход, то после успешного `session/load` этой сессии последний ход реплея показан отменённым (`cancelled`, `stopReason: cancelled`), а не завершённым без `stopReason` («Completed with stopReason unknown.»). Поздние `session/update` хода после `session/load` по-прежнему отбрасываются.
- E2E `session_list_load_flow_test.dart` в режиме `dart`: Reconnect посреди хода по WebSocket отменяет ход, следующий промпт агент принимает.

Не входит (после MVP):
- возобновление хода после переподключения: клиент читает `_meta.codelab.turnEnded`, агент держит `fs/*` и `terminal/*` до переподключения; черновик клиентской части — локальная ветка `feature/add-resumed-turn-after-reload`;
- флаг или конфиг для `detachGrace` бинаря.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities
- `agent-binary`: «Команда serve» — у `serve --ws` `detachGrace` ноль.
- `acp-protocol-client`: новое требование «Ход, прерванный заменой транспорта».
- `testing-quality`: новое требование «Интеграционный тест Reconnect посреди хода».

## Impact

- `apps/codelab_agent`: `agent_host.dart` (`detachGrace`), `agent_host_test.dart`.
- `packages/dart/codelab_client_acp`: `AcpClientApplication` (отметка прерванных ходов, пометка хода после `session/load`), `test/application/interrupted_turn_test.dart`.
- `apps/codelab_desktop/integration_test`: `session_list_load_flow_test.dart`, `support/e2e_agent.dart` (`startWebSocketAgent`), `llm_scripts/reconnect_mid_turn.json`; `apps/codelab_agent/test/llm_scripts_load_test.dart`.
- Документы: `09-09-stage-4-acp-adapter.md` (grace бинаря), `agent-core/13-acp-adapter.md` §13.10 (бинарь MVP не ждёт переподключения), `docs/architecture/session-lifecycle.md` §30.
- ACP-контракт, `codelab_agent_acp`, `codelab_client_core` и зависимости не меняются.
