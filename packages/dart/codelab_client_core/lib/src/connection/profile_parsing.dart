/// Разбор полей формы профиля stdio: строка аргументов и строки окружения.
///
/// Почему: app и CLI принимают команду агента как текст, а профиль хранит
/// список аргументов и словарь окружения; правило разбора должно быть одно
/// (перенос `_splitShellWords` и `_parseEnv` из `CodeLabShellCubit`,
/// design D8).
library;

/// Делит [value] на слова по любым пробельным символам; пустые слова
/// отбрасываются.
///
/// Кавычки и экранирование не разбираются — так работала форма app:
/// `"a b"` даёт два слова `"a` и `b"`.
List<String> parseShellWords(String value) => value
    .split(RegExp(r'\s+'))
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toList(growable: false);

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
