## Why

Агентский прогон golden-фикстур этапа 4 (`add-dart-agent-acp-server`) показал, что клиент теряет текст ответа. Dart-агент стримит текст дельтами по 16 символов (`ScriptedStreamFunction`), а `_applyUpdateToTurn` в `acp_client_core` (`state_machines.dart`) отбрасывал любой `session/update`, равный уже записанному в ходе (`turn.updates.contains(update)`). Две одинаковые дельты — `----------------` в таблице Markdown, повторяющийся текст, `'x' * 160` в contract test — превращались в одну: в ходе оставался один чанк из десяти.

Чанки ACP (`agent_message_chunk`, `agent_thought_chunk`, `user_message_chunk`) — приращения без id, номера или ревизии. По ним нельзя отличить повторную доставку от следующей законной дельты с тем же текстом, а `docs/architecture/streaming.md` §8 запрещает дедупликацию без опоры в протоколе. Сценарий «Приходит дублирующееся обновление» требования «Идемпотентные переходы состояния» при буквальном чтении требовал именно такой эвристики, поэтому его формулировка уточняется.

## What Changes

- Чанки текста и рассуждений всегда дописываются в ход, даже когда равны предыдущим.
- Защита от дублей остаётся для идемпотентных обновлений-снимков: `tool_call`/`tool_call_update` (слияние по `toolCallId`), `plan`, `current_mode_update`, `available_commands_update`, `config_option_update` и прочих.
- **BREAKING**: нет. ACP не гарантирует повторную доставку чанков, а stdio/WebSocket-транспорты их не повторяют.

## Capabilities

### New Capabilities
_Нет._

### Modified Capabilities
- `acp-protocol-client`: в требовании «Идемпотентные переходы состояния» сценарий дубля относится к обновлениям-снимкам; добавлен сценарий повторяющихся одинаковых чанков.
- `testing-quality`: сценарий теста дублирующегося события уточнён так же.

## Impact

- `packages/dart/acp_client_core/lib/src/domain/state_machines.dart` — `_applyUpdateToTurn`.
- `packages/dart/acp_client_core/test/state_machines_test.dart`, `test/application_use_cases_test.dart` — тест, закреплявший дефект, заменён.
- UI (`shell_cubit.dart`, `_agentTranscriptEntries`) уже склеивает подряд идущие чанки одного вида в одну запись; изменений не требует.
