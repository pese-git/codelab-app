/// Значение цвета роли темы (spec `client-themes`, «Формат файла»).
///
/// Почему: файл темы общий для app и CLI, а цвет в нём бывает и RGB, и
/// терминальным (ANSI, 256 цветов); ядро клиента хранит вид значения, а
/// превращение в цвет (RGB для app, понижение глубины для CLI) — забота
/// потребителя (design.md change `add-app-appearance-page`, D2).
///
/// Как использовать: [ThemeColorValue.tryParse] разбирает строку файла;
/// `null` — строка не по формату (`invalidValue`).
library;

/// Вид значения цвета роли: RGB, «из базы», ANSI или индекс 256 цветов.
///
/// Как использовать: приходит из [ThemeColorValue.tryParse] и из карты ролей
/// темы; `switch` по закрытой иерархии. Терминальные виды app не применяет.
sealed class ThemeColorValue {
  const ThemeColorValue();

  static final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');
  static final _indexed = RegExp(r'^256:(0|[1-9][0-9]{0,2})$');
  static const _ansiBase = [
    'black',
    'red',
    'green',
    'yellow',
    'blue',
    'magenta',
    'cyan',
    'white',
  ];
  static final _ansiNames = {
    ..._ansiBase,
    for (final n in _ansiBase) 'bright_$n',
  };

  /// Разбор строки формата: `#rrggbb` (любой регистр), `default`, имя ANSI,
  /// `256:<n>` с целым `n` от 0 до 255; иное — `null`.
  static ThemeColorValue? tryParse(String text) {
    if (_hex.hasMatch(text)) {
      return Rgb(int.parse(text.substring(1), radix: 16));
    }
    if (text == 'default') return const DefaultColor();
    if (_ansiNames.contains(text)) return AnsiColor(text);
    if (_indexed.hasMatch(text)) {
      final n = int.parse(text.substring(4));
      if (n <= 255) return IndexedColor(n);
    }
    return null;
  }
}

/// `#rrggbb`: [value] — 24 бита RGB. Единственный вид, который app применяет.
final class Rgb extends ThemeColorValue {
  const Rgb(this.value);

  final int value;

  @override
  bool operator ==(Object other) => other is Rgb && other.value == value;

  @override
  int get hashCode => Object.hash(Rgb, value);

  @override
  String toString() => 'Rgb(0x${value.toRadixString(16).padLeft(6, '0')})';
}

/// `default` — «роль из `extends`»; так же помечена роль, которую файл не
/// задал или задал терминальным цветом.
final class DefaultColor extends ThemeColorValue {
  const DefaultColor();

  @override
  bool operator ==(Object other) => other is DefaultColor;

  @override
  int get hashCode => (DefaultColor).hashCode;

  @override
  String toString() => 'DefaultColor()';
}

/// Один из 16 цветов ANSI: [name] — `red`, `bright_red`. Для CLI; app даёт
/// предупреждение `terminalColor`.
final class AnsiColor extends ThemeColorValue {
  const AnsiColor(this.name);

  final String name;

  @override
  bool operator ==(Object other) => other is AnsiColor && other.name == name;

  @override
  int get hashCode => Object.hash(AnsiColor, name);

  @override
  String toString() => 'AnsiColor($name)';
}

/// `256:<n>`, [index] от 0 до 255. Для CLI; app даёт предупреждение
/// `terminalColor`.
final class IndexedColor extends ThemeColorValue {
  const IndexedColor(this.index);

  final int index;

  @override
  bool operator ==(Object other) =>
      other is IndexedColor && other.index == index;

  @override
  int get hashCode => Object.hash(IndexedColor, index);

  @override
  String toString() => 'IndexedColor($index)';
}
