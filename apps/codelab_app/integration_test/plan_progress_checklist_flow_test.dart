import 'dart:io';

import 'package:acp_testing/acp_testing.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/app/codelab_app_widget.dart';
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
    "a real agent's plan updates dock the activity bar, support expand and "
    'dismiss, and hide it entirely once every entry is completed',
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
        mode: CodelabCompatibleStdioAgentMode.withPlan,
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

      Future<void> submitAndWait(String text) async {
        final textBoxKey = const ValueKey('composer-text-box');
        // An explicit tap-to-focus before `enterText` — a prior tap
        // elsewhere (expanding/dismissing the plan section) can leave focus
        // off the composer, and `enterText` alone does not reliably recover
        // it for this custom fluent_ui `TextBox`; without it, the field
        // silently keeps its previous value and nothing new gets typed.
        await tester.tap(find.byKey(textBoxKey));
        await tester.pump();
        await tester.enterText(find.byKey(textBoxKey), text);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('composer-send-button')));
        await tester.pump();

        // The plan update, like the agent's reply, arrives over a real
        // stdio round trip — poll the cubit's own state rather than relying
        // on `pumpAndSettle` to wait for it (see stdio_connect_flow_test.dart
        // for the same rationale).
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (shellCubit.state.isPromptSubmitting &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      await submitAndWait('start working on the plan');

      // Compact summary names the real in-progress entry from the agent's
      // plan update, plus the remaining pending count. The entry's own text
      // also shows up a second time in the inspector's raw protocol log
      // (same `plan` update, rendered independently there) — `findsWidgets`
      // where the assertion is about content that log duplicates; the
      // labels/badges below are this feature's own presentation text, not
      // mirrored by the inspector, so those stay `findsOneWidget`.
      expect(find.text('Current:'), findsOneWidget);
      expect(
        find.text('Run melos analyze to confirm no new lint issues'),
        findsWidgets,
      );
      expect(find.text('1 left'), findsOneWidget);
      expect(shellCubit.state.currentPlan, hasLength(3));

      await tester.tap(find.text('Current:'));
      await tester.pumpAndSettle();

      // Expanded: aggregate count, every entry, priority badges.
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Open PR for review'), findsWidgets);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear plan'));
      await tester.pumpAndSettle();

      expect(shellCubit.state.currentPlan, isNull);
      // The activity bar itself is gone — the authoritative "dismissed"
      // check; the inspector's historical protocol log is untouched by
      // `dismissPlan()` (by design — it's a log, not live state) and would
      // still show "Open PR for review" as a past `plan` update's value, so
      // asserting that text's absence here would be a false failure.
      expect(find.byType(AcpActivityBar), findsNothing);

      await submitAndWait('keep going');

      // A later plan update from the same real agent process repopulates
      // the section after it was dismissed — dismissing does not suppress
      // future updates.
      expect(find.text('Current:'), findsOneWidget);
      expect(shellCubit.state.currentPlan, hasLength(3));

      await submitAndWait('finish the plan');

      // Every entry completed — the whole activity bar disappears, not
      // just its label (see design.md: no Zed-style "All Done" state).
      expect(find.byType(AcpActivityBar), findsNothing);
      expect(find.text('Current:'), findsNothing);
      expect(
        shellCubit.state.currentPlan?.every(
          (entry) => entry.status == AcpPlanEntryStatus.completed,
        ),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
