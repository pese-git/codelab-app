// Тесты `CodeLabKeyValueList` (задача 2.8 change `add-provider-setup-ui`;
// D19, артборд `Providers`, класс `.kv`): подписи и значения, моноширинная
// часть, колонка подписей 140 px, порядок и пустой список.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpList(WidgetTester tester, Widget list) => tester.pumpWidget(
    FluentApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 600, child: list),
      ),
    ),
  );

  testWidgets('shows labels and values in the given order', (tester) async {
    await pumpList(
      tester,
      const CodeLabKeyValueList(
        entries: [
          CodeLabKeyValueEntry(label: 'Key', value: 'In keychain'),
          CodeLabKeyValueEntry(label: 'Last check', value: '14:01 · 12 models'),
          CodeLabKeyValueEntry(label: 'Source', monoValue: '~/.codelab/a.yaml'),
        ],
      ),
    );

    expect(find.text('Key'), findsOneWidget);
    expect(find.text('In keychain'), findsOneWidget);
    expect(find.text('14:01 · 12 models'), findsOneWidget);
    expect(find.text('~/.codelab/a.yaml'), findsOneWidget);
    final ys = [
      'Key',
      'Last check',
      'Source',
    ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(ys, [...ys]..sort());
    expect(ys.toSet().length, 3);
  });

  testWidgets('aligns values in one column after a 140 px label column', (
    tester,
  ) async {
    await pumpList(
      tester,
      const CodeLabKeyValueList(
        entries: [
          CodeLabKeyValueEntry(label: 'Key', value: 'a'),
          CodeLabKeyValueEntry(label: 'Last check', value: 'b'),
        ],
      ),
    );

    final listLeft = tester.getTopLeft(find.byType(CodeLabKeyValueList)).dx;
    final a = tester.getTopLeft(find.text('a')).dx;
    final b = tester.getTopLeft(find.text('b')).dx;
    expect(a, b);
    expect(a - listLeft, 140 + 16);
  });

  testWidgets('sets the mono part in a monospace font after the text', (
    tester,
  ) async {
    await pumpList(
      tester,
      const CodeLabKeyValueList(
        entries: [
          CodeLabKeyValueEntry(
            label: 'Key',
            value: 'In keychain as ',
            monoValue: 'codelab/anthropic',
          ),
        ],
      ),
    );

    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) =>
            w is RichText && w.text.toPlainText().contains('codelab/anthropic'),
      ),
    );
    expect(rich.text.toPlainText(), 'In keychain as codelab/anthropic');
    final spans = <TextSpan>[];
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.text != null) spans.add(s);
      return true;
    });
    final mono = spans.firstWhere((s) => s.text == 'codelab/anthropic');
    expect(mono.style?.fontFamily, 'Menlo');
  });

  testWidgets('wraps long values instead of overflowing', (tester) async {
    await pumpList(
      tester,
      CodeLabKeyValueList(
        entries: [CodeLabKeyValueEntry(label: 'Source', value: 'word ' * 80)],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(CodeLabKeyValueList)).height,
      greaterThan(40),
    );
  });

  testWidgets('renders nothing visible for an empty list', (tester) async {
    await pumpList(tester, const CodeLabKeyValueList(entries: []));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(CodeLabKeyValueList)).height, 0);
  });
}
