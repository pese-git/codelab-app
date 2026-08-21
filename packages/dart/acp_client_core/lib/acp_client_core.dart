/// Public API for ACP client domain models and application use cases.
library;

export 'package:acp_protocol/acp_protocol.dart' show acpProtocolPackageName;
export 'package:acp_transports/acp_transports.dart'
    show acpTransportsPackageName;

export 'src/domain/domain_models.dart';
export 'src/domain/state_machines.dart';

const acpClientCorePackageName = 'acp_client_core';
