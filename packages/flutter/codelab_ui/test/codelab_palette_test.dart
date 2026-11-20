// Красный тест 3.1 change `add-app-appearance-page`: палитра кита из
// расширения темы `CodeLabPalette` — доказательство D-20 (пользовательская
// тема меняет цвета виджетов кита без знания кита о файлах тем).
//
// Spec agent-workbench-ui: «Цвета кита из палитры темы» («Палитра из
// расширения», «Без расширения вид прежний») и MODIFIED «Блок кода в ответе
// агента» («Роль пользовательской темы с низким контрастом»); design.md D4.
// Реализация — задача 3.2; до неё тесты «из расширения» падают по
// утверждениям (кит ещё берёт зашитые `Colors.*`), а «вид прежний» и роль
// `code.*` зелёные — они фиксируют то, что менять нельзя.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _green = Color(0xFFA6E3A1);
const _red = Color(0xFFF38BA8);
const _blue = Color(0xFF89B4FA);

/// Палитра из сценария спецификации; незаданные в нём роли — нейтральные.
const _custom = CodeLabPalette(
  success: _green,
  warning: Color(0xFFF9E2AF),
  danger: _red,
  accent: _blue,
  info: _blue,
  diffAddBackground: Color(0xFF1E3A2A),
  diffRemoveBackground: Color(0xFF3A1E26),
  selection: Color(0xFF45475A),
);

Widget _host(Widget child, {FluentThemeData? theme}) => FluentApp(
  theme: theme ?? FluentThemeData(extensions: const [_custom]),
  home: ScaffoldPage(
    content: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 600, child: child),
    ),
  ),
);

Color? _textColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

void main() {
  group('палитра из расширения темы (spec: «Палитра из расширения»)', () {
    testWidgets('тег Done берёт success, тег Failed — danger', (tester) async {
      await tester.pumpWidget(
        _host(
          const Row(
            children: [
              CodeLabBadge(label: 'Done', tone: CodeLabTone.success),
              CodeLabBadge(label: 'Failed', tone: CodeLabTone.danger),
            ],
          ),
        ),
      );

      expect(_textColor(tester, 'Done'), _green);
      expect(_textColor(tester, 'Failed'), _red);
    });

    testWidgets('ссылка markdown берёт info', (tester) async {
      final theme = FluentThemeData(extensions: const [_custom]);
      await tester.pumpWidget(
        _host(
          CodeLabMarkdownScope(
            canOpenLink: (_) => true,
            onOpenLink: (_) {},
            canLoadImage: (_) => false,
            imageFor: (_) => throw UnimplementedError(),
            shownImages: const {},
            onShowImage: (_) {},
            onImageFailed: (_, _) {},
            child: CodeLabMarkdown(
              id: 'agent-1',
              text: 'See [docs](https://example.com/a).',
              config: CodeLabMarkdownConfig(theme),
            ),
          ),
          theme: theme,
        ),
      );

      Color? linkColor;
      for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
        text.text.visitChildren((span) {
          if (span is TextSpan && (span.text ?? '').contains('docs')) {
            linkColor = span.style?.color;
          }
          return true;
        });
      }
      expect(linkColor, _blue);
    });

    testWidgets('CodeLabPalette.of отдаёт зарегистрированную палитру', (
      tester,
    ) async {
      final theme = FluentThemeData(extensions: const [_custom]);
      expect(CodeLabPalette.of(theme).success, _green);
    });
  });

  group('без расширения вид прежний (spec: «Без расширения вид прежний»)', () {
    testWidgets('теги и палитра равны прежним Colors.*', (tester) async {
      await tester.pumpWidget(
        _host(
          const Row(
            children: [
              CodeLabBadge(label: 'Done', tone: CodeLabTone.success),
              CodeLabBadge(label: 'Failed', tone: CodeLabTone.danger),
            ],
          ),
          theme: FluentThemeData(),
        ),
      );

      expect(_textColor(tester, 'Done'), Colors.green);
      expect(_textColor(tester, 'Failed'), Colors.red);
    });

    test('CodeLabPalette.of выводит прежние цвета из FluentTheme', () {
      final theme = FluentThemeData();
      final palette = CodeLabPalette.of(theme);
      expect(palette.success, Colors.green);
      expect(palette.danger, Colors.red);
      expect(palette.warning, Colors.warningPrimaryColor);
      expect(palette.accent, Colors.blue);
      // Ссылки в Fluent-теме — акцент темы: вид не меняется (D4).
      expect(palette.info, theme.accentColor);
    });
  });

  testWidgets('роль code.* с низким контрастом применяется как задана, без '
      'подгонки под порог (spec: «Роль пользовательской темы с низким '
      'контрастом»)', (tester) async {
    const background = Color(0xFF14121F);
    const comment = Color(0xFF3A3650);
    final theme = FluentThemeData(
      extensions: [
        _custom,
        CodeLabCodeTheme(
          background: background,
          plain: const Color(0xFFCDD6F4),
          colors: const {CodeLabTokenClass.comment: comment},
        ),
      ],
    );
    const code = '// note';
    await tester.pumpWidget(
      _host(
        CodeLabMarkdown(
          id: 'agent-1',
          text: '```dart\n$code\n```\n',
          config: CodeLabMarkdownConfig(
            theme,
            highlighter: CodeLabCodeHighlighter(
              tokenizer: (language, source) => [
                CodeLabCodeToken(0, code.length, CodeLabTokenClass.comment),
              ],
            ),
          ),
        ),
        theme: theme,
      ),
    );
    await tester.pump();

    final colors = <Color>{};
    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      if (!text.text.toPlainText().contains('note')) continue;
      text.text.visitChildren((span) {
        final color = span is TextSpan ? span.style?.color : null;
        if (color != null) colors.add(color);
        return true;
      });
    }
    expect(colors, contains(comment));
    final block = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(CodeLabCodeBlock),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((block.decoration as BoxDecoration).color, background);
  });

  // Spec agent-workbench-ui / app-settings «Нейтральный тег в тёмной теме»
  // (задача 4.12): `Colors.grey` (#323130) на тёмном фоне давал 1,3:1.
  group('нейтральный тег: цвет по режиму темы', () {
    test('светлая тема — прежний Colors.grey', () {
      final theme = FluentThemeData(brightness: Brightness.light);

      expect(
        CodeLabPalette.of(theme).toneColor(CodeLabTone.neutral, theme),
        Colors.grey,
      );
    });

    test('тёмная тема — вторичный текст темы', () {
      final theme = FluentThemeData(brightness: Brightness.dark);

      expect(
        CodeLabPalette.of(theme).toneColor(CodeLabTone.neutral, theme),
        theme.resources.textFillColorSecondary,
      );
    });

    test('остальные тона не зависят от режима темы', () {
      final theme = FluentThemeData(brightness: Brightness.dark);
      final palette = CodeLabPalette.of(theme);

      expect(palette.toneColor(CodeLabTone.success, theme), palette.success);
      expect(palette.toneColor(CodeLabTone.warning, theme), palette.warning);
      expect(palette.toneColor(CodeLabTone.danger, theme), palette.danger);
      expect(palette.toneColor(CodeLabTone.accent, theme), palette.accent);
    });
  });
}
