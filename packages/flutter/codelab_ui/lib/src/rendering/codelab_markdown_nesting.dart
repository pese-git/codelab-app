/// Наибольшая вложенность цитат и списков, при которой ответ ещё рисуется как
/// markdown.
///
/// Почему: пакет `gpt_markdown` рекурсивен — на вложенности около 1000
/// падает со Stack Overflow, а стоимость растёт квадратично (замер
/// 2026-11-11 в `flutter test`: 64 уровня — 40 мс, 128 — 0,1 с, 256 — 0,7 с,
/// 512 — 1,3 с). Настоящий ответ вкладывает не глубже десятка уровней; 32
/// даёт запас и кадр порядка 30 мс (решение пользователя 2026-11-11,
/// design.md `add-desktop-markdown` D14).
const int kMaxMarkdownNestingDepth = 32;

/// Оценивает вложенность цитат и списков в [text] с запасом сверху.
///
/// Почему: решение «показать как markdown или как текст» нельзя принять после
/// разбора — именно разбор падает. Точно повторять разбор пакета нельзя: он
/// допускает префиксы и разделители, которые простой подсчёт пропускает
/// (`\r`, U+2028, BOM, `\f`, сноска, обратная кавычка в info-строке, конец
/// контейнера), и каждый такой обход давал Stack Overflow (ревью итерации 2,
/// три круга). Поэтому оценка намеренно завышена, а не точна (D14: ошибка в
/// сторону простого текста безопасна).
///
/// Для чего: `CodeLabMarkdown` сравнивает результат с
/// [kMaxMarkdownNestingDepth]. Строки делятся по `\n`, `\r`, U+2028, U+2029 и
/// U+0085. Глубина строки — число символов `>` в любом месте, плюс число
/// маркеров списка в любом месте (`-`, `*`, `+` или `N.`/`N)` до девяти цифр,
/// перед которыми начало строки или не буква и не цифра, а после — пробельный
/// символ или конец строки), плюс `сумма отступов ~/ 2`: пробелы и табуляции
/// (табуляция — четыре колонки; в сериях после `>` и маркера один пробел-
/// разделитель не считается) суммируются во всём ведущем префиксе
/// контейнеров — пока идут пробелы, `>` и маркеры списка, в том числе после
/// них (`>\t\t- x`). Содержимое огороженных блоков не
/// исключается. Таблицы не ограничиваются. Запас: обычный текст с десятком
/// `->` или пунктов в одной строке остаётся ниже порога 32.
///
/// Как использовать: `markdownNestingDepth(text) > kMaxMarkdownNestingDepth`.
/// Один линейный проход, без регулярных выражений с возвратом.
int markdownNestingDepth(String text) {
  var deepest = 0;
  var depth = 0;
  var columns = 0;
  var pending = 0; // колонки текущей серии пробелов
  var seenMarker = false; // до серии уже был непробельный символ префикса
  var inPrefix = true;
  var markerEnd = -1;
  var previous = 0x0A; // начало строки
  final length = text.length;
  for (var i = 0; i <= length; i++) {
    final c = i < length ? text.codeUnitAt(i) : 0x0A;
    final isSpace = c == 0x20 || c == 0x09;
    if (!isSpace && pending > 0) {
      // Серия после `>` или маркера содержит один обязательный разделитель
      // (`> `, `- `): он вложенности не добавляет. Ведущая серия считается
      // целиком.
      if (inPrefix) {
        columns += seenMarker ? (pending > 1 ? pending - 1 : 0) : pending;
      }
      pending = 0;
    }
    if (_isLineBreak(c)) {
      final total = depth + columns ~/ 2;
      if (total > deepest) deepest = total;
      depth = 0;
      columns = 0;
      seenMarker = false;
      inPrefix = true;
      markerEnd = -1;
      previous = 0x0A;
      continue;
    }
    if (isSpace) {
      // Отступ считается во всём ведущем префиксе контейнеров: пакет
      // вкладывает список в цитату отступом после `>` (четвёртый круг ревью).
      pending += c == 0x09 ? 4 : 1;
    } else if (i <= markerEnd) {
      // Остаток уже учтённого маркера `N.` / `N)`.
    } else if (c == 0x3E) {
      depth++;
    } else if (!_isWordChar(previous) && _isMarkerAt(text, i, length)) {
      depth++;
      if (c >= 0x30 && c <= 0x39) {
        var j = i;
        while (text.codeUnitAt(j) >= 0x30 && text.codeUnitAt(j) <= 0x39) {
          j++;
        }
        markerEnd = j;
      }
    } else {
      inPrefix = false;
    }
    if (!isSpace) {
      seenMarker = true;
    }
    previous = c;
  }
  return deepest;
}

/// С позиции [i] начинается маркер списка: `-`, `*`, `+` или `N.` / `N)`
/// (до девяти цифр), за которым пробельный символ или конец строки.
bool _isMarkerAt(String text, int i, int length) {
  final c = text.codeUnitAt(i);
  if (c == 0x2D || c == 0x2A || c == 0x2B) {
    return _endsToken(text, i + 1, length);
  }
  if (c < 0x30 || c > 0x39) return false;
  var j = i;
  while (j < length &&
      text.codeUnitAt(j) >= 0x30 &&
      text.codeUnitAt(j) <= 0x39) {
    j++;
  }
  if (j - i > 9 || j >= length) return false;
  final d = text.codeUnitAt(j);
  return (d == 0x2E || d == 0x29) && _endsToken(text, j + 1, length);
}

bool _isLineBreak(int c) =>
    c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029 || c == 0x85;

/// Буква или цифра: перед маркером списка такого символа быть не должно
/// (`a-b`, `x1.`); кириллица и прочие буквы считаются «не словом» —
/// это завышает оценку, что допустимо.
bool _isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A);

/// После маркера идёт пробельный символ или конец строки.
bool _endsToken(String text, int i, int length) {
  if (i >= length) return true;
  final c = text.codeUnitAt(i);
  return c == 0x20 || c == 0x09 || _isLineBreak(c);
}
