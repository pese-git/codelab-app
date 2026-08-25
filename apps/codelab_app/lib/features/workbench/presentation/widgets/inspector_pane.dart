import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../application/shell_cubit.dart';

class WorkbenchInspectorPane extends StatelessWidget {
  const WorkbenchInspectorPane({
    required this.state,
    required this.cubit,
    super.key,
  });

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: AcpText('Inspector', role: AcpTextRole.subtitle),
                ),
                AcpIconButton(
                  icon: FluentIcons.clear,
                  tooltip: 'Clear diagnostics',
                  onPressed: cubit.clearDiagnostics,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final entry in state.inspectorEntries) ...[
                  _InspectorEntryCard(entry: entry),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  height: 260,
                  child: AcpDebugLogPanel(
                    entries: state.diagnostics,
                    onClear: cubit.clearDiagnostics,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorEntryCard extends StatelessWidget {
  const _InspectorEntryCard({required this.entry});

  final CodeLabInspectorEntry entry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _toneColor.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _toneColor.withAlpha(56)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AcpBadge(label: _categoryLabel, tone: _tone),
                const SizedBox(width: 8),
                Expanded(
                  child: AcpText(
                    entry.title,
                    role: AcpTextRole.strong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AcpText(
              entry.summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (entry.risk != null || entry.status != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (entry.risk != null)
                    AcpBadge(label: 'Risk ${entry.risk}', tone: _riskTone),
                  if (entry.status != null)
                    AcpBadge(label: entry.status!, tone: AcpTone.neutral),
                ],
              ),
            ],
            if (entry.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final detail in entry.details)
                _InspectorDetailLine(detail: detail),
            ],
            if (entry.rawInput != null) ...[
              const SizedBox(height: 8),
              _InspectorRawBlock(label: 'Raw input', value: entry.rawInput!),
            ],
            if (entry.rawOutput != null) ...[
              const SizedBox(height: 8),
              _InspectorRawBlock(label: 'Raw output', value: entry.rawOutput!),
            ],
          ],
        ),
      ),
    );
  }

  String get _categoryLabel {
    return switch (entry.category) {
      CodeLabInspectorCategory.approval => 'Approval',
      CodeLabInspectorCategory.toolCall => 'Tool',
      CodeLabInspectorCategory.protocol => 'Protocol',
      CodeLabInspectorCategory.diagnostic => 'Diagnostic',
    };
  }

  AcpTone get _tone {
    return switch (entry.category) {
      CodeLabInspectorCategory.approval => AcpTone.warning,
      CodeLabInspectorCategory.toolCall => AcpTone.accent,
      CodeLabInspectorCategory.protocol => AcpTone.neutral,
      CodeLabInspectorCategory.diagnostic => AcpTone.danger,
    };
  }

  AcpTone get _riskTone {
    return switch (entry.risk) {
      'readOnly' => AcpTone.success,
      'localWrite' || 'network' => AcpTone.warning,
      'shell' || 'destructive' => AcpTone.danger,
      _ => AcpTone.neutral,
    };
  }

  Color get _toneColor {
    return switch (entry.category) {
      CodeLabInspectorCategory.approval => Colors.orange,
      CodeLabInspectorCategory.toolCall => Colors.blue,
      CodeLabInspectorCategory.protocol => Colors.grey,
      CodeLabInspectorCategory.diagnostic => Colors.red,
    };
  }
}

class _InspectorDetailLine extends StatelessWidget {
  const _InspectorDetailLine({required this.detail});

  final CodeLabInspectorDetail detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: AcpText(detail.label, role: AcpTextRole.caption),
          ),
          Expanded(
            child: AcpText(
              detail.value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorRawBlock extends StatelessWidget {
  const _InspectorRawBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AcpText(label, role: AcpTextRole.caption),
            const SizedBox(height: 4),
            AcpText(value, maxLines: 8, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
