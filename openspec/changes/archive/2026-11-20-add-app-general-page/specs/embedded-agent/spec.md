## ADDED Requirements

### Requirement: Версия встроенного агента для клиентов
Основной барель `package:codelab_embedded/codelab_embedded.dart` SHALL экспортировать константу `embeddedAgentVersion` — ту же строку, что встроенный агент передаёт в `agentInfo.version` ответа `initialize` (design.md change `add-app-general-page`, D11). Клиент SHALL брать версию встроенного агента для показа из этой константы, а не запускать агента и не дублировать строку у себя. Экспорт НЕ SHALL тянуть в основной барель `dart:io` и `package:codelab_agent_io/`.

#### Scenario: Константа совпадает с agentInfo
- **WHEN** тест открывает встроенного агента сценарным открывателем и выполняет `initialize`
- **THEN** `agentInfo.version` ответа равен `embeddedAgentVersion` из основного бареля

#### Scenario: Барель остаётся web-безопасным
- **WHEN** точка входа `packages/dart/codelab_embedded/test/web_smoke/main.dart` читает `embeddedAgentVersion`
- **THEN** `fvm dart run melos run web-compile` компилирует её в JavaScript и WebAssembly без ошибок
