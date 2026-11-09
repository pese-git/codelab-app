// ЗАГЛУШКА красного шага TDD (задача 1.1 change `switch-default-agent-to-dart`).
// Настоящая реализация — задача 1.2 (design.md, D2). Сигнатуры зафиксированы
// тестом `matrix_parser_test.dart`; тела бросают `UnimplementedError`, чтобы
// тесты падали по смыслу, а не из-за ошибки компиляции.

/// Строка матрицы целей, прошедшая отбор по приоритету Must (D2).
class MatrixRow {
  const MatrixRow({
    required this.id,
    required this.line,
    required this.criterion,
  });

  /// Идентификатор строки (`R-08`).
  final String id;

  /// Номер строки файла матрицы, с 1.
  final int line;

  /// Ячейка «Критерий приёмки» с уже снятым экранированием `\|`.
  final String criterion;
}

/// Результат разбора матрицы.
class ParsedMatrix {
  const ParsedMatrix({required this.mustRows, required this.summaryMust});

  /// Строки Must из таблиц §3 и все строки таблицы §4.1, в порядке файла.
  final List<MatrixRow> mustRows;

  /// Итог Must из сводки §7.
  final int summaryMust;
}

/// Ошибка разбора матрицы с номером строки файла (D2).
class MatrixParseException implements Exception {
  const MatrixParseException(this.line, this.message);

  /// Номер строки файла, с 1; 0 — ошибка не привязана к строке.
  final int line;

  /// Описание ошибки.
  final String message;

  @override
  String toString() => 'MatrixParseException(line $line): $message';
}

/// Разбирает Markdown матрицы целей (D2).
ParsedMatrix parseMatrix(String markdown) =>
    throw UnimplementedError('parseMatrix: задача 1.2');
