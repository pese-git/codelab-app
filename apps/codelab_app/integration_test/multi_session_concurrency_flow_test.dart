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
    'a second session accepts and completes a prompt immediately while the '
    'first session is still hung on a pending approval, against a real '
    'stdio process',
    (tester) async {
      await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
      await tester.pumpAndSettle();

      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_multi_session_e2e_',
      );
      addTearDown(() async {
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });
      final agent = await writeCodelabCompatibleStdioAgent(
        agentDirectory,
        mode: CodelabCompatibleStdioAgentMode.withConcurrentSessions,
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

      // Session A — created first, so the test agent hangs its prompt turn
      // on a `session/request_permission` round trip (see
      // codelab_compatible_stdio_agent.dart's `with_concurrent_sessions`
      // mode).
      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();
      final sessionAId = shellCubit.state.activeSessionId!;

      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'run the test command',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();

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
      expect(hasPendingApproval(), isTrue);
      expect(shellCubit.state.isPromptSubmitting, isTrue);

      // Session B — created afterward, while A's turn is still hanging in
      // the background. The composer must reflect B's own free state right
      // away, not A's busy one.
      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();
      final sessionBId = shellCubit.state.activeSessionId!;
      expect(sessionBId, isNot(sessionAId));
      expect(shellCubit.state.isPromptSubmitting, isFalse);

      // Session B's composer is a freshly (re)mounted widget instance — its
      // text field needs an explicit tap-to-focus before `enterText`, unlike
      // session A's, which already had focus as the first field on screen.
      await tester.tap(find.byKey(const ValueKey('composer-text-box')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'hello from B',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();

      // A real, independent second `session/prompt` round trip — the test
      // agent answers it immediately since B is not the first session (see
      // `with_concurrent_sessions` mode), regardless of A's still-pending
      // permission request on the same process.
      final bDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (shellCubit.state.isPromptSubmitting &&
          DateTime.now().isBefore(bDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(shellCubit.state.activeSessionId, sessionBId);
      expect(shellCubit.state.isPromptSubmitting, isFalse);
      expect(find.text('hello from $sessionBId'), findsWidgets);

      // A stays visible in the sidebar as awaiting approval, live, purely in
      // the background — the user never switched to it to see this update.
      AcpSessionStatus statusOf(String sessionId) => shellCubit.state.sessions
          .firstWhere((item) => item.id == sessionId)
          .status;
      expect(statusOf(sessionAId), AcpSessionStatus.awaitingApproval);

      // Switch back to A, through the real sidebar, and resolve its pending
      // approval — its transcript reflects the resolution correctly even
      // though the whole wait happened while B was active.
      await tester.tap(find.text('Session $sessionAId'));
      await tester.pumpAndSettle();
      expect(shellCubit.state.activeSessionId, sessionAId);
      expect(hasPendingApproval(), isTrue);

      await tester.tap(find.text('Allow once'));
      await tester.pump();

      final aDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (shellCubit.state.isPromptSubmitting &&
          DateTime.now().isBefore(aDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(find.text('approved: allow_once'), findsWidgets);
      expect(shellCubit.state.isPromptSubmitting, isFalse);
      expect(statusOf(sessionAId), AcpSessionStatus.idle);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
