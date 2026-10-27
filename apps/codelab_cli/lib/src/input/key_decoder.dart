import 'dart:async';

/// Специальная клавиша терминала.
///
/// [label] — подпись клавиши в `/help keys` (§12.2.11, TUI-7).
enum Key {
  enter('Enter'),
  altEnter('Alt+Enter'),
  ctrlJ('Ctrl+J'),
  tab('Tab'),
  backspace('Backspace'),
  delete('Delete'),
  escape('Esc'),
  up('Up'),
  down('Down'),
  left('Left'),
  right('Right'),
  home('Home'),
  end('End'),
  ctrlA('Ctrl+A'),
  ctrlC('Ctrl+C'),
  ctrlD('Ctrl+D'),
  ctrlE('Ctrl+E'),
  ctrlL('Ctrl+L'),
  ctrlU('Ctrl+U');

  const Key(this.label);

  final String label;
}

/// Событие клавиатуры: вставленный текст или специальная клавиша.
sealed class KeyEvent {
  const KeyEvent();
}

/// Печатаемый текст одного чтения: набранные символы или вставка.
final class TextKey extends KeyEvent {
  const TextKey(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is TextKey && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TextKey($text)';
}

final class SpecialKey extends KeyEvent {
  const SpecialKey(this.key);

  final Key key;

  @override
  bool operator ==(Object other) => other is SpecialKey && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'SpecialKey(${key.name})';
}

/// Таймер декодера; тесты подменяют его ручными часами.
typedef StartTimer =
    Timer Function(Duration duration, void Function() callback);

/// Превращает байты stdin в raw-режиме в [KeyEvent].
///
/// Почему: терминал шлёт клавиши байтами — UTF-8, управляющими кодами и
/// последовательностями `ESC [` / `ESC O`, — и чтение может разрезать любую
/// из них. Одиночный Esc отличается от начала последовательности только
/// паузой (design.md change `add-codelab-cli`, D5).
///
/// Для чего: единственное место разбора ввода; дальше REPL работает с
/// клавишами через таблицу `KeyBindings`.
///
/// Как использовать: `KeyDecoder(onKey)`, затем [add] на каждое чтение
/// stdin и [close] в конце ввода. Esc без продолжения становится
/// [Key.escape] через [escapeTimeout]; `ESC CR` — [Key.altEnter]; Esc с
/// другим байтом — Esc и этот байт. Неизвестная CSI-последовательность
/// отбрасывается целиком, неверный UTF-8 даёт `U+FFFD`.
final class KeyDecoder {
  KeyDecoder(
    this._onKey, {
    Duration escapeTimeout = const Duration(milliseconds: 50),
    StartTimer? startTimer,
  }) : _escapeTimeout = escapeTimeout,
       _startTimer = startTimer ?? Timer.new;

  final void Function(KeyEvent key) _onKey;
  final Duration _escapeTimeout;
  final StartTimer _startTimer;

  /// Байты незаконченной последовательности: начало ESC-последовательности
  /// или UTF-8-символа, разрезанного между чтениями.
  final _pending = <int>[];
  Timer? _escapeTimer;
  final _text = StringBuffer();

  void add(List<int> bytes) {
    _escapeTimer?.cancel();
    _escapeTimer = null;
    _pending.addAll(bytes);
    _drain();
    _flushText();
    if (_pending.length == 1 && _pending.first == 0x1b) {
      _escapeTimer = _startTimer(_escapeTimeout, _flushEscape);
    }
  }

  /// Конец ввода: ожидающий Esc становится клавишей, обрывок — отброшен.
  void close() {
    _escapeTimer?.cancel();
    _escapeTimer = null;
    if (_pending.isNotEmpty && _pending.first == 0x1b) {
      _onKey(const SpecialKey(Key.escape));
    }
    _pending.clear();
  }

  void _flushEscape() {
    _escapeTimer = null;
    if (_pending.length == 1 && _pending.first == 0x1b) {
      _pending.clear();
      _onKey(const SpecialKey(Key.escape));
    }
  }

