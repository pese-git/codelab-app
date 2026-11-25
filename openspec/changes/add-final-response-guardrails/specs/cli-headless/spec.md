## MODIFIED Requirements

### Requirement: Коды выхода headless
Код выхода headless SHALL вычисляться одним модулем (`lib/src/exit_codes.dart`) из ответа `session/prompt`, ошибок и сигналов, а не из текста транскрипта (H-02):
- `0` — `stopReason: end_turn`, ответ не пустой и без `_meta.codelab.held`;
- `1` — JSON-RPC ошибка на `session/prompt`, `end_turn` без единого `agent_message_chunk`, `end_turn` с `_meta.codelab.held` (ответ удержан финальными проверками агента; design.md change `add-final-response-guardrails`, D7), `max_tokens`, `max_turn_requests`, `refusal`, не удалось подключиться к агенту, агент завершился или соединение оборвалось;
- `64` — ошибка использования: неизвестный флаг или подкоманда, нет промпта, неверное значение `--agent`, нет профиля;
- `130` — SIGINT или истёкший `--timeout` (`stopReason: cancelled`);
- `143` — SIGTERM.

При `end_turn` с `_meta.codelab.held` ответ агента SHALL печататься в stdout как обычно, а в stderr SHALL печататься строка `Response held: <reason>` с причиной из итога хода.

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

#### Scenario: Ответ удержан
- **WHEN** агент отвечает `end_turn` с `_meta.codelab.held: "revision limit reached: [unverified_success] …"` после `agent_message_chunk` с текстом `All tests pass.`
- **THEN** stdout содержит `All tests pass.`, stderr — `Response held: revision limit reached: [unverified_success] …`, код выхода `1`
