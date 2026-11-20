/// Общий клиентский слой ACP без UI: рабочее пространство, соединение,
/// сессии, их транскрипт, очередь, одобрения, опции, каталог команд
/// палитры, инспектор и диагностика (changes `extract-acp-client-kit`,
/// `add-command-palette-agent-commands`).
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
export 'src/commands/command_catalog.dart';
export 'src/connection/connection_profile.dart';
export 'src/connection/connection_view.dart';
export 'src/connection/profile_draft.dart';
export 'src/connection/profile_committer.dart';
export 'src/connection/profile_ids.dart';
export 'src/connection/profile_parsing.dart';
export 'src/connection/profile_secrets.dart';
export 'src/connection/profile_token_ref.dart';
export 'src/connection/secret_source.dart';
export 'src/connection/token_rejection.dart';
export 'src/connection/transport_resolver.dart';
export 'src/diagnostics/diagnostics.dart';
export 'src/files/project_files.dart';
export 'src/files/project_files_rules.dart';
export 'src/inspector/inspector_projection.dart';
export 'src/queue/prompt_queue.dart';
export 'src/restore/workspace_snapshot.dart';
export 'src/session/session_views.dart';
export 'src/session/subagent_rows.dart' show SubagentRowState, SubagentRowView;
export 'src/stores/stores.dart';
export 'src/themes/theme_color.dart';
export 'src/themes/theme_file.dart';
export 'src/themes/theme_issue.dart';
export 'src/themes/theme_library.dart';
export 'src/themes/theme_role.dart';
export 'src/transcript/subagent_views.dart';
export 'src/transcript/tool_row.dart';
export 'src/transcript/transcript_item.dart';
export 'src/usage/usage_decoder.dart';
export 'src/usage/usage_ledger_decoder.dart';
export 'src/usage/usage_ledger_models.dart';
export 'src/usage/usage_fold.dart';
export 'src/usage/usage_format.dart';
export 'src/usage/usage_models.dart';
export 'src/workspace/client_workspace.dart';
export 'src/workspace/client_workspace_exception.dart';
export 'src/workspace/workspace_state.dart';

const acpClientKitPackageName = 'codelab_client_core';
