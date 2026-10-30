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
/// Как использовать: `ConfigCommands().check(CheckOptions(cwd: …, environment:
/// Platform.environment))`, затем вывести `stdout`/`stderr` результата и
/// завершиться с `exitCode` — одним из `configValidExit` (0),
/// `configInvalidExit` (1), `configUsageExit` (64). Остальное из §12.4.2
/// (`FileAgentConfigStore`, `systemSecretStore()`) придёт со своими
/// потребителями.
library;

export 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        CheckOptions,
        ConfigCommandResult,
        ConfigCommands,
        configInvalidExit,
        configUsageExit,
        configValidExit;
