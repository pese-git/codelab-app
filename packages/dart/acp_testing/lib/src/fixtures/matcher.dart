import 'dart:convert';

import 'fixture.dart';

/// Normalization and comparison of ACP frames — `14-golden-fixtures.md`
/// §14.5 (normalization) and §14.6 (matchers), design.md D3.
///
/// Comparison is exact by default: an extra key in the actual frame is a
/// mismatch, key order does not matter, array order does. Matcher objects in
/// the expected frame relax the comparison only in their place; `_meta` is
/// always compared as `$partial`.

/// One difference between an expected and an actual frame.
final class FrameMismatch {
  const FrameMismatch(this.path, this.message);

  /// JSON path inside the frame, e.g. `$.params.update.status`.
  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

/// The fixture cannot be evaluated: unknown variable, unknown or misplaced
/// matcher, or a matcher the client driver cannot turn into a value.
final class FixtureMatchException implements Exception {
  const FixtureMatchException(this.message);

  final String message;

  @override
  String toString() => 'FixtureMatchException: $message';
}

const _matcherKeys = {
  r'$any',
  r'$absent',
  r'$capture',
  r'$regex',
  r'$contains',
  r'$partial',
  r'$oneOf',
};

/// Fields whose value is replaced by `<ts>` regardless of format (§14.5).
const _timeFields = {'updatedAt', 'timestamp', 'created'};

const _timestampPlaceholder = '<ts>';

/// Value the client driver sends where an `a2c` frame expects `<ts>`.
const fixtureTimestamp = '2026-01-01T00:00:00Z';

final _isoTimestamp = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}');
final _variable = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');

/// Compares frames of one fixture run and keeps its variables: `cwd`,
/// `sessionId` and every `$capture`.
final class FrameMatcher {
  FrameMatcher({required this.cwd, this.replace = const []});

  /// Absolute working directory of the run; `${cwd}` in frames.
  final String cwd;

  /// `normalize.replace` rules of the fixture.
  final List<FixtureReplaceRule> replace;

  /// Variables available as `${name}`. `cwd` is implicit.
  final variables = <String, Object?>{};

