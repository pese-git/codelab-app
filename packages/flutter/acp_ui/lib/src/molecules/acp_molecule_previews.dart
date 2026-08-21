import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widget_previews.dart';

import 'acp_approval_option_group.dart';
import 'acp_connection_status_row.dart';
import 'acp_prompt_composer.dart';
import 'acp_tool_call_summary.dart';
import 'acp_view_mode.dart';
import '../atomics/atomics.dart';

const acpMoleculePreviewGroup = 'ACP molecules';

@Preview(
  name: 'Prompt composer',
  group: acpMoleculePreviewGroup,
  size: Size(620, 120),
)
Widget acpPromptComposerPreview() {
  return _AcpPreviewSurface(
    child: AcpPromptComposer(
      initialPrompt: 'Summarize the current diff',
      canCancel: true,
      onSubmit: acpPreviewPromptSubmit,
      onCancel: acpPreviewCancel,
    ),
  );
}

@Preview(
  name: 'Tool call summary normal',
  group: acpMoleculePreviewGroup,
  size: Size(520, 120),
)
Widget acpToolCallSummaryPreview() {
  return const _AcpPreviewSurface(
    child: AcpToolCallSummary(
      name: 'shell',
      target: 'fvm dart analyze',
      status: AcpToolCallStatus.running,
      detail: 'cwd packages/flutter/acp_ui',
    ),
  );
}

@Preview(
  name: 'Tool call summary summary',
  group: acpMoleculePreviewGroup,
  size: Size(360, 120),
)
Widget acpToolCallSummarySummaryPreview() {
  return const _AcpPreviewSurface(
    child: AcpToolCallSummary(
      name: 'shell',
      target: 'fvm dart analyze',
      status: AcpToolCallStatus.running,
      detail: 'cwd packages/flutter/acp_ui',
      viewMode: AcpViewMode.summary,
    ),
  );
}

@Preview(
  name: 'Tool call summary verbose',
  group: acpMoleculePreviewGroup,
  size: Size(520, 180),
)
Widget acpToolCallSummaryVerbosePreview() {
  return const _AcpPreviewSurface(
    child: AcpToolCallSummary(
      name: 'shell',
      target: 'fvm dart analyze',
      status: AcpToolCallStatus.running,
      detail: 'cwd packages/flutter/acp_ui',
      viewMode: AcpViewMode.verbose,
    ),
  );
}

@Preview(
  name: 'Connection status row',
  group: acpMoleculePreviewGroup,
  size: Size(560, 140),
)
Widget acpConnectionStatusRowPreview() {
  return const _AcpPreviewSurface(
    child: AcpConnectionStatusRow(
      status: AcpConnectionStatus.connected,
      transportLabel: 'stdio',
      profileLabel: 'Codelab Agent',
      detail: 'codelab serve --stdio',
    ),
  );
}

@Preview(
  name: 'Approval option group',
  group: acpMoleculePreviewGroup,
  size: Size(520, 180),
)
Widget acpApprovalOptionGroupPreview() {
  return _AcpPreviewSurface(
    child: AcpApprovalOptionGroup(
      selectedOptionId: 'allow_once',
      onSelected: acpPreviewApprovalSelected,
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
  );
}

void acpPreviewPromptSubmit(String prompt) {}

void acpPreviewApprovalSelected(String optionId) {}

void acpPreviewCancel() {}

class _AcpPreviewSurface extends StatelessWidget {
  const _AcpPreviewSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FluentTheme(
        data: FluentThemeData(),
        child: Builder(
          builder: (context) {
            return ColoredBox(
              color: FluentTheme.of(context).scaffoldBackgroundColor,
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            );
          },
        ),
      ),
    );
  }
}
