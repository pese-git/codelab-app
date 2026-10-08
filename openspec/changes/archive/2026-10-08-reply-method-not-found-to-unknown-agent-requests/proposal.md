## Why

Когда агент присылает **запрос** (JSON-RPC request с `id`), метод которого CodeLab не обрабатывает, клиент сегодня ничего не отвечает: в `AcpClientApplication._handleInboundMessage` ветка `JsonRpcRequest()` просто делает `break`. По JSON-RPC 2.0 на каждый запрос обязан прийти ответ, а ACP прямо описывает случай нераспознанного кастомного метода (`docs/acp/protocol/15-Extensibility.md`, «Custom Requests»): получатель отвечает стандартной ошибкой `-32601 Method not found`. Агент, который ждёт ответа на такой запрос, остаётся в ожидании навсегда (зависший turn / недоступная фича), а в логе CodeLab нет ни следа этого.

Реальные агенты уже шлют нестандартные методы с префиксом `_` (например, уведомление `_auth/status_update` у `@agentclientprotocol/claude-agent-acp`); запросы такого рода — вопрос времени. Ограничение зафиксировано в `docs/integrations/claude-code.md`, разд. 5, п. 2.

## What Changes

- На любой входящий запрос агента, метод которого CodeLab не обрабатывает (кастомный `_vendor/...`, неизвестный стандартный метод, а также метод направления клиент→агент, присланный агентом по ошибке), клиент отвечает ошибкой JSON-RPC `-32601` «Method not found» с тем же `id`.
- Отказ фиксируется диагностикой уровня WARNING (метод и `requestId`; параметры запроса не логируются — они могут содержать секреты).
- Входящие **уведомления** с неизвестным методом по-прежнему игнорируются без ответа (JSON-RPC запрещает отвечать на notification); их приём не ошибка.
- **BREAKING**: нет. Меняется только реакция на запросы, которые CodeLab не поддерживает.

## Capabilities

### New Capabilities
_Нет._

### Modified Capabilities
- `acp-protocol-client`: добавляется требование об ответе `Method not found` на неподдерживаемые запросы агента.

## Impact

- `packages/dart/acp_client_core/lib/src/application/acp_client_application.dart` (ветка `JsonRpcRequest()` в `_handleInboundMessage`) и тесты `acp_client_core`.
- `docs/integrations/claude-code.md`: снимается ограничение «неизвестный запрос остаётся без ответа».
- Публичный API пакетов, зависимости и ACP-контракты (то, что CodeLab отправляет сам) не меняются.
