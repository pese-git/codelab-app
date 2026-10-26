import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

typedef CodeLabSessionSelected = void Function(String sessionId);

enum CodeLabSessionStatus {
  idle,
  running,
  awaitingApproval,
  completed,
  failed,
  cancelled,
}

class CodeLabSessionListItem {
  const CodeLabSessionListItem({
    required this.id,
    required this.title,
    required this.status,
    this.subtitle,
    this.updatedLabel,
  });

  final String id;
  final String title;
  final CodeLabSessionStatus status;
  final String? subtitle;
  final String? updatedLabel;
}

class CodeLabSessionSidebar extends StatelessWidget {
  const CodeLabSessionSidebar({
    required this.sessions,
    required this.onSessionSelected,
    this.activeSessionId,
    this.onNewSession,
    this.emptyLabel = 'No sessions yet',
    super.key,
  });

  final List<CodeLabSessionListItem> sessions;
  final String? activeSessionId;
  final CodeLabSessionSelected onSessionSelected;
  final VoidCallback? onNewSession;
  final String emptyLabel;

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
                  child: CodeLabText(
                    'Sessions',
                    role: CodeLabTextRole.subtitle,
                  ),
                ),
                if (onNewSession != null)
                  CodeLabIconButton(
                    key: const ValueKey('new-session-button'),
                    icon: FluentIcons.add,
                    tooltip: 'New session',
                    onPressed: onNewSession,
                  ),
              ],
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: CodeLabText(
                      emptyLabel,
                      role: CodeLabTextRole.caption,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: sessions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return _AcpSessionTile(
                        session: session,
                        selected: session.id == activeSessionId,
                        onSelected: () => onSessionSelected(session.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AcpSessionTile extends StatelessWidget {
  const _AcpSessionTile({
    required this.session,
    required this.selected,
    required this.onSelected,
  });

  final CodeLabSessionListItem session;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: onSelected,
      style: ButtonStyle(
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (selected) {
            return Colors.blue.withAlpha(28);
          }
          if (states.isHovered) {
            return Colors.grey.withAlpha(18);
          }
          return Colors.transparent;
        }),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CodeLabIcon(_statusIcon, tone: _statusTone, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CodeLabText(
                          session.title,
                          role: CodeLabTextRole.strong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CodeLabBadge(label: _statusLabel, tone: _statusTone),
                    ],
                  ),
                  if (session.subtitle != null) ...[
                    const SizedBox(height: 4),
                    CodeLabText(
                      session.subtitle!,
                      role: CodeLabTextRole.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (session.updatedLabel != null) ...[
                    const SizedBox(height: 4),
                    CodeLabText(
                      session.updatedLabel!,
                      role: CodeLabTextRole.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _statusLabel {
    return switch (session.status) {
      CodeLabSessionStatus.idle => 'Idle',
      CodeLabSessionStatus.running => 'Running',
      CodeLabSessionStatus.awaitingApproval => 'Approval',
      CodeLabSessionStatus.completed => 'Done',
      CodeLabSessionStatus.failed => 'Failed',
      CodeLabSessionStatus.cancelled => 'Cancelled',
    };
  }

  CodeLabTone get _statusTone {
    return switch (session.status) {
      CodeLabSessionStatus.idle => CodeLabTone.neutral,
      CodeLabSessionStatus.running => CodeLabTone.accent,
      CodeLabSessionStatus.awaitingApproval => CodeLabTone.warning,
      CodeLabSessionStatus.completed => CodeLabTone.success,
      CodeLabSessionStatus.failed => CodeLabTone.danger,
      CodeLabSessionStatus.cancelled => CodeLabTone.warning,
    };
  }

  IconData get _statusIcon {
    return switch (session.status) {
      CodeLabSessionStatus.idle => FluentIcons.circle_ring,
      CodeLabSessionStatus.running => FluentIcons.processing,
      CodeLabSessionStatus.awaitingApproval => FluentIcons.permissions,
      CodeLabSessionStatus.completed => FluentIcons.completed,
      CodeLabSessionStatus.failed => FluentIcons.error,
      CodeLabSessionStatus.cancelled => FluentIcons.cancel,
    };
  }
}
