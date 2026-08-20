import 'package:fluent_ui/fluent_ui.dart';

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
    final color = switch (tone) {
      AcpStatusTone.idle => Colors.grey,
      AcpStatusTone.active => Colors.green,
      AcpStatusTone.warning => Colors.warningPrimaryColor,
      AcpStatusTone.danger => Colors.red,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(FluentIcons.circle_fill, size: 8, color: color),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
