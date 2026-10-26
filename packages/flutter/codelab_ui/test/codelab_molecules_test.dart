import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports molecules through the public package API', () {
    expect(CodeLabApprovalOption, isA<Type>());
    expect(CodeLabApprovalOptionGroup, isA<Type>());
    expect(CodeLabCommandAction, isA<Type>());
    expect(CodeLabConnectionStatus.connected, isA<CodeLabConnectionStatus>());
    expect(CodeLabConnectionStatusRow, isA<Type>());
    expect(CodeLabPromptComposer, isA<Type>());
    expect(CodeLabToolCallStatus.running, isA<CodeLabToolCallStatus>());
    expect(CodeLabToolCallSummary, isA<Type>());
    expect(CodeLabViewMode.normal, isA<CodeLabViewMode>());
  });

  test('filters command actions by slash command, label, and description', () {
    expect(CodeLabCommandAction.defaults, hasLength(6));
    expect(
      CodeLabCommandAction.defaults.map((action) => action.slashCommand),
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
      CodeLabCommandAction.filter(
        CodeLabCommandAction.defaults,
        '/per',
      ).single.slashCommand,
      '/permissions',
    );
    expect(
      CodeLabCommandAction.filter(
        CodeLabCommandAction.defaults,
        'diagnostic',
      ).single.slashCommand,
      '/logs',
    );
  });

  testWidgets('submits prompt text and clears the composer', (tester) async {
    String? submittedPrompt;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabPromptComposer(
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
        home: CodeLabPromptComposer(
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

  testWidgets('disables submit while the prompt is empty', (tester) async {
    var submitted = false;

    await tester.pumpWidget(
      FluentApp(home: CodeLabPromptComposer(onSubmit: (_) => submitted = true)),
    );

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(submitted, isFalse);
  });

  testWidgets('isSubmitting only shows the loading spinner — it never disables '
      'typing or submitting, since the caller must still be able to queue a '
      'message while a turn is already running (add-prompt-queue/design.md, '
      'Goals)', (tester) async {
    String? submittedPrompt;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabPromptComposer(
          initialPrompt: 'run',
          isSubmitting: true,
          onSubmit: (prompt) => submittedPrompt = prompt,
        ),
      ),
    );

    expect(find.byType(ProgressRing), findsOneWidget);
    expect(tester.widget<TextBox>(find.byType(TextBox)).enabled, isTrue);

    await tester.enterText(find.byType(EditableText), 'queue me too');
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(submittedPrompt, 'queue me too');
  });

  testWidgets('invokes cancel callback when cancel is available', (
    tester,
  ) async {
    var cancelled = false;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabPromptComposer(
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
        home: CodeLabPromptComposer(
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
        home: CodeLabPromptComposer(
          onSubmit: (_) {},
          commandActions: CodeLabCommandAction.defaults,
          onCommandSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), '/');
    await tester.pump();

    expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);
    expect(find.text('/new'), findsOneWidget);
  });

  testWidgets('slash inside an existing word does not open the palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: CodeLabPromptComposer(
          onSubmit: (_) {},
          commandActions: CodeLabCommandAction.defaults,
          onCommandSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), 'path');
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'path/');
    await tester.pump();

    expect(find.byType(CodeLabCommandPaletteSurface), findsNothing);
  });

  testWidgets('continuing to type filters the inline command list', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: CodeLabPromptComposer(
          onSubmit: (_) {},
          commandActions: CodeLabCommandAction.defaults,
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
      CodeLabCommandAction? selected;

      await tester.pumpWidget(
        FluentApp(
          home: CodeLabPromptComposer(
            onSubmit: (_) {},
            commandActions: CodeLabCommandAction.defaults,
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
      expect(find.byType(CodeLabCommandPaletteSurface), findsNothing);
    },
  );

  testWidgets(
    'Enter on a highlighted unavailable command in the inline palette does '
    'nothing',
    (tester) async {
      CodeLabCommandAction? selected;

      await tester.pumpWidget(
        FluentApp(
          home: CodeLabPromptComposer(
            onSubmit: (_) {},
            commandActions: CodeLabCommandAction.defaults,
            onCommandSelected: (action) => selected = action,
          ),
        ),
      );

      await tester.enterText(find.byType(EditableText), '/pl');
      await tester.pump();

      // `/plan` is the only match for "pl" and it's unavailable.
      expect(
        CodeLabCommandAction.filter(
          CodeLabCommandAction.defaults,
          '/pl',
        ).single.id,
        'plan',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected, isNull);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '/pl',
      );
      expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);
    },
  );

  testWidgets('Enter outside the inline trigger is not hijacked', (
    tester,
  ) async {
    CodeLabCommandAction? selected;
    String? submitted;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabPromptComposer(
          onSubmit: (prompt) => submitted = prompt,
          commandActions: CodeLabCommandAction.defaults,
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
    CodeLabCommandAction? selected;

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
            CodeLabPromptComposer(
              onSubmit: (_) {},
              commandActions: CodeLabCommandAction.defaults,
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
    expect(find.byType(CodeLabCommandPaletteSurface), findsNothing);
  });

  testWidgets('deleting the triggering slash closes the inline palette without '
      'executing a command', (tester) async {
    CodeLabCommandAction? selected;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabPromptComposer(
          onSubmit: (_) {},
          commandActions: CodeLabCommandAction.defaults,
          onCommandSelected: (action) => selected = action,
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), '/ne');
    await tester.pump();
    expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '/n');
    await tester.pump();
    expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();

    expect(find.byType(CodeLabCommandPaletteSurface), findsNothing);
    expect(selected, isNull);
  });

  testWidgets(
    "shows a selected agent command's input hint as a suffix until the "
    'user types past it',
    (tester) async {
      const deploy = CodeLabCommandAction(
        id: 'agent-deploy',
        label: 'deploy',
        slashCommand: '/deploy',
        description: 'Deploy the app',
        icon: FluentIcons.robot,
        source: CodeLabCommandSource.agent,
        hint: 'target environment',
      );

      await tester.pumpWidget(
        FluentApp(
          home: CodeLabPromptComposer(
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

  testWidgets('does not render a config options row when the list is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(home: CodeLabPromptComposer(onSubmit: (_) {})),
    );

    expect(
      find.byKey(const ValueKey('composer-config-options-row')),
      findsNothing,
    );
  });

  testWidgets(
    'renders one chip per config option in the declared order with its '
    'current value',
    (tester) async {
      const modelOption = CodeLabConfigOption(
        id: 'model',
        name: 'Model',
        currentValue: 'gpt-5',
        values: [
          CodeLabConfigOptionValue(value: 'gpt-5', name: 'GPT-5'),
          CodeLabConfigOptionValue(value: 'gpt-4', name: 'GPT-4'),
        ],
      );
      const modeOption = CodeLabConfigOption(
        id: 'mode',
        name: 'Session Mode',
        currentValue: 'ask',
        values: [CodeLabConfigOptionValue(value: 'ask', name: 'Ask')],
      );

      await tester.pumpWidget(
        FluentApp(
          home: CodeLabPromptComposer(
            onSubmit: (_) {},
            configOptions: const [modelOption, modeOption],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('composer-config-options-row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('composer-config-option-model')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('composer-config-option-mode')),
        findsOneWidget,
      );
      expect(find.text('GPT-5'), findsOneWidget);
      expect(find.text('Ask'), findsOneWidget);

      final modelChip = tester.getTopLeft(
        find.byKey(const ValueKey('composer-config-option-model')),
      );
      final modeChip = tester.getTopLeft(
        find.byKey(const ValueKey('composer-config-option-mode')),
      );
      expect(modelChip.dx, lessThan(modeChip.dx));
    },
  );

  testWidgets('selecting a value from a config option chip calls '
      'onConfigOptionSelected with the configId and chosen value', (
    tester,
  ) async {
    String? selectedConfigId;
    String? selectedValue;
    const modelOption = CodeLabConfigOption(
      id: 'model',
      name: 'Model',
      currentValue: 'gpt-5',
      values: [
        CodeLabConfigOptionValue(value: 'gpt-5', name: 'GPT-5'),
        CodeLabConfigOptionValue(value: 'gpt-4', name: 'GPT-4'),
      ],
    );

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabPromptComposer(
          onSubmit: (_) {},
          configOptions: const [modelOption],
          onConfigOptionSelected: (configId, value) {
            selectedConfigId = configId;
            selectedValue = value;
          },
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('composer-config-option-model')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT-4'));
    await tester.pumpAndSettle();

    expect(selectedConfigId, 'model');
    expect(selectedValue, 'gpt-4');
  });

  testWidgets(
    'replaces the config options row entirely when a new list is provided',
    (tester) async {
      const modelOption = CodeLabConfigOption(
        id: 'model',
        name: 'Model',
        currentValue: 'gpt-5',
        values: [CodeLabConfigOptionValue(value: 'gpt-5', name: 'GPT-5')],
      );
      const modeOption = CodeLabConfigOption(
        id: 'mode',
        name: 'Session Mode',
        currentValue: 'ask',
        values: [CodeLabConfigOptionValue(value: 'ask', name: 'Ask')],
      );

      await tester.pumpWidget(
        FluentApp(
          home: CodeLabPromptComposer(
            onSubmit: (_) {},
            configOptions: const [modelOption],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('composer-config-option-model')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('composer-config-option-mode')),
        findsNothing,
      );

      await tester.pumpWidget(
        FluentApp(
          home: CodeLabPromptComposer(
            onSubmit: (_) {},
            configOptions: const [modeOption],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('composer-config-option-model')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('composer-config-option-mode')),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders compact tool call status details', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: CodeLabToolCallSummary(
          name: 'edit',
          target: 'lib/main.dart',
          status: CodeLabToolCallStatus.failed,
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
        home: CodeLabToolCallSummary(
          name: 'edit',
          target: 'lib/main.dart',
          status: CodeLabToolCallStatus.running,
          detail: 'permission pending',
          viewMode: CodeLabViewMode.summary,
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
        home: CodeLabToolCallSummary(
          name: 'edit',
          target: 'lib/main.dart',
          status: CodeLabToolCallStatus.succeeded,
          detail: 'applied patch',
          viewMode: CodeLabViewMode.verbose,
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
        home: CodeLabConnectionStatusRow(
          status: CodeLabConnectionStatus.connected,
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
        home: CodeLabApprovalOptionGroup(
          selectedOptionId: 'allow_once',
          onSelected: (optionId) => selected = optionId,
          options: const [
            CodeLabApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              kind: CodeLabApprovalOptionKind.allowOnce,
              description: 'Run once for this prompt turn.',
              tone: CodeLabTone.warning,
            ),
            CodeLabApprovalOption(
              id: 'reject',
              label: 'Reject',
              kind: CodeLabApprovalOptionKind.rejectOnce,
              description: 'Deny the request.',
              tone: CodeLabTone.danger,
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

  testWidgets('binds all four option kinds to their own keyboard shortcut', (
    tester,
  ) async {
    final selected = <String>[];

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabApprovalOptionGroup(
          onSelected: selected.add,
          options: const [
            CodeLabApprovalOption(
              id: 'allow_once',
              label: 'Allow once',
              kind: CodeLabApprovalOptionKind.allowOnce,
            ),
            CodeLabApprovalOption(
              id: 'allow_always',
              label: 'Allow always',
              kind: CodeLabApprovalOptionKind.allowAlways,
            ),
            CodeLabApprovalOption(
              id: 'reject_once',
              label: 'Reject once',
              kind: CodeLabApprovalOptionKind.rejectOnce,
            ),
            CodeLabApprovalOption(
              id: 'reject_always',
              label: 'Reject always',
              kind: CodeLabApprovalOptionKind.rejectAlways,
            ),
          ],
        ),
      ),
    );

    Future<void> pressWithModifiers(
      LogicalKeyboardKey trigger, {
      bool alt = false,
    }) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (alt) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      }
      await tester.sendKeyEvent(trigger);
      if (alt) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
    }

    await pressWithModifiers(LogicalKeyboardKey.enter);
    await pressWithModifiers(LogicalKeyboardKey.enter, alt: true);
    await pressWithModifiers(LogicalKeyboardKey.backspace);
    await pressWithModifiers(LogicalKeyboardKey.backspace, alt: true);

    expect(selected, [
      'allow_once',
      'allow_always',
      'reject_once',
      'reject_always',
    ]);
  });

  testWidgets('a non-English label without allow/reject words still gets the '
      'shortcut its kind implies', (tester) async {
    final selected = <String>[];

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabApprovalOptionGroup(
          onSelected: selected.add,
          options: const [
            CodeLabApprovalOption(
              id: 'opt_1',
              label: 'Разрешить',
              kind: CodeLabApprovalOptionKind.allowOnce,
            ),
            CodeLabApprovalOption(
              id: 'opt_2',
              label: 'Отклонить',
              kind: CodeLabApprovalOptionKind.rejectOnce,
            ),
          ],
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected, ['opt_2']);
  });

  testWidgets(
    'compactRow layout arranges options horizontally with a shortcut hint '
    'per bound kind',
    (tester) async {
      String? selected;

      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 400,
            child: CodeLabApprovalOptionGroup(
              layout: CodeLabApprovalOptionsLayout.compactRow,
              onSelected: (optionId) => selected = optionId,
              options: const [
                CodeLabApprovalOption(
                  id: 'allow_once',
                  label: 'Allow once',
                  kind: CodeLabApprovalOptionKind.allowOnce,
                  tone: CodeLabTone.success,
                ),
                CodeLabApprovalOption(
                  id: 'allow_always',
                  label: 'Allow always',
                  kind: CodeLabApprovalOptionKind.allowAlways,
                  tone: CodeLabTone.success,
                ),
                CodeLabApprovalOption(
                  id: 'reject',
                  label: 'Reject',
                  kind: CodeLabApprovalOptionKind.rejectOnce,
                  tone: CodeLabTone.danger,
                ),
              ],
            ),
          ),
        ),
      );

      // Horizontal, not the vertical list's "Selected" badge column.
      expect(find.byType(Row), findsWidgets);
      expect(find.text('Selected'), findsNothing);
      // No description/tone-badge chips at this density.
      expect(find.text('Safe'), findsNothing);
      expect(find.text('Risk'), findsNothing);

      final isMac = defaultTargetPlatform == TargetPlatform.macOS;
      final mod = isMac ? '⌘' : 'Ctrl+';
      final alt = isMac ? '⌥' : 'Alt+';
      expect(find.text('$mod⏎'), findsOneWidget);
      expect(find.text('$alt$mod⏎'), findsOneWidget);
      expect(find.text('$mod⌫'), findsOneWidget);

      await tester.tap(find.text('Allow always'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(selected, 'allow_always');
    },
  );
}
