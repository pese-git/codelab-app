## ADDED Requirements

### Requirement: Гейт передачи данных встроенного агента
`EmbeddedHostServices` SHALL иметь необязательное поле `sharingGate` (`SharingGate` ядра); `localEmbeddedAgentOpener` и `scriptedEmbeddedAgentOpener` SHALL принимать необязательный параметр `sharingGate` и передавать его в `EmbeddedHostServices` (design.md change `add-ai-data-sharing-consent`, D4). Основной барель SHALL реэкспортировать `SharingGate`, `ProviderEndpoint` и `ProviderApi` и оставаться web-безопасным.

Если гейт задан, `createEmbeddedAgent` SHALL оборачивать `withSharingGate` функцию модели каждого снимка конфигурации в `modelsFor` — начальную, после перезагрузки корня и для сессий других папок, — а сценарный открыватель SHALL оборачивать сценарную функцию. `endpointOf` SHALL строиться по `CoreConfig` того же снимка: `ProviderEndpoint.of` для провайдеров `CoreConfig.providers`, `null` для провайдеров из `providerProblems` и неизвестных. Без гейта функция модели НЕ SHALL оборачиваться, и поведение SHALL быть прежним.

Отказ гейта SHALL доходить до клиента существующим итогом хода `failed` (`-32603`, `data.codelab.errorClass: "badRequest"`). Новых методов, полей и состояний ACP мост НЕ SHALL добавлять.

#### Scenario: Отказ гейта во встроенном агенте
- **WHEN** `scriptedEmbeddedAgentOpener(sharingGate: (_, _) async => false)` открывает агента, и тестовый клиент отправляет `session/prompt`
- **THEN** ответ — `-32603` с `data.codelab.errorClass: "badRequest"` и текстом отказа, сценарий модели не получил ни одного запроса

#### Scenario: Гейт после перезагрузки конфига
- **WHEN** гейт задан, конфиг корня перезагружен с новым провайдером `gw2`, и сессия переключается на модель `gw2/m`
- **THEN** запрос `gw2/m` вызывает гейт с `providerId: gw2`

#### Scenario: Без гейта как раньше
- **WHEN** открыватель вызван без `sharingGate`
- **THEN** запрос модели уходит без обёртки, события `llm.sharing.*` нет