  String get _cwdSlash => cwd.replaceAll(r'\', '/');

  /// Compares [actual] with the [expected] template. Captures are committed
  /// to [variables] only when there are no mismatches.
  List<FrameMismatch> match(Object? expected, Object? actual) {
    final mismatches = <FrameMismatch>[];
    final captures = <String, Object?>{};
    _compare(
      _applyRules(expected),
      _applyRules(normalize(actual)),
      r'$',
      mismatches,
      captures,
    );
    if (mismatches.isEmpty) {
      variables.addAll(captures);
    }
    return mismatches;
  }

  /// `match.$text` of a `repeat: "+"` frame: the concatenated
  /// `params.update.content.text` of [actualFrames] equals [expected].
  List<FrameMismatch> matchText(
    String expected,
    Iterable<Object?> actualFrames,
  ) {
    final buffer = StringBuffer();
    for (final (i, frame) in actualFrames.indexed) {
      final text = _textOf(normalize(frame));
      if (text is! String) {
        return [
          FrameMismatch(
            '\$[$i].params.update.content.text',
            'expected a text chunk, got ${_encode(text)}',
          ),
        ];
      }
      buffer.write(text);
    }
    final wanted = _substitute(expected);
    final got = buffer.toString();
    if (wanted == got) {
      return const [];
    }
    return [
      FrameMismatch(
        r'$.params.update.content.text',
        'expected concatenated text ${_encode(wanted)}, got ${_encode(got)}',
      ),
    ];
  }

  /// `unordered`: [actual] frames match [expected] templates in some order.
  List<FrameMismatch> matchUnordered(
    List<Object?> expected,
    List<Object?> actual,
  ) {
    if (expected.length != actual.length) {
      return [
        FrameMismatch(
          r'$',
          'expected ${expected.length} unordered frames, got ${actual.length}',
        ),
      ];
    }
    final normalizedActual = [
      for (final frame in actual) _applyRules(normalize(frame)),
    ];
    final templates = [for (final frame in expected) _applyRules(frame)];
    final captures = <String, Object?>{};

    bool assign(int i, Set<int> used) {
      if (i == templates.length) {
        return true;
      }
      for (var j = 0; j < normalizedActual.length; j++) {
        if (used.contains(j)) {
          continue;
        }
        final attempt = <String, Object?>{...captures};
        final out = <FrameMismatch>[];
        _compare(templates[i], normalizedActual[j], r'$', out, attempt);
        if (out.isEmpty) {
          final before = Map.of(captures);
          captures
            ..clear()
            ..addAll(attempt);
          if (assign(i + 1, {...used, j})) {
            return true;
          }
          captures
            ..clear()
            ..addAll(before);
        }
      }
      return false;
    }

    if (assign(0, {})) {
      variables.addAll(captures);
      return const [];
    }
    return [
      const FrameMismatch(
        r'$',
        'no order of the actual frames matches the unordered frames',
      ),
      for (final (i, template) in templates.indexed)
        for (final mismatch in _compareAlone(template, normalizedActual[i]))
          FrameMismatch('[$i]${mismatch.path.substring(1)}', mismatch.message),
    ];
  }

  /// The actual-side normalization of §14.5: the `cwd` prefix becomes
  /// `${cwd}` and path separators become `/`.
  Object? normalize(Object? actual) => switch (actual) {
    final String s => _normalizeString(s),
    final Map<String, Object?> m => {
      for (final MapEntry(:key, :value) in m.entries) key: normalize(value),
    },
    final List<Object?> l => [for (final item in l) normalize(item)],
    _ => actual,
  };

  /// Turns an `a2c` template into a concrete frame for the client driver:
  /// variables are substituted, `$capture` generates and stores an id,
  /// `$contains`/`$partial`/`$oneOf` give their own value, `$any` a
  /// placeholder string, `$absent` drops the key, `<ts>` a fixed time.
  Object? materialize(Object? template, [String path = r'$']) {
    switch (template) {
      case final String s:
        return s == _timestampPlaceholder
            ? fixtureTimestamp
            : _substitute(s, includeCwd: true);
      case final Map<String, Object?> m when _isMatcher(m):
        final MapEntry(:key, :value) = m.entries.single;
        return switch (key) {
          r'$any' => 'fixture-any',
          r'$capture' =>
            variables[_captureName(value, path)] =
                'fixture-${_captureName(value, path)}',
          r'$contains' => materialize(value, path),
          r'$partial' => materialize(value, path),
          r'$oneOf' when value is List<Object?> && value.isNotEmpty =>
            materialize(value.first, path),
          _ => throw FixtureMatchException(
            '$path: $key cannot be turned into a value for the client run',
          ),
        };
      case final Map<String, Object?> m:
        return {
          for (final MapEntry(:key, :value) in m.entries)
            if (!_isAbsent(value)) key: materialize(value, '$path${_key(key)}'),
        };
      case final List<Object?> l:
        return [
          for (final (i, item) in l.indexed) materialize(item, '$path[$i]'),
        ];
      default:
        return template;
    }
  }

  /// Substitutes known variables in [template] and keeps matchers, e.g. to
  /// show the expected frame in a hook. Variables that are not captured yet
  /// stay as `${name}`.
  Object? substitute(Object? template) => switch (template) {
    final String s => _substitute(s, includeCwd: true, lenient: true),
    final Map<String, Object?> m => {
      for (final MapEntry(:key, :value) in m.entries) key: substitute(value),
    },
    final List<Object?> l => [for (final item in l) substitute(item)],
    _ => template,
  };

  List<FrameMismatch> _compareAlone(Object? expected, Object? actual) {
    final out = <FrameMismatch>[];
    _compare(expected, actual, r'$', out, {...variables});
    return out;
  }

  void _compare(
    Object? expected,
    Object? actual,
    String path,
    List<FrameMismatch> out,
    Map<String, Object?> captures, {
    String? key,
  }) {
    switch (expected) {
      case final Map<String, Object?> m when _isMatcher(m):
        _compareMatcher(m, actual, path, out, captures);
      case final String s:
        final wanted = _substitute(s, captures: captures);
        if (wanted is! String) {
          _compare(wanted, actual, path, out, captures, key: key);
        } else if (wanted == _timestampPlaceholder) {
          final isTime =
              actual is String &&
              (_timeFields.contains(key) || _isTimestamp(actual));
          if (!isTime) {
            out.add(
              FrameMismatch(path, 'expected <ts>, got ${_encode(actual)}'),
            );
          }
        } else if (actual != wanted) {
          _mismatch(out, path, wanted, actual);
        }
      case final Map<String, Object?> m:
        if (actual is! Map<String, Object?>) {
          _mismatch(out, path, m, actual);
          return;
        }
        _compareObject(m, actual, path, out, captures, partial: false);
      case final List<Object?> l:
        if (actual is! List<Object?>) {
          _mismatch(out, path, l, actual);
          return;
        }
        if (l.length != actual.length) {
          out.add(
            FrameMismatch(
              path,
              'expected ${l.length} items, got ${actual.length}: '
              '${_encode(actual)}',
            ),
          );
          return;
        }
        for (var i = 0; i < l.length; i++) {
          _compare(l[i], actual[i], '$path[$i]', out, captures);
        }
      case final num n:
        if (actual is! num || actual != n) {
          _mismatch(out, path, n, actual);
        }
      default:
        if (actual != expected) {
          _mismatch(out, path, expected, actual);
        }
    }
  }

  void _compareObject(
    Map<String, Object?> expected,
    Map<String, Object?> actual,
    String path,
    List<FrameMismatch> out,
    Map<String, Object?> captures, {
    required bool partial,
  }) {
    for (final MapEntry(:key, :value) in expected.entries) {
      final keyPath = '$path${_key(key)}';
      if (_isAbsent(value)) {
        if (actual.containsKey(key)) {
          out.add(
            FrameMismatch(
              keyPath,
              'expected no key, got ${_encode(actual[key])}',
            ),
          );
        }
        continue;
      }
      if (!actual.containsKey(key)) {
        out.add(
          FrameMismatch(keyPath, 'missing key (expected ${_encode(value)})'),
        );
        continue;
      }
      if (key == '_meta' &&
          value is Map<String, Object?> &&
          !_isMatcher(value)) {
        final meta = actual[key];
        if (meta is! Map<String, Object?>) {
          _mismatch(out, keyPath, value, meta);
        } else {
          _compareObject(value, meta, keyPath, out, captures, partial: true);
        }
        continue;
      }
      _compare(value, actual[key], keyPath, out, captures, key: key);
    }
    if (partial) {
      return;
    }
    for (final MapEntry(:key, :value) in actual.entries) {
      if (!expected.containsKey(key) && key != '_meta') {
        out.add(
          FrameMismatch(
            '$path${_key(key)}',
            'unexpected key (got ${_encode(value)})',
          ),
        );
      }
    }
  }

  void _compareMatcher(
    Map<String, Object?> matcher,
    Object? actual,
    String path,
    List<FrameMismatch> out,
    Map<String, Object?> captures,
  ) {
    final MapEntry(:key, :value) = matcher.entries.single;
    switch (key) {
      case r'$any':
        return;
      case r'$capture':
        captures[_captureName(value, path)] = actual;
      case r'$regex':
        if (value is! String) {
          throw FixtureMatchException('$path: \$regex must be a string');
        }
        if (actual is! String || !RegExp(value).hasMatch(actual)) {
          out.add(
            FrameMismatch(
              path,
              'expected a string matching /$value/, got ${_encode(actual)}',
            ),
          );
        }
      case r'$contains':
        final needle = value is String
            ? _substitute(value, captures: captures)
            : throw FixtureMatchException('$path: \$contains must be a string');
        if (actual is! String || !actual.contains('$needle')) {
          out.add(
            FrameMismatch(
              path,
              'expected a string containing ${_encode(needle)}, '
              'got ${_encode(actual)}',
            ),
          );
        }
      case r'$partial':
        if (value is! Map<String, Object?>) {
          throw FixtureMatchException('$path: \$partial must be an object');
        }
        if (actual is! Map<String, Object?>) {
          _mismatch(out, path, value, actual);
          return;
        }
        _compareObject(value, actual, path, out, captures, partial: true);
      case r'$oneOf':
        if (value is! List<Object?> || value.isEmpty) {
          throw FixtureMatchException(
            '$path: \$oneOf must be a non-empty list',
          );
        }
        for (final option in value) {
          final attempt = <String, Object?>{...captures};
          final optionOut = <FrameMismatch>[];
          _compare(option, actual, path, optionOut, attempt);
          if (optionOut.isEmpty) {
            captures.addAll(attempt);
            return;
          }
        }
        out.add(
          FrameMismatch(
            path,
            'expected one of ${_encode(value)}, got ${_encode(actual)}',
          ),
        );
      case r'$absent':
        throw FixtureMatchException(
          '$path: \$absent is only allowed as an object value',
        );
    }
  }

  bool _isMatcher(Map<String, Object?> value) {
    if (value.length != 1 || !value.keys.single.startsWith(r'$')) {
      return false;
    }
    final key = value.keys.single;
    if (!_matcherKeys.contains(key)) {
      throw FixtureMatchException('unknown matcher "$key"');
    }
    return true;
  }

  bool _isAbsent(Object? value) =>
      value is Map<String, Object?> &&
      value.length == 1 &&
      value.containsKey(r'$absent');

  String _captureName(Object? value, String path) => value is String
      ? value
      : throw FixtureMatchException('$path: \$capture must be a name');

  /// Substitutes `${name}` in an expected string. A string that is exactly
  /// one variable keeps the variable's JSON type. `${cwd}` stays as is in
  /// expected frames: the actual side is normalized to it instead.
  Object? _substitute(
    String template, {
    Map<String, Object?> captures = const {},
    bool includeCwd = false,
    bool lenient = false,
  }) {
    Object? lookup(String name) {
      if (name == 'cwd') {
        return cwd;
      }
      if (captures.containsKey(name)) {
        return captures[name];
      }
      if (variables.containsKey(name)) {
        return variables[name];
      }
      if (lenient) {
        return '\${$name}';
      }
      throw FixtureMatchException('unknown variable \${$name}');
    }

    final whole = _variable.matchAsPrefix(template);
    if (whole != null && whole.end == template.length) {
      final name = whole.group(1)!;
      return name == 'cwd' && !includeCwd ? template : lookup(name);
    }
    return template.replaceAllMapped(_variable, (match) {
      final name = match.group(1)!;
      return name == 'cwd' && !includeCwd ? match.group(0)! : '${lookup(name)}';
    });
  }

  String _normalizeString(String value) {
    if (!value.contains(cwd) && !value.contains(_cwdSlash)) {
      return value;
    }
    return value.replaceAll(r'\', '/').replaceAll(_cwdSlash, r'${cwd}');
  }

  Object? _applyRules(Object? frame) {
    var result = frame;
    for (final rule in replace) {
      result = _replaceAt(result, _parsePath(rule.path), 0, rule);
    }
    return result;
  }

  Object? _replaceAt(
    Object? node,
    List<Object> segments,
    int index,
    FixtureReplaceRule rule,
  ) {
    if (index == segments.length) {
      return node is String
          ? node.replaceAll(rule.regex, rule.replacement)
          : node;
    }
    final segment = segments[index];
    if (segment is String && node is Map<String, Object?>) {
      if (!node.containsKey(segment)) {
        return node;
      }
      return {
        ...node,
        segment: _replaceAt(node[segment], segments, index + 1, rule),
      };
    }
    if (segment is int && node is List<Object?> && segment < node.length) {
      return [
        for (final (i, item) in node.indexed)
          i == segment ? _replaceAt(item, segments, index + 1, rule) : item,
      ];
    }
    return node;
  }
}

/// `$.a.b[0].c` → `['a', 'b', 0, 'c']`.
List<Object> _parsePath(String path) {
  final segments = <Object>[];
  final pattern = RegExp(r'\.([^.\[]+)|\[(\d+)\]');
  for (final match in pattern.allMatches(path.substring(1))) {
    segments.add(match.group(1) ?? int.parse(match.group(2)!));
  }
  return segments;
}

Object? _textOf(Object? frame) {
  if (frame case {
    'params': {'update': {'content': {'text': final Object? text}}},
  }) {
    return text;
  }
  return null;
}

bool _isTimestamp(String value) =>
    _isoTimestamp.hasMatch(value) && DateTime.tryParse(value) != null;

void _mismatch(
  List<FrameMismatch> out,
  String path,
  Object? expected,
  Object? actual,
) {
  out.add(
    FrameMismatch(
      path,
      'expected ${_encode(expected)}, got ${_encode(actual)}',
    ),
  );
}

String _encode(Object? value) {
  try {
    return jsonEncode(value);
  } on JsonUnsupportedObjectError {
    return '$value';
  }
}

String _key(String key) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key) ? '.$key' : '["$key"]';
