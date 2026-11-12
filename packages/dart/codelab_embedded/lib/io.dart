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
/// Перенос секретов (change `add-config-literal-secrets-and-migrate`, D8):
/// отсюда же composition root app берёт движок `SecretMigrator`, опции
/// `SecretMigrationOptions` (слои — `ConfigLayer`), отчёт
/// `SecretMigrationReport` и его пункты. Основной барель их не экспортирует
/// (он web-безопасен), а app не импортирует `codelab_agent_*` (PKG-4).
/// Вызов: `SecretMigrator().run(secretMigrationOptionsFor(cwd: …,
/// environment: …, dryRun: true))` — план; тот же вызов без `dryRun`
/// применяет. Помощник задаёт `--all`, без `force`, и то же тестовое
/// хранилище, что у открывателя; опции вручную app не собирает. `report.canApply` включает кнопку «Migrate»,
/// `readOnlyBackend` — бэкенд `env`, `items[i].describe()` — строки без
/// значений. `force` в app не используется.
///
/// Как использовать: composition root клиента (CLI, desktop) вызывает
/// [localEmbeddedAgentOpener] один раз и передаёт результат резолверу
/// транспорта; импорт разрешён сторожем только composition root клиента.
library;

export 'src/io/local_opener.dart' show localEmbeddedAgentOpener;
export 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        SecretActionRequiredItem,
        SecretMigrationAction,
        SecretMigrationItem,
        SecretMigrationOptions,
        SecretMigrationReport,
        SecretMigrator,
        SecretMovedItem,
        SecretNotMigratedItem,
        SecretProviderMovedItem,
        SecretPlanItem,
        SecretReplacedItem,
        SecretReusedItem;
export 'package:codelab_agent_core/codelab_agent_core.dart' show ConfigLayer;
export 'src/io/migration_options.dart' show secretMigrationOptionsFor;
