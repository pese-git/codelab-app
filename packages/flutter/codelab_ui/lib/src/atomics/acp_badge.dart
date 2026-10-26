import 'package:fluent_ui/fluent_ui.dart';

import 'acp_tone.dart';

class AcpBadge extends StatelessWidget {
  const AcpBadge({required this.label, this.tone = AcpTone.neutral, super.key});

  final String label;
  final AcpTone tone;

  @override
  Widget build(BuildContext context) {
    final color = _backgroundColorForTone(tone);
    final foreground = _foregroundColorForTone(tone);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FluentTheme.of(context).typography.caption?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

Color _backgroundColorForTone(AcpTone tone) {
  return switch (tone) {
    AcpTone.neutral => Colors.grey.withAlpha(46),
    AcpTone.accent => Colors.blue.withAlpha(46),
    AcpTone.success => Colors.green.withAlpha(46),
    AcpTone.warning => Colors.warningPrimaryColor.withAlpha(56),
    AcpTone.danger => Colors.red.withAlpha(46),
  };
}

Color _foregroundColorForTone(AcpTone tone) {
  return switch (tone) {
    AcpTone.neutral => Colors.grey,
    AcpTone.accent => Colors.blue,
    AcpTone.success => Colors.green,
    AcpTone.warning => Colors.warningPrimaryColor,
    AcpTone.danger => Colors.red,
  };
}
