import 'dart:ui';

import 'package:codelab_client_core/codelab_client_core.dart' show ThemeRole;
import 'package:fluent_ui/fluent_ui.dart' show FluentThemeData;

/// Порог WCAG AA для текста, 4,5:1 (D8).
const kMinTextContrast = 4.5;

/// Отношение контраста WCAG 2 двух непрозрачных цветов (D8).
///
/// ЗАГЛУШКА для красных тестов 4.3; формула — задача 4.4.
double contrastRatio(Color a, Color b) => 0;

/// Проверка одной роли на фоне кода.
final class ContrastCheck {
  const ContrastCheck({
    required this.role,
    required this.color,
    required this.ratio,
  });

  final ThemeRole role;
  final Color color;
  final double ratio;

  bool get passes => ratio >= kMinTextContrast;
}

/// Проверяемые роли `text`, `info`, `error` и `code.*` (кроме фона) темы
/// [theme] на её `code.background` (D8). ЗАГЛУШКА: пустой список.
List<ContrastCheck> checkContrast(FluentThemeData theme) => const [];
