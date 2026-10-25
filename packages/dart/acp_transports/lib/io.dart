/// dart:io ACP transports: stdio child processes and WebSocket endpoints.
///
/// Import from composition roots and tests only; web-safe code uses
/// `package:acp_transports/acp_transports.dart`.
library;

export 'src/io/stdio_acp_transport.dart';
export 'src/io/websocket_acp_transport.dart';
export 'src/io/stdio_server_acp_transport.dart';
export 'src/io/websocket_server_acp_transport.dart';
