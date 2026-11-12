import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widget_previews.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'codelab_activity_bar.dart';
import 'codelab_app_bar.dart';
import 'codelab_approval_prompt.dart';
import 'codelab_command_palette_surface.dart';
import 'codelab_connection_screen.dart';
import 'codelab_file_preview.dart';
import 'codelab_file_tree.dart';
import 'codelab_progress_checklist.dart';
import 'codelab_session_pane_header.dart';
import 'codelab_session_sidebar.dart';
import 'codelab_settings_navigation.dart';
import 'codelab_start_screen.dart';
import 'codelab_status_table.dart';
import 'codelab_terminal_pane.dart';
import 'codelab_tool_dock.dart';
import 'codelab_transcript_panel.dart';
import 'codelab_transcript_row.dart';
import 'codelab_workbench_layout.dart';

const codelabOrganismPreviewGroup = 'ACP organisms';

@Preview(
  name: 'Status table',
  group: codelabOrganismPreviewGroup,
  size: Size(820, 260),
)
Widget codelabStatusTablePreview() {
  return const _AcpOrganismPreviewSurface(child: _StatusTableSample());
}

@Preview(
  name: 'Status table dark',
  group: codelabOrganismPreviewGroup,
  size: Size(820, 260),
  brightness: Brightness.dark,
)
Widget codelabStatusTableDarkPreview() {
  return const _AcpOrganismPreviewSurface(
    brightness: Brightness.dark,
    child: _StatusTableSample(),
  );
}

/// Пример панели «Agent status» (артборд `Mcp`): подключённый сервер, сбой с
/// повтором и выключенный сервер без действия.
class _StatusTableSample extends StatelessWidget {
  const _StatusTableSample();

  @override
  Widget build(BuildContext context) {
    return CodeLabStatusTable(
      columns: const ['SERVER', 'STATE', 'TOOLS', 'LAST ERROR'],
      rows: [
        CodeLabStatusTableRow(
          cells: const [
            CodeLabStatusTableCell('github', mono: true),
            CodeLabStatusTableCell('connected', tone: CodeLabStatusTone.active),
            CodeLabStatusTableCell('42'),
            CodeLabStatusTableCell('—', muted: true),
          ],
          action: CodeLabStatusTableAction(
            label: 'Reconnect',
            onPressed: codelabPreviewReconnect,
          ),
        ),
        CodeLabStatusTableRow(
          cells: const [
            CodeLabStatusTableCell('postgres', mono: true),
            CodeLabStatusTableCell(
              'failed · retry in 24 s',
              tone: CodeLabStatusTone.danger,
            ),
            CodeLabStatusTableCell('0'),
            CodeLabStatusTableCell('ECONNREFUSED 127.0.0.1:5432', mono: true),
          ],
          action: CodeLabStatusTableAction(
            label: 'Reconnect',
            onPressed: codelabPreviewReconnect,
          ),
        ),
        const CodeLabStatusTableRow(
          cells: [
            CodeLabStatusTableCell('playwright', mono: true),
            CodeLabStatusTableCell('disabled', tone: CodeLabStatusTone.idle),
            CodeLabStatusTableCell('—', muted: true),
            CodeLabStatusTableCell('—', muted: true),
          ],
        ),
      ],
    );
  }
}

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
            text:
                'I will inspect the **workspace checks** first, starting with '
                '`dart analyze`:\n\n```bash\nfvm dart analyze '
                'packages/flutter/codelab_ui\n```',
          ),
          CodeLabAgentTextRow(
            id: 'agent-block-1',
            text: '```text\nMCP servers (1)\n  docs  connected  3 tools\n```',
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
              risk: CodeLabApprovalRisk.shell,
              reason: 'Agent wants to execute a build script.',
              command: 'npm test --coverage',
              rawInput: '{\n  "command": "npm test --coverage"\n}',
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
  name: 'Approval prompt',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 160),
)
Widget codelabApprovalPromptPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      child: CodeLabApprovalPrompt(
        reason: 'The agent wants to verify the Flutter UI package.',
        rawInput: '{\n  "command": "fvm dart run melos run analyze"\n}',
        onOptionSelected: codelabPreviewApprovalSelected,
        options: [
          CodeLabApprovalOption(
            id: 'allow_once',
            label: 'Allow once',
            kind: CodeLabApprovalOptionKind.allowOnce,
          ),
          CodeLabApprovalOption(
            id: 'allow_always',
            label: 'Always allow melos run analyze',
            kind: CodeLabApprovalOptionKind.allowAlways,
          ),
          CodeLabApprovalOption(
            id: 'reject_once',
            label: 'Reject',
            kind: CodeLabApprovalOptionKind.rejectOnce,
          ),
          CodeLabApprovalOption(
            id: 'reject_always',
            label: 'Always reject',
            kind: CodeLabApprovalOptionKind.rejectAlways,
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

/// Стартовый экран панели сессии с проектом (change `require-project-folder`,
/// D18): подсказка и «New session». Путь вымышленный.
@Preview(
  name: 'Start screen',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 240),
)
Widget codelabStartScreenPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 240,
      child: CodeLabStartScreen(
        message: 'Start a new session in app.',
        actionLabel: 'New session',
        onAction: codelabPreviewConnect,
      ),
    ),
  );
}

