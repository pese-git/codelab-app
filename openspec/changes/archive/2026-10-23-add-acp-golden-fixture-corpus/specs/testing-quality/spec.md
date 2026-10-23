## ADDED Requirements

### Requirement: Клиентская conformance-проверка на корпусе фикстур
CodeLab SHALL проигрывать каждую golden-фикстуру с ролью `client` против `AcpClientApplication` тестом `packages/dart/acp_client_core/test/fixtures/client_fixture_conformance_test.dart`. Melos-скрипт `conformance:client` SHALL запускать эту проверку и SHALL входить в полную проверку `check` и в джоб CI `conformance`.

#### Scenario: Корпус этапа 0 проходит
- **WHEN** выполняется `fvm dart run melos run conformance:client`
- **THEN** все 12 фикстур этапа 0 с ролью `client` проходят

#### Scenario: Полная проверка включает клиентский прогон
- **WHEN** выполняется `fvm dart run melos run check` или джоб CI `conformance`
- **THEN** запускается и `protocol-conformance`, и `conformance:client`
