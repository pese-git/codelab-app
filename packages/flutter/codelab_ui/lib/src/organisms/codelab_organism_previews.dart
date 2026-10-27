import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widget_previews.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'codelab_activity_bar.dart';
import 'codelab_app_bar.dart';
import 'codelab_approval_panel.dart';
import 'codelab_command_palette_surface.dart';
import 'codelab_connection_screen.dart';
import 'codelab_progress_checklist.dart';
import 'codelab_session_pane_header.dart';
import 'codelab_session_sidebar.dart';
import 'codelab_tool_dock.dart';
import 'codelab_transcript_panel.dart';
import 'codelab_transcript_row.dart';
import 'codelab_workbench_layout.dart';

const codelabOrganismPreviewGroup = 'ACP organisms';

@Preview(
  name: 'Transcript panel conversation',
  group: codelabOrganismPreviewGroup,
  size: Size(820, 460),
)
Widget codelabTranscriptPanelPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 820,
      height: 460,
      child: CodeLabTranscriptPanel(
        rows: [
          CodeLabUserRow(
            id: 'user-1',
            text: 'Run analyzer and summarize any failures.',
          ),
          CodeLabThoughtRow(
            id: 'thought-1',
            text:
                'The analyzer runs per package; start with codelab_ui and '
                'report only errors.',
          ),
          CodeLabAgentTextRow(
            id: 'agent-1',
            text: 'I will inspect the workspace checks first.',
          ),
          CodeLabToolCallRow(
            id: 'tool-1',
            status: CodeLabToolCallStatus.succeeded,
            label: 'Read',
            detail: 'lib/src/organisms/codelab_transcript_panel.dart',
            output: ['import \'package:fluent_ui/fluent_ui.dart\';'],
          ),
          CodeLabToolCallRow(
            id: 'tool-2',
            status: CodeLabToolCallStatus.running,
            label: 'Run',
            detail: 'fvm dart analyze packages/flutter/codelab_ui',
          ),
          CodeLabNoticeRow(
            id: 'notice-1',
            severity: CodeLabNoticeSeverity.info,
            body:
                'The agent cannot restore sessions; a new session was '
                'started.',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel thinking',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 300),
)
Widget codelabTranscriptPanelThinkingPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 300,
      child: CodeLabTranscriptPanel(
        rows: [
          CodeLabUserRow(id: 'user-1', text: 'Why is the build slow?'),
          CodeLabThoughtRow(
            id: 'thought-1',
            streaming: true,
            text:
                'The build runs build_runner for every package.\n'
                'Only three packages have generated files.\n'
                'Check melos.yaml for the bootstrap hook.',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel failed turn',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 300),
)
Widget codelabTranscriptPanelFailedTurnPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 300,
      child: CodeLabTranscriptPanel(
        rows: [
          const CodeLabUserRow(
            id: 'user-1',
            text: 'Run analyzer and summarize any failures.',
          ),
          CodeLabNoticeRow(
            id: 'prompt-error-1',
            severity: CodeLabNoticeSeverity.error,
            title: 'The model provider is unavailable',
            body: '503 Service Unavailable',
            details: 'ACP request session/prompt failed: Turn failed',
            action: CodeLabTranscriptAction(
              label: 'Retry',
              icon: FluentIcons.refresh,
              onPressed: () {},
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
        rows: [
          CodeLabAgentTextRow(
            id: 'agent-verbose-1',
            text:
                'Analyzed protocol package, checked generated DTO boundaries, '
                'and kept the current session state unchanged while reporting '
                'the formatter-only diff.',
          ),
          CodeLabToolCallRow(
            id: 'tool-verbose-1',
            status: CodeLabToolCallStatus.failed,
            label: 'Read',
            detail: 'lib/main.dart',
            secondary: 'File not found: lib/main.dart',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel with embedded approval',
  group: codelabOrganismPreviewGroup,
  size: Size(820, 460),
)
Widget codelabTranscriptPanelEmbeddedApprovalPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 820,
      height: 460,
      child: CodeLabTranscriptPanel(
        rows: [
          const CodeLabToolCallRow(
            id: 'tool-resolved-1',
            status: CodeLabToolCallStatus.succeeded,
            label: 'Edit',
            detail: 'jest.config.js',
            approval: CodeLabTranscriptApproval.resolved(
              label: 'Allow once',
              outcome: CodeLabApprovalOutcome.allowed,
            ),
          ),
          CodeLabToolCallRow(
            id: 'tool-pending-1',
            status: CodeLabToolCallStatus.queued,
            label: 'Run',
            detail: 'npm test --coverage',
            approval: CodeLabTranscriptApproval.pending(
              title: 'Run a command?',
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
                  id: 'allow_always',
                  label: 'Always allow npm test',
                  kind: CodeLabApprovalOptionKind.allowAlways,
                  tone: CodeLabTone.success,
                ),
                CodeLabApprovalOption(
                  id: 'reject_once',
                  label: 'Reject',
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
        onNewSession: codelabPreviewNewSession,
        projects: _previewProjects,
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
    // `InfoBar` заметок ленты читает `FluentLocalizations`; превью
    // рендерятся без `FluentApp`, поэтому локализации подключаются здесь.
    return Localizations(
      locale: const Locale('en'),
      delegates: const [
        FluentLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FluentTheme(
          data: FluentThemeData(),
          child: Builder(
            builder: (context) {
              // Подсказки (`Tooltip`) сайдбара и app bar требуют `Overlay`, а
              // превью рендерятся без `FluentApp`.
              return Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (context) => ColoredBox(
                      color: FluentTheme.of(context).scaffoldBackgroundColor,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

void codelabPreviewCancel() {}

const _previewProjects = [
  CodeLabSidebarProject(
    path: '/work/codelab-app',
    name: 'codelab-app',
    current: true,
    sessions: [
      CodeLabSessionListItem(
        id: 'session-1',
        title: 'Repository audit',
        status: CodeLabSessionStatus.completed,
      ),
      CodeLabSessionListItem(
        id: 'session-2',
        title: 'Workbench UI',
        status: CodeLabSessionStatus.awaitingApproval,
      ),
      CodeLabSessionListItem(
        id: 'session-3',
        title: 'Transport logs',
        status: CodeLabSessionStatus.running,
      ),
    ],
  ),
  CodeLabSidebarProject(path: '/work/codelab-cli', name: 'codelab-cli'),
  CodeLabSidebarProject(path: '/work/notes-app', name: 'notes-app'),
];

const _previewPlan = [
  CodeLabPlanEntry(
    content: 'Split transcript into typed rows',
    status: CodeLabPlanEntryStatus.completed,
    priority: CodeLabPlanEntryPriority.medium,
  ),
  CodeLabPlanEntry(
    content: 'TranscriptRowMapper with row reuse',
    status: CodeLabPlanEntryStatus.inProgress,
    priority: CodeLabPlanEntryPriority.medium,
  ),
  CodeLabPlanEntry(
    content: 'Diff preview in approval card',
    status: CodeLabPlanEntryStatus.pending,
    priority: CodeLabPlanEntryPriority.high,
  ),
];

class _AcpPreviewWorkbench extends StatelessWidget {
  const _AcpPreviewWorkbench();

  @override
  Widget build(BuildContext context) {
    return CodeLabWorkbenchLayout(
      appBar: const CodeLabAppBar(
        title: 'CodeLab',
        connectionStatus: CodeLabConnectionStatus.connected,
        paneToggles: [
          CodeLabPaneToggle(pane: ToolPane.plan, selected: true),
          CodeLabPaneToggle(pane: ToolPane.protocol),
        ],
      ),
      sidebar: const CodeLabSessionSidebar(
        activeSessionId: 'session-2',
        onSessionSelected: codelabPreviewSessionSelected,
        projects: _previewProjects,
      ),
      sessionPane: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeLabSessionPaneHeader(
            title: 'Workbench UI',
            projectName: 'codelab-app',
            projectPath: '/work/codelab-app',
            mode: 'standard',
          ),
          SizedBox(height: 8),
          Expanded(
            child: CodeLabTranscriptPanel(
              rows: [
                CodeLabUserRow(
                  id: 'user-1',
                  text: 'Create a desktop layout shell for the workbench.',
                ),
                CodeLabAgentTextRow(
                  id: 'agent-1',
                  text: 'I will keep it slot-based for future app wiring.',
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          CodeLabPromptComposer(onSubmit: codelabPreviewPromptSubmitted),
        ],
      ),
      dock: CodeLabToolDock(
        active: ToolPane.plan,
        tabs: [
          const CodeLabDockTab(
            pane: ToolPane.plan,
            content: _PreviewPlanList(),
          ),
          CodeLabDockTab(pane: ToolPane.protocol, content: SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _PreviewPlanList extends StatelessWidget {
  const _PreviewPlanList();

  @override
  Widget build(BuildContext context) =>
      CodeLabProgressChecklist.list(entries: _previewPlan);
}
