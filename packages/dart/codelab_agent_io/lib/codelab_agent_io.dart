/// Реализации портов ядра CodeLab на `dart:io`: локальные файлы и процессы
/// (`agent-core-architecture` §4.3, §4.6), журналы сессий в JSONL (§8.5) и
/// stdio-транспорт MCP-серверов (design.md change `add-agent-mcp-client`, D9).
library;

export 'src/cli/exit_codes.dart';
export 'src/cli/config_commands.dart'
    show CheckOptions, ConfigCommandResult, ConfigCommands;
export 'src/config/config_loader.dart'
    show ConfigLoader, ConfigUsageException, checkConfigFileName, codelabHomeOf;
export 'src/env/host_path.dart';
export 'src/env/local_execution_env.dart';
export 'src/mcp/stdio_process_transport.dart'
    show StdioMcpTransportFactory, StdioProcessTransport;
export 'src/session/jsonl_session_store.dart';
