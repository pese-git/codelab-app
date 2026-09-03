import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widget_previews.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'acp_approval_panel.dart';
import 'acp_command_palette_surface.dart';
import 'acp_connection_screen.dart';
import 'acp_debug_log_panel.dart';
import 'acp_session_sidebar.dart';
import 'acp_transcript_panel.dart';
import 'acp_workbench_layout.dart';

const acpOrganismPreviewGroup = 'ACP organisms';

@Preview(
  name: 'Transcript panel normal',
  group: acpOrganismPreviewGroup,
  size: Size(620, 360),
)
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

@Preview(
  name: 'Transcript panel summary',
  group: acpOrganismPreviewGroup,
  size: Size(440, 320),
)
Widget acpTranscriptPanelSummaryPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 440,
      height: 320,
      child: AcpTranscriptPanel(
        viewMode: AcpViewMode.summary,
        entries: [
          AcpTranscriptEntry(
            id: 'agent-summary-1',
            kind: AcpTranscriptEntryKind.agent,
            title: 'Codelab Agent',
            body:
                'Analyzed protocol package and found one formatter-only diff.',
            timestampLabel: '12:04',
          ),
          AcpTranscriptEntry(
            id: 'tool-summary-1',
            kind: AcpTranscriptEntryKind.toolCall,
            title: 'Tool call',
            toolCall: AcpToolCallSummary(
              name: 'shell',
              target: 'fvm dart analyze',
              status: AcpToolCallStatus.succeeded,
              detail: 'cwd packages/flutter/acp_ui',
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel verbose',
  group: acpOrganismPreviewGroup,
  size: Size(620, 420),
)
Widget acpTranscriptPanelVerbosePreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 420,
      child: AcpTranscriptPanel(
        viewMode: AcpViewMode.verbose,
        entries: [
          AcpTranscriptEntry(
            id: 'agent-verbose-1',
            kind: AcpTranscriptEntryKind.agent,
            title: 'Codelab Agent',
            body:
                'Analyzed protocol package, checked generated DTO boundaries, '
                'and kept the current session state unchanged while reporting '
                'the formatter-only diff.',
            timestampLabel: '12:04',
          ),
          AcpTranscriptEntry(
            id: 'tool-verbose-1',
            kind: AcpTranscriptEntryKind.toolCall,
            title: 'Tool call',
            toolCall: AcpToolCallSummary(
              name: 'shell',
              target: 'fvm dart run melos run analyze',
              status: AcpToolCallStatus.succeeded,
              detail: 'cwd packages/flutter/acp_ui',
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel with embedded approval',
  group: acpOrganismPreviewGroup,
  size: Size(620, 520),
)
Widget acpTranscriptPanelEmbeddedApprovalPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 520,
      child: AcpTranscriptPanel(
        entries: [
          const AcpTranscriptEntry(
            id: 'tool-resolved-1',
            kind: AcpTranscriptEntryKind.toolCall,
            title: 'Edit file — jest.config.js',
            toolCall: AcpToolCallSummary(
              name: 'edit',
              status: AcpToolCallStatus.succeeded,
            ),
            approval: AcpTranscriptApproval.resolved(label: 'Allowed once'),
          ),
          AcpTranscriptEntry(
            id: 'tool-pending-1',
            kind: AcpTranscriptEntryKind.toolCall,
            title: 'Run command',
            toolCall: const AcpToolCallSummary(
              name: 'execute',
              status: AcpToolCallStatus.queued,
            ),
            approval: AcpTranscriptApproval.pending(
              risk: AcpApprovalRisk.shell,
              reason: 'Agent wants to execute a build script.',
              command: 'npm test --coverage',
              cwd: '/home/user/project',
              onOptionSelected: acpPreviewApprovalSelected,
              options: const [
                AcpApprovalOption(
                  id: 'allow_once',
                  label: 'Allow once',
                  tone: AcpTone.success,
                ),
                AcpApprovalOption(
                  id: 'reject_once',
                  label: 'Reject once',
                  tone: AcpTone.danger,
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
  group: acpOrganismPreviewGroup,
  size: Size(520, 360),
)
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

@Preview(
  name: 'Connection screen',
  group: acpOrganismPreviewGroup,
  size: Size(620, 360),
)
Widget acpConnectionScreenPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 360,
      child: AcpConnectionScreen(
        status: AcpConnectionStatus.disconnected,
        transportLabel: 'stdio',
        profileLabel: 'Codelab Agent',
        detail: 'codelab serve --stdio',
        description: 'Connect to a local ACP agent using the default profile.',
        onConnect: acpPreviewConnect,
        onReconnect: acpPreviewReconnect,
        onConfigureConnection: acpPreviewEditProfile,
      ),
    ),
  );
}

@Preview(
  name: 'Debug log panel',
  group: acpOrganismPreviewGroup,
  size: Size(620, 360),
)
Widget acpDebugLogPanelPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 360,
      child: AcpDebugLogPanel(
        entries: [
          AcpDebugLogEntry(
            id: 'log-1',
            severity: AcpDebugLogSeverity.info,
            source: 'transport',
            message: 'stdio process started',
            timestampLabel: '12:04:01',
          ),
          AcpDebugLogEntry(
            id: 'log-2',
            severity: AcpDebugLogSeverity.warning,
            source: 'protocol',
            message: 'stderr diagnostic: API_KEY=[REDACTED]',
            timestampLabel: '12:04:03',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Session sidebar',
  group: acpOrganismPreviewGroup,
  size: Size(320, 420),
)
Widget acpSessionSidebarPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 320,
      height: 420,
      child: AcpSessionSidebar(
        activeSessionId: 'session-2',
        onSessionSelected: acpPreviewSessionSelected,
        sessions: [
          AcpSessionListItem(
            id: 'session-1',
            title: 'Repository audit',
            status: AcpSessionStatus.completed,
            subtitle: 'Checked protocol package boundaries.',
            updatedLabel: 'Done 10 min ago',
          ),
          AcpSessionListItem(
            id: 'session-2',
            title: 'Workbench UI',
            status: AcpSessionStatus.awaitingApproval,
            subtitle: 'Waiting for shell command approval.',
            updatedLabel: 'Active',
          ),
          AcpSessionListItem(
            id: 'session-3',
            title: 'Transport logs',
            status: AcpSessionStatus.running,
            subtitle: 'Streaming diagnostics from stdio.',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Command palette empty query',
  group: acpOrganismPreviewGroup,
  size: Size(520, 360),
)
Widget acpCommandPaletteEmptyQueryPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      height: 360,
      child: AcpCommandPaletteSurface(onActionSelected: acpPreviewCommand),
    ),
  );
}

@Preview(
  name: 'Command palette filtered',
  group: acpOrganismPreviewGroup,
  size: Size(520, 260),
)
Widget acpCommandPaletteFilteredPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      height: 260,
      child: AcpCommandPaletteSurface(
        initialQuery: '/log',
        onActionSelected: acpPreviewCommand,
      ),
    ),
  );
}

@Preview(
  name: 'Command palette selected',
  group: acpOrganismPreviewGroup,
  size: Size(520, 360),
)
Widget acpCommandPaletteSelectedPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      height: 360,
      child: AcpCommandPaletteSurface(
        selectedActionId: 'permissions',
        onActionSelected: acpPreviewCommand,
      ),
    ),
  );
}

@Preview(
  name: 'Workbench layout desktop',
  group: acpOrganismPreviewGroup,
  size: Size(1180, 720),
)
Widget acpWorkbenchLayoutPreview() {
  return _AcpOrganismPreviewSurface(child: _AcpPreviewWorkbench());
}

@Preview(
  name: 'Workbench layout medium',
  group: acpOrganismPreviewGroup,
  size: Size(860, 720),
)
Widget acpWorkbenchLayoutMediumPreview() {
  return _AcpOrganismPreviewSurface(child: _AcpPreviewWorkbench());
}

@Preview(
  name: 'Workbench layout narrow',
  group: acpOrganismPreviewGroup,
  size: Size(430, 720),
)
Widget acpWorkbenchLayoutNarrowPreview() {
  return _AcpOrganismPreviewSurface(child: _AcpPreviewWorkbench());
}

void acpPreviewApprovalSelected(String optionId) {}

void acpPreviewSessionSelected(String sessionId) {}

void acpPreviewCommand(AcpCommandAction action) {}

void acpPreviewNewSession() {}

void acpPreviewPromptSubmitted(String prompt) {}

void acpPreviewConnect() {}

void acpPreviewReconnect() {}

void acpPreviewEditProfile() {}

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
            Expanded(child: AcpText('CodeLab Agent', role: AcpTextRole.title)),
            AcpStatusIndicator(label: 'Connected', tone: AcpStatusTone.active),
            SizedBox(width: 8),
            AcpButton(
              label: 'Cancel',
              icon: FluentIcons.cancel,
              onPressed: acpPreviewCancel,
            ),
            SizedBox(width: 8),
            AcpButton(
              label: 'Reconnect',
              icon: FluentIcons.refresh,
              onPressed: acpPreviewReconnect,
            ),
          ],
        ),
      ),
    );
  }
}

