import 'dart:io';

import 'package:acp_testing/acp_testing.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/app/codelab_app_widget.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports missing stdio command without crashing', (tester) async {
    await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Command')),
      '',
    );
    await tester.tap(find.widgetWithText(AcpButton, 'Connect').first);
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsWidgets);
    expect(
      find.text('Stdio command is required before connecting.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await closeCodeLabRootScope();
  });

  testWidgets('connects to a codelab-compatible stdio agent', (tester) async {
    await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
    await tester.pumpAndSettle();

    final agentDirectory = await Directory.systemTemp.createTemp(
      'codelab_app_stdio_e2e_',
    );
    addTearDown(() async {
      if (await agentDirectory.exists()) {
        await agentDirectory.delete(recursive: true);
      }
    });
    final agent = await writeCodelabCompatibleStdioAgent(agentDirectory);

    const dartExecutable = String.fromEnvironment(
      'CODELAB_E2E_DART',
      defaultValue: 'dart',
    );

    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Command')),
      dartExecutable,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Args')),
      '${agent.path} serve --stdio',
    );
    await tester.tap(find.widgetWithText(AcpButton, 'Connect').first);
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsWidgets);
    final diagnostics = codeLabDependenciesOf(
      tester.element(find.byType(CodeLabApp)),
    ).shellCubit.state.diagnostics.map((entry) => entry.message);
    expect(diagnostics, contains(contains('Starting stdio ACP agent:')));
    expect(diagnostics, contains(contains('Stdio ACP agent started:')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await closeCodeLabRootScope();
  });
}
