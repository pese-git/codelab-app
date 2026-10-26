/// Public API for ACP transport ports and configuration.
///
/// Web-safe: never reaches the VM-only IO library. The stdio and WebSocket
/// transports live in `package:codelab_acp_transports/io.dart`.
library;

export 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcId, JsonRpcMessage, acpProtocolPackageName;

export 'src/acp_transport.dart';
export 'src/transport_configs.dart';

const acpTransportsPackageName = 'codelab_acp_transports';
