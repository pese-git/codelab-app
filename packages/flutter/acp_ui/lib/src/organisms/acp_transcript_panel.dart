import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

enum AcpTranscriptEntryKind { user, agent, toolCall, approval, diagnostic }

class AcpTranscriptEntry {
  const AcpTranscriptEntry({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.toolCall,
    this.timestampLabel,
  });

  final String id;
  final AcpTranscriptEntryKind kind;
  final String title;
  final String? body;
  final AcpToolCallSummary? toolCall;
  final String? timestampLabel;
}

class AcpTranscriptPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AcpText(emptyLabel, role: AcpTextRole.caption),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _AcpTranscriptEntryRow(
                  entry: entries[index],
                  viewMode: viewMode,
                );
              },
            ),
    );
  }
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
                    AcpText(
                      entry.body!,
                      maxLines: _bodyMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (entry.toolCall != null) ...[
                    const SizedBox(height: 8),
                    _toolCallForMode(entry.toolCall!),
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
