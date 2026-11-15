import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import '../rendering/escape_for_display.dart';
import 'codelab_transcript_row.dart';

// Внутренний файл организмов (не экспортируется из `organisms.dart`): общие
// компактные строки вызовов, которые рисуют и хвост строки `agent` в
// `CodeLabToolCallTile`, и дерево шагов `CodeLabAgentsPane` (D27, D49 Т10).
// Вынесены, чтобы панель не дублировала вид строк ленты.

/// Значок статуса вызова; смысл дублируется тегом, цвет не единственный
/// носитель (§12.3, A5).
class StatusGlyph extends StatelessWidget {
  const StatusGlyph({required this.row, super.key});

  final CodeLabToolCallRow row;

  @override
  Widget build(BuildContext context) {
    if (row.awaitsApproval ||
        row.awaitsChildApproval ||
        row.awaitsRootDecision) {
      return const CodeLabIcon(
        FluentIcons.permissions,
        tone: CodeLabTone.accent,
        size: 16,
      );
    }
    return switch (row.status) {
      CodeLabToolCallStatus.running => const SizedBox.square(
        dimension: 16,
        child: ProgressRing(strokeWidth: 2),
      ),
      CodeLabToolCallStatus.queued => const CodeLabIcon(
        FluentIcons.circle_ring,
        size: 16,
      ),
      CodeLabToolCallStatus.succeeded => const CodeLabIcon(
        FluentIcons.check_mark,
        tone: CodeLabTone.success,
        size: 16,
      ),
      CodeLabToolCallStatus.failed => const CodeLabIcon(
        FluentIcons.error_badge,
        tone: CodeLabTone.danger,
        size: 16,
      ),
      CodeLabToolCallStatus.cancelled => const CodeLabIcon(
        FluentIcons.cancel,
        tone: CodeLabTone.warning,
        size: 16,
      ),
    };
  }
}

/// Метка и деталь строки одной фразой. Для вложенных строк [escape] включает
/// видимые escape-символы: команду и путь вложенного вызова пишет модель, и
/// bidi-символы не должны переставить видимый текст (`AGENTS.md` §10, D47).
TextSpan rowTitleSpan(
  BuildContext context,
  CodeLabToolCallRow row,
  String detail, {
  required bool escape,
}) {
  final muted = FluentTheme.of(context).resources.textFillColorSecondary;
  final label = escape ? escapeForDisplay(row.label) : row.label;
  final shown = escape ? escapeForDisplay(detail) : detail;
  return TextSpan(
    children: [
      TextSpan(text: label),
      if (shown.isNotEmpty) ...[
        const TextSpan(text: ' '),
        TextSpan(
          text: shown,
          style: CodeLabText.styleOf(
            context,
            CodeLabTextRole.mono,
          )?.copyWith(color: muted),
        ),
      ],
    ],
  );
}

/// Компактная однострочная строка вызова: глиф статуса и «метка деталь»
/// одной фразой (D25, D27). Без рамки и шапки: хвост под свёрнутым `agent` и
/// дерево шагов панели Agents — обзор, а не раскрывашка; вызов раскрывается в
/// теле строки `agent` ленты.
///
/// [trailing] — необязательные виджеты справа (тег «Awaiting approval» и
/// действие перехода в панели Agents); [indent] — отступ слева по глубине
/// вложенности дерева шагов.
class TailLine extends StatelessWidget {
  const TailLine({
    required this.row,
    required this.title,
    this.trailing = const [],
    this.indent = 0,
    super.key,
  });

  final CodeLabToolCallRow row;
  final Widget title;
  final List<Widget> trailing;
  final double indent;

  /// Заголовок вызова потомка: текст пишет модель, поэтому с escape-ами.
  static Widget titleOf(BuildContext context, CodeLabToolCallRow row) {
    return Text.rich(
      rowTitleSpan(context, row, row.detail, escape: true),
      style: FluentTheme.of(context).typography.body,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
      child: Row(
        children: [
          StatusGlyph(row: row),
          const SizedBox(width: 8),
          Expanded(child: title),
          for (final widget in trailing) ...[const SizedBox(width: 8), widget],
        ],
      ),
    );
  }
}
