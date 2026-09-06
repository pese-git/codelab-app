import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports atomics through the public package API', () {
    expect(AcpBadge, isA<Type>());
    expect(AcpButton, isA<Type>());
    expect(AcpIcon, isA<Type>());
    expect(AcpIconButton, isA<Type>());
    expect(AcpProgressIndicator, isA<Type>());
    expect(AcpStatusIndicator, isA<Type>());
    expect(AcpStatusTone.active, isA<AcpStatusTone>());
    expect(AcpText, isA<Type>());
    expect(AcpTone.accent, isA<AcpTone>());
  });

  testWidgets('renders button and invokes callback', (tester) async {
    var pressed = false;

    await tester.pumpWidget(
      FluentApp(
        home: AcpButton(
          label: 'Connect',
          icon: FluentIcons.plug_connected,
          emphasis: AcpButtonEmphasis.primary,
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
    'imply that (see acp_prompt_composer.dart\'s Send button, which relies '
    'on the opposite: staying pressable while isLoading is true)',
    (tester) async {
      var pressed = false;

      await tester.pumpWidget(
        FluentApp(
          home: AcpButton(
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
        home: AcpButton(label: 'Connecting', isLoading: true, onPressed: null),
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
            AcpBadge(label: 'Active', tone: AcpTone.success),
            AcpIconButton(
              icon: FluentIcons.cancel,
              tooltip: 'Cancel',
              onPressed: null,
            ),
            AcpText('Transcript', role: AcpTextRole.subtitle),
            AcpProgressIndicator(value: 65, semanticLabel: 'Loading'),
          ],
        ),
      ),
    );

    expect(find.text('Active'), findsOneWidget);
    expect(find.byType(AcpIconButton), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
  });

  testWidgets('renders a status label', (tester) async {
    await tester.pumpWidget(
      const FluentApp(home: AcpStatusIndicator(label: 'Ready')),
    );

    expect(find.text('Ready'), findsOneWidget);
  });
}
