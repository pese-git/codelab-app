## Why

При `session/load` агент повторяет историю сессии уведомлениями `session/update` до ответа на запрос (`docs/acp/protocol/03-Session Setup.md#loading-a-session`; `agent-core/13-acp-adapter.md` §13.5). Клиент `acp_client_core` создавал сессию только по ответу, а обновления неизвестной сессии отбрасывал — загруженная сессия открывалась пустой. Кроме того, `current_mode_update` и `session_info_update` вне хода не доходили до состояния сессии, хотя ACP разрешает их в любой момент сессии.

## What Changes

- `loadSession` буферизует `session/update` загружаемой сессии (id из запроса) до ответа и после успешного ответа раскладывает историю в завершённые ходы; при ошибке запроса буфер отбрасывается.
- Модель хода реплея: ход открывает `user_message_chunk` после ответа агента; подряд идущие чанки пользователя — одна реплика в `prompt`; ход реплея закрыт как `completed` без `stopReason` (`session-lifecycle.md` §51).
- `current_mode_update` меняет текущий режим сессии, `session_info_update` — заголовок, независимо от наличия активного хода (как уже работали `available_commands_update` и `config_option_update`).
- Режимы и опции из ответа `session/load` главнее значений из реплея.
- **BREAKING**: нет. ACP contracts не меняются.

## Capabilities

### New Capabilities

_(нет)_

### Modified Capabilities

- `acp-protocol-client`: требование «Настройка сессии» — восстановление истории при `session/load`; требование «Жизненный цикл prompt turn» не меняется.

## Impact

- `packages/dart/acp_client_core/lib/src/application/acp_client_application.dart` — буфер реплея.
- `packages/dart/acp_client_core/lib/src/domain/state_machines.dart` — `SessionStateMachine.replayHistory`, сессионные `current_mode_update`/`session_info_update`.
- Клиентское покрытие golden-фикстур (`acp/session-load-replay`, `pendingCoverage` FIX-2) — follow-up после слияния итерации 4 этапа 4 (`add-dart-agent-acp-server`).
