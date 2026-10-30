## MODIFIED Requirements

### Requirement: Фабрика и закрытые адаптеры
Хост SHALL получать функцию модели только через фабрики ядра:
- `createStreamFunction(ProviderConfig, CoreLlmServices)` — один провайдер;
- `createRoutedStreamFunction(List<ProviderConfig>, CoreLlmServices, {unavailable})` — несколько провайдеров конфигурации (design.md change `add-agent-configuration`, D11).

Фабрика одного провайдера собирает цепочку §2.10: адаптер → `withWatchdogs` → `withTransientRetry` → `withFallback`. `CoreLlmServices` несёт `http.Client`, `Clock`, `Random` и `Logger` хоста. Публичный барель ядра НЕ SHALL экспортировать `lib/src/llm/providers/*` (PKG-5).

Маршрутизирующая фабрика SHALL:
- выбирать цепочку `createStreamFunction` по `ModelRef.provider` и создавать её при первом запросе к провайдеру;
- для провайдера из `unavailable` (id → причина) возвращать поток с ошибкой класса `auth` и текстом причины без HTTP-запроса;
- для провайдера вне списка возвращать поток с ошибкой `badRequest` `unknown provider <id>`.

#### Scenario: Барель не раскрывает адаптеры
- **WHEN** проверяется файл `lib/codelab_agent_core.dart`
- **THEN** в нём нет экспорта `src/llm/providers/`

#### Scenario: Фабрика собирает устойчивую цепочку
- **WHEN** функция из фабрики получает сетевой сбой до вывода, а затем успешный ответ
- **THEN** потребитель видит один `StartEvent` и успешный ответ, а `Logger` — одну запись `llm.retry`

#### Scenario: Маршрут по провайдеру
- **WHEN** маршрутизирующая функция с провайдерами `a` (`MockClient` на `https://a.test`) и `b` (`https://b.test`) получает запрос модели `b/m`
- **THEN** HTTP-запрос уходит только на `https://b.test`, цепочка провайдера `a` не создана

#### Scenario: Провайдер без ключа
- **WHEN** провайдер `openai` передан в `unavailable` с причиной `API key variable OPENAI_API_KEY is not set`, а запрос идёт к модели `openai/gpt-4o`
- **THEN** поток завершается ошибкой класса `auth` с этим текстом, HTTP-клиент не получил ни одного запроса
