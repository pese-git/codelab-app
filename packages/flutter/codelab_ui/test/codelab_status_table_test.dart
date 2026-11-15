// Тесты `CodeLabStatusTable` (задача 5.6 change `add-provider-setup-ui`; D19,
// артборд `Mcp`, `ListView (table)` панели «Agent status»): колонки,
// действие строки и строка без действия.
//
// Красные тесты 5.6: виджета ещё нет (реализация — задача 5.9). Ожидаемый
// API: `CodeLabStatusTable(columns:, rows:, actionsLabel:)`;
// `CodeLabStatusTableRow(key:, cells:, action:)`;
// `CodeLabStatusTableCell(text, {tone, mono, muted})` — при `tone` ячейка
// рисуется `CodeLabStatusIndicator` (тег состояния `connected`, `failed …`);
// `CodeLabStatusTableAction(label:, onPressed:, key:)` — кнопка
// `CodeLabButton` с акцентом `subtle` (`f-btn subtle` артборда).
// Знания о MCP у виджета нет: модели — простые значения и колбэки.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

const _columns = ['SERVER', 'STATE', 'TOOLS', 'LAST ERROR'];

CodeLabStatusTableRow _row(
  String name, {
  String state = 'connected',
  CodeLabStatusTone tone = CodeLabStatusTone.active,
  String tools = '42',
  String error = '—',
  VoidCallback? onReconnect,
  bool withAction = true,
}) => CodeLabStatusTableRow(
  key: ValueKey('row-$name'),
  cells: [
    CodeLabStatusTableCell(name, mono: true),
    CodeLabStatusTableCell(state, tone: tone),
    CodeLabStatusTableCell(tools),
    CodeLabStatusTableCell(error, mono: error != '—', muted: error == '—'),
  ],
  action: withAction
      ? CodeLabStatusTableAction(
          key: ValueKey('act-$name'),
          label: 'Reconnect',
          onPressed: onReconnect,
        )
      : null,
);

