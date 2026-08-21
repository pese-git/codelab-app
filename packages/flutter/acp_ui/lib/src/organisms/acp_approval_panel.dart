import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

enum AcpApprovalRisk { readOnly, localWrite, network, shell, destructive }

class AcpApprovalPanel extends StatelessWidget {
  const AcpApprovalPanel({
    required this.title,
    required this.risk,
    required this.options,
    required this.onOptionSelected,
    this.reason,
    this.command,
    this.cwd,
    this.diffSummary,
    this.selectedOptionId,
    this.enabled = true,
    super.key,
  });

  final String title;
  final AcpApprovalRisk risk;
  final String? reason;
  final String? command;
  final String? cwd;
  final String? diffSummary;
  final List<AcpApprovalOption> options;
  final String? selectedOptionId;
  final AcpApprovalOptionSelected onOptionSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withAlpha(64)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AcpText(
                    title,
                    role: AcpTextRole.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
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
            const SizedBox(height: 12),
            AcpApprovalOptionGroup(
              options: options,
              selectedOptionId: selectedOptionId,
              enabled: enabled,
              onSelected: onOptionSelected,
            ),
          ],
        ),
      ),
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
