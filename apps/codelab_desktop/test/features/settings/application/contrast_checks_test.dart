// Красные тесты проверки контраста (задача 4.3 change
// `add-app-appearance-page`; design.md D8; spec app-settings «Контраст на
// фоне кода»: «Встроенные темы проходят»).
//
// Формула WCAG 2: (L1 + 0.05) / (L2 + 0.05) по относительной яркости
// непрозрачных цветов; порог текста — 4,5:1.

import 'package:codelab_client_core/codelab_client_core.dart' show ThemeRole;
import 'package:codelab_desktop/app/appearance/built_in_themes.dart';
import 'package:codelab_desktop/app/appearance/fluent_theme_builder.dart';
import 'package:codelab_desktop/features/settings/application/contrast_checks.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('формула WCAG 2 на эталонных парах', () {
    test('чёрный и белый — 21:1 в любом порядке', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      expect(contrastRatio(black, white), closeTo(21, 0.001));
      expect(contrastRatio(white, black), closeTo(21, 0.001));
    });

    test('одинаковые цвета — 1:1', () {
      const grey = Color(0xFF777777);
      expect(contrastRatio(grey, grey), closeTo(1, 0.001));
    });

    test('#777777 на белом — около 4,48:1 (ниже порога AA)', () {
      final ratio = contrastRatio(
        const Color(0xFF777777),
        const Color(0xFFFFFFFF),
      );
      expect(ratio, closeTo(4.48, 0.01));
      expect(ratio, lessThan(kMinTextContrast));
    });

    test('порог — 4,5', () {
      expect(kMinTextContrast, 4.5);
    });
  });

  group('«Встроенные темы проходят»', () {
    // Тёмный, светлый и насыщенный акценты: акцент не должен ронять контраст
    // проверяемых ролей (D8).
    const accents = <Color?>[
      null,
      Color(0xFF1B1B3A),
      Color(0xFFF2F2FF),
      Color(0xFFFF2D55),
    ];

    test('проверяются text, info, error и code.* без фона', () {
      final checks = checkContrast(buildFluentTheme(builtInThemeFile('dark')));

      expect(
        checks.map((c) => c.role),
        containsAll([
          ThemeRole.text,
          ThemeRole.info,
          ThemeRole.error,
          ThemeRole.codeKeyword,
          ThemeRole.codeString,
          ThemeRole.codeComment,
          ThemeRole.codeNumber,
          ThemeRole.codeType,
          ThemeRole.codeFunction,
          ThemeRole.codeVariable,
          ThemeRole.codeOperator,
          ThemeRole.codeAttribute,
        ]),
      );
      expect(
        checks.map((c) => c.role),
        isNot(contains(ThemeRole.codeBackground)),
      );
    });

    for (final id in kBuiltInThemeIds) {
      for (final accent in accents) {
        test(
          '$id, акцент ${accent ?? 'выключен'}: каждая роль не ниже 4,5:1',
          () {
            final theme = buildFluentTheme(
              builtInThemeFile(id),
              systemAccent: accent,
            );

            final checks = checkContrast(theme);

            expect(checks, isNotEmpty);
            for (final check in checks) {
              expect(
                check.ratio,
                greaterThanOrEqualTo(kMinTextContrast),
                reason: '$id, ${check.role.qualifiedName}, акцент $accent',
              );
              expect(check.passes, isTrue);
            }
          },
        );
      }
    }
  });
}
