## ADDED Requirements

### Requirement: Гейт передачи данных провайдеру
Ядро SHALL экспортировать из основного бареля `ProviderEndpoint` (`providerId`, `api`, `baseUrl`; `ProviderEndpoint.of(ProviderConfig)`), тип `SharingGate = Future<bool> Function(ProviderEndpoint endpoint, Future<void> cancelled)` и декоратор `withSharingGate(StreamFunction inner, {required ProviderEndpoint? Function(String providerId) endpointOf, required SharingGate gate, required Logger logger})` (`agent-core-architecture` §2.10.6, LLM-17; design.md change `add-ai-data-sharing-consent`, D4).

Декоратор SHALL для каждого запроса:
- при `endpointOf(model.provider) == null` вызывать `inner` без гейта;
- иначе вызывать гейт один раз и до его ответа `inner` НЕ SHALL вызываться;
- при ответе `true` отдавать поток `inner` без изменений;
- при ответе `false` завершать поток `ErrorEvent` класса `badRequest` с текстом `<providerId>: the user did not allow sending data to this provider` и писать лог `llm.sharing.denied {provider}`;
- при исключении гейта завершать поток `ErrorEvent` `badRequest` с текстом `<providerId>: the data sharing check failed` и писать `llm.sharing.gate_failed {provider, error_class}` без текста исключения;
- при отмене `CancelToken` во время ожидания завершать поток `aborted` в пределах одного цикла событий (LLM-7) и завершать `cancelled` гейта; ответ гейта после отмены SHALL игнорироваться.

Решения гейта декоратор НЕ SHALL кэшировать. Контракт `StreamFunction` (LLM-1, LLM-2) SHALL сохраняться: поток возвращается синхронно, работа начинается не раньше следующей микрозадачи. Класс `badRequest` отказа не повторяется и не переключает модель (LLM-9).

#### Scenario: Отказ без HTTP
- **WHEN** `withSharingGate` оборачивает маршрутизирующую функцию с провайдером `a` (`MockClient` на `https://a.test`), гейт отвечает `false`, и приходит запрос модели `a/m`
- **THEN** поток завершается `ErrorEvent` `badRequest` с текстом `a: the user did not allow sending data to this provider`, `MockClient` не получил запросов, лог содержит `llm.sharing.denied` с `provider: a`

#### Scenario: Разрешение пропускает поток
- **WHEN** гейт отвечает `true`
- **THEN** потребитель видит те же события, что без декоратора, гейт вызван один раз с `ProviderEndpoint(providerId: a, baseUrl: https://a.test…)`

#### Scenario: Каждый запрос спрашивает гейт
- **WHEN** два последовательных запроса модели `a/m` проходят через декоратор
- **THEN** гейт вызван дважды

#### Scenario: Отмена во время ожидания
- **WHEN** гейт не отвечает, и `CancelToken` отменяется
- **THEN** поток завершается `aborted` в пределах цикла событий, `cancelled` гейта завершён, `inner` не вызывался; ответ гейта `true` после этого ничего не меняет

#### Scenario: Исключение гейта — отказ
- **WHEN** гейт бросает `StateError('boom /secret/path')`
- **THEN** поток завершается `badRequest` `a: the data sharing check failed`, лог `llm.sharing.gate_failed` содержит `error_class: StateError` и не содержит `/secret/path`

#### Scenario: Провайдер без адреса идёт мимо гейта
- **WHEN** `endpointOf('b')` возвращает `null`, и приходит запрос модели `b/m`
- **THEN** гейт не вызван, поток — поток `inner`
