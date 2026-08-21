/// Public API for ACP test doubles, fixtures, and conformance helpers.
library;

export 'package:acp_client_core/acp_client_core.dart'
    show acpClientCorePackageName;
export 'package:acp_protocol/acp_protocol.dart' show acpProtocolPackageName;
export 'package:acp_transports/acp_transports.dart'
    show
        AcpTransport,
        AcpTransportDiagnostic,
        AcpTransportDiagnosticSeverity,
        AcpTransportErrorCode,
        AcpTransportEvent,
        AcpTransportException,
        AcpTransportFailure,
        AcpTransportState,
        AcpTransportStateChanged,
        JsonRpcId,
        JsonRpcMessage,
        acpTransportsPackageName;

export 'src/fake_acp_transport.dart';

const acpTestingPackageName = 'acp_testing';
