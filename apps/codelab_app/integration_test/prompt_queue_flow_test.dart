import 'dart:io';

import 'package:acp_testing/acp_testing.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/app/codelab_app_widget.dart';
import 'package:codelab_app/features/workbench/application/shell_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// See stdio_connect_flow_test.dart for why the connection setup dialog and
// the connect round trip need this specific choreography.
Future<void> _openConnectionSetupDialog(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('command-bar-configure-connection')),
  );
  await tester.pumpAndSettle();
}

Future<void> _closeConnectionSetupDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(Button, 'Close'));
  await tester.pumpAndSettle();
}

Future<void> _tapConnectAndWaitUntilSettled(
  WidgetTester tester,
  CodeLabShellCubit shellCubit,
) async {
  await tester.tap(find.widgetWithText(AcpButton, 'Connect').first);
  await tester.pump();
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (shellCubit.state.connectionStatus == AcpConnectionStatus.connecting &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a message submitted while the session is busy queues through the '
    'real composer, shows in the activity bar, and is delivered '
    'automatically once the block clears, against a real stdio process',
    (tester) async {
      await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
      await tester.pumpAndSettle();

      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_prompt_queue_e2e_',
      );
      addTearDown(() async {
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });
      final agent = await writeCodelabCompatibleStdioAgent(
        agentDirectory,
        mode: CodelabCompatibleStdioAgentMode.withQueuedPromptDrain,
      );

      const dartExecutable = String.fromEnvironment(
        'CODELAB_E2E_DART',
        defaultValue: 'dart',
      );

      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;

      await _openConnectionSetupDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Command')),
        dartExecutable,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Args')),
        '${agent.path} serve --stdio',
      );
      await _closeConnectionSetupDialog(tester);
      await _tapConnectAndWaitUntilSettled(tester, shellCubit);

      expect(find.text('Connected'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();

      const textBoxKey = ValueKey('composer-text-box');

      // An explicit tap-to-focus before `enterText` — a prior tap elsewhere
      // (or, here, the transcript/activity bar rebuilding as the approval
      // arrives) can leave focus off the composer, and `enterText` alone
      // does not reliably recover it for this custom fluent_ui `TextBox`;
      // without it, the field silently keeps its previous value and
      // nothing new gets typed. Same workaround as
      // plan_progress_checklist_flow_test.dart's `submitAndWait`.
      await tester.tap(find.byKey(textBoxKey));
      await tester.pump();
      await tester.enterText(find.byKey(textBoxKey), 'run a command');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();

      // The permission request arrives over a real stdio round trip — poll
      // the cubit's own state rather than relying on frame timing (same
      // pattern as permission_flow_test.dart).
      bool hasPendingApproval() => shellCubit.state.transcriptEntries.any(
        (entry) => entry.approval is AcpTranscriptApprovalPending,
      );
      final approvalDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (!hasPendingApproval() &&
          DateTime.now().isBefore(approvalDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Not `pumpAndSettle()`: the composer's send button is still showing
      // its loading spinner while the turn waits on this approval — an
      // indeterminate animation `pumpAndSettle` would wait on forever.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Allow once'), findsOneWidget);

      // The session is busy (turn running, approval pending) — submitting a
      // second message through the real composer must queue it instead of
      // attempting to send, per add-prompt-queue/design.md, Goals. This is
      // exactly the path acp_prompt_composer.dart's `isSubmitting` used to
      // block entirely (both the text field and the Send button were
      // disabled) — a real regression only an e2e test driving the actual
      // widget tree, not a unit test calling the cubit directly, could have
      // caught.
      await tester.tap(find.byKey(textBoxKey));
      await tester.pump();
      await tester.enterText(
        find.byKey(textBoxKey),
        'second message while busy',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();

      expect(shellCubit.state.queuedPrompts, hasLength(1));
      expect(
        shellCubit.state.queuedPrompts.single.content,
        'second message while busy',
      );
      expect(find.textContaining('Prompt failed'), findsNothing);

      // The Queue section is docked in the same activity bar as Plan,
      // collapsed by default — its header alone already confirms it
      // appeared, without needing to expand it.
      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('1 queued'), findsOneWidget);

      await tester.tap(find.text('Queue'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('second message while busy'), findsOneWidget);

      // Resolving the approval completes the first turn and, once it does,
      // auto-drains the queued message as a second real `session/prompt`
      // round trip — with no further action from the test beyond this tap.
      await tester.tap(find.text('Allow once'));
      await tester.pump();

      final turnDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (shellCubit.state.isPromptSubmitting &&
          DateTime.now().isBefore(turnDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(find.text('approved: allow_once'), findsWidgets);
      // The agent's reply to the *second*, auto-drained `session/prompt` —
      // proof the queued message was actually delivered, not just dropped
      // from the queue.
      expect(find.text('queued message delivered'), findsWidgets);
      expect(shellCubit.state.queuedPrompts, isEmpty);
      expect(find.text('Queue'), findsNothing);
      expect(find.byType(AcpActivityBar), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
