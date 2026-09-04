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
    'requests permission for a tool call and completes the turn once the '
    'user approves it, against a real stdio process',
    (tester) async {
      await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
      await tester.pumpAndSettle();

      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_permission_e2e_',
      );
      addTearDown(() async {
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });
      final agent = await writeCodelabCompatibleStdioAgent(
        agentDirectory,
        mode: CodelabCompatibleStdioAgentMode.withPermissionRequest,
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

      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'run the test command',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();

      // The permission request arrives over a real stdio round trip — poll
      // the cubit's own state rather than relying on frame timing (same
      // pattern as the prompt/config-option round trips in
      // stdio_connect_flow_test.dart).
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

      // The pending approval renders inline in the transcript (not a
      // separate panel) — see embed-approval-in-thread — with the tool
      // call's title, its risk, and all four standard option kinds each
      // bound to their own kind-based shortcut (add-approval-option-kinds).
      expect(find.text('Run test command'), findsWidgets);
      expect(find.text('Shell'), findsWidgets);
      expect(find.text('Allow once'), findsOneWidget);
      expect(find.text('Allow always'), findsOneWidget);
      expect(find.text('Reject once'), findsOneWidget);
      expect(find.text('Reject always'), findsOneWidget);

      // The extracted `command` is always visible in the approval details —
      // both in the transcript's inline panel and in the Inspector, which
      // mirrors tool call details independently.
      expect(find.text('echo hello'), findsWidgets);

      // The full raw-input JSON (identified here by the `shell` field, which
      // has no dedicated detail row) is always visible in the Inspector
      // (diagnosable-by-design) but collapsed by default in the transcript's
      // own approval panel (read on the golden path) — one match before
      // expanding it there, two once expanded.
      expect(find.text('View raw input'), findsOneWidget);
      expect(find.textContaining('/bin/bash'), findsOneWidget);
      await tester.tap(find.text('View raw input'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('/bin/bash'), findsNWidgets(2));

      await tester.tap(find.text('Allow once'));
      await tester.pump();

      // The agent's response to the permission choice, and the deferred
      // `session/prompt` completion, both arrive over the same real stdio
      // round trip.
      final turnDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (shellCubit.state.isPromptSubmitting &&
          DateTime.now().isBefore(turnDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(find.text('approved: allow_once'), findsWidgets);
      expect(shellCubit.state.isPromptSubmitting, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
