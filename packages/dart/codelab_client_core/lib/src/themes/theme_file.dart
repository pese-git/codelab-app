/// Разбор файла пользовательской темы (spec `client-themes`, D2).
///
/// ЗАГЛУШКА красного теста 1.3: разбор — задача 1.4.
library;

import 'theme_color.dart';
import 'theme_issue.dart';
import 'theme_role.dart';

/// Предел размера файла темы, байт (64 КиБ).
const themeFileMaxBytes = 64 * 1024;

/// Допустимые значения `extends`.
enum ThemeBase {
  light('light'),
  dark('dark'),
  highContrast('high-contrast');

  const ThemeBase(this.jsonName);

  final String jsonName;
}

/// Тема с полным набором ролей: не заданные файлом — [DefaultColor].
final class ThemeFile {
  const ThemeFile({
    required this.name,
    required this.base,
    required this.roles,
  });

  /// `ThemeFile.parse(fileName, text)`: [fileName] — имя файла с `.json`;
  /// `null` — не сверять `name` с файлом (импорт). Текст больше
  /// [themeFileMaxBytes] в UTF-8 — `tooLarge`.
  static ThemeParseResult parse(String? fileName, String text) =>
      throw UnimplementedError('theme_file: задача 1.4');

  /// То же для сырых байт: не UTF-8 — `notUtf8`.
  static ThemeParseResult parseBytes(String? fileName, List<int> bytes) =>
      throw UnimplementedError('theme_file: задача 1.4');

  final String name;
  final ThemeBase base;

  /// Значения всех [ThemeRole.values].
  final Map<ThemeRole, ThemeColorValue> roles;
}

sealed class ThemeParseResult {
  const ThemeParseResult();
}

/// Тема загружена: возможно, с предупреждениями.
final class ThemeLoaded extends ThemeParseResult {
  const ThemeLoaded(this.theme, this.warnings, this.unsetRoles);

  final ThemeFile theme;
  final List<ThemeIssue> warnings;

  /// Роли, которых файл не задал (справка, не предупреждение).
  final List<ThemeRole> unsetRoles;
}

/// Тема не загружается: клиент берёт запасную.
final class ThemeRejected extends ThemeParseResult {
  const ThemeRejected(this.issue);

  final ThemeIssue issue;
}
