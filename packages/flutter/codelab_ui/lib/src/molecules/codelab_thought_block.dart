import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Сворачиваемый блок мыслей модели.
///
/// Почему: мысли рисовались той же записью «Agent», что и ответ, и
/// пользователь не отличал рассуждение от результата (D-08; DSK-10;
/// change `redesign-transcript-rows`).
///
/// Для чего: приглушённый блок с заголовком «Thinking…» и индикатором, пока
/// мысли идут, и «Thoughts» после. Раскрыт он или нет, решает владелец — лента
/// по таблице design D3 и ручному выбору пользователя; блок только сообщает
/// о нажатии через [onToggle].
///
/// Как использовать: `CodeLabThoughtBlock(text:, streaming:, expanded:,
/// onToggle:)`. Во время стрима раскрытый блок показывает последние
/// [streamingTailLines] строк, чтобы не расти бесконечно; после — весь текст
/// как есть, без markdown. Раскрытие без анимации: лента не прыгает у
/// читающего пользователя (§12.3.6).
class CodeLabThoughtBlock extends StatelessWidget {
  const CodeLabThoughtBlock({
    required this.text,
    required this.streaming,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  static const headerKey = ValueKey('thought-block-header');
  static const streamingTailLines = 6;

  final String text;
  final bool streaming;
  final bool expanded;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final muted = FluentTheme.of(context).resources.textFillColorSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: streaming ? 'Thinking' : 'Thoughts',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: headerKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => onToggle(!expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    if (streaming)
                      const SizedBox.square(
                        dimension: 14,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    else
                      Icon(FluentIcons.lightbulb, size: 14, color: muted),
                    const SizedBox(width: 8),
                    CodeLabText(
                      streaming ? 'Thinking…' : 'Thoughts',
                      role: CodeLabTextRole.caption,
                      color: muted,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      expanded
                          ? FluentIcons.chevron_up_small
                          : FluentIcons.chevron_down_small,
                      size: 10,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded && text.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 6, top: 4),
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: muted.withAlpha(90))),
            ),
            child: CodeLabText(
              streaming ? _tail(text) : text,
              role: CodeLabTextRole.caption,
              color: muted,
            ),
          ),
      ],
    );
  }

  static String _tail(String text) {
    final lines = text.trimRight().split('\n');
    return lines.length <= streamingTailLines
        ? lines.join('\n')
        : lines.sublist(lines.length - streamingTailLines).join('\n');
  }
}
