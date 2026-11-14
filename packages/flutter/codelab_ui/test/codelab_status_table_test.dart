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

  _skillsTableTests();
}

// Красные тесты 3.1 change `add-app-skills-page` (D12, D13): аддитивное
// расширение таблицы для страницы «Skills & extensions». Ожидаемый API:
//  * `CodeLabStatusTableCell(text, {secondary, tags, untrusted})`;
//    `tags` — `List<CodeLabStatusTableTag>` (`CodeLabStatusTableTag(label,
//    {tone = CodeLabTone.neutral})`), рисуются `CodeLabBadge` после текста;
//  * `CodeLabStatusTableRow(toggle: CodeLabStatusTableToggle(value:,
//    onChanged:, tooltip:, label:, key:))` — `ToggleSwitch` вместо кнопки
//    действия; `onChanged: null` — неактивен, `tooltip` — причина;
//  * `CodeLabStatusTable(columnFlex: [..])` — доли ширины (`List<int>`, веса как у `Expanded.flex`).
// Без новых параметров вёрстка и поведение прежние (страж MCP servers).

const _skillColumns = ['SKILL', 'SOURCE'];
const _longDescription =
    'Reviews a pull request for correctness, style and missing tests, then '
    'writes a summary with a list of concrete follow-up actions per file.';

Future<void> _pump(
  WidgetTester tester,
  List<CodeLabStatusTableRow> rows, {
  List<String> columns = _skillColumns,
  List<int>? columnFlex,
  double width = 900,
}) => tester.pumpWidget(
  FluentApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: columnFlex == null
            ? CodeLabStatusTable(columns: columns, rows: rows)
            : CodeLabStatusTable(
                columns: columns,
                rows: rows,
                columnFlex: columnFlex,
              ),
      ),
    ),
  ),
);

CodeLabStatusTableRow _skillRow(
  String name, {
  String? secondary,
  List<CodeLabStatusTableTag> tags = const [],
  bool untrusted = false,
  CodeLabStatusTableToggle? toggle,
}) => CodeLabStatusTableRow(
  key: ValueKey('skill-$name'),
  cells: [
    CodeLabStatusTableCell(
      name,
      mono: true,
      secondary: secondary,
      tags: tags,
      untrusted: untrusted,
    ),
    const CodeLabStatusTableCell('user'),
  ],
  toggle: toggle,
);

Finder _tooltipWith(String message) => find.byWidgetPredicate(
  (w) => w is Tooltip && w.message == message,
  description: 'Tooltip "$message"',
);

