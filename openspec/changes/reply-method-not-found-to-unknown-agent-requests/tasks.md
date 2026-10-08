## 1. Реализация

- [x] 1.1 В `acp_client_application.dart` (`_handleInboundMessage`) разделить финальные case'ы: `JsonRpcNotification()` по-прежнему `break`, а `JsonRpcRequest()` отправляет `_sendAcpMethodError(request.id, method: request.method, error: AcpProtocolError.unknownMethod(request.method))`
- [x] 1.2 Перед отправкой записать диагностику WARNING (`source: 'application.protocol'`, контекст — только `method` и `requestId`, без `params`)

## 2. Тесты `acp_client_core`

- [x] 2.1 Кастомный запрос `_vendor/feature` от агента → в `transport.sentMessages` ответ с `error.code == -32601` и тем же `id`
- [x] 2.2 Неизвестный стандартный метод → то же
- [x] 2.3 После отказа соединение остаётся `Ready`, следующий поддерживаемый запрос/ответ обрабатывается как обычно
- [x] 2.4 Неизвестное уведомление (`_auth/status_update`) → ничего не отправлено, состояние не изменилось
- [x] 2.5 Диагностика отказа не содержит `params` запроса

## 3. Документация

- [x] 3.1 В `docs/integrations/claude-code.md` убрать ограничение «неизвестный запрос остаётся без ответа» (разд. 5, п. 2) и описать новое поведение рядом с `_auth/status_update` (разд. 3.4)

## 4. Проверка

- [x] 4.1 `fvm dart format`, `fvm dart analyze`, `fvm dart test` для `acp_client_core` и `acp_protocol`; `fvm flutter test` для `codelab_app`
- [x] 4.2 `openspec validate reply-method-not-found-to-unknown-agent-requests --strict`
