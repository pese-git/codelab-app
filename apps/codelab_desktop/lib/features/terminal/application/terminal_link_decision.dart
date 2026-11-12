/// Решение по адресу ссылки OSC 8: можно ли предлагать его открыть.
///
/// Почему: адрес приходит из вывода процесса и недоверенный; решение «опасно
/// ли» принадлежит application, а не виджету (`AGENTS.md` §10; D3 «Ссылки
/// OSC 8», Q14).
///
/// Для чего: диалог показывает кнопку «Open» только при [canOpen]; [scheme]
/// идёт в события `terminal.link_*` вместо адреса (D9).
///
/// Как использовать: `terminalLinkDecision(uri)`.
final class TerminalLinkDecision {
  const TerminalLinkDecision({
    required this.canOpen,
    required this.scheme,
    required this.address,
  });

  /// `true` — схема `http` или `https` и в адресе нет скрытых символов.
  final bool canOpen;

  /// Адрес для показа в диалоге: ровно `Uri.parse(uri).toString()`, то есть
  /// то, что уйдёт в порт открытия (Q21). Нормализация кодирует пробелы,
  /// юникод и управляющие символы в `%XX`, поэтому диалог не показывает
  /// «чистый» адрес, который открылся бы иначе. Неразбираемый адрес
  /// показывается как есть, но скрытые символы заменены на `\u{код}`.
  final String address;

  /// Схема в нижнем регистре; `null`, если адрес не разобрался.
  final String? scheme;
}

/// Скрытые и управляющие символы адреса (Q21).
///
/// Почему: bidi-управление переставляет визуальный порядок, символы нулевой
/// ширины невидимы, C0/C1 управляют терминалом; в диалоге такой адрес мог бы
/// выглядеть как другой. Для чего: адрес с ними не открывается вовсе. Состав:
/// U+202A–U+202E, U+2066–U+2069, U+200E, U+200F (bidi); U+200B–U+200D,
/// U+FEFF, U+2060 (нулевая ширина); U+0000–U+001F, U+007F–U+009F (C0/C1).
final _hiddenCharacters = RegExp(
  r'[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u202A-\u202E'
  r'\u2060\u2066-\u2069\uFEFF]',
);

/// Разбирает [uri] (`Uri.tryParse`) и разрешает только `http`/`https` без
/// учёта регистра и без скрытых символов ([_hiddenCharacters]); прочие схемы,
/// пустой и неразбираемый адрес отклоняются. Схема в решении сохраняется и для
/// отклонённого адреса: она идёт в событие `terminal.link_refused` (D9).
TerminalLinkDecision terminalLinkDecision(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) {
    return TerminalLinkDecision(
      canOpen: false,
      scheme: null,
      address: uri.replaceAllMapped(
        _hiddenCharacters,
        (m) => '\\u{${m[0]!.codeUnitAt(0).toRadixString(16)}}',
      ),
    );
  }
  final scheme = parsed.scheme.toLowerCase();
  return TerminalLinkDecision(
    canOpen:
        (scheme == 'http' || scheme == 'https') &&
        !_hiddenCharacters.hasMatch(uri),
    scheme: scheme,
    address: parsed.toString(),
  );
}
