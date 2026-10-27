// Лента переписки на строках (tasks 2.2–2.7, 2.9 change
// `redesign-transcript-rows`; spec agent-workbench-ui «Transcript reads as a
// conversation», «Model thoughts in a collapsible block», «Tool call as a
// one-line row», «Approval card inside the tool call row», «Transcript notices
// by severity»; прежние проверки прокрутки — follow-transcript-tail).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _panel(
  List<CodeLabTranscriptRow> rows, {
  double width = 600,
  double height = 400,
  CodeLabViewMode viewMode = CodeLabViewMode.normal,
  Map<String, bool> overrides = const {},
  ValueChanged<({String rowId, bool expanded})>? onExpansionChanged,
}) => FluentApp(
  home: SizedBox(
    width: width,
    height: height,
    child: CodeLabTranscriptPanel(
      rows: rows,
      viewMode: viewMode,
      expansionOverrides: overrides,
      onExpansionChanged: onExpansionChanged,
    ),
  ),
);

CodeLabToolCallRow _pendingRow(String id) => CodeLabToolCallRow(
  id: id,
  status: CodeLabToolCallStatus.queued,
  label: 'Run',
  detail: 'echo running tests',
  approval: CodeLabTranscriptApproval.pending(
    title: 'Run a command?',
    risk: CodeLabApprovalRisk.shell,
    command: 'echo running tests',
    cwd: '/work/app',
    options: const [
      CodeLabApprovalOption(
        id: 'allow',
        label: 'Allow once',
        kind: CodeLabApprovalOptionKind.allowOnce,
      ),
      CodeLabApprovalOption(
        id: 'always',
        label: 'Always allow',
        kind: CodeLabApprovalOptionKind.allowAlways,
      ),
      CodeLabApprovalOption(
        id: 'reject',
        label: 'Reject',
        kind: CodeLabApprovalOptionKind.rejectOnce,
      ),
      CodeLabApprovalOption(
        id: 'never',
        label: 'Always reject',
        kind: CodeLabApprovalOptionKind.rejectAlways,
      ),
    ],
    onOptionSelected: (_) {},
  ),
);

CodeLabAgentTextRow _agent(int i) => CodeLabAgentTextRow(
  id: 'agent-$i',
  text: 'Message number $i\nwith a second line\nand a third one.',
);

