import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

enum AcpToolCallStatus { queued, running, succeeded, failed, cancelled }

class AcpToolCallSummary extends StatelessWidget {
  const AcpToolCallSummary({
    required this.name,
    required this.status,
    this.target,
    this.detail,
    super.key,
  });

  final String name;
  final AcpToolCallStatus status;
  final String? target;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            AcpStatusIndicator(label: _statusLabel, tone: _statusTone),
            const SizedBox(width: 10),
            Expanded(
              child: AcpText(
                target == null ? name : '$name - $target',
                role: AcpTextRole.strong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: 10),
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
        ),
      ),
    );
  }

  String get _statusLabel {
    return switch (status) {
      AcpToolCallStatus.queued => 'Queued',
      AcpToolCallStatus.running => 'Running',
      AcpToolCallStatus.succeeded => 'Done',
      AcpToolCallStatus.failed => 'Failed',
      AcpToolCallStatus.cancelled => 'Cancelled',
    };
  }

  AcpStatusTone get _statusTone {
    return switch (status) {
      AcpToolCallStatus.queued => AcpStatusTone.idle,
      AcpToolCallStatus.running => AcpStatusTone.active,
      AcpToolCallStatus.succeeded => AcpStatusTone.active,
      AcpToolCallStatus.failed => AcpStatusTone.danger,
      AcpToolCallStatus.cancelled => AcpStatusTone.warning,
    };
  }
}
