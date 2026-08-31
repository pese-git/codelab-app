import 'dart:io';

import 'package:acp_testing/acp_testing.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/app/codelab_app_widget.dart';
import 'package:codelab_app/features/workbench/application/shell_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// The stdio connect round trip spawns a real child process and waits for a
// real `initialize` response — this can take longer than a single
// `pumpAndSettle` reliably waits for. Poll the cubit's own state instead of
// relying on frame timing (same pattern used below for prompt/config-option
// round trips).
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

    final shellCubit = codeLabDependenciesOf(
      tester.element(find.byType(CodeLabApp)),
    ).shellCubit;

    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Command')),
      dartExecutable,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Args')),
      '${agent.path} serve --stdio',
    );
    await _tapConnectAndWaitUntilSettled(tester, shellCubit);

    expect(find.text('Connected'), findsWidgets);
    final diagnostics = shellCubit.state.diagnostics.map(
      (entry) => entry.message,
    );
    expect(diagnostics, contains(contains('Starting stdio ACP agent:')));
    expect(diagnostics, contains(contains('Stdio ACP agent started:')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await closeCodeLabRootScope();
  });

  testWidgets(
    'creates a session and completes a prompt turn against a real stdio '
    'process',
    (tester) async {
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

      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;

      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Command')),
        dartExecutable,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Args')),
        '${agent.path} serve --stdio',
      );
      await _tapConnectAndWaitUntilSettled(tester, shellCubit);

      expect(find.text('Connected'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();

      expect(find.text('Session codelab-test-session'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'hello from the e2e test',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();

      // The agent reply arrives over a real stdio round trip, which does not
      // reliably keep scheduling widget frames for `pumpAndSettle` to wait
      // on — poll the cubit's own state instead of relying on frame timing.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (shellCubit.state.isPromptSubmitting &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(find.text('hello from the e2e test'), findsWidgets);
      expect(find.text('hello from compatible stdio agent'), findsWidgets);
      expect(shellCubit.state.isPromptSubmitting, isFalse);
      expect(shellCubit.state.canCancel, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'selects a session config option value against a real stdio process',
    (tester) async {
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
      final agent = await writeCodelabCompatibleStdioAgent(
        agentDirectory,
        mode: CodelabCompatibleStdioAgentMode.withConfigOptions,
      );

      const dartExecutable = String.fromEnvironment(
        'CODELAB_E2E_DART',
        defaultValue: 'dart',
      );

      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;

      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Command')),
        dartExecutable,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Args')),
        '${agent.path} serve --stdio',
      );
      await _tapConnectAndWaitUntilSettled(tester, shellCubit);

      expect(find.text('Connected'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();

      // The fake agent declares a `model` config option (`gpt-5`/`gpt-4`) in
      // its `session/new` response — see
      // codelab_compatible_stdio_agent.dart.
      expect(
        find.byKey(const ValueKey('composer-config-option-model')),
        findsOneWidget,
      );
      expect(find.text('GPT-5'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('composer-config-option-model')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('GPT-4'));
      await tester.pump();

      // The response comes back over a real stdio round trip — poll the
      // cubit's own state rather than relying on `pumpAndSettle` to wait for
      // it (see the prompt-flow test above for why).
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (shellCubit.state.isRespondingToConfigOption &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(shellCubit.state.configOptions.single.currentValue, 'gpt-4');
      expect(shellCubit.state.isRespondingToConfigOption, isFalse);
      expect(find.text('GPT-4'), findsOneWidget);
      expect(find.text('GPT-5'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'a real stdio agent process dying mid-turn is reflected as a failed '
    'connection, not a stuck Connected/running UI',
    (tester) async {
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
      final agent = await writeCodelabCompatibleStdioAgent(
        agentDirectory,
        mode: CodelabCompatibleStdioAgentMode.crashMidPrompt,
      );

      const dartExecutable = String.fromEnvironment(
        'CODELAB_E2E_DART',
        defaultValue: 'dart',
      );

      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;

      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Command')),
        dartExecutable,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Args')),
        '${agent.path} serve --stdio',
      );
      await _tapConnectAndWaitUntilSettled(tester, shellCubit);

      expect(find.text('Connected'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'this turn will never get a reply',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();

      // The fake agent exits the moment it receives `session/prompt` — a
      // real process death, not a simulated transport event — so the real
      // `StdioAcpTransport` has to detect it via the child process's actual
      // exit code, exactly as it would for a genuinely crashed agent. Since
      // this agent process is already running (connected earlier in this
      // test), the crash-and-detect round trip can complete within a single
      // pump, so unlike the connect step above there is no reliable
      // intermediate "submitting" moment to assert on here — the equivalent
      // synchronous transition is already covered at the unit level in
      // widget_test.dart. Poll straight for the settled failed state.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (shellCubit.state.connectionStatus != AcpConnectionStatus.failed &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(shellCubit.state.connectionStatus, AcpConnectionStatus.failed);
      expect(shellCubit.state.isPromptSubmitting, isFalse);
      expect(shellCubit.state.canCancel, isFalse);
      expect(shellCubit.state.pendingApproval, isNull);
      expect(find.text('Failed'), findsWidgets);
      // The transcript up to the point of the crash is history, not part of
      // the now-untrustworthy active request — it must stay visible.
      expect(find.text('this turn will never get a reply'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