/// Дерево файлов (артборд `Files`): раскрытая папка, ссылка наружу и строка
/// «… N more». Пути вымышленные, без данных пользователя.
@Preview(
  name: 'File tree',
  group: codelabOrganismPreviewGroup,
  size: Size(320, 260),
)
Widget codelabFileTreePreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 320,
      height: 260,
      child: CodeLabFileTree(
        selectedPath: 'lib/main.dart',
        rows: const [
          CodeLabFileTreeRowData(
            relativePath: 'lib',
            name: 'lib',
            kind: CodeLabFileTreeRowKind.directory,
            expanded: true,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'lib/main.dart',
            name: 'main.dart',
            kind: CodeLabFileTreeRowKind.file,
            depth: 1,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'lib/#more',
            name: '… 4980 more',
            kind: CodeLabFileTreeRowKind.more,
            depth: 1,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'docs',
            name: 'docs',
            kind: CodeLabFileTreeRowKind.directory,
            loading: true,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'shared',
            name: 'shared',
            kind: CodeLabFileTreeRowKind.outsideLink,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'README.md',
            name: 'README.md',
            kind: CodeLabFileTreeRowKind.file,
          ),
        ],
        onToggleDirectory: codelabPreviewFileTreeRow,
        onOpenFile: codelabPreviewFileTreeRow,
      ),
    ),
  );
}

/// Колбэк строк превью дерева: превью ничего не открывает.
void codelabPreviewFileTreeRow(CodeLabFileTreeRowData row) {}

/// Просмотр файла: текст с подсвеченной строкой и предупреждением о секретах.
@Preview(
  name: 'File preview',
  group: codelabOrganismPreviewGroup,
  size: Size(420, 260),
)
Widget codelabFilePreviewPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 420,
      height: 260,
      child: CodeLabFilePreview(
        relativePath: 'config/.env',
        maybeSecret: true,
        highlightLine: 2,
        onCopyPath: codelabPreviewCopyPath,
        content: const CodeLabFilePreviewContent.text(
          'EXAMPLE_NAME=demo\nEXAMPLE_FLAG=true\n',
        ),
      ),
    ),
  );
}

/// Просмотр двоичного файла: только пометка с размером.
@Preview(
  name: 'File preview binary',
  group: codelabOrganismPreviewGroup,
  size: Size(420, 160),
)
Widget codelabFilePreviewBinaryPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 420,
      height: 160,
      child: CodeLabFilePreview(
        relativePath: 'assets/logo.bin',
        content: CodeLabFilePreviewContent.binary('24 KB'),
      ),
    ),
  );
}

/// Колбэк «Copy path» превью: ничего не копирует.
void codelabPreviewCopyPath(String relativePath) {}

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

@Preview(
  name: 'Settings navigation',
  group: codelabOrganismPreviewGroup,
  size: Size(900, 420),
)
Widget codelabSettingsNavigationPreview() {
  // `NavigationView` требует Navigator и локализации, поэтому превью
  // собирается внутри собственного `FluentApp`.
  return FluentApp(
    debugShowCheckedModeBanner: false,
    home: CodeLabSettingsNavigation(
      items: const [
        CodeLabSettingsNavItem(
          id: 'connection',
          title: 'Connection',
          icon: FluentIcons.plug_connected,
          group: 'Agent',
        ),
        CodeLabSettingsNavItem(
          id: 'general',
          title: 'General',
          icon: FluentIcons.settings,
          group: 'App',
        ),
      ],
      selectedId: 'connection',
      onSelected: (_) {},
      onQueryChanged: (_) {},
      onBack: () {},
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: CodeLabText('Page body', role: CodeLabTextRole.title),
      ),
    ),
  );
}

@Preview(
  name: 'Terminal pane',
  group: codelabOrganismPreviewGroup,
  size: Size(520, 260),
)
Widget codelabTerminalPanePreview() {
  return _AcpOrganismPreviewSurface(
    child: CodeLabTerminalPane(
      tabs: const [
        CodeLabTerminalTab(
          id: 'a',
          title: 'zsh',
          statusLabel: 'Running',
          statusTone: CodeLabTone.success,
        ),
        CodeLabTerminalTab(
          id: 'b',
          title: 'build',
          statusLabel: 'Exited 1',
          statusTone: CodeLabTone.warning,
        ),
      ],
      activeTabId: 'a',
      hasSession: true,
      disclosure: 'Commands run with your permissions.',
      onDisclosureClosed: codelabPreviewCancel,
      content: const ColoredBox(
        color: Color(0xFF1E1E1E),
        child: SizedBox.expand(),
      ),
    ),
  );
}

class _AcpOrganismPreviewSurface extends StatelessWidget {
  const _AcpOrganismPreviewSurface({
    required this.child,
    this.brightness = Brightness.light,
  });

  final Widget child;

  /// Тема превью: тёмный вариант нужен таблице с тегами и обводками (D19).
  final Brightness brightness;

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
          data: FluentThemeData(brightness: brightness),
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
