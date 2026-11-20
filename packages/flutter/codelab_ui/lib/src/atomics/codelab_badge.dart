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
    final theme = FluentTheme.of(context);
    final palette = CodeLabPalette.of(theme);
    final color = _backgroundColorForTone(palette, theme, tone);
    final foreground = palette.toneColor(tone, theme);

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

Color _backgroundColorForTone(
  CodeLabPalette palette,
  FluentThemeData theme,
  CodeLabTone tone,
) {
  final base = palette.toneColor(tone, theme);
  return base.withAlpha(switch (tone) {
    CodeLabTone.warning => 56,
    _ => 46,
  });
}
