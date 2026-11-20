import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_palette.dart';
import 'codelab_tone.dart';

class CodeLabIcon extends StatelessWidget {
  const CodeLabIcon(
    this.icon, {
    this.tone = CodeLabTone.neutral,
    this.size,
    super.key,
  });

  final IconData icon;
  final CodeLabTone tone;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Icon(
      icon,
      color: CodeLabPalette.of(theme).toneColor(tone, theme),
      size: size,
    );
  }
}
