import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

enum AcpApprovalRisk { readOnly, localWrite, network, shell, destructive }

class AcpApprovalPanel extends StatelessWidget {
  const AcpApprovalPanel({
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
    this.optionsLayout = AcpApprovalOptionsLayout.list,
    super.key,
  });

  /// Omit when a host (e.g. a transcript entry) already renders an
  /// equivalent title for the tool call this approval belongs to — showing
  /// only the risk badge in that case.
  final String? title;
  final AcpApprovalRisk risk;
  final String? reason;
  final String? command;
  final String? cwd;
  final String? diffSummary;

  /// The tool call's raw input, shown behind a collapsed "View raw input"
  /// disclosure — unlike the inspector's always-visible raw input, this is
  /// opt-in since the approval panel is read on the golden path.
  final String? rawInput;
  final List<AcpApprovalOption> options;
  final String? selectedOptionId;
  final AcpApprovalOptionSelected onOptionSelected;
  final bool enabled;
  final String? approveOptionId;
  final String? rejectOptionId;
  final bool shortcutsEnabled;

  /// When `false`, renders without the outer border/background/padding —
  /// for hosts (e.g. a transcript entry) that already provide their own
  /// framing and would otherwise double it up.
  final bool bordered;

  /// See [AcpApprovalOptionsLayout] — `list` (default) for the standalone
  /// panel, `compactRow` for an inline-embedded transcript entry.
  final AcpApprovalOptionsLayout optionsLayout;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (title case final title?) ...[
              Expanded(
                child: AcpText(
                  title,
                  role: AcpTextRole.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
            ],
            AcpBadge(label: _riskLabel, tone: _riskTone),
          ],
        ),
        if (reason != null) ...[
          const SizedBox(height: 8),
          AcpText(reason!, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        if (_hasDetails) ...[
          const SizedBox(height: 12),
          _ApprovalDetails(
            command: command,
            cwd: cwd,
            diffSummary: diffSummary,
          ),
        ],
        if (rawInput case final rawInput?) ...[
          const SizedBox(height: 12),
          _RawInputDisclosure(rawInput: rawInput),
        ],
        const SizedBox(height: 12),
        AcpApprovalOptionGroup(
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
      AcpApprovalRisk.readOnly => 'Read-only',
      AcpApprovalRisk.localWrite => 'Local write',
      AcpApprovalRisk.network => 'Network',
      AcpApprovalRisk.shell => 'Shell',
      AcpApprovalRisk.destructive => 'Destructive',
    };
  }

  AcpTone get _riskTone {
    return switch (risk) {
      AcpApprovalRisk.readOnly => AcpTone.success,
      AcpApprovalRisk.localWrite => AcpTone.warning,
      AcpApprovalRisk.network => AcpTone.warning,
      AcpApprovalRisk.shell => AcpTone.danger,
      AcpApprovalRisk.destructive => AcpTone.danger,
    };
  }
}

class _ApprovalDetails extends StatelessWidget {
  const _ApprovalDetails({this.command, this.cwd, this.diffSummary});

  final String? command;
  final String? cwd;
  final String? diffSummary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (command != null)
              _ApprovalDetailLine(label: 'Command', value: command!),
            if (cwd != null) _ApprovalDetailLine(label: 'CWD', value: cwd!),
            if (diffSummary != null)
              _ApprovalDetailLine(label: 'Diff', value: diffSummary!),
          ],
        ),
      ),
    );
  }
}

class _ApprovalDetailLine extends StatelessWidget {
  const _ApprovalDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 74, child: AcpText(label, role: AcpTextRole.caption)),
          Expanded(
            child: AcpText(value, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// A minimal collapsed-by-default disclosure for the tool call's raw input.
///
/// Not `fluent_ui`'s `Expander`: that widget reads `PageStorage.of(context)`
/// in `initState`, which throws outside a `Navigator` ancestor — a real
/// crash surfaced by running this panel in the widget-preview environment
/// and in `acp_previews_test.dart`, both of which render organisms bare
/// (no `FluentApp`/`Navigator`), matching every other preview in this file.
class _RawInputDisclosure extends StatefulWidget {
  const _RawInputDisclosure({required this.rawInput});

  final String rawInput;

  @override
  State<_RawInputDisclosure> createState() => _RawInputDisclosureState();
}

class _RawInputDisclosureState extends State<_RawInputDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Button(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? FluentIcons.chevron_up : FluentIcons.chevron_down,
                size: 10,
              ),
              const SizedBox(width: 6),
              const AcpText('View raw input', role: AcpTextRole.caption),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 6),
          AcpText(widget.rawInput, role: AcpTextRole.caption),
        ],
      ],
    );
  }
}
