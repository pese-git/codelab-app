import 'package:fluent_ui/fluent_ui.dart';

import 'acp_tone.dart';

class AcpIcon extends StatelessWidget {
  const AcpIcon(this.icon, {this.tone = AcpTone.neutral, this.size, super.key});

  final IconData icon;
  final AcpTone tone;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, color: _colorForTone(tone), size: size);
  }
}

Color _colorForTone(AcpTone tone) {
  return switch (tone) {
    AcpTone.neutral => Colors.grey,
    AcpTone.accent => Colors.blue,
    AcpTone.success => Colors.green,
    AcpTone.warning => Colors.warningPrimaryColor,
    AcpTone.danger => Colors.red,
  };
}
