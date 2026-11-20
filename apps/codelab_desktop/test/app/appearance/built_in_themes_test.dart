// Красные тесты встроенных тем и сборки `FluentThemeData` (задача 4.3 change
// `add-app-appearance-page`; design.md D4, D6; spec app-settings «Режим
// оформления и темы режимов»: «Стандартная тема не меняет вид»).
//
// `light` и `dark` — стандартная тема Fluent своего режима, значения кита для
// них равны выведенным китом (доказательство «вид не изменился»);
// `high-contrast` — палитра из D6. App регистрирует `CodeLabPalette` и
// `CodeLabCodeTheme` всегда.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/appearance/built_in_themes.dart';
import 'package:codelab_desktop/app/appearance/fluent_theme_builder.dart';
import 'package:codelab_desktop/features/settings/application/contrast_checks.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('встроенные темы называются light, dark, high-contrast', () {
    expect(kBuiltInThemeIds, ['light', 'dark', 'high-contrast']);
    expect(builtInThemeFile('light').base, ThemeBase.light);
    expect(builtInThemeFile('dark').base, ThemeBase.dark);
    expect(builtInThemeFile('high-contrast').base, ThemeBase.dark);
  });

  test('встроенные темы имеют значения всех ролей', () {
    for (final id in kBuiltInThemeIds) {
      expect(
        builtInThemeFile(id).roles.keys,
        containsAll(ThemeRole.values),
        reason: id,
      );
    }
  });

  group('«Стандартная тема не меняет вид» (light и dark)', () {
    for (final brightness in Brightness.values) {
      final id = brightness == Brightness.light ? 'light' : 'dark';

      test('$id: расширения зарегистрированы, значения равны выведенным '
          'китом', () {
        final built = buildFluentTheme(builtInThemeFile(id));
        final derived = FluentThemeData(brightness: brightness);

        expect(built.brightness, brightness);
        // App регистрирует палитру всегда (D4), а не полагается на вывод.
        expect(built.extensions[CodeLabPalette], isA<CodeLabPalette>());
        expect(built.extensions[CodeLabCodeTheme], isA<CodeLabCodeTheme>());

        final palette = CodeLabPalette.of(built);
        final expected = CodeLabPalette.of(derived);
        // Тоны светлой темы остаются прежними; в тёмной теме `Colors.green` и
        // `Colors.red` нечитаемы, и app подгоняет их под фон (задача 4.11, D8).
        if (brightness == Brightness.light) {
          expect(palette.success, expected.success);
          expect(palette.warning, expected.warning);
          expect(palette.accent, expected.accent);
        }
        // `Colors.red` на светлом фоне кода даёт 4,23:1 < 4,5 (D8): `danger`
        // подгоняется в обеих темах и остаётся красным по тону.
        final background = CodeLabCodeTheme.of(built).background;
        expect(
          contrastRatio(palette.danger, background),
          greaterThanOrEqualTo(kMinTextContrast),
        );
        expect(
          HSLColor.fromColor(palette.danger).hue,
          closeTo(HSLColor.fromColor(expected.danger).hue, 3),
        );
        expect(palette.info, expected.info);
        expect(palette.diffAddBackground, expected.diffAddBackground);
        expect(palette.diffRemoveBackground, expected.diffRemoveBackground);
        expect(palette.selection, expected.selection);

        final code = CodeLabCodeTheme.of(built);
        final expectedCode = CodeLabCodeTheme.of(derived);
        expect(code.background, expectedCode.background);
        expect(code.plain, expectedCode.plain);
        for (final tokenClass in CodeLabTokenClass.values) {
          expect(
            code.colorOf(tokenClass),
            expectedCode.colorOf(tokenClass),
            reason: '$id: $tokenClass',
          );
        }
      });
    }
  });

  group('high-contrast (D6)', () {
    late FluentThemeData theme;

    setUp(() => theme = buildFluentTheme(builtInThemeFile('high-contrast')));

    test('тёмная база с чёрным фоном кода', () {
      expect(theme.brightness, Brightness.dark);
      expect(CodeLabCodeTheme.of(theme).background, const Color(0xFF000000));
    });

    test('цвета кода и статусов — из артборда', () {
      final code = CodeLabCodeTheme.of(theme);
      expect(code.plain, const Color(0xFFFFFFFF));
      expect(code.colorOf(CodeLabTokenClass.comment), const Color(0xFFC8C8C8));
      expect(code.colorOf(CodeLabTokenClass.keyword), const Color(0xFFFF9DF5));
      expect(code.colorOf(CodeLabTokenClass.string), const Color(0xFF7CFC8A));
      expect(code.colorOf(CodeLabTokenClass.type), const Color(0xFF7FD4FF));
      expect(code.colorOf(CodeLabTokenClass.number), const Color(0xFFFFC66B));

      final palette = CodeLabPalette.of(theme);
      expect(palette.success, const Color(0xFF7CFC8A));
      expect(palette.warning, const Color(0xFFFFD75F));
      expect(palette.danger, const Color(0xFFFF8080));
      expect(palette.info, const Color(0xFF7FD4FF));
      expect(palette.diffAddBackground, const Color(0xFF003D12));
      expect(palette.diffRemoveBackground, const Color(0xFF4A0000));
    });
  });

  group('системный акцент (D7, Q4)', () {
    test('перекрывает accent встроенной темы', () {
      const system = Color(0xFFFF2D55);
      for (final id in kBuiltInThemeIds) {
        final theme = buildFluentTheme(
          builtInThemeFile(id),
          systemAccent: system,
        );
        expect(theme.accentColor.normal, system, reason: id);
      }
    });

    test('выключенный акцент не меняет accentColor стандартной темы', () {
      final built = buildFluentTheme(builtInThemeFile('dark'));
      expect(
        built.accentColor,
        FluentThemeData(brightness: Brightness.dark).accentColor,
      );
    });
  });

  // Spec app-settings «Тоны тёмной темы читаемы» (задача 4.12): текст тона
  // читаем на фоне страницы, карточки, кода и на заливке самого тега (альфа 56
  // у тегов тонов, 46 у нейтрального).
  group('тоны темы читаемы на четырёх фонах', () {
    List<Color> backgrounds(FluentThemeData theme, Color tone, int alpha) {
      final page = theme.resources.solidBackgroundFillColorBase;
      final card = Color.alphaBlend(
        theme.resources.cardBackgroundFillColorDefault,
        page,
      ).withValues(alpha: 1);
      return [
        page,
        card,
        CodeLabCodeTheme.of(theme).background,
        Color.alphaBlend(tone.withAlpha(alpha), page),
        Color.alphaBlend(tone.withAlpha(alpha), card),
      ];
    }

    void expectReadable(
      FluentThemeData theme,
      String name,
      Color tone, {
      int alpha = 56,
    }) {
      for (final background in backgrounds(theme, tone, alpha)) {
        expect(
          contrastRatio(Color.alphaBlend(tone, background), background),
          greaterThanOrEqualTo(kMinTextContrast),
          reason: '$name на #${background.toARGB32().toRadixString(16)}',
        );
      }
    }

    test('dark: success, warning, danger и accent', () {
      final theme = buildFluentTheme(builtInThemeFile('dark'));
      final palette = CodeLabPalette.of(theme);

      expectReadable(theme, 'success', palette.success);
      expectReadable(theme, 'warning', palette.warning);
      expectReadable(theme, 'danger', palette.danger);
      expectReadable(theme, 'accent', palette.accent);
    });

    test('light: danger и нейтральный тег', () {
      final theme = buildFluentTheme(builtInThemeFile('light'));
      final palette = CodeLabPalette.of(theme);

      expectReadable(theme, 'danger', palette.danger);
      expectReadable(
        theme,
        'neutral',
        palette.toneColor(CodeLabTone.neutral, theme),
        alpha: 46,
      );
    });

    test('dark: нейтральный тег', () {
      final theme = buildFluentTheme(builtInThemeFile('dark'));

      expectReadable(
        theme,
        'neutral',
        CodeLabPalette.of(theme).toneColor(CodeLabTone.neutral, theme),
        alpha: 46,
      );
    });
  });
}
