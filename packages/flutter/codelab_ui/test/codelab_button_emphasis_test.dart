// `CodeLabButton` subtle и danger (change `add-provider-setup-ui`, артборд
// `Providers`: кнопки Check/Edit/Remove в заголовке Expander — `f-btn subtle`,
// Remove — `subtle danger`): без рамки, нажатие работает, отключённая не
// нажимается.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final emphasis in [
    CodeLabButtonEmphasis.subtle,
    CodeLabButtonEmphasis.danger,
  ]) {
    testWidgets('${emphasis.name} shows its label and reports a tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        FluentApp(
          home: Center(
            child: CodeLabButton(
              label: 'Remove',
              emphasis: emphasis,
              onPressed: () => taps++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('${emphasis.name} is inert without a handler', (tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: Center(
            child: CodeLabButton(
              label: 'Remove',
              emphasis: emphasis,
              onPressed: null,
            ),
          ),
        ),
      );

      expect(tester.widget<Button>(find.byType(Button)).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