void main() {
  Future<void> pumpTable(
    WidgetTester tester,
    List<CodeLabStatusTableRow> rows, {
    double width = 900,
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    FluentApp(
      theme: FluentThemeData(brightness: brightness),
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: CodeLabStatusTable(columns: _columns, rows: rows),
        ),
      ),
    ),
  );

  testWidgets('shows the column titles in the mono role, bold and in the '
      'secondary colour', (tester) async {
    await pumpTable(tester, [_row('github')]);

    final context = tester.element(find.byType(CodeLabStatusTable));
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono)!;
    final theme = FluentTheme.of(context);
    for (final title in _columns) {
      final style = tester.widget<Text>(find.text(title)).style!;
      expect(style.fontFamily, mono.fontFamily, reason: title);
      expect(style.fontWeight, FontWeight.w600, reason: title);
      expect(style.color, theme.resources.textFillColorSecondary);
    }
    final xs = [
      for (final title in _columns) tester.getTopLeft(find.text(title)).dx,
    ];
    expect(xs, [...xs]..sort());
    expect(xs.toSet(), hasLength(_columns.length));
  });

  testWidgets('the cells of every row stand under their column title', (
    tester,
  ) async {
    await pumpTable(tester, [
      _row('github', tools: '42'),
      _row('postgres', tools: '0', error: 'ECONNREFUSED 127.0.0.1:5432'),
    ]);

    double x(String text) => tester.getTopLeft(find.text(text)).dx;
    expect(x('github'), x('SERVER'));
    expect(x('postgres'), x('SERVER'));
    expect(x('42'), x('TOOLS'));
    expect(x('0'), x('TOOLS'));
    expect(x('ECONNREFUSED 127.0.0.1:5432'), x('LAST ERROR'));
    expect(
      tester.getTopLeft(find.text('github')).dy,
      lessThan(tester.getTopLeft(find.text('postgres')).dy),
    );
  });

  testWidgets('a mono cell uses the mono role, a muted one the secondary '
      'colour', (tester) async {
    await pumpTable(tester, [_row('github')]);

    final context = tester.element(find.byType(CodeLabStatusTable));
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono)!;
    expect(
      tester.widget<Text>(find.text('github')).style!.fontFamily,
      mono.fontFamily,
    );
    expect(
      tester.widget<Text>(find.text('—')).style!.color,
      FluentTheme.of(context).resources.textFillColorSecondary,
    );
  });

  testWidgets('a cell with a tone is a status indicator with its label', (
    tester,
  ) async {
    await pumpTable(tester, [
      _row('github'),
      _row(
        'postgres',
        state: 'failed · retry in 24 s',
        tone: CodeLabStatusTone.danger,
      ),
      _row('playwright', state: 'disabled', tone: CodeLabStatusTone.idle),
    ]);

    final indicators = tester
        .widgetList<CodeLabStatusIndicator>(find.byType(CodeLabStatusIndicator))
        .toList();
    expect(indicators.map((i) => i.label), [
      'connected',
      'failed · retry in 24 s',
      'disabled',
    ]);
    expect(indicators.map((i) => i.tone), [
      CodeLabStatusTone.active,
      CodeLabStatusTone.danger,
      CodeLabStatusTone.idle,
    ]);
  });

  testWidgets('a row action is a subtle button in the last column and calls '
      'back once', (tester) async {
    var calls = 0;
    await pumpTable(tester, [_row('github', onReconnect: () => calls++)]);

    final button = tester.widget<CodeLabButton>(
      find.descendant(
        of: find.byKey(const ValueKey('act-github')),
        matching: find.byType(CodeLabButton),
        matchRoot: true,
      ),
    );
    expect(button.label, 'Reconnect');
    expect(button.emphasis, CodeLabButtonEmphasis.subtle);
    expect(
      tester.getTopLeft(find.text('Reconnect')).dx,
      greaterThan(tester.getTopLeft(find.text('LAST ERROR')).dx),
    );

    await tester.tap(find.byKey(const ValueKey('act-github')));
    // Нажатие кнопки Fluent оставляет таймер: дать ему отработать.
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('an action without a callback is inactive', (tester) async {
    await pumpTable(tester, [_row('github')]);

    final button = tester.widget<CodeLabButton>(
      find.descendant(
        of: find.byKey(const ValueKey('row-github')),
        matching: find.byType(CodeLabButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a row without an action has no button and keeps its cells '
      'under the titles', (tester) async {
    await pumpTable(tester, [
      _row('github'),
      _row(
        'playwright',
        state: 'disabled',
        tone: CodeLabStatusTone.idle,
        tools: '—',
        withAction: false,
      ),
    ]);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('row-playwright')),
        matching: find.byType(CodeLabButton),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('row-github')),
        matching: find.byType(CodeLabButton),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('playwright')).dx,
      tester.getTopLeft(find.text('SERVER')).dx,
    );
  });

  testWidgets('the actions column has a title for assistive technology only', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpTable(tester, [_row('github')]);

    expect(find.bySemanticsLabel('Actions'), findsOneWidget);
    expect(find.text('Actions'), findsNothing);
    handle.dispose();
  });

  testWidgets('a narrow width and an empty list do not overflow', (
    tester,
  ) async {
    await pumpTable(tester, [
      _row('postgres', error: 'ECONNREFUSED 127.0.0.1:5432'),
    ], width: 320);
    expect(tester.takeException(), isNull);

    await pumpTable(tester, const []);
    expect(tester.takeException(), isNull);
    expect(find.text('SERVER'), findsOneWidget);
  });

  testWidgets('on a 400 pt column every header stays on one line and keeps '
      'its full text in a tooltip', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: CodeLabStatusTable(
              columns: _columns,
              rows: [_row('github', error: 'ECONNREFUSED 127.0.0.1:5432')],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final header = find.text('LAST ERROR');
    expect(header, findsOneWidget);
    // Одна строка шрифта, а не две («LAST» / «ERROR»).
    expect(tester.getSize(header).height, lessThan(24));
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == 'LAST ERROR'),
      findsOneWidget,
    );
    // Полный текст ошибки остаётся в дереве (переносится, не обрезается).
    expect(find.text('ECONNREFUSED 127.0.0.1:5432'), findsOneWidget);
  });

  Widget tableOf(double width, {List<int>? columnFlex}) => FluentApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: CodeLabStatusTable(
          columns: _columns,
          columnFlex: columnFlex,
          rows: [_row('github', error: 'ECONNREFUSED 127.0.0.1:5432')],
        ),
      ),
    ),
  );

  // Тестовый шрифт Ahem шире настоящего (1 em на символ), поэтому ширина
  // взята так, чтобы весовая колонка вмещала «LAST ERROR» в Ahem (140 pt):
  // 6/16 от (520 - 24 - 120) = 141 pt. В настоящем шрифте колонке хватает
  // и ~96 pt (колонка страницы 400 pt).
  testWidgets('columnFlex gives LAST ERROR enough width to show whole', (
    tester,
  ) async {
    await tester.pumpWidget(tableOf(520, columnFlex: const [4, 3, 3, 6]));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('LAST ERROR'),
        matching: find.byType(RichText),
      ),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without columnFlex the columns are equal', (tester) async {
    await tester.pumpWidget(tableOf(520));

    final widths = [
      for (final title in _columns) tester.getSize(find.text(title)).width,
    ];
    expect(widths.toSet(), hasLength(1));
  });
}
