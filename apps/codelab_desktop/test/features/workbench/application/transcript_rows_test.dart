// Лента на строках в рабочем месте (tasks 3.1–3.3, 4.3 change
// `redesign-transcript-rows`; spec agent-workbench-ui «Model thoughts in a
// collapsible block», «Session pane header», «Empty session after
// connecting»).

import 'package:codelab_desktop/features/workbench/application/shell_part.dart';
import 'package:codelab_desktop/features/workbench/application/transcript_view_cubit.dart';
import 'package:codelab_desktop/features/workbench/presentation/widgets/main_pane.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/transcript_rows.dart';
import 'shell_cubit_characterization/harness.dart';

void main() {
  setUp(setUpCharacterization);

  group('TranscriptViewCubit', () {
    test('keeps the choice per session', () async {
      final cubit = TranscriptViewCubit(changes: ShellChanges());
      addTearDown(cubit.close);

      cubit
        ..setExpanded(sessionId: 's1', rowId: 'thought-2', expanded: true)
        ..setExpanded(sessionId: 's2', rowId: 'thought-2', expanded: false)
        ..setExpanded(sessionId: 's1', rowId: 'tool-3', expanded: true);

      expect(cubit.state.overridesFor('s1'), {
        'thought-2': true,
        'tool-3': true,
      });
      expect(cubit.state.overridesFor('s2'), {'thought-2': false});
      expect(cubit.state.overridesFor('s3'), isEmpty);
      expect(cubit.state.overridesFor(null), isEmpty);
    });
  });

  test('a thought streams until the reply starts, and the choice of the user '
      'follows its session', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    final turn = await h.startTurn('why is the build slow?');

    h.sessionUpdate('session-1', {
      'sessionUpdate': 'agent_thought_chunk',
      'content': {'type': 'text', 'text': 'check melos.yaml'},
    });
    final thought = h.cubit.state.transcriptRows.last as CodeLabThoughtRow;
    expect(thought.streaming, isTrue);
    expect(h.cubit.state.turnState, CodeLabTurnState.running);

    h.agentText('session-1', 'The bootstrap hook runs build_runner.');
    expect(
      h.cubit.state.transcriptRows
          .whereType<CodeLabThoughtRow>()
          .single
          .streaming,
      isFalse,
    );

    h.cubit.setTranscriptRowExpanded(thought.id, true);
    expect(h.cubit.state.transcriptExpansion, {thought.id: true});

    h.endTurn(turn.request);
    await turn.done;
    expect(h.cubit.state.turnState, isNull);

    await h.createSession('session-2');
    expect(h.cubit.state.transcriptExpansion, isEmpty);
    h.cubit.selectSession('session-1');
    expect(h.cubit.state.transcriptExpansion, {thought.id: true});
    expect(h.cubit.state.transcriptRows.map((row) => row.kind), [
      'user',
      'thought',
      'agent',
    ]);
  });

  testWidgets('a new session while connected shows the empty transcript, not '
      'the connection screen', (tester) async {
    final h = ShellHarness();
    await tester.runAsync(() async {
      await h.connect();
      await h.createSession('session-1');
    });

    await tester.pumpWidget(
      FluentApp(
        home: WorkbenchMainPane(state: h.cubit.state, cubit: h.cubit),
      ),
    );

    expect(find.byType(CodeLabConnectionScreen), findsNothing);
    expect(find.text('Connect'), findsNothing);
    expect(find.text('Send a message to start.'), findsOneWidget);
  });

  testWidgets('while disconnected the empty session pane offers Connect', (
    tester,
  ) async {
    final h = ShellHarness();

    await tester.pumpWidget(
      FluentApp(
        home: WorkbenchMainPane(state: h.cubit.state, cubit: h.cubit),
      ),
    );

    expect(find.byType(CodeLabConnectionScreen), findsOneWidget);
  });

  testWidgets('the header shows the turn state chip', (tester) async {
    final h = ShellHarness();
    final state = h.cubit.state.copyWith(
      transcriptRows: const [CodeLabUserRow(id: 'prompt-1', text: 'hello')],
      turnState: CodeLabTurnState.awaitingApproval,
    );

    await tester.pumpWidget(
      FluentApp(
        home: WorkbenchMainPane(state: state, cubit: h.cubit),
      ),
    );

    expect(find.text('Waiting for approval'), findsOneWidget);
  });
}
