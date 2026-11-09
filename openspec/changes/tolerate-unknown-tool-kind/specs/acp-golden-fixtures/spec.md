## ADDED Requirements

### Requirement: Фикстура неизвестного вида вызова
Корпус SHALL содержать фикстуру `acp/tool-kind-unknown-tolerated` с ролью только `client` (Dart-агент таких видов не выдаёт) и ссылками `spec` на `08-Tool Calls.md#creating`, `08-Tool Calls.md#updating`, `08-Tool Calls.md#requesting-permission`, `12-Session Model.md#exiting-plan-modes`, `17-Schema.md#toolkind` и `05-Prompt Turn.md#4-check-for-completion`. В одном ходе агент SHALL присылать: `tool_call` с `kind: "future_kind"`, его `tool_call_update` с тем же видом и `status: "completed"`, `tool_call` с `kind: "switch_mode"` и `session/request_permission` на него с вариантами `allow_always`, `allow_once`, `reject_once` по образцу `12-Session Model.md`; ожидаемый кадр клиента — ответ `selected` с вариантом `reject_once`; затем `tool_call_update` `failed` и ответ `session/prompt` `end_turn` (design.md change `tolerate-unknown-tool-kind`, D8).

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер проигрывает `acp/tool-kind-unknown-tolerated`, а тест в хуке выбирает вариант `reject_once`
- **THEN** ответ клиента на `session/request_permission` — `selected` с `optionId` `reject`, а не `cancelled`, и ход завершается кадром ответа `session/prompt`

#### Scenario: Состояние после прогона
- **WHEN** клиентский прогон этой фикстуры завершён
- **THEN** вызов `call_future` в ходе имеет вид `other`, статус `completed` и риск `unknown`, вызов `call_switch_mode_001` — вид `switchMode` и риск `unknown`, а диагностик уровня error нет

#### Scenario: Агентский прогон пропускает фикстуру
- **WHEN** агентский драйвер получает `acp/tool-kind-unknown-tolerated`
- **THEN** он её пропускает и сообщает, что у фикстуры нет роли `agent`
