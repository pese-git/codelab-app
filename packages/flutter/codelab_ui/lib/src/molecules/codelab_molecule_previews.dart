import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widget_previews.dart';

import 'codelab_approval_option_group.dart';
import 'codelab_connection_status_row.dart';
import 'codelab_prompt_composer.dart';
import 'codelab_tool_call_summary.dart';
import 'codelab_view_mode.dart';
import '../atomics/atomics.dart';

const codelabMoleculePreviewGroup = 'ACP molecules';

@Preview(
  name: 'Prompt composer',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 120),
)
Widget codelabPromptComposerPreview() {
  return _AcpPreviewSurface(
    child: CodeLabPromptComposer(
      initialPrompt: 'Summarize the current diff',
      canCancel: true,
      onSubmit: codelabPreviewPromptSubmit,
      onCancel: codelabPreviewCancel,
    ),
  );
}

@Preview(
  name: 'Tool call summary normal',
  group: codelabMoleculePreviewGroup,
  size: Size(520, 120),
)
Widget codelabToolCallSummaryPreview() {
  return const _AcpPreviewSurface(
    child: CodeLabToolCallSummary(
      name: 'shell',
      target: 'fvm dart analyze',
      status: CodeLabToolCallStatus.running,
      detail: 'cwd packages/flutter/codelab_ui',
    ),
  );
}

@Preview(
  name: 'Tool call summary summary',
  group: codelabMoleculePreviewGroup,
  size: Size(360, 120),
)
Widget codelabToolCallSummarySummaryPreview() {
  return const _AcpPreviewSurface(
    child: CodeLabToolCallSummary(
      name: 'shell',
      target: 'fvm dart analyze',
      status: CodeLabToolCallStatus.running,
      detail: 'cwd packages/flutter/codelab_ui',
      viewMode: CodeLabViewMode.summary,
    ),
  );
}

@Preview(
  name: 'Tool call summary verbose',
  group: codelabMoleculePreviewGroup,
  size: Size(520, 180),
)
Widget codelabToolCallSummaryVerbosePreview() {
  return const _AcpPreviewSurface(
    child: CodeLabToolCallSummary(
      name: 'shell',
      target: 'fvm dart analyze',
      status: CodeLabToolCallStatus.running,
      detail: 'cwd packages/flutter/codelab_ui',
      viewMode: CodeLabViewMode.verbose,
    ),
  );
}

@Preview(
  name: 'Connection status row',
  group: codelabMoleculePreviewGroup,
  size: Size(560, 140),
)
Widget codelabConnectionStatusRowPreview() {
  return const _AcpPreviewSurface(
    child: CodeLabConnectionStatusRow(
      status: CodeLabConnectionStatus.connected,
      transportLabel: 'stdio',
      profileLabel: 'Codelab Agent',
      detail: 'codelab serve --stdio',
    ),
  );
}

@Preview(
  name: 'Approval option group',
  group: codelabMoleculePreviewGroup,
  size: Size(520, 180),
)
Widget codelabApprovalOptionGroupPreview() {
  return _AcpPreviewSurface(
    child: CodeLabApprovalOptionGroup(
      selectedOptionId: 'allow_once',
      onSelected: codelabPreviewApprovalSelected,
      options: const [
        CodeLabApprovalOption(
          id: 'allow_once',
          label: 'Allow once',
          kind: CodeLabApprovalOptionKind.allowOnce,
          description: 'Run this command for the active prompt turn.',
          tone: CodeLabTone.warning,
        ),
        CodeLabApprovalOption(
          id: 'reject',
          label: 'Reject',
          kind: CodeLabApprovalOptionKind.rejectOnce,
          description: 'Return a denied outcome to the agent.',
          tone: CodeLabTone.danger,
        ),
      ],
    ),
  );
}

void codelabPreviewPromptSubmit(String prompt) {}

void codelabPreviewApprovalSelected(String optionId) {}

void codelabPreviewCancel() {}

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
