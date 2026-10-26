/// Общий клиентский слой ACP без UI: рабочее пространство, соединение,
/// сессии и их транскрипт (change `extract-acp-client-kit`).
///
/// Почему: app и CLI должны вести себя одинаково, поэтому логика клиента
/// живёт здесь, на чистом Dart, а хосты только отображают её состояние
/// (`dart-agent-and-clients` §9.10).
///
/// Как использовать: composition root создаёт `ClientWorkspace` с
/// `AcpClientBackend` и резолверами транспорта; хост подписывается на
/// `ClientWorkspace.state`.
library;

export 'src/backend/agent_backend.dart';
export 'src/connection/connection_profile.dart';
export 'src/connection/connection_view.dart';
export 'src/connection/secret_source.dart';
export 'src/connection/transport_resolver.dart';
export 'src/transcript/transcript_item.dart';
export 'src/workspace/client_workspace.dart';
export 'src/workspace/client_workspace_exception.dart';
export 'src/workspace/workspace_state.dart';

const acpClientKitPackageName = 'acp_client_kit';
