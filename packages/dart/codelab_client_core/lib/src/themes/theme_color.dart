/// Значение цвета роли темы (spec `client-themes`, «Формат файла»).
///
/// ЗАГЛУШКА красного теста 1.3: разбор и равенство — задача 1.4.
library;

sealed class ThemeColorValue {
  const ThemeColorValue();

  /// Разбор строки формата: `#rrggbb`, `default`, имя ANSI, `256:<n>`;
  /// иное — `null`.
  static ThemeColorValue? tryParse(String text) =>
      throw UnimplementedError('theme_color: задача 1.4');
}

/// `#rrggbb`: [value] — 24 бита RGB.
final class Rgb extends ThemeColorValue {
  const Rgb(this.value);

  final int value;
}

/// `default` — «роль из `extends`».
final class DefaultColor extends ThemeColorValue {
  const DefaultColor();
}

/// Один из 16 цветов ANSI: [name] — `red`, `bright_red`.
final class AnsiColor extends ThemeColorValue {
  const AnsiColor(this.name);

  final String name;
}

/// `256:<n>`, [index] от 0 до 255.
final class IndexedColor extends ThemeColorValue {
  const IndexedColor(this.index);

  final int index;
}
