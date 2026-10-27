/// Разбор полей формы профиля stdio: строка аргументов и строки окружения.
///
/// Почему: app и CLI принимают команду агента как текст, а профиль хранит
/// список аргументов и словарь окружения; правило разбора должно быть одно
/// (перенос `_splitShellWords` и `_parseEnv` из `CodeLabShellCubit`,
/// design D8).
library;

/// Делит строку команды [value] на слова как POSIX shell без подстановок.
///
/// Почему: профиль `stdio:` CLI и поле аргументов профиля app принимают
/// команду текстом, а у аргумента может быть пробел внутри
/// (`-m "codelab agent"`); прежний разбор по пробелам ломал такие команды
/// (design.md change `add-codelab-cli`, D14).
///
/// Правила: пробельные символы вне кавычек разделяют слова; одинарные кавычки
/// сохраняют текст буквально; в двойных кавычках `\"` и `\\` дают `"` и
/// `\`, остальная обратная косая сохраняется; вне кавычек обратная косая
/// экранирует следующий символ; кавычки, примыкающие к тексту, дают одно
/// слово (`--opt="a b"c` → `--opt=a bc`), пустые кавычки — пустое слово.
/// Переменные, `~` и шаблоны не раскрываются.
///
/// Ошибки: незакрытая кавычка или обратная косая в конце — [FormatException].
List<String> parseShellWords(String value) {
  final words = <String>[];
  final word = StringBuffer();
  // Слово начато, даже если пусто: так `""` даёт пустое слово.
  var inWord = false;
  var i = 0;
  while (i < value.length) {
    final char = value[i];
    if (char == "'") {
      final end = value.indexOf("'", i + 1);
      if (end < 0) {
        throw FormatException('Unterminated single quote', value, i);
      }
      word.write(value.substring(i + 1, end));
      inWord = true;
      i = end + 1;
    } else if (char == '"') {
      i = _readDoubleQuoted(value, i, word);
      inWord = true;
    } else if (char == r'\') {
      if (i + 1 >= value.length) {
        throw FormatException('Trailing backslash', value, i);
      }
      word.write(value[i + 1]);
      inWord = true;
      i += 2;
    } else if (_isSpace(char)) {
      if (inWord) {
        words.add(word.toString());
        word.clear();
        inWord = false;
      }
      i++;
    } else {
      word.write(char);
      inWord = true;
      i++;
    }
  }
  if (inWord) {
    words.add(word.toString());
  }
  return List.unmodifiable(words);
}

/// Читает двойные кавычки с позиции [start] в [word]; возвращает позицию
/// после закрывающей кавычки.
int _readDoubleQuoted(String value, int start, StringBuffer word) {
  var i = start + 1;
  while (i < value.length) {
    final char = value[i];
    if (char == '"') {
      return i + 1;
    }
    if (char == r'\' &&
        i + 1 < value.length &&
        (value[i + 1] == '"' || value[i + 1] == r'\')) {
      word.write(value[i + 1]);
      i += 2;
      continue;
    }
    word.write(char);
    i++;
  }
  throw FormatException('Unterminated double quote', value, start);
}

bool _isSpace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

/// Читает строки `KEY=VALUE` из [value]; ключ и значение обрезаются по
/// краям, значение может содержать `=`.
///
/// Пустые строки и строки без ключа (`=value`, `noequals`) пропускаются.
Map<String, String> parseEnvLines(String value) {
  final env = <String, String>{};
  for (final line in value.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final separator = trimmed.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    env[trimmed.substring(0, separator).trim()] = trimmed
        .substring(separator + 1)
        .trim();
  }
  return env;
}
