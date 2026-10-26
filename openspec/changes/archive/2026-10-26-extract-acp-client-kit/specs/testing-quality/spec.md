## ADDED Requirements

### Requirement: Характеризационные тесты фасада приложения
Перенос логики клиента из `CodeLabShellCubit` в `acp_client_kit` SHALL быть защищён характеризационными тестами публичной поверхности Cubit в `apps/codelab_app/test/features/workbench/application/shell_cubit_characterization/`: подключение, сессии, промпты и очередь, отмена, опции конфигурации, одобрения, переподключение. Тесты SHALL создавать Cubit через граф cherrypick app (`CodeLabTestBinding`) с `FakeAcpTransport`, проверять только публичные методы и поля `CodeLabShellState` и конечные состояния, а не число промежуточных `emit`. Тесты SHALL быть зелёными до первого переноса и после каждой итерации change без изменения их текста; тексты 8 интеграционных тестов `apps/codelab_app/integration_test/` на время переноса НЕ SHALL меняться.

#### Scenario: Тесты пишутся до переноса
- **WHEN** открывается первый PR change `extract-acp-client-kit`
- **THEN** он содержит только характеризационные тесты, код `apps/codelab_app/lib` не изменён, и тесты зелёные

#### Scenario: Перенос не меняет тесты
- **WHEN** итерация переносит часть логики Cubit в kit
- **THEN** характеризационные тесты и `test/widget_test.dart` зелёные без правок, а `fvm dart analyze` собирает интеграционные тесты
