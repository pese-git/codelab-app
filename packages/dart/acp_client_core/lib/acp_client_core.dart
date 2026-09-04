/// Public API for ACP client domain models and application use cases.
library;

export 'package:acp_protocol/acp_protocol.dart' show acpProtocolPackageName;
export 'package:acp_transports/acp_transports.dart'
    show
        AcpTransport,
        AcpTransportErrorCode,
        AcpTransportException,
        AcpTransportState,
        acpTransportsPackageName;

export 'src/application/acp_client_application.dart';
export 'src/application/application_models.dart';
export 'src/application/use_cases.dart';
export 'src/domain/approval_policy.dart';
export 'src/domain/domain_models.dart';
export 'src/domain/fs_access.dart';
export 'src/domain/secret_redaction.dart';
export 'src/domain/state_machines.dart';
export 'src/domain/terminal_access.dart';

const acpClientCorePackageName = 'acp_client_core';
