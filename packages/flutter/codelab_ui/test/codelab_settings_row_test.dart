// Тесты `CodeLabSettingsRow` (задача 1.4 change `add-app-settings-shell`;
// D16): заголовок, описание, `trailing`, ключ теста.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpRow(WidgetTester tester, Widget row) => tester.pumpWidget(
    FluentApp(
      home: Center(child: SizedBox(width: 600, child: row)),
    ),
  );

  testWidgets('shows title, description and the trailing control', (
    tester,
  ) async {
    var toggled = false;
    await pumpRow(
      tester,
      CodeLabSettingsRow(
        title: 'Connect on start',
        description: 'Connect to the default profile when CodeLab opens.',
        trailing: ToggleSwitch(checked: toggled, onChanged: (v) => toggled = v),
      ),
    );

    expect(find.text('Connect on start'), findsOneWidget);
    expect(
      find.text('Connect to the default profile when CodeLab opens.'),
      findsOneWidget,
    );
    expect(find.byType(ToggleSwitch), findsOneWidget);
  });

  testWidgets('works without a description or trailing control', (
    tester,
  ) async {
    await pumpRow(tester, const CodeLabSettingsRow(title: 'Only title'));

    expect(find.text('Only title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the test key passed by the owner', (tester) async {
    await pumpRow(
      tester,
      const CodeLabSettingsRow(
        key: ValueKey('settings-row-demo'),
        title: 'Keyed',
      ),
    );

    expect(find.byKey(const ValueKey('settings-row-demo')), findsOneWidget);
  });

  testWidgets('a wide fixed trailing shrinks on a narrow row and the title '
      'stays on one line', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 368,
            child: CodeLabSettingsRow(
              title: 'Default model',
              description: 'Used by new sessions.',
              leading: FluentIcons.settings,
              trailing: SizedBox(
                key: ValueKey('wide-trailing'),
                width: 260,
                child: Text('control'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Default model')).height, lessThan(24));
    expect(
      tester.getSize(find.byKey(const ValueKey('wide-trailing'))).width,
      lessThan(260),
    );
  });

  testWidgets('on a wide row the trailing keeps its own width', (tester) async {
    await pumpRow(
      tester,
      const CodeLabSettingsRow(
        title: 'Default model',
        trailing: SizedBox(
          key: ValueKey('wide-trailing'),
          width: 260,
          child: Text('control'),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('wide-trailing'))).width,
      260,
    );
  });
}
