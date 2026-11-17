// Красные тесты задачи 1.6 change `add-desktop-usage-pane`: организм
// `CodeLabUsagePane` (слой `organisms/`; design.md D1, D2; agent-workbench-ui
// «Панель Usage»: карточки, таблицы `Per turn` и `Per model` с раскрытием,
// состояния журнала, заметка сбоя с `Retry`, заметка «без журнала»).
//
// Отсутствующее пока поведение (до задачи 1.7 виджет пуст): ключи `usage-*`,
// раскрытие хода до шагов, индикаторы, кнопки и заметки.
//
// Границы (`codelab_ui/AGENTS.md` §2): виджет ничего не форматирует и не
// считает. Тон и тексты (`~$2.26`, `—`, `Couldn't load usage history.`)
// приходят готовыми и проверяются как есть; кнопка `Rebuild from log` без
// колбэка недоступна, а не скрыта (D2 п. 1).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _pane(CodeLabUsagePane pane) => FluentApp(
  home: ScaffoldPage(
    padding: EdgeInsets.zero,
    content: SingleChildScrollView(child: pane),
  ),
);

Finder _in(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

const _cards = [
  CodeLabUsageCard(
    id: 'input',
    title: 'Input',
    value: '950',
    detail: 'cache read 400 · write 50',
  ),
  CodeLabUsageCard(id: 'output', title: 'Output', value: '300'),
  CodeLabUsageCard(
    id: 'cost',
    title: 'Cost',
    value: r'~$2.26',
    detail: 'agent sent no usage for some steps',
    tone: CodeLabTone.warning,
  ),
  CodeLabUsageCard(
    id: 'turns',
    title: 'Turns · steps',
    value: '2 · 3',
    detail: 'avg 1.5 steps per turn',
  ),
];

const _turns = [
  CodeLabUsageRow(
    id: '2',
    label: '2 · “Fix the build”',
    input: '130',
    output: '40',
    cost: r'$0.0041',
    running: true,
    note: 'subagents · 2 runs',
    children: [
      CodeLabUsageRow(
        id: '2-0',
        label: 'step 1 · Read lib/a.dart',
        input: '50',
        output: '10',
        cost: r'$0.001',
        hint: 'openai/gpt-5',
      ),
      CodeLabUsageRow(
        id: '2-1',
        label: 'step 2 · reply',
        input: '—',
        output: '—',
        cost: '—',
      ),
    ],
  ),
  CodeLabUsageRow(id: '1', label: '1', input: '—', output: '—', cost: '—'),
];

const _models = [
  CodeLabUsageRow(
    id: 'openai/gpt-5',
    label: 'openai / gpt-5',
    input: '950',
    output: '300',
    cost: r'$1.20',
  ),
  CodeLabUsageRow(
    id: 'subagents',
    label: 'Subagents',
    input: '10',
    output: '5',
    cost: '—',
    note: '2 runs',
  ),
];

CodeLabUsagePane _full({
  VoidCallback? onRebuild,
  VoidCallback? onExport,
  VoidCallback? onRetry,
  bool loading = false,
  bool refreshing = false,
  List<CodeLabUsageNote> notes = const [],
  List<CodeLabUsageRow> turns = _turns,
  List<CodeLabUsageRow> models = _models,
  bool showRebuild = true,
  bool showExport = true,
}) => CodeLabUsagePane(
  title: 'This session',
  cards: _cards,
  statusLine: 'Ledger: up to date · 12 records',
  turns: turns,
  models: models,
  loading: loading,
  refreshing: refreshing,
  notes: notes,
  showRebuild: showRebuild,
  showExport: showExport,
  onRebuild: onRebuild,
  onExport: onExport,
  onRetry: onRetry,
);

void main() {
  testWidgets('shows the header, the ledger status and the four cards as '
      'ready strings', (tester) async {
    await tester.pumpWidget(_pane(_full(onRebuild: () {}, onExport: () {})));

    expect(find.text('This session'), findsOneWidget);
    expect(
      _in('usage-ledger-status', find.text('Ledger: up to date · 12 records')),
      findsOneWidget,
    );
    expect(_in('usage-card-input', find.text('950')), findsOneWidget);
    expect(
      _in('usage-card-input', find.text('cache read 400 · write 50')),
      findsOneWidget,
    );
    expect(_in('usage-card-output', find.text('300')), findsOneWidget);
    expect(_in('usage-card-cost', find.text(r'~$2.26')), findsOneWidget);
    expect(
      _in('usage-card-cost', find.text('agent sent no usage for some steps')),
      findsOneWidget,
    );
    expect(_in('usage-card-turns', find.text('2 · 3')), findsOneWidget);
    expect(
      _in('usage-card-turns', find.text('avg 1.5 steps per turn')),
      findsOneWidget,
    );
  });

  testWidgets('the tone of a card comes from the data: a toned value is a '
      'badge, a neutral one is plain text', (tester) async {
    await tester.pumpWidget(_pane(_full()));

    expect(_in('usage-card-cost', find.byType(CodeLabBadge)), findsOneWidget);
    expect(_in('usage-card-input', find.byType(CodeLabBadge)), findsNothing);
  });

  testWidgets('a card without a second line shows no empty line', (
    tester,
  ) async {
    await tester.pumpWidget(_pane(_full()));

    expect(_in('usage-card-output', find.byType(CodeLabText)), findsWidgets);
    expect(
      _in('usage-card-output', find.textContaining('reasoning')),
      findsNothing,
    );
  });

  testWidgets('turns keep the order of the data; the running mark and the '
      'dashes are shown as given', (tester) async {
    await tester.pumpWidget(_pane(_full()));

    final newer = tester.getTopLeft(find.byKey(const ValueKey('usage-turn-2')));
    final older = tester.getTopLeft(find.byKey(const ValueKey('usage-turn-1')));
    expect(newer.dy, lessThan(older.dy));
    expect(
      _in('usage-turn-2', find.text('2 · “Fix the build”')),
      findsOneWidget,
    );
    expect(_in('usage-turn-2', find.text('running')), findsOneWidget);
    expect(_in('usage-turn-1', find.text('running')), findsNothing);
    expect(_in('usage-turn-1', find.text('—')), findsNWidgets(3));
    expect(
      _in('usage-turn-2', find.text('subagents · 2 runs')),
      findsOneWidget,
    );
  });

  testWidgets('a turn expands to its steps on tap and collapses on the '
      'second tap', (tester) async {
    await tester.pumpWidget(_pane(_full()));
    expect(find.byKey(const ValueKey('usage-step-2-0')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('usage-turn-2')));
    await tester.pump();

    expect(find.byKey(const ValueKey('usage-step-2-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-step-2-1')), findsOneWidget);
    expect(
      _in('usage-step-2-0', find.text('step 1 · Read lib/a.dart')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('usage-turn-2')));
    await tester.pump();

    expect(find.byKey(const ValueKey('usage-step-2-0')), findsNothing);
  });

  testWidgets('the model of a step is the tooltip of its row', (tester) async {
    await tester.pumpWidget(_pane(_full()));
    await tester.tap(find.byKey(const ValueKey('usage-turn-2')));
    await tester.pump();

    final tooltip = tester.widget<Tooltip>(
      _in('usage-step-2-0', find.byType(Tooltip)),
    );

    expect(tooltip.message, 'openai/gpt-5');
  });

  testWidgets('a turn without steps does not expand', (tester) async {
    await tester.pumpWidget(_pane(_full()));

    await tester.tap(find.byKey(const ValueKey('usage-turn-1')));
    await tester.pump();

    expect(find.byKey(const ValueKey('usage-step-1-0')), findsNothing);
  });

  testWidgets('models are numbered by position and carry the group note', (
    tester,
  ) async {
    await tester.pumpWidget(_pane(_full()));

    expect(_in('usage-model-0', find.text('openai / gpt-5')), findsOneWidget);
    expect(_in('usage-model-1', find.text('Subagents')), findsOneWidget);
    expect(_in('usage-model-1', find.text('2 runs')), findsOneWidget);
  });

  testWidgets('without a ledger yet an indicator replaces the tables', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pane(_full(loading: true, turns: const [], models: const [])),
    );

    expect(find.byKey(const ValueKey('usage-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-turn-2')), findsNothing);
    expect(find.byKey(const ValueKey('usage-model-0')), findsNothing);
  });

  testWidgets('refreshing keeps the old tables and shows the indicator in the '
      'header', (tester) async {
    await tester.pumpWidget(_pane(_full(refreshing: true)));

    expect(find.byKey(const ValueKey('usage-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-turn-2')), findsOneWidget);
  });

  testWidgets('no indicator when the journal is idle of work', (tester) async {
    await tester.pumpWidget(_pane(_full()));

    expect(find.byKey(const ValueKey('usage-progress')), findsNothing);
  });

  testWidgets('a failure note shows the text and Retry, and the hint is '
      'its tooltip', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _pane(
        _full(
          onRetry: () => retries++,
          notes: const [
            CodeLabUsageNote(
              text: "Couldn't load usage history.",
              hint: '-32603',
              retryLabel: 'Retry',
            ),
          ],
        ),
      ),
    );

    expect(
      _in('usage-note', find.text("Couldn't load usage history.")),
      findsOneWidget,
    );
    expect(
      tester.widget<Tooltip>(_in('usage-note', find.byType(Tooltip))).message,
      '-32603',
    );
    await tester.tap(find.byKey(const ValueKey('usage-retry')));
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('the no-history note has no Retry action', (tester) async {
    await tester.pumpWidget(
      _pane(
        const CodeLabUsagePane(
          title: 'This session',
          cards: _cards,
          notes: [
            CodeLabUsageNote(
              text: 'This agent does not provide usage history.',
            ),
          ],
        ),
      ),
    );

    expect(
      _in(
        'usage-note',
        find.text('This agent does not provide usage history.'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('usage-retry')), findsNothing);
    expect(find.byKey(const ValueKey('usage-turn-2')), findsNothing);
  });

  testWidgets('Rebuild from log and Export CSV report taps', (tester) async {
    var rebuilds = 0;
    var exports = 0;
    await tester.pumpWidget(
      _pane(_full(onRebuild: () => rebuilds++, onExport: () => exports++)),
    );

    await tester.tap(find.byKey(const ValueKey('usage-rebuild')));
    await tester.tap(find.byKey(const ValueKey('usage-export')));
    await tester.pump();

    expect(rebuilds, 1);
    expect(exports, 1);
    expect(find.text('Rebuild from log'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
  });

  testWidgets('a button without a callback is disabled, not hidden', (
    tester,
  ) async {
    await tester.pumpWidget(_pane(_full()));

    final rebuild = tester.widget<CodeLabButton>(
      find.byKey(const ValueKey('usage-rebuild')),
    );

    expect(rebuild.onPressed, isNull);
    expect(find.byKey(const ValueKey('usage-export')), findsOneWidget);
  });

  testWidgets('buttons the data does not offer are absent', (tester) async {
    await tester.pumpWidget(
      _pane(_full(showRebuild: false, showExport: false)),
    );

    expect(find.byKey(const ValueKey('usage-rebuild')), findsNothing);
    expect(find.byKey(const ValueKey('usage-export')), findsNothing);
  });
}