void main() {
  group('conversation', () {
    testWidgets('a prompt and its reply have no You or Agent labels', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(const [
          CodeLabUserRow(id: 'user-1', text: 'Render replies as markdown'),
          CodeLabAgentTextRow(
            id: 'agent-1',
            text: "I'll split the transcript into typed rows.",
          ),
        ]),
      );

      expect(find.text('Render replies as markdown'), findsOneWidget);
      expect(
        find.text("I'll split the transcript into typed rows."),
        findsOneWidget,
      );
      expect(find.text('You'), findsNothing);
      expect(find.text('Agent'), findsNothing);

      final bubble = tester.getRect(find.text('Render replies as markdown'));
      final reply = tester.getRect(
        find.text("I'll split the transcript into typed rows."),
      );
      expect(
        bubble.center.dx,
        greaterThan(reply.center.dx),
        reason: 'the prompt bubble sits to the right of the reply',
      );
    });

    testWidgets('a wide pane keeps a 760 px column in the centre', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _panel(const [
          CodeLabAgentTextRow(id: 'agent-1', text: 'Reply'),
        ], width: 1200),
      );

      final row = tester.getRect(
        find.byKey(CodeLabTranscriptPanel.rowKey('agent-1')),
      );
      final column = tester.getRect(
        find
            .descendant(
              of: find.byKey(CodeLabTranscriptPanel.rowKey('agent-1')),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(column.width, kTranscriptColumnMaxWidth);
      expect(column.center.dx, closeTo(row.center.dx, 1));
    });

    testWidgets('long user, agent and notice texts are never cut', (
      tester,
    ) async {
      final longText = List.generate(12, (i) => 'Line ${i + 1}.').join('\n');
      for (final viewMode in CodeLabViewMode.values) {
        for (final row in <CodeLabTranscriptRow>[
          CodeLabUserRow(id: 'r', text: longText),
          CodeLabAgentTextRow(id: 'r', text: longText),
          CodeLabNoticeRow(
            id: 'r',
            severity: CodeLabNoticeSeverity.warning,
            body: longText,
          ),
        ]) {
          await tester.pumpWidget(
            _panel([row], height: 600, viewMode: viewMode),
          );
          final text = tester.widget<Text>(find.text(longText));
          expect(text.maxLines, isNull, reason: '$viewMode ${row.runtimeType}');
        }
      }
    });

    testWidgets('an empty transcript shows its empty label', (tester) async {
      await tester.pumpWidget(_panel(const []));

      expect(find.text('No transcript yet'), findsOneWidget);
    });
  });

  group('thoughts', () {
    const thought = 'Goldens need a fixed font.';

    testWidgets('a streaming thought is expanded and says Thinking', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(const [
          CodeLabThoughtRow(id: 't', text: thought, streaming: true),
        ]),
      );

      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.byType(ProgressRing), findsOneWidget);
      expect(find.text(thought), findsOneWidget);
    });

    testWidgets('a finished thought collapses to Thoughts', (tester) async {
      await tester.pumpWidget(
        _panel(const [CodeLabThoughtRow(id: 't', text: thought)]),
      );

      expect(find.text('Thoughts'), findsOneWidget);
      expect(find.text(thought), findsNothing);
    });

    testWidgets('verbose expands and summary keeps the header only', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(const [
          CodeLabThoughtRow(id: 't', text: thought),
        ], viewMode: CodeLabViewMode.verbose),
      );
      expect(find.text(thought), findsOneWidget);

      await tester.pumpWidget(
        _panel(const [
          CodeLabThoughtRow(id: 't', text: thought, streaming: true),
        ], viewMode: CodeLabViewMode.summary),
      );
      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.text(thought), findsNothing);
    });

    testWidgets("the user's choice wins and the tap reports it", (
      tester,
    ) async {
      ({String rowId, bool expanded})? reported;
      await tester.pumpWidget(
        _panel(const [
          CodeLabThoughtRow(id: 't', text: thought),
        ], onExpansionChanged: (change) => reported = change),
      );

      await tester.tap(find.byKey(CodeLabThoughtBlock.headerKey));
      expect(reported, (rowId: 't', expanded: true));

      await tester.pumpWidget(
        _panel(
          const [CodeLabThoughtRow(id: 't', text: thought)],
          overrides: const {'t': true},
        ),
      );
      expect(find.text(thought), findsOneWidget);
    });
  });

  group('tool call rows', () {
    testWidgets('a completed read is one row: label, detail and Done', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(const [
          CodeLabToolCallRow(
            id: 'tool-1',
            status: CodeLabToolCallStatus.succeeded,
            label: 'Read',
            detail: 'lib/main.dart',
          ),
        ]),
      );

      expect(find.text('Read'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('a failed call shows its reason only when expanded', (
      tester,
    ) async {
      const row = CodeLabToolCallRow(
        id: 'tool-1',
        status: CodeLabToolCallStatus.failed,
        label: 'Read',
        detail: 'lib/main.dart',
        secondary: 'File not found: lib/main.dart',
      );
      await tester.pumpWidget(_panel(const [row]));
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('File not found: lib/main.dart'), findsNothing);

      await tester.pumpWidget(_panel(const [row], overrides: {'tool-1': true}));
      expect(find.text('File not found: lib/main.dart'), findsOneWidget);
    });

    testWidgets('a reason equal to the output is shown once', (tester) async {
      await tester.pumpWidget(
        _panel(
          const [
            CodeLabToolCallRow(
              id: 'tool-1',
              status: CodeLabToolCallStatus.failed,
              label: 'Read',
              detail: 'lib/main.dart',
              secondary: 'File not found: lib/main.dart',
              output: ['File not found: lib/main.dart'],
            ),
          ],
          overrides: {'tool-1': true},
        ),
      );

      expect(find.text('File not found: lib/main.dart'), findsOneWidget);
    });

    testWidgets('verbose expands the output', (tester) async {
      await tester.pumpWidget(
        _panel(const [
          CodeLabToolCallRow(
            id: 'tool-1',
            status: CodeLabToolCallStatus.succeeded,
            label: 'Run',
            detail: 'echo hi',
            output: ['hi'],
          ),
        ], viewMode: CodeLabViewMode.verbose),
      );

      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('a command awaiting approval is expanded with its card', (
      tester,
    ) async {
      await tester.pumpWidget(_panel([_pendingRow('tool-1')], width: 820));

      expect(find.text('Awaiting approval'), findsOneWidget);
      expect(find.text('Queued'), findsNothing);
      expect(find.text('Run a command?'), findsOneWidget);
      expect(find.text(r'$ echo running tests'), findsOneWidget);
      expect(find.text('/work/app'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Allow once'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a pending approval stays expanded against an override', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(
          [_pendingRow('tool-1')],
          width: 820,
          overrides: const {'tool-1': false},
        ),
      );

      expect(find.text('Run a command?'), findsOneWidget);
    });

    testWidgets('a decision leaves a tag toned by its outcome', (tester) async {
      Future<void> pumpResolved(CodeLabApprovalOutcome outcome) =>
          tester.pumpWidget(
            _panel([
              CodeLabToolCallRow(
                id: 'tool-1',
                status: CodeLabToolCallStatus.succeeded,
                label: 'Run',
                approval: CodeLabTranscriptApproval.resolved(
                  label: 'Allow once',
                  outcome: outcome,
                ),
              ),
            ]),
          );

      CodeLabTone tagTone() => tester
          .widget<CodeLabBadge>(
            find.ancestor(
              of: find.text('Allow once'),
              matching: find.byType(CodeLabBadge),
            ),
          )
          .tone;

      await pumpResolved(CodeLabApprovalOutcome.allowed);
      expect(tagTone(), CodeLabTone.success);
      expect(find.text('Run a command?'), findsNothing);

      await pumpResolved(CodeLabApprovalOutcome.cancelled);
      expect(tagTone(), CodeLabTone.warning);

      await pumpResolved(CodeLabApprovalOutcome.rejected);
      expect(tagTone(), CodeLabTone.danger);
    });
  });

  group('notices', () {
    testWidgets('an info notice is a neutral line, not an InfoBar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(const [
          CodeLabNoticeRow(
            id: 'n',
            severity: CodeLabNoticeSeverity.info,
            body:
                'The agent cannot restore sessions; a new session was '
                'started.',
          ),
        ]),
      );

      expect(
        find.textContaining('a new session was started', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(InfoBar), findsNothing);
    });

    testWidgets('a failed turn notice hides details until expanded and '
        'offers its action', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        _panel([
          CodeLabNoticeRow(
            id: 'prompt-error-1',
            severity: CodeLabNoticeSeverity.error,
            title: 'The model provider is unavailable',
            body: '503 Service Unavailable',
            details: 'ACP request session/prompt failed: Turn failed',
            action: CodeLabTranscriptAction(
              label: 'Retry',
              icon: FluentIcons.refresh,
              onPressed: () => retried = true,
            ),
          ),
        ]),
      );

      expect(find.byType(InfoBar), findsOneWidget);
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
  });

  group('auto-scroll to approvals', () {
    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    testWidgets('follows a new pending approval only near the bottom', (
      tester,
    ) async {
      final base = [for (var i = 0; i < 20; i += 1) _agent(i)];
      await tester.pumpWidget(_panel(base, width: 820, height: 200));
      await tester.pumpAndSettle();

      await tester.fling(find.byType(Scrollable), const Offset(0, -5000), 3000);
      await tester.pumpAndSettle();
      expect(position(tester).pixels, position(tester).maxScrollExtent);

      await tester.pumpWidget(
        _panel([...base, _pendingRow('p1')], width: 820, height: 200),
      );
      await tester.pumpAndSettle();
      expect(position(tester).pixels, position(tester).maxScrollExtent);

      await tester.fling(find.byType(Scrollable), const Offset(0, 5000), 3000);
      await tester.pumpAndSettle();
      expect(position(tester).pixels, 0.0);

      await tester.pumpWidget(
        _panel(
          [...base, _pendingRow('p1'), _pendingRow('p2')],
          width: 820,
          height: 200,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        position(tester).pixels,
        0.0,
        reason: 'does not yank the user away from history they are reading',
      );
    });

    testWidgets('brings into view an approval present on the first build', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(
          [for (var i = 0; i < 20; i += 1) _agent(i), _pendingRow('p1')],
          width: 820,
          height: 300,
        ),
      );
      await tester.pumpAndSettle();

      expect(position(tester).maxScrollExtent, greaterThan(0));
      expect(position(tester).pixels, position(tester).maxScrollExtent);
      expect(
        tester.getRect(find.text('Allow once')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(Scrollable)).bottom),
      );
    });
  });

  group('follows the transcript tail (follow-transcript-tail)', () {
    List<CodeLabTranscriptRow> rows(int count) => [
      for (var i = 0; i < count; i += 1)
        if (i.isEven)
          CodeLabToolCallRow(
            id: 'row-$i',
            status: CodeLabToolCallStatus.succeeded,
            label: 'Tool $i',
          )
        else
          _agent(i),
    ];

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    testWidgets('new rows at the bottom stay visible', (tester) async {
      await tester.pumpWidget(_panel(rows(1), height: 200));
      await tester.pumpAndSettle();
      for (var count = 2; count <= 16; count += 1) {
        await tester.pumpWidget(_panel(rows(count), height: 200));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(position(tester).maxScrollExtent, greaterThan(200));
      expect(position(tester).pixels, position(tester).maxScrollExtent);
      expect(find.text('Tool 14'), findsOneWidget);
    });

    testWidgets('does not move while the user reads history', (tester) async {
      await tester.pumpWidget(_panel(rows(16), height: 200));
      await tester.pumpAndSettle();
      await tester.fling(find.byType(Scrollable), const Offset(0, -5000), 3000);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable), const Offset(0, 300));
      await tester.pumpAndSettle();
      final readingOffset = position(tester).pixels;

      await tester.pumpWidget(_panel(rows(20), height: 200));
      await tester.pumpAndSettle();

      expect(position(tester).pixels, readingOffset);
      expect(find.text('Tool 18'), findsNothing);
    });

    testWidgets('returning to the bottom resumes following', (tester) async {
      await tester.pumpWidget(_panel(rows(16), height: 200));
      await tester.pumpAndSettle();
      await tester.fling(find.byType(Scrollable), const Offset(0, -5000), 3000);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable), const Offset(0, 300));
      await tester.pumpAndSettle();
      await tester.fling(find.byType(Scrollable), const Offset(0, -5000), 3000);
      await tester.pumpAndSettle();

      await tester.pumpWidget(_panel(rows(20), height: 200));
      await tester.pumpAndSettle();

      expect(position(tester).pixels, position(tester).maxScrollExtent);
      expect(find.text('Tool 18'), findsOneWidget);
    });
  });

  testWidgets('session pane header shows the turn state chip', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 800,
          child: CodeLabSessionPaneHeader(
            title: 'Fix reconnect race',
            turnState: CodeLabTurnState.awaitingApproval,
          ),
        ),
      ),
    );

    expect(find.text('Waiting for approval'), findsOneWidget);

    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 800,
          child: CodeLabSessionPaneHeader(title: 'Fix reconnect race'),
        ),
      ),
    );
    expect(find.byKey(CodeLabSessionPaneHeader.turnChipKey), findsNothing);
  });
}
