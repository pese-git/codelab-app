## MODIFIED Requirements

### Requirement: Жизненный цикл prompt turn
CodeLab SHALL поддерживать `session/prompt`, потоковые `session/update`, `session/request_permission`, `session/cancel` и финальный ответ `session/prompt` со `stopReason`. Уведомление `session/update` с незнакомым видом обновления (`sessionUpdate`) SHALL пропускаться без ошибки и без изменения состояния сессии.

#### Scenario: Prompt стримит обновления
- **WHEN** пользователь отправляет prompt
- **THEN** CodeLab отправляет `session/prompt` и рендерит входящие уведомления `session/update` как типизированные события таймлайна

#### Scenario: Prompt завершается
- **WHEN** агент отвечает на `session/prompt` со `stopReason`
- **THEN** CodeLab помечает активный prompt turn как completed, failed, refused, maxed или cancelled в соответствии со stop reason

#### Scenario: Ответ агента с дополнительным полем доходит до таймлайна
- **WHEN** агент во время prompt turn присылает `agent_message_chunk` с корневым полем, которого нет в типизированной модели (например, `messageId`)
- **THEN** CodeLab добавляет текст чанка в ответ агента в таймлайне так же, как для чанка без этого поля

#### Scenario: Незнакомый вид обновления пропускается
- **WHEN** агент присылает `session/update`, чей `sessionUpdate` не входит в виды, известные CodeLab (например, `usage_update`)
- **THEN** CodeLab не меняет состояние сессии, не создаёт диагностику уровня error, записывает в application-журнал одну запись уровня DEBUG с видом обновления и идентификатором сессии без содержимого, и продолжает обрабатывать последующие обновления и ответ на `session/prompt`

#### Scenario: Payload пропущенного обновления доступен только в protocol-трассировке
- **WHEN** CodeLab пропускает `session/update` незнакомого вида
- **THEN** CodeLab дополнительно записывает в developer-only журнал `category=protocol` событие с тем же текстом, видом обновления, идентификатором сессии и полным payload уведомления с маскированием секретов, а application-журнал (console, `application.log`, сервер логов) payload не получает
