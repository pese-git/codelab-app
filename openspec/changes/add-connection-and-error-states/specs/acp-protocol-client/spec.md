## ADDED Requirements

### Requirement: Типизированный сбой prompt turn
Когда `session/prompt` завершается ошибкой, CodeLab SHALL сохранять в сорвавшемся ходе типизированный `PromptFailure` наряду с текстом для диагностики:

- `agent` — JSON-RPC ошибка, у которой `data.codelab` — объект; несёт `errorClass` (строка или нет), `message` и `retryable` (`bool` или нет);
- `request` — JSON-RPC ошибка без объекта `data.codelab`; несёт `code` и `message`;
- `connectionLost` — ход прерван неожиданным отказом транспорта текущего соединения;
- `unknown` — любой другой сбой.

Разбор `data.codelab` SHALL выполняться в протокольном клиенте. Незнакомое значение `errorClass` SHALL сохраняться как есть. Поле неожиданного типа SHALL считаться отсутствующим, не ломая разбор ответа.

#### Scenario: Сбой провайдера у агента CodeLab
- **WHEN** агент отвечает на `session/prompt` ошибкой `-32603` с `data.codelab: {"errorClass": "auth", "message": "401 Unauthorized from openai: check api_key_env", "retryable": false}`
- **THEN** ход имеет статус `failed` и `PromptFailure.agent` с `errorClass: "auth"`, этим сообщением и `retryable: false`

#### Scenario: Ошибка без расширения CodeLab
- **WHEN** агент отвечает на `session/prompt` ошибкой `-32603` без поля `data`
- **THEN** ход имеет статус `failed` и `PromptFailure.request` с кодом `-32603` и сообщением JSON-RPC

#### Scenario: Незнакомый класс сбоя
- **WHEN** `data.codelab.errorClass` — строка, не известная CodeLab, а `retryable` — не `bool`
- **THEN** ход имеет `PromptFailure.agent` с этой строкой в `errorClass` и `retryable: null`

#### Scenario: Ход прерван обрывом соединения
- **WHEN** во время хода транспорт текущего соединения неожиданно отказывает
- **THEN** ход имеет статус `failed` и `PromptFailure.connectionLost`
