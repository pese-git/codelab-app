import 'dart:io';

import 'package:acp_testing/acp_testing.dart';
import 'package:acp_ui/acp_ui.dart';
import 'package:codelab_app/app/app_scope.dart';
import 'package:codelab_app/app/codelab_app_widget.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Command')),
      dartExecutable,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transport-field-Args')),
      '${agent.path} serve --stdio',
    );
    await tester.tap(find.widgetWithText(AcpButton, 'Connect').first);
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsWidgets);
    final diagnostics = codeLabDependenciesOf(
      tester.element(find.byType(CodeLabApp)),
    ).shellCubit.state.diagnostics.map((entry) => entry.message);
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

      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Command')),
        dartExecutable,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Args')),
        '${agent.path} serve --stdio',
      );
      await tester.tap(find.widgetWithText(AcpButton, 'Connect').first);
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();

      expect(find.text('Session codelab-test-session'), findsWidgets);

      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;

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

      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Command')),
        dartExecutable,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transport-field-Args')),
        '${agent.path} serve --stdio',
      );
      await tester.tap(find.widgetWithText(AcpButton, 'Connect').first);
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();

      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;

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
}
