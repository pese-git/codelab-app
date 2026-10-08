## 1. Новый лояльный decode-helper

- [x] 1.1 Добавить `requireAcpCapabilityObject(Object? value, {required String path})` в `packages/dart/acp_protocol/lib/src/acp/acp_validation.dart` — проверяет только, что значение является JSON-объектом (`requireJsonObject`), без вызова `requireOnlyRootKeys`
- [x] 1.2 Задокументировать разницу с `requireAcpObject` прямо в doc-комментарии helper'а (capability-объекты initialize vs. runtime ACP-сообщения) — см. design.md, Decisions

## 2. Переключить capability-модели `initialize.dart`

- [x] 2.1 `AgentCapabilities.fromJson` — заменить `requireAcpObject(..., allowedKeys: {...})` на `requireAcpCapabilityObject(..., path: ...)`, убрать `allowedKeys`
- [x] 2.2 `McpCapabilities.fromJson` — то же самое
- [x] 2.3 `PromptCapabilities.fromJson` — то же самое
- [x] 2.4 `SessionCapabilities.fromJson` — то же самое (устраняет исходный сбой на `fork`/`resume`)
- [x] 2.5 `SessionListCapabilities.fromJson` — то же самое
- [x] 2.6 `ClientCapabilities.fromJson` — то же самое
- [x] 2.7 `FileSystemCapabilities.fromJson` — то же самое
- [x] 2.8 Убедиться, что `Implementation.fromJson`, `AuthMethod.fromJson`, `InitializeRequest.fromJson`, `InitializeResponse.fromJson` остаются на строгом `requireAcpObject` без изменений (см. design.md, Non-Goals)

## 3. Тесты

- [x] 3.1 Новый тест: `initialize`-ответ с незнакомым полем внутри `agentCapabilities.sessionCapabilities` (например `fork`/`resume`, как у реального `@zed-industries/claude-code-acp`) decode'ится успешно, известные поля (`list`) читаются корректно
- [x] 3.2 Новый тест: незнакомое поле внутри `agentCapabilities` верхнего уровня (не внутри `sessionCapabilities`) тоже decode'ится без ошибки
- [x] 3.3 Новый тест: незнакомое поле на верхнем уровне самого `InitializeResponse` (не внутри `agentCapabilities`) по-прежнему приводит к `JsonRpcProtocolException.invalidShape` — подтверждает, что строгая проверка верхнего уровня не ослаблена
- [x] 3.4 Новый тест: незнакомое поле в НЕ-capability ACP-сообщении (например `session/update` или `tool_call`) по-прежнему приводит к ошибке — подтверждает, что область изменения не расширилась за пределы `initialize.dart`
- [x] 3.5 Убедиться, что существующие тесты `packages/dart/acp_protocol/test/` на строгую валидацию (session/prompt/tool_call/permission/fs/terminal) не сломаны

## 4. Проверка против реального агента

- [x] 4.1 (на уровне протокола: настоящий `initialize`-ответ кэшированного `@zed-industries/claude-code-acp` — `sessionCapabilities: {fork, list, resume}` — декодируется новым кодом без ошибки; сквозное подключение через UI CodeLab не проверялось) Вручную подключиться к `@zed-industries/claude-code-acp` через CodeLab (stdio, `npx --yes @zed-industries/claude-code-acp` или закешированный бинарь) и убедиться, что `initialize` больше не падает, соединение переходит в `Connected`
- [ ] 4.2 Создать сессию и отправить простой read-only запрос реальному агенту, убедиться, что turn проходит штатно (см. add-multi-session-concurrency для похожего протокола ручной проверки)

## 5. Проверка

- [x] 5.1 `fvm dart run melos run format` (эквивалент: `fvm dart format` по затронутому пакету — без изменений)
- [x] 5.2 `fvm dart run melos run analyze` (эквивалент: `fvm dart analyze` по `acp_protocol`, `acp_client_core`, `acp_transports` — чисто)
- [x] 5.3 `fvm dart run melos run test` (эквивалент по пакетам: `acp_protocol` 83, `acp_client_core` 96, `acp_transports` 15, `codelab_app` 86 — все проходят)
- [x] 5.4 `fvm dart test packages/dart/acp_protocol/test` (протокольный пакет отдельно, для быстрой обратной связи)
