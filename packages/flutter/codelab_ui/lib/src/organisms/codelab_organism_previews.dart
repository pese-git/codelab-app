import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widget_previews.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'codelab_activity_bar.dart';
import 'codelab_approval_panel.dart';
import 'codelab_command_palette_surface.dart';
import 'codelab_connection_screen.dart';
import 'codelab_progress_checklist.dart';
import 'codelab_session_sidebar.dart';
import 'codelab_transcript_panel.dart';
import 'codelab_workbench_layout.dart';

const codelabOrganismPreviewGroup = 'ACP organisms';

@Preview(
  name: 'Transcript panel normal',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 360),
)
Widget codelabTranscriptPanelPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 360,
      child: CodeLabTranscriptPanel(
        entries: [
          CodeLabTranscriptEntry(
            id: 'user-1',
            kind: CodeLabTranscriptEntryKind.user,
            title: 'You',
            body: 'Run analyzer and summarize any failures.',
            timestampLabel: '12:04',
          ),
          CodeLabTranscriptEntry(
            id: 'agent-1',
            kind: CodeLabTranscriptEntryKind.agent,
            title: 'Codelab Agent',
            body: 'I will inspect the workspace checks.',
            timestampLabel: '12:04',
          ),
          CodeLabTranscriptEntry(
            id: 'tool-1',
            kind: CodeLabTranscriptEntryKind.toolCall,
            title: 'Tool call',
            toolCall: CodeLabToolCallSummary(
              name: 'shell',
              target: 'fvm dart analyze',
              status: CodeLabToolCallStatus.running,
              detail: 'packages/flutter/codelab_ui',
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel summary',
  group: codelabOrganismPreviewGroup,
  size: Size(440, 320),
)
Widget codelabTranscriptPanelSummaryPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 440,
      height: 320,
      child: CodeLabTranscriptPanel(
        viewMode: CodeLabViewMode.summary,
        entries: [
          CodeLabTranscriptEntry(
            id: 'agent-summary-1',
            kind: CodeLabTranscriptEntryKind.agent,
            title: 'Codelab Agent',
            body:
                'Analyzed protocol package and found one formatter-only diff.',
            timestampLabel: '12:04',
          ),
          CodeLabTranscriptEntry(
            id: 'tool-summary-1',
            kind: CodeLabTranscriptEntryKind.toolCall,
            title: 'Tool call',
            toolCall: CodeLabToolCallSummary(
              name: 'shell',
              target: 'fvm dart analyze',
              status: CodeLabToolCallStatus.succeeded,
              detail: 'cwd packages/flutter/codelab_ui',
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel verbose',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 420),
)
Widget codelabTranscriptPanelVerbosePreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 420,
      child: CodeLabTranscriptPanel(
        viewMode: CodeLabViewMode.verbose,
        entries: [
          CodeLabTranscriptEntry(
            id: 'agent-verbose-1',
            kind: CodeLabTranscriptEntryKind.agent,
            title: 'Codelab Agent',
            body:
                'Analyzed protocol package, checked generated DTO boundaries, '
                'and kept the current session state unchanged while reporting '
                'the formatter-only diff.',
            timestampLabel: '12:04',
          ),
          CodeLabTranscriptEntry(
            id: 'tool-verbose-1',
            kind: CodeLabTranscriptEntryKind.toolCall,
            title: 'Tool call',
            toolCall: CodeLabToolCallSummary(
              name: 'shell',
              target: 'fvm dart run melos run analyze',
              status: CodeLabToolCallStatus.succeeded,
              detail: 'cwd packages/flutter/codelab_ui',
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel with embedded approval',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 520),
)
Widget codelabTranscriptPanelEmbeddedApprovalPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 520,
      child: CodeLabTranscriptPanel(
        entries: [
          const CodeLabTranscriptEntry(
            id: 'tool-resolved-1',
            kind: CodeLabTranscriptEntryKind.toolCall,
            title: 'Edit file — jest.config.js',
            toolCall: CodeLabToolCallSummary(
              name: 'edit',
              status: CodeLabToolCallStatus.succeeded,
            ),
            approval: CodeLabTranscriptApproval.resolved(label: 'Allowed once'),
          ),
          CodeLabTranscriptEntry(
            id: 'tool-pending-1',
            kind: CodeLabTranscriptEntryKind.toolCall,
            title: 'Run command',
            toolCall: const CodeLabToolCallSummary(
              name: 'execute',
              status: CodeLabToolCallStatus.queued,
            ),
            approval: CodeLabTranscriptApproval.pending(
              risk: CodeLabApprovalRisk.shell,
              reason: 'Agent wants to execute a build script.',
              command: 'npm test --coverage',
              cwd: '/home/user/project',
              onOptionSelected: codelabPreviewApprovalSelected,
              options: const [
                CodeLabApprovalOption(
                  id: 'allow_once',
                  label: 'Allow once',
                  kind: CodeLabApprovalOptionKind.allowOnce,
                  tone: CodeLabTone.success,
                ),
                CodeLabApprovalOption(
                  id: 'reject_once',
                  label: 'Reject once',
                  kind: CodeLabApprovalOptionKind.rejectOnce,
                  tone: CodeLabTone.danger,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Approval panel',
  group: codelabOrganismPreviewGroup,
  size: Size(520, 360),
)
Widget codelabApprovalPanelPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      child: CodeLabApprovalPanel(
        title: 'Run shell command',
        risk: CodeLabApprovalRisk.shell,
        reason: 'The agent wants to verify the Flutter UI package.',
        command: 'fvm dart run melos run analyze',
        cwd: 'packages/flutter/codelab_ui',
        rawInput: '{\n  "command": "fvm dart run melos run analyze"\n}',
        selectedOptionId: 'allow_once',
        onOptionSelected: codelabPreviewApprovalSelected,
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
    ),
  );
}

@Preview(
  name: 'Activity bar — plan collapsed',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 100),
)
Widget codelabActivityBarPlanCollapsedPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      child: CodeLabActivityBar(sections: [_previewPlanSection()]),
    ),
  );
}

@Preview(
  name: 'Activity bar — plan expanded',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 320),
)
Widget codelabActivityBarPlanExpandedPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      child: CodeLabActivityBar(
        sections: [_previewPlanSection(initiallyExpanded: true)],
      ),
    ),
  );
}

CodeLabActivityBarSection _previewPlanSection({
  bool initiallyExpanded = false,
}) {
  final section = CodeLabProgressChecklist.section(
    id: 'plan',
    onDismiss: codelabPreviewDismissPlan,
    entries: const [
      CodeLabPlanEntry(
        content: 'Read auth module and locate token refresh call sites',
        status: CodeLabPlanEntryStatus.completed,
        priority: CodeLabPlanEntryPriority.medium,
      ),
      CodeLabPlanEntry(
        content: 'Reproduce the token refresh race condition',
        status: CodeLabPlanEntryStatus.completed,
        priority: CodeLabPlanEntryPriority.high,
      ),
      CodeLabPlanEntry(
        content: 'Run melos analyze to confirm no new lint issues',
        status: CodeLabPlanEntryStatus.inProgress,
        priority: CodeLabPlanEntryPriority.medium,
      ),
      CodeLabPlanEntry(
        content: 'Open PR for review',
        status: CodeLabPlanEntryStatus.pending,
        priority: CodeLabPlanEntryPriority.low,
      ),
    ],
  );

  return CodeLabActivityBarSection(
    id: section.id,
    headerBuilder: section.headerBuilder,
    bodyBuilder: section.bodyBuilder,
    initiallyExpanded: initiallyExpanded,
  );
}

void codelabPreviewDismissPlan() {}

@Preview(
  name: 'Connection screen',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 360),
)
Widget codelabConnectionScreenPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 360,
      child: CodeLabConnectionScreen(
        status: CodeLabConnectionStatus.disconnected,
        transportLabel: 'stdio',
        profileLabel: 'Codelab Agent',
        detail: 'codelab serve --stdio',
        description: 'Connect to a local ACP agent using the default profile.',
        onConnect: codelabPreviewConnect,
        onReconnect: codelabPreviewReconnect,
        onConfigureConnection: codelabPreviewEditProfile,
      ),
    ),
  );
}