void acpPreviewCancel() {}

class _AcpPreviewWorkbench extends StatelessWidget {
  const _AcpPreviewWorkbench();

  @override
  Widget build(BuildContext context) {
    return AcpWorkbenchLayout(
      commandBar: const _AcpPreviewCommandBar(),
      sessionsPane: const AcpSessionSidebar(
        activeSessionId: 'session-2',
        onSessionSelected: acpPreviewSessionSelected,
        sessions: [
          AcpSessionListItem(
            id: 'session-1',
            title: 'Repository audit',
            status: AcpSessionStatus.completed,
            subtitle: 'Checked protocol package boundaries.',
            updatedLabel: 'Done 10 min ago',
          ),
          AcpSessionListItem(
            id: 'session-2',
            title: 'Workbench UI',
            status: AcpSessionStatus.awaitingApproval,
            subtitle: 'Composing desktop scaffold.',
            updatedLabel: 'Active',
          ),
        ],
      ),
      mainPane: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AcpTranscriptPanel(
              entries: [
                AcpTranscriptEntry(
                  id: 'user-1',
                  kind: AcpTranscriptEntryKind.user,
                  title: 'You',
                  body: 'Create a desktop layout shell for the workbench.',
                  timestampLabel: '12:04',
                ),
                AcpTranscriptEntry(
                  id: 'agent-1',
                  kind: AcpTranscriptEntryKind.agent,
                  title: 'Codelab Agent',
                  body: 'I will keep it slot-based for future app wiring.',
                  timestampLabel: '12:05',
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          AcpPromptComposer(onSubmit: acpPreviewPromptSubmitted),
        ],
      ),
      inspectorPane: AcpApprovalPanel(
        title: 'Run analyzer',
        risk: AcpApprovalRisk.shell,
        reason: 'Verify the package after layout changes.',
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
    );
  }
}