void _skillsTableTests() {
  group('secondary — вторая строка ячейки', () {
    testWidgets('рисуется под основным текстом приглушённым цветом', (
      tester,
    ) async {
      await _pump(tester, [_skillRow('review', secondary: 'Review a PR')]);

      final main = tester.getTopLeft(find.text('review'));
      final second = tester.getTopLeft(find.text('Review a PR'));
      expect(second.dy, greaterThan(main.dy));
      expect(second.dx, main.dx);
      final context = tester.element(find.byType(CodeLabStatusTable));
      expect(
        tester.widget<Text>(find.text('Review a PR')).style!.color,
        FluentTheme.of(context).resources.textFillColorSecondary,
      );
    });

    testWidgets('ограничена двумя строками, полный текст — в подсказке', (
      tester,
    ) async {
      await _pump(tester, [
        _skillRow('review', secondary: _longDescription),
      ], width: 360);

      final text = tester.widget<Text>(find.text(_longDescription));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(_tooltipWith(_longDescription), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('без secondary второй строки и подсказки нет', (tester) async {
      await _pump(tester, [_skillRow('review')]);

      expect(find.byType(Tooltip), findsNothing);
      expect(find.byType(Text), findsNWidgets(_skillColumns.length + 2));
    });
  });

  group('tags — теги после текста', () {
    testWidgets('каждый тег — CodeLabBadge с подписью и тоном', (tester) async {
      await _pump(tester, [
        _skillRow(
          'review',
          tags: const [
            CodeLabStatusTableTag('Overrides user skill'),
            CodeLabStatusTableTag('1 warning', tone: CodeLabTone.warning),
          ],
        ),
      ]);

      final badges = tester
          .widgetList<CodeLabBadge>(find.byType(CodeLabBadge))
          .toList();
      expect(badges.map((b) => b.label), ['Overrides user skill', '1 warning']);
      expect(badges.map((b) => b.tone), [
        CodeLabTone.neutral,
        CodeLabTone.warning,
      ]);
    });

    testWidgets('теги стоят после основного текста в той же колонке', (
      tester,
    ) async {
      await _pump(tester, [
        _skillRow(
          'review',
          tags: const [CodeLabStatusTableTag('Command only')],
        ),
      ]);

      expect(
        tester.getTopLeft(find.byType(CodeLabBadge)).dx,
        greaterThan(tester.getTopRight(find.text('review')).dx - 1),
      );
      expect(
        tester.getTopLeft(find.byType(CodeLabBadge)).dx,
        lessThan(tester.getTopLeft(find.text('user')).dx),
      );
    });

    testWidgets('без тегов бейджей нет', (tester) async {
      await _pump(tester, [_skillRow('review')]);

      expect(find.byType(CodeLabBadge), findsNothing);
    });
  });

  group('toggle — переключатель строки', () {
    testWidgets('вместо кнопки действия; нажатие передаёт новое значение', (
      tester,
    ) async {
      bool? received;
      await _pump(tester, [
        _skillRow(
          'review',
          toggle: CodeLabStatusTableToggle(
            key: const ValueKey('skills-toggle-review'),
            value: true,
            label: 'Enable review',
            onChanged: (v) => received = v,
          ),
        ),
      ]);

      expect(find.byType(CodeLabButton), findsNothing);
      final toggle = tester.widget<ToggleSwitch>(find.byType(ToggleSwitch));
      expect(toggle.checked, isTrue);
      expect(
        tester.getTopLeft(find.byType(ToggleSwitch)).dx,
        greaterThan(tester.getTopLeft(find.text('SOURCE')).dx),
      );

      await tester.tap(find.byType(ToggleSwitch));
      await tester.pumpAndSettle();
      expect(received, isFalse);
    });

    testWidgets('onChanged: null — неактивен, подсказка с причиной', (
      tester,
    ) async {
      await _pump(tester, [
        _skillRow(
          'review',
          toggle: const CodeLabStatusTableToggle(
            value: true,
            label: 'Enable review',
            onChanged: null,
            tooltip: 'Set in project config; edit .codelab/config.yaml',
          ),
        ),
      ]);

      expect(
        tester.widget<ToggleSwitch>(find.byType(ToggleSwitch)).onChanged,
        isNull,
      );
      expect(
        _tooltipWith('Set in project config; edit .codelab/config.yaml'),
        findsOneWidget,
      );
    });

    testWidgets('для чтения с экрана у переключателя есть подпись', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [
        _skillRow(
          'review',
          toggle: const CodeLabStatusTableToggle(
            value: false,
            label: 'Enable review',
            onChanged: null,
            tooltip: 'Read-only',
          ),
        ),
      ]);

      expect(find.bySemanticsLabel('Enable review'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('строка без переключателя и без действия — колонка пуста', (
      tester,
    ) async {
      await _pump(tester, [_skillRow('review')]);

      expect(find.byType(ToggleSwitch), findsNothing);
      expect(find.byType(CodeLabButton), findsNothing);
    });
  });

  group('columnFlex — доли колонок', () {
    testWidgets('ширина колонок пропорциональна долям', (tester) async {
      await _pump(
        tester,
        [_skillRow('review')],
        columnFlex: const [3, 1],
        width: 920,
      );

      // Свободная ширина: 920 − действия (120) − поля (24) = 776; 3:1.
      final firstX = tester.getTopLeft(find.text('SKILL')).dx;
      final secondX = tester.getTopLeft(find.text('SOURCE')).dx;
      expect(secondX - firstX, closeTo(776 * 0.75, 1));
    });

    testWidgets('по умолчанию колонки равны', (tester) async {
      await _pump(tester, [_skillRow('review')], width: 920);

      final firstX = tester.getTopLeft(find.text('SKILL')).dx;
      final secondX = tester.getTopLeft(find.text('SOURCE')).dx;
      expect(secondX - firstX, closeTo(776 / 2, 1));
    });
  });

  group('untrusted — недоверенный текст', () {
    const hostile = 'safe\u202Egpj.exe';

    testWidgets(
      'U+202E в имени и secondary показан escape-последовательностью',
      (tester) async {
        await _pump(tester, [
          _skillRow('na\u202Eme', secondary: hostile, untrusted: true),
        ]);

        expect(find.text('na\\u202eme'), findsOneWidget);
        expect(find.text('safe\\u202egpj.exe'), findsOneWidget);
        expect(find.text('na\u202Eme'), findsNothing);
        // Подсказка с полным текстом тоже экранирована.
        expect(_tooltipWith('safe\\u202egpj.exe'), findsOneWidget);
        expect(_tooltipWith(hostile), findsNothing);
      },
    );

    testWidgets('markdown не разбирается: звёздочки и ссылки — простой текст', (
      tester,
    ) async {
      await _pump(tester, [
        _skillRow(
          'a',
          secondary: '**bold** [x](http://evil.test)',
          untrusted: true,
        ),
      ]);

      expect(find.text('**bold** [x](http://evil.test)'), findsOneWidget);
    });

    testWidgets('без признака текст выводится как есть (страж MCP servers)', (
      tester,
    ) async {
      await _pump(tester, [_skillRow('na\u202Eme')]);

      expect(find.text('na\u202Eme'), findsOneWidget);
    });
  });

  testWidgets('страж: без новых параметров нет подсказок, бейджей и '
      'переключателей, колонки равны', (tester) async {
    await pumpDefaultTable(tester);

    expect(find.byType(Tooltip), findsNothing);
    expect(find.byType(CodeLabBadge), findsNothing);
    expect(find.byType(ToggleSwitch), findsNothing);
    final xs = [for (final t in _columns) tester.getTopLeft(find.text(t)).dx];
    final steps = [for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1]];
    for (final step in steps) {
      expect(step, closeTo(steps.first, 1));
    }
    expect(tester.widget<Text>(find.text('github')).maxLines, isNull);
  });
}

Future<void> pumpDefaultTable(WidgetTester tester) => tester.pumpWidget(
  FluentApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 900,
        child: CodeLabStatusTable(
          columns: _columns,
          rows: [_row('github', onReconnect: () {})],
        ),
      ),
    ),
  ),
);
