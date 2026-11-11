/// Строка для показа пользователю с видимыми escape-последовательностями
/// вместо управляющих и невидимых символов.
///
/// Почему: адрес или имя файла из ответа агента — недоверенный текст. Символы
/// направления (`U+202E` и др.), нулевой ширины и разделители строк позволяют
/// выдать один адрес за другой или спрятать часть строки (D5, R4,
/// `AGENTS.md` §10).
///
/// Для чего: подсказки и подписи заглушек изображений (D6), а в итерации 4 —
/// подсказка ссылки. Заменяются C0 и C1, `U+061C`, `U+200B–U+200F`,
/// `U+2028/2029`, `U+202A–U+202E`, `U+2066–U+2069`, `U+FEFF` на `\uXXXX`.
///
/// Как использовать: `escapeForDisplay(url)` перед выводом в `Text` или
/// `Tooltip`; остальные символы, включая кириллицу и эмодзи, остаются.
String escapeForDisplay(String value) {
  final out = StringBuffer();
  for (final unit in value.runes) {
    if (_isInvisibleOrControl(unit)) {
      out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

bool _isInvisibleOrControl(int unit) =>
    unit < 0x20 ||
    (unit >= 0x7F && unit <= 0x9F) ||
    unit == 0x061C ||
    (unit >= 0x200B && unit <= 0x200F) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    (unit >= 0x202A && unit <= 0x202E) ||
    (unit >= 0x2066 && unit <= 0x2069) ||
    unit == 0xFEFF;
