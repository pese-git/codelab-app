/// Разбор строки команды `/<слово> <остаток>` — единственное место (design.md
/// change `add-agent-builtin-slash-commands`, D3; `agent-core-architecture`
/// §17.2.6).
///
/// Почему отдельный файл: слово команды и `raw` определяют и встроенные
/// команды (`BuiltinCommands.match`), и шаблоны (`expandCommand`). Две копии
/// регулярного выражения и снятия `\r?\n` разошлись бы, и одна и та же строка
/// была бы командой для одной стороны и текстом для другой.
///
/// Как использовать: `parseCommandLine(firstTextBlock)`; `null` — строка не
/// команда и уходит модели без изменений. Функция чистая: не исполняет shell и
/// не читает файлы (SKL-8).
library;

final _commandWord = RegExp(r'^[A-Za-z0-9][A-Za-z0-9:_-]*$');
final _whitespace = RegExp(r'\s');

/// Слово и аргументы команды.
typedef CommandLine = ({String word, String raw});

/// Выделяет из [text] слово команды (до первого пробельного символа, без `/`)
/// и `raw` — остаток после ведущих пробелов без завершающего `\r?\n`.
///
/// `null`, если [text] не начинается с `/` в первой позиции (ведущие пробелы
/// команду не делают) или слово не соответствует
/// `^[A-Za-z0-9][A-Za-z0-9:_-]*$` (`/usr/bin/foo`, `/`). `\r` не попадает в
/// `raw`: иначе он дошёл бы до `$ARGUMENTS` и до `command.args` журнала.
CommandLine? parseCommandLine(String text) {
  if (!text.startsWith('/')) {
    return null;
  }
  final end = text.indexOf(_whitespace);
  final word = text.substring(1, end < 0 ? text.length : end);
  if (!_commandWord.hasMatch(word)) {
    return null;
  }
  var raw = end < 0 ? '' : text.substring(end).trimLeft();
  if (raw.endsWith('\r\n')) {
    raw = raw.substring(0, raw.length - 2);
  } else if (raw.endsWith('\n')) {
    raw = raw.substring(0, raw.length - 1);
  }
  return (word: word, raw: raw);
}
