## Why

`fix-acp-capability-forward-compat` убрало падение `initialize` на незнакомых capability-флагах, но намеренно оставило строгой всю остальную валидацию. Ручная проверка с реальным агентом (`@zed-industries/claude-code-acp` 0.16.2) показала, что этого недостаточно: подключение проходит (`Ready`), а `session/new` падает —

```
Failed to decode ACP response for session/new.
newSessionResponse contains unsupported root field "models"; use _meta for extensions.
```

Агент отвечает `{sessionId, models: {availableModels, currentModelId}, modes: {…}}`; `models` — расширение агента, которого нет ни в нашей модели, ни в вендоренной спеке `docs/acp/`. Похожий сбой уже встречался на `session/set_config_option` (корневое поле `modes` в ответе). Сессию создать нельзя — CodeLab не работает с реальным агентом, пока он объявляет хоть одно поле, которого мы не знаем.

Строгость на **ответах агента** ничего не защищает: ответ приходит от внешнего процесса, клиент не может «починить» агента отказом, а теряет при этом весь корректный остаток ответа (в примере — валидный `sessionId` уже созданной сессии). Строгость нужна на том, что отправляем мы сами, и там, где неожиданное поле — сигнал о ошибке протокольного потока.

## What Changes

- Декодирование **result-объектов ответов агента** (`decodeAcpResponseResult` — единственная точка входа для ответов в `acp_client_core`) перестаёт отвергать незнакомые корневые поля на любом уровне вложенности: поле молча игнорируется, не читается и не сохраняется. Затрагивает `initialize` (включая корень `InitializeResponse`), `session/new`, `session/load`, `session/list`, `session/set_config_option`, `session/prompt`.
- Структурная валидация не ослабляется: ответ по-прежнему обязан быть JSON-объектом, обязательные поля обязательны, типы и значения полей, которые CodeLab знает, проверяются как раньше (`stopReason`, discriminators, диапазоны и т.д.).
- Остаются строгими без изменений: параметры запросов, которые CodeLab **отправляет** агенту; параметры запросов и уведомлений, которые **присылает агент** (`session/update`, `session/request_permission`, `fs/*`, `terminal/*`) — это runtime-поток, а не ответ на наш вызов; прямой `Model.fromJson(...)` вне `decodeAcpResponseResult`.
- Незнакомые поля не интерпретируются: `models` НЕ становится поддержкой выбора модели (отдельный change, если понадобится) — это только «не падать».
- **BREAKING**: нет. Меняется только реакция на поля, которых CodeLab сегодня не знает.

## Capabilities

### New Capabilities
_Нет._

### Modified Capabilities
- `acp-protocol-client`: требование «Обработка сообщений JSON-RPC 2.0» получает правило о терпимости к незнакомым полям в ответах агента; требование «Инициализация и capabilities» уточняется — терпимость распространяется и на корень `InitializeResponse` (сценарий «Незнакомое поле вне capability-объектов», введённый `fix-acp-capability-forward-compat`, сужается до запросов и runtime-сообщений).

## Impact

- `packages/dart/acp_protocol`: `acp_validation.dart` (scoped-терпимость), `acp_method_codec.dart` (`decodeAcpResult`/`decodeAcpResponseResult`); тесты в `test/`.
- `packages/dart/acp_client_core`: изменений кода нет (использует `decodeAcpResponseResult`), нужен регрессионный тест на `session/new` с `models`.
- Порядок: change опирается на helper и тесты из `fix-acp-capability-forward-compat` (PR #2) — архивировать после него.
- Зависимости, публичный API пакетов, ACP-контракты (то, что CodeLab отправляет) не меняются.
