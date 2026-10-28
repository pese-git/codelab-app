/// Многострочный композер полноэкранного режима.
///
/// Почему: в TUI промпт редактируется на месте, как в редакторе: курсор
/// ходит по строкам, вставка попадает целиком, а история общая с REPL
/// (spec codelab-tui «Композер TUI», «Вставка в TUI»; design.md change
/// `add-cli-tui`, D8). Строковый `LineEditor` REPL так не умеет: у него одна
/// логическая строка и курсор только по ней.
///
/// Для чего: неизменяемое состояние — строки, курсор `(row, column)` в
/// рунах, история и позиция в ней. Каждая операция возвращает новое
/// состояние; ввод-вывода нет (TUI-5).
///
/// Как использовать: `reduce` вызывает операции по действиям реестра
/// клавиш; [submit] отдаёт текст и чистое состояние с записью в историю, а
/// `\` в конце строки перед Enter превращает в перевод строки (§12.2.9,
/// шаг 5). [up] и [down] на первой и последней строке листают историю.
final class ComposerState {
  const ComposerState({
    this.lines = const [''],
    this.row = 0,
    this.column = 0,
    this.history = const [],
    this.historyIndex,
    this.draft = '',
  });

  final List<String> lines;
  final int row;
  final int column;

  /// Отправленные промпты, старые первыми (`$CODELAB_HOME/cli_history`).
  final List<String> history;

  /// Показанная запись истории; `null` — свой черновик.
  final int? historyIndex;

  /// Черновик, который был до листания истории.
  final String draft;

  /// Предел записей — как у `History` REPL.
  static const _historyLimit = 1000;

  String get text => lines.join('\n');

  bool get isEmpty => lines.length == 1 && lines.first.isEmpty;

  ComposerState _with({
    List<String>? lines,
    int? row,
    int? column,
    List<String>? history,
    int? Function()? historyIndex,
    String? draft,
  }) => ComposerState(
    lines: lines ?? this.lines,
    row: row ?? this.row,
    column: column ?? this.column,
    history: history ?? this.history,
    historyIndex: historyIndex == null ? this.historyIndex : historyIndex(),
    draft: draft ?? this.draft,
  );

  List<int> get _line => lines[row].runes.toList();

  /// Текст [value] на месте курсора; переводы строк делят строки.
  ComposerState insert(String value) {
    final runes = _line;
    final before = String.fromCharCodes(runes.take(column));
    final after = String.fromCharCodes(runes.skip(column));
    final parts = '$before$value'.split('\n');
    final next = [
      ...lines.take(row),
      ...parts.take(parts.length - 1),
      '${parts.last}$after',
      ...lines.skip(row + 1),
    ];
    return _with(
      lines: next,
      row: row + parts.length - 1,
      column: parts.last.runes.length,
      historyIndex: () => null,
    );
  }

  /// Вставка из буфера: `\r\n` и `\r` — `\n`, управляющие символы, кроме
  /// `\n` и `\t`, удаляются; промпт не отправляется (TUI-3).
  ComposerState paste(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final clean = String.fromCharCodes(
      normalized.runes.where(
        (rune) =>
            rune == 0x0a ||
            rune == 0x09 ||
            !(rune < 0x20 || (rune >= 0x7f && rune <= 0x9f)),
      ),
    );
    return insert(clean);
  }

  ComposerState newline() => insert('\n');

  ComposerState deleteBackward() {
    if (column > 0) {
      final runes = _line..removeAt(column - 1);
      return _replaceLine(String.fromCharCodes(runes), column - 1);
    }
    if (row == 0) {
      return this;
    }
    final previous = lines[row - 1];
    return _with(
      lines: [
        ...lines.take(row - 1),
        '$previous${lines[row]}',
        ...lines.skip(row + 1),
      ],
      row: row - 1,
      column: previous.runes.length,
    );
  }

  ComposerState deleteForward() {
    final runes = _line;
    if (column < runes.length) {
      runes.removeAt(column);
      return _replaceLine(String.fromCharCodes(runes), column);
    }
    if (row == lines.length - 1) {
      return this;
    }
    return _with(
      lines: [
        ...lines.take(row),
        '${lines[row]}${lines[row + 1]}',
        ...lines.skip(row + 2),
      ],
    );
  }

  /// Ctrl+U: удалить от начала строки до курсора.
  ComposerState deleteToStart() =>
      _replaceLine(String.fromCharCodes(_line.skip(column)), 0);

  ComposerState _replaceLine(String line, int column) => _with(
    lines: [...lines.take(row), line, ...lines.skip(row + 1)],
    column: column,
  );

  ComposerState moveLeft() {
    if (column > 0) {
      return _with(column: column - 1);
    }
    return row > 0
        ? _with(row: row - 1, column: lines[row - 1].runes.length)
        : this;
  }

  ComposerState moveRight() {
    if (column < _line.length) {
      return _with(column: column + 1);
    }
    return row < lines.length - 1 ? _with(row: row + 1, column: 0) : this;
  }

  ComposerState moveHome() => _with(column: 0);

  ComposerState moveEnd() => _with(column: _line.length);

  ComposerState clear() =>
      ComposerState(history: history, historyIndex: null, draft: '');

  /// ↑: строкой выше, а на первой строке — предыдущая запись истории.
  ComposerState up() {
    if (row > 0) {
      final target = lines[row - 1].runes.length;
      return _with(row: row - 1, column: column < target ? column : target);
    }
    final index = historyIndex ?? history.length;
    if (index == 0) {
      return this;
    }
    return _showHistory(index - 1, draft: historyIndex == null ? text : draft);
  }

  /// ↓: строкой ниже, а на последней — следующая запись или черновик.
  ComposerState down() {
    if (row < lines.length - 1) {
      final target = lines[row + 1].runes.length;
      return _with(row: row + 1, column: column < target ? column : target);
    }
    final index = historyIndex;
    if (index == null) {
      return this;
    }
    if (index + 1 >= history.length) {
      return _setText(draft)._with(historyIndex: () => null, draft: '');
    }
    return _showHistory(index + 1, draft: draft);
  }

  ComposerState _showHistory(int index, {required String draft}) =>
      _setText(history[index])._with(historyIndex: () => index, draft: draft);

  ComposerState _setText(String value) {
    final next = value.split('\n');
    return _with(
      lines: next,
      row: next.length - 1,
      column: next.last.runes.length,
    );
  }

  /// Enter: `(состояние, текст)`. Пустой текст — `null` и ничего не
  /// меняется; `\` в конце строки на курсоре — перевод строки и `null`.
  (ComposerState, String?) submit() {
    final line = lines[row];
    if (line.endsWith(r'\') && column == line.runes.length) {
      return (
        _replaceLine(line.substring(0, line.length - 1), column - 1).newline(),
        null,
      );
    }
    final value = text;
    if (value.trim().isEmpty) {
      return (this, null);
    }
    // То же правило, что у `History` REPL: повтор последней записи не
    // пишется — файл истории общий.
    final recorded = history.isNotEmpty && history.last == value
        ? history
        : [...history, value];
    return (
      ComposerState(
        history: recorded.length > _historyLimit
            ? recorded.sublist(recorded.length - _historyLimit)
            : recorded,
      ),
      value,
    );
  }
}
