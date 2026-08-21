import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widget_previews.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'acp_approval_panel.dart';
import 'acp_transcript_panel.dart';

const acpOrganismPreviewGroup = 'ACP organisms';

@Preview(name: 'Transcript panel', group: acpOrganismPreviewGroup)
Widget acpTranscriptPanelPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 360,
      child: AcpTranscriptPanel(
        entries: [
          AcpTranscriptEntry(
            id: 'user-1',
            kind: AcpTranscriptEntryKind.user,
            title: 'You',
            body: 'Run analyzer and summarize any failures.',
            timestampLabel: '12:04',
          ),
          AcpTranscriptEntry(
            id: 'agent-1',
            kind: AcpTranscriptEntryKind.agent,
            title: 'Codelab Agent',
            body: 'I will inspect the workspace checks.',
            timestampLabel: '12:04',
          ),
          AcpTranscriptEntry(
            id: 'tool-1',
            kind: AcpTranscriptEntryKind.toolCall,
            title: 'Tool call',
            toolCall: AcpToolCallSummary(
              name: 'shell',
              target: 'fvm dart analyze',
              status: AcpToolCallStatus.running,
              detail: 'packages/flutter/acp_ui',
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(name: 'Approval panel', group: acpOrganismPreviewGroup)
Widget acpApprovalPanelPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      child: AcpApprovalPanel(
        title: 'Run shell command',
        risk: AcpApprovalRisk.shell,
        reason: 'The agent wants to verify the Flutter UI package.',
        command: 'fvm dart run melos run analyze',
        cwd: 'packages/flutter/acp_ui',
        selectedOptionId: 'allow_once',
        onOptionSelected: acpPreviewApprovalSelected,
        options: const [
          AcpApprovalOption(
            id: 'allow_once',
            label: 'Allow once',
            description: 'Run this command for the active prompt turn.',
            tone: AcpTone.warning,
          ),
          AcpApprovalOption(
            id: 'reject',
            label: 'Reject',
            description: 'Return a denied outcome to the agent.',
            tone: AcpTone.danger,
          ),
        ],
      ),
    ),
  );
}

void acpPreviewApprovalSelected(String optionId) {}

class _AcpOrganismPreviewSurface extends StatelessWidget {
  const _AcpOrganismPreviewSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}
