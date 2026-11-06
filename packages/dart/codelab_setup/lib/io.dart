/// IO-барель моста `codelab_setup`: общие подкоманды `config` для клиентов
/// (`dart-agent-and-clients` §12.4.2, `agent-core-architecture` §17.5.5;
/// design.md change `add-agent-configuration`, D13, D14).
///
/// Почему: `codelab config check` и `codelab-agent config check` обязаны
/// печатать одно и то же, поэтому реализация одна — в `codelab_agent_io`, а
/// терминальный клиент, которому прямой импорт `codelab_agent_*` запрещён,
/// получает её через этот барель.
///
/// Для чего: единственная точка входа клиентов в `ConfigCommands`; импортируется
/// только composition root клиента (точка входа CLI, `dart:io`).
///
/// Как использовать: `await ConfigCommands().check(CheckOptions(cwd: …,
/// environment: Platform.environment))`, затем вывести `stdout`/`stderr`
/// результата и завершиться с `exitCode` — одним из `configValidExit` (0),
/// `configInvalidExit` (1), `configUsageExit` (64). Подкоманда `secret`:
/// `SecretCommands().set/delete/list(…)` с `StdinSecretInput()` печатает тот же
/// вывод, что `codelab-agent secret`; `SecretAdmin` с результатами и
/// `openSecretStore` — для страницы настроек (change `add-agent-secret-store`,
/// D8, D15). Подкоманды записи и чтения конфига (change
/// `add-config-writer-and-reload`, D6): `ConfigCommands().path/get/set/unset`,
/// `ProviderCommands().add/list/remove`, `McpServerCommands().add/list/remove`
/// и их опции (`ConfigSetOptions`, `ProviderAddOptions`, `McpAddOptions` и др.,
/// слой чтения — `ConfigGetLayer`) дают тот же вывод и коды выхода, что
/// `codelab-agent`; типы, без которых их не собрать и не типизировать
/// (`DescribedSecretStore`, `SecretStoreUnavailableException`, `Logger`,
/// `LogLevel`), реэкспортируются из ядра. Подкоманда `secret migrate` (change
/// `add-config-literal-secrets-and-migrate`, D7): `SecretCommands().migrate(
/// SecretMigrateOptions(…))` либо движок `SecretMigrator` с
/// `SecretMigrationOptions`, отчёт `SecretMigrationReport` и его пункты; флаги
/// `--header-stdin`, `--env-stdin`, `--header-scheme` — поля `McpAddOptions`.
/// Строка о 1.0 для справок — `before1Note` (R8-7, D13). Клиентский доступ к
/// секретам (change `add-provider-setup-ui`, D3, D4): `ClientSecretAccess.open(
/// codelabHome: …, environment: …, logger: …)` — выбор бэкенда по
/// `secrets.backend`, `backend`, `admin`, `isSet`, `read` без кэша — и
/// `secretReadOnlyHint(SecretReadOnly, home)` — одна подсказка про бэкенд только
/// для чтения для `codelab secret set`, мастера и app. Снимок и запись конфига
/// агента, проверка `/models` и удаление секрета (change
/// `add-provider-setup-ui`, D6, D8, D10): `FileAgentConfigStore(paths: …,
/// environment: …, secrets: …)` реализует порт `AgentConfigStore` основного
/// бареля, `ioProviderCheck()` даёт `ProviderCheck` на `IOClient`,
/// `secretDeleterOf(access)` — `SecretDeleter` для `ProviderRemover`.
/// Остальное из §12.4.2 (мастер, пути `$CODELAB_HOME`) придёт со своими
/// потребителями.
library;

export 'src/io/file_agent_config_store.dart' show FileAgentConfigStore;
export 'src/io/io_provider_check.dart' show ioProviderCheck;
export 'src/io/provider_keys.dart' show providerKeysOf;
export 'src/io/secret_deleter.dart' show secretDeleterOf;

export 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        CheckOptions,
        ClientSecretAccess,
        ConfigCommandResult,
        ConfigCommands,
        ConfigGetLayer,
        ConfigGetOptions,
        ConfigPathOptions,
        ConfigSetOptions,
        ConfigUnsetOptions,
        McpAddOptions,
        McpListOptions,
        McpRemoveOptions,
        McpServerCommands,
        MultilineSecretException,
        ProviderAddOptions,
        ProviderCommands,
        ProviderListOptions,
        ProviderRemoveOptions,
        SecretActionRequiredItem,
        SecretAdmin,
        SecretCollision,
        SecretCommandResult,
        SecretCommands,
        SecretDeleteOptions,
        SecretDeleteOutcome,
        SecretDeleted,
        SecretFailed,
        SecretInput,
        SecretInvalidName,
        SecretInvalidValue,
        SecretListFailed,
        SecretListOptions,
        SecretListOutcome,
        SecretListing,
        SecretMigrateOptions,
        SecretMigrationAction,
        SecretMigrationItem,
        SecretMigrationOptions,
        SecretMigrationReport,
        SecretMigrator,
        SecretMovedItem,
        SecretNotMigratedItem,
        SecretNotSet,
        SecretPlanItem,
        SecretReadOnly,
        SecretReplacedItem,
        SecretReusedItem,
        SecretSetOptions,
        SecretStored,
        SecretUpdated,
        SecretWriteOutcome,
        StdinSecretInput,
        before1Note,
        configInvalidExit,
        configUsageExit,
        configValidExit,
        openSecretStore,
        secretReadOnlyHint;

// Типы ядра, которые нужны клиенту, чтобы вызвать `openSecretStore` и получить
// `SecretAdmin` (ревью итерации 4 change `add-agent-secret-store`): результат
// фабрики, её исключение и логгер. `openHostSecrets` не экспортируется: D15
// отдаёт его хосту агента, а не мосту.
export 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        DescribedSecretStore,
        LogLevel,
        Logger,
        SecretBackendInfo,
        SecretStoreUnavailableException;
