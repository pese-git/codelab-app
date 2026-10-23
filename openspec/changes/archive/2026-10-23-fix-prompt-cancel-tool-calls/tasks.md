## 1. Домен: состояния отмены (TDD)

- [x] 1.1 Красные тесты `state_machines_test.dart`: `cancel` переводит ход в `cancelling` и помечает незавершённые вызовы (`failed` + `cancelledByClient`), завершённые не трогает; обновления применяются к ходу в `cancelling`; правила слияния D4; `complete` из `cancelling` даёт статус по `stopReason`; `startTurn` отклоняется в `cancellingTurn`; `requestApproval` отклоняется в `cancelling`
- [x] 1.2 `PromptTurnStatus.cancelling`, `SessionLifecycleStatus.cancellingTurn`, `ToolCallRecord.cancelledByClient`; перегенерировать freezed
- [x] 1.3 Переходы в `state_machines.dart`, тесты 1.1 зелёные

## 2. Приложение: `AcpClientApplication`

- [x] 2.1 Красные тесты `application_use_cases_test.dart`: `cancelTurn` возвращает ход в `cancelling`, поздний `tool_call_update` применяется, ответ `cancelled` завершает ход, повторный `cancelTurn` не шлёт второй `session/cancel`, `session/request_permission` во время отмены получает `cancelled`, `sendPrompt` до ответа отклоняется
- [x] 2.2 `cancelTurn` и обработка `session/request_permission`, тесты 2.1 зелёные; поправить существующие тесты, ожидавшие немедленный `cancelled`

## 3. Workbench

- [x] 3.1 `CodeLabShellCubit`: `cancellingTurn` — занята, `canCancel: false`, в списке сессий `running`; `failed` + `cancelledByClient` → `AcpToolCallStatus.cancelled`; тесты cubit

## 4. Conformance и документация

- [x] 4.1 Снять `skip` (`_cancelledToolCallSkip`) с теста `acp/prompt-cancel-mid-tool: the cancelled tool call ends failed` в `client_fixture_conformance_test.dart`; тест зелёный (после слияния итерации 2 `add-acp-golden-fixture-corpus`) — сделано при архивировании `add-acp-golden-fixture-corpus`: отдельный тест со `skip` удалён, проверка `call_1 → failed` вошла в проверку состояния фикстуры
- [x] 4.2 Убрать запись о расхождении из раздела «Найденные расхождения клиента» `add-acp-golden-fixture-corpus/design.md` (или из его архива) — запись заменена историей «найдено и исправлено этим change» (архив `2026-10-23-add-acp-golden-fixture-corpus/design.md`)
- [x] 4.3 Фикстура `prompt-cancel-mid-tool.json` не меняется

## 5. Проверка

- [x] 5.1 `fvm dart run melos run check` зелёный
- [x] 5.2 `openspec validate fix-prompt-cancel-tool-calls --strict`