@Preview(
  name: 'Session sidebar',
  group: codelabOrganismPreviewGroup,
  size: Size(320, 420),
)
Widget codelabSessionSidebarPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 320,
      height: 420,
      child: CodeLabSessionSidebar(
        activeSessionId: 'session-2',
        onSessionSelected: codelabPreviewSessionSelected,
        sessions: [
          CodeLabSessionListItem(
            id: 'session-1',
            title: 'Repository audit',
            status: CodeLabSessionStatus.completed,
            subtitle: 'Checked protocol package boundaries.',
            updatedLabel: 'Done 10 min ago',
          ),
          CodeLabSessionListItem(
            id: 'session-2',
            title: 'Workbench UI',
            status: CodeLabSessionStatus.awaitingApproval,
            subtitle: 'Waiting for shell command approval.',
            updatedLabel: 'Active',
          ),
          CodeLabSessionListItem(
            id: 'session-3',
            title: 'Transport logs',
            status: CodeLabSessionStatus.running,
            subtitle: 'Streaming diagnostics from stdio.',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Command palette empty query',
  group: codelabOrganismPreviewGroup,
  size: Size(520, 360),
)
Widget codelabCommandPaletteEmptyQueryPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      height: 360,
      child: CodeLabCommandPaletteSurface(
        onActionSelected: codelabPreviewCommand,
      ),
    ),
  );
}

