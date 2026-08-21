import 'package:fluent_ui/fluent_ui.dart';

class AcpCommandAction {
  const AcpCommandAction({
    required this.id,
    required this.label,
    required this.slashCommand,
    required this.description,
    required this.icon,
  });

  final String id;
  final String label;
  final String slashCommand;
  final String description;
  final IconData icon;

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
    ),
    AcpCommandAction(
      id: 'permissions',
      label: 'Permissions',
      slashCommand: '/permissions',
      description: 'Open permission mode controls.',
      icon: FluentIcons.permissions,
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
