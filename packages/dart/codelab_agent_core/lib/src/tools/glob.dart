/// Шаблон пути инструмента `search` (`agent-core-architecture` §6.4, шаг 3;
/// design.md, D10).
///
/// Почему свой код: синтаксис маленький, а готовый пакет glob расширил бы
/// allowlist зависимостей ядра (PKG-2).
///
/// Синтаксис: `*` — любые символы кроме `/`; `**` — любые символы, включая
/// `/` (`**/` может соответствовать пустой строке); `?` — один символ кроме
/// `/`; `{a,b}` — альтернатива (вложенные допускаются); `[abc]` и `[!abc]` —
/// класс символов. Незакрытые `{` и `[` понимаются буквально.
///
/// Как использовать: `Glob('**/*.dart').matches('lib/a.dart')`. Путь
/// передаётся относительным, через `/`. Шаблон без `/` сравнивается только
/// с именем файла: `*.dart` находит и `lib/a.dart`.
final class Glob {
  Glob(this.pattern)
    : _byName = !pattern.contains('/'),
      _regex = RegExp('^${_compile(pattern)}\$');

  final String pattern;
  final bool _byName;
  final RegExp _regex;

  bool matches(String relativePath) {
    final subject = _byName
        ? relativePath.substring(relativePath.lastIndexOf('/') + 1)
        : relativePath;
    return _regex.hasMatch(subject);
  }

  static String _compile(String glob) {
    final out = StringBuffer();
    var i = 0;
    while (i < glob.length) {
      final c = glob[i];
      switch (c) {
        case '*':
          if (i + 1 < glob.length && glob[i + 1] == '*') {
            if (i + 2 < glob.length && glob[i + 2] == '/') {
              out.write('(?:.*/)?');
              i += 3;
            } else {
              out.write('.*');
              i += 2;
            }
            continue;
          }
          out.write('[^/]*');
        case '?':
          out.write('[^/]');
        case '{':
          final end = _closing(glob, i);
          if (end < 0) {
            out.write(RegExp.escape(c));
          } else {
            final alternatives = _split(glob.substring(i + 1, end));
            out.write('(?:${alternatives.map(_compile).join('|')})');
            i = end + 1;
            continue;
          }
        case '[':
          final end = glob.indexOf(']', i + 2);
          if (end < 0) {
            out.write(RegExp.escape(c));
          } else {
            var body = glob.substring(i + 1, end);
            final negated = body.startsWith('!');
            if (negated) {
              body = body.substring(1);
            }
            final escaped = body.replaceAllMapped(
              RegExp(r'[\\\]^]'),
              (m) => '\\${m[0]}',
            );
            out.write('[${negated ? '^' : ''}$escaped]');
            i = end + 1;
            continue;
          }
        default:
          out.write(RegExp.escape(c));
      }
      i++;
    }
    return '$out';
  }

  /// Индекс `}`, закрывающей `{` в позиции [open], с учётом вложенности;
  /// `-1` — не закрыта.
  static int _closing(String glob, int open) {
    var depth = 0;
    for (var i = open; i < glob.length; i++) {
      if (glob[i] == '{') {
        depth++;
      } else if (glob[i] == '}' && --depth == 0) {
        return i;
      }
    }
    return -1;
  }

  /// Альтернативы внутри `{…}`: запятые на верхнем уровне вложенности.
  static List<String> _split(String body) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < body.length; i++) {
      switch (body[i]) {
        case '{':
          depth++;
        case '}':
          depth--;
        case ',' when depth == 0:
          parts.add(body.substring(start, i));
          start = i + 1;
      }
    }
    return parts..add(body.substring(start));
  }
}
