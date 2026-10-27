import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports organisms through the public package API', () {
    expect(CodeLabActivityBar, isA<Type>());
    expect(CodeLabActivityBarSection, isA<Type>());
    expect(CodeLabProgressChecklist, isA<Type>());
    expect(CodeLabPlanEntry, isA<Type>());
    expect(CodeLabPlanEntryStatus.inProgress, isA<CodeLabPlanEntryStatus>());
    expect(CodeLabPlanEntryPriority.high, isA<CodeLabPlanEntryPriority>());
    expect(CodeLabApprovalPanel, isA<Type>());
    expect(CodeLabApprovalRisk.shell, isA<CodeLabApprovalRisk>());
    expect(CodeLabCommandPaletteSurface, isA<Type>());
    expect(CodeLabConnectionScreen, isA<Type>());
    expect(CodeLabSidebarProject, isA<Type>());
    expect(CodeLabAppBar, isA<Type>());
    expect(CodeLabToolDock, isA<Type>());
    expect(CodeLabSessionPaneHeader, isA<Type>());
    expect(CodeLabSessionListItem, isA<Type>());
    expect(CodeLabSessionSidebar, isA<Type>());
    expect(CodeLabSessionStatus.awaitingApproval, isA<CodeLabSessionStatus>());
    expect(CodeLabTranscriptEntry, isA<Type>());
    expect(
      CodeLabTranscriptEntryKind.toolCall,
      isA<CodeLabTranscriptEntryKind>(),
    );
    expect(CodeLabTranscriptPanel, isA<Type>());
    expect(CodeLabWorkbenchLayout, isA<Type>());
    expect(CodeLabWorkbenchShortcuts, isA<Type>());
  });

  testWidgets('renders command palette default command list', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 520,
          height: 360,
          child: CodeLabCommandPaletteSurface(),
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
          child: CodeLabCommandPaletteSurface(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(CodeLabCommandPaletteSurface.queryFieldKey),
      '/perm',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('/permissions'), findsOneWidget);
    expect(find.text('/new'), findsNothing);
    expect(find.text('/logs'), findsNothing);
  });

  testWidgets('renders command palette empty filtered state', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 520,
          height: 260,
          child: CodeLabCommandPaletteSurface(initialQuery: '/missing'),
        ),
      ),
    );

    expect(find.text('No matching commands'), findsOneWidget);
    expect(find.byKey(CodeLabCommandPaletteSurface.emptyKey), findsOneWidget);
    expect(find.text('/new'), findsNothing);
  });

  testWidgets('selects command palette action by typed model', (tester) async {
    CodeLabCommandAction? selected;

    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 520,
          height: 360,
          child: CodeLabCommandPaletteSurface(
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

  testWidgets('routes workbench command palette and inspector shortcuts', (
    tester,
  ) async {
    var openedPalette = false;
    var previousInspector = false;
    var nextInspector = false;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabWorkbenchShortcuts(
          onOpenCommandPalette: () => openedPalette = true,
          onInspectorPrevious: () => previousInspector = true,
          onInspectorNext: () => nextInspector = true,
          child: const SizedBox(width: 320, height: 200),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump(const Duration(milliseconds: 100));

    expect(openedPalette, isTrue);
    expect(previousInspector, isTrue);
    expect(nextInspector, isTrue);
  });

  testWidgets('renders transcript entries and embedded tool summaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 600,
          height: 360,
          child: CodeLabTranscriptPanel(
            entries: [
              CodeLabTranscriptEntry(
                id: 'user-1',
                kind: CodeLabTranscriptEntryKind.user,
                title: 'You',
                body: 'Check the UI package.',
                timestampLabel: '12:30',
              ),
              CodeLabTranscriptEntry(
                id: 'tool-1',
                kind: CodeLabTranscriptEntryKind.toolCall,
                title: 'Tool call',
                toolCall: CodeLabToolCallSummary(
                  name: 'shell',
                  target: 'fvm flutter test',
                  status: CodeLabToolCallStatus.succeeded,
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

  testWidgets('a resolved approval is marked by its outcome: a check only '
      'when allowed', (tester) async {
    Future<void> pumpResolved(CodeLabApprovalOutcome outcome) {
      return tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 400,
            height: 200,
            child: CodeLabTranscriptPanel(
              entries: [
                CodeLabTranscriptEntry(
                  id: 'call-1',
                  kind: CodeLabTranscriptEntryKind.toolCall,
                  title: 'Run command',
                  approval: CodeLabTranscriptApproval.resolved(
                    label: 'Resolved',
                    outcome: outcome,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    await pumpResolved(CodeLabApprovalOutcome.allowed);
    expect(find.byIcon(FluentIcons.check_mark), findsOneWidget);

    await pumpResolved(CodeLabApprovalOutcome.cancelled);
    expect(find.byIcon(FluentIcons.check_mark), findsNothing);
    expect(find.byIcon(FluentIcons.cancel), findsOneWidget);

    await pumpResolved(CodeLabApprovalOutcome.rejected);
    expect(find.byIcon(FluentIcons.check_mark), findsNothing);
    expect(find.byIcon(FluentIcons.blocked2), findsOneWidget);
  });

  testWidgets(
    'auto-scrolls to a new pending approval only when already near the '
    'bottom',
    (tester) async {
      Widget buildPanel(List<CodeLabTranscriptEntry> entries) {
        return FluentApp(
          home: SizedBox(
            width: 400,
            height: 200,
            child: CodeLabTranscriptPanel(entries: entries),
          ),
        );
      }

      CodeLabTranscriptEntry pendingApprovalEntry(String id) {
        return CodeLabTranscriptEntry(
          id: id,
          kind: CodeLabTranscriptEntryKind.toolCall,
          title: 'Run command',
          approval: CodeLabTranscriptApproval.pending(
            risk: CodeLabApprovalRisk.shell,
            options: const [
              CodeLabApprovalOption(
                id: 'allow',
                label: 'Allow',
                kind: CodeLabApprovalOptionKind.allowOnce,
              ),
            ],
            onOptionSelected: (_) {},
          ),
        );
      }

      final baseEntries = [
        for (var i = 0; i < 20; i += 1)
          CodeLabTranscriptEntry(
            id: 'agent-$i',
            kind: CodeLabTranscriptEntryKind.agent,
            title: 'Agent',
            body: 'Message number $i with enough text to take vertical space.',
          ),
      ];

      await tester.pumpWidget(buildPanel(baseEntries));
      await tester.pumpAndSettle();

      final scrollableFinder = find.byType(Scrollable);
      ScrollPosition position() =>
          tester.state<ScrollableState>(scrollableFinder).position;

      // User scrolls to the bottom (following the live tail).
      await tester.fling(scrollableFinder, const Offset(0, -5000), 3000);
      await tester.pumpAndSettle();
      expect(position().pixels, position().maxScrollExtent);

      await tester.pumpWidget(
        buildPanel([...baseEntries, pendingApprovalEntry('tool-pending-1')]),
      );
      await tester.pumpAndSettle();

      expect(
        position().pixels,
        position().maxScrollExtent,
        reason: 'stays pinned to the bottom, following the new approval',
      );

      // User scrolls back up to read earlier history.
      await tester.fling(scrollableFinder, const Offset(0, 5000), 3000);
      await tester.pumpAndSettle();
      expect(position().pixels, 0.0);

      final offsetWhileReadingHistory = position().pixels;
      await tester.pumpWidget(
        buildPanel([
          ...baseEntries,
          pendingApprovalEntry('tool-pending-1'),
          pendingApprovalEntry('tool-pending-2'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        position().pixels,
        offsetWhileReadingHistory,
        reason: 'does not yank the user away from history they are reading',
      );
    },
  );

  testWidgets(
    'auto-scrolls to a new pending approval when the transcript outgrew the '
    'viewport without the user ever scrolling it',
    (tester) async {
      Widget buildPanel(List<CodeLabTranscriptEntry> entries) {
        return FluentApp(
          home: SizedBox(
            width: 400,
            height: 200,
            child: CodeLabTranscriptPanel(entries: entries),
          ),
        );
      }

      CodeLabTranscriptEntry agentEntry(int i) {
        return CodeLabTranscriptEntry(
          id: 'agent-$i',
          kind: CodeLabTranscriptEntryKind.agent,
          title: 'Agent',
          body: 'Message number $i with enough text to take vertical space.',
        );
      }

      await tester.pumpWidget(buildPanel([agentEntry(0)]));
      await tester.pumpAndSettle();

      // Агент дописал больше, чем помещается, а пользователь ленту не
      // трогал — лента следует за хвостом (follow-transcript-tail).
      final grownEntries = [for (var i = 0; i < 20; i += 1) agentEntry(i)];
      await tester.pumpWidget(buildPanel(grownEntries));
      await tester.pumpAndSettle();

      final scrollableFinder = find.byType(Scrollable);
      ScrollPosition position() =>
          tester.state<ScrollableState>(scrollableFinder).position;
      expect(position().maxScrollExtent, greaterThan(200));
      expect(position().pixels, position().maxScrollExtent);

      await tester.pumpWidget(
        buildPanel([
          ...grownEntries,
          CodeLabTranscriptEntry(
            id: 'tool-pending-1',
            kind: CodeLabTranscriptEntryKind.toolCall,
            title: 'Run command',
            approval: CodeLabTranscriptApproval.pending(
              risk: CodeLabApprovalRisk.shell,
              options: const [
                CodeLabApprovalOption(
                  id: 'allow',
                  label: 'Allow',
                  kind: CodeLabApprovalOptionKind.allowOnce,
                ),
              ],
              onOptionSelected: (_) {},
            ),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        position().pixels,
        position().maxScrollExtent,
        reason:
            'the user has not scrolled up to read history, so the new '
            'approval is brought into view',
      );
      expect(find.text('Allow'), findsOneWidget);
      expect(
        tester.getRect(find.text('Allow')).bottom,
        lessThanOrEqualTo(tester.getRect(scrollableFinder).bottom),
      );
    },
  );

  testWidgets(
    'auto-scrolls to a pending approval that is already present when the '
    'transcript is first shown',
    (tester) async {
      // The host swaps an empty-state screen for the transcript panel only
      // once the first entries arrive — over a fast stdio round trip those
      // can already include the pending approval, so there is no earlier
      // build for `didUpdateWidget` to diff against.
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 400,
            height: 200,
            child: CodeLabTranscriptPanel(
              entries: [
                for (var i = 0; i < 20; i += 1)
                  CodeLabTranscriptEntry(
                    id: 'agent-$i',
                    kind: CodeLabTranscriptEntryKind.agent,
                    title: 'Agent',
                    body:
                        'Message number $i with enough text to take '
                        'vertical space.',
                  ),
                CodeLabTranscriptEntry(
                  id: 'tool-pending-1',
                  kind: CodeLabTranscriptEntryKind.toolCall,
                  title: 'Run command',
                  approval: CodeLabTranscriptApproval.pending(
                    risk: CodeLabApprovalRisk.shell,
                    options: const [
                      CodeLabApprovalOption(
                        id: 'allow',
                        label: 'Allow',
                        kind: CodeLabApprovalOptionKind.allowOnce,
                      ),
                    ],
                    onOptionSelected: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.byType(Scrollable);
      final position = tester.state<ScrollableState>(scrollableFinder).position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, position.maxScrollExtent);
      expect(find.text('Allow'), findsOneWidget);
      expect(
        tester.getRect(find.text('Allow')).bottom,
        lessThanOrEqualTo(tester.getRect(scrollableFinder).bottom),
      );
    },
  );

  group('следует за хвостом ленты (follow-transcript-tail)', () {
    Widget buildPanel(List<CodeLabTranscriptEntry> entries) {
      return FluentApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: CodeLabTranscriptPanel(entries: entries),
        ),
      );
    }

    // Карточки инструментов выше обычных сообщений — как у Dart-агента,
    // чьи `read`/`write`/`exec` выталкивали итоговое сообщение за видимую
    // часть ленивого списка.
    List<CodeLabTranscriptEntry> entries(int count) => [
      for (var i = 0; i < count; i += 1)
        CodeLabTranscriptEntry(
          id: 'entry-$i',
          kind: i.isEven
              ? CodeLabTranscriptEntryKind.toolCall
              : CodeLabTranscriptEntryKind.agent,
          title: i.isEven ? 'Tool $i' : 'Agent',
          body: 'Entry number $i\nwith a second line\nand a third one.',
        ),
    ];

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    testWidgets('новые записи у низа ленты остаются видимыми', (tester) async {
      await tester.pumpWidget(buildPanel(entries(1)));
      await tester.pumpAndSettle();

      for (var count = 2; count <= 12; count += 1) {
        await tester.pumpWidget(buildPanel(entries(count)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(position(tester).maxScrollExtent, greaterThan(200));
      expect(position(tester).pixels, position(tester).maxScrollExtent);
      expect(find.text('Tool 10'), findsOneWidget);
      expect(
        find.textContaining('Entry number 11', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('не сдвигает ленту, пока пользователь читает историю', (
      tester,
    ) async {
      await tester.pumpWidget(buildPanel(entries(12)));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, 0.0);

      // Прыжок вниз и чтение истории — обе прокрутки пользовательские.
      await tester.fling(find.byType(Scrollable), const Offset(0, -5000), 3000);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable), const Offset(0, 300));
      await tester.pumpAndSettle();
      final readingOffset = position(tester).pixels;
      expect(position(tester).maxScrollExtent - readingOffset, greaterThan(80));

      await tester.pumpWidget(buildPanel(entries(16)));
      await tester.pumpAndSettle();

      expect(position(tester).pixels, readingOffset);
      expect(find.text('Tool 14'), findsNothing);
    });

    testWidgets('возврат к низу возобновляет следование', (tester) async {
      await tester.pumpWidget(buildPanel(entries(12)));
      await tester.pumpAndSettle();
      await tester.fling(find.byType(Scrollable), const Offset(0, -5000), 3000);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable), const Offset(0, 300));
      await tester.pumpAndSettle();

      await tester.fling(find.byType(Scrollable), const Offset(0, -5000), 3000);
      await tester.pumpAndSettle();
      expect(position(tester).pixels, position(tester).maxScrollExtent);

      await tester.pumpWidget(buildPanel(entries(16)));
      await tester.pumpAndSettle();

      expect(position(tester).pixels, position(tester).maxScrollExtent);
      expect(find.text('Tool 14'), findsOneWidget);
    });
  });

  testWidgets('renders transcript summary mode with compact details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 360,
          height: 240,
          child: CodeLabTranscriptPanel(
            viewMode: CodeLabViewMode.summary,
            entries: [
              CodeLabTranscriptEntry(
                id: 'agent-1',
                kind: CodeLabTranscriptEntryKind.agent,
                title: 'Agent',
                body: 'Long update that should stay compact in summary mode.',
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
      ),
    );

    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('shell - fvm dart analyze'), findsNothing);
    expect(find.text('packages/flutter/codelab_ui'), findsNothing);
  });

  testWidgets('renders transcript verbose mode with expanded tool details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 520,
          height: 320,
          child: CodeLabTranscriptPanel(
            viewMode: CodeLabViewMode.verbose,
            entries: [
              CodeLabTranscriptEntry(
                id: 'tool-1',
                kind: CodeLabTranscriptEntryKind.toolCall,
                title: 'Tool call',
                toolCall: CodeLabToolCallSummary(
                  name: 'shell',
                  target: 'fvm dart analyze',
                  status: CodeLabToolCallStatus.succeeded,
                  detail: 'packages/flutter/codelab_ui',
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
    expect(find.text('packages/flutter/codelab_ui'), findsOneWidget);
  });

  testWidgets('renders full agent body without truncation across view modes', (
    tester,
  ) async {
    final longBody = List.generate(
      12,
      (i) => 'Agent response line ${i + 1}.',
    ).join('\n');

    for (final viewMode in CodeLabViewMode.values) {
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 360,
            height: 480,
            child: CodeLabTranscriptPanel(
              viewMode: viewMode,
              entries: [
                CodeLabTranscriptEntry(
                  id: 'agent-1',
                  kind: CodeLabTranscriptEntryKind.agent,
                  title: 'Agent',
                  body: longBody,
                ),
              ],
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text(longBody));
      expect(
        textWidget.maxLines,
        isNull,
        reason: 'viewMode: $viewMode should not limit agent body lines',
      );
      expect(
        textWidget.overflow,
        isNot(TextOverflow.ellipsis),
        reason: 'viewMode: $viewMode should not ellipsize agent body',
      );
    }
  });

  testWidgets('renders full user/approval/diagnostic body without truncation', (
    tester,
  ) async {
    final longBody = List.generate(
      12,
      (i) => 'Content line ${i + 1}.',
    ).join('\n');

    for (final kind in [
      CodeLabTranscriptEntryKind.user,
      CodeLabTranscriptEntryKind.approval,
      CodeLabTranscriptEntryKind.diagnostic,
    ]) {
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 360,
            height: 480,
            child: CodeLabTranscriptPanel(
              viewMode: CodeLabViewMode.summary,
              entries: [
                CodeLabTranscriptEntry(
                  id: 'entry-1',
                  kind: kind,
                  title: 'Entry',
                  body: longBody,
                ),
              ],
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text(longBody));
      expect(
        textWidget.maxLines,
        isNull,
        reason: 'kind: $kind should not limit body lines',
      );
      expect(
        textWidget.overflow,
        isNot(TextOverflow.ellipsis),
        reason: 'kind: $kind should not ellipsize body',
      );
    }
  });

  testWidgets('still truncates tool call body by view mode (regression)', (
    tester,
  ) async {
    final longBody = List.generate(
      12,
      (i) => 'Tool call body line ${i + 1}.',
    ).join('\n');

    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 360,
          height: 480,
          child: CodeLabTranscriptPanel(
            viewMode: CodeLabViewMode.summary,
            entries: [
              CodeLabTranscriptEntry(
                id: 'tool-1',
                kind: CodeLabTranscriptEntryKind.toolCall,
                title: 'Tool call',
                body: longBody,
              ),
            ],
          ),
        ),
      ),
    );

    final textWidget = tester.widget<Text>(find.text(longBody));
    expect(textWidget.maxLines, 1);
    expect(textWidget.overflow, TextOverflow.ellipsis);
  });

  testWidgets('renders transcript empty state', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 320,
          height: 220,
          child: CodeLabTranscriptPanel(entries: []),
        ),
      ),
    );

    expect(find.text('No transcript yet'), findsOneWidget);
  });

  testWidgets('renders approval and diagnostic transcript entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 520,
          height: 260,
          child: CodeLabTranscriptPanel(
            entries: [
              CodeLabTranscriptEntry(
                id: 'approval-1',
                kind: CodeLabTranscriptEntryKind.approval,
                title: 'Permission required',
                body: 'The agent wants to run a shell command.',
              ),
              CodeLabTranscriptEntry(
                id: 'diagnostic-1',
                kind: CodeLabTranscriptEntryKind.diagnostic,
                title: 'Protocol error',
                body: 'invalid params',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Permission required'), findsOneWidget);
    expect(
      find.text('The agent wants to run a shell command.'),
      findsOneWidget,
    );
    expect(find.text('Protocol error'), findsOneWidget);
    expect(find.text('invalid params'), findsOneWidget);
  });

  testWidgets('a failed turn notice hides details until expanded and offers '
      'its action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 520,
          height: 300,
          child: CodeLabTranscriptPanel(
            entries: [
              CodeLabTranscriptEntry(
                id: 'prompt-error-1',
                kind: CodeLabTranscriptEntryKind.diagnostic,
                title: 'The model provider is unavailable',
                body: '503 Service Unavailable',
                details: 'ACP request session/prompt failed: Turn failed',
                action: CodeLabTranscriptEntryAction(
                  label: 'Retry',
                  icon: FluentIcons.refresh,
                  onPressed: () => retried = true,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('The model provider is unavailable'), findsOneWidget);
    expect(find.text('503 Service Unavailable'), findsOneWidget);
    expect(
      find.text('ACP request session/prompt failed: Turn failed'),
      findsNothing,
    );

    await tester.tap(find.text('Details'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('ACP request session/prompt failed: Turn failed'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(retried, isTrue);
  });

  testWidgets('renders approval risk details and selects option', (
    tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabApprovalPanel(
          title: 'Run shell command',
          risk: CodeLabApprovalRisk.shell,
          reason: 'Needed to verify workspace health.',
          command: 'fvm dart analyze',
          cwd: '/repo',
          diffSummary: 'No file edits',
          selectedOptionId: 'allow_once',
          onOptionSelected: (optionId) => selected = optionId,
          options: const [
            CodeLabApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              kind: CodeLabApprovalOptionKind.allowOnce,
              description: 'Run once.',
              tone: CodeLabTone.warning,
            ),
            CodeLabApprovalOption(
              id: 'reject',
              label: 'Reject',
              kind: CodeLabApprovalOptionKind.rejectOnce,
              description: 'Deny.',
              tone: CodeLabTone.danger,
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

  testWidgets('keeps disabled approvals from selecting options or shortcuts', (
    tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabApprovalPanel(
          title: 'Run shell command',
          risk: CodeLabApprovalRisk.shell,
          enabled: false,
          onOptionSelected: (optionId) => selected = optionId,
          options: const [
            CodeLabApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              kind: CodeLabApprovalOptionKind.allowOnce,
            ),
            CodeLabApprovalOption(
              id: 'reject',
              label: 'Reject',
              kind: CodeLabApprovalOptionKind.rejectOnce,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Allow once'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected, isNull);
  });

  testWidgets('raw input is collapsed by default and expands on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: CodeLabApprovalPanel(
          title: 'Run shell command',
          risk: CodeLabApprovalRisk.shell,
          rawInput: '{\n  "command": "rm -rf build"\n}',
          onOptionSelected: (_) {},
          options: const [
            CodeLabApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              kind: CodeLabApprovalOptionKind.allowOnce,
            ),
          ],
        ),
      ),
    );

    expect(find.text('View raw input'), findsOneWidget);
    expect(find.textContaining('rm -rf build'), findsNothing);

    await tester.tap(find.text('View raw input'));
    await tester.pumpAndSettle();

    expect(find.textContaining('rm -rf build'), findsOneWidget);
  });

  testWidgets('renders connection details and invokes callbacks', (
    tester,
  ) async {
    var connected = false;
    var reconnected = false;
    var edited = false;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabConnectionScreen(
          status: CodeLabConnectionStatus.disconnected,
          transportLabel: 'stdio',
          profileLabel: 'Codelab Agent',
          detail: 'codelab serve --stdio',
          description: 'Connect to a local ACP agent.',
          onConnect: () => connected = true,
          onReconnect: () => reconnected = true,
          onConfigureConnection: () => edited = true,
        ),
      ),
    );

    expect(find.text('Codelab Agent'), findsWidgets);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('stdio'), findsOneWidget);
    expect(find.text('codelab serve --stdio'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.tap(find.text('Reconnect'));
    await tester.tap(find.text('Configure connection'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(connected, isTrue);
    expect(reconnected, isTrue);
    expect(edited, isTrue);
  });

  testWidgets('renders every connection state label', (tester) async {
    for (final status in CodeLabConnectionStatus.values) {
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 520,
            height: 180,
            child: CodeLabConnectionScreen(
              status: status,
              transportLabel: 'stdio',
              profileLabel: 'Codelab Agent',
              detail: 'state ${status.name}',
            ),
          ),
        ),
      );

      expect(find.text(_connectionStatusLabel(status)), findsOneWidget);
      expect(find.text('state ${status.name}'), findsOneWidget);
    }
  });

  testWidgets('keeps busy connection actions disabled', (tester) async {
    var connected = false;
    var reconnected = false;
    var edited = false;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabConnectionScreen(
          status: CodeLabConnectionStatus.connecting,
          transportLabel: 'stdio',
          profileLabel: 'Codelab Agent',
          isBusy: true,
          onConnect: () => connected = true,
          onReconnect: () => reconnected = true,
          onConfigureConnection: () => edited = true,
        ),
      ),
    );

    expect(find.byType(ProgressRing), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.tap(find.text('Reconnect'));
    await tester.tap(find.text('Configure connection'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(connected, isFalse);
    expect(reconnected, isFalse);
    expect(edited, isFalse);
  });

  group('CodeLabSessionSidebar', () {
    const sessions = [
      CodeLabSessionListItem(
        id: 'session-1',
        title: 'Repository audit',
        status: CodeLabSessionStatus.completed,
        subtitle: '/work/codelab-app',
      ),
      CodeLabSessionListItem(
        id: 'session-2',
        title: 'Workbench UI',
        status: CodeLabSessionStatus.awaitingApproval,
      ),
      CodeLabSessionListItem(
        id: 'session-3',
        title: 'Fix reconnect race',
        status: CodeLabSessionStatus.running,
      ),
    ];
    const projects = [
      CodeLabSidebarProject(
        path: '/work/codelab-app',
        name: 'codelab-app',
        current: true,
        sessions: sessions,
      ),
      CodeLabSidebarProject(path: '/work/notes-app', name: 'notes-app'),
    ];

    Widget sidebar({
      List<CodeLabSidebarProject> projects = projects,
      double width = 300,
      CodeLabSessionSelected onSessionSelected = acpTestSessionSelected,
      VoidCallback? onNewSession,
      ValueChanged<String>? onProjectSelected,
      VoidCallback? onLoadMore,
      VoidCallback? onOpenFolder,
      VoidCallback? onSettings,
    }) => FluentApp(
      home: Center(
        child: SizedBox(
          width: width,
          height: 560,
          child: CodeLabSessionSidebar(
            projects: projects,
            activeSessionId: 'session-2',
            onSessionSelected: onSessionSelected,
            onNewSession: onNewSession,
            onProjectSelected: onProjectSelected,
            onLoadMore: onLoadMore,
            onOpenFolder: onOpenFolder,
            onSettings: onSettings,
          ),
        ),
      ),
    );

    testWidgets('groups sessions by project and selects a session', (
      tester,
    ) async {
      String? selected;
      var newSession = 0;
      await tester.pumpWidget(
        sidebar(
          onSessionSelected: (id) => selected = id,
          onNewSession: () => newSession++,
        ),
      );

      expect(find.text('New session'), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);
      expect(
        find.byKey(CodeLabSessionSidebar.projectKey('codelab-app')),
        findsOneWidget,
      );
      expect(
        find.byKey(CodeLabSessionSidebar.projectKey('notes-app')),
        findsOneWidget,
      );
      expect(find.text('Repository audit'), findsOneWidget);
      expect(find.text('Workbench UI'), findsOneWidget);

      await tester.tap(find.text('Repository audit'));
      await tester.tap(find.byKey(CodeLabSessionSidebar.newSessionKey));
      await tester.pump(const Duration(milliseconds: 100));

      expect(selected, 'session-1');
      expect(newSession, 1);
    });

    testWidgets('shows a status badge for notable sessions only, including '
        'background ones', (tester) async {
      await tester.pumpWidget(
        sidebar(
          projects: const [
            CodeLabSidebarProject(
              path: '/work/codelab-app',
              name: 'codelab-app',
              current: true,
              sessions: [
                ...sessions,
                CodeLabSessionListItem(
                  id: 'session-4',
                  title: 'From the journal',
                  status: CodeLabSessionStatus.notLoaded,
                ),
                CodeLabSessionListItem(
                  id: 'session-5',
                  title: 'Lost on reconnect',
                  status: CodeLabSessionStatus.detached,
                ),
              ],
            ),
          ],
        ),
      );

      // Фоновая сессия показывает свой статус, хотя активна другая
      // (add-multi-session-concurrency, «Sessions sidebar shows live
      // status for background sessions»).
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Approval'), findsOneWidget);
      expect(find.text('Not loaded'), findsOneWidget);
      expect(find.text('Detached'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
    });

    testWidgets('selecting a recent project switches to it', (tester) async {
      String? selectedPath;
      await tester.pumpWidget(
        sidebar(onProjectSelected: (path) => selectedPath = path),
      );

      await tester.tap(
        find.byKey(CodeLabSessionSidebar.projectKey('notes-app')),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(selectedPath, '/work/notes-app');
    });

    testWidgets('the current project group collapses and expands', (
      tester,
    ) async {
      await tester.pumpWidget(sidebar());

      await tester.tap(
        find.byKey(CodeLabSessionSidebar.projectKey('codelab-app')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Repository audit'), findsNothing);

      await tester.tap(
        find.byKey(CodeLabSessionSidebar.projectKey('codelab-app')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Repository audit'), findsOneWidget);
    });

    testWidgets('the filter narrows sessions by title', (tester) async {
      await tester.pumpWidget(sidebar());

      await tester.enterText(
        find.byKey(CodeLabSessionSidebar.filterKey),
        'RECONNECT',
      );
      await tester.pump();

      expect(find.text('Fix reconnect race'), findsOneWidget);
      expect(find.text('Repository audit'), findsNothing);
      expect(find.text('Workbench UI'), findsNothing);
    });

    testWidgets('offers Load more only with onLoadMore and calls it', (
      tester,
    ) async {
      await tester.pumpWidget(sidebar());
      expect(find.byKey(CodeLabSessionSidebar.loadMoreKey), findsNothing);

      var requested = 0;
      await tester.pumpWidget(sidebar(onLoadMore: () => requested++));
      await tester.tap(find.byKey(CodeLabSessionSidebar.loadMoreKey));
      await tester.pump(const Duration(milliseconds: 100));

      expect(requested, 1);
    });

    testWidgets('Open folder and Settings call their callbacks', (
      tester,
    ) async {
      var openFolder = 0;
      var settings = 0;
      await tester.pumpWidget(
        sidebar(onOpenFolder: () => openFolder++, onSettings: () => settings++),
      );

      await tester.tap(find.byKey(CodeLabSessionSidebar.openFolderKey));
      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pump(const Duration(milliseconds: 100));

      expect(openFolder, 1);
      expect(settings, 1);
    });

    testWidgets('a narrow sidebar shows icons only', (tester) async {
      String? selected;
      await tester.pumpWidget(
        sidebar(width: 56, onSessionSelected: (id) => selected = id),
      );

      expect(find.text('New session'), findsNothing);
      expect(find.text('Projects'), findsNothing);
      await tester.tap(
        find.byKey(CodeLabSessionSidebar.sessionKey('session-3')),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(selected, 'session-3');
    });

    testWidgets('renders the empty state of the current project', (
      tester,
    ) async {
      await tester.pumpWidget(
        sidebar(
          projects: const [
            CodeLabSidebarProject(
              path: '/work/codelab-app',
              name: 'codelab-app',
              current: true,
            ),
          ],
        ),
      );

      expect(find.text('No sessions yet'), findsOneWidget);
    });
  });

  group('CodeLabAppBar', () {
    Widget bar({
      CodeLabConnectionStatus status = CodeLabConnectionStatus.connected,
      List<CodeLabPaneToggle> toggles = const [],
      ValueChanged<ToolPane>? onPaneToggled,
      VoidCallback? onSearch,
      VoidCallback? onRetry,
      VoidCallback? onConnect,
      VoidCallback? onMenu,
    }) => FluentApp(
      home: ScaffoldPage(
        content: CodeLabAppBar(
          title: 'CodeLab',
          connectionStatus: status,
          paneToggles: toggles,
          onPaneToggled: onPaneToggled,
          onSearch: onSearch,
          onRetry: onRetry,
          onConnect: onConnect,
          onMenu: onMenu,
          connectionTooltip: 'Codelab Agent · stdio',
        ),
      ),
    );

    testWidgets('the search field opens the palette', (tester) async {
      var searched = 0;
      await tester.pumpWidget(bar(onSearch: () => searched++));

      expect(find.text('Search or run a command'), findsOneWidget);
      await tester.tap(find.byKey(CodeLabAppBar.searchKey));
      await tester.pump(const Duration(milliseconds: 100));

      expect(searched, 1);
    });

    testWidgets('pane toggles report the pane', (tester) async {
      final toggled = <ToolPane>[];
      await tester.pumpWidget(
        bar(
          toggles: const [
            CodeLabPaneToggle(pane: ToolPane.plan, selected: true),
            CodeLabPaneToggle(pane: ToolPane.protocol),
          ],
          onPaneToggled: toggled.add,
        ),
      );

      await tester.tap(find.byKey(CodeLabAppBar.toggleKey(ToolPane.protocol)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(toggled, [ToolPane.protocol]);
    });

    testWidgets('connected badge has no Connect and no binary path', (
      tester,
    ) async {
      await tester.pumpWidget(bar(onConnect: () {}, onRetry: () {}));

      expect(find.text('Connected'), findsOneWidget);
      expect(find.byKey(CodeLabAppBar.connectionConnectKey), findsNothing);
      expect(find.byKey(CodeLabAppBar.connectionRetryKey), findsNothing);
    });

    testWidgets('a lost connection offers Retry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        bar(status: CodeLabConnectionStatus.lost, onRetry: () => retried++),
      );

      expect(find.text('Connection lost'), findsOneWidget);
      await tester.tap(find.byKey(CodeLabAppBar.connectionRetryKey));
      await tester.pump(const Duration(milliseconds: 100));

      expect(retried, 1);
    });

    testWidgets('disconnected offers Connect; reconnecting shows progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        bar(status: CodeLabConnectionStatus.disconnected, onConnect: () {}),
      );
      expect(find.byKey(CodeLabAppBar.connectionConnectKey), findsOneWidget);

      await tester.pumpWidget(
        bar(status: CodeLabConnectionStatus.reconnecting),
      );
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.byType(ProgressRing), findsOneWidget);
    });

    testWidgets('the menu button appears only with onMenu', (tester) async {
      await tester.pumpWidget(bar());
      expect(find.byKey(CodeLabAppBar.menuKey), findsNothing);

      await tester.pumpWidget(bar(onMenu: () {}));
      expect(find.byKey(CodeLabAppBar.menuKey), findsOneWidget);
    });
  });

  group('CodeLabToolDock', () {
    Widget dock({
      ToolPane active = ToolPane.plan,
      ValueChanged<ToolPane>? onSelected,
      ValueChanged<ToolPane>? onClosed,
    }) => FluentApp(
      home: SizedBox(
        width: 360,
        height: 400,
        child: CodeLabToolDock(
          active: active,
          onSelected: onSelected,
          onClosed: onClosed,
          tabs: const [
            CodeLabDockTab(pane: ToolPane.plan, content: Text('Plan body')),
            CodeLabDockTab(
              pane: ToolPane.protocol,
              content: Text('Protocol body'),
            ),
          ],
        ),
      ),
    );

    testWidgets('shows a tab per pane and the active content', (tester) async {
      await tester.pumpWidget(dock());

      expect(find.byKey(CodeLabToolDock.tabKey(ToolPane.plan)), findsOneWidget);
      expect(
        find.byKey(CodeLabToolDock.tabKey(ToolPane.protocol)),
        findsOneWidget,
      );
      expect(find.text('Plan body'), findsOneWidget);
      expect(find.text('Protocol body'), findsNothing);
      expect(
        find.byKey(CodeLabToolDock.paneKey(ToolPane.plan)),
        findsOneWidget,
      );
    });

    testWidgets('selecting and closing tabs report the pane', (tester) async {
      final selected = <ToolPane>[];
      final closed = <ToolPane>[];
      await tester.pumpWidget(
        dock(onSelected: selected.add, onClosed: closed.add),
      );

      await tester.tap(find.byKey(CodeLabToolDock.tabKey(ToolPane.protocol)));
      await tester.tap(find.byKey(CodeLabToolDock.closeKey(ToolPane.plan)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(selected, [ToolPane.protocol]);
      expect(closed, [ToolPane.plan]);
    });

    testWidgets('an active pane missing from the tabs falls back to the '
        'first', (tester) async {
      await tester.pumpWidget(dock(active: ToolPane.files));

      expect(find.text('Plan body'), findsOneWidget);
    });
  });

  testWidgets('session pane header shows title, project and mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: ScaffoldPage(
          content: CodeLabSessionPaneHeader(
            title: 'Fix reconnect race',
            projectName: 'codelab-app',
            projectPath: '/work/codelab-app',
            mode: 'standard',
          ),
        ),
      ),
    );

    expect(find.text('Fix reconnect race'), findsOneWidget);
    expect(find.text('codelab-app'), findsOneWidget);
    expect(find.text('standard'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == '/work/codelab-app',
      ),
      findsOneWidget,
    );
  });

  group('CodeLabWorkbenchLayout', () {
    void setWindow(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Widget layout({
      Widget? dock = const _AcpTestPane(label: 'Dock'),
      Widget sessionPane = const _AcpTestPane(label: 'Session'),
      bool sidebarCollapsed = false,
      bool sidebarOverlayOpen = false,
      bool dockOverlayOpen = false,
      ValueChanged<double>? onSidebarWidthChanged,
      VoidCallback? onSidebarResizeEnd,
      ValueChanged<double>? onDockWidthChanged,
      VoidCallback? onSidebarOverlayDismiss,
    }) => FluentApp(
      home: CodeLabWorkbenchLayout(
        appBar: const _AcpTestPane(label: 'App bar'),
        sidebar: const _AcpTestPane(label: 'Sidebar'),
        sessionPane: sessionPane,
        dock: dock,
        sidebarCollapsed: sidebarCollapsed,
        sidebarOverlayOpen: sidebarOverlayOpen,
        dockOverlayOpen: dockOverlayOpen,
        onSidebarWidthChanged: onSidebarWidthChanged,
        onSidebarResizeEnd: onSidebarResizeEnd,
        onDockWidthChanged: onDockWidthChanged,
        onSidebarOverlayDismiss: onSidebarOverlayDismiss,
      ),
    );

    test('layout class follows the window width thresholds', () {
      expect(
        [640.0, 641.0, 899.0, 900.0, 1279.0, 1280.0].map(CodeLabLayoutClass.of),
        [
          CodeLabLayoutClass.phone,
          CodeLabLayoutClass.narrow,
          CodeLabLayoutClass.narrow,
          CodeLabLayoutClass.medium,
          CodeLabLayoutClass.medium,
          CodeLabLayoutClass.wide,
        ],
      );
    });

    testWidgets('wide window shows the four zones left to right', (
      tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      await tester.pumpWidget(layout());

      expect(tester.takeException(), isNull);
      final appBarBottom = tester
          .getBottomLeft(find.byKey(CodeLabWorkbenchLayout.appBarKey))
          .dy;
      final sidebar = tester.getRect(
        find.byKey(CodeLabWorkbenchLayout.sidebarKey),
      );
      final session = tester.getRect(
        find.byKey(CodeLabWorkbenchLayout.sessionPaneKey),
      );
      final dock = tester.getRect(find.byKey(CodeLabWorkbenchLayout.dockKey));
      expect(sidebar.top, greaterThan(appBarBottom));
      expect(sidebar.right, lessThan(session.left));
      expect(session.right, lessThan(dock.left));
      expect(sidebar.width, 280);
      expect(dock.width, 360);
    });

    testWidgets('the dock is a column only from 1280 px', (tester) async {
      setWindow(tester, const Size(1279, 900));
      await tester.pumpWidget(layout());
      expect(find.text('Dock'), findsNothing);

      await tester.pumpWidget(layout(dockOverlayOpen: true));
      await tester.pump();
      expect(find.text('Dock'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workbench-overlay-scrim')),
        findsOneWidget,
      );
    });

    testWidgets('without open panes there is no dock', (tester) async {
      setWindow(tester, const Size(1440, 900));
      await tester.pumpWidget(layout(dock: null));

      expect(find.byKey(CodeLabWorkbenchLayout.dockKey), findsNothing);
    });

    testWidgets('narrow window hides the sidebar until it is opened over '
        'the content', (tester) async {
      setWindow(tester, const Size(820, 900));
      var dismissed = 0;
      await tester.pumpWidget(layout());
      expect(find.text('Sidebar'), findsNothing);
      expect(find.text('Session'), findsOneWidget);

      await tester.pumpWidget(
        layout(
          sidebarOverlayOpen: true,
          onSidebarOverlayDismiss: () => dismissed++,
        ),
      );
      await tester.pump();
      expect(find.text('Sidebar'), findsOneWidget);

      await tester.tapAt(const Offset(800, 450));
      expect(dismissed, 1);
    });

    testWidgets('a collapsed sidebar keeps only its icon width', (
      tester,
    ) async {
      setWindow(tester, const Size(1100, 900));
      await tester.pumpWidget(layout(sidebarCollapsed: true));

      expect(
        tester.getSize(find.byKey(CodeLabWorkbenchLayout.sidebarKey)).width,
        56,
      );
    });

    testWidgets('resizing the window across classes keeps the session pane '
        'state (MOB-3)', (tester) async {
      setWindow(tester, const Size(1440, 900));
      var created = 0;
      final pane = _CountingPane(onCreate: () => created++);
      await tester.pumpWidget(layout(sessionPane: pane));

      for (final size in const [Size(820, 900), Size(1100, 900)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(layout(sessionPane: pane));
      }
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpWidget(layout(sessionPane: pane));

      expect(created, 1);
    });

    testWidgets('dragging the sidebar divider reports a positive delta', (
      tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      final deltas = <double>[];
      var ended = 0;
      await tester.pumpWidget(
        layout(
          onSidebarWidthChanged: deltas.add,
          onSidebarResizeEnd: () => ended++,
        ),
      );

      await tester.drag(
        find.byType(CodeLabResizeHandle).first,
        const Offset(30, 0),
      );

      expect(deltas.fold(0.0, (sum, dx) => sum + dx), closeTo(30, 0.01));
      expect(ended, 1);
    });

    testWidgets('dragging the dock divider left grows the dock', (
      tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      final deltas = <double>[];
      await tester.pumpWidget(layout(onDockWidthChanged: deltas.add));

      await tester.drag(
        find.byType(CodeLabResizeHandle).last,
        const Offset(-30, 0),
      );

      expect(deltas.fold(0.0, (sum, dx) => sum + dx), closeTo(30, 0.01));
    });

    testWidgets('dividers are absent without resize callbacks', (tester) async {
      setWindow(tester, const Size(1440, 900));
      await tester.pumpWidget(layout());

      expect(find.byType(CodeLabResizeHandle), findsNothing);
    });
  });

  group('CodeLabActivityBar / CodeLabProgressChecklist', () {
    List<CodeLabPlanEntry> plan() => const [
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
    ];

    // `home:` gives its child tight, full-viewport constraints, which would
    // force even a `SizedBox.shrink()`-backed widget to fill the test
    // window — `Center` gives loose constraints instead, so the bar's
    // `Column(mainAxisSize: min)` actually shrink-wraps to its content, and
    // `SizedBox(width: 620)` keeps that width realistic without fixing a
    // height.
    Widget wrap(Widget child) => FluentApp(
      home: Center(child: SizedBox(width: 620, child: child)),
    );

    testWidgets('renders nothing when there are no sections', (tester) async {
      await tester.pumpWidget(wrap(const CodeLabActivityBar(sections: [])));

      expect(find.byType(CodeLabActivityBar), findsOneWidget);
      expect(tester.getSize(find.byType(CodeLabActivityBar)).height, 0);
    });

    testWidgets(
      'collapsed header names the in-progress entry and the remaining count',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            CodeLabActivityBar(
              sections: [
                CodeLabProgressChecklist.section(
                  id: 'plan',
                  entries: plan(),
                  onDismiss: () {},
                ),
              ],
            ),
          ),
        );

        expect(find.text('Current:'), findsOneWidget);
        expect(
          find.text('Run melos analyze to confirm no new lint issues'),
          findsOneWidget,
        );
        expect(find.text('1 left'), findsOneWidget);
        expect(find.text('Plan'), findsNothing);
      },
    );

    testWidgets('collapsed header shows an aggregate count once nothing is in '
        'progress', (tester) async {
      const allPending = [
        CodeLabPlanEntry(
          content: 'Read the module',
          status: CodeLabPlanEntryStatus.pending,
          priority: CodeLabPlanEntryPriority.low,
        ),
        CodeLabPlanEntry(
          content: 'Write the fix',
          status: CodeLabPlanEntryStatus.pending,
          priority: CodeLabPlanEntryPriority.low,
        ),
      ];
      await tester.pumpWidget(
        wrap(
          CodeLabActivityBar(
            sections: [
              CodeLabProgressChecklist.section(
                id: 'plan',
                entries: allPending,
                onDismiss: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('2 Tasks'), findsOneWidget);
    });

    testWidgets('expanding the section shows every entry with its status and '
        'priority', (tester) async {
      await tester.pumpWidget(
        wrap(
          CodeLabActivityBar(
            sections: [
              CodeLabProgressChecklist.section(
                id: 'plan',
                entries: plan(),
                onDismiss: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.text('Open PR for review'), findsNothing);

      await tester.tap(find.text('Current:'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Open PR for review'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
    });

    testWidgets('a long plan stays within a bounded height and scrolls', (
      tester,
    ) async {
      final manyEntries = List.generate(
        20,
        (index) => CodeLabPlanEntry(
          content: 'Step $index',
          status: CodeLabPlanEntryStatus.pending,
          priority: CodeLabPlanEntryPriority.low,
        ),
      );

      await tester.pumpWidget(
        wrap(
          CodeLabActivityBar(
            sections: [
              CodeLabProgressChecklist.section(
                id: 'plan',
                entries: manyEntries,
                onDismiss: () {},
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Plan'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Step 0'), findsOneWidget);
      expect(find.text('Step 19'), findsNothing);

      final barHeight = tester.getSize(find.byType(CodeLabActivityBar)).height;
      expect(barHeight, lessThan(250));
    });

    testWidgets('the dismiss button clears the plan without toggling '
        'expansion', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        wrap(
          CodeLabActivityBar(
            sections: [
              CodeLabProgressChecklist.section(
                id: 'plan',
                entries: plan(),
                onDismiss: () => dismissed = true,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.byType(CodeLabIconButton));
      await tester.pump(const Duration(milliseconds: 100));

      expect(dismissed, isTrue);
      // Still collapsed — the dismiss tap did not also toggle the section.
      expect(find.text('Open PR for review'), findsNothing);
    });
  });

  testWidgets('a given search replaces the built-in filter and keeps its '
      'order (change add-command-palette-agent-commands, D5)', (tester) async {
    final logs = CodeLabCommandAction.defaults.firstWhere(
      (a) => a.id == 'logs',
    );
    final newSession = CodeLabCommandAction.defaults.firstWhere(
      (a) => a.id == 'new',
    );
    final queries = <String>[];

    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 520,
          height: 360,
          child: CodeLabCommandPaletteSurface(
            initialQuery: '/zz',
            search: (query) {
              queries.add(query);
              return [logs, newSession];
            },
          ),
        ),
      ),
    );

    expect(queries.last, '/zz');
    expect(find.text('/logs'), findsOneWidget);
    expect(find.text('/new'), findsOneWidget);
    expect(find.text('/plan'), findsNothing);
    expect(
      tester.getTopLeft(find.text('/logs')).dy,
      lessThan(tester.getTopLeft(find.text('/new')).dy),
    );
  });
}

void acpTestSessionSelected(String sessionId) {}

void acpTestPromptSubmitted(String prompt) {}

String _connectionStatusLabel(CodeLabConnectionStatus status) {
  return switch (status) {
    CodeLabConnectionStatus.idle => 'Idle',
    CodeLabConnectionStatus.connecting => 'Connecting',
    CodeLabConnectionStatus.connected => 'Connected',
    CodeLabConnectionStatus.reconnecting => 'Reconnecting',
    CodeLabConnectionStatus.disconnected => 'Disconnected',
    CodeLabConnectionStatus.lost => 'Connection lost',
    CodeLabConnectionStatus.failed => 'Failed',
  };
}

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

/// Панель, которая считает создания своего состояния: тест MOB-3 проверяет,
/// что смена класса раскладки не пересоздаёт панель сессии.
class _CountingPane extends StatefulWidget {
  const _CountingPane({required this.onCreate});

  final VoidCallback onCreate;

  @override
  State<_CountingPane> createState() => _CountingPaneState();
}

class _CountingPaneState extends State<_CountingPane> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const Text('Session');
}
