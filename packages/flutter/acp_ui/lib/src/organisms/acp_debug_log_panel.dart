import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

enum AcpDebugLogSeverity { debug, info, warning, error }

class AcpDebugLogEntry {
  const AcpDebugLogEntry({
    required this.id,
    required this.severity,
    required this.message,
    this.source,
    this.timestampLabel,
  });

  final String id;
  final AcpDebugLogSeverity severity;
  final String message;
  final String? source;
  final String? timestampLabel;
}

class AcpDebugLogPanel extends StatelessWidget {
  const AcpDebugLogPanel({
    required this.entries,
    this.emptyLabel = 'No diagnostics yet',
    this.onClear,
    super.key,
  });

  final List<AcpDebugLogEntry> entries;
  final String emptyLabel;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: AcpText('Debug log', role: AcpTextRole.subtitle),
                ),
                if (onClear != null)
                  AcpIconButton(
                    icon: FluentIcons.clear,
                    tooltip: 'Clear log',
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(child: AcpText(emptyLabel, role: AcpTextRole.caption))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: entries.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _AcpDebugLogEntryRow(entry: entries[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AcpDebugLogEntryRow extends StatelessWidget {
  const _AcpDebugLogEntryRow({required this.entry});

  final AcpDebugLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _toneColor.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AcpBadge(label: _severityLabel, tone: _tone),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (entry.source != null) ...[
                        Flexible(
                          child: AcpText(
                            entry.source!,
                            role: AcpTextRole.strong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (entry.timestampLabel != null)
                        AcpText(
                          entry.timestampLabel!,
                          role: AcpTextRole.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  AcpText(
                    entry.message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _severityLabel {
    return switch (entry.severity) {
      AcpDebugLogSeverity.debug => 'Debug',
      AcpDebugLogSeverity.info => 'Info',
      AcpDebugLogSeverity.warning => 'Warning',
      AcpDebugLogSeverity.error => 'Error',
    };
  }

  AcpTone get _tone {
    return switch (entry.severity) {
      AcpDebugLogSeverity.debug => AcpTone.neutral,
      AcpDebugLogSeverity.info => AcpTone.accent,
      AcpDebugLogSeverity.warning => AcpTone.warning,
      AcpDebugLogSeverity.error => AcpTone.danger,
    };
  }

  Color get _toneColor {
    return switch (entry.severity) {
      AcpDebugLogSeverity.debug => Colors.grey,
      AcpDebugLogSeverity.info => Colors.blue,
      AcpDebugLogSeverity.warning => Colors.warningPrimaryColor,
      AcpDebugLogSeverity.error => Colors.red,
    };
  }
}
