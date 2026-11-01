/// Настольный открыватель встроенного агента: конфигурация, секреты, журнал
/// сессий, файлы проекта и MCP (design.md change `add-embedded-agent-mode`,
/// D2, D5).
///
/// Почему отдельная точка входа: открыватель использует `dart:io` и
/// `package:codelab_agent_io`, а основной барель `codelab_embedded` обязан
/// собираться для web (D3, сторож `codelab_architecture_tests`). Сценария
/// модели здесь нет: он живёт в `testing.dart` (D8), и рабочая сборка клиента
/// его не импортирует.
///
/// Как использовать: composition root клиента (CLI, desktop) вызывает
/// [localEmbeddedAgentOpener] один раз и передаёт результат резолверу
/// транспорта; импорт разрешён сторожем только composition root клиента.
library;

export 'src/io/local_opener.dart' show localEmbeddedAgentOpener;
