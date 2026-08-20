import 'package:codelab_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the desktop workbench shell', (tester) async {
    await tester.pumpWidget(const CodeLabApp());

    expect(find.text('Agent Workbench'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
  });
}
