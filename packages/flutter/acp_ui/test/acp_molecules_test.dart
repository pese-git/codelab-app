import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports molecules through the public package API', () {
    expect(AcpApprovalOption, isA<Type>());
    expect(AcpApprovalOptionGroup, isA<Type>());
    expect(AcpCommandAction, isA<Type>());
    expect(AcpConnectionStatus.connected, isA<AcpConnectionStatus>());
    expect(AcpConnectionStatusRow, isA<Type>());
    expect(AcpPromptComposer, isA<Type>());
    expect(AcpToolCallStatus.running, isA<AcpToolCallStatus>());
    expect(AcpToolCallSummary, isA<Type>());
    expect(AcpViewMode.normal, isA<AcpViewMode>());
  });

  test('filters command actions by slash command, label, and description', () {
    expect(AcpCommandAction.defaults, hasLength(6));
    expect(
      AcpCommandAction.defaults.map((action) => action.slashCommand),
      containsAll([
        '/new',
        '/plan',
        '/permissions',
        '/logs',
        '/compact',
        '/reconnect',
      ]),
    );

    expect(
      AcpCommandAction.filter(
        AcpCommandAction.defaults,
        '/per',
      ).single.slashCommand,
      '/permissions',
    );
    expect(
      AcpCommandAction.filter(
        AcpCommandAction.defaults,
        'diagnostic',
      ).single.slashCommand,
      '/logs',
    );
  });

  testWidgets('submits prompt text and clears the composer', (tester) async {
    String? submittedPrompt;

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          initialPrompt: '  inspect protocol logs  ',
          onSubmit: (prompt) => submittedPrompt = prompt,
        ),
      ),
    );

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(submittedPrompt, 'inspect protocol logs');
    expect(find.text('inspect protocol logs'), findsNothing);
  });

  testWidgets('submits prompt with desktop shortcut', (tester) async {
    String? submittedPrompt;

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          initialPrompt: 'keyboard submit',
          onSubmit: (prompt) => submittedPrompt = prompt,
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));

    expect(submittedPrompt, 'keyboard submit');
  });

  testWidgets('disables submit while prompt is empty or submitting', (
    tester,
  ) async {
    var submitted = false;

    await tester.pumpWidget(
      FluentApp(home: AcpPromptComposer(onSubmit: (_) => submitted = true)),
    );

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(submitted, isFalse);

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          initialPrompt: 'run',
          isSubmitting: true,
          onSubmit: (_) => submitted = true,
        ),
      ),
    );

    expect(find.byType(ProgressRing), findsOneWidget);
  });

  testWidgets('invokes cancel callback when cancel is available', (
    tester,
  ) async {
    var cancelled = false;

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          initialPrompt: 'long task',
          canCancel: true,
          onSubmit: (_) {},
          onCancel: () => cancelled = true,
        ),
      ),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(cancelled, isTrue);
  });

  testWidgets('invokes cancel shortcut when cancel is available', (
    tester,
  ) async {
    var cancelled = false;

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          initialPrompt: 'long task',
          canCancel: true,
          onSubmit: (_) {},
          onCancel: () => cancelled = true,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));

    expect(cancelled, isTrue);
  });

  testWidgets('slash at the start of the composer opens the inline palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          onSubmit: (_) {},
          commandActions: AcpCommandAction.defaults,
          onCommandSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), '/');
    await tester.pump();

    expect(find.byType(AcpCommandPaletteSurface), findsOneWidget);
    expect(find.text('/new'), findsOneWidget);
  });

  testWidgets('slash inside an existing word does not open the palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          onSubmit: (_) {},
          commandActions: AcpCommandAction.defaults,
          onCommandSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), 'path');
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'path/');
    await tester.pump();

    expect(find.byType(AcpCommandPaletteSurface), findsNothing);
  });

  testWidgets('continuing to type filters the inline command list', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          onSubmit: (_) {},
          commandActions: AcpCommandAction.defaults,
          onCommandSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), '/lo');
    await tester.pump();

    expect(find.text('/logs'), findsOneWidget);
    expect(find.text('/new'), findsNothing);
    expect(find.text('/reconnect'), findsNothing);
  });

  testWidgets(
    'Enter selects the highlighted inline command instead of inserting a '
    'newline',
    (tester) async {
      AcpCommandAction? selected;

      await tester.pumpWidget(
        FluentApp(
          home: AcpPromptComposer(
            onSubmit: (_) {},
            commandActions: AcpCommandAction.defaults,
            onCommandSelected: (action) => selected = action,
          ),
        ),
      );

      await tester.enterText(find.byType(EditableText), '/ne');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected?.id, 'new');
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      expect(find.byType(AcpCommandPaletteSurface), findsNothing);
    },
  );

  testWidgets(
    'Enter on a highlighted unavailable command in the inline palette does '
    'nothing',
    (tester) async {
      AcpCommandAction? selected;

      await tester.pumpWidget(
        FluentApp(
          home: AcpPromptComposer(
            onSubmit: (_) {},
            commandActions: AcpCommandAction.defaults,
            onCommandSelected: (action) => selected = action,
          ),
        ),
      );

      await tester.enterText(find.byType(EditableText), '/pl');
      await tester.pump();

      // `/plan` is the only match for "pl" and it's unavailable.
      expect(
        AcpCommandAction.filter(AcpCommandAction.defaults, '/pl').single.id,
        'plan',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected, isNull);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '/pl',
      );
      expect(find.byType(AcpCommandPaletteSurface), findsOneWidget);
    },
  );

  testWidgets('Enter outside the inline trigger is not hijacked', (
    tester,
  ) async {
    AcpCommandAction? selected;
    String? submitted;

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          onSubmit: (prompt) => submitted = prompt,
          commandActions: AcpCommandAction.defaults,
          onCommandSelected: (action) => selected = action,
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), 'hello');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selected, isNull);
    expect(submitted, isNull);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'hello',
    );
  });

  testWidgets('selecting a command from the inline palette clears the '
      'trigger fragment', (tester) async {
    AcpCommandAction? selected;

    await tester.pumpWidget(
      FluentApp(
        // The inline palette floats above the composer via an
        // `OverlayPortal`, so — like the real main pane, where the
        // composer sits at the bottom of the screen with content above
        // it — this needs room above the composer for the tap target to
        // land on-screen.
        home: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AcpPromptComposer(
              onSubmit: (_) {},
              commandActions: AcpCommandAction.defaults,
              onCommandSelected: (action) => selected = action,
            ),
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), '/ne');
    await tester.pump();

    await tester.tap(find.text('/new'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected?.id, 'new');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    expect(find.byType(AcpCommandPaletteSurface), findsNothing);
  });

  testWidgets('deleting the triggering slash closes the inline palette without '
      'executing a command', (tester) async {
    AcpCommandAction? selected;

    await tester.pumpWidget(
      FluentApp(
        home: AcpPromptComposer(
          onSubmit: (_) {},
          commandActions: AcpCommandAction.defaults,
          onCommandSelected: (action) => selected = action,
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), '/ne');
    await tester.pump();
    expect(find.byType(AcpCommandPaletteSurface), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '/n');
    await tester.pump();
    expect(find.byType(AcpCommandPaletteSurface), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();

    expect(find.byType(AcpCommandPaletteSurface), findsNothing);
    expect(selected, isNull);
  });

  testWidgets(
    "shows a selected agent command's input hint as a suffix until the "
    'user types past it',
    (tester) async {
      const deploy = AcpCommandAction(
        id: 'agent-deploy',
        label: 'deploy',
        slashCommand: '/deploy',
        description: 'Deploy the app',
        icon: FluentIcons.robot,
        source: AcpCommandSource.agent,
        hint: 'target environment',
      );

      await tester.pumpWidget(
        FluentApp(
          home: AcpPromptComposer(
            onSubmit: (_) {},
            commandActions: [deploy],
            onCommandSelected: (_) {},
          ),
        ),
      );

      expect(find.text('target environment'), findsNothing);

      await tester.enterText(find.byType(EditableText), '/deploy ');
      await tester.pump();

      expect(find.text('target environment'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), '/deploy prod');
      await tester.pump();

      expect(find.text('target environment'), findsNothing);
    },
  );

  testWidgets('renders compact tool call status details', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: AcpToolCallSummary(
          name: 'edit',
          target: 'lib/main.dart',
          status: AcpToolCallStatus.failed,
          detail: 'permission denied',
        ),
      ),
    );

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('edit - lib/main.dart'), findsOneWidget);
    expect(find.text('permission denied'), findsOneWidget);
  });

  testWidgets('renders summary tool calls without target or detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: AcpToolCallSummary(
          name: 'edit',
          target: 'lib/main.dart',
          status: AcpToolCallStatus.running,
          detail: 'permission pending',
          viewMode: AcpViewMode.summary,
        ),
      ),
    );

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('edit'), findsOneWidget);
    expect(find.text('edit - lib/main.dart'), findsNothing);
    expect(find.text('permission pending'), findsNothing);
  });

  testWidgets('renders verbose tool calls with target and detail rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: AcpToolCallSummary(
          name: 'edit',
          target: 'lib/main.dart',
          status: AcpToolCallStatus.succeeded,
          detail: 'applied patch',
          viewMode: AcpViewMode.verbose,
        ),
      ),
    );

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('edit'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('applied patch'), findsOneWidget);
  });

  testWidgets('renders connection status with transport and profile labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: AcpConnectionStatusRow(
          status: AcpConnectionStatus.connected,
          transportLabel: 'stdio',
          profileLabel: 'Codelab Agent',
          detail: 'ready',
        ),
      ),
    );

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('stdio'), findsOneWidget);
    expect(find.text('Codelab Agent'), findsOneWidget);
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('selects approval option by id', (tester) async {
    String? selected;

    await tester.pumpWidget(
      FluentApp(
        home: AcpApprovalOptionGroup(
          selectedOptionId: 'allow_once',
          onSelected: (optionId) => selected = optionId,
          options: const [
            AcpApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              description: 'Run once for this prompt turn.',
              tone: AcpTone.warning,
            ),
            AcpApprovalOption(
              id: 'reject',
              label: 'Reject',
              description: 'Deny the request.',
              tone: AcpTone.danger,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Reject'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected, 'reject');
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Risk'), findsOneWidget);
  });

  testWidgets('selects approval and reject options from shortcuts', (
    tester,
  ) async {
    final selected = <String>[];

    await tester.pumpWidget(
      FluentApp(
        home: AcpApprovalOptionGroup(
          selectedOptionId: 'allow_once',
          onSelected: selected.add,
          options: const [
            AcpApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              description: 'Run once for this prompt turn.',
              tone: AcpTone.warning,
            ),
            AcpApprovalOption(
              id: 'reject',
              label: 'Reject',
              description: 'Deny the request.',
              tone: AcpTone.danger,
            ),
          ],
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected, ['allow_once', 'reject']);
  });
}
