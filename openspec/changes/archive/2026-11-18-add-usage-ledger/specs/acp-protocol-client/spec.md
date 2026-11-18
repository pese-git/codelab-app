## ADDED Requirements

### Requirement: Запрос журнала usage
Клиент CodeLab SHALL считать запрос `_codelab/session/usage/ledger` доступным, только если `agentCapabilities._meta.codelab.usageLedger` ответа `initialize` — объект с `version`, равным целому JSON-числу `1` (правило D9 change `add-subagents-and-tasks`; design.md change `add-usage-ledger`, D7, D9). Клиент НЕ SHALL объявлять `usageLedger` в `clientCapabilities._meta.codelab`.

`AcpClientApplication` SHALL предоставлять операцию запроса журнала с `sessionId` и `rebuild`; она отправляет `_codelab/session/usage/ledger` с параметрами `{"sessionId", "rebuild"}` (`rebuild` — только при `true`) и возвращает сырой результат (объект JSON) вместе с поколением соединения, на котором ушёл запрос. Содержимое результата этот слой не разбирает. Операция — `AcpClientApplication.requestUsageLedger({sessionId, rebuild})`, результат — `UsageLedgerReply {result, generation}`. Ошибка JSON-RPC SHALL возвращаться `AcpClientApplicationException` с `cause` типа `JsonRpcError` (код — `cause.code`); без объявленного `usageLedger` операция SHALL завершаться тем же исключением без отправки кадра. Запрос НЕ SHALL добавлять полей в стандартные типы ACP.

#### Scenario: Агент объявил журнал
- **WHEN** ответ `initialize` содержит `agentCapabilities._meta.codelab.usageLedger: {"version": 1}`, и приложение запрашивает журнал с `rebuild: true`
- **THEN** на провод уходит `_codelab/session/usage/ledger` с `{"sessionId": "<id>", "rebuild": true}`, результат возвращён как есть с поколением соединения (`usage_ledger_request_test.dart`)

#### Scenario: Агент без ключа
- **WHEN** в ответе `initialize` нет `usageLedger` или его `version` — `2`, `1.0` или `"1"`
- **THEN** операция завершается отказом, кадр не отправлен

#### Scenario: Ошибка агента
- **WHEN** агент отвечает на запрос `-32601`
- **THEN** операция возвращает типизированный сбой с кодом `-32601`, соединение живо
