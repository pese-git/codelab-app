import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import 'codelab_activity_bar.dart';

/// Mirrors the ACP protocol's `PlanEntryStatus` — kept as its own
/// presentation enum (rather than importing `codelab_acp_protocol`'s) for the same
/// package-boundary reason as `CodeLabApprovalOptionKind`
/// (`codelab_approval_option_group.dart`).
enum CodeLabPlanEntryStatus { pending, inProgress, completed }

/// Mirrors the ACP protocol's `PlanEntryPriority`.
enum CodeLabPlanEntryPriority { high, medium, low }

class CodeLabPlanEntry {
  const CodeLabPlanEntry({
    required this.content,
    required this.status,
    required this.priority,
  });

  final String content;
  final CodeLabPlanEntryStatus status;
  final CodeLabPlanEntryPriority priority;
}

/// The agent's plan, rendered as an [CodeLabActivityBarSection] — a collapsed
/// summary (naming the in-progress entry, or an aggregate count) and, when
/// expanded, the full list of [CodeLabPlanEntry] with status and priority.
class CodeLabProgressChecklist {
  CodeLabProgressChecklist._();

  static CodeLabActivityBarSection section({
    required String id,
    required List<CodeLabPlanEntry> entries,
    required VoidCallback onDismiss,
  }) {
    return CodeLabActivityBarSection(
      id: id,
      headerBuilder: (context, expanded) =>
          _Header(entries: entries, expanded: expanded, onDismiss: onDismiss),
      bodyBuilder: (context) => _Body(entries: entries),
    );
  }

  /// Полный чек-лист без ограничения высоты — содержимое панели Plan дока.
  ///
  /// Почему: в доке план занимает всю высоту панели, а секция activity bar
  /// ограничена [_Body._maxHeight] (change `redesign-workbench-shell`, D5).
  /// Как использовать: класть в панель с ограниченной высотой — список
  /// прокручивается сам; строки те же, что в раскрытой секции.
  static Widget list({required List<CodeLabPlanEntry> entries, Key? key}) =>
      ListView.separated(
        key: key,
        padding: const EdgeInsets.all(12),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _EntryRow(entry: entries[index]),
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.entries,
    required this.expanded,
    required this.onDismiss,
  });

  final List<CodeLabPlanEntry> entries;
  final bool expanded;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final total = entries.length;
    final completed = entries
        .where((entry) => entry.status == CodeLabPlanEntryStatus.completed)
        .length;
    final pending = entries
        .where((entry) => entry.status == CodeLabPlanEntryStatus.pending)
        .length;
    CodeLabPlanEntry? inProgress;
    for (final entry in entries) {
      if (entry.status == CodeLabPlanEntryStatus.inProgress) {
        inProgress = entry;
        break;
      }
    }

    final Widget title;
    if (!expanded && inProgress != null) {
      title = Row(
        children: [
          const CodeLabText('Current:', role: CodeLabTextRole.caption),
          const SizedBox(width: 6),
          Expanded(
            child: CodeLabText(
              inProgress.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pending > 0) ...[
            const SizedBox(width: 6),
            CodeLabText('$pending left', role: CodeLabTextRole.caption),
          ],
        ],
      );
    } else {
      final statusLabel = completed == 0 ? '$total Tasks' : '$completed/$total';
      title = Row(
        children: [
          const Expanded(
            child: CodeLabText('Plan', role: CodeLabTextRole.caption),
          ),
          CodeLabText(statusLabel, role: CodeLabTextRole.caption),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 8),
        CodeLabIconButton(
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

  final List<CodeLabPlanEntry> entries;

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

  final CodeLabPlanEntry entry;

  @override
  Widget build(BuildContext context) {
    final completed = entry.status == CodeLabPlanEntryStatus.completed;
    final baseStyle = FluentTheme.of(context).typography.body;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeLabIcon(_statusIcon, tone: _statusTone, size: 16),
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
        CodeLabBadge(label: _priorityLabel, tone: _priorityTone),
      ],
    );
  }

  IconData get _statusIcon => switch (entry.status) {
    CodeLabPlanEntryStatus.pending => FluentIcons.circle_ring,
    CodeLabPlanEntryStatus.inProgress => FluentIcons.skype_circle_clock,
    CodeLabPlanEntryStatus.completed => FluentIcons.status_circle_checkmark,
  };

  CodeLabTone get _statusTone => switch (entry.status) {
    CodeLabPlanEntryStatus.pending => CodeLabTone.neutral,
    CodeLabPlanEntryStatus.inProgress => CodeLabTone.accent,
    CodeLabPlanEntryStatus.completed => CodeLabTone.success,
  };

  String get _priorityLabel => switch (entry.priority) {
    CodeLabPlanEntryPriority.high => 'High',
    CodeLabPlanEntryPriority.medium => 'Medium',
    CodeLabPlanEntryPriority.low => 'Low',
  };

  CodeLabTone get _priorityTone => switch (entry.priority) {
    CodeLabPlanEntryPriority.high => CodeLabTone.danger,
    CodeLabPlanEntryPriority.medium => CodeLabTone.warning,
    CodeLabPlanEntryPriority.low => CodeLabTone.neutral,
  };
}
