import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports molecules through the public package API', () {
    expect(AcpApprovalOption, isA<Type>());
    expect(AcpApprovalOptionGroup, isA<Type>());
    expect(AcpConnectionStatus.connected, isA<AcpConnectionStatus>());
    expect(AcpConnectionStatusRow, isA<Type>());
    expect(AcpPromptComposer, isA<Type>());
    expect(AcpToolCallStatus.running, isA<AcpToolCallStatus>());
    expect(AcpToolCallSummary, isA<Type>());
  });

  testWidgets('submits prompt text and clears the composer', (tester) async {
    String? submittedPrompt;

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          initialPrompt: '  inspect protocol logs  ',
          onSubmit: (prompt) => submittedPrompt = prompt,
        ),
      ),
    );

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(submittedPrompt, 'inspect protocol logs');
    expect(find.text('inspect protocol logs'), findsNothing);
  });

  testWidgets('disables submit while prompt is empty or submitting', (
    tester,
  ) async {
    var submitted = false;

    await tester.pumpWidget(
      FluentApp(home: AcpPromptComposer(onSubmit: (_) => submitted = true)),
    );

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(submitted, isFalse);

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          initialPrompt: 'run',
          isSubmitting: true,
          onSubmit: (_) => submitted = true,
        ),
      ),
    );

    expect(find.byType(ProgressRing), findsOneWidget);
  });

  testWidgets('invokes cancel callback when cancel is available', (
    tester,
  ) async {
    var cancelled = false;

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          initialPrompt: 'long task',
          canCancel: true,
          onSubmit: (_) {},
          onCancel: () => cancelled = true,
        ),
      ),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(cancelled, isTrue);
  });

  testWidgets('renders compact tool call status details', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: AcpToolCallSummary(
          name: 'edit',
          target: 'lib/main.dart',
          status: AcpToolCallStatus.failed,
          detail: 'permission denied',
        ),
      ),
    );

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('edit - lib/main.dart'), findsOneWidget);
    expect(find.text('permission denied'), findsOneWidget);
  });

  testWidgets('renders connection status with transport and profile labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: AcpConnectionStatusRow(
          status: AcpConnectionStatus.connected,
          transportLabel: 'stdio',
          profileLabel: 'Codelab Agent',
          detail: 'ready',
        ),
      ),
    );

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('stdio'), findsOneWidget);
    expect(find.text('Codelab Agent'), findsOneWidget);
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('selects approval option by id', (tester) async {
    String? selected;

    await tester.pumpWidget(
      FluentApp(
        home: AcpApprovalOptionGroup(
          selectedOptionId: 'allow_once',
          onSelected: (optionId) => selected = optionId,
          options: const [
            AcpApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              description: 'Run once for this prompt turn.',
              tone: AcpTone.warning,
            ),
            AcpApprovalOption(
              id: 'reject',
              label: 'Reject',
              description: 'Deny the request.',
              tone: AcpTone.danger,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Reject'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected, 'reject');
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Risk'), findsOneWidget);
  });
}
