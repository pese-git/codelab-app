import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'codelab_approval_prompt.dart';
import 'codelab_transcript_row.dart';

/// Вызов инструмента в ленте: одна строка и раскрываемые подробности.
///
/// Почему: вызов рисовался карточкой с заголовком агента и вложенной строкой
/// «● Done think», где статус повторялся, а вид протокола показывался как
/// есть (change `redesign-transcript-rows`, D5; §12.1.6).
///
/// Для чего: шапка раскрывашки ([CodeLabExpanderCard], как в макете) —
/// значок статуса, метка и через пробел моноширинная деталь, тег статуса и
/// шеврон; под ним — вторая строка и текстовый вывод. Пока вызов ждёт
/// одобрения (change `lighten-approval-block`): деталь — команда целиком,
/// до трёх строк и «Show full command» для остального (D5); вместо тега
/// статуса — тег риска (D6); внизу — полоса решения
/// [CodeLabApprovalPrompt]. Свернуть такую строку нельзя: иначе
/// пропадут кнопки решения.
///
/// Как использовать: `CodeLabToolCallTile(row:, expanded:, onToggle:)`;
/// раскрытие решает лента ([CodeLabTranscriptPanel]).
class CodeLabToolCallTile extends StatefulWidget {
  const CodeLabToolCallTile({
    required this.row,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  static const headerKey = ValueKey('tool-call-header');
  static const statusTagKey = ValueKey('tool-call-status');
  static const showFullCommandKey = ValueKey('tool-call-show-full-command');

  /// Сколько последних строк вывода видно в раскрытой строке.
  static const outputTailLines = 20;

  /// Сколько строк команды видно в шапке до «Show full command».
  static const pendingDetailLines = 3;

  final CodeLabToolCallRow row;
  final bool expanded;
  final ValueChanged<bool> onToggle;

  @override
  State<CodeLabToolCallTile> createState() => _CodeLabToolCallTileState();
}

class _CodeLabToolCallTileState extends State<CodeLabToolCallTile> {
  /// Пользователь раскрыл длинную команду в шапке. Это временный просмотр
  /// до решения, а не выбор о ленте, поэтому он живёт в `State` строки, а не
  /// в `TranscriptViewCubit` (design D5).
  bool _showFullDetail = false;

  CodeLabToolCallRow get row => widget.row;

  @override
  Widget build(BuildContext context) {
    final canToggle = row.isExpandable && !row.awaitsApproval;
    final showBody =
        row.isExpandable && (widget.expanded || row.awaitsApproval);
    // Вторая строка упавшего вызова — первая строка его же вывода: если
    // вывод ничего к ней не добавляет, он не повторяется под ней.
    final showOutput =
        row.output.isNotEmpty && _outputTail.trim() != row.secondary?.trim();
    final approval = row.approval;
    final resolved = approval is CodeLabTranscriptApprovalResolved
        ? approval
        : null;
    final pending = approval is CodeLabTranscriptApprovalPending
        ? approval
        : null;
    final (statusLabel, statusTone) = pending == null
        ? _statusTag
        : (pending.risk.label, pending.risk.tone);

    final body = showBody
        ? Column(
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
              if (pending != null) ...[
                if (row.secondary != null || showOutput)
                  const SizedBox(height: 12),
                CodeLabApprovalPrompt(
                  reason: pending.reason,
                  diffSummary: pending.diffSummary,
                  rawInput: pending.rawInput,
                  options: pending.options,
                  enabled: pending.enabled,
                  approveOptionId: pending.approveOptionId,
                  rejectOptionId: pending.rejectOptionId,
                  shortcutsEnabled: pending.shortcutsEnabled,
                  onOptionSelected: pending.onOptionSelected,
                ),
              ],
            ],
          )
        : null;

    return CodeLabExpanderCard(
      headerKey: CodeLabToolCallTile.headerKey,
      expanded: widget.expanded,
      onToggle: canToggle ? widget.onToggle : null,
      leading: _StatusGlyph(row: row),
      title: pending == null
          ? _title(context, row.detail, maxLines: 1)
          : _pendingTitle(context, pending.command ?? row.detail),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (resolved != null) ...[
            CodeLabBadge(
              label: resolved.label,
              tone: _outcomeTone(resolved.outcome),
            ),
            const SizedBox(width: 6),
          ],
          CodeLabBadge(
            key: CodeLabToolCallTile.statusTagKey,
            label: statusLabel,
            tone: statusTone,
          ),
        ],
      ),
      // Полоса решения — узкая полоса внизу строки под тонкой линией тела
      // (design D3): поля минимальные, отступы держат сами кнопки.
      bodyPadding: pending != null
          ? const EdgeInsets.all(4)
          : const EdgeInsets.all(16),
      body: body,
    );
  }

  /// Метка и деталь — одна фраза через пробел, как в макете: «Read
  /// lib/main.dart», а не две колонки.
  Text _title(BuildContext context, String detail, {int? maxLines}) {
    final theme = FluentTheme.of(context);
    return Text.rich(
      _titleSpan(context, detail),
      style: theme.typography.body,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }

  TextSpan _titleSpan(BuildContext context, String detail) {
    final muted = FluentTheme.of(context).resources.textFillColorSecondary;
    return TextSpan(
      children: [
        TextSpan(text: row.label),
        if (detail.isNotEmpty) ...[
          const TextSpan(text: ' '),
          TextSpan(
            text: detail,
            style: CodeLabText.styleOf(
              context,
              CodeLabTextRole.mono,
            )?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }

  /// Шапка ждущего вызова: команда целиком, до [pendingDetailLines] строк;
  /// длиннее — «Show full command» показывает остальное на месте. До
  /// решения команда не обрезается многоточием: пользователь одобряет ровно
  /// то, что выполнится (spec «Long command is never cut before the
  /// decision»).
  Widget _pendingTitle(BuildContext context, String detail) {
    const lines = CodeLabToolCallTile.pendingDetailLines;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            style: FluentTheme.of(context).typography.body,
            children: [_titleSpan(context, detail)],
          ),
          maxLines: lines,
          textDirection: Directionality.of(context),
          textScaler:
              MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
        )..layout(maxWidth: constraints.maxWidth);
        final exceeds = painter.didExceedMaxLines;
        painter.dispose();
        if (!exceeds) {
          return _title(context, detail);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Обрезка по строкам без многоточия: остаток открывает ссылка
            // ниже, а не скрывает «…» посреди команды.
            _showFullDetail
                ? _title(context, detail)
                : Text.rich(
                    _titleSpan(context, detail),
                    style: FluentTheme.of(context).typography.body,
                    maxLines: lines,
                    overflow: TextOverflow.clip,
                  ),
            HyperlinkButton(
              key: CodeLabToolCallTile.showFullCommandKey,
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              onPressed: () =>
                  setState(() => _showFullDetail = !_showFullDetail),
              child: Text(_showFullDetail ? 'Show less' : 'Show full command'),
            ),
          ],
        );
      },
    );
  }

  (String, CodeLabTone) get _statusTag {
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
    return lines.length <= CodeLabToolCallTile.outputTailLines
        ? lines.join('\n')
        : lines
              .sublist(lines.length - CodeLabToolCallTile.outputTailLines)
              .join('\n');
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
