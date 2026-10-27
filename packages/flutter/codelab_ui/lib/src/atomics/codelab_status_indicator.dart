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
        if (label.isNotEmpty) ...[
          const SizedBox(width: 8),
          // Подпись сжимается с многоточием, когда индикатор стоит в узкой
          // строке (change `redesign-workbench-shell`, 5.3).
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
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
