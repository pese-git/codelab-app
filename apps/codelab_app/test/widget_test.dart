import 'package:codelab_app/main.dart';
import 'package:codelab_app/src/app_scope.dart';
import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_scope.dart';

void main() {
  testWidgets('renders the desktop workbench shell', (tester) async {
    final binding = CodeLabTestBinding();
    final scope = binding.scope;

    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));

    expect(find.text('Agent Workbench'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
    expect(
      scope.resolve<CodeLabTransportFactory>(),
      isA<CodeLabTransportFactory>(),
    );
    expect(scope.resolve<StdioAcpAgentProfile>(), codelabAgentStdioProfile);
    expect(scope.resolve<AcpClientApplication>(), isA<AcpClientApplication>());
    expect(scope.resolve<AcpTransport>(), same(binding.transport));
    expect(scope.resolve<CodeLabRootLifecycle>(), isA<CodeLabRootLifecycle>());
    expect(
      codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).application,
      same(scope.resolve<AcpClientApplication>()),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });
}
