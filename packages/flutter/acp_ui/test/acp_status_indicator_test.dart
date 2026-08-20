import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a status label', (tester) async {
    await tester.pumpWidget(
      const FluentApp(home: AcpStatusIndicator(label: 'Ready')),
    );

    expect(find.text('Ready'), findsOneWidget);
  });
}
