import 'dart:convert';

import '../input/key_decoder.dart';
import '../render/sanitize.dart';

/// Однострочное поле ввода: буфер, маска ключа и перерисовка.
///
/// Почему отдельный файл: мастер провайдера, первый запуск и подтверждение
/// сводки флаговой формы вводят строки одинаково (U-17), и разбор клавиш не
/// должен дублироваться (design.md change `add-provider-setup-ui`, D15, D16).
///
/// Для чего: [hidden] — поле ключа: на экране `*` по числу рун, Ctrl+R
/// показывает и прячет значение; Ctrl+U очищает. Значение живёт только в
/// буфере и в событии автомата (SETUP-1); [clear] обязателен при отправке,
/// отмене и закрытии (D17).
///
/// Как использовать: [applyLineKey] на каждую клавишу, затем [draw] с
/// `redraw: true`. Длинное значение переносится на несколько экранных строк,
/// поэтому [draw] стирает все перенесённые строки прежней отрисовки.
/// Предел значения секрета в байтах: как `maxSecretValueBytes` у
/// `StdinSecretInput` (`codelab_agent_io`, D14).
const maxKeyBytes = 64 * 1024;

final class PromptLine {
  PromptLine({required this.prompt, String initial = '', this.hidden = false})
    : _text = _clean(initial).runes.toList();

  final String prompt;
  final bool hidden;
  var revealed = false;
  List<int> _text;

  /// В скрытое поле вставили несколько строк или значение длиннее
  /// [maxKeyBytes]: значение отклоняется целиком, без цитирования (D14).
  var rejected = false;
  var _bytes = 0;

  /// Сколько экранных строк заняла прошлая отрисовка.
  var _rows = 1;

  String get text => String.fromCharCodes(_text);

  /// Что показывать: значение или `*` по числу рун. Управляющие символы
  /// вырезаны: значение пришло от человека, пресета или конфига.
  String get shown =>
      hidden && !revealed ? '*' * _text.length : String.fromCharCodes(_text);

  static String _clean(String value) => String.fromCharCodes(
    value.runes.where(
      (r) => r >= 0x20 && r != 0x7f && !(r >= 0x80 && r < 0xa0),
    ),
  );

  void insert(String value) {
    if (hidden && (value.contains('\n') || value.contains('\r'))) {
      rejected = true;
    }
    for (final rune in _clean(value).runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (hidden && _bytes + size > maxKeyBytes) {
        rejected = true;
        continue;
      }
      _bytes += size;
      _text.add(rune);
    }
  }

  void backspace() {
    if (_text.isNotEmpty) {
      _bytes -= utf8.encode(String.fromCharCode(_text.removeLast())).length;
    }
  }

  void clear() {
    _text = [];
    _bytes = 0;
    rejected = false;
  }

  /// Рисует строку в [out]; с [redraw] сначала стирает прежнюю (все её
  /// экранные строки при ширине [columns]).
  void draw(StringSink out, {required int columns, bool redraw = false}) {
    if (redraw) {
      out.write(_rows > 1 ? '\x1b[${_rows - 1}A' : '');
      out.write('\r\x1b[J');
    }
    final line = sanitizeTerminalText('$prompt$shown');
    out.write(line);
    final length = line.runes.length;
    _rows = length == 0 || columns <= 0 ? 1 : (length - 1) ~/ columns + 1;
  }
}

/// Что сделала клавиша с полем.
enum LineKey { edited, submit, cancel, multiline, ignored }

/// Применяет [event] к [line]: ввод, Backspace, Ctrl+U, Ctrl+R (только у
/// скрытого поля), Enter и отмена (Ctrl+C, Esc, Ctrl+D).
LineKey applyLineKey(PromptLine line, KeyEvent event) {
  switch (event) {
    case TextKey(:final text):
      line.insert(text);
      return line.rejected ? LineKey.multiline : LineKey.edited;
    case SpecialKey(:final key):
      switch (key) {
        case Key.enter:
          return LineKey.submit;
        // Перевод строки внутри ключа — вставка нескольких строк (D14).
        case Key.ctrlJ || Key.altEnter || Key.shiftEnter when line.hidden:
          return LineKey.multiline;
        case Key.ctrlC || Key.escape || Key.ctrlD:
          return LineKey.cancel;
        case Key.backspace:
          line.backspace();
          return LineKey.edited;
        case Key.ctrlU:
          line.clear();
          return LineKey.edited;
        case Key.ctrlR when line.hidden:
          line.revealed = !line.revealed;
          return LineKey.edited;
        case _:
          return LineKey.ignored;
      }
  }
}

/// Строка о отклонённом ключе: без значения и без его длины (D14).
const keyRejectedLine =
    'The key must be a single line of at most 64 KiB; enter it again.';