  /// Разбирает [_pending], оставляя в нём только незаконченный хвост.
  void _drain() {
    var i = 0;
    while (i < _pending.length) {
      final consumed = _decodeAt(i);
      if (consumed == 0) {
        break;
      }
      i += consumed;
    }
    _pending.removeRange(0, i);
  }

  /// Сколько байтов с [i] составили одно событие; `0` — нужно ещё чтение.
  int _decodeAt(int i) {
    final byte = _pending[i];
    if (byte == 0x1b) {
      return _decodeEscape(i);
    }
    if (byte < 0x20 || byte == 0x7f) {
      final key = _controlKeys[byte];
      if (key != null) {
        _emit(SpecialKey(key));
      }
      return 1;
    }
    if (byte < 0x80) {
      _text.writeCharCode(byte);
      return 1;
    }
    return _decodeUtf8(i);
  }

  int _decodeEscape(int i) {
    if (i + 1 >= _pending.length) {
      return 0;
    }
    final next = _pending[i + 1];
    if (next == 0x0d) {
      _emit(const SpecialKey(Key.altEnter));
      return 2;
    }
    if (next == 0x5b) {
      return _decodeCsi(i);
    }
    if (next == 0x4f) {
      if (i + 2 >= _pending.length) {
        return 0;
      }
      final key = _ss3Keys[_pending[i + 2]];
      if (key != null) {
        _emit(SpecialKey(key));
      }
      return 3;
    }
    _emit(const SpecialKey(Key.escape));
    return 1;
  }

  /// `ESC [ <параметры> <финальный байт 0x40–0x7E>`.
  int _decodeCsi(int i) {
    for (var j = i + 2; j < _pending.length; j++) {
      final byte = _pending[j];
      if (byte >= 0x40 && byte <= 0x7e) {
        final params = String.fromCharCodes(_pending.sublist(i + 2, j));
        final key = byte == 0x7e
            ? _tildeKeys[params]
            : (params.isEmpty ? _csiKeys[byte] : null);
        if (key != null) {
          _emit(SpecialKey(key));
        }
        return j - i + 1;
      }
    }
    return 0;
  }

  int _decodeUtf8(int i) {
    final lead = _pending[i];
    final length = lead >= 0xf8
        ? 0
        : lead >= 0xf0
        ? 4
        : lead >= 0xe0
        ? 3
        : lead >= 0xc0
        ? 2
        : 0;
    if (length == 0) {
      _text.writeCharCode(0xfffd);
      return 1;
    }
    for (var k = 1; k < length; k++) {
      if (i + k >= _pending.length) {
        return 0;
      }
      if (_pending[i + k] & 0xc0 != 0x80) {
        _text.writeCharCode(0xfffd);
        return k;
      }
    }
    var rune = lead & (0xff >> (length + 1));
    for (var k = 1; k < length; k++) {
      rune = (rune << 6) | (_pending[i + k] & 0x3f);
    }
    _text.writeCharCode(rune);
    return length;
  }

  /// Специальная клавиша обрывает накопленный текст: порядок событий тот
  /// же, что у байтов.
  void _emit(KeyEvent key) {
    _flushText();
    _onKey(key);
  }

  void _flushText() {
    if (_text.isEmpty) {
      return;
    }
    final text = _text.toString();
    _text.clear();
    _onKey(TextKey(text));
  }

  static const _controlKeys = {
    0x01: Key.ctrlA,
    0x03: Key.ctrlC,
    0x04: Key.ctrlD,
    0x05: Key.ctrlE,
    0x08: Key.backspace,
    0x09: Key.tab,
    0x0a: Key.ctrlJ,
    0x0c: Key.ctrlL,
    0x0d: Key.enter,
    0x15: Key.ctrlU,
    0x7f: Key.backspace,
  };

  static const _csiKeys = {
    0x41: Key.up,
    0x42: Key.down,
    0x43: Key.right,
    0x44: Key.left,
    0x46: Key.end,
    0x48: Key.home,
  };

  static const _ss3Keys = _csiKeys;

  static const _tildeKeys = {
    '1': Key.home,
    '3': Key.delete,
    '4': Key.end,
    '7': Key.home,
    '8': Key.end,
  };
}
