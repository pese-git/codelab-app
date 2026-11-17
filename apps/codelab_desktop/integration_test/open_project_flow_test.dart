import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/core/platform/shared_preferences_recent_projects_store.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart'
    show projectNameOf;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

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

      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();

      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_stdio_e2e_',
      );
      addTearDown(() async {
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });
      final launch = await E2eAgent.current.launch(
        agentDirectory,
        mode: CodelabCompatibleStdioAgentMode.echoesCwd,
      );

      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;

      await launch.connect(tester, shellCubit);

      expect(find.text('Connected'), findsWidgets);

      // Недавний проект — свёрнутая группа сайдбара; её выбор переключает
      // проект (change `redesign-workbench-shell`, D4).
      final recentEntryKey = CodeLabSessionSidebar.projectKey(
        projectNameOf(projectDirectory.path),
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
    'recently opened projects and the selected project persist across a '
    'restart',
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

      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();

      // Недавний проект — свёрнутая группа сайдбара; её выбор переключает
      // проект (change `redesign-workbench-shell`, D4).
      final recentEntryKey = CodeLabSessionSidebar.projectKey(
        projectNameOf(projectDirectory.path),
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

      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();

      final restartedShellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      // Выбранный проект восстанавливается из снимка рабочего пространства
      // (spec agent-workbench-ui «Workbench restores sessions after reconnect
      // and restart»; design D6 change `add-session-list-and-reload`).
      // Раньше он не сохранялся — это было вне рамок add-open-project-picker.
      await tester.pumpAndSettle();
      expect(
        restartedShellCubit.state.selectedProjectPath,
        projectDirectory.path,
      );

      expect(find.byKey(recentEntryKey), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
