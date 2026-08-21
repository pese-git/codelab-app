import 'package:fluent_ui/fluent_ui.dart';

import 'acp_icon.dart';
import 'acp_tone.dart';

enum AcpStatusTone { idle, active, warning, danger }

class AcpStatusIndicator extends StatelessWidget {
  const AcpStatusIndicator({
    required this.label,
    this.tone = AcpStatusTone.idle,
    super.key,
  });

  final String label;
  final AcpStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AcpIcon(FluentIcons.circle_fill, size: 8, tone: _toneForStatus(tone)),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

AcpTone _toneForStatus(AcpStatusTone tone) {
  return switch (tone) {
    AcpStatusTone.idle => AcpTone.neutral,
    AcpStatusTone.active => AcpTone.success,
    AcpStatusTone.warning => AcpTone.warning,
    AcpStatusTone.danger => AcpTone.danger,
  };
}
