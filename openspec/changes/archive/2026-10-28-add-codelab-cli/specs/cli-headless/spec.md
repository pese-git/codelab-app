## ADDED Requirements

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
- `read-only` — `allow_once` для вызовов вида `read`, остальное — `reject_once`;
- `allow-all` — `allow_once` для всех запросов, кроме запросов с `PendingApprovalView.critical` (`_meta.codelab.critical: true` в запросе или его `toolCall`), которые получают `reject_once`; при старте в stderr печатается одно предупреждение.

Если агент не предложил нужный вариант, запрос SHALL получать первый предложенный вариант вида `reject_*`, а без таковых — исход `cancelled` через отмену хода. Каждое решение SHALL давать одну строку в stderr с инструментом, решением и причиной (`policy`, `critical`, `cancelled`).

#### Scenario: Отказ по умолчанию
- **WHEN** агент запрашивает одобрение `exec`, `--approve` не задан
- **THEN** агент получает `optionId` варианта `reject_once`, в stderr — строка решения

#### Scenario: allow-all и критичный запрос
- **WHEN** `--approve allow-all`, и агент присылает запрос с `_meta.codelab.critical: true`
- **THEN** агент получает `reject_once`, строка stderr называет причину `critical`

#### Scenario: read-only разрешает чтение
- **WHEN** `--approve read-only`, и агент запрашивает одобрение вызова вида `read`
- **THEN** агент получает `allow_once`

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
