## MODIFIED Requirements

### Requirement: Жизненный цикл prompt turn
CodeLab SHALL поддерживать `session/prompt`, потоковые `session/update`, `session/request_permission`, `session/cancel` и финальный ответ `session/prompt` со `stopReason`. Уведомление `session/update` с незнакомым видом обновления (`sessionUpdate`) SHALL пропускаться без ошибки и без изменения состояния сессии.

Payload пропущенного уведомления SHALL попадать только в трассу `category=protocol` и только при базовой политике payload `full` (structured-logging «Protocol tracing выключен по умолчанию в release»). При `metadataOnly` ни одна запись журнала о пропуске payload SHALL NOT нести.

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

#### Scenario: Payload пропущенного обновления при политике full
- **WHEN** CodeLab с базовой политикой payload `full` пропускает `session/update` незнакомого вида
- **THEN** CodeLab дополнительно записывает в журнал `category=protocol` событие `Skipped unsupported ACP session update.` с видом обновления, идентификатором сессии и полным payload уведомления после маскирования секретов, а application-журнал (console, `application.log`, сервер логов) payload не получает (`payload_policy_diagnostics_test.dart`, «full: запись с payload в категории protocol»)

#### Scenario: Payload пропущенного обновления при политике metadataOnly
- **WHEN** CodeLab с базовой политикой payload `metadataOnly` пропускает `session/update` незнакомого вида с текстом в обновлении
- **THEN** ни одна запись `Skipped unsupported ACP session update.` не содержит `payload`, а текст обновления не виден ни в журнале, ни в диагностике (`payload_policy_diagnostics_test.dart`, «metadataOnly: запись без payload»)
