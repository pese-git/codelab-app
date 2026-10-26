import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_icon.dart';
import 'codelab_tone.dart';

enum CodeLabStatusTone { idle, active, warning, danger }

class CodeLabStatusIndicator extends StatelessWidget {
  const CodeLabStatusIndicator({
    required this.label,
    this.tone = CodeLabStatusTone.idle,
    super.key,
  });

  final String label;
  final CodeLabStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CodeLabIcon(
          FluentIcons.circle_fill,
          size: 8,
          tone: _toneForStatus(tone),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

CodeLabTone _toneForStatus(CodeLabStatusTone tone) {
  return switch (tone) {
    CodeLabStatusTone.idle => CodeLabTone.neutral,
    CodeLabStatusTone.active => CodeLabTone.success,
    CodeLabStatusTone.warning => CodeLabTone.warning,
    CodeLabStatusTone.danger => CodeLabTone.danger,
  };
}
