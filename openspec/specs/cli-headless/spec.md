# cli-headless Specification

## Purpose
Headless-режим `codelab -p` для скриптов и CI: один ход без интерактива, ответ — в stdout, диагностика — в stderr, политика одобрений `--approve` без вопросов, код выхода — из причины остановки, а не из текста (H-01, H-02). Устройство — `docs/architecture/proposals/dart-agent-and-clients/09-11-stage-6-cli-mvp.md`; формат `stream-json` — отдельный change (§12.5).
## Requirements
### Requirement: Источники промпта headless
`codelab -p "<текст>"` SHALL запускать headless-режим: одна сессия, один промпт, без интерактива. Источники промпта (H-01):
- `-p "<текст>"` — текст как есть, файлом не считается никогда;
- `-f <файл>` — содержимое файла в UTF-8; `-f -` — содержимое stdin; ошибка чтения — код `64`;
- без `-p` и `-f`, если stdin не TTY — содержимое stdin;
- позиционные аргументы вместе с `-p`/`-f`/stdin-промптом НЕ SHALL допускаться (код `64`); без них позиционные аргументы REPL — первое сообщение REPL.

Пустой промпт после чтения SHALL давать код `64` и `No prompt.`. Headless SHALL создавать новую сессию в `--cwd` или загружать её по `--resume <id>` или `--continue`, применять `--model` и `--mode` через `session/set_config_option` до промпта; реплей истории загруженной сессии в stdout НЕ SHALL выводиться.

#### Scenario: Промпт из -p
- **WHEN** запускается `codelab -p hello -a 'stdio:<scripted-агент>'`
- **THEN** агент получает `session/prompt` с текстом `hello`, ответ печатается в stdout, код `0`

#### Scenario: Промпт из stdin
- **WHEN** запускается `echo hello | codelab -a <профиль>`
- **THEN** агент получает `session/prompt` с текстом `hello`

#### Scenario: Нет промпта
- **WHEN** запускается `codelab -p ''`
- **THEN** код `64`, stdout пуст, в stderr — `No prompt.`

### Requirement: Вывод headless
stdout в headless SHALL содержать только текст ответов агента (`agent_message_chunk`) хода байт в байт как пришёл, без ANSI и без разбора markdown, с переводом строки в конце, если ответ им не кончается. Мысли НЕ SHALL печататься. Строки инструментов, заметки, решения политики одобрения и диагностика SHALL идти в stderr; `--verbose` SHALL добавлять в stderr диагностику соединения (`ClientWorkspace.diagnostics`, уже с редакцией секретов). Значение `CODELAB_AGENT_TOKEN` НЕ SHALL попадать ни в stdout, ни в stderr.

#### Scenario: Ответ отдельно от диагностики
- **WHEN** агент в ходе вызывает инструмент и отвечает `done`
- **THEN** stdout равен `done\n`, строка инструмента — в stderr

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

### Requirement: Коды выхода headless
Код выхода headless SHALL вычисляться одним модулем (`lib/src/headless/exit_codes.dart`) из ответа `session/prompt`, ошибок и сигналов, а не из текста транскрипта (H-02):
- `0` — `stopReason: end_turn` и ответ не пустой;
- `1` — JSON-RPC ошибка на `session/prompt`, `end_turn` без единого `agent_message_chunk`, `max_tokens`, `max_turn_requests`, `refusal`, не удалось подключиться к агенту, агент завершился или соединение оборвалось;
- `64` — ошибка использования: неизвестный флаг или подкоманда, нет промпта, неверное значение `--agent`, нет профиля;
- `130` — SIGINT или истёкший `--timeout` (`stopReason: cancelled`);
- `143` — SIGTERM.

`--timeout <длительность>` (`90s`, `10m`) SHALL отправлять `session/cancel` по истечении и печатать в stderr `timeout`. После ответа headless SHALL закрывать транспорт и завершать процесс агента.

#### Scenario: Ошибка провайдера
- **WHEN** агент отвечает на `session/prompt` JSON-RPC ошибкой `-32603`
- **THEN** код выхода `1`, в stderr — сообщение ошибки

#### Scenario: Пустой ответ
- **WHEN** агент отвечает `end_turn` без `agent_message_chunk`
- **THEN** код выхода `1`, в stderr — заметка о пустом ответе

#### Scenario: Таймаут
- **WHEN** `--timeout 1s`, а агент не отвечает
- **THEN** агент получает `session/cancel`, код выхода `130`

#### Scenario: SIGTERM
- **WHEN** headless получает SIGTERM во время хода
- **THEN** агент получает `session/cancel`, транспорт закрыт, код выхода `143`

### Requirement: Операции со списком задач в headless
В headless (`-p`) элемент `TaskOpsItem` (acp-client-kit «Операции со списком задач в ленте») SHALL печататься в stderr одной строкой с текстом kit — например `Tasks #1–#4 added to the plan` — вместо строк вызовов, которые он заменяет (design.md change `add-subagents-and-tasks`, D27, D35). Строка SHALL печататься ровно один раз на элемент, когда элемент перестал расти: после него в транскрипте появился другой элемент или ход завершился. Промежуточные состояния сливающегося элемента НЕ SHALL печататься. Неуспешная операция печатается обычной строкой вызова с причиной. stdout при этом не меняется (требование «Вывод headless»).

#### Scenario: Четыре создания подряд в headless
- **WHEN** в `-p` модель создаёт четыре пункта подряд, затем отвечает `done`
- **THEN** stderr содержит ровно одну строку `Tasks #1–#4 added to the plan` и не содержит строк `Task #1 added to the plan`, `Tasks #1–#2 added to the plan`, `Tasks #1–#3 added to the plan`; stdout равен `done\n`

#### Scenario: Операции, разделённые вызовом
- **WHEN** в `-p` модель создаёт `#1`, вызывает `read`, создаёт `#2`, ход завершается
- **THEN** stderr содержит по порядку `Task #1 added to the plan`, строку `read` и `Task #2 added to the plan`, каждую — один раз

