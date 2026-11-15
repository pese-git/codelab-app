// Поведение запроса показа строки в `CodeLabTranscriptPanel` (D49 Т7) и
// мелких свойств панели Agents: повтор и устаревание запроса по `serial`,
// колбэк `onShowRequestDone`, escape метки `#N`, семантика строки панели и
// отдельный ключ «Go to approval» у шага дерева.

import 'dart:ui' show Tristate;

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

List<CodeLabTranscriptRow> _rows(String prefix, {int count = 60}) => [
  CodeLabToolCallRow(
    id: 'tool-1',
    status: CodeLabToolCallStatus.running,
    label: 'Subagent review: $prefix',
    subagent: const CodeLabSubagentCall(),
  ),
  for (var i = 0; i < count; i++)
    CodeLabAgentTextRow(id: '$prefix-text-$i', text: 'Answer $prefix $i'),
];

Widget _panel(
  List<CodeLabTranscriptRow> rows, {
  CodeLabTranscriptShowRequest? request,
  ValueChanged<int>? onDone,
}) => FluentApp(
  home: SizedBox(
    width: 700,
    height: 400,
    child: CodeLabTranscriptPanel(
      rows: rows,
      showRequest: request,
      onShowRequestDone: onDone,
    ),
  ),
);

const _request = CodeLabTranscriptShowRequest(
  rowId: 'tool-1',
  targetId: 'tool-1',
  serial: 5,
);

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _toBottom(WidgetTester tester) async {
  _position(tester).jumpTo(_position(tester).maxScrollExtent);
  await tester.pump();
  await tester.pump();
}

final _rlo = String.fromCharCode(0x202E);

void main() {
  final highlight = find.byKey(CodeLabTranscriptPanel.highlightKey('tool-1'));

  group('show request serial', () {
    testWidgets('same serial after null is not executed again', (tester) async {
      await tester.pumpWidget(_panel(_rows('a')));
      await _toBottom(tester);
      await tester.pumpWidget(_panel(_rows('a'), request: _request));
      await _frames(tester);
      expect(highlight, findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(highlight, findsNothing);

      // Уход из сессии и возврат: запрос тот же, лента у низа.
      await tester.pumpWidget(_panel(_rows('a')));
      await _toBottom(tester);
      await tester.pumpWidget(_panel(_rows('a'), request: _request));
      await _frames(tester);

      expect(highlight, findsNothing);
      expect(
        find.byKey(CodeLabTranscriptPanel.rowKey('tool-1')),
        findsNothing,
        reason: 'лента не прокручена к строке повторно',
      );
    });

    testWidgets('a greater serial is executed', (tester) async {
      await tester.pumpWidget(_panel(_rows('a')));
      await _toBottom(tester);
      await tester.pumpWidget(_panel(_rows('a'), request: _request));
      await _frames(tester);
      await tester.pump(const Duration(seconds: 3));
      await _toBottom(tester);

      await tester.pumpWidget(
        _panel(
          _rows('a'),
          request: const CodeLabTranscriptShowRequest(
            rowId: 'tool-1',
            targetId: 'tool-1',
            serial: 6,
          ),
        ),
      );
      await _frames(tester);
      expect(highlight, findsOneWidget);
    });

    testWidgets('chain is cancelled when the request disappears', (
      tester,
    ) async {
      await tester.pumpWidget(_panel(_rows('a')));
      await _toBottom(tester);
      await tester.pumpWidget(_panel(_rows('a'), request: _request));
      // Цепочка начата, но не завершена; запрос исчез, строки другой сессии
      // с тем же id `tool-1`.
      await tester.pumpWidget(_panel(_rows('b')));
      await _toBottom(tester);
      await _frames(tester);

      expect(highlight, findsNothing);
      expect(
        find.byKey(CodeLabTranscriptPanel.rowKey('tool-1')),
        findsNothing,
        reason: 'цепочка прежнего запроса не прокручивает чужую ленту',
      );
    });
  });

  group('agents pane review', () {
    Widget pane({List<CodeLabTranscriptRow> steps = const []}) => FluentApp(
      home: SizedBox(
        width: 720,
        height: 600,
        child: CodeLabAgentsPane(
          rows: [
            CodeLabAgentRow(
              id: 'tool-root',
              depth: 1,
              type: 'review',
              title: 'Review',
              state: CodeLabAgentRowState.running,
              items: [CodeLabAgentItemRef(label: '#${_rlo}1')],
            ),
          ],
          selectedId: 'tool-root',
          steps: steps,
          onSelect: (_) {},
        ),
      ),
    );

    testWidgets('item label is escaped', (tester) async {
      await tester.pumpWidget(pane());
      expect(find.textContaining(_rlo), findsNothing);
      expect(find.textContaining('#\\u202e1'), findsOneWidget);
    });

    testWidgets('row is a selected button for semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(pane());
      final data = tester
          .getSemantics(find.byKey(CodeLabAgentsPane.rowKey('tool-root')))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('step approval link has its own key', (tester) async {
      String? went;
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 720,
            height: 600,
            child: CodeLabAgentsPane(
              rows: const [
                CodeLabAgentRow(
                  id: 'tool-root',
                  depth: 1,
                  type: 'review',
                  title: 'Review',
                  state: CodeLabAgentRowState.running,
                ),
              ],
              selectedId: 'tool-root',
              steps: const [
                CodeLabToolCallRow(
                  id: 'tool-step',
                  status: CodeLabToolCallStatus.running,
                  label: 'Run',
                  awaitsRootDecision: true,
                ),
              ],
              onStepGoToApproval: (id) => went = id,
            ),
          ),
        ),
      );
      final key = CodeLabAgentsPane.stepGoToApprovalKey('tool-step');
      expect(find.byKey(key), findsOneWidget);
      expect(
        find.byKey(CodeLabAgentsPane.goToApprovalKey('tool-step')),
        findsNothing,
      );
      await tester.tap(find.byKey(key));
      await tester.pump();
      expect(went, 'tool-step');
    });
  });

  group('onShowRequestDone', () {
    testWidgets('reports the serial when the show is finished', (tester) async {
      final done = <int>[];
      await tester.pumpWidget(_panel(_rows('a'), onDone: done.add));
      await _toBottom(tester);
      await tester.pumpWidget(
        _panel(_rows('a'), request: _request, onDone: done.add),
      );
      await _frames(tester);

      expect(highlight, findsOneWidget);
      expect(done, [5]);
    });

    testWidgets('is not reported when the request disappears', (tester) async {
      final done = <int>[];
      await tester.pumpWidget(_panel(_rows('a'), onDone: done.add));
      await _toBottom(tester);
      await tester.pumpWidget(
        _panel(_rows('a'), request: _request, onDone: done.add),
      );
      await tester.pumpWidget(_panel(_rows('b'), onDone: done.add));
      await _frames(tester);

      expect(done, isEmpty);
    });

    testWidgets(
      'is reported when the steps are exhausted for a missing target',
      (tester) async {
        final done = <int>[];
        await tester.pumpWidget(_panel(_rows('a'), onDone: done.add));
        await _toBottom(tester);
        await tester.pumpWidget(
          _panel(
            _rows('a'),
            request: const CodeLabTranscriptShowRequest(
              rowId: 'tool-1',
              targetId: 'tool-1/missing',
              serial: 7,
            ),
            onDone: done.add,
          ),
        );
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(done, [7]);
      },
    );
  });
}
