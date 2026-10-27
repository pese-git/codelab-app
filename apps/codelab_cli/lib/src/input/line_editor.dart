import 'history.dart';

/// Модель строки ввода REPL: буфер, курсор, многострочность, история.
///
/// Почему: правка строки — логика, которую надо проверять без терминала;
/// перерисовку делает REPL по [text] и [cursor] (design.md change
/// `add-codelab-cli`, D5).
///
/// Для чего: буфер — список кодовых точек, поэтому курсор и удаление
/// работают с целыми символами, а не с половинами UTF-16 (эмодзи); [cursor]
/// — позиция в кодовых точках. Home/End — начало и конец текущей строки
/// многострочного ввода.
///
/// Как использовать: REPL переводит действия `KeyBindings` в вызовы
/// методов; [submit] — Enter: `null`, если строка кончалась `\` (Enter стал
/// переводом строки), иначе отправляемый текст.
final class LineEditor {
  LineEditor(this.history);

  final History history;

  var _runes = <int>[];
  var _cursor = 0;

  /// Позиция в истории при ↑/↓: `null` — правится свой черновик.
  int? _historyIndex;
  var _draft = <int>[];

  String get text => String.fromCharCodes(_runes);

  int get cursor => _cursor;

  bool get isEmpty => _runes.isEmpty;

  void insert(String text) {
    final runes = text.runes.toList();
    _runes.insertAll(_cursor, runes);
    _cursor += runes.length;
  }

  void insertNewline() => insert('\n');

  void deleteBackward() {
    if (_cursor == 0) {
      return;
    }
    _runes.removeAt(--_cursor);
  }

  void deleteForward() {
    if (_cursor < _runes.length) {
      _runes.removeAt(_cursor);
    }
  }

  void deleteToStart() {
    _runes.removeRange(0, _cursor);
    _cursor = 0;
  }

  void moveLeft() {
    if (_cursor > 0) {
      _cursor--;
    }
  }

  void moveRight() {
    if (_cursor < _runes.length) {
      _cursor++;
    }
  }

  void moveHome() {
    var i = _cursor;
    while (i > 0 && _runes[i - 1] != 0x0a) {
      i--;
    }
    _cursor = i;
  }

  void moveEnd() {
    var i = _cursor;
    while (i < _runes.length && _runes[i] != 0x0a) {
      i++;
    }
    _cursor = i;
  }

  /// Заменяет буфер текстом [text], курсор — в конец (Tab-дополнение).
  void setText(String text) {
    _runes = text.runes.toList();
    _cursor = _runes.length;
    _historyIndex = null;
  }

  void clear() {
    _runes = [];
    _cursor = 0;
    _historyIndex = null;
  }

  /// Enter: `\` в конце строки заменяется переводом строки (запасной путь
  /// многострочного ввода в любом терминале, §9.11), иначе текст уходит —
  /// буфер очищается, непустой текст попадает в историю.
  String? submit() {
    if (_runes.isNotEmpty && _runes.last == 0x5c && _cursor == _runes.length) {
      _runes.removeLast();
      _cursor--;
      insertNewline();
      return null;
    }
    final value = text;
    clear();
    history.add(value);
    return value.trim().isEmpty ? '' : value;
  }

  void historyPrevious() {
    final entries = history.entries;
    if (entries.isEmpty) {
      return;
    }
    final index = _historyIndex;
    if (index == null) {
      _draft = [..._runes];
      _show(entries.length - 1, entries);
    } else if (index > 0) {
      _show(index - 1, entries);
    }
  }

  void historyNext() {
    final index = _historyIndex;
    if (index == null) {
      return;
    }
    final entries = history.entries;
    if (index + 1 < entries.length) {
      _show(index + 1, entries);
    } else {
      _historyIndex = null;
      _runes = [..._draft];
      _cursor = _runes.length;
    }
  }

  void _show(int index, List<String> entries) {
    _historyIndex = index;
    _runes = entries[index].runes.toList();
    _cursor = _runes.length;
  }
}
