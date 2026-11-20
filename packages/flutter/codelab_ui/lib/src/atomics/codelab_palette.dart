import 'package:fluent_ui/fluent_ui.dart';

/// ЗАГЛУШКА для красного теста 3.1 (change `add-app-appearance-page`, D4).
///
/// Только API, чтобы `test/codelab_palette_test.dart` компилировался: кит
/// пока не читает палитру, поэтому тест падает по утверждениям. Настоящая
/// реализация (`of` с выводом из Fluent, потребители в тегах, ссылках) — задача 3.2; эту заглушку она заменяет целиком.
class CodeLabPalette extends ThemeExtension<CodeLabPalette> {
  const CodeLabPalette({
    required this.success,
    required this.warning,
    required this.danger,
    required this.accent,
    required this.info,
    required this.diffAddBackground,
    required this.diffRemoveBackground,
    required this.selection,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color accent;
  final Color info;
  final Color diffAddBackground;
  final Color diffRemoveBackground;
  final Color selection;

  static const _unset = Color(0x00000000);

  /// Заглушка: зарегистрированная палитра или «пустая»; вывод из Fluent — 3.2.
  static CodeLabPalette of(FluentThemeData theme) {
    final registered = theme.extensions[CodeLabPalette];
    if (registered is CodeLabPalette) return registered;
    return const CodeLabPalette(
      success: _unset,
      warning: _unset,
      danger: _unset,
      accent: _unset,
      info: _unset,
      diffAddBackground: _unset,
      diffRemoveBackground: _unset,
      selection: _unset,
    );
  }

  @override
  CodeLabPalette copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? accent,
    Color? info,
    Color? diffAddBackground,
    Color? diffRemoveBackground,
    Color? selection,
  }) => CodeLabPalette(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    accent: accent ?? this.accent,
    info: info ?? this.info,
    diffAddBackground: diffAddBackground ?? this.diffAddBackground,
    diffRemoveBackground: diffRemoveBackground ?? this.diffRemoveBackground,
    selection: selection ?? this.selection,
  );

  @override
  CodeLabPalette lerp(ThemeExtension<CodeLabPalette>? other, double t) => this;
}
