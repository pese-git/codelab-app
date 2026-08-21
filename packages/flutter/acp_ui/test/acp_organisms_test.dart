import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports organisms through the public package API', () {
    expect(AcpApprovalPanel, isA<Type>());
    expect(AcpApprovalRisk.shell, isA<AcpApprovalRisk>());
    expect(AcpTranscriptEntry, isA<Type>());
    expect(AcpTranscriptEntryKind.toolCall, isA<AcpTranscriptEntryKind>());
    expect(AcpTranscriptPanel, isA<Type>());
  });

  testWidgets('renders transcript entries and embedded tool summaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 600,
          height: 360,
          child: AcpTranscriptPanel(
            entries: [
              AcpTranscriptEntry(
                id: 'user-1',
                kind: AcpTranscriptEntryKind.user,
                title: 'You',
                body: 'Check the UI package.',
                timestampLabel: '12:30',
              ),
              AcpTranscriptEntry(
                id: 'tool-1',
                kind: AcpTranscriptEntryKind.toolCall,
                title: 'Tool call',
                toolCall: AcpToolCallSummary(
                  name: 'shell',
                  target: 'fvm flutter test',
                  status: AcpToolCallStatus.succeeded,
                  detail: 'all tests passed',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('You'), findsOneWidget);
    expect(find.text('Check the UI package.'), findsOneWidget);
    expect(find.text('12:30'), findsOneWidget);
    expect(find.text('Tool call'), findsOneWidget);
    expect(find.text('shell - fvm flutter test'), findsOneWidget);
    expect(find.text('all tests passed'), findsOneWidget);
  });

  testWidgets('renders transcript empty state', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: SizedBox(
          width: 320,
          height: 220,
          child: AcpTranscriptPanel(entries: []),
        ),
      ),
    );

    expect(find.text('No transcript yet'), findsOneWidget);
  });

  testWidgets('renders approval risk details and selects option', (
    tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      FluentApp(
        home: AcpApprovalPanel(
          title: 'Run shell command',
          risk: AcpApprovalRisk.shell,
          reason: 'Needed to verify workspace health.',
          command: 'fvm dart analyze',
          cwd: '/repo',
          diffSummary: 'No file edits',
          selectedOptionId: 'allow_once',
          onOptionSelected: (optionId) => selected = optionId,
          options: const [
            AcpApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              description: 'Run once.',
              tone: AcpTone.warning,
            ),
            AcpApprovalOption(
              id: 'reject',
              label: 'Reject',
              description: 'Deny.',
              tone: AcpTone.danger,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Run shell command'), findsOneWidget);
    expect(find.text('Shell'), findsOneWidget);
    expect(find.text('Needed to verify workspace health.'), findsOneWidget);
    expect(find.text('fvm dart analyze'), findsOneWidget);
    expect(find.text('/repo'), findsOneWidget);
    expect(find.text('No file edits'), findsOneWidget);

    await tester.tap(find.text('Reject'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected, 'reject');
  });
}
