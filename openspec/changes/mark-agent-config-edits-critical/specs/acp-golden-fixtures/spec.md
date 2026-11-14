## ADDED Requirements

### Requirement: Фикстура критической правки конфигурации агента
Корпус SHALL содержать фикстуру `acp/permission-agent-config-edit-critical` с ролями `agent` и `client`, `extensions: ["critical", "outcome"]` и ссылками `spec` на `08-Tool Calls.md#requesting-permission` и `15-Extensibility.md#the-_meta-field` (design.md change `mark-agent-config-edits-critical`, D8). Сценарий: режим `bypass`, scripted-модель вызывает `write` с путём `.codelab/config.yaml`; агент отправляет `session/request_permission`, у которого `toolCall.kind` — `edit`, первый блок `content` — текст `agent configuration: .codelab/config.yaml`, затем `diff`, `toolCall._meta.codelab` — `{"critical": true, "label": "write to agent configuration"}`, варианты — `allow_once`, `reject_once`, `reject_always` без `allow_always`; клиент отвечает `reject_once`; агент НЕ SHALL отправлять `fs/write_text_file`, вызов завершается `tool_call_update` `failed` с `_meta.codelab.outcome: rejected`, ход — ответом `session/prompt` с `end_turn`.

#### Scenario: Агентский прогон
- **WHEN** агентский драйвер проигрывает `acp/permission-agent-config-edit-critical` против Dart-агента
- **THEN** кадр `session/request_permission` совпадает с фикстурой, включая `_meta.codelab.critical` и метку, и ни одного `fs/write_text_file` нет

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер проигрывает эту фикстуру, а тест в хуке выбирает `reject_once`
- **THEN** одобрение хода помечено `critical`, вызов `call_1` — `failed`, ход завершён
