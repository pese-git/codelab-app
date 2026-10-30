/// Путь ключа конфигурации и мелкие чистые помощники слоя конфигурации
/// (`agent-core-architecture` §15.4, §15.5).
///
/// Почему отдельный файл: формат пути — контракт между разборщиком хоста
/// (он кладёт позиции в `ConfigTree.positions`) и валидатором ядра (он их
/// читает), поэтому правило квотирования живёт в одном месте.
library;

final _plainSegment = RegExp(r'^[A-Za-z0-9_./\-]+$');

/// Путь ключа: сегменты через точку, элемент списка — `[имя]` или `[n]`.
///
/// Сегмент с символами вне `A-Za-z0-9_./-` (`llama3.1:70b`, пробел) пишется в
/// кавычках: `providers.ollama.models."llama3.1:70b".context_window`
/// (§15.4). Точка в обычном сегменте не квотируется: ключ `qwen2.5-coder`
/// остаётся читаемым.
extension type const KeyPath(String value) {
  static const root = KeyPath('');

  KeyPath child(String name) {
    final segment = _plainSegment.hasMatch(name) ? name : '"$name"';
    return KeyPath(value.isEmpty ? segment : '$value.$segment');
  }

  /// Элемент списка: `[github]` у `mcp.servers`, `[0]` у остальных.
  KeyPath at(Object index) => KeyPath('$value[$index]');

  bool get isRoot => value.isEmpty;
}

/// Расстояние Левенштейна: подсказка для неизвестного ключа (D6).
///
/// Алгоритм общеизвестный (динамическое программирование по двум строкам).
int editDistance(String a, String b) {
  if (a == b) {
    return 0;
  }
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var best = previous[j - 1] + cost;
      if (previous[j] + 1 < best) {
        best = previous[j] + 1;
      }
      if (current[j - 1] + 1 < best) {
        best = current[j - 1] + 1;
      }
      current[j] = best;
    }
    previous = current;
  }
  return previous[b.length];
}

/// Ближайший ключ с расстоянием ≤ 2 или `null`.
String? nearestKey(String key, Iterable<String> candidates) {
  String? best;
  var bestDistance = 3;
  for (final candidate in candidates) {
    final distance = editDistance(key, candidate);
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

final _duration = RegExp(r'^(\d{1,9})(ms|s|m|h)$');

/// `30s`, `2m`, `1h`, `500ms` (§15.4, тип `duration`); иначе `null`.
Duration? parseConfigDuration(String text) {
  final match = _duration.firstMatch(text);
  if (match == null) {
    return null;
  }
  final amount = int.parse(match.group(1)!);
  return switch (match.group(2)) {
    'ms' => Duration(milliseconds: amount),
    's' => Duration(seconds: amount),
    'm' => Duration(minutes: amount),
    _ => Duration(hours: amount),
  };
}

/// Сегменты абсолютного пути без `.` и `..`: сравнение по компонентам
/// (D7, D9).
List<String> pathComponents(String path) {
  final out = <String>[];
  for (final part in path.split(RegExp(r'[/\\]'))) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (out.isNotEmpty) {
        out.removeLast();
      }
      continue;
    }
    out.add(part);
  }
  return out;
}

/// Путь абсолютный: начинается с `/`, обратной косой черты или буквы диска
/// (`C:`).
bool isAbsolutePath(String path) =>
    path.startsWith('/') ||
    path.startsWith('\\') ||
    RegExp(r'^[A-Za-z]:').hasMatch(path);

/// Один и тот же путь по компонентам после нормализации. Хост передаёт
/// канонические пути (symlink раскрывает он); ядро без `dart:io` их не
/// раскрывает.
bool samePath(String a, String b) {
  if (isAbsolutePath(a) != isAbsolutePath(b)) {
    return false;
  }
  final left = pathComponents(a);
  final right = pathComponents(b);
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
