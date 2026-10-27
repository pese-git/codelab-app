import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

enum CodeLabApprovalRisk { readOnly, localWrite, network, shell, destructive }

class CodeLabApprovalPanel extends StatelessWidget {
  const CodeLabApprovalPanel({
    this.title,
    required this.risk,
    required this.options,
    required this.onOptionSelected,
    this.reason,
    this.command,
    this.cwd,
    this.diffSummary,
    this.rawInput,
    this.selectedOptionId,
    this.enabled = true,
    this.approveOptionId,
    this.rejectOptionId,
    this.shortcutsEnabled = true,
    this.bordered = true,
    this.optionsLayout = CodeLabApprovalOptionsLayout.list,
    this.statusLabel,
    super.key,
  });

  /// Тег состояния рядом с риском — «Awaiting approval» в строке вызова
  /// ленты (change `redesign-transcript-rows`, D5); `null` — без тега.
  final String? statusLabel;

  /// Omit when a host (e.g. a transcript entry) already renders an
  /// equivalent title for the tool call this approval belongs to — showing
  /// only the risk badge in that case.
  final String? title;
  final CodeLabApprovalRisk risk;
  final String? reason;
  final String? command;
  final String? cwd;
  final String? diffSummary;

  /// The tool call's raw input, shown behind a collapsed "View raw input"
  /// disclosure — unlike the inspector's always-visible raw input, this is
  /// opt-in since the approval panel is read on the golden path.
  final String? rawInput;
  final List<CodeLabApprovalOption> options;
  final String? selectedOptionId;
  final CodeLabApprovalOptionSelected onOptionSelected;
  final bool enabled;
  final String? approveOptionId;
  final String? rejectOptionId;
  final bool shortcutsEnabled;

  /// When `false`, renders without the outer border/background/padding —
  /// for hosts (e.g. a transcript entry) that already provide their own
  /// framing and would otherwise double it up.
  final bool bordered;

  /// See [CodeLabApprovalOptionsLayout] — `list` (default) for the standalone
  /// panel, `compactRow` for an inline-embedded transcript entry.
  final CodeLabApprovalOptionsLayout optionsLayout;

  /// Промежуток между частями карточки — 8, как в макете (карточка
  /// «Run a command?» артборда Main): заголовок, команда и кнопки читаются
  /// одним блоком.
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (title case final title?) ...[
              Expanded(
                child: CodeLabText(
                  title,
                  role: CodeLabTextRole.strong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (title == null) const Spacer(),
            if (statusLabel case final status?) ...[
              CodeLabBadge(label: status, tone: CodeLabTone.accent),
              const SizedBox(width: 6),
            ],
            CodeLabBadge(label: _riskLabel, tone: _riskTone),
          ],
        ),
        if (reason != null) ...[
          const SizedBox(height: 8),
          CodeLabText(reason!, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        if (_hasDetails) ...[
          const SizedBox(height: _gap),
          _ApprovalDetails(
            command: command,
            cwd: cwd,
            diffSummary: diffSummary,
          ),
        ],
        if (rawInput case final rawInput?) ...[
          const SizedBox(height: _gap),
          CodeLabTextDisclosure(label: 'View raw input', text: rawInput),
        ],
        const SizedBox(height: _gap),
        CodeLabApprovalOptionGroup(
          options: options,
          selectedOptionId: selectedOptionId,
          enabled: enabled,
          approveOptionId: approveOptionId,
          rejectOptionId: rejectOptionId,
          shortcutsEnabled: shortcutsEnabled,
          layout: optionsLayout,
          onSelected: onOptionSelected,
        ),
      ],
    );

    if (!bordered) {
      return content;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withAlpha(64)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: content),
    );
  }

  bool get _hasDetails => command != null || cwd != null || diffSummary != null;

  String get _riskLabel {
    return switch (risk) {
      CodeLabApprovalRisk.readOnly => 'Read-only',
      CodeLabApprovalRisk.localWrite => 'Local write',
      CodeLabApprovalRisk.network => 'Network',
      CodeLabApprovalRisk.shell => 'Shell',
      CodeLabApprovalRisk.destructive => 'Destructive',
    };
  }

  CodeLabTone get _riskTone {
    return switch (risk) {
      CodeLabApprovalRisk.readOnly => CodeLabTone.success,
      CodeLabApprovalRisk.localWrite => CodeLabTone.warning,
      CodeLabApprovalRisk.network => CodeLabTone.warning,
      CodeLabApprovalRisk.shell => CodeLabTone.danger,
      CodeLabApprovalRisk.destructive => CodeLabTone.danger,
    };
  }
}

/// Подробности запроса: команда — в терминальном блоке, `cwd` и сводка
/// правки — подписями под ним (артборд Main, карточка «Run a command?»).
class _ApprovalDetails extends StatelessWidget {
  const _ApprovalDetails({this.command, this.cwd, this.diffSummary});

  final String? command;
  final String? cwd;
  final String? diffSummary;

  @override
  Widget build(BuildContext context) {
    final command = this.command;
    final cwd = this.cwd;
    final diffSummary = this.diffSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (command != null)
          DecoratedBox(
            key: const ValueKey('approval-command'),
            // Терминальный блок тёмный в обеих темах, как в макете: команда
            // читается как то, что выполнится в оболочке.
            decoration: BoxDecoration(
              color: const Color(0xFF1F2328),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: CodeLabText(
                '\$ $command',
                role: CodeLabTextRole.mono,
                color: const Color(0xFFE6EDF3),
              ),
            ),
          ),
        if (cwd != null) ...[
          const SizedBox(height: 4),
          CodeLabText(cwd, role: CodeLabTextRole.caption),
        ],
        if (diffSummary != null) ...[
          const SizedBox(height: 4),
          CodeLabText(diffSummary, role: CodeLabTextRole.caption),
        ],
      ],
    );
  }
}
