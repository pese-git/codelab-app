import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'codelab_approval_panel.dart';
import 'codelab_transcript_row.dart';

/// Вызов инструмента в ленте: одна строка и раскрываемые подробности.
///
/// Почему: вызов рисовался карточкой с заголовком агента и вложенной строкой
/// «● Done think», где статус повторялся, а вид протокола показывался как
/// есть (change `redesign-transcript-rows`, D5; §12.1.6).
///
/// Для чего: заголовок — значок статуса, метка, моноширинная деталь, тег
/// статуса и шеврон; под ним — вторая строка, текстовый вывод и карточка
/// ожидающего одобрения. Пока вызов ждёт одобрения, тег — «Awaiting
/// approval», а строку нельзя свернуть: иначе пропадут кнопки решения.
///
/// Как использовать: `CodeLabToolCallTile(row:, expanded:, onToggle:)`;
/// раскрытие решает лента ([CodeLabTranscriptPanel]).
class CodeLabToolCallTile extends StatelessWidget {
  const CodeLabToolCallTile({
    required this.row,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  static const headerKey = ValueKey('tool-call-header');
  static const statusTagKey = ValueKey('tool-call-status');

  /// Сколько последних строк вывода видно в раскрытой строке.
  static const outputTailLines = 20;

  final CodeLabToolCallRow row;
  final bool expanded;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final canToggle = row.isExpandable && !row.awaitsApproval;
    final showBody = row.isExpandable && (expanded || row.awaitsApproval);
    // Вторая строка упавшего вызова — первая строка его же вывода: если
    // вывод ничего к ней не добавляет, он не повторяется под ней.
    final showOutput =
        row.output.isNotEmpty && _outputTail.trim() != row.secondary?.trim();
    final (statusLabel, statusTone) = _statusTag;
    final approval = row.approval;

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _StatusGlyph(row: row),
          const SizedBox(width: 10),
          CodeLabText(row.label, role: CodeLabTextRole.strong),
          if (row.detail.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: CodeLabText(
                row.detail,
                role: CodeLabTextRole.mono,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: 8),
          if (approval case CodeLabTranscriptApprovalResolved(
            :final label,
            :final outcome,
          )) ...[
            CodeLabBadge(label: label, tone: _outcomeTone(outcome)),
            const SizedBox(width: 6),
          ],
          CodeLabBadge(key: statusTagKey, label: statusLabel, tone: statusTone),
          if (canToggle) ...[
            const SizedBox(width: 6),
            Icon(
              expanded
                  ? FluentIcons.chevron_up_small
                  : FluentIcons.chevron_down_small,
              size: 10,
              color: theme.resources.textFillColorSecondary,
            ),
          ],
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(
          color: row.awaitsApproval
              ? theme.accentColor
              : theme.resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canToggle)
            Semantics(
              button: true,
              expanded: expanded,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: headerKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onToggle(!expanded),
                  child: header,
                ),
              ),
            )
          else
            KeyedSubtree(key: headerKey, child: header),
          if (showBody)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.resources.cardStrokeColorDefault,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (row.secondary case final secondary?)
                    CodeLabText(
                      secondary,
                      color: row.status == CodeLabToolCallStatus.failed
                          ? Colors.red
                          : null,
                    ),
                  if (showOutput) ...[
                    if (row.secondary != null) const SizedBox(height: 8),
                    CodeLabText(_outputTail, role: CodeLabTextRole.mono),
                  ],
                  if (approval
                      case final CodeLabTranscriptApprovalPending pending) ...[
                    if (row.secondary != null || showOutput)
                      const SizedBox(height: 12),
                    CodeLabApprovalPanel(
                      bordered: false,
                      optionsLayout: CodeLabApprovalOptionsLayout.compactRow,
                      title: pending.title,
                      risk: pending.risk,
                      reason: pending.reason,
                      command: pending.command,
                      cwd: pending.cwd,
                      diffSummary: pending.diffSummary,
                      rawInput: pending.rawInput,
                      options: pending.options,
                      selectedOptionId: pending.selectedOptionId,
                      enabled: pending.enabled,
                      approveOptionId: pending.approveOptionId,
                      rejectOptionId: pending.rejectOptionId,
                      shortcutsEnabled: pending.shortcutsEnabled,
                      onOptionSelected: pending.onOptionSelected,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  (String, CodeLabTone) get _statusTag {
    if (row.awaitsApproval) {
      return ('Awaiting approval', CodeLabTone.accent);
    }
    return switch (row.status) {
      CodeLabToolCallStatus.queued => ('Queued', CodeLabTone.neutral),
      CodeLabToolCallStatus.running => ('Running', CodeLabTone.accent),
      CodeLabToolCallStatus.succeeded => ('Done', CodeLabTone.success),
      CodeLabToolCallStatus.failed => ('Failed', CodeLabTone.danger),
      CodeLabToolCallStatus.cancelled => ('Cancelled', CodeLabTone.warning),
    };
  }

  String get _outputTail {
    final lines = row.output.join('\n').trimRight().split('\n');
    return lines.length <= outputTailLines
        ? lines.join('\n')
        : lines.sublist(lines.length - outputTailLines).join('\n');
  }

  // Тоны — как у тегов статуса: отмена — warning, отказ — danger.
  static CodeLabTone _outcomeTone(CodeLabApprovalOutcome outcome) =>
      switch (outcome) {
        CodeLabApprovalOutcome.allowed => CodeLabTone.success,
        CodeLabApprovalOutcome.rejected => CodeLabTone.danger,
        CodeLabApprovalOutcome.cancelled => CodeLabTone.warning,
        CodeLabApprovalOutcome.unknown => CodeLabTone.neutral,
      };
}

/// Значок статуса вызова; смысл дублируется тегом, цвет не единственный
/// носитель (§12.3, A5).
class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.row});

  final CodeLabToolCallRow row;

  @override
  Widget build(BuildContext context) {
    if (row.awaitsApproval) {
      return const CodeLabIcon(
        FluentIcons.permissions,
        tone: CodeLabTone.accent,
        size: 14,
      );
    }
    return switch (row.status) {
      CodeLabToolCallStatus.running => const SizedBox.square(
        dimension: 14,
        child: ProgressRing(strokeWidth: 2),
      ),
      CodeLabToolCallStatus.queued => const CodeLabIcon(
        FluentIcons.circle_ring,
        size: 14,
      ),
      CodeLabToolCallStatus.succeeded => const CodeLabIcon(
        FluentIcons.check_mark,
        tone: CodeLabTone.success,
        size: 14,
      ),
      CodeLabToolCallStatus.failed => const CodeLabIcon(
        FluentIcons.error_badge,
        tone: CodeLabTone.danger,
        size: 14,
      ),
      CodeLabToolCallStatus.cancelled => const CodeLabIcon(
        FluentIcons.cancel,
        tone: CodeLabTone.warning,
        size: 14,
      ),
    };
  }
}
