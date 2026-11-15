// Красные тесты задачи 5b.1 (`codelab_ui`) change `add-subagents-and-tasks`:
// spec agent-workbench-ui «Панель Agents v1» (D33, D49 Т7 и Т10, D50 п. 3).
// Вынесены в отдельный файл: организм `CodeLabAgentsPane` и запрос показа
// строки у `CodeLabTranscriptPanel` появляются только в задаче 5b.3.
//
// Границы: организм не форматирует и не считает — время, число вызовов,
// токены, метки `#N` приходят готовыми строками, а колбэки лишь сообщают
// выбор пользователя. Решения в панели нет: только переходы к ленте.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _rlo = '\u202E';

const _root = CodeLabAgentRow(
  id: 'tool-root',
  depth: 1,
  type: 'review',
  title: 'Review the change',
  state: CodeLabAgentRowState.running,
  time: '12s',
  calls: '3 tool calls',
  lastAction: 'Read lib/a.dart',
);
const _child = CodeLabAgentRow(
  id: 'tool-child',
  depth: 2,
  type: 'explore',
  title: 'Find auth code',
  state: CodeLabAgentRowState.waitingForApproval,
);
const _grand = CodeLabAgentRow(
  id: 'tool-grand',
  depth: 3,
  type: 'lint',
  title: 'Check style',
  state: CodeLabAgentRowState.done,
  time: '19s',
  calls: '2 tool calls',
  tokens: '10.2k',
);

Widget _pane({
  List<CodeLabAgentRow> rows = const [_root, _child, _grand],
  Map<CodeLabAgentRowState, int> counts = const {},
  String? selectedId,
  List<CodeLabTranscriptRow> steps = const [],
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onGoToApproval,
  ValueChanged<String>? onShowInTranscript,
}) => FluentApp(
  home: SizedBox(
    width: 720,
    height: 600,
    child: CodeLabAgentsPane(
      rows: rows,
      counts: counts,
      selectedId: selectedId,
      steps: steps,
      onSelect: onSelect,
      onGoToApproval: onGoToApproval,
      onShowInTranscript: onShowInTranscript,
    ),
  ),
);

Finder _byKey(String key) => find.byKey(ValueKey(key));

/// Все тексты под [root] — для проверки «поля без данных не рисуются».
List<String> _textsUnder(WidgetTester tester, Finder root) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: root, matching: find.byType(Text)),
  ))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

