/// Текст сессии без управляющих символов терминала.
///
/// Почему: ответ, мысли, заголовки инструментов и ошибки приходят от агента,
/// и `ESC` в них мог бы менять цвет, двигать курсор или писать в заголовок
/// окна терминала; управляющие последовательности в выводе CLI делает только
/// сам рендер (§12.2.11, TUI-11; design.md change `add-codelab-cli`, D6).
///
/// Как использовать: каждый текст из сессии перед выводом в терминал. Не
/// применяется к stdout headless — там ответ выводится байт в байт (H-01).
/// C0, кроме `\n`, DEL и C1 вырезаются, `\t` раскрывается в четыре пробела.
String sanitizeTerminalText(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x0a) {
      out.writeCharCode(rune);
    } else if (rune == 0x09) {
      out.write('    ');
    } else if (rune < 0x20 || (rune >= 0x7f && rune <= 0x9f)) {
      continue;
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}
