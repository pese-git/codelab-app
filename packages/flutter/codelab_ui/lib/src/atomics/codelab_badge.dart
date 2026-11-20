import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_palette.dart';
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
    final palette = CodeLabPalette.of(FluentTheme.of(context));
    final color = _backgroundColorForTone(palette, tone);
    final foreground = palette.toneColor(tone);

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

Color _backgroundColorForTone(CodeLabPalette palette, CodeLabTone tone) {
  final base = palette.toneColor(tone);
  return base.withAlpha(switch (tone) {
    CodeLabTone.warning => 56,
    _ => 46,
  });
}
