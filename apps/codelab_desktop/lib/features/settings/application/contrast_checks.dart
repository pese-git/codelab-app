import 'dart:ui';

import 'package:codelab_client_core/codelab_client_core.dart' show ThemeRole;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' show AccentColor, FluentThemeData;

/// Порог WCAG AA для текста, 4,5:1 (`add-app-appearance-page`, D8).
const kMinTextContrast = 4.5;

/// Отношение контраста WCAG 2 двух цветов: `(L1 + 0.05) / (L2 + 0.05)` по
/// относительной яркости (`Color.computeLuminance`).
///
/// Почему здесь, а не в ядре клиента: контраст нужен только app (D8).
/// Как использовать: цвета берутся непрозрачными; полупрозрачный цвет вызывающий
/// сначала накладывает на фон (`Color.alphaBlend`). Порядок аргументов
/// неважен.
double contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Проверка одной роли на фоне кода (D8): роль, её цвет и отношение к
/// `code.background`.
final class ContrastCheck {
  const ContrastCheck({
    required this.role,
    required this.color,
    required this.ratio,
  });

  final ThemeRole role;
  final Color color;
  final double ratio;

  /// Не ниже порога AA ([kMinTextContrast]).
  bool get passes => ratio >= kMinTextContrast;
}

const _codeRoles = {
  CodeLabTokenClass.keyword: ThemeRole.codeKeyword,
  CodeLabTokenClass.string: ThemeRole.codeString,
  CodeLabTokenClass.comment: ThemeRole.codeComment,
  CodeLabTokenClass.number: ThemeRole.codeNumber,
  CodeLabTokenClass.type: ThemeRole.codeType,
  CodeLabTokenClass.function: ThemeRole.codeFunction,
  CodeLabTokenClass.variable: ThemeRole.codeVariable,
  CodeLabTokenClass.operator: ThemeRole.codeOperator,
  CodeLabTokenClass.attribute: ThemeRole.codeAttribute,
};

/// Проверяемые роли темы [theme] на её фоне кода: `text`, `info`, `error` и
/// все роли `code.*`, кроме фона (D8).
///
/// Для чего: страница «Appearance» показывает отношения и вердикты, бейдж
/// карточки считает роли ниже порога; тест встроенных тем проверяет, что ни
/// одна не ниже порога при любом акценте. Роль применяется как задана — даже
/// ниже порога (spec app-settings «Контраст на фоне кода»).
///
/// Как использовать: [theme] — готовая тема из `buildFluentTheme` с
/// расширениями `CodeLabPalette` и `CodeLabCodeTheme`; порядок результата —
/// `text`, `info`, `error`, затем `code.*`.
List<ContrastCheck> checkContrast(FluentThemeData theme) {
  final code = CodeLabCodeTheme.of(theme);
  final palette = CodeLabPalette.of(theme);
  final background = code.background;
  // Ссылка в Fluent-темах — акцент: его рисуют оттенком режима (D4).
  final info = palette.info;
  final link = info is AccentColor
      ? info.defaultBrushFor(theme.brightness)
      : info;
  ContrastCheck check(ThemeRole role, Color color) {
    final solid = Color.alphaBlend(color, background);
    return ContrastCheck(
      role: role,
      color: solid,
      ratio: contrastRatio(solid, background),
    );
  }

  return [
    check(ThemeRole.text, code.plain),
    check(ThemeRole.info, link),
    check(ThemeRole.error, palette.danger),
    for (final entry in _codeRoles.entries)
      check(entry.value, code.colorOf(entry.key)),
  ];
}
