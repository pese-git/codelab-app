// Красные тесты задачи 2.1 (app) change `add-subagents-and-tasks`: spec
// agent-workbench-ui «Завершённый субагент свёрнут», «Неуспешный субагент
// сохраняет тег», «Без дерева — строка прогресса» (D24, D27, артборд 30).
// Вынесены в отдельный файл, чтобы отсутствующий пока API
// (`CodeLabToolCallRow.subagent`, `CodeLabSubagentCall`) не ломал компиляцию
// соседних тестов; при реализации (задача 2.10) файл можно оставить как есть.
//
// Границы: виджет не разбирает ACP и не считает итог. Заголовок
// «Subagent <type>: <description>», сокращённый итог справа («4 tool calls ·
// 18.2k · 48s») и последнюю строку прогресса собирает kit/маппер app и
// передаёт готовыми строками; кит только решает, что показывать в свёрнутом
// виде (тег «Done» и #id скрыты, «Failed»/«Cancelled» остаются).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = 'Subagent explore: Find auth code';
const _stats = '4 tool calls · 18.2k · 48s';

CodeLabToolCallRow _agent({
  CodeLabToolCallStatus status = CodeLabToolCallStatus.succeeded,
  CodeLabSubagentCall subagent = const CodeLabSubagentCall(stats: _stats),
  List<String> output = const ['Auth lives in lib/auth/session.dart.'],
}) => CodeLabToolCallRow(
  id: 'tool-1',
  status: status,
  label: _title,
  output: output,
  subagent: subagent,
);

Widget _panel(
  List<CodeLabTranscriptRow> rows, {
  Map<String, bool> expansionOverrides = const {},
  CodeLabViewMode viewMode = CodeLabViewMode.normal,
}) => FluentApp(
  home: SizedBox(
    width: 700,
    height: 400,
    child: CodeLabTranscriptPanel(
      rows: rows,
      viewMode: viewMode,
      expansionOverrides: expansionOverrides,
    ),
  ),
);

void main() {
  test('CodeLabSubagentCall compares by value', () {
    expect(
      const CodeLabSubagentCall(stats: _stats, progress: 'p'),
      const CodeLabSubagentCall(stats: _stats, progress: 'p'),
    );
    expect(
      const CodeLabSubagentCall(stats: _stats).hashCode,
      const CodeLabSubagentCall(stats: _stats).hashCode,
    );
    expect(
      const CodeLabSubagentCall(stats: _stats),
      isNot(const CodeLabSubagentCall(stats: '1 tool call · 1k · 1s')),
    );
  });

  group('completed subagent is one collapsed line (D27)', () {
    testWidgets('title, trailing summary and success glyph, no Done tag', (
      tester,
    ) async {
      await tester.pumpWidget(_panel([_agent()]));

      expect(find.textContaining(_title), findsOneWidget);
      expect(find.text(_stats), findsOneWidget);
      expect(find.byIcon(FluentIcons.check_mark), findsOneWidget);
      // Статус передаёт глиф, а не тег; #id пункта в свёрнутом виде нет.
      expect(find.text('Done'), findsNothing);
      expect(find.byKey(CodeLabToolCallTile.statusTagKey), findsNothing);
      expect(find.textContaining('#'), findsNothing);
    });

    testWidgets('the row is collapsed by default: the report is hidden', (
      tester,
    ) async {
      await tester.pumpWidget(_panel([_agent()]));

      expect(find.textContaining('Auth lives in'), findsNothing);
      // Раскрываемая строка показывает шеврон.
      expect(find.byIcon(FluentIcons.chevron_down_small), findsOneWidget);
    });

    testWidgets('expanding shows the report', (tester) async {
      await tester.pumpWidget(
        _panel([_agent()], expansionOverrides: const {'tool-1': true}),
      );

      expect(find.textContaining('Auth lives in'), findsOneWidget);
      expect(find.byIcon(FluentIcons.chevron_up_small), findsOneWidget);
    });

    testWidgets('a header tap reports the expansion change', (tester) async {
      ({String rowId, bool expanded})? reported;
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 700,
            height: 400,
            child: CodeLabTranscriptPanel(
              rows: [_agent()],
              onExpansionChanged: (change) => reported = change,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(CodeLabToolCallTile.headerKey));

      expect(reported, (rowId: 'tool-1', expanded: true));
    });

    testWidgets('a regular call row keeps its Done tag', (tester) async {
      // Компактный вид — только у вызова `agent` с признаком subagent; у
      // стороннего агента без `_meta` строка прежняя (D28).
      await tester.pumpWidget(
        _panel(const [
          CodeLabToolCallRow(
            id: 'tool-2',
            status: CodeLabToolCallStatus.succeeded,
            label: 'Read',
            detail: 'lib/main.dart',
          ),
        ]),
      );

      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('unsuccessful subagent keeps its tag', () {
    testWidgets('Failed stays next to the summary', (tester) async {
      await tester.pumpWidget(
        _panel([_agent(status: CodeLabToolCallStatus.failed)]),
      );

      expect(find.text('Failed'), findsOneWidget);
      expect(find.text(_stats), findsOneWidget);
      expect(find.byIcon(FluentIcons.error_badge), findsOneWidget);
    });

    testWidgets('Cancelled stays next to the summary', (tester) async {
      await tester.pumpWidget(
        _panel([_agent(status: CodeLabToolCallStatus.cancelled)]),
      );

      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text(_stats), findsOneWidget);
    });
  });

  group('running subagent without a call tree shows the progress line', () {
    // Клиент без `subagentToolCalls`: потомков в ленте нет, под свёрнутой
    // строкой — последняя строка прогресса (D27 п.3, §17.3.4).
    CodeLabToolCallRow running(String? progress) => _agent(
      status: CodeLabToolCallStatus.running,
      subagent: CodeLabSubagentCall(progress: progress),
      output: const [],
    );

    testWidgets('the last progress line is under the collapsed row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel([running('explore: 2 tool calls · 6.1k tokens · 12s')]),
      );

      expect(find.textContaining(_title), findsOneWidget);
      expect(
        find.text('explore: 2 tool calls · 6.1k tokens · 12s'),
        findsOneWidget,
      );
      expect(find.text('Running'), findsOneWidget);
    });

    testWidgets('no progress yet: no extra line', (tester) async {
      await tester.pumpWidget(_panel([running(null)]));

      expect(find.textContaining(_title), findsOneWidget);
      expect(find.textContaining('tool calls'), findsNothing);
    });

    testWidgets('a finished subagent does not keep the progress line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel([
          _agent(
            subagent: const CodeLabSubagentCall(
              stats: _stats,
              progress: 'explore: 2 tool calls · 6.1k tokens · 12s',
            ),
          ),
        ]),
      );

      expect(find.text(_stats), findsOneWidget);
      expect(find.textContaining('explore: 2 tool calls'), findsNothing);
    });
  });
}
