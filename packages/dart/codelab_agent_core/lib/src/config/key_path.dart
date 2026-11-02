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

/// Ближайший к [key] из [candidates] ключ для подсказки «did you mean».
///
/// Почему отдельная публичная функция: опечатку в ключе объясняют одним
/// способом и валидатор ядра (неизвестный ключ файла), и хост, который сам
/// разбирает вход вне схемы (предконфигурация провайдера
/// `CODELAB_PROVIDER_CONFIG`, design.md change
/// `add-config-writer-and-reload`, D3). Две копии расходились бы.
///
/// Для чего: порог расстояния Левенштейна ([editDistance]) не больше 2; дальше
/// догадка вводила бы в заблуждение. При равенстве выигрывает первый
/// кандидат.
///
/// Как использовать: `nearestKey('contex_window', fields)` — имя для текста
/// `unknown key (did you mean <имя>?)`; `null` — подсказки нет, текст без неё.
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

/// Сегмент разобранного пути ключа: имя или выбор элемента списка.
///
/// Почему запись: `[github]` у `mcp.servers` — не ключ отображения, а выбор
/// элемента по имени (или по номеру), и читатель пути обязан отличать их от
/// сегмента `"[github]"` в кавычках (§15.4; design.md change
/// `add-config-writer-and-reload`, D5).
typedef KeyPathSegment = ({String value, bool isElement});

/// Разбирает путь ключа, как его пишет [KeyPath]: сегменты через точку,
/// сегмент в кавычках — одно имя (точка и двоеточие внутри не делят его),
/// `[имя]` или `[n]` после сегмента — элемент списка.
///
/// Почему отдельная функция: реестр настроек (`lookup`) и
/// `ConfigSnapshot.get` читают один и тот же формат, и две копии разбора
/// расходились бы на ключах моделей вида `"qwen2.5-coder-32b"`.
///
/// Путь приходит от пользователя (`config set <key>`), поэтому разбор строгий
/// и возвращает `null` для пустого пути, пустого сегмента (`a..b`, `.a`,
/// `a.`), незакрытой кавычки или скобки, пустого `[]` и текста сразу после
/// закрывающей кавычки или скобки: молча «починенный» путь указал бы на
/// другой ключ, чем написал человек.
List<KeyPathSegment>? splitKeyPath(String path) {
  final out = <KeyPathSegment>[];
  final buffer = StringBuffer();
  // Сегмент начат (есть текст, кавычки или он следует за точкой).
  var pending = false;
  // Предыдущий символ закрыл кавычку или скобку: дальше только `.` или `[`.
  var closed = false;

  bool flush() {
    if (!pending) {
      // Пустой сегмент допустим только сразу после `]`.
      return closed;
    }
    out.add((value: buffer.toString(), isElement: false));
    buffer.clear();
    pending = false;
    return true;
  }

  for (var i = 0; i < path.length; i++) {
    final char = path[i];
    if (char == '"') {
      if (buffer.isNotEmpty || pending || closed) {
        return null;
      }
      final end = path.indexOf('"', i + 1);
      if (end < 0) {
        return null;
      }
      buffer.write(path.substring(i + 1, end));
      pending = true;
      closed = true;
      i = end;
    } else if (char == '.') {
      if (!flush()) {
        return null;
      }
      closed = false;
      // После точки обязан идти сегмент: `a.` — ошибка.
      if (i == path.length - 1) {
        return null;
      }
    } else if (char == '[') {
      if (pending) {
        flush();
      } else if (out.isEmpty) {
        return null;
      }
      final end = path.indexOf(']', i);
      if (end < 0 || end == i + 1) {
        return null;
      }
      out.add((value: path.substring(i + 1, end), isElement: true));
      closed = true;
      i = end;
    } else {
      if (closed) {
        return null;
      }
      buffer.write(char);
      pending = true;
    }
  }
  if (pending) {
    flush();
  }
  return out.isEmpty ? null : out;
}
