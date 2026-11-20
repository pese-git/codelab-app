import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../l10n/strings.dart';
import '../molecules/molecules.dart';
import '../rendering/escape_for_display.dart';
import 'codelab_approval_prompt.dart';
import 'codelab_compact_call_line.dart';
import 'codelab_transcript_row.dart';
import 'codelab_transcript_target.dart';

/// Ключ полосы решения ожидающего одобрения: без сессии или id ключа нет.
Key? _promptKeyOf(CodeLabTranscriptApprovalPending p) =>
    switch ((p.sessionId, p.targetId)) {
      (final session?, final id?) => CodeLabApprovalPrompt.keyFor(session, id),
      _ => null,
    };

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
    this.highlightedId,
    this.onApprovalFocusReleased,
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

  /// Id цели показа, которая подсвечена сейчас (вложенная строка или блок
  /// одобрения потомка внутри этой строки); `null` — подсветки нет (D49 Т7).
  final String? highlightedId;

  /// Полоса одобрения этой строки (и блоков потомков под ней) с клавиатурным
  /// фокусом исчезла: лента передаёт хосту, чтобы тот вернул фокус
  /// (`fix-approval-focus`, D5).
  final VoidCallback? onApprovalFocusReleased;

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
        ? _statusTag(context)
        : (pending.risk.labelOf(context), pending.risk.tone);

    final body = showBody
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (row.secondary case final secondary?)
                CodeLabText(
                  secondary,
                  color: row.status == CodeLabToolCallStatus.failed
                      ? CodeLabPalette.of(FluentTheme.of(context)).danger
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
                  key: _promptKeyOf(pending),
                  onApprovalFocusReleased: widget.onApprovalFocusReleased,
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
      leading: StatusGlyph(row: row),
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
          _targetOf(
            child.targetId,
            _ChildApprovalBlock(
              approval: child,
              onApprovalFocusReleased: widget.onApprovalFocusReleased,
            ),
          ),
      ],
    );
  }

  /// Рамка цели показа вокруг блока с id; без id блок не адресуется.
  Widget _targetOf(String? id, Widget child) => id == null
      ? child
      : TranscriptTargetFrame(
          id: id,
          highlighted: widget.highlightedId == id,
          child: child,
        );

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
                final CodeLabToolCallRow call => _targetOf(
                  call.id,
                  CodeLabToolCallTile(
                    key: ValueKey('nested-${call.id}'),
                    row: call,
                    expanded: widget.nestedExpanded?.call(call.id) ?? false,
                    onToggle: (expanded) =>
                        widget.onNestedToggle?.call(call.id, expanded),
                    nestedExpanded: widget.nestedExpanded,
                    onNestedToggle: widget.onNestedToggle,
                    depth: widget.depth + 1,
                    highlightedId: widget.highlightedId,
                    onApprovalFocusReleased: widget.onApprovalFocusReleased,
                  ),
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
              final CodeLabToolCallRow call => TailLine(
                row: call,
                title: TailLine.titleOf(context, call),
              ),
              CodeLabTaskOpsRow(:final text) => CodeLabTaskOpsLine(text: text),
              _ => const SizedBox.shrink(),
            },
          if (subagent.tailMore > 0)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: CodeLabText(
                codeLabStringsOf(
                  context,
                ).codeLabCallMoreToolCalls(subagent.tailMore),
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
    return rowTitleSpan(context, row, detail, escape: widget.depth > 0);
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
              child: Text(
                _showFullDetail
                    ? codeLabStringsOf(context).codeLabCallShowLess
                    : codeLabStringsOf(context).codeLabCallShowFullCommand,
              ),
            ),
          ],
        );
      },
    );
  }

  (String, CodeLabTone) _statusTag(BuildContext context) {
    final strings = codeLabStringsOf(context);
    // Вложенный вызов ждёт решения в блоке под строкой корня: тег говорит
    // об ожидании, а кнопок у строки нет (D27 п. 4).
    if (row.awaitsRootDecision) {
      return (strings.codeLabApprovalAwaiting, CodeLabTone.accent);
    }
    return switch (row.status) {
      CodeLabToolCallStatus.queued => (
        strings.codeLabCallQueued,
        CodeLabTone.neutral,
      ),
      CodeLabToolCallStatus.running => (
        strings.codeLabCallRunning,
        CodeLabTone.accent,
      ),
      CodeLabToolCallStatus.succeeded => (
        strings.codeLabCallDone,
        CodeLabTone.success,
      ),
      CodeLabToolCallStatus.failed => (
        strings.codeLabCallFailed,
        CodeLabTone.danger,
      ),
      CodeLabToolCallStatus.cancelled => (
        strings.codeLabCallCancelled,
        CodeLabTone.warning,
      ),
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
  const _ChildApprovalBlock({
    required this.approval,
    this.onApprovalFocusReleased,
  });

  final CodeLabTranscriptApproval approval;
  final VoidCallback? onApprovalFocusReleased;

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
            key: _promptKeyOf(p),
            onApprovalFocusReleased: onApprovalFocusReleased,
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
