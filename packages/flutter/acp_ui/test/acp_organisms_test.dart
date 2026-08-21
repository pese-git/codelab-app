import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports organisms through the public package API', () {
    expect(AcpApprovalPanel, isA<Type>());
    expect(AcpApprovalRisk.shell, isA<AcpApprovalRisk>());
    expect(AcpCommandPaletteSurface, isA<Type>());
    expect(AcpConnectionScreen, isA<Type>());
    expect(AcpDebugLogEntry, isA<Type>());
    expect(AcpDebugLogPanel, isA<Type>());
    expect(AcpDebugLogSeverity.warning, isA<AcpDebugLogSeverity>());
    expect(AcpSessionListItem, isA<Type>());
    expect(AcpSessionSidebar, isA<Type>());
    expect(AcpSessionStatus.awaitingApproval, isA<AcpSessionStatus>());
    expect(AcpTranscriptEntry, isA<Type>());
    expect(AcpTranscriptEntryKind.toolCall, isA<AcpTranscriptEntryKind>());
    expect(AcpTranscriptPanel, isA<Type>());
    expect(AcpWorkbenchLayout, isA<Type>());
  });

  testWidgets('renders command palette default command list', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 520,
          height: 360,
          child: AcpCommandPaletteSurface(),
        ),
      ),
    );

    expect(find.text('Command palette'), findsOneWidget);
    expect(find.text('/new'), findsOneWidget);
    expect(find.text('/plan'), findsOneWidget);
    expect(find.text('/permissions'), findsOneWidget);
    expect(find.text('/logs'), findsOneWidget);
    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('/reconnect'), findsOneWidget);
  });

  testWidgets('filters command palette from slash input', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 520,
          height: 360,
          child: AcpCommandPaletteSurface(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(AcpCommandPaletteSurface.queryFieldKey),
      '/perm',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('/permissions'), findsOneWidget);
    expect(find.text('/new'), findsNothing);
    expect(find.text('/logs'), findsNothing);
  });

  testWidgets('selects command palette action by typed model', (tester) async {
    AcpCommandAction? selected;

    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 520,
          height: 360,
          child: AcpCommandPaletteSurface(
            selectedActionId: 'logs',
            onActionSelected: (action) => selected = action,
          ),
        ),
      ),
    );

    await tester.tap(find.text('/logs'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected?.id, 'logs');
    expect(selected?.slashCommand, '/logs');
  });

  testWidgets('renders transcript entries and embedded tool summaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 600,
          height: 360,
          child: AcpTranscriptPanel(
            entries: [
              AcpTranscriptEntry(
                id: 'user-1',
                kind: AcpTranscriptEntryKind.user,
                title: 'You',
                body: 'Check the UI package.',
                timestampLabel: '12:30',
              ),
              AcpTranscriptEntry(
                id: 'tool-1',
                kind: AcpTranscriptEntryKind.toolCall,
                title: 'Tool call',
                toolCall: AcpToolCallSummary(
                  name: 'shell',
                  target: 'fvm flutter test',
                  status: AcpToolCallStatus.succeeded,
                  detail: 'all tests passed',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('You'), findsOneWidget);
    expect(find.text('Check the UI package.'), findsOneWidget);
    expect(find.text('12:30'), findsOneWidget);
    expect(find.text('Tool call'), findsOneWidget);
    expect(find.text('shell - fvm flutter test'), findsOneWidget);
    expect(find.text('all tests passed'), findsOneWidget);
  });

  testWidgets('renders transcript summary mode with compact details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 360,
          height: 240,
          child: AcpTranscriptPanel(
            viewMode: AcpViewMode.summary,
            entries: [
              AcpTranscriptEntry(
                id: 'agent-1',
                kind: AcpTranscriptEntryKind.agent,
                title: 'Agent',
                body: 'Long update that should stay compact in summary mode.',
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
      ),
    );

    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('shell - fvm dart analyze'), findsNothing);
    expect(find.text('packages/flutter/acp_ui'), findsNothing);
  });

  testWidgets('renders transcript verbose mode with expanded tool details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 520,
          height: 320,
          child: AcpTranscriptPanel(
            viewMode: AcpViewMode.verbose,
            entries: [
              AcpTranscriptEntry(
                id: 'tool-1',
                kind: AcpTranscriptEntryKind.toolCall,
                title: 'Tool call',
                toolCall: AcpToolCallSummary(
                  name: 'shell',
                  target: 'fvm dart analyze',
                  status: AcpToolCallStatus.succeeded,
                  detail: 'packages/flutter/acp_ui',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('fvm dart analyze'), findsOneWidget);
    expect(find.text('packages/flutter/acp_ui'), findsOneWidget);
  });

  testWidgets('renders transcript empty state', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 320,
          height: 220,
          child: AcpTranscriptPanel(entries: []),
        ),
      ),
    );

    expect(find.text('No transcript yet'), findsOneWidget);
  });

  testWidgets('renders approval risk details and selects option', (
    tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      FluentApp(
        home: AcpApprovalPanel(
          title: 'Run shell command',
          risk: AcpApprovalRisk.shell,
          reason: 'Needed to verify workspace health.',
          command: 'fvm dart analyze',
          cwd: '/repo',
          diffSummary: 'No file edits',
          selectedOptionId: 'allow_once',
          onOptionSelected: (optionId) => selected = optionId,
          options: const [
            AcpApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              description: 'Run once.',
              tone: AcpTone.warning,
            ),
            AcpApprovalOption(
              id: 'reject',
              label: 'Reject',
              description: 'Deny.',
              tone: AcpTone.danger,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Run shell command'), findsOneWidget);
    expect(find.text('Shell'), findsOneWidget);
    expect(find.text('Needed to verify workspace health.'), findsOneWidget);
    expect(find.text('fvm dart analyze'), findsOneWidget);
    expect(find.text('/repo'), findsOneWidget);
    expect(find.text('No file edits'), findsOneWidget);

    await tester.tap(find.text('Reject'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected, 'reject');
  });

  testWidgets('renders connection details and invokes callbacks', (
    tester,
  ) async {
    var connected = false;
    var reconnected = false;
    var edited = false;

    await tester.pumpWidget(
      FluentApp(
        home: AcpConnectionScreen(
          status: AcpConnectionStatus.disconnected,
          transportLabel: 'stdio',
          profileLabel: 'Codelab Agent',
          detail: 'codelab serve --stdio',
          description: 'Connect to a local ACP agent.',
          onConnect: () => connected = true,
          onReconnect: () => reconnected = true,
          onEditProfile: () => edited = true,
        ),
      ),
    );

    expect(find.text('Codelab Agent'), findsWidgets);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('stdio'), findsOneWidget);
    expect(find.text('codelab serve --stdio'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.tap(find.text('Reconnect'));
    await tester.tap(find.text('Edit profile'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(connected, isTrue);
    expect(reconnected, isTrue);
    expect(edited, isTrue);
  });

  testWidgets('renders debug log entries and clear callback', (tester) async {
    var cleared = false;

    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 520,
          height: 320,
          child: AcpDebugLogPanel(
            onClear: () => cleared = true,
            entries: const [
              AcpDebugLogEntry(
                id: 'log-1',
                severity: AcpDebugLogSeverity.info,
                source: 'transport',
                message: 'stdio process started',
                timestampLabel: '12:00:01',
              ),
              AcpDebugLogEntry(
                id: 'log-2',
                severity: AcpDebugLogSeverity.warning,
                source: 'protocol',
                message: 'token=[REDACTED]',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Debug log'), findsOneWidget);
    expect(find.text('Info'), findsOneWidget);
    expect(find.text('transport'), findsOneWidget);
    expect(find.text('stdio process started'), findsOneWidget);
    expect(find.text('Warning'), findsOneWidget);
    expect(find.text('token=[REDACTED]'), findsOneWidget);

    await tester.tap(find.byType(AcpIconButton));
    await tester.pump(const Duration(milliseconds: 100));

    expect(cleared, isTrue);
  });

  testWidgets('renders debug log empty state', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 360,
          height: 220,
          child: AcpDebugLogPanel(entries: []),
        ),
      ),
    );

    expect(find.text('No diagnostics yet'), findsOneWidget);
  });

  testWidgets('renders sessions and invokes selection/new callbacks', (
    tester,
  ) async {
    String? selectedSessionId;
    var newSessionRequested = false;

    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 320,
          height: 420,
          child: AcpSessionSidebar(
            activeSessionId: 'session-2',
            onSessionSelected: (sessionId) => selectedSessionId = sessionId,
            onNewSession: () => newSessionRequested = true,
            sessions: const [
              AcpSessionListItem(
                id: 'session-1',
                title: 'Repository audit',
                status: AcpSessionStatus.completed,
                subtitle: 'Checked package boundaries.',
                updatedLabel: 'Done 10 min ago',
              ),
              AcpSessionListItem(
                id: 'session-2',
                title: 'Workbench UI',
                status: AcpSessionStatus.awaitingApproval,
                subtitle: 'Waiting for approval.',
                updatedLabel: 'Active',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Repository audit'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Workbench UI'), findsOneWidget);
    expect(find.text('Approval'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    await tester.tap(find.text('Repository audit'));
    await tester.tap(find.byType(AcpIconButton));
    await tester.pump(const Duration(milliseconds: 100));

    expect(selectedSessionId, 'session-1');
    expect(newSessionRequested, isTrue);
  });

  testWidgets('renders session sidebar empty state', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 280,
          height: 240,
          child: AcpSessionSidebar(
            sessions: [],
            onSessionSelected: acpTestSessionSelected,
          ),
        ),
      ),
    );

    expect(find.text('No sessions yet'), findsOneWidget);
  });

  testWidgets('renders workbench desktop regions in left center right order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 1200,
          height: 760,
          child: AcpWorkbenchLayout(
            commandBar: Text('Command bar slot'),
            sessionsPane: Text('Sessions slot'),
            mainPane: Text('Transcript and prompt slot'),
            inspectorPane: Text('Inspector slot'),
          ),
        ),
      ),
    );

    expect(find.byKey(AcpWorkbenchLayout.commandBarKey), findsOneWidget);
    expect(find.byKey(AcpWorkbenchLayout.sessionsPaneKey), findsOneWidget);
    expect(find.byKey(AcpWorkbenchLayout.mainPaneKey), findsOneWidget);
    expect(find.byKey(AcpWorkbenchLayout.inspectorPaneKey), findsOneWidget);
    expect(find.text('Command bar slot'), findsOneWidget);
    expect(find.text('Sessions slot'), findsOneWidget);
    expect(find.text('Transcript and prompt slot'), findsOneWidget);
    expect(find.text('Inspector slot'), findsOneWidget);

    final sessionsLeft = tester
        .getTopLeft(find.byKey(AcpWorkbenchLayout.sessionsPaneKey))
        .dx;
    final mainLeft = tester
        .getTopLeft(find.byKey(AcpWorkbenchLayout.mainPaneKey))
        .dx;
    final inspectorLeft = tester
        .getTopLeft(find.byKey(AcpWorkbenchLayout.inspectorPaneKey))
        .dx;

    expect(sessionsLeft, lessThan(mainLeft));
    expect(mainLeft, lessThan(inspectorLeft));
  });

  testWidgets('workbench avoids horizontal overflow at desktop width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FluentApp(
        home: AcpWorkbenchLayout(
          commandBar: const _AcpTestPane(label: 'Command'),
          sessionsPane: const _AcpTestPane(label: 'Sessions'),
          mainPane: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: _AcpTestPane(label: 'Transcript')),
              const SizedBox(height: 12),
              AcpPromptComposer(onSubmit: acpTestPromptSubmitted),
            ],
          ),
          inspectorPane: const _AcpTestPane(label: 'Inspector'),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'workbench compacts sessions and moves inspector below on medium width',
    (tester) async {
      tester.view.physicalSize = const Size(860, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        FluentApp(
          home: AcpWorkbenchLayout(
            commandBar: const _AcpTestPane(label: 'Command'),
            sessionsPane: const _AcpTestPane(label: 'Sessions'),
            mainPane: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: _AcpTestPane(label: 'Transcript')),
                const SizedBox(height: 12),
                AcpPromptComposer(onSubmit: acpTestPromptSubmitted),
              ],
            ),
            inspectorPane: const _AcpTestPane(label: 'Inspector'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final sessionsSize = tester.getSize(
        find.byKey(AcpWorkbenchLayout.sessionsPaneKey),
      );
      final mainTop = tester
          .getTopLeft(find.byKey(AcpWorkbenchLayout.mainPaneKey))
          .dy;
      final inspectorTop = tester
          .getTopLeft(find.byKey(AcpWorkbenchLayout.inspectorPaneKey))
          .dy;
      final mainLeft = tester
          .getTopLeft(find.byKey(AcpWorkbenchLayout.mainPaneKey))
          .dx;
      final inspectorLeft = tester
          .getTopLeft(find.byKey(AcpWorkbenchLayout.inspectorPaneKey))
          .dx;

      expect(sessionsSize.width, 176);
      expect(inspectorTop, greaterThan(mainTop));
      expect(inspectorLeft, mainLeft);
    },
  );

  testWidgets(
    'workbench keeps narrow width focused on main pane without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(430, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        FluentApp(
          home: AcpWorkbenchLayout(
            commandBar: const _AcpTestPane(label: 'Command'),
            sessionsPane: const _AcpTestPane(label: 'Sessions'),
            mainPane: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: _AcpTestPane(label: 'Transcript')),
                const SizedBox(height: 12),
                AcpPromptComposer(onSubmit: acpTestPromptSubmitted),
              ],
            ),
            inspectorPane: const _AcpTestPane(label: 'Inspector'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Transcript'), findsOneWidget);
      expect(find.text('Sessions'), findsNothing);
      expect(find.text('Inspector'), findsNothing);
      expect(
        find.byKey(AcpWorkbenchLayout.sessionsPaneKey, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(AcpWorkbenchLayout.inspectorPaneKey, skipOffstage: false),
        findsOneWidget,
      );
    },
  );
}

void acpTestSessionSelected(String sessionId) {}

void acpTestPromptSubmitted(String prompt) {}

class _AcpTestPane extends StatelessWidget {
  const _AcpTestPane({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
      child: Center(child: Text(label)),
    );
  }
}
