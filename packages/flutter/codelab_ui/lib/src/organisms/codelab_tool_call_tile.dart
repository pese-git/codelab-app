import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import '../rendering/escape_for_display.dart';
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
    this.nestedExpanded,
    this.onNestedToggle,
    this.depth = 0,
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

  /// Раскрыта ли вложенная строка [CodeLabToolCallRow.children] по её id;
  /// без обработчика вложенные строки свёрнуты. Состояние хранит лента
  /// (`TranscriptViewCubit`, D47 Т11), а не `State` строки: строки
  /// виртуализированы.
  final bool Function(String rowId)? nestedExpanded;

  /// Пользователь раскрыл или свернул вложенную строку [rowId].
  final void Function(String rowId, bool expanded)? onNestedToggle;

  /// Глубина вложенности: 0 — строка ленты. У вложенных строк текст модели
  /// показывается с видимыми escape-символами (`escapeForDisplay`).
  final int depth;

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
              if (row.children.isNotEmpty) ...[
                if (row.secondary != null) const SizedBox(height: 8),
                _nestedRows(),
              ],
              if (showOutput) ...[
                if (row.secondary != null || row.children.isNotEmpty)
                  const SizedBox(height: 8),
                CodeLabText(_outputTail, role: CodeLabTextRole.mono),
              ],
              if (pending != null) ...[
                if (row.secondary != null || showOutput)
                  const SizedBox(height: 12),
                if (pending.requesterLine case final line?)
                  _RequesterHeader(line: line, hint: pending.requesterHint),
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

    final card = CodeLabExpanderCard(
      headerKey: CodeLabToolCallTile.headerKey,
      expanded: widget.expanded,
      onToggle: canToggle ? widget.onToggle : null,
      leading: _StatusGlyph(row: row),
      title: pending == null
          ? _withProgress(context, _title(context, row.detail, maxLines: 1))
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
          if (row.subagent?.stats case final stats?) ...[
            CodeLabText(stats, role: CodeLabTextRole.mono),
            const SizedBox(width: 12),
          ],
          if (!_hidesStatusTag(pending != null))
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
    if (row.childApprovals.isEmpty) {
      return card;
    }
    // Блоки потомков стоят под строкой корня и не зависят от её раскрытия:
    // дерево предков не раскрывается (D27 п. 4, D43 п. 2).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        for (final child in row.childApprovals)
          _ChildApprovalBlock(approval: child),
      ],
    );
  }

  /// Вложенные строки потомков с отступом по глубине: те же компактные
  /// строки, а операции со списком задач — тихими строками без рамки и тега
  /// (D24, D48 п. 3). Вложенный `agent` раскрывается по своему id.
  Widget _nestedRows() {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in row.children)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: switch (child) {
                final CodeLabToolCallRow call => CodeLabToolCallTile(
                  key: ValueKey('nested-${call.id}'),
                  row: call,
                  expanded: widget.nestedExpanded?.call(call.id) ?? false,
                  onToggle: (expanded) =>
                      widget.onNestedToggle?.call(call.id, expanded),
                  nestedExpanded: widget.nestedExpanded,
                  onNestedToggle: widget.onNestedToggle,
                  depth: widget.depth + 1,
                ),
                CodeLabTaskOpsRow(:final text) => CodeLabTaskOpsLine(
                  text: text,
                ),
                _ => const SizedBox.shrink(),
              },
            ),
        ],
      ),
    );
  }

  /// Свёрнутый успешный `agent` не несёт тега «Done»: статус передаёт глиф
  /// (D27, spec agent-workbench-ui «Завершённый субагент свёрнут»).
  /// «Failed», «Cancelled» и «Running» остаются; ждущий одобрения — тоже.
  bool _hidesStatusTag(bool pending) =>
      row.subagent != null &&
      !pending &&
      !widget.expanded &&
      row.status == CodeLabToolCallStatus.succeeded;

  /// Что стоит под заголовком свёрнутой строки работающего `agent`: хвост из
  /// трёх последних вызовов поддерева и «+N more tool calls» (D25, Q15), а
  /// клиенту без дерева — последняя строка прогресса (D27 п. 3).
  Widget _withProgress(BuildContext context, Widget title) {
    if (row.status != CodeLabToolCallStatus.running || widget.expanded) {
      return title;
    }
    final subagent = row.subagent;
    if (subagent != null && subagent.tail.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 4),
          for (final item in subagent.tail)
            switch (item) {
              final CodeLabToolCallRow call => _TailLine(
                row: call,
                title: _TailLine.titleOf(context, call),
              ),
              CodeLabTaskOpsRow(:final text) => CodeLabTaskOpsLine(text: text),
              _ => const SizedBox.shrink(),
            },
          if (subagent.tailMore > 0)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: CodeLabText(
                '+${subagent.tailMore} more tool calls',
                role: CodeLabTextRole.caption,
              ),
            ),
        ],
      );
    }
    final progress = subagent?.progress;
    if (progress == null || progress.isEmpty) {
      return title;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        CodeLabText(progress, role: CodeLabTextRole.mono, maxLines: 1),
      ],
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
    return _rowTitleSpan(context, row, detail, escape: widget.depth > 0);
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
    // Вложенный вызов ждёт решения в блоке под строкой корня: тег говорит
    // об ожидании, а кнопок у строки нет (D27 п. 4).
    if (row.awaitsRootDecision) {
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

/// Строка пути спрашивающего субагента над панелью решения.
///
/// Почему: путь «review › explore wants to run» говорит, чей это запрос;
/// заголовок задачи — в подсказке и строкой под путём (D27 п. 4).
/// Для чего: показать готовые строки kit; виджет путь не строит.
class _RequesterHeader extends StatelessWidget {
  const _RequesterHeader({required this.line, this.hint});

  final String line;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = CodeLabText(line, role: CodeLabTextRole.mono);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hint case final hint? when hint.isNotEmpty) ...[
            Tooltip(message: hint, child: text),
            CodeLabText(hint),
          ] else
            text,
        ],
      ),
    );
  }
}

