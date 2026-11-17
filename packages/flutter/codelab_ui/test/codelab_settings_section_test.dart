// Тесты `CodeLabSettingsSection` (задача 1.4 change `add-app-settings-shell`;
// D16): заголовок секции и столбец строк.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the title and the rows in order', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SingleChildScrollView(
          child: CodeLabSettingsSection(
            key: ValueKey('settings-section-behavior'),
            title: 'Behavior',
            children: [
              CodeLabSettingsRow(title: 'First'),
              CodeLabSettingsRow(title: 'Second'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Behavior'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-section-behavior')),
      findsOneWidget,
    );
    final first = tester.getTopLeft(find.text('First'));
    final second = tester.getTopLeft(find.text('Second'));
    expect(first.dy, lessThan(second.dy));
    expect(tester.getTopLeft(find.text('Behavior')).dy, lessThan(first.dy));
  });
}
