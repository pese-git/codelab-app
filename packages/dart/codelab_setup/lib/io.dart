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
/// D8, D15); типы, без которых их не собрать и не типизировать
/// (`DescribedSecretStore`, `SecretStoreUnavailableException`, `Logger`,
/// `LogLevel`), реэкспортируются из ядра. Остальное из §12.4.2 (`FileAgentConfigStore`) придёт со своими
/// потребителями.
library;

export 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        CheckOptions,
        ConfigCommandResult,
        ConfigCommands,
        MultilineSecretException,
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
        SecretNotSet,
        SecretReadOnly,
        SecretSetOptions,
        SecretStored,
        SecretUpdated,
        SecretWriteOutcome,
        StdinSecretInput,
        configInvalidExit,
        configUsageExit,
        configValidExit,
        openSecretStore;

// Типы ядра, которые нужны клиенту, чтобы вызвать `openSecretStore` и получить
// `SecretAdmin` (ревью итерации 4 change `add-agent-secret-store`): результат
// фабрики, её исключение и логгер. `openHostSecrets` не экспортируется: D15
// отдаёт его хосту агента, а не мосту.
export 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        DescribedSecretStore,
        LogLevel,
        Logger,
        SecretStoreUnavailableException;
