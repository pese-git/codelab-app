## ADDED Requirements

### Requirement: Web-безопасный публичный барель transport
Основная точка входа `package:acp_transports/acp_transports.dart` SHALL экспортировать порт transport и классы конфигурации (`StdioAcpTransportConfig`, `StdioAcpAgentProfile`, `WebSocketAcpTransportConfig`) без транзитивного импорта `dart:io`. Реализации `StdioAcpTransport` и `WebSocketAcpTransport` SHALL экспортироваться только из отдельной точки входа `package:acp_transports/io.dart`. Файлы основного бареля НЕ SHALL ссылаться на файлы IO-точки входа.

#### Scenario: Основной барель не тянет dart:io
- **WHEN** сторож архитектуры проверяет `packages/dart/acp_transports/lib/` по правилу web-безопасного пакета с исключением IO-точки входа
- **THEN** нарушений нет, а `grep -rn "dart:io"` по `lib/acp_transports.dart` и `lib/src/transport_configs.dart` ничего не находит

#### Scenario: Код создания транспорта импортирует io.dart
- **WHEN** composition root приложения создаёт `StdioAcpTransport` или `WebSocketAcpTransport`
- **THEN** он импортирует `package:acp_transports/io.dart`, а поведение подключения по stdio и WebSocket не меняется — интеграционные тесты stdio проходят
