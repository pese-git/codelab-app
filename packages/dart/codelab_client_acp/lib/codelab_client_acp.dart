/// Public API for ACP client domain models and application use cases.
library;

export 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show acpProtocolPackageName;
export 'package:codelab_acp_transports/codelab_acp_transports.dart'
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
export 'src/domain/logger.dart';
export 'src/domain/prompt_failure.dart';
export 'src/domain/secret_redaction.dart';
export 'src/domain/state_machines.dart';
export 'src/domain/terminal_access.dart';
export 'src/infrastructure/structured_log_logger.dart';

const acpClientCorePackageName = 'codelab_client_acp';
