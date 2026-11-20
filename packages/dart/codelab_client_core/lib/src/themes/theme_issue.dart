/// Проблема разбора темы: код, позиция и аргументы без текста (D2).
///
/// ЗАГЛУШКА красного теста 1.3: равенство значений — задача 1.4.
library;

enum ThemeIssueCode {
  // Предупреждения: тема применяется.
  unknownKey,
  duplicateKey,
  terminalColor,
  // Ошибки: тема не загружается.
  tooLarge,
  notUtf8,
  invalidJson,
  notAnObject,
  missingName,
  invalidName,
  nameMismatch,
  reservedName,
  invalidExtends,
  invalidValue,
}

final class ThemeIssue {
  const ThemeIssue(
    this.code, {
    required this.line,
    required this.column,
    this.key,
    this.value,
    this.hint,
  });

  final ThemeIssueCode code;

  /// Строка и колонка с 1.
  final int line;
  final int column;

  /// Ключ (`accent`, `code.keyword`), к которому относится проблема.
  final String? key;

  /// Значение, вызвавшее проблему.
  final String? value;

  /// Подсказка: ближайшая роль области для `unknownKey` (`accent`).
  final String? hint;
}
