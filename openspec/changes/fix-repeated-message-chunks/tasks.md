## 1. Тесты

- [x] 1.1 Красные тесты `PromptTurnStateMachine`: два одинаковых `agent_message_chunk`/`agent_thought_chunk`/`user_message_chunk` подряд дают две дельты; `'x' * 160` дельтами по 16 символов даёт десять дельт и полный текст; дельта, равная более ранней несоседней, сохраняется
- [x] 1.2 Тест: повтор `plan` по-прежнему игнорируется
- [x] 1.3 `SendPrompt`: повтор `tool_call_update` схлопывается, повтор чанка сохраняется

## 2. Исправление

- [x] 2.1 `_applyUpdateToTurn`: чанки всегда дописываются, проверка `turn.updates.contains` остаётся для остальных обновлений
- [x] 2.2 Проверить склейку чанков в UI (`shell_cubit.dart`)

## 3. Проверка

- [x] 3.1 `fvm dart run melos run check`
