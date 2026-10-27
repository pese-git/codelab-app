import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/features/workbench/presentation/widgets/inspector_pane.dart';
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
      final launch = await E2eAgent.current.launch(
        agentDirectory,
        mode: CodelabCompatibleStdioAgentMode.withPermissionRequest,
      );

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
        (entry) => entry.approval is CodeLabTranscriptApprovalPending,
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
      // Варианты ищутся по ключу вида, а не по подписи: по ACP `name` —
      // свободный текст агента (у Dart-агента `Always allow <pattern>`,
      // у scripted-агента `Allow always`), смысл несёт `kind`.
      expect(find.text(launch.permissionTitle), findsWidgets);
      expect(find.text('Shell'), findsWidgets);
      for (final kind in CodeLabApprovalOptionKind.values) {
        expect(find.byKey(approvalOptionKey(kind)), findsOneWidget);
      }

      // The extracted `command` is always visible in the approval details —
      // both in the transcript's inline panel and in the Inspector, which
      // mirrors tool call details independently. Для Dart-агента это
      // проверка D-02: команда берётся из аргументов вызова `exec`.
      expect(find.text('echo hello'), findsWidgets);

      // The full raw-input JSON (identified here by `rawInputMarker` — the
      // scripted agent's `shell` field or the Dart agent's `timeout`, neither
      // of which has a dedicated detail row) is always visible in the Inspector
      // (diagnosable-by-design) but collapsed by default in the transcript's
      // own approval panel (read on the golden path).
      // Поиск ограничен панелями, а не общим числом совпадений: инспектор
      // показывает по карточке на каждый протокольный факт, и у Dart-агента,
      // который до `session/request_permission` шлёт `tool_call` с `rawInput`,
      // сырые аргументы есть в нескольких карточках, а у scripted-агента — в
      // одной.
      Finder rawInputIn(Type panel) => find.descendant(
        of: find.byType(panel),
        matching: find.textContaining(launch.rawInputMarker),
      );
      expect(find.text('View raw input'), findsOneWidget);
      // Записи протокола — в панели Protocol дока (change
      // `redesign-workbench-shell`, D5).
      shellCubit.togglePane(ToolPane.protocol);
      await tester.pumpAndSettle();
      expect(rawInputIn(WorkbenchInspectorPane), findsWidgets);
      expect(rawInputIn(CodeLabApprovalPanel), findsNothing);
      await tester.tap(find.text('View raw input'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(rawInputIn(CodeLabApprovalPanel), findsOneWidget);

      await tester.tap(
        find.byKey(approvalOptionKey(CodeLabApprovalOptionKind.allowOnce)),
      );
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
