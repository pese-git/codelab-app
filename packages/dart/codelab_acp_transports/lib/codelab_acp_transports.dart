/// Публичный API портов ACP-транспорта и их конфигурации.
///
/// Порт транспорта, конфигурации и пара транспортов в памяти
/// (`InProcessAcpLink`, `InProcessAcpTransport`).
///
/// Web-безопасен: не тянет `dart:io` (agent-transports «Web-безопасный
/// публичный барель transport»). Транспорты stdio и WebSocket лежат в
/// `package:codelab_acp_transports/io.dart`.
library;

export 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcId, JsonRpcMessage, acpProtocolPackageName;

export 'src/acp_transport.dart';
export 'src/in_process_acp_transport.dart';
export 'src/transport_configs.dart';

const acpTransportsPackageName = 'codelab_acp_transports';
