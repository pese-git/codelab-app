## ADDED Requirements

### Requirement: Адрес провайдера модели по умолчанию
Мост `codelab_setup` SHALL экспортировать функцию `defaultProviderEndpoint(snapshot)`: для снимка с построенным `CoreConfig` она SHALL возвращать `ProviderEndpoint.of` провайдера модели `CoreConfig.defaultModel` (явной или первой модели первого провайдера, как у `checkProviderReadiness`), иначе `null` (design.md change `add-ai-data-sharing-consent`, D10). Значения ключей и секретов функция НЕ SHALL читать. Барель SHALL реэкспортировать `ProviderEndpoint` и `ProviderApi` ядра, чтобы клиенты не импортировали `package:codelab_agent_*` (PKG-4).

#### Scenario: Адрес по умолчанию
- **WHEN** снимок содержит провайдера `anthropic` без `base_url` с моделью и провайдера `gw` с `base_url: https://llm.internal/v1`, а `agent.default_model` не задан
- **THEN** функция возвращает `ProviderEndpoint(providerId: anthropic, api: anthropicMessages)` с адресом по умолчанию ядра для Anthropic

#### Scenario: Нет модели
- **WHEN** снимок пустого `CODELAB_HOME`
- **THEN** функция возвращает `null`
