import 'package:fluent_ui/fluent_ui.dart';

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
    return Icon(icon, color: _colorForTone(tone), size: size);
  }
}

Color _colorForTone(CodeLabTone tone) {
  return switch (tone) {
    CodeLabTone.neutral => Colors.grey,
    CodeLabTone.accent => Colors.blue,
    CodeLabTone.success => Colors.green,
    CodeLabTone.warning => Colors.warningPrimaryColor,
    CodeLabTone.danger => Colors.red,
  };
}
