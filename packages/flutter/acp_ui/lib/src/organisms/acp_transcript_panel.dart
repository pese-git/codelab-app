import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'acp_approval_panel.dart';

enum AcpTranscriptEntryKind { user, agent, toolCall, approval, diagnostic }

/// Approval state carried by a [AcpTranscriptEntry] for the tool call it
/// belongs to — rendered inline in the entry's own row, not as a separate
/// panel outside the transcript.
sealed class AcpTranscriptApproval {
  const AcpTranscriptApproval();

  const factory AcpTranscriptApproval.pending({
    required AcpApprovalRisk risk,
    required List<AcpApprovalOption> options,
    required AcpApprovalOptionSelected onOptionSelected,
    String? reason,
    String? command,
    String? cwd,
    String? diffSummary,
    String? selectedOptionId,
    bool enabled,
    String? approveOptionId,
    String? rejectOptionId,
    bool shortcutsEnabled,
  }) = AcpTranscriptApprovalPending;

  const factory AcpTranscriptApproval.resolved({required String label}) =
      AcpTranscriptApprovalResolved;
}

final class AcpTranscriptApprovalPending extends AcpTranscriptApproval {
  const AcpTranscriptApprovalPending({
    required this.risk,
    required this.options,
    required this.onOptionSelected,
    this.reason,
    this.command,
    this.cwd,
    this.diffSummary,
    this.selectedOptionId,
    this.enabled = true,
    this.approveOptionId,
    this.rejectOptionId,
    this.shortcutsEnabled = true,
  });

  final AcpApprovalRisk risk;
  final List<AcpApprovalOption> options;
  final AcpApprovalOptionSelected onOptionSelected;
  final String? reason;
  final String? command;
  final String? cwd;
  final String? diffSummary;
  final String? selectedOptionId;
  final bool enabled;
  final String? approveOptionId;
  final String? rejectOptionId;
  final bool shortcutsEnabled;
}

final class AcpTranscriptApprovalResolved extends AcpTranscriptApproval {
  const AcpTranscriptApprovalResolved({required this.label});

  final String label;
}

class AcpTranscriptEntry {
  const AcpTranscriptEntry({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.toolCall,
    this.timestampLabel,
    this.approval,
  });

  final String id;
  final AcpTranscriptEntryKind kind;
  final String title;
  final String? body;
  final AcpToolCallSummary? toolCall;
  final String? timestampLabel;

  /// Non-null only for a [AcpTranscriptEntryKind.toolCall] entry that has an
  /// associated `ApprovalRequest` — pending (interactive) or resolved
  /// (compact marker).
  final AcpTranscriptApproval? approval;
}

/// How close to the bottom (in pixels) counts as "the user is following the
/// live tail of the transcript" — a new pending approval only auto-scrolls
/// into view when the user was already within this distance of the bottom.
const _autoScrollBottomThreshold = 80.0;

class AcpTranscriptPanel extends StatefulWidget {
  const AcpTranscriptPanel({
    required this.entries,
    this.emptyLabel = 'No transcript yet',
    this.viewMode = AcpViewMode.normal,
    super.key,
  });

  final List<AcpTranscriptEntry> entries;
  final String emptyLabel;
  final AcpViewMode viewMode;

  @override
  State<AcpTranscriptPanel> createState() => _AcpTranscriptPanelState();
}

class _AcpTranscriptPanelState extends State<AcpTranscriptPanel> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AcpTranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newPendingApprovalIds = _pendingApprovalEntryIds(
      widget.entries,
    ).difference(_pendingApprovalEntryIds(oldWidget.entries));
    if (newPendingApprovalIds.isEmpty || !_controller.hasClients) {
      return;
    }

    final position = _controller.position;
    final wasNearBottom =
        position.maxScrollExtent - position.pixels <=
        _autoScrollBottomThreshold;
    if (!wasNearBottom) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) {
        return;
      }
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: widget.entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AcpText(widget.emptyLabel, role: AcpTextRole.caption),
              ),
            )
          : ListView.separated(
              controller: _controller,
              padding: const EdgeInsets.all(12),
              itemCount: widget.entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _AcpTranscriptEntryRow(
                  entry: widget.entries[index],
                  viewMode: widget.viewMode,
                );
              },
            ),
    );
  }
}

Set<String> _pendingApprovalEntryIds(List<AcpTranscriptEntry> entries) {
  return {
    for (final entry in entries)
      if (entry.approval is AcpTranscriptApprovalPending) entry.id,
  };
}

