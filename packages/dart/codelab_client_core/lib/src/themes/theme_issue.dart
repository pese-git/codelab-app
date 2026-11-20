/// Проблема разбора темы: код, позиция и аргументы без текста (D2).
///
/// Почему: ядро клиента языконезависимо (spec app-settings «Локализация
/// интерфейса app»), поэтому проблема — данные, а текст строит клиент: app по
/// ARB, CLI — своими строками.
///
/// Как использовать: [ThemeIssueCode.isWarning] отличает предупреждения
/// (тема применяется) от ошибок (тема не загружается).
library;

/// Код проблемы разбора темы (spec `client-themes`).
///
/// Почему: ядро языконезависимо, клиент по коду выбирает свой текст.
///
/// Как использовать: коды до `terminalColor` включительно — предупреждения
/// ([isWarning]), остальные отклоняют тему.
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
  invalidValue;

  /// Предупреждение: тема применяется, проблема только сообщается.
  bool get isWarning => index <= terminalColor.index;
}

/// Проблема разбора: код, позиция и аргументы для текста клиента.
///
/// Как использовать: создаёт разбор; клиент по [code] подставляет [key],
/// [value], [hint] в строку ARB или CLI. Значения из файла — недоверенный
/// текст: перед показом их экранируют.
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

  @override
  bool operator ==(Object other) =>
      other is ThemeIssue &&
      other.code == code &&
      other.line == line &&
      other.column == column &&
      other.key == key &&
      other.value == value &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(code, line, column, key, value, hint);

  // Только для диагностики: человекочитаемый текст строит клиент (D2).
  @override
  String toString() =>
      'ThemeIssue(${code.name} $line:$column key=$key value=$value hint=$hint)';
}
