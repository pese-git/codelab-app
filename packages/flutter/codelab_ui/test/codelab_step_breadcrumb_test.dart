// Тесты `CodeLabStepBreadcrumb` (задача 3.5 change `add-provider-setup-ui`;
// D19, артборд `Wizard`, класс `.st`): подписи шагов с разделителем `›`,
// текущий шаг полужирный и основным цветом, остальные — вторичным.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _steps = ['API type', 'Base URL', 'Key', 'Check', 'Model', 'Review'];

void main() {
  Future<void> pumpBreadcrumb(
    WidgetTester tester, {
    required int current,
    List<String> steps = _steps,
    double width = 800,
  }) => tester.pumpWidget(
    FluentApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: CodeLabStepBreadcrumb(steps: steps, current: current),
        ),
      ),
    ),
  );

  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!;

  testWidgets('shows every step, the separator on all but the last', (
    tester,
  ) async {
    await pumpBreadcrumb(tester, current: 3);

    for (final label in _steps.take(5)) {
      expect(find.text('$label ›'), findsOneWidget);
    }
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Review ›'), findsNothing);
    final xs = [
      'API type ›',
      'Base URL ›',
      'Key ›',
      'Check ›',
      'Model ›',
      'Review',
    ].map((t) => tester.getTopLeft(find.text(t)).dx).toList();
    expect(xs, [...xs]..sort());
  });

  testWidgets('only the current step is bold and in the primary colour', (
    tester,
  ) async {
    await pumpBreadcrumb(tester, current: 3);

    final theme = FluentTheme.of(
      tester.element(find.byType(CodeLabStepBreadcrumb)),
    );
    final current = styleOf(tester, 'Check ›');
    expect(current.fontWeight, FontWeight.w600);
    expect(current.color, theme.resources.textFillColorPrimary);
    for (final other in ['API type ›', 'Key ›', 'Model ›', 'Review']) {
      final style = styleOf(tester, other);
      expect(style.fontWeight, isNot(FontWeight.w600), reason: other);
      expect(style.color, theme.resources.textFillColorSecondary);
    }
  });

  testWidgets('marks the current step for assistive technology', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpBreadcrumb(tester, current: 0);

    expect(
      tester.getSemantics(find.text('API type ›')),
      matchesSemantics(
        label: 'API type ›',
        isSelected: true,
        hasSelectedState: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('the last step is current without a trailing separator', (
    tester,
  ) async {
    await pumpBreadcrumb(tester, current: 5);

    expect(styleOf(tester, 'Review').fontWeight, FontWeight.w600);
    expect(styleOf(tester, 'Model ›').fontWeight, isNot(FontWeight.w600));
  });

  testWidgets('wraps onto the next line when the width is short', (
    tester,
  ) async {
    await pumpBreadcrumb(tester, current: 1, width: 200);

    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.text('API type ›'));
    final last = tester.getTopLeft(find.text('Review'));
    expect(last.dy, greaterThan(first.dy));
  });

  testWidgets('an empty list is empty and an out-of-range index marks none', (
    tester,
  ) async {
    await pumpBreadcrumb(tester, current: 0, steps: const []);
    expect(tester.takeException(), isNull);

    await pumpBreadcrumb(tester, current: 9);
    expect(tester.takeException(), isNull);
    expect(styleOf(tester, 'Review').fontWeight, isNot(FontWeight.w600));
  });
}
