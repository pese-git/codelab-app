## MODIFIED Requirements

### Requirement: Запросы агента к клиенту
`AcpClientExecutionEnv` SHALL исполнять файлы и команды через клиента по §4.7 и §13.9:
- `readText` → `fs/read_text_file`, `writeText` → `fs/write_text_file`, `stat` → `fs/read_text_file` с `limit: 1`; таймаут 30 с;
- `exec` → `terminal/create` (`command: "/bin/sh"`, `args: ["-c", <команда>]`, `cwd`, `env`, `outputByteLimit`) → `terminal/wait_for_exit` → `terminal/output` → `terminal/release`; `terminal/release` — всегда, включая ошибки, отмену и таймаут (ACP-9, ENV-7);
- метод, для которого клиент не объявил capability, → `Err(unsupported)` без запроса (`exec` — `ExecErrorCode.shellUnavailable`);
- ошибка JSON-RPC `-32002` → `notFound`, прочие → `io` с текстом клиента, таймаут → `io` «… (timed out)», разрыв соединения → `io` «client connection lost».

`AcpPermissionGate` SHALL запрашивать решение через `session/request_permission` по §7.8: `toolCall` с `rawInput`, `locations` и `diff`, варианты `allow_once`, `allow_always` (только если предложен), `reject_once`, `reject_always`. Запрос с `PermissionRequest.criticalLabel` — критическая команда (§7.6) или правка конфигурации агента (§7.6.1, PERM-11) — SHALL нести `toolCall._meta.codelab = {"critical": true, "label": <criticalLabel>}`; запрос без метки SHALL NOT нести `_meta.codelab.critical` (design.md change `mark-agent-config-edits-critical`, D5). Неизвестный `optionId`, ошибка JSON-RPC и разрыв → отказ с логом; `cancelled` и отмена хода → `cancelled`.

#### Scenario: Ошибка ожидания терминала
- **WHEN** клиент отвечает ошибкой на `terminal/wait_for_exit`
- **THEN** агент всё равно отправляет `terminal/release`, а результат `exec` — ошибка

#### Scenario: Клиент без терминала
- **WHEN** клиент не объявил `terminal`, а модель зовёт `exec`
- **THEN** ни одного кадра `terminal/*` не уходит, вызов завершается ошибкой

#### Scenario: Правка конфигурации агента помечена критической
- **WHEN** в режиме `bypass` модель вызывает `write` с путём `.codelab/config.yaml`, а клиент отвечает `reject_once`
- **THEN** `session/request_permission` содержит `toolCall._meta.codelab` `{"critical": true, "label": "write to agent configuration"}`, первый блок `content` — текст `agent configuration: .codelab/config.yaml`, варианты — `allow_once`, `reject_once`, `reject_always`; `fs/write_text_file` не отправляется, `tool_call_update` — `failed` с `_meta.codelab.outcome: rejected` (`acp/permission-agent-config-edit-critical`)

#### Scenario: Обычный вопрос без пометки
- **WHEN** в режиме `standard` модель вызывает `write NOTES.md`
- **THEN** `toolCall` в `session/request_permission` не содержит `_meta.codelab.critical` (`acp/tool-write-permission-diff`)
