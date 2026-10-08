## Why

Прогон реального prompt turn на `@agentclientprotocol/claude-agent-acp` 0.88.0 (2026-10-09, сырой обмен по stdio, 10 входящих сообщений пропущены через `acp_protocol`) показал: ответ агента не отображается. Агент присылает

- `session/update` / `agent_message_chunk` с дополнительным корневым полем `messageId` — сам текст ответа (`pong`) отвергается как `unsupported root field "messageId"`;
- `session/update` / `usage_update` (`used`, `size`, `cost`) — вид обновления, которого нет в вендоренной спеке `docs/acp/`; отвергается как неподдерживаемый.

`AcpClientApplication._handleSessionUpdate` превращает ошибку decode в диагностику уровня `error` и выбрасывает обновление: пользователь не видит ответа модели, а журнал заполняется ошибками. Это тот же класс сбоя, что закрыли `fix-acp-capability-forward-compat` и `tolerate-unknown-agent-response-fields` для ответов на запросы; для потока `session/update` строгость тогда оставили «до фактического сбоя» (design.md того change, Open Questions) — сбой теперь воспроизведён.

Строгость здесь ничего не защищает: `session/update` — односторонний поток от внешнего процесса, клиент не может заставить агента слать иначе, а отказ от сообщения целиком теряет корректную часть (текст ответа).

## What Changes

- Декодирование уведомления `session/update` (`decodeAcpNotificationParams`) перестаёт отвергать незнакомые корневые поля на любом уровне вложенности (корень уведомления, `update`, content-блоки, tool call, plan entries и т.д.): поле игнорируется, не читается и не сохраняется. Тот же zone-механизм, что и для result.
- Обновление с незнакомым значением `sessionUpdate` (например, `usage_update`) SHALL пропускаться клиентом без ошибки: состояние сессии не меняется, в журнал пишется одна запись уровня DEBUG (вид обновления и `sessionId`, без содержимого). Известные виды обновлений обрабатываются как раньше.
- Структурная валидация известных видов обновлений не ослабляется: не-объект, отсутствие обязательного поля, неверный тип, неизвестный discriminator внутри известного вида (`type` content-блока, `status`/`kind` tool call и т.п.) остаются ошибкой.
- Остаются строгими без изменений: параметры запросов, которые CodeLab отправляет; параметры запросов агента (`session/request_permission`, `fs/*`, `terminal/*`) — они требуют ответа и/или влияют на безопасность; прямой `decodeAcpParams` и `Model.fromJson`.
- Незнакомое не интерпретируется: `messageId` не становится идентификатором сообщения, `usage_update` не становится индикатором использования контекста — это отдельные changes, если понадобятся.
- **BREAKING**: нет.

## Capabilities

### New Capabilities
_Нет._

### Modified Capabilities
- `acp-protocol-client`: требование «Обработка сообщений JSON-RPC 2.0» — сценарий «Незнакомое поле вне ответов агента» сужается (`session/update` выводится из строгого набора), добавляется сценарий для `session/update`; требование «Жизненный цикл prompt turn» получает сценарии про незнакомое поле и незнакомый вид обновления.

## Impact

- `packages/dart/acp_protocol`: `acp_method_codec.dart` (`decodeAcpNotificationParams` для `session/update`), `session_update.dart` (определение «неизвестный вид обновления»); тесты в `test/`.
- `packages/dart/acp_client_core`: `acp_client_application.dart` (`_handleSessionUpdate`); тесты на реальную последовательность сообщений 0.88.0.
- `docs/integrations/claude-code.md`: разд. 3.5, 4, 5 — отражают новое поведение.
- Зависимости, публичные ACP-контракты (то, что CodeLab отправляет) и данные не меняются.
