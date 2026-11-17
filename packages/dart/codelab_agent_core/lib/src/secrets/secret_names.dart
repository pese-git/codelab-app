/// Имена секретов (`agent-core-architecture` §17.5.2; design.md change
/// `add-agent-secret-store`, D2).
library;

/// Единственное правило имени секрета и производные от него имена.
///
/// Почему одно правило: временная проверка 8.5 допускала любые имена без
/// пробелов, а нормализация давала бы два имени на один секрет и
/// неоднозначную переменную `CODELAB_SECRET_*` (D2). Строгое имя в
/// `api_key_secret`, `${secret:<name>}` и в аргументе `secret set` проверяет
/// один код.
///
/// Для чего: загрузка конфига (`config/`), подкоманды `secret` и резолвер
/// ([SecretResolver]) получают имена только отсюда; ошибка имени — значение
/// ([problem]), а не `ArgumentError`: имя из конфига — проблема загрузки
/// (`ConfigIssue`), а не исключение.
///
/// Как использовать: `SecretNames.problem(name) == null` — имя годится;
/// [envOverride] даёт переменную переопределения, [suggestFor] и [forMcp] —
/// имя для подсказки `codelab secret set <name>`. Текст [problem] не
/// содержит проверяемой строки: в поле имени часто вписывают сам ключ.
abstract final class SecretNames {
  /// Допустимые символы и длина; дополнительно запрещены `..` и `/` в конце
  /// (см. [problem]).
  static final RegExp pattern = RegExp(r'^[a-z0-9][a-z0-9._/-]{0,127}$');

  /// Максимальная длина имени (часть [pattern]).
  static const int maxLength = 128;

  static const String _rule =
      'expected a secret name: lowercase letters, digits and . _ / -, '
      'up to 128 characters';

  /// `null` — имя годится; иначе английский текст правила без самого имени.
  static String? problem(String name) {
    if (pattern.hasMatch(name) && !name.contains('..') && !name.endsWith('/')) {
      return null;
    }
    return _rule;
  }

  /// Переменная переопределения: префикс `CODELAB_SECRET_`, имя в верхнем
  /// регистре, каждый символ вне `[A-Z0-9]` — `_`.
  ///
  /// Отображение необратимо (`codelab/a-b` и `codelab/a.b` дают одну
  /// переменную), поэтому `secret set` отклоняет имя, чья переменная
  /// совпала с переменной другого имени (D8).
  static String envOverride(String name) =>
      'CODELAB_SECRET_${name.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '_')}';

  /// Предлагаемое имя по пути ключа конфига (§17.5.4): для подсказки
  /// `codelab secret set <name>` в `ConfigInlineSecretException`.
  ///
  /// - `providers.<id>.*` → `codelab/<id>`;
  /// - `mcp.servers[<server>].env.<KEY>`, `….headers.<Key>` и
  ///   `mcp.servers[<server>].<key>` → `codelab/mcp/<server>/<key>`;
  /// - `tools.web.search.backends.<b>.*` → `codelab/search-<b>`;
  /// - прочий путь → `codelab/<путь>` (запасной вариант: подсказка остаётся
  ///   допустимым именем).
  ///
  /// Результат всегда проходит [problem]: части приводятся к
  /// `[a-z0-9._-]`, обрезаются, а пустая часть заменяется на `x`.
  static String suggestFor(String configPath) {
    final provider = RegExp(r'^providers\.([^.]+)\.').firstMatch(configPath);
    if (provider != null) {
      return _join('codelab/${_part(provider.group(1)!, 100)}');
    }
    final mcp = RegExp(
      r'^mcp\.servers\[(.*?)\]\.(?:(?:env|headers)\.)?(.+)$',
    ).firstMatch(configPath);
    if (mcp != null) {
      return forMcp(mcp.group(1)!, mcp.group(2)!);
    }
    final search = RegExp(
      r'^tools\.web\.search\.backends\.([^.]+)\.',
    ).firstMatch(configPath);
    if (search != null) {
      return _join('codelab/search-${_part(search.group(1)!, 100)}');
    }
    return _join('codelab/${_part(configPath, 100)}');
  }

  /// `codelab/mcp/<server>/<key>`: обе части в нижнем регистре, символы вне
  /// `[a-z0-9._-]` заменены на `-`.
  static String forMcp(String server, String key) =>
      _join('codelab/mcp/${_part(server, 50)}/${_part(key, 50)}');

  /// Часть имени: нижний регистр, недопустимые символы — `-`, `..` схлопнуто,
  /// начало и конец только из `[a-z0-9]`, не длиннее [limit]; пустое — `x`.
  static String _part(String raw, int limit) {
    var text = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '-')
        .replaceAll(RegExp(r'\.{2,}'), '.');
    text = text.replaceAll(RegExp(r'^[^a-z0-9]+'), '');
    if (text.length > limit) {
      text = text.substring(0, limit);
    }
    text = text.replaceAll(RegExp(r'[^a-z0-9]+$'), '');
    return text.isEmpty ? 'x' : text;
  }

  /// Защита в глубину: сборка из уже безопасных частей не должна
  /// выходить за предел длины.
  static String _join(String name) =>
      name.length <= maxLength ? name : name.substring(0, maxLength);
}
