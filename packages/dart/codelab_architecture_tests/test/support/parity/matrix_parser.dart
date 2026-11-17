/// Разбор матрицы целей `docs/architecture/proposals/agent-parity-goals.md`.
///
/// Почему: приёмка этапа 9 держится на строках Must матрицы, а таблицы
/// Markdown легко сломать незаметно: лишний `|` в ячейке сдвигает колонки, и
/// строка перестаёт быть Must (`switch-default-agent-to-dart`, D2). Разбор
/// поэтому громкий: любая неожиданная строка — ошибка с номером строки файла.
///
/// Для чего: даёт `parity_evidence_test` список строк Must с их ячейкой
/// «Критерий приёмки» и итогом Must из сводки §7 — контрольную сумму против
/// потерянной строки.
///
/// Как использовать: `parseMatrix(File(...).readAsStringSync())`. Берутся
/// таблицы §3 с колонкой «Приоритет» (строки `Must`) и таблицы §4.1 с колонкой
/// «Критерий приёмки» (все строки — Must). Подтаблицы «Дано / Когда / Тогда» и
/// §4.2 пропускаются целиком: §4.2 закрывается строками §3 и §4.1 (§7).
/// Ячейки делятся по `|`, не экранированному `\`.
library;

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

const _priorityColumn = 'Приоритет';
const _criterionColumn = 'Критерий приёмки';

/// Делит строку таблицы на ячейки по `|` вне `\|` (D2).
///
/// Крайние `|` отбрасываются; `\|` в ячейке снимается до `|`. Возвращает
/// `null`, если строка не выглядит как строка таблицы.
List<String>? _cells(String line) {
  final text = line.trim();
  if (!text.startsWith('|')) return null;
  var body = text.substring(1);
  if (body.endsWith('|') && !body.endsWith(r'\|')) {
    body = body.substring(0, body.length - 1);
  }
  final cells = <String>[];
  final current = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    final char = body[i];
    if (char == r'\' && i + 1 < body.length && body[i + 1] == '|') {
      current.write('|');
      i++;
    } else if (char == '|') {
      cells.add(current.toString().trim());
      current.clear();
    } else {
      current.write(char);
    }
  }
  cells.add(current.toString().trim());
  return cells;
}

bool _isDelimiter(List<String> cells) =>
    cells.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c));

String _unbold(String cell) => cell.replaceAll('*', '').trim();

/// Разбирает Markdown матрицы целей (D2).
///
/// Бросает [MatrixParseException]: строка таблицы §3 или §4.1 с числом ячеек,
/// отличным от заголовка (приоритет строки не важен), нет сводки §7 или число
/// найденных строк Must не совпадает с её итогом.
ParsedMatrix parseMatrix(String markdown) {
  final lines = markdown.split('\n');
  final rows = <MatrixRow>[];
  int? summaryMust;

  var section = ''; // номер раздела верхнего уровня: `3`, `4`, `7`
  var subsection = ''; // `4.1`, `4.2`
  var inFence = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;

    final heading = RegExp(r'^(#{2,3})\s+(\d+)(?:\.(\d+))?\.').firstMatch(line);
    if (heading != null) {
      if (heading[1] == '##') {
        section = heading[2]!;
        subsection = '';
      } else {
        subsection = '${heading[2]}.${heading[3] ?? ''}';
      }
      continue;
    }

    final headerCells = _cells(line);
    if (headerCells == null) continue;

    // Начало таблицы: строка-заголовок, за ней разделитель. Всё остальное
    // (разделитель, строки данных) разбирает цикл по таблице ниже.
    final next = i + 1 < lines.length ? _cells(lines[i + 1]) : null;
    if (next == null || !_isDelimiter(next)) continue;

    final tableStart = i;
    var end = i + 2;
    while (end < lines.length && lines[end].trim().startsWith('|')) {
      end++;
    }
    i = end - 1; // таблица обработана целиком

    if (section == '7') {
      for (var r = tableStart + 2; r < end; r++) {
        final cells = _cells(lines[r])!;
        if (cells.isNotEmpty && _unbold(cells.first) == 'Итого') {
          if (cells.length < 2) {
            throw MatrixParseException(
              r + 1,
              'the "Итого" row has no Must count',
            );
          }
          summaryMust = int.tryParse(_unbold(cells[1]));
          if (summaryMust == null) {
            throw MatrixParseException(
              r + 1,
              'the Must total "${cells[1]}" is not a number',
            );
          }
        }
      }
      continue;
    }

    final priorityIndex = headerCells.indexOf(_priorityColumn);
    final criterionIndex = headerCells.indexOf(_criterionColumn);
    final isGoals = section == '3' && priorityIndex >= 0;
    final isPreserve = subsection == '4.1' && criterionIndex >= 0;
    if (!isGoals && !isPreserve) continue; // подтаблицы Дано/Когда/Тогда, §4.2

    for (var r = tableStart + 2; r < end; r++) {
      final cells = _cells(lines[r])!;
      if (cells.length != headerCells.length) {
        throw MatrixParseException(
          r + 1,
          'the table row has ${cells.length} cells instead of '
          '${headerCells.length}: check for an unescaped `|` '
          '(escape it as `\\|`)',
        );
      }
      final isMust = isPreserve || _unbold(cells[priorityIndex]) == 'Must';
      if (!isMust) continue;
      rows.add(
        MatrixRow(
          id: cells.first,
          line: r + 1,
          criterion: cells[criterionIndex],
        ),
      );
    }
  }

  if (summaryMust == null) {
    throw const MatrixParseException(
      0,
      'section 7 has no "Итого" summary row with the Must total',
    );
  }
  if (rows.length != summaryMust) {
    throw MatrixParseException(
      0,
      'found ${rows.length} Must rows but the summary of section 7 says '
      '$summaryMust: a row was lost or a table is broken',
    );
  }
  return ParsedMatrix(mustRows: rows, summaryMust: summaryMust);
}
