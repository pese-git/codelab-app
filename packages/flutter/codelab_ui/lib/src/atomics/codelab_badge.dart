import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_tone.dart';

class CodeLabBadge extends StatelessWidget {
  const CodeLabBadge({
    required this.label,
    this.tone = CodeLabTone.neutral,
    super.key,
  });

  final String label;
  final CodeLabTone tone;

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

Color _backgroundColorForTone(CodeLabTone tone) {
  return switch (tone) {
    CodeLabTone.neutral => Colors.grey.withAlpha(46),
    CodeLabTone.accent => Colors.blue.withAlpha(46),
    CodeLabTone.success => Colors.green.withAlpha(46),
    CodeLabTone.warning => Colors.warningPrimaryColor.withAlpha(56),
    CodeLabTone.danger => Colors.red.withAlpha(46),
  };
}

Color _foregroundColorForTone(CodeLabTone tone) {
  return switch (tone) {
    CodeLabTone.neutral => Colors.grey,
    CodeLabTone.accent => Colors.blue,
    CodeLabTone.success => Colors.green,
    CodeLabTone.warning => Colors.warningPrimaryColor,
    CodeLabTone.danger => Colors.red,
  };
}
