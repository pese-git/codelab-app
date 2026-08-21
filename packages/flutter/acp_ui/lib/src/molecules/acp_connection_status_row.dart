import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

enum AcpConnectionStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  failed,
}

class AcpConnectionStatusRow extends StatelessWidget {
  const AcpConnectionStatusRow({
    required this.status,
    required this.transportLabel,
    required this.profileLabel,
    this.detail,
    super.key,
  });

  final AcpConnectionStatus status;
  final String transportLabel;
  final String profileLabel;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AcpStatusIndicator(label: _statusLabel, tone: _statusTone),
        const SizedBox(width: 10),
        AcpBadge(label: transportLabel, tone: AcpTone.accent),
        const SizedBox(width: 6),
        Flexible(
          child: AcpText(
            profileLabel,
            role: AcpTextRole.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: AcpText(
              detail!,
              role: AcpTextRole.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  String get _statusLabel {
    return switch (status) {
      AcpConnectionStatus.idle => 'Idle',
      AcpConnectionStatus.connecting => 'Connecting',
      AcpConnectionStatus.connected => 'Connected',
      AcpConnectionStatus.reconnecting => 'Reconnecting',
      AcpConnectionStatus.disconnected => 'Disconnected',
      AcpConnectionStatus.failed => 'Failed',
    };
  }

  AcpStatusTone get _statusTone {
    return switch (status) {
      AcpConnectionStatus.idle => AcpStatusTone.idle,
      AcpConnectionStatus.connecting => AcpStatusTone.warning,
      AcpConnectionStatus.connected => AcpStatusTone.active,
      AcpConnectionStatus.reconnecting => AcpStatusTone.warning,
      AcpConnectionStatus.disconnected => AcpStatusTone.warning,
      AcpConnectionStatus.failed => AcpStatusTone.danger,
    };
  }
}
