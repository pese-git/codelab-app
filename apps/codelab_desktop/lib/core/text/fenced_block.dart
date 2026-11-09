/// Снимает одно внешнее markdown-ограждение ответа (задача 6.1i, Q34/Q37,
/// D27 change `add-provider-setup-ui`).
///
/// Почему: ядро агента ставит ограждение ```` ```text ```` вокруг ответов
/// slash-команд для ленты чата, а панель «Agent status» и лента показывают
/// такой ответ моноширинным блоком без строк ограждения. Правило одно на оба
/// места (spec app-settings «Ответ /mcp list без внешнего ограждения»,
/// agent-workbench-ui «Ответ агента одним огороженным блоком»).
///
/// Для чего: возвращает содержимое, только если весь [text] (без пробельных
/// строк по краям) — одна строка ``` с необязательным словом языка, тело и
/// строка ``` и внутри нет другой строки-ограждения. Иначе — `null`: текст
/// показывается как есть (проза до или после, два блока, только открывающая
/// строка идущего хода). Содержимое не разбирается (SETUP-11).
///
/// Как использовать: `unfenceSingleBlock(text) ?? text`; `preformatted` —
/// результат `!= null`.
String? unfenceSingleBlock(String text) {
  // Дешёвый предфильтр: функция вызывается для каждого ответа агента при
  // каждом изменении ленты, а проза почти всегда не начинается с ограждения.
  if (!text.trimLeft().startsWith('```')) {
    return null;
  }
  final lines = text.split(RegExp(r'\r?\n'));
  var start = 0;
  var end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  if (end - start < 2) {
    return null;
  }
  final open = RegExp(r'^\s*```[A-Za-z0-9_+.-]*\s*$');
  final close = RegExp(r'^\s*```\s*$');
  if (!open.hasMatch(lines[start]) || !close.hasMatch(lines[end - 1])) {
    return null;
  }
  final inner = lines.sublist(start + 1, end - 1);
  if (inner.any((line) => line.trimLeft().startsWith('```'))) {
    return null;
  }
  return inner.join('\n');
}
