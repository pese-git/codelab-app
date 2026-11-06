import 'dart:convert';

import '../input/key_decoder.dart';

/// Предел значения секрета в байтах: как `maxSecretValueBytes` у
/// `StdinSecretInput` (`codelab_agent_io`, D14).
const maxKeyBytes = 64 * 1024;

/// Строка о отклонённом ключе: без значения и без его длины (D14).
const keyRejectedLine =
    'The key must be a single line of at most 64 KiB; enter it again.';

/// Что сделала клавиша с полем.
enum LineKey { edited, submit, cancel, multiline, ignored }

/// Неизменяемое однострочное поле ввода: руны, маска ключа, отказ вставки.
///
/// Почему неизменяемое и без вывода: одно поле нужно и построчному мастеру
/// (`PromptLine`), и оверлею `--ui tui`, чьё ядро — чистые функции
/// `reduce`/`render` без побочных эффектов (TUI-5); второй копии разбора
/// клавиш быть не должно (design.md change `add-provider-setup-ui`, D17).
///
/// Для чего: [hidden] — поле ключа: на экране `*` по числу рун
/// ([shown]), Ctrl+R показывает и прячет ([revealed]), Ctrl+U очищает.
/// [rejected] — вставили несколько строк или значение длиннее [maxKeyBytes]:
/// вызывающий очищает поле и показывает [keyRejectedLine] (D14). Значение
/// живёт только в рунах поля (SETUP-1); `toString` его не содержит.
///
/// Как использовать: `applyFieldKey(field, event)` на каждую клавишу и
/// `field.pasted(text)` на вставку; результат — новое поле.
final class LineField {
  const LineField({
    this.runes = const [],
    this.hidden = false,
    this.revealed = false,
    this.rejected = false,
    this.bytes = 0,
  });

  /// Поле с начальным значением [initial] (управляющие символы вырезаны).
  factory LineField.initial(String initial, {bool hidden = false}) {
    final runes = _clean(initial).runes.toList();
    return LineField(
      runes: runes,
      hidden: hidden,
      bytes: utf8.encode(String.fromCharCodes(runes)).length,
    );
  }

  final List<int> runes;
  final bool hidden;
  final bool revealed;
  final bool rejected;
  final int bytes;

  bool get isEmpty => runes.isEmpty;

  /// Значение поля.
  String get text => String.fromCharCodes(runes);

  /// Что показывать: значение или `*` по числу рун.
  String get shown =>
      hidden && !revealed ? '*' * runes.length : String.fromCharCodes(runes);

  static String _clean(String value) => String.fromCharCodes(
    value.runes.where(
      (r) => r >= 0x20 && r != 0x7f && !(r >= 0x80 && r < 0xa0),
    ),
  );

  LineField _copy({
    List<int>? runes,
    bool? revealed,
    bool? rejected,
    int? bytes,
  }) => LineField(
    runes: runes ?? this.runes,
    hidden: hidden,
    revealed: revealed ?? this.revealed,
    rejected: rejected ?? this.rejected,
    bytes: bytes ?? this.bytes,
  );

  /// Ввод или вставка [value]. У скрытого поля перевод строки и превышение
  /// [maxKeyBytes] отклоняют значение целиком ([rejected]).
  LineField pasted(String value) {
    var reject = rejected;
    if (hidden && (value.contains('\n') || value.contains('\r'))) {
      reject = true;
    }
    final next = [...runes];
    var total = bytes;
    for (final rune in _clean(value).runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (hidden && total + size > maxKeyBytes) {
        reject = true;
        continue;
      }
      total += size;
      next.add(rune);
    }
    return _copy(runes: next, bytes: total, rejected: reject);
  }

  LineField backspace() {
    if (runes.isEmpty) {
      return this;
    }
    final last = runes.last;
    return _copy(
      runes: runes.sublist(0, runes.length - 1),
      bytes: bytes - utf8.encode(String.fromCharCode(last)).length,
    );
  }

  /// Пустое поле: сбрасывает значение и отказ; показ ([revealed]) остаётся
  /// выбором человека (Ctrl+U не прячет значение).
  LineField cleared() => LineField(hidden: hidden, revealed: revealed);

  LineField toggleReveal() => _copy(revealed: !revealed);

  @override
  String toString() => 'LineField(${runes.length} runes, hidden: $hidden)';
}

/// Применяет [event] к [field]: ввод, Backspace, Ctrl+U, Ctrl+R (только у
/// скрытого поля), Enter и отмена (Ctrl+C, Esc, Ctrl+D). Возвращает новое
/// поле и что произошло; при [LineKey.multiline] вызывающий очищает поле и
/// показывает [keyRejectedLine].
(LineField, LineKey) applyFieldKey(LineField field, KeyEvent event) {
  switch (event) {
    case TextKey(:final text):
      final next = field.pasted(text);
      return (next, next.rejected ? LineKey.multiline : LineKey.edited);
    case SpecialKey(:final key):
      switch (key) {
        case Key.enter:
          return (field, LineKey.submit);
        // Перевод строки внутри ключа — вставка нескольких строк (D14).
        case Key.ctrlJ || Key.altEnter || Key.shiftEnter when field.hidden:
          return (field, LineKey.multiline);
        case Key.ctrlC || Key.escape || Key.ctrlD:
          return (field, LineKey.cancel);
        case Key.backspace:
          return (field.backspace(), LineKey.edited);
        case Key.ctrlU:
          return (field.cleared(), LineKey.edited);
        case Key.ctrlR when field.hidden:
          return (field.toggleReveal(), LineKey.edited);
        case _:
          return (field, LineKey.ignored);
      }
  }
}
