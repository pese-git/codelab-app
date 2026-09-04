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

/// Connects the real app to a real stdio agent of [mode], with the session's
/// working directory set to [workingDirectory] — shared choreography for
/// both tests below.
Future<CodeLabShellCubit> _connectAndCreateSession(
  WidgetTester tester, {
  required CodelabCompatibleStdioAgentMode mode,
  required String workingDirectory,
  required Directory agentDirectory,
}) async {
  await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
  await tester.pumpAndSettle();

  final agent = await writeCodelabCompatibleStdioAgent(
    agentDirectory,
    mode: mode,
  );

  // Unlike the other e2e tests, this one points the session's working
  // directory at a dedicated temp dir — which is also the agent process's
  // OS-level spawn cwd (`StdioAcpTransportConfig.cwd` → `Process.start
  // (workingDirectory: ...)`, see shell_cubit.dart `_stdioConfigFromState`).
  // The melos-provided `CODELAB_E2E_DART` is relative
  // (`../../.fvm/flutter_sdk/bin/dart`, resolved against `apps/codelab_app`
  // by the other tests, which never change the working directory) — resolve
  // it to an absolute path up front so it still finds `dart` once the spawn
  // cwd moves. A bare `dart` (the default, found via `PATH`) is left as-is.
  const rawDartExecutable = String.fromEnvironment(
    'CODELAB_E2E_DART',
    defaultValue: 'dart',
  );
  final dartExecutable = rawDartExecutable.contains('/')
      ? File(rawDartExecutable).absolute.path
      : rawDartExecutable;

  final shellCubit = codeLabDependenciesOf(
    tester.element(find.byType(CodeLabApp)),
  ).shellCubit;

  // "Working directory" is no longer a connection-dialog field — it is the
  // independently-selected "project" (add-open-project-picker), applied to
  // both the session's `cwd` and (by default, via
  // `runAgentFromProjectDirectory`) the stdio spawn cwd. Selecting it via
  // the cubit directly, rather than through the "Open Project" UI, mirrors
  // the other e2e tests here that also drive connection state via
  // `enterText` on the dialog's fields rather than pixel-perfect UI
  // interactions for every input.
  await shellCubit.selectProject(workingDirectory);

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

  return shellCubit;
}

Future<void> _sendPromptAndWaitForTurn(
  WidgetTester tester,
  CodeLabShellCubit shellCubit,
) async {
  await tester.enterText(
    find.byKey(const ValueKey('composer-text-box')),
    'access files in the working directory',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('composer-send-button')));
  await tester.pump();

  // The fs/* round trip happens over real stdio, entirely between the
  // client and agent processes — poll for turn completion rather than
  // relying on frame timing (same pattern as stdio_connect_flow_test.dart
  // and permission_flow_test.dart).
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
    'reads and writes real files in the session working directory via a '
    'real fs/read_text_file + fs/write_text_file round trip, with no '
    'approval step',
    (tester) async {
      final workDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_fs_e2e_work_',
      );
      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_fs_e2e_agent_',
      );
      addTearDown(() async {
        if (await workDirectory.exists()) {
          await workDirectory.delete(recursive: true);
        }
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });

      final inputFile = File('${workDirectory.path}/input.txt');
      await inputFile.writeAsString('hello from disk');

      final shellCubit = await _connectAndCreateSession(
        tester,
        mode: CodelabCompatibleStdioAgentMode.withFsAccess,
        workingDirectory: workDirectory.path,
        agentDirectory: agentDirectory,
      );

      await _sendPromptAndWaitForTurn(tester, shellCubit);

      // The agent read the real file through the client's real fs adapter
      // (IoTextFileIo, not a fake) and reported the content it saw back in
      // the transcript.
      expect(find.text('fs roundtrip complete: hello from disk'), findsWidgets);
      expect(shellCubit.state.isPromptSubmitting, isFalse);

      // The client wrote the derived file to real disk — no approval
      // dialog, no pending state, just the direct result of the protocol
      // round trip (add-acp-fs-client-support/design.md, Decision 1).
      final outputFile = File('${workDirectory.path}/output.txt');
      expect(await outputFile.exists(), isTrue);
      expect(await outputFile.readAsString(), 'echo: hello from disk');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'rejects an agent fs/read_text_file whose path escapes the session '
    'working directory, without ever touching the real filesystem there',
    (tester) async {
      final workDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_fs_e2e_work_',
      );
      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_fs_e2e_agent_',
      );
      addTearDown(() async {
        if (await workDirectory.exists()) {
          await workDirectory.delete(recursive: true);
        }
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });

      // The escape target the fake agent will try to read: a real file one
      // directory above the session's working directory, so a successful
      // (wrongly permitted) read would be observable.
      final escapeFile = File('${workDirectory.parent.path}/escape.txt');
      await escapeFile.writeAsString('should never be read');
      addTearDown(() async {
        if (await escapeFile.exists()) {
          await escapeFile.delete();
        }
      });

      final shellCubit = await _connectAndCreateSession(
        tester,
        mode: CodelabCompatibleStdioAgentMode.withFsPathEscape,
        workingDirectory: workDirectory.path,
        agentDirectory: agentDirectory,
      );

      await _sendPromptAndWaitForTurn(tester, shellCubit);

      // The client's real containment check rejected the request before
      // any infrastructure call — the escaped file's content never made it
      // back to the agent (and thus never into the transcript).
      expect(find.textContaining('fs/read_text_file rejected:'), findsWidgets);
      expect(find.textContaining('should never be read'), findsNothing);
      expect(shellCubit.state.isPromptSubmitting, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