void main() {
  group('CodeLabAgentsPane', () {
    testWidgets('indents rows by depth', (tester) async {
      await tester.pumpWidget(_pane());

      final root = tester.getTopLeft(find.text('review')).dx;
      final child = tester.getTopLeft(find.text('explore')).dx;
      final grand = tester.getTopLeft(find.text('lint')).dx;
      expect(child, greaterThan(root));
      expect(grand, greaterThan(child));
      // Шаг отступа одинаков для каждого уровня.
      expect(grand - child, closeTo(child - root, 0.5));
      expect(_byKey('agents-row-tool-root'), findsOneWidget);
      expect(_byKey('agents-row-tool-child'), findsOneWidget);
      expect(_byKey('agents-row-tool-grand'), findsOneWidget);
    });

    testWidgets('shows type, title, state word and готовые поля', (
      tester,
    ) async {
      await tester.pumpWidget(_pane());

      expect(find.text('Find auth code'), findsOneWidget);
      expect(find.text('running'), findsOneWidget);
      expect(find.text('waiting for approval'), findsOneWidget);
      expect(find.text('done'), findsOneWidget);
      expect(find.text('19s'), findsOneWidget);
      expect(find.text('2 tool calls'), findsOneWidget);
      expect(find.text('10.2k'), findsOneWidget);
      expect(find.textContaining('Read lib/a.dart'), findsOneWidget);
    });

    testWidgets('header lists non-zero counters in the fixed order', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pane(
          counts: const {
            // Порядок вставки нарочно перемешан: порядок задаёт кит.
            CodeLabAgentRowState.cancelled: 1,
            CodeLabAgentRowState.done: 1,
            CodeLabAgentRowState.running: 2,
            CodeLabAgentRowState.failed: 1,
            CodeLabAgentRowState.waitingForApproval: 1,
          },
        ),
      );
      expect(
        find.text(
          'Subagents · 2 running · 1 waiting for approval · 1 done · '
          '1 failed · 1 cancelled',
        ),
        findsOneWidget,
      );
    });

    testWidgets('header omits zero counters', (tester) async {
      await tester.pumpWidget(
        _pane(
          counts: const {
            CodeLabAgentRowState.running: 1,
            CodeLabAgentRowState.waitingForApproval: 0,
            CodeLabAgentRowState.done: 1,
          },
        ),
      );
      expect(find.text('Subagents · 1 running · 1 done'), findsOneWidget);
      expect(find.textContaining('0 waiting'), findsNothing);
    });

    testWidgets('header without counters is just the title', (tester) async {
      await tester.pumpWidget(_pane());
      expect(find.text('Subagents'), findsOneWidget);
    });

    testWidgets('does not draw fields without data', (tester) async {
      await tester.pumpWidget(
        _pane(
          rows: const [
            CodeLabAgentRow(
              id: 'bare',
              depth: 1,
              type: 'explore',
              title: 'Bare row',
              state: CodeLabAgentRowState.running,
            ),
          ],
        ),
      );

      final texts = _textsUnder(tester, _byKey('agents-row-bare'));
      expect(texts, containsAll(['explore', 'Bare row', 'running']));
      // Только заголовок строки, слово состояния и подпись действия:
      // ни времени, ни вызовов, ни токенов, ни заглушек «—»/«null».
      const allowed = {'explore', 'Bare row', 'running', 'Show in transcript'};
      expect(texts.toSet().difference(allowed), isEmpty, reason: '$texts');
      expect(find.text('—'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('model text is shown with visible escapes', (tester) async {
      await tester.pumpWidget(
        _pane(
          rows: const [
            CodeLabAgentRow(
              id: 'evil',
              depth: 1,
              type: 'explore',
              title: 'Find ${_rlo}code',
              state: CodeLabAgentRowState.running,
              lastAction: 'Read a$_rlo.dart',
            ),
          ],
        ),
      );

      expect(find.textContaining('Find \\u202ecode'), findsOneWidget);
      expect(find.textContaining('Read a\\u202e.dart'), findsOneWidget);
      expect(find.textContaining(_rlo), findsNothing);
    });

    testWidgets('failure text is shown with visible escapes', (tester) async {
      await tester.pumpWidget(
        _pane(
          rows: const [
            CodeLabAgentRow(
              id: 'bad',
              depth: 1,
              type: 'explore',
              title: 'Broken',
              state: CodeLabAgentRowState.failed,
              lastAction: 'Exec x$_rlo',
            ),
          ],
        ),
      );
      expect(find.text('failed'), findsOneWidget);
      expect(find.textContaining(_rlo), findsNothing);
    });

    testWidgets('shows #N labels with the item title as tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pane(
          rows: const [
            CodeLabAgentRow(
              id: 'with-items',
              depth: 1,
              type: 'explore',
              title: 'Find auth code',
              state: CodeLabAgentRowState.running,
              items: [
                CodeLabAgentItemRef(label: '#2', hint: 'Check callers'),
                CodeLabAgentItemRef(label: '#5'),
              ],
            ),
          ],
        ),
      );

      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#5'), findsOneWidget);
      expect(find.byTooltip('Check callers'), findsOneWidget);
    });

    testWidgets('tapping a row reports the selection', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(_pane(onSelect: selected.add));

      await tester.tap(_byKey('agents-row-tool-child'));
      await tester.pump();
      expect(selected, ['tool-child']);
    });

    testWidgets('show in transcript is available on every row', (tester) async {
      final shown = <String>[];
      await tester.pumpWidget(_pane(onShowInTranscript: shown.add));

      for (final id in ['tool-root', 'tool-child', 'tool-grand']) {
        expect(_byKey('agents-show-in-transcript-$id'), findsOneWidget);
      }
      await tester.tap(_byKey('agents-show-in-transcript-tool-grand'));
      await tester.pump();
      expect(shown, ['tool-grand']);
    });

    testWidgets('go to approval only on a waiting row', (tester) async {
      final went = <String>[];
      final selected = <String>[];
      await tester.pumpWidget(
        _pane(onGoToApproval: went.add, onSelect: selected.add),
      );

      expect(_byKey('agents-go-to-approval-tool-child'), findsOneWidget);
      expect(_byKey('agents-go-to-approval-tool-root'), findsNothing);
      expect(_byKey('agents-go-to-approval-tool-grand'), findsNothing);

      await tester.tap(_byKey('agents-go-to-approval-tool-child'));
      await tester.pump();
      expect(went, ['tool-child']);
      // Кнопка перехода не выбирает строку: у действий свой колбэк.
      expect(selected, isEmpty);
    });

    testWidgets('has no decision buttons or Stop actions', (tester) async {
      await tester.pumpWidget(_pane());
      for (final label in ['Allow', 'Reject', 'Stop', 'Open transcript']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.byType(CodeLabApprovalPrompt), findsNothing);
    });

    group('steps tree', () {
      // «review»: два вызова read и вызов agent внука с вызовом ls.
      const steps = <CodeLabTranscriptRow>[
        CodeLabToolCallRow(
          id: 'r1',
          status: CodeLabToolCallStatus.succeeded,
          label: 'Read',
          detail: 'lib/a.dart',
          output: ['SECRET-OUTPUT-1'],
        ),
        CodeLabToolCallRow(
          id: 'r2',
          status: CodeLabToolCallStatus.succeeded,
          label: 'Read',
          detail: 'lib/b.dart',
        ),
        CodeLabToolCallRow(
          id: 'g1',
          status: CodeLabToolCallStatus.running,
          label: 'Subagent explore: Find auth code',
          output: ['REPORT-TEXT'],
          subagent: CodeLabSubagentCall(progress: 'PROGRESS-LINE'),
          children: [
            CodeLabToolCallRow(
              id: 'g1-ls',
              status: CodeLabToolCallStatus.succeeded,
              label: 'ls',
              detail: 'lib',
            ),
            CodeLabTaskOpsRow(id: 'g1-ops', text: 'Tasks #1–#2 added'),
          ],
        ),
      ];

      testWidgets('is fully expanded in compact lines', (tester) async {
        await tester.pumpWidget(_pane(selectedId: 'tool-root', steps: steps));

        final tree = _byKey('agents-steps');
        expect(tree, findsOneWidget);
        expect(
          find.descendant(
            of: tree,
            matching: find.textContaining(
              'Read lib/a.dart',
              findRichText: true,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: tree,
            matching: find.textContaining(
              'Read lib/b.dart',
              findRichText: true,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: tree,
            matching: find.textContaining(
              'Subagent explore: Find auth code',
              findRichText: true,
            ),
          ),
          findsOneWidget,
        );
        // Вложенный вызов внука виден без раскрытия, и тихая строка задач тоже.
        expect(
          find.descendant(
            of: tree,
            matching: find.textContaining('ls lib', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tree, matching: find.byType(CodeLabTaskOpsLine)),
          findsOneWidget,
        );
      });

      testWidgets('has no tiles, output, reports or progress', (tester) async {
        await tester.pumpWidget(_pane(selectedId: 'tool-root', steps: steps));

        expect(find.byType(CodeLabToolCallTile), findsNothing);
        expect(find.text('SECRET-OUTPUT-1'), findsNothing);
        expect(find.text('REPORT-TEXT'), findsNothing);
        expect(find.text('PROGRESS-LINE'), findsNothing);
      });

      testWidgets('is absent without a selected row', (tester) async {
        await tester.pumpWidget(_pane());
        expect(_byKey('agents-steps'), findsNothing);
      });

      testWidgets('step text from the model has visible escapes', (
        tester,
      ) async {
        await tester.pumpWidget(
          _pane(
            selectedId: 'tool-root',
            steps: const [
              CodeLabToolCallRow(
                id: 'evil',
                status: CodeLabToolCallStatus.running,
                label: 'Exec',
                detail: 'ls $_rlo-la',
              ),
            ],
          ),
        );
        expect(
          find.textContaining('ls \\u202e-la', findRichText: true),
          findsOneWidget,
        );
        expect(find.textContaining(_rlo, findRichText: true), findsNothing);
      });

      testWidgets('waiting step carries the tag and go-to-approval action', (
        tester,
      ) async {
        final went = <String>[];
        await tester.pumpWidget(
          _pane(
            selectedId: 'tool-root',
            onGoToApproval: went.add,
            steps: const [
              CodeLabToolCallRow(
                id: 'wait-1',
                status: CodeLabToolCallStatus.running,
                label: 'Exec',
                detail: 'git diff --stat',
                awaitsRootDecision: true,
              ),
            ],
          ),
        );

        expect(
          find.descendant(
            of: _byKey('agents-steps'),
            matching: find.text('Awaiting approval'),
          ),
          findsOneWidget,
        );
        await tester.tap(_byKey('agents-go-to-approval-wait-1'));
        await tester.pump();
        expect(went, ['wait-1']);
      });
    });
  });

  group('CodeLabTranscriptPanel show request', () {
    const total = 60;

    List<CodeLabTranscriptRow> rowsOf(int count) => [
      // Строка `agent` с вложенным потомком — далеко вверху ленты.
      const CodeLabToolCallRow(
        id: 'agent-1',
        status: CodeLabToolCallStatus.running,
        label: 'Subagent review: Review the change',
        subagent: CodeLabSubagentCall(),
        children: [
          CodeLabToolCallRow(
            id: 'agent-1-nested',
            status: CodeLabToolCallStatus.running,
            label: 'Subagent explore: Find auth code',
            subagent: CodeLabSubagentCall(),
          ),
        ],
      ),
      for (var i = 0; i < count; i++)
        CodeLabAgentTextRow(id: 'text-$i', text: 'Answer paragraph $i'),
    ];

    Widget panel(
      List<CodeLabTranscriptRow> rows, {
      CodeLabTranscriptShowRequest? request,
    }) => FluentApp(
      home: SizedBox(
        width: 700,
        height: 400,
        child: CodeLabTranscriptPanel(
          rows: rows,
          expansionOverrides: const {'agent-1': true},
          showRequest: request,
        ),
      ),
    );

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    /// Несколько кадров без `pumpAndSettle`: подсветка живёт по таймеру, и
    /// полный settle её бы уже снял.
    Future<void> frames(WidgetTester tester) async {
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    bool isVisible(WidgetTester tester, Finder target) {
      if (target.evaluate().isEmpty) return false;
      final area = tester.getRect(find.byType(CodeLabTranscriptPanel));
      final rect = tester.getRect(target);
      return rect.top >= area.top - 1 && rect.bottom <= area.bottom + 1;
    }

    Future<void> scrollToBottom(WidgetTester tester) async {
      position(tester).jumpTo(position(tester).maxScrollExtent);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('scrolls to a row that is not built yet and highlights it', (
      tester,
    ) async {
      await tester.pumpWidget(panel(rowsOf(total)));
      await scrollToBottom(tester);
      final top = CodeLabTranscriptPanel.rowKey('agent-1');
      expect(find.byKey(top), findsNothing, reason: 'строка вне построенных');

      await tester.pumpWidget(
        panel(
          rowsOf(total),
          request: const CodeLabTranscriptShowRequest(
            rowId: 'agent-1',
            targetId: 'agent-1',
            serial: 1,
          ),
        ),
      );
      await frames(tester);

      expect(find.byKey(top), findsOneWidget);
      expect(isVisible(tester, find.byKey(top)), isTrue);
      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey('agent-1')),
        findsOneWidget,
      );

      // Подсветка короткая: около 1,5 с.
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey('agent-1')),
        findsNothing,
      );
    });

    testWidgets('scrolls to a nested target inside the row', (tester) async {
      await tester.pumpWidget(panel(rowsOf(total)));
      await scrollToBottom(tester);

      await tester.pumpWidget(
        panel(
          rowsOf(total),
          request: const CodeLabTranscriptShowRequest(
            rowId: 'agent-1',
            targetId: 'agent-1-nested',
            serial: 1,
          ),
        ),
      );
      await frames(tester);

      final target = find.byKey(
        CodeLabTranscriptPanel.targetKey('agent-1-nested'),
      );
      expect(target, findsOneWidget);
      expect(isVisible(tester, target), isTrue);
      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey('agent-1-nested')),
        findsOneWidget,
      );
    });

    testWidgets('a repeated request with a new serial scrolls again', (
      tester,
    ) async {
      const first = CodeLabTranscriptShowRequest(
        rowId: 'agent-1',
        targetId: 'agent-1',
        serial: 1,
      );
      await tester.pumpWidget(panel(rowsOf(total)));
      await scrollToBottom(tester);
      await tester.pumpWidget(panel(rowsOf(total), request: first));
      await frames(tester);
      expect(
        isVisible(tester, find.byKey(CodeLabTranscriptPanel.rowKey('agent-1'))),
        isTrue,
      );

      // Пользователь ушёл вниз; тот же запрос с новым номером — снова наверх.
      await scrollToBottom(tester);
      await tester.pumpWidget(
        panel(
          rowsOf(total),
          request: const CodeLabTranscriptShowRequest(
            rowId: 'agent-1',
            targetId: 'agent-1',
            serial: 2,
          ),
        ),
      );
      await frames(tester);
      expect(
        isVisible(tester, find.byKey(CodeLabTranscriptPanel.rowKey('agent-1'))),
        isTrue,
      );
    });

    testWidgets('does not return to the bottom after the jump (D49 Т7)', (
      tester,
    ) async {
      await tester.pumpWidget(panel(rowsOf(total)));
      await scrollToBottom(tester);
      // Лента у хвоста и следует за ним, как при идущем стриме.
      await tester.pumpWidget(panel(rowsOf(total + 1)));
      await frames(tester);

      const request = CodeLabTranscriptShowRequest(
        rowId: 'agent-1',
        targetId: 'agent-1',
        serial: 1,
      );
      await tester.pumpWidget(panel(rowsOf(total + 1), request: request));
      await frames(tester);
      final top = find.byKey(CodeLabTranscriptPanel.rowKey('agent-1'));
      expect(isVisible(tester, top), isTrue);

      // Поток дописывает ответ: без режима чтения истории лента вернулась бы к
      // низу и увела строку с экрана.
      await tester.pumpWidget(panel(rowsOf(total + 2), request: request));
      await frames(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(isVisible(tester, top), isTrue);
      expect(
        position(tester).maxScrollExtent - position(tester).pixels,
        greaterThan(200),
      );
    });
  });
}
