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
    show CheckOptions, ConfigCommandResult, ConfigCommands;
export 'src/cli/secret_commands.dart'
    show
        SecretCommandResult,
        SecretCommands,
        SecretDeleteOptions,
        SecretListOptions,
        SecretSetOptions;
export 'src/cli/secret_input.dart'
    show MultilineSecretException, SecretInput, StdinSecretInput;
export 'src/config/config_loader.dart'
    show ConfigLoader, ConfigUsageException, checkConfigFileName, codelabHomeOf;
export 'src/config/config_warnings.dart' show logConfigWarnings;
export 'src/config/environment_layer.dart' show testSecretStorePath;
export 'src/env/host_path.dart';
export 'src/env/local_execution_env.dart';
export 'src/mcp/stdio_process_transport.dart'
    show StdioMcpTransportFactory, StdioProcessTransport;
export 'src/project/project_files_loader.dart';
export 'src/secrets/env_secret_store.dart';
export 'src/secrets/file_secret_store.dart';
export 'src/secrets/host_secrets.dart';
export 'src/secrets/open_secret_store.dart' show openSecretStore;
export 'src/secrets/secret_admin.dart';
export 'src/secrets/secret_process_runner.dart';
export 'src/secrets/secrets_backend_problem.dart';
export 'src/session/host_sessions.dart' show openHostSessions;
export 'src/session/jsonl_session_store.dart';
