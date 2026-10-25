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
export 'src/fake_terminal_process_runner.dart';
export 'src/codelab_compatible_stdio_agent.dart';
export 'src/fixtures/agent_conformance.dart';
export 'src/fixtures/client_conformance.dart';
export 'src/fixtures/fixture.dart';
export 'src/fixtures/matcher.dart';
export 'src/in_process_acp_link.dart';

const acpTestingPackageName = 'acp_testing';
