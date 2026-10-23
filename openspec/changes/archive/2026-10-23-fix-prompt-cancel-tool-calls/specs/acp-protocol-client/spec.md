## ADDED Requirements

### Requirement: Отмена prompt turn
CodeLab SHALL после отправки `session/cancel` держать prompt turn в нетерминальном состоянии «отменяется» до ответа агента на `session/prompt` этого хода (`05-Prompt Turn.md#cancellation`). В этом состоянии CodeLab SHALL применять к ходу входящие `session/update`, SHALL NOT начинать в сессии новый prompt turn и SHALL отвечать `cancelled` на `session/request_permission`. Незавершённые вызовы инструментов хода (`pending`, `in_progress`) CodeLab SHALL пометить отменёнными в момент отправки `session/cancel`; так как в ACP `ToolCallStatus` нет значения `cancelled`, отменённый вызов хранится со статусом `failed` и признаком отмены клиентом.

#### Scenario: Незавершённые вызовы помечаются при отправке cancel
- **WHEN** пользователь отменяет ход, в котором есть вызов инструмента в статусе `in_progress` и вызов в статусе `completed`
- **THEN** CodeLab отправляет `session/cancel`, переводит ход в «отменяется», вызов `in_progress` получает статус `failed` с признаком отмены клиентом, а вызов `completed` не меняется

#### Scenario: Поздний tool_call_update того же хода принимается
- **WHEN** после `session/cancel`, но до ответа на `session/prompt` агент присылает `tool_call_update` для вызова этого хода с новым содержимым и статусом `failed`
- **THEN** CodeLab применяет содержимое и статус к вызову, вызов остаётся отменённым

#### Scenario: Нетерминальный статус не возвращает отменённый вызов в работу
- **WHEN** после `session/cancel` агент присылает для отменённого вызова `tool_call_update` со статусом `in_progress`
- **THEN** CodeLab применяет остальные поля обновления, но статус вызова остаётся `failed` с признаком отмены клиентом

#### Scenario: Вызов успел завершиться
- **WHEN** после `session/cancel` агент присылает для отменённого вызова `tool_call_update` со статусом `completed`
- **THEN** CodeLab переводит вызов в `completed` и снимает признак отмены клиентом

#### Scenario: Ответ на session/prompt завершает отмену
- **WHEN** агент отвечает на `session/prompt` отменяемого хода со `stopReason`
- **THEN** CodeLab переводит ход в терминальный статус по `stopReason` (`cancelled` для `cancelled`), а сессия снова может начать новый ход

#### Scenario: Обновление после ответа на session/prompt отбрасывается
- **WHEN** `session/update` приходит после ответа на `session/prompt` отменённого хода, и новый ход ещё не начат
- **THEN** CodeLab не меняет состояние завершённого хода

#### Scenario: Новый ход не начинается до ответа агента
- **WHEN** ход в сессии отменяется и ответ на его `session/prompt` ещё не пришёл, а клиент пытается начать новый prompt turn в этой сессии
- **THEN** CodeLab отклоняет начало хода без отправки `session/prompt`

#### Scenario: Повторная отмена идемпотентна
- **WHEN** пользователь повторно отменяет ход, который уже «отменяется»
- **THEN** CodeLab не отправляет повторный `session/cancel` и возвращает тот же ход

#### Scenario: Запрос разрешения во время отмены
- **WHEN** агент присылает `session/request_permission`, пока ход «отменяется»
- **THEN** CodeLab сразу отвечает исходом `cancelled` и не создаёт approval
