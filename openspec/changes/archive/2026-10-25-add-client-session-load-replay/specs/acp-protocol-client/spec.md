## MODIFIED Requirements

### Requirement: Настройка сессии
CodeLab SHALL поддерживать `session/new` и SHALL вызывать `session/load` только когда доступен `agentCapabilities.loadSession`. При `session/load` CodeLab SHALL восстанавливать историю, которую агент повторяет уведомлениями `session/update` до ответа на запрос, и SHALL NOT считать сессию загруженной до ответа.

#### Scenario: Создаётся новая сессия
- **WHEN** пользователь создаёт сессию
- **THEN** CodeLab отправляет `session/new` с абсолютным `cwd` и сохраняет полученный `sessionId`

#### Scenario: Load session не поддерживается
- **WHEN** агент не заявляет `loadSession`
- **THEN** CodeLab не предлагает и не вызывает `session/load`

#### Scenario: Загруженная сессия показывает повторённую историю
- **WHEN** агент в ответ на `session/load` присылает до ответа `user_message_chunk`, `tool_call` с итоговым статусом и `agent_message_chunk`, а затем отвечает на запрос
- **THEN** после ответа сессия содержит завершённый ход с репликой пользователя в prompt, вызовом инструмента с его статусом и ответом агента, и ни один ход реплея не показан выполняющимся

#### Scenario: Границы ходов в реплее
- **WHEN** в реплее `user_message_chunk` следует за ответом агента
- **THEN** CodeLab начинает новый ход, а подряд идущие `user_message_chunk` объединяет в одну реплику пользователя

#### Scenario: Сессионные обновления реплея
- **WHEN** в реплее приходят `current_mode_update`, `config_option_update`, `available_commands_update` и `session_info_update`
- **THEN** CodeLab применяет их к сессии (текущий режим, опции, команды, заголовок), а режимы и опции из ответа на `session/load` имеют приоритет

#### Scenario: Ошибка session/load
- **WHEN** агент отвечает на `session/load` ошибкой после части реплея
- **THEN** CodeLab не создаёт сессию и отбрасывает накопленные обновления реплея

#### Scenario: Режим и заголовок вне хода
- **WHEN** агент присылает `current_mode_update` или `session_info_update` при отсутствии активного хода
- **THEN** CodeLab обновляет текущий режим или заголовок сессии; `session_info_update` без `title` заголовок не меняет