class _AcpTranscriptEntryRow extends StatelessWidget {
  const _AcpTranscriptEntryRow({required this.entry, required this.viewMode});

  final AcpTranscriptEntry entry;
  final AcpViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _backgroundColor(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AcpIcon(_icon, tone: _tone, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AcpText(
                          entry.title,
                          role: AcpTextRole.strong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.timestampLabel != null) ...[
                        const SizedBox(width: 8),
                        AcpText(
                          entry.timestampLabel!,
                          role: AcpTextRole.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  if (entry.body != null) ...[
                    const SizedBox(height: 6),
                    if (entry.kind == AcpTranscriptEntryKind.toolCall)
                      AcpText(
                        entry.body!,
                        maxLines: _bodyMaxLines,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      AcpText(entry.body!),
                  ],
                  if (entry.toolCall != null) ...[
                    const SizedBox(height: 8),
                    _toolCallForMode(entry.toolCall!),
                  ],
                  if (entry.approval case final approval?) ...[
                    const SizedBox(height: 8),
                    _AcpTranscriptApprovalContent(approval: approval),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _backgroundColor(BuildContext context) {
    return switch (entry.kind) {
      AcpTranscriptEntryKind.user => Colors.blue.withAlpha(24),
      AcpTranscriptEntryKind.agent => Colors.grey.withAlpha(24),
      AcpTranscriptEntryKind.toolCall => Colors.warningPrimaryColor.withAlpha(
        24,
      ),
      AcpTranscriptEntryKind.approval => Colors.orange.withAlpha(24),
      AcpTranscriptEntryKind.diagnostic => Colors.red.withAlpha(20),
    };
  }

  IconData get _icon {
    return switch (entry.kind) {
      AcpTranscriptEntryKind.user => FluentIcons.contact,
      AcpTranscriptEntryKind.agent => FluentIcons.robot,
      AcpTranscriptEntryKind.toolCall => FluentIcons.processing,
      AcpTranscriptEntryKind.approval => FluentIcons.permissions,
      AcpTranscriptEntryKind.diagnostic => FluentIcons.warning,
    };
  }

  AcpTone get _tone {
    return switch (entry.kind) {
      AcpTranscriptEntryKind.user => AcpTone.accent,
      AcpTranscriptEntryKind.agent => AcpTone.neutral,
      AcpTranscriptEntryKind.toolCall => AcpTone.warning,
      AcpTranscriptEntryKind.approval => AcpTone.warning,
      AcpTranscriptEntryKind.diagnostic => AcpTone.danger,
    };
  }

  int get _bodyMaxLines {
    return switch (viewMode) {
      AcpViewMode.summary => 1,
      AcpViewMode.normal => 4,
      AcpViewMode.verbose => 8,
    };
  }

  Widget _toolCallForMode(AcpToolCallSummary toolCall) {
    return AcpToolCallSummary(
      name: toolCall.name,
      status: toolCall.status,
      target: toolCall.target,
      detail: toolCall.detail,
      viewMode: viewMode,
    );
  }
}

class _AcpTranscriptApprovalContent extends StatelessWidget {
  const _AcpTranscriptApprovalContent({required this.approval});

  final AcpTranscriptApproval approval;

  @override
  Widget build(BuildContext context) {
    return switch (approval) {
      AcpTranscriptApprovalPending(
        :final risk,
        :final reason,
        :final command,
        :final cwd,
        :final diffSummary,
        :final options,
        :final selectedOptionId,
        :final enabled,
        :final approveOptionId,
        :final rejectOptionId,
        :final shortcutsEnabled,
        :final onOptionSelected,
      ) =>
        AcpApprovalPanel(
          bordered: false,
          optionsLayout: AcpApprovalOptionsLayout.compactRow,
          risk: risk,
          reason: reason,
          command: command,
          cwd: cwd,
          diffSummary: diffSummary,
          options: options,
          selectedOptionId: selectedOptionId,
          enabled: enabled,
          approveOptionId: approveOptionId,
          rejectOptionId: rejectOptionId,
          shortcutsEnabled: shortcutsEnabled,
          onOptionSelected: onOptionSelected,
        ),
      AcpTranscriptApprovalResolved(:final label) => Row(
        children: [
          const AcpIcon(
            FluentIcons.check_mark,
            tone: AcpTone.success,
            size: 13,
          ),
          const SizedBox(width: 6),
          AcpText(label, role: AcpTextRole.caption),
        ],
      ),
    };
  }
}
