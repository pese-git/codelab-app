import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports atomics through the public package API', () {
    expect(CodeLabBadge, isA<Type>());
    expect(CodeLabButton, isA<Type>());
    expect(CodeLabIcon, isA<Type>());
    expect(CodeLabIconButton, isA<Type>());
    expect(CodeLabProgressIndicator, isA<Type>());
    expect(CodeLabStatusIndicator, isA<Type>());
    expect(CodeLabStatusTone.active, isA<CodeLabStatusTone>());
    expect(CodeLabText, isA<Type>());
    expect(CodeLabTone.accent, isA<CodeLabTone>());
  });

  testWidgets('renders button and invokes callback', (tester) async {
    var pressed = false;

    await tester.pumpWidget(
      FluentApp(
        home: CodeLabButton(
          label: 'Connect',
          icon: FluentIcons.plug_connected,
          emphasis: CodeLabButtonEmphasis.primary,
          onPressed: () => pressed = true,
        ),
      ),
    );

    await tester.tap(find.text('Connect'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(pressed, isTrue);
  });

  testWidgets(
    'isLoading shows the progress spinner without disabling the button — '
    'a caller that wants it disabled while loading (e.g. "Connecting…") '
    'passes onPressed: null itself, rather than relying on isLoading to '
    'imply that (see codelab_prompt_composer.dart\'s Send button, which relies '
    'on the opposite: staying pressable while isLoading is true)',
    (tester) async {
      var pressed = false;

      await tester.pumpWidget(
        FluentApp(
          home: CodeLabButton(
            label: 'Connecting',
            isLoading: true,
            onPressed: () => pressed = true,
          ),
        ),
      );

      expect(find.byType(ProgressRing), findsOneWidget);

      await tester.tap(find.text('Connecting'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(pressed, isTrue);
    },
  );

  testWidgets('a caller that passes onPressed: null while isLoading renders a '
      'genuinely disabled button', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: CodeLabButton(
          label: 'Connecting',
          isLoading: true,
          onPressed: null,
        ),
      ),
    );

    final button = tester.widget<Button>(find.byType(Button));
    expect(button.onPressed, isNull);
  });

  testWidgets('renders badge, icon button, text, and progress atomics', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: Column(
          children: [
            CodeLabBadge(label: 'Active', tone: CodeLabTone.success),
            CodeLabIconButton(
              icon: FluentIcons.cancel,
              tooltip: 'Cancel',
              onPressed: null,
            ),
            CodeLabText('Transcript', role: CodeLabTextRole.subtitle),
            CodeLabProgressIndicator(value: 65, semanticLabel: 'Loading'),
          ],
        ),
      ),
    );

    expect(find.text('Active'), findsOneWidget);
    expect(find.byType(CodeLabIconButton), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
  });

  testWidgets('renders a status label', (tester) async {
    await tester.pumpWidget(
      const FluentApp(home: CodeLabStatusIndicator(label: 'Ready')),
    );

    expect(find.text('Ready'), findsOneWidget);
  });
}
