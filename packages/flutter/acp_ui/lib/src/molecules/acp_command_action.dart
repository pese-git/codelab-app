import 'package:fluent_ui/fluent_ui.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'acp_command_action.freezed.dart';

/// Where an [AcpCommandAction] came from — used by the command palette only
/// to render visually separate sections; it does not affect filtering.
enum AcpCommandSource { client, agent }

@freezed
sealed class AcpCommandAction with _$AcpCommandAction {
  const AcpCommandAction._();

  const factory AcpCommandAction({
    required String id,
    required String label,
    required String slashCommand,
    required String description,
    required IconData icon,
    @Default(AcpCommandSource.client) AcpCommandSource source,

    /// Whether selecting this command performs a real action. `false`
    /// renders the command as disabled/"coming soon" instead of a silent
    /// no-op.
    @Default(true) bool isAvailable,
  }) = _AcpCommandAction;

  static const List<AcpCommandAction> defaults = [
    AcpCommandAction(
      id: 'new',
      label: 'New session',
      slashCommand: '/new',
      description: 'Start a fresh ACP session.',
      icon: FluentIcons.add,
    ),
    AcpCommandAction(
      id: 'plan',
      label: 'Plan mode',
      slashCommand: '/plan',
      description: 'Switch the prompt turn into planning.',
      icon: FluentIcons.plan_view,
      isAvailable: false,
    ),
    AcpCommandAction(
      id: 'permissions',
      label: 'Permissions',
      slashCommand: '/permissions',
      description: 'Open permission mode controls.',
      icon: FluentIcons.permissions,
      isAvailable: false,
    ),
    AcpCommandAction(
      id: 'logs',
      label: 'Logs',
      slashCommand: '/logs',
      description: 'Open protocol and diagnostic logs.',
      icon: FluentIcons.command_prompt,
    ),
    AcpCommandAction(
      id: 'compact',
      label: 'Compact transcript',
      slashCommand: '/compact',
      description: 'Prepare the transcript for compaction.',
      icon: FluentIcons.view_list,
      isAvailable: false,
    ),
    AcpCommandAction(
      id: 'reconnect',
      label: 'Reconnect',
      slashCommand: '/reconnect',
      description: 'Retry the current agent connection.',
      icon: FluentIcons.refresh,
    ),
  ];

  static List<AcpCommandAction> filter(
    Iterable<AcpCommandAction> actions,
    String query,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty || normalizedQuery == '/') {
      return List.unmodifiable(actions);
    }

    return List.unmodifiable(
      actions.where((action) {
        final normalizedSlashCommand = action.slashCommand.toLowerCase();
        final normalizedLabel = action.label.toLowerCase();
        final normalizedDescription = action.description.toLowerCase();

        return normalizedSlashCommand.contains(normalizedQuery) ||
            normalizedLabel.contains(normalizedQuery.replaceFirst('/', '')) ||
            normalizedDescription.contains(
              normalizedQuery.replaceFirst('/', ''),
            );
      }),
    );
  }
}
