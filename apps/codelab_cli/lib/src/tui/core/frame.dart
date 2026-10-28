/// Кадр полноэкранного режима и ширина строк в колонках терминала.
///
/// Почему: `dart_tui` пишет содержимое `View` как есть и не режет строки
/// шире экрана — длинная строка переносится терминалом и сдвигает весь кадр
/// (разведка 6.11, design.md change `add-cli-tui`, D14 пункт 8). Поэтому
/// ширину считает и строки режет наш рендер (§12.2.7, шаг 4).
///
/// Для чего: [Frame] — результат `render`; [fitLine] — последний шаг каждой
/// строки кадра: обрезка по ширине и сброс атрибутов (TUI-9); [wrapLine] —
/// перенос текста сессии; [displayWidth] — ширина в колонках без SGR.
///
/// Как использовать: строки кадра строит только `render` ядра экрана; в
/// [fitLine] попадает строка, где управляющие последовательности — только
/// SGR самого рендера (текст сессии уже прошёл санитизацию, TUI-11).
library;

/// SGR-последовательность рендера (`ESC [ … m`).
final _sgr = RegExp('\x1b\\[[0-9;]*m');

const _reset = '\x1b[0m';

/// Кадр: ровно столько строк, сколько у терминала, и позиция курсора
/// `(строка, колонка)`; `null` — курсор скрыт.
final class Frame {
  const Frame(this.lines, {this.cursor});

  final List<String> lines;
  final (int, int)? cursor;
}

/// Ширина руны в колонках: `0` — комбинируемые знаки, ZWJ и селекторы
/// вариантов; `2` — восточноазиатские широкие символы и эмодзи; иначе `1`.
///
/// Таблица — приближение East Asian Width и Emoji Presentation Unicode:
/// терминалы сами расходятся в спорных символах, поэтому [fitLine] оставляет
/// для них запас в одну колонку (D14, пункт 8).
int runeWidth(int rune) {
  if (rune == 0x200d ||
      (rune >= 0x0300 && rune <= 0x036f) ||
      (rune >= 0x1ab0 && rune <= 0x1aff) ||
      (rune >= 0x20d0 && rune <= 0x20ff) ||
      (rune >= 0xfe00 && rune <= 0xfe0f) ||
      (rune >= 0xfe20 && rune <= 0xfe2f) ||
      (rune >= 0x1f3fb && rune <= 0x1f3ff) ||
      (rune >= 0xe0100 && rune <= 0xe01ef)) {
    return 0;
  }
  if ((rune >= 0x1100 && rune <= 0x115f) ||
      (rune >= 0x2e80 && rune <= 0x303e) ||
      (rune >= 0x3041 && rune <= 0x33ff) ||
      (rune >= 0x3400 && rune <= 0x4dbf) ||
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0xa000 && rune <= 0xa4cf) ||
      (rune >= 0xac00 && rune <= 0xd7a3) ||
      (rune >= 0xf900 && rune <= 0xfaff) ||
      (rune >= 0xfe30 && rune <= 0xfe4f) ||
      (rune >= 0xff00 && rune <= 0xff60) ||
      (rune >= 0xffe0 && rune <= 0xffe6) ||
      (rune >= 0x1f300 && rune <= 0x1f64f) ||
      (rune >= 0x1f900 && rune <= 0x1f9ff) ||
      (rune >= 0x1f680 && rune <= 0x1f6ff) ||
      (rune >= 0x20000 && rune <= 0x3fffd)) {
    return 2;
  }
  return 1;
}

/// Ширина [text] в колонках; SGR не занимает места. Символы после ZWJ —
/// часть той же графемы и колонок не добавляют.
int displayWidth(String text) {
  var width = 0;
  var joined = false;
  for (final rune in text.replaceAll(_sgr, '').runes) {
    if (joined) {
      joined = false;
      continue;
    }
    if (rune == 0x200d) {
      joined = true;
      continue;
    }
    width += runeWidth(rune);
  }
  return width;
}

/// Есть ли в [text] символы, ширину которых терминалы считают по-разному.
bool _hasDisputed(String text) =>
    text.runes.any((rune) => rune > 0x7f && runeWidth(rune) != 1);

/// Строка кадра: не шире [width] колонок и, при [color], со сбросом
/// атрибутов в конце (TUI-9).
///
/// Строке со спорными символами достаётся на одну колонку меньше: если
/// терминал посчитает символ шире нас, строка всё равно не перенесётся.
/// Широкий символ не разрезается пополам.
String fitLine(String line, int width, {bool color = true}) {
  final limit = _hasDisputed(line) ? width - 1 : width;
  final out = StringBuffer();
  var used = 0;
  var joined = false;
  var index = 0;
  while (index < line.length) {
    if (_sgr.matchAsPrefix(line, index) case final match?) {
      out.write(match[0]);
      index = match.end;
      continue;
    }
    final (rune, units) = _runeAt(line, index);
    final cost = joined || rune == 0x200d ? 0 : runeWidth(rune);
    joined = rune == 0x200d;
    if (used + cost > limit) {
      break;
    }
    used += cost;
    out.write(line.substring(index, index + units));
    index += units;
  }
  if (color) {
    out.write(_reset);
  }
  return out.toString();
}

/// Руна, которая начинается с кодовой единицы [index], и число её единиц.
(int, int) _runeAt(String text, int index) {
  final high = text.codeUnitAt(index);
  if (high >= 0xd800 && high <= 0xdbff && index + 1 < text.length) {
    final low = text.codeUnitAt(index + 1);
    if (low >= 0xdc00 && low <= 0xdfff) {
      return (0x10000 + ((high - 0xd800) << 10) + (low - 0xdc00), 2);
    }
  }
  return (high, 1);
}

/// Перенос простого текста (без SGR) по [width] колонкам: по пробелам, а
/// слово длиннее строки — по символам. Пустой текст — одна пустая строка.
List<String> wrapLine(String text, int width) {
  if (width <= 0 || displayWidth(text) <= width) {
    return [text];
  }
  final lines = <String>[];
  var current = StringBuffer();
  var currentWidth = 0;
  void flush() {
    lines.add(current.toString().trimRight());
    current = StringBuffer();
    currentWidth = 0;
  }

  for (final word in text.split(' ')) {
    final wordWidth = displayWidth(word);
    final gap = currentWidth == 0 ? 0 : 1;
    if (currentWidth + gap + wordWidth <= width) {
      if (gap == 1) {
        current.write(' ');
      }
      current.write(word);
      currentWidth += gap + wordWidth;
      continue;
    }
    if (currentWidth > 0) {
      flush();
    }
    if (wordWidth <= width) {
      current.write(word);
      currentWidth = wordWidth;
      continue;
    }
    // Слово шире строки режется по символам.
    for (final rune in word.runes) {
      final cost = runeWidth(rune);
      if (currentWidth + cost > width) {
        flush();
      }
      current.writeCharCode(rune);
      currentWidth += cost;
    }
  }
  if (currentWidth > 0 || lines.isEmpty) {
    flush();
  }
  return lines;
}