/// Блок одобрения потомка под строкой `agent` корня: путь, команда и панель
/// решения, а после решения — тег исхода (spec agent-workbench-ui «Запрос
/// одобрения от субагента под строкой корня»). Решение уходит тем же
/// обработчиком запроса, что и у обычного одобрения (PERM-4).
class _ChildApprovalBlock extends StatelessWidget {
  const _ChildApprovalBlock({required this.approval});

  final CodeLabTranscriptApproval approval;

  @override
  Widget build(BuildContext context) {
    return switch (approval) {
      CodeLabTranscriptApprovalPending() => _pending(
        context,
        approval as CodeLabTranscriptApprovalPending,
      ),
      CodeLabTranscriptApprovalResolved(
        :final label,
        :final outcome,
        :final requesterLine,
      ) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 4, 0, 4),
          child: Row(
            children: [
              CodeLabBadge(label: label, tone: _ToolCallTones.outcome(outcome)),
              if (requesterLine != null) ...[
                const SizedBox(width: 8),
                CodeLabText(requesterLine, role: CodeLabTextRole.mono),
              ],
            ],
          ),
        ),
    };
  }

  Widget _pending(BuildContext context, CodeLabTranscriptApprovalPending p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p.requesterLine case final line?)
            _RequesterHeader(line: line, hint: p.requesterHint),
          if (p.callTitle case final title? when title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // Заголовок пишет модель: управляющие и bidi-символы показываем
              // escape-ами, чтобы они не переставили видимый путь. Без
              // maxLines: длинный путь переносится, а не обрезается.
              child: CodeLabText(
                escapeForDisplay(title),
                role: CodeLabTextRole.mono,
              ),
            ),
          if (p.command case final command?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // Команду пишет модель; когда заголовок скрыт как её дубль,
              // это единственная копия, поэтому bidi/управляющие символы
              // экранируем (без обрезки: решение принимают по полной
              // команде). D44 п. 4.
              child: CodeLabText(
                escapeForDisplay(command),
                role: CodeLabTextRole.mono,
              ),
            ),
          CodeLabApprovalPrompt(
            reason: p.reason,
            diffSummary: p.diffSummary,
            rawInput: p.rawInput,
            options: p.options,
            enabled: p.enabled,
            approveOptionId: p.approveOptionId,
            rejectOptionId: p.rejectOptionId,
            shortcutsEnabled: p.shortcutsEnabled,
            onOptionSelected: p.onOptionSelected,
          ),
        ],
      ),
    );
  }
}

/// Тоны тега исхода — те же, что у тега строки вызова.
abstract final class _ToolCallTones {
  static CodeLabTone outcome(CodeLabApprovalOutcome outcome) =>
      _CodeLabToolCallTileState._outcomeTone(outcome);
}

/// Метка и деталь строки одной фразой. Для вложенных строк [escape] включает
/// видимые escape-символы: команду и путь вложенного вызова пишет модель, и
/// bidi-символы не должны переставить видимый текст (`AGENTS.md` §10, D47).
TextSpan _rowTitleSpan(
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

/// Тихая строка операций со списком задач (D27): иконка списка и приглушённый
/// текст, без рамки, тега статуса и панели вывода. Рисуется и в ленте, и
/// внутри раскрытого `agent` (D48 п. 3); [text] целиком собирает kit.
class CodeLabTaskOpsLine extends StatelessWidget {
  const CodeLabTaskOpsLine({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const CodeLabIcon(FluentIcons.bulleted_list, size: 14),
          const SizedBox(width: 8),
          Expanded(child: CodeLabText(text, role: CodeLabTextRole.caption)),
        ],
      ),
    );
  }
}

/// Строка хвоста под свёрнутым работающим `agent`: глиф статуса и «метка
/// деталь» одной фразой (D25). Без рамки и шапки: хвост — обзор, а не
/// раскрывашка; вызов раскрывается в теле строки `agent`.
class _TailLine extends StatelessWidget {
  const _TailLine({required this.row, required this.title});

  final CodeLabToolCallRow row;
  final Widget title;

  /// Заголовок вызова потомка: текст пишет модель, поэтому с escape-ами.
  static Widget titleOf(BuildContext context, CodeLabToolCallRow row) {
    return Text.rich(
      _rowTitleSpan(context, row, row.detail, escape: true),
      style: FluentTheme.of(context).typography.body,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          _StatusGlyph(row: row),
          const SizedBox(width: 8),
          Expanded(child: title),
        ],
      ),
    );
  }
}
