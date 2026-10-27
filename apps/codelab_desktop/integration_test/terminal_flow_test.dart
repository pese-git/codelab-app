import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

// See stdio_connect_flow_test.dart for why the connection setup dialog and
// the connect round trip need this specific choreography.
Future<void> _openConnectionSetupDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
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
  await tester.tap(find.widgetWithText(CodeLabButton, 'Connect').first);
  await tester.pump();
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (shellCubit.state.connectionStatus ==
          CodeLabConnectionStatus.connecting &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

/// Connects the real app to a real stdio agent of [mode] and creates a
/// session — shared choreography for all tests below.
Future<CodeLabShellCubit> _connectAndCreateSession(
  WidgetTester tester, {
  required CodelabCompatibleStdioAgentMode mode,
  required Directory agentDirectory,
}) async {
  await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
  await tester.pumpAndSettle();

  final launch = await E2eAgent.current.launch(agentDirectory, mode: mode);

  final shellCubit = codeLabDependenciesOf(
    tester.element(find.byType(CodeLabApp)),
  ).shellCubit;

  await _openConnectionSetupDialog(tester);
  await tester.enterText(
    find.byKey(const ValueKey('transport-field-Command')),
    launch.command,
  );
  await tester.enterText(
    find.byKey(const ValueKey('transport-field-Args')),
    launch.args,
  );
  await _closeConnectionSetupDialog(tester);
  await _tapConnectAndWaitUntilSettled(tester, shellCubit);

  expect(find.text('Connected'), findsWidgets);

  await tester.tap(find.byKey(const ValueKey('new-session-button')));
  await tester.pumpAndSettle();

  return shellCubit;
}

Future<void> _sendPromptAndWaitForTurn(
  WidgetTester tester,
  CodeLabShellCubit shellCubit,
) async {
  await tester.enterText(
    find.byKey(const ValueKey('composer-text-box')),
    'run the command',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('composer-send-button')));
  await tester.pump();

  // The terminal/* round trip happens over real stdio, entirely between the
  // client and agent processes — poll for turn completion rather than
  // relying on frame timing (same pattern as the other e2e suites here).
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (shellCubit.state.isPromptSubmitting &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'terminal/create runs a real command and the agent observes its real '
    'output and exit code',
    (tester) async {
      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_terminal_e2e_',
      );
      addTearDown(() async {
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });

      final shellCubit = await _connectAndCreateSession(
        tester,
        mode: CodelabCompatibleStdioAgentMode.withTerminalExecution,
        agentDirectory: agentDirectory,
      );

      await _sendPromptAndWaitForTurn(tester, shellCubit);

      // The agent ran `sh -c 'echo hello-from-terminal; exit 3'` through the
      // real IoTerminalProcessRunner (a real child process, not a fake) and
      // reported the real captured stdout + exit code back in the
      // transcript.
      expect(
        find.textContaining('terminal output: hello-from-terminal'),
        findsWidgets,
      );
      expect(find.textContaining('exitCode: 3'), findsWidgets);
      expect(shellCubit.state.isPromptSubmitting, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'terminal/create with a cwd outside the working directory is rejected '
    'before starting a process',
    (tester) async {
      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_terminal_e2e_',
      );
      addTearDown(() async {
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });

      final shellCubit = await _connectAndCreateSession(
        tester,
        mode: CodelabCompatibleStdioAgentMode.withTerminalPathEscape,
        agentDirectory: agentDirectory,
      );

      await _sendPromptAndWaitForTurn(tester, shellCubit);

      // The client's real working-directory containment check rejected the
      // request before any process was ever spawned.
      expect(find.textContaining('terminal/create rejected:'), findsWidgets);
      expect(shellCubit.state.isPromptSubmitting, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
    tags: scriptedOnly,
  );

  testWidgets('terminal/kill terminates a real long-running process without '
      'releasing its terminalId', (tester) async {
    final agentDirectory = await Directory.systemTemp.createTemp(
      'codelab_app_terminal_e2e_',
    );
    addTearDown(() async {
      if (await agentDirectory.exists()) {
        await agentDirectory.delete(recursive: true);
      }
    });

    final shellCubit = await _connectAndCreateSession(
      tester,
      mode: CodelabCompatibleStdioAgentMode.withTerminalKill,
      agentDirectory: agentDirectory,
    );

    await _sendPromptAndWaitForTurn(tester, shellCubit);

    // The agent started a real `sleep 30`, killed it via terminal/kill,
    // then successfully called terminal/output with the SAME terminalId
    // — proving the real IoTerminalProcessRunner did not release it, and
    // that the real OS process was actually terminated (signal SIGKILL/
    // SIGTERM shows up in the reported exit status).
    expect(find.textContaining('terminal output:'), findsWidgets);
    expect(find.textContaining('SIGTERM'), findsWidgets);
    expect(shellCubit.state.isPromptSubmitting, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await closeCodeLabRootScope();
  }, tags: scriptedOnly);
}
