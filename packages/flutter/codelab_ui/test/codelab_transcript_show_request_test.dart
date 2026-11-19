// Поведение запроса показа строки в `CodeLabTranscriptPanel` (D49 Т7) и
// мелких свойств панели Agents: повтор и устаревание запроса по `serial`,
// колбэк `onShowRequestDone`, escape метки `#N`, семантика строки панели и
// отдельный ключ «Go to approval» у шага дерева.

import 'dart:ui' show Tristate;

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/approval_focus.dart';

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

  // Запрос показа с `focusApproval` (задача 2.1 change `fix-approval-focus`;
  // design.md D4, п. 2; spec «Переход к ожидающему одобрению с клавиатуры»).
  group('focusApproval', () {
    const options = [
      CodeLabApprovalOption(
        id: 'ao',
        label: 'Allow once',
        kind: CodeLabApprovalOptionKind.allowOnce,
      ),
      CodeLabApprovalOption(
        id: 'ro',
        label: 'Reject',
        kind: CodeLabApprovalOptionKind.rejectOnce,
      ),
    ];

    CodeLabTranscriptApproval pending(String targetId) =>
        CodeLabTranscriptApproval.pending(
          risk: CodeLabApprovalRisk.shell,
          options: options,
          onOptionSelected: (_) {},
          targetId: targetId,
        );

    // Одобрение корня: цель — сама строка (как `AgentsPaneData`).
    List<CodeLabTranscriptRow> ownRows() => [
      CodeLabToolCallRow(
        id: 'tool-1',
        status: CodeLabToolCallStatus.running,
        label: 'Run echo',
        approval: pending('perm-1'),
      ),
      for (var i = 0; i < 60; i++)
        CodeLabAgentTextRow(id: 'text-$i', text: 'Answer $i'),
    ];

    // Одобрение потомка: блок под строкой `agent`, цель — id запроса.
    List<CodeLabTranscriptRow> childRows() => [
      CodeLabToolCallRow(
        id: 'tool-1',
        status: CodeLabToolCallStatus.running,
        label: 'Subagent review: x',
        subagent: const CodeLabSubagentCall(),
        childApprovals: [pending('perm-9')],
      ),
      for (var i = 0; i < 60; i++)
        CodeLabAgentTextRow(id: 'text-$i', text: 'Answer $i'),
    ];

    late FocusNode outside;
    setUp(() {
      outside = FocusNode(debugLabel: 'outside');
      addTearDown(outside.dispose);
    });

    Widget host(
      List<CodeLabTranscriptRow> rows, {
      CodeLabTranscriptShowRequest? request,
      ValueChanged<int>? onDone,
      Key? panelKey,
    }) => FluentApp(
      home: Column(
        children: [
          // Узел «вне полосы»: от него видно, переносит ли лента фокус.
          Focus(focusNode: outside, child: const SizedBox(height: 20)),
          SizedBox(
            width: 700,
            height: 400,
            child: CodeLabTranscriptPanel(
              key: panelKey,
              rows: rows,
              showRequest: request,
              onShowRequestDone: onDone,
            ),
          ),
        ],
      ),
    );

    CodeLabTranscriptShowRequest req(
      String targetId, {
      int serial = 5,
      bool focus = true,
    }) => CodeLabTranscriptShowRequest(
      rowId: 'tool-1',
      targetId: targetId,
      serial: serial,
      focusApproval: focus,
    );

    final prompt = find.byType(CodeLabApprovalPrompt);

    Future<void> start(
      WidgetTester tester,
      List<CodeLabTranscriptRow> rows,
    ) async {
      await tester.pumpWidget(host(rows));
      await _toBottom(tester);
      outside.requestFocus();
      await tester.pump();
      expect(outside.hasPrimaryFocus, isTrue);
    }

    testWidgets('scrolls to the target and focuses its bar', (tester) async {
      await start(tester, ownRows());

      await tester.pumpWidget(host(ownRows(), request: req('tool-1')));
      await _frames(tester);

      expect(focusIsInside(tester, prompt), isTrue);
      expect(
        focusIsInside(tester, find.byKey(CodeLabApprovalPrompt.allowKey)),
        isFalse,
        reason: 'фокус на самой полосе, а не на кнопке',
      );
    });

    testWidgets('focuses the bar of a descendant approval under the agent '
        'row', (tester) async {
      await start(tester, childRows());

      await tester.pumpWidget(host(childRows(), request: req('perm-9')));
      await _frames(tester);

      expect(focusIsInside(tester, prompt), isTrue);
    });

    testWidgets('a request without the flag leaves the focus alone', (
      tester,
    ) async {
      await start(tester, ownRows());

      await tester.pumpWidget(
        host(ownRows(), request: req('tool-1', focus: false)),
      );
      await _frames(tester);

      expect(outside.hasPrimaryFocus, isTrue);
    });

    testWidgets('a target that was not built keeps the focus and reports '
        'done', (tester) async {
      final done = <int>[];
      await start(tester, ownRows());

      await tester.pumpWidget(
        host(ownRows(), request: req('tool-1/missing'), onDone: done.add),
      );
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(outside.hasPrimaryFocus, isTrue);
      expect(done, [5]);
    });

    testWidgets('a stale request does not move the focus: only the newer '
        'serial is reported', (tester) async {
      final done = <int>[];
      await start(tester, ownRows());

      await tester.pumpWidget(
        host(ownRows(), request: req('tool-1'), onDone: done.add),
      );
      // Запрос сменился на более новый, без признака, до кадров прежнего.
      await tester.pumpWidget(
        host(
          ownRows(),
          request: req('tool-1', serial: 6, focus: false),
          onDone: done.add,
        ),
      );
      await _frames(tester);

      expect(outside.hasPrimaryFocus, isTrue);
      expect(done, [6]);
    });

    testWidgets('the same request after null does not focus again', (
      tester,
    ) async {
      await start(tester, ownRows());
      await tester.pumpWidget(host(ownRows(), request: req('tool-1')));
      await _frames(tester);
      expect(focusIsInside(tester, prompt), isTrue);

      // Пользователь ушёл с полосы; хост погасил запрос и показал снова тот
      // же номер (возврат в сессию): повторного фокуса нет.
      outside.requestFocus();
      await tester.pump();
      await tester.pumpWidget(host(ownRows()));
      await _toBottom(tester);
      await tester.pumpWidget(host(ownRows(), request: req('tool-1')));
      await _frames(tester);

      expect(outside.hasPrimaryFocus, isTrue);
    });
  });

  // Уход полосы с фокусом из ленты (задача 3.1 `fix-approval-focus`, D5): лента
  // сообщает хосту `onApprovalFocusReleased`, когда исчезает полоса, в которой
  // был фокус; без фокуса — не сообщает.
  group('onApprovalFocusReleased', () {
    const options = [
      CodeLabApprovalOption(
        id: 'ao',
        label: 'Allow once',
        kind: CodeLabApprovalOptionKind.allowOnce,
      ),
    ];

    List<CodeLabTranscriptRow> rows({required bool pending}) => [
      CodeLabToolCallRow(
        id: 'tool-1',
        status: CodeLabToolCallStatus.running,
        label: 'Run echo',
        approval: pending
            ? CodeLabTranscriptApproval.pending(
                risk: CodeLabApprovalRisk.shell,
                options: options,
                onOptionSelected: (_) {},
                targetId: 'perm-1',
              )
            : const CodeLabTranscriptApproval.resolved(label: 'Allow once'),
      ),
    ];

    Widget host(
      List<CodeLabTranscriptRow> rows, {
      CodeLabTranscriptShowRequest? request,
      required VoidCallback onReleased,
    }) => FluentApp(
      home: SizedBox(
        width: 700,
        height: 400,
        child: CodeLabTranscriptPanel(
          rows: rows,
          showRequest: request,
          onApprovalFocusReleased: onReleased,
        ),
      ),
    );

    const request = CodeLabTranscriptShowRequest(
      rowId: 'tool-1',
      targetId: 'tool-1',
      serial: 5,
      focusApproval: true,
    );

    testWidgets('the focused bar is gone: reported once', (tester) async {
      var released = 0;
      void onReleased() => released++;
      await tester.pumpWidget(
        host(rows(pending: true), onReleased: onReleased),
      );
      await tester.pumpWidget(
        host(rows(pending: true), request: request, onReleased: onReleased),
      );
      await _frames(tester);
      expect(focusIsInside(tester, find.byType(CodeLabApprovalPrompt)), isTrue);

      await tester.pumpWidget(
        host(rows(pending: false), onReleased: onReleased),
      );
      await tester.pump();

      expect(find.byType(CodeLabApprovalPrompt), findsNothing);
      expect(released, 1);
    });

    testWidgets('a bar without focus is gone: not reported', (tester) async {
      var released = 0;
      void onReleased() => released++;
      await tester.pumpWidget(
        host(rows(pending: true), onReleased: onReleased),
      );
      await tester.pump();

      await tester.pumpWidget(
        host(rows(pending: false), onReleased: onReleased),
      );
      await tester.pump();

      expect(find.byType(CodeLabApprovalPrompt), findsNothing);
      expect(released, 0);
    });
  });
}
