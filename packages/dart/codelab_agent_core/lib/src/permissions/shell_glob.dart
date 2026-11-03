/// Маски путей оболочки для проверки целей `exec`: `*`, `?`, `[…]` и
/// фигурные скобки `{a,b}` (PERM-11, `agent-core/07-permissions.md` §7.6.1;
/// правило R5-4 change `add-config-writer-and-reload`).
///
/// Почему не `tools/glob.dart`: инструмент `glob` обходит файловую систему и
/// сопоставляет целые пути с учётом `**`; здесь файловой системы нет (PKG-1) и
/// нужен другой вопрос — «может ли маска ОДНОЙ компоненты совпасть с данным
/// именем защищаемого потомка». Поэтому правила другие: имя на точку совпадает
/// только с маской, начинающейся с точки (`*` не видит `.codelab`), а
/// нераскрытые скобки и сломанная маска не отвергаются, а считаются
/// совпадением — fail closed (`AGENTS.md` §10).
///
/// Для чего: [hasMask], [braceExpand] и [globMatches] — чистые функции от
/// строк; их использует `ConfigCheck` из `agent_config_rules.dart`.
///
/// Как использовать: сначала [braceExpand] слова, затем для каждого варианта
/// [hasMask]; маску одной компоненты сравнивают с именем через [globMatches].
library;

final maskChars = RegExp(r'[*?\[\]{}]');

/// Есть ли в слове маска пути (`*`, `?`, `[`) или нераскрытая фигурная скобка.
bool hasMask(String word) =>
    word.contains('*') ||
    word.contains('?') ||
    word.contains('[') ||
    // `{}` — подстановка `find -exec`, а не скобки оболочки.
    word.replaceAll('{}', '').contains('{');

/// Раскрывает фигурные скобки со списком (`a{b,c}d` → `abd`, `acd`); `${…}`
/// и скобки без запятой (`{1..3}`, `{}`) остаются как есть. Больше 64
/// вариантов — слово не раскрывается: дальше оно считается маской (fail
/// closed, R5-4).
List<String> braceExpand(String word) {
  const limit = 64;
  final out = <String>[];
  void expand(String w) {
    if (out.length > limit) {
      return;
    }
    final group = _findBraceGroup(w);
    if (group == null) {
      out.add(w);
      return;
    }
    for (final alternative in group.alternatives) {
      expand(
        '${w.substring(0, group.start)}$alternative'
        '${w.substring(group.end + 1)}',
      );
    }
  }

  expand(word);
  return out.length > limit ? [word] : out;
}

({int start, int end, List<String> alternatives})? _findBraceGroup(String w) {
  for (var i = 0; i < w.length; i++) {
    if (w[i] != '{' || i > 0 && w[i - 1] == r'$') {
      continue;
    }
    var depth = 0;
    final cuts = <int>[];
    for (var j = i; j < w.length; j++) {
      if (w[j] == '{') {
        depth++;
      } else if (w[j] == '}') {
        depth--;
        if (depth == 0) {
          if (cuts.isEmpty) {
            break;
          }
          final bounds = [i, ...cuts, j];
          return (
            start: i,
            end: j,
            alternatives: [
              for (var n = 0; n < bounds.length - 1; n++)
                w.substring(bounds[n] + 1, bounds[n + 1]),
            ],
          );
        }
      } else if (w[j] == ',' && depth == 1) {
        cuts.add(j);
      }
    }
  }
  return null;
}

/// Совпадает ли имя [name] с маской одной компоненты [glob]: `*`, `?`,
/// `[…]`; имя на точку совпадает, только если маска сама начинается с точки.
/// Нераскрытые фигурные скобки и сломанная маска — совпадение по литеральному
/// префиксу или без проверки (fail closed).
bool globMatches(String glob, String name, {bool ignoreCase = false}) {
  final g = ignoreCase ? glob.toLowerCase() : glob;
  final n = ignoreCase ? name.toLowerCase() : name;
  if (g.contains('{')) {
    final prefix = g.substring(0, g.indexOf(RegExp(r'[*?\[{]')));
    return n.startsWith(prefix);
  }
  if (n.startsWith('.') && !g.startsWith('.')) {
    return false;
  }
  final regex = StringBuffer('^');
  for (var i = 0; i < g.length; i++) {
    final c = g[i];
    if (c == '*') {
      regex.write('.*');
    } else if (c == '?') {
      regex.write('.');
    } else if (c == '[') {
      final close = g.indexOf(']', i + 2);
      if (close < 0) {
        regex.write(r'\[');
        continue;
      }
      var body = g.substring(i + 1, close).replaceAll(r'\', r'\\');
      if (body.startsWith('!')) {
        body = '^${body.substring(1)}';
      }
      regex.write('[$body]');
      i = close;
    } else {
      regex.write(RegExp.escape(c));
    }
  }
  regex.write(r'$');
  try {
    return RegExp(regex.toString(), dotAll: true).hasMatch(n);
  } on FormatException {
    return true;
  }
}
