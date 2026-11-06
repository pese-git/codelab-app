import '../input/key_decoder.dart';
import '../render/sanitize.dart';
import 'line_field.dart';

export 'line_field.dart' show LineKey, keyRejectedLine, maxKeyBytes;

/// Поле ввода построчного режима: [LineField] плюс отрисовка в `StringSink`.
///
/// Почему отдельный файл: мастер провайдера, первый запуск и подтверждение
/// сводки флаговой формы вводят строки одинаково (U-17), а правила поля —
/// в чистом [LineField], общем с оверлеем TUI (design.md change
/// `add-provider-setup-ui`, D15, D16, D17).
///
/// Для чего: хранит текущее [field] и число экранных строк прошлой
/// отрисовки. Значение живёт только в поле (SETUP-1); [clear] обязателен при
/// отправке, отмене и закрытии (D17).
///
/// Как использовать: [applyLineKey] на каждую клавишу, затем [draw] с
/// `redraw: true`. Длинное значение переносится на несколько экранных строк,
/// поэтому [draw] стирает все перенесённые строки прежней отрисовки.
final class PromptLine {
  PromptLine({required this.prompt, String initial = '', bool hidden = false})
    : field = LineField.initial(initial, hidden: hidden);

  final String prompt;
  LineField field;

  /// Сколько экранных строк заняла прошлая отрисовка.
  var _rows = 1;

  bool get hidden => field.hidden;
  String get text => field.text;
  String get shown => field.shown;
  bool get rejected => field.rejected;

  void clear() => field = field.cleared();

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

/// Применяет [event] к [line] (см. `applyFieldKey`).
LineKey applyLineKey(PromptLine line, KeyEvent event) {
  final (next, key) = applyFieldKey(line.field, event);
  line.field = next;
  return key;
}
