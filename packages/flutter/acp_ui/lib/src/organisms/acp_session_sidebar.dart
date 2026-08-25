import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

typedef AcpSessionSelected = void Function(String sessionId);

enum AcpSessionStatus {
  idle,
  running,
  awaitingApproval,
  completed,
  failed,
  cancelled,
}

class AcpSessionListItem {
  const AcpSessionListItem({
    required this.id,
    required this.title,
    required this.status,
    this.subtitle,
    this.updatedLabel,
  });

  final String id;
  final String title;
  final AcpSessionStatus status;
  final String? subtitle;
  final String? updatedLabel;
}

class AcpSessionSidebar extends StatelessWidget {
  const AcpSessionSidebar({
    required this.sessions,
    required this.onSessionSelected,
    this.activeSessionId,
    this.onNewSession,
    this.emptyLabel = 'No sessions yet',
    super.key,
  });

  final List<AcpSessionListItem> sessions;
  final String? activeSessionId;
  final AcpSessionSelected onSessionSelected;
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
                  child: AcpText('Sessions', role: AcpTextRole.subtitle),
                ),
                if (onNewSession != null)
                  AcpIconButton(
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
                ? Center(child: AcpText(emptyLabel, role: AcpTextRole.caption))
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

  final AcpSessionListItem session;
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
            AcpIcon(_statusIcon, tone: _statusTone, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AcpText(
                          session.title,
                          role: AcpTextRole.strong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AcpBadge(label: _statusLabel, tone: _statusTone),
                    ],
                  ),
                  if (session.subtitle != null) ...[
                    const SizedBox(height: 4),
                    AcpText(
                      session.subtitle!,
                      role: AcpTextRole.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (session.updatedLabel != null) ...[
                    const SizedBox(height: 4),
                    AcpText(
                      session.updatedLabel!,
                      role: AcpTextRole.caption,
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
      AcpSessionStatus.idle => 'Idle',
      AcpSessionStatus.running => 'Running',
      AcpSessionStatus.awaitingApproval => 'Approval',
      AcpSessionStatus.completed => 'Done',
      AcpSessionStatus.failed => 'Failed',
      AcpSessionStatus.cancelled => 'Cancelled',
    };
  }

  AcpTone get _statusTone {
    return switch (session.status) {
      AcpSessionStatus.idle => AcpTone.neutral,
      AcpSessionStatus.running => AcpTone.accent,
      AcpSessionStatus.awaitingApproval => AcpTone.warning,
      AcpSessionStatus.completed => AcpTone.success,
      AcpSessionStatus.failed => AcpTone.danger,
      AcpSessionStatus.cancelled => AcpTone.warning,
    };
  }

  IconData get _statusIcon {
    return switch (session.status) {
      AcpSessionStatus.idle => FluentIcons.circle_ring,
      AcpSessionStatus.running => FluentIcons.processing,
      AcpSessionStatus.awaitingApproval => FluentIcons.permissions,
      AcpSessionStatus.completed => FluentIcons.completed,
      AcpSessionStatus.failed => FluentIcons.error,
      AcpSessionStatus.cancelled => FluentIcons.cancel,
    };
  }
}
