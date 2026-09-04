import 'dart:io';

import 'package:acp_testing/acp_testing.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/app/codelab_app_widget.dart';
import 'package:codelab_app/core/platform/shared_preferences_recent_projects_store.dart';
import 'package:codelab_app/features/workbench/application/shell_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// The transport setup form only lives inside the modal ConnectionSetupDialog
// — see stdio_connect_flow_test.dart for the same helper.
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

// Same rationale as stdio_connect_flow_test.dart's helper of the same name:
// a real stdio round trip does not reliably keep scheduling frames for
// `pumpAndSettle` to wait on, so poll the cubit's own state instead.
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
    'selecting a recent project from Open Project applies it as cwd for a '
    'real stdio session',
    (tester) async {
      final projectDirectory = await Directory.systemTemp.createTemp(
        'codelab_open_project_e2e_',
      );
      addTearDown(() async {
        if (await projectDirectory.exists()) {
          await projectDirectory.delete(recursive: true);
        }
      });
      // Seeds recents the way a prior "Browse for folder…" selection would
      // have — the native OS folder dialog itself cannot be driven from a
      // headless integration test, so this is the closest automatable
      // stand-in for "the user already has this project in their recents".
      await const SharedPreferencesRecentProjectsStore().record(
        projectDirectory.path,
      );

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
        mode: CodelabCompatibleStdioAgentMode.echoesCwd,
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

      await tester.tap(find.byKey(const ValueKey('open-project-picker')));
      await tester.pumpAndSettle();

      final recentEntryKey = ValueKey(
        'open-project-recent-${projectDirectory.path}',
      );
      expect(find.byKey(recentEntryKey), findsOneWidget);
      await tester.tap(find.byKey(recentEntryKey));
      await tester.pumpAndSettle();

      expect(shellCubit.state.selectedProjectPath, projectDirectory.path);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();

      expect(shellCubit.state.currentSessionDetail, projectDirectory.path);

      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'where am I',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (shellCubit.state.isPromptSubmitting &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      // The message text comes from the real agent process, over a real
      // stdio round trip — proves the selected project's path genuinely
      // reached `session/new`'s `cwd` as the agent received it, not just
      // the client's own echo of what it believes it sent (see
      // codelab_compatible_stdio_agent.dart's `echoesCwd` mode).
      expect(find.text('cwd was: ${projectDirectory.path}'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'recently opened projects persist across a restart, without carrying '
    'over the previously selected project',
    (tester) async {
      final projectDirectory = await Directory.systemTemp.createTemp(
        'codelab_open_project_restart_e2e_',
      );
      addTearDown(() async {
        if (await projectDirectory.exists()) {
          await projectDirectory.delete(recursive: true);
        }
      });
      await const SharedPreferencesRecentProjectsStore().record(
        projectDirectory.path,
      );

      await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-project-picker')));
      await tester.pumpAndSettle();

      final recentEntryKey = ValueKey(
        'open-project-recent-${projectDirectory.path}',
      );
      expect(find.byKey(recentEntryKey), findsOneWidget);
      await tester.tap(find.byKey(recentEntryKey));
      await tester.pumpAndSettle();

      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      expect(shellCubit.state.selectedProjectPath, projectDirectory.path);

      // Tear down and rebuild the composition root — the closest a single
      // `flutter test` process can get to a real app restart, and enough to
      // exercise the actual mechanism under test: `SharedPreferences` data
      // outliving one `Scope`'s lifetime (see
      // add-open-project-picker/design.md, Decision 4).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();

      await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
      await tester.pumpAndSettle();

      final restartedShellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      // The selected project itself is session-scoped app state, not
      // persisted — only the recents list survives (design.md, Risks).
      expect(restartedShellCubit.state.selectedProjectPath, isNull);

      await tester.tap(find.byKey(const ValueKey('open-project-picker')));
      await tester.pumpAndSettle();

      expect(find.byKey(recentEntryKey), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
