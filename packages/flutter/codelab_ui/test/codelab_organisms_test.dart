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
    expect(CodeLabProjectPicker, isA<Type>());
    expect(CodeLabRecentProject, isA<Type>());
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
          child: CodeLabSessionSidebar(
            activeSessionId: 'session-2',
            onSessionSelected: (sessionId) => selectedSessionId = sessionId,
            onNewSession: () => newSessionRequested = true,
            sessions: const [
              CodeLabSessionListItem(
                id: 'session-1',
                title: 'Repository audit',
                status: CodeLabSessionStatus.completed,
                subtitle: 'Checked package boundaries.',
                updatedLabel: 'Done 10 min ago',
              ),
              CodeLabSessionListItem(
                id: 'session-2',
                title: 'Workbench UI',
                status: CodeLabSessionStatus.awaitingApproval,
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
    await tester.tap(find.byType(CodeLabIconButton));
    await tester.pump(const Duration(milliseconds: 100));

    expect(selectedSessionId, 'session-1');
    expect(newSessionRequested, isTrue);
  });

  testWidgets(
    'renders a live status badge for a background (non-active) session, '
    'independent of the active one',
    (tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 320,
            height: 420,
            child: CodeLabSessionSidebar(
              activeSessionId: 'session-2',
              onSessionSelected: acpTestSessionSelected,
              sessions: const [
                CodeLabSessionListItem(
                  id: 'session-1',
                  title: 'Background refactor',
                  status: CodeLabSessionStatus.running,
                ),
                CodeLabSessionListItem(
                  id: 'session-2',
                  title: 'Active session',
                  status: CodeLabSessionStatus.idle,
                ),
              ],
            ),
          ),
        ),
      );

      // session-1's "Running" badge reflects its own live turn even though
      // it is not the active session — see
      // add-multi-session-concurrency/specs/agent-workbench-ui/spec.md,
      // "Sessions sidebar shows live status for background sessions".
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Idle'), findsOneWidget);
    },
  );

  testWidgets('shows recents, selects a recent project, and requests browse', (
    tester,
  ) async {
    String? selectedPath;
    var browseRequested = false;

    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 280,
          height: 80,
          child: CodeLabProjectPicker(
            currentProjectPath: '/Users/dev/codelab-app',
            recentProjects: const [
              CodeLabRecentProject(path: '/Users/dev/codelab-app'),
              CodeLabRecentProject(path: '/Users/dev/another-project'),
            ],
            onProjectSelected: (path) => selectedPath = path,
            onBrowseRequested: () => browseRequested = true,
          ),
        ),
      ),
    );

    expect(find.text('codelab-app'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-project-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Browse for folder…'), findsOneWidget);
    expect(find.text('/Users/dev/another-project'), findsOneWidget);

    await tester.tap(find.text('/Users/dev/another-project'));
    await tester.pumpAndSettle();

    expect(selectedPath, '/Users/dev/another-project');
    expect(browseRequested, isFalse);

    await tester.tap(find.byKey(const ValueKey('open-project-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse for folder…'));
    await tester.pumpAndSettle();

    expect(browseRequested, isTrue);
  });

  testWidgets('renders session sidebar empty state', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 280,
          height: 240,
          child: CodeLabSessionSidebar(
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
          child: CodeLabWorkbenchLayout(
            commandBar: Text('Command bar slot'),
            sessionsPane: Text('Sessions slot'),
            mainPane: Text('Transcript and prompt slot'),
            inspectorPane: Text('Inspector slot'),
          ),
        ),
      ),
    );

    expect(find.byKey(CodeLabWorkbenchLayout.commandBarKey), findsOneWidget);
    expect(find.byKey(CodeLabWorkbenchLayout.sessionsPaneKey), findsOneWidget);
    expect(find.byKey(CodeLabWorkbenchLayout.mainPaneKey), findsOneWidget);
    expect(find.byKey(CodeLabWorkbenchLayout.inspectorPaneKey), findsOneWidget);
    expect(find.text('Command bar slot'), findsOneWidget);
    expect(find.text('Sessions slot'), findsOneWidget);
    expect(find.text('Transcript and prompt slot'), findsOneWidget);
    expect(find.text('Inspector slot'), findsOneWidget);

    final sessionsLeft = tester
        .getTopLeft(find.byKey(CodeLabWorkbenchLayout.sessionsPaneKey))
        .dx;
    final mainLeft = tester
        .getTopLeft(find.byKey(CodeLabWorkbenchLayout.mainPaneKey))
        .dx;
    final inspectorLeft = tester
        .getTopLeft(find.byKey(CodeLabWorkbenchLayout.inspectorPaneKey))
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
        home: CodeLabWorkbenchLayout(
          commandBar: const _AcpTestPane(label: 'Command'),
          sessionsPane: const _AcpTestPane(label: 'Sessions'),
          mainPane: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: _AcpTestPane(label: 'Transcript')),
              const SizedBox(height: 12),
              CodeLabPromptComposer(onSubmit: acpTestPromptSubmitted),
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
          home: CodeLabWorkbenchLayout(
            commandBar: const _AcpTestPane(label: 'Command'),
            sessionsPane: const _AcpTestPane(label: 'Sessions'),
            mainPane: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: _AcpTestPane(label: 'Transcript')),
                const SizedBox(height: 12),
                CodeLabPromptComposer(onSubmit: acpTestPromptSubmitted),
              ],
            ),
            inspectorPane: const _AcpTestPane(label: 'Inspector'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final sessionsSize = tester.getSize(
        find.byKey(CodeLabWorkbenchLayout.sessionsPaneKey),
      );
      final mainTop = tester
          .getTopLeft(find.byKey(CodeLabWorkbenchLayout.mainPaneKey))
          .dy;
      final inspectorTop = tester
          .getTopLeft(find.byKey(CodeLabWorkbenchLayout.inspectorPaneKey))
          .dy;
      final mainLeft = tester
          .getTopLeft(find.byKey(CodeLabWorkbenchLayout.mainPaneKey))
          .dx;
      final inspectorLeft = tester
          .getTopLeft(find.byKey(CodeLabWorkbenchLayout.inspectorPaneKey))
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
          home: CodeLabWorkbenchLayout(
            commandBar: const _AcpTestPane(label: 'Command'),
            sessionsPane: const _AcpTestPane(label: 'Sessions'),
            mainPane: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: _AcpTestPane(label: 'Transcript')),
                const SizedBox(height: 12),
                CodeLabPromptComposer(onSubmit: acpTestPromptSubmitted),
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
        find.byKey(CodeLabWorkbenchLayout.sessionsPaneKey, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(
          CodeLabWorkbenchLayout.inspectorPaneKey,
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'workbench keeps the inspector on stage in narrow layout when asked to',
    (tester) async {
      tester.view.physicalSize = const Size(430, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        FluentApp(
          home: CodeLabWorkbenchLayout(
            commandBar: const _AcpTestPane(label: 'Command'),
            sessionsPane: const _AcpTestPane(label: 'Sessions'),
            mainPane: const _AcpTestPane(label: 'Transcript'),
            inspectorPane: const _AcpTestPane(label: 'Inspector'),
            inspectorVisibleInNarrowMode: true,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Inspector'), findsOneWidget);
      expect(find.text('Sessions'), findsNothing);
    },
  );

  testWidgets('workbench applies custom desktop pane dimensions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 1200,
          height: 720,
          child: CodeLabWorkbenchLayout(
            sessionsPaneWidth: 240,
            inspectorPaneWidth: 360,
            commandBar: _AcpTestPane(label: 'Command'),
            sessionsPane: _AcpTestPane(label: 'Sessions'),
            mainPane: _AcpTestPane(label: 'Main'),
            inspectorPane: _AcpTestPane(label: 'Inspector'),
          ),
        ),
      ),
    );

    final sessionsSize = tester.getSize(
      find.byKey(CodeLabWorkbenchLayout.sessionsPaneKey),
    );
    final inspectorSize = tester.getSize(
      find.byKey(CodeLabWorkbenchLayout.inspectorPaneKey),
    );

    expect(sessionsSize.width, 240);
    expect(inspectorSize.width, 360);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the sessions/main divider reports a positive delta', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final deltas = <double>[];
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 1200,
          height: 760,
          child: CodeLabWorkbenchLayout(
            commandBar: const _AcpTestPane(label: 'Command'),
            sessionsPane: const _AcpTestPane(label: 'Sessions'),
            mainPane: const _AcpTestPane(label: 'Main'),
            inspectorPane: const _AcpTestPane(label: 'Inspector'),
            onSessionsPaneWidthChanged: deltas.add,
          ),
        ),
      ),
    );

    await tester.drag(
      find.byType(CodeLabResizeHandle).first,
      const Offset(30, 0),
    );

    expect(deltas, isNotEmpty);
    expect(deltas.fold(0.0, (sum, dx) => sum + dx), closeTo(30, 0.01));
  });

  testWidgets(
    'dragging the main/inspector divider reports a positive delta when '
    'growing the inspector',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final deltas = <double>[];
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 1200,
            height: 760,
            child: CodeLabWorkbenchLayout(
              commandBar: const _AcpTestPane(label: 'Command'),
              sessionsPane: const _AcpTestPane(label: 'Sessions'),
              mainPane: const _AcpTestPane(label: 'Main'),
              inspectorPane: const _AcpTestPane(label: 'Inspector'),
              onInspectorPaneWidthChanged: deltas.add,
            ),
          ),
        ),
      );

      // The inspector's divider sits on its left edge, so dragging it left
      // (negative dx) must grow the inspector (positive reported delta).
      await tester.drag(
        find.byType(CodeLabResizeHandle).last,
        const Offset(-30, 0),
      );

      expect(deltas, isNotEmpty);
      expect(deltas.fold(0.0, (sum, dx) => sum + dx), closeTo(30, 0.01));
    },
  );

  testWidgets('workbench dividers are absent without resize callbacks', (
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
          child: CodeLabWorkbenchLayout(
            commandBar: _AcpTestPane(label: 'Command'),
            sessionsPane: _AcpTestPane(label: 'Sessions'),
            mainPane: _AcpTestPane(label: 'Main'),
            inspectorPane: _AcpTestPane(label: 'Inspector'),
          ),
        ),
      ),
    );

    expect(find.byType(CodeLabResizeHandle), findsNothing);
  });

  testWidgets('workbench divider signals resize end after a drag completes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var resizeEndCalls = 0;
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 1200,
          height: 760,
          child: CodeLabWorkbenchLayout(
            commandBar: const _AcpTestPane(label: 'Command'),
            sessionsPane: const _AcpTestPane(label: 'Sessions'),
            mainPane: const _AcpTestPane(label: 'Main'),
            inspectorPane: const _AcpTestPane(label: 'Inspector'),
            onSessionsPaneWidthChanged: (_) {},
            onSessionsPaneResizeEnd: () => resizeEndCalls++,
          ),
        ),
      ),
    );

    await tester.drag(
      find.byType(CodeLabResizeHandle).first,
      const Offset(30, 0),
    );

    expect(resizeEndCalls, 1);
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
