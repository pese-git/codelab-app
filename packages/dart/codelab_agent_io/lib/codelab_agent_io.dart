/// Реализации портов ядра CodeLab на `dart:io`: локальные файлы и процессы
/// (`agent-core-architecture` §4.3, §4.6), журналы сессий в JSONL (§8.5) и
/// stdio-транспорт MCP-серверов (design.md change `add-agent-mcp-client`, D9) и
/// хранилища секретов `env`/`file` (change `add-agent-secret-store`).
///
/// Сценарий модели для тестов (`LlmScript`) сюда НЕ входит: он живёт в
/// `package:codelab_agent_io/testing.dart` (change `add-embedded-agent-mode`,
/// D8, задача 2.9), чтобы не попадать в граф импортов рабочей сборки клиентов.
library;

export 'src/cli/exit_codes.dart';
export 'src/cli/config_commands.dart'
    show
        CheckOptions,
        ConfigCommandResult,
        ConfigCommands,
        ConfigGetLayer,
        ConfigGetOptions,
        ConfigPathOptions,
        ConfigSetOptions,
        ConfigUnsetOptions;
export 'src/cli/mcp_server_commands.dart'
    show McpAddOptions, McpListOptions, McpRemoveOptions, McpServerCommands;
export 'src/cli/provider_commands.dart'
    show
        ProviderAddOptions,
        ProviderCommands,
        ProviderListOptions,
        ProviderRemoveOptions;
// Строка о 1.0 (R8-7, D13) живёт в ядре; реэкспорт сохраняет прежний импорт
// приложений из `codelab_agent_io`.
export 'package:codelab_agent_core/codelab_agent_core.dart' show before1Note;
export 'src/cli/secret_commands.dart'
    show
        SecretCommandResult,
        SecretCommands,
        SecretDeleteOptions,
        SecretListOptions,
        SecretMigrateOptions,
        SecretSetOptions;
export 'src/cli/secret_input.dart'
    show MultilineSecretException, SecretInput, StdinSecretInput;
export 'src/config/agent_config_paths.dart'
    show agentConfigPathsFor, watchedConfigFiles;
export 'src/config/config_loader.dart'
    show
        ConfigCandidateResult,
        ConfigLoader,
        ConfigUsageException,
        checkConfigFileName,
        codelabHomeOf,
        maxConfigBytes;
export 'src/config/config_watcher.dart'
    show
        ConfigFileProbe,
        ConfigFileStamp,
        ConfigWatcher,
        DirectoryChange,
        DirectoryEventsFactory,
        configWatchDebounce,
        defaultConfigFileProbe,
        defaultDirectoryEvents;
export 'src/config/config_writer.dart' show ConfigWriteResult, ConfigWriter;
export 'src/config/config_warnings.dart' show logConfigWarnings;
export 'src/config/file_config_source.dart' show FileConfigSource;
export 'src/config/environment_layer.dart' show testSecretStorePath;
export 'src/config/provider_preconfig.dart' show ProviderPreconfigFlags;
export 'src/env/host_path.dart';
export 'src/env/local_execution_env.dart';
export 'src/mcp/stdio_process_transport.dart'
    show StdioMcpTransportFactory, StdioProcessTransport;
export 'src/project/project_files_loader.dart';
export 'src/secrets/client_secret_access.dart';
export 'src/secrets/env_secret_store.dart';
export 'src/secrets/file_secret_store.dart';
export 'src/secrets/host_secrets.dart';
export 'src/secrets/open_secret_store.dart' show openSecretStore;
export 'src/secrets/secret_admin.dart';
export 'src/secrets/secret_migrator.dart'
    show
        SecretActionRequiredItem,
        SecretMigrationAction,
        SecretMigrationItem,
        SecretMigrationOptions,
        SecretMigrationReport,
        SecretMigrator,
        SecretMovedItem,
        SecretNotMigratedItem,
        SecretPlanItem,
        SecretReplacedItem,
        SecretReusedItem;
export 'src/secrets/secret_read_only_hint.dart';
export 'src/secrets/secret_process_runner.dart' hide chmodExecutablePath;
export 'src/secrets/secrets_backend_problem.dart';
export 'src/session/host_sessions.dart' show openHostSessions;
export 'src/session/jsonl_session_store.dart';
export 'src/state/last_model_file.dart';
