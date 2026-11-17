## MODIFIED Requirements

### Requirement: Политика одобрений headless
Запросы одобрения в headless SHALL решаться политикой `--approve` без чтения stdin (по умолчанию `reject`):
- `reject` — вариант `reject_once`;
- `read-only` — `allow_once` только для запроса, у вызова которого вид `read` и уровень риска одобрения (`PendingApprovalView.risk`) — `readOnly`; любой другой запрос, в том числе вызов вида `read`, чей запрос разрешения пришёл с незнакомым видом, с видом `switch_mode` или с более опасным видом либо содержимым (риск выше `readOnly`), — `reject_once` (design.md change `tolerate-unknown-tool-kind`, D5, D9);
- `allow-all` — `allow_once` для всех запросов, кроме запросов с `PendingApprovalView.critical` (`_meta.codelab.critical: true` в запросе или его `toolCall`), которые получают `reject_once`; при старте в stderr печатается одно предупреждение.

Если агент не предложил нужный вариант, запрос SHALL получать первый предложенный вариант вида `reject_*`, а без таковых — исход `cancelled` через отмену хода. Каждое решение SHALL давать одну строку в stderr с инструментом, решением и причиной (`policy`, `critical`, `cancelled`).

#### Scenario: Отказ по умолчанию
- **WHEN** агент запрашивает одобрение `exec`, `--approve` не задан
- **THEN** агент получает `optionId` варианта `reject_once`, в stderr — строка решения

#### Scenario: allow-all и критичный запрос
- **WHEN** `--approve allow-all`, и агент присылает запрос с `_meta.codelab.critical: true`
- **THEN** агент получает `reject_once`, строка stderr называет причину `critical`

#### Scenario: read-only разрешает чтение
- **WHEN** `--approve read-only`, и агент запрашивает одобрение вызова вида `read` с уровнем риска `readOnly`
- **THEN** агент получает `allow_once`

#### Scenario: read-only отклоняет чтение, запрос на которое пришёл с незнакомым видом
- **WHEN** `--approve read-only`, агент прислал `tool_call` вида `read`, затем `session/request_permission` для него с `toolCall.kind: "future_kind"` (вид записи `read`, риск `unknown`)
- **THEN** агент получает `reject_once`, строка stderr называет причину `policy`

#### Scenario: read-only отклоняет чтение, запрос на которое пришёл с switch_mode
- **WHEN** `--approve read-only`, агент прислал `tool_call` вида `read`, затем `session/request_permission` для него с `toolCall.kind: "switch_mode"`
- **THEN** агент получает `reject_once`

#### Scenario: read-only отклоняет чтение с повышенным риском
- **WHEN** `--approve read-only`, агент прислал `tool_call` вида `read`, затем `session/request_permission` для него с `toolCall.kind: "execute"` (риск `shell`)
- **THEN** агент получает `reject_once`
