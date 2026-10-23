## Why

Клиентский прогон корпуса golden-фикстур (`melos run conformance:client`, change `add-acp-golden-fixture-corpus`) нашёл расхождение со спецификацией ACP в фикстуре `acp/prompt-cancel-mid-tool`: после `cancelTurn` вызов инструмента, который ещё не завершился, остаётся в `in_progress`.

`AcpClientApplication` сразу переводит ход в терминальный `cancelled`, поэтому:

- не помечает незавершённые вызовы хода отменёнными, хотя `05-Prompt Turn.md#cancellation` говорит, что клиент SHOULD сделать это сразу после `session/cancel`;
- отбрасывает поздний `tool_call_update` (агент сообщает вызов как `failed` до ответа на `session/prompt`), хотя клиент SHOULD принимать обновления вызовов после `session/cancel`. Это нарушает и уже утверждённый сценарий «Запоздавшее обновление после cancel» в `acp-protocol-client`;
- освобождает сессию до ответа на `session/prompt`. Очередь промптов сразу шлёт следующий `session/prompt`, и запоздавшие обновления старого хода, а затем его ответ `stopReason: cancelled` применяются уже к новому ходу (`AGENTS.md` §9).

## What Changes

- Ход после `session/cancel` проходит явное промежуточное состояние «отменяется» и становится терминальным только по ответу на свой `session/prompt`. В этом состоянии клиент принимает обновления хода, сессия занята и не начинает новый ход.
- При отправке `session/cancel` клиент сразу помечает незавершённые (`pending`, `in_progress`) вызовы хода отменёнными. В wire-перечислении `ToolCallStatus` нет `cancelled`, поэтому отмена хранится как `failed` с признаком отмены клиентом; UI показывает такой вызов как «Cancelled».
- Поздний `tool_call_update` того же хода принимается; нетерминальный статус не возвращает отменённый вызов в работу, терминальный статус агента (`completed`/`failed`) применяется.
- Обновления после ответа на `session/prompt` и события прежнего соединения по-прежнему отбрасываются как устаревшие.
- Из `client_fixture_conformance_test.dart` убирается `skip` проверки статуса вызова, из `add-acp-golden-fixture-corpus/design.md` — запись о расхождении.
- **BREAKING** для потребителей `acp_client_core`: новые значения `PromptTurnStatus.cancelling` и `SessionLifecycleStatus.cancellingTurn`, `cancelTurn` возвращает ход в состоянии `cancelling`. ACP-контракты (wire) не меняются.

## Capabilities

### New Capabilities

_(нет)_

### Modified Capabilities

- `acp-protocol-client`: жизненный цикл отмены prompt turn (состояние «отменяется», пометка незавершённых вызовов, приём обновлений до ответа на `session/prompt`, граница устаревших событий).
- `agent-workbench-ui`: отменённый клиентом вызов показывается как «Cancelled»; во время отмены сессия занята, очередь ждёт ответа агента.

## Impact

- `packages/dart/acp_client_core`: `domain_models.dart` (`PromptTurnStatus`, `SessionLifecycleStatus`, `ToolCallRecord`), `state_machines.dart` (переходы отмены и слияние обновлений вызова), `acp_client_application.dart` (`cancelTurn`, `session/request_permission` во время отмены), тесты.
- `apps/codelab_app`: `shell_cubit.dart` — отображение нового статуса сессии и отменённого вызова, `canCancel` во время отмены.
- `packages/dart/acp_client_core/test/fixtures/client_fixture_conformance_test.dart` — снять `skip`.
- `openspec/changes/add-acp-golden-fixture-corpus/design.md` (или его архив) — убрать запись о расхождении.
- Фикстура `packages/dart/acp_testing/fixtures/acp/prompt-cancel-mid-tool.json` не меняется (D7).
