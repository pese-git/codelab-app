import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import 'acp_activity_bar.dart';

/// Mirrors the ACP protocol's `PlanEntryStatus` — kept as its own
/// presentation enum (rather than importing `acp_protocol`'s) for the same
/// package-boundary reason as `AcpApprovalOptionKind`
/// (`acp_approval_option_group.dart`).
enum AcpPlanEntryStatus { pending, inProgress, completed }

/// Mirrors the ACP protocol's `PlanEntryPriority`.
enum AcpPlanEntryPriority { high, medium, low }

class AcpPlanEntry {
  const AcpPlanEntry({
    required this.content,
    required this.status,
    required this.priority,
  });

  final String content;
  final AcpPlanEntryStatus status;
  final AcpPlanEntryPriority priority;
}

/// The agent's plan, rendered as an [AcpActivityBarSection] — a collapsed
/// summary (naming the in-progress entry, or an aggregate count) and, when
/// expanded, the full list of [AcpPlanEntry] with status and priority.
class AcpProgressChecklist {
  AcpProgressChecklist._();

  static AcpActivityBarSection section({
    required String id,
    required List<AcpPlanEntry> entries,
    required VoidCallback onDismiss,
  }) {
    return AcpActivityBarSection(
      id: id,
      headerBuilder: (context, expanded) =>
          _Header(entries: entries, expanded: expanded, onDismiss: onDismiss),
      bodyBuilder: (context) => _Body(entries: entries),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.entries,
    required this.expanded,
    required this.onDismiss,
  });

  final List<AcpPlanEntry> entries;
  final bool expanded;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final total = entries.length;
    final completed = entries
        .where((entry) => entry.status == AcpPlanEntryStatus.completed)
        .length;
    final pending = entries
        .where((entry) => entry.status == AcpPlanEntryStatus.pending)
        .length;
    AcpPlanEntry? inProgress;
    for (final entry in entries) {
      if (entry.status == AcpPlanEntryStatus.inProgress) {
        inProgress = entry;
        break;
      }
    }

    final Widget title;
    if (!expanded && inProgress != null) {
      title = Row(
        children: [
          const AcpText('Current:', role: AcpTextRole.caption),
          const SizedBox(width: 6),
          Expanded(
            child: AcpText(
              inProgress.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pending > 0) ...[
            const SizedBox(width: 6),
            AcpText('$pending left', role: AcpTextRole.caption),
          ],
        ],
      );
    } else {
      final statusLabel = completed == 0 ? '$total Tasks' : '$completed/$total';
      title = Row(
        children: [
          const Expanded(child: AcpText('Plan', role: AcpTextRole.caption)),
          AcpText(statusLabel, role: AcpTextRole.caption),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 8),
        AcpIconButton(
          icon: FluentIcons.chrome_close,
          tooltip: 'Clear plan',
          onPressed: onDismiss,
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.entries});

  final List<AcpPlanEntry> entries;

  static const double _maxHeight = 128;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(height: 6),
        itemBuilder: (context, index) => _EntryRow(entry: entries[index]),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final AcpPlanEntry entry;

  @override
  Widget build(BuildContext context) {
    final completed = entry.status == AcpPlanEntryStatus.completed;
    final baseStyle = FluentTheme.of(context).typography.body;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AcpIcon(_statusIcon, tone: _statusTone, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            entry.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: baseStyle?.copyWith(
              color: completed ? Colors.grey : null,
              decoration: completed ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        AcpBadge(label: _priorityLabel, tone: _priorityTone),
      ],
    );
  }

  IconData get _statusIcon => switch (entry.status) {
    AcpPlanEntryStatus.pending => FluentIcons.circle_ring,
    AcpPlanEntryStatus.inProgress => FluentIcons.skype_circle_clock,
    AcpPlanEntryStatus.completed => FluentIcons.status_circle_checkmark,
  };

  AcpTone get _statusTone => switch (entry.status) {
    AcpPlanEntryStatus.pending => AcpTone.neutral,
    AcpPlanEntryStatus.inProgress => AcpTone.accent,
    AcpPlanEntryStatus.completed => AcpTone.success,
  };

  String get _priorityLabel => switch (entry.priority) {
    AcpPlanEntryPriority.high => 'High',
    AcpPlanEntryPriority.medium => 'Medium',
    AcpPlanEntryPriority.low => 'Low',
  };

  AcpTone get _priorityTone => switch (entry.priority) {
    AcpPlanEntryPriority.high => AcpTone.danger,
    AcpPlanEntryPriority.medium => AcpTone.warning,
    AcpPlanEntryPriority.low => AcpTone.neutral,
  };
}