@Preview(
  name: 'Command palette filtered',
  group: codelabOrganismPreviewGroup,
  size: Size(520, 260),
)
Widget codelabCommandPaletteFilteredPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      height: 260,
      child: CodeLabCommandPaletteSurface(
        initialQuery: '/log',
        onActionSelected: codelabPreviewCommand,
      ),
    ),
  );
}

@Preview(
  name: 'Command palette selected',
  group: codelabOrganismPreviewGroup,
  size: Size(520, 360),
)
Widget codelabCommandPaletteSelectedPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      height: 360,
      child: CodeLabCommandPaletteSurface(
        selectedActionId: 'permissions',
        onActionSelected: codelabPreviewCommand,
      ),
    ),
  );
}

@Preview(
  name: 'Workbench layout desktop',
  group: codelabOrganismPreviewGroup,
  size: Size(1180, 720),
)
Widget codelabWorkbenchLayoutPreview() {
  return _AcpOrganismPreviewSurface(child: _AcpPreviewWorkbench());
}

@Preview(
  name: 'Workbench layout medium',
  group: codelabOrganismPreviewGroup,
  size: Size(860, 720),
)
Widget codelabWorkbenchLayoutMediumPreview() {
  return _AcpOrganismPreviewSurface(child: _AcpPreviewWorkbench());
}

@Preview(
  name: 'Workbench layout narrow',
  group: codelabOrganismPreviewGroup,
  size: Size(430, 720),
)
Widget codelabWorkbenchLayoutNarrowPreview() {
  return _AcpOrganismPreviewSurface(child: _AcpPreviewWorkbench());
}

void codelabPreviewApprovalSelected(String optionId) {}

void codelabPreviewSessionSelected(String sessionId) {}

void codelabPreviewCommand(CodeLabCommandAction action) {}

void codelabPreviewNewSession() {}

void codelabPreviewPromptSubmitted(String prompt) {}

void codelabPreviewConnect() {}

void codelabPreviewReconnect() {}

void codelabPreviewEditProfile() {}

class _AcpOrganismPreviewSurface extends StatelessWidget {
  const _AcpOrganismPreviewSurface({required this.child});

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

class _AcpPreviewCommandBar extends StatelessWidget {
  const _AcpPreviewCommandBar();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: CodeLabText('CodeLab Agent', role: CodeLabTextRole.title),
            ),
            CodeLabStatusIndicator(
              label: 'Connected',
              tone: CodeLabStatusTone.active,
            ),
            SizedBox(width: 8),
            CodeLabButton(
              label: 'Cancel',
              icon: FluentIcons.cancel,
              onPressed: codelabPreviewCancel,
            ),
            SizedBox(width: 8),
            CodeLabButton(
              label: 'Reconnect',
              icon: FluentIcons.refresh,
              onPressed: codelabPreviewReconnect,
            ),
          ],
        ),
      ),
    );
  }
}

void codelabPreviewCancel() {}

class _AcpPreviewWorkbench extends StatelessWidget {
  const _AcpPreviewWorkbench();

  @override
  Widget build(BuildContext context) {
    return CodeLabWorkbenchLayout(
      commandBar: const _AcpPreviewCommandBar(),
      sessionsPane: const CodeLabSessionSidebar(
        activeSessionId: 'session-2',
        onSessionSelected: codelabPreviewSessionSelected,
        sessions: [
          CodeLabSessionListItem(
            id: 'session-1',
            title: 'Repository audit',
            status: CodeLabSessionStatus.completed,
            subtitle: 'Checked protocol package boundaries.',
            updatedLabel: 'Done 10 min ago',
          ),
          CodeLabSessionListItem(
            id: 'session-2',
            title: 'Workbench UI',
            status: CodeLabSessionStatus.awaitingApproval,
            subtitle: 'Composing desktop scaffold.',
            updatedLabel: 'Active',
          ),
        ],
      ),
      mainPane: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CodeLabTranscriptPanel(
              entries: [
                CodeLabTranscriptEntry(
                  id: 'user-1',
                  kind: CodeLabTranscriptEntryKind.user,
                  title: 'You',
                  body: 'Create a desktop layout shell for the workbench.',
                  timestampLabel: '12:04',
                ),
                CodeLabTranscriptEntry(
                  id: 'agent-1',
                  kind: CodeLabTranscriptEntryKind.agent,
                  title: 'Codelab Agent',
                  body: 'I will keep it slot-based for future app wiring.',
                  timestampLabel: '12:05',
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          CodeLabPromptComposer(onSubmit: codelabPreviewPromptSubmitted),
        ],
      ),
      inspectorPane: CodeLabApprovalPanel(
        title: 'Run analyzer',
        risk: CodeLabApprovalRisk.shell,
        reason: 'Verify the package after layout changes.',
        command: 'fvm dart run melos run analyze',
        cwd: 'packages/flutter/codelab_ui',
        selectedOptionId: 'allow_once',
        onOptionSelected: codelabPreviewApprovalSelected,
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
}
