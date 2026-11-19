/// Эвристический поиск английских литералов интерфейса в коде presentation
/// (design.md change `add-desktop-localization`, D10, риск R3/R8).
///
/// Почему: тексты интерфейса desktop живут в каталогах ARB, а новая строка,
/// написанная литералом мимо каталога, незаметно остаётся английской при
/// русском языке. Сторож — регрессионная сетка для таких строк, в том числе
/// из параллельных changes.
///
/// Для чего: даёт тесту `ui_literals_test.dart` список позиций вида
/// `путь|литерал`; сопоставление с allowlist делает тест.
///
/// Как использовать: `scanUiLiterals(root)` обходит каталоги [uiLiteralDirs].
/// Это эвристика по регулярным выражениям, а не разбор AST: позиции узкие
/// (`Text('…')`, `CodeLabText('…')`, `label:`, `tooltip:`, `placeholder:`,
/// `title:`, `message:`, `content:`, `description:`), литерал считается
/// интерфейсным, если начинается с буквы. Литералы в `application/` проверяет ревью.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Каталоги, где искать литералы, относительно корня репозитория.
const uiLiteralDirs = [
  'apps/codelab_desktop/lib/app',
  'apps/codelab_desktop/lib/features',
  'packages/flutter/codelab_ui/lib/src',
];

/// Литерал, найденный в позиции интерфейсного текста.
typedef UiLiteral = ({String file, int line, String literal});

/// Ключ сопоставления с allowlist: `путь|литерал` (без номера строки,
/// чтобы правка соседнего кода не ломала allowlist).
String uiLiteralKey(UiLiteral l) => '${l.file}|${l.literal}';

// Строковый литерал на первой позиции: одинарные или двойные кавычки.
const _str = r'''(?:r?'([A-Za-z][^'\n]*)'|r?"([A-Za-z][^"\n]*)")''';

final _widgetPosition = RegExp(
  r'\b(?:CodeLabText|Text)\(\s*(?:const\s+)?' + _str,
);
final _namedPosition = RegExp(
  r'\b(?:label|tooltip|placeholder|title|message|content|description)\s*:\s*(?:const\s+)?' +
      _str,
);

/// Найденные литералы под [root]; пути — от [root] со слешами `/`.
List<UiLiteral> scanUiLiterals(String root, {List<String>? dirs}) {
  final found = <(UiLiteral, int)>[];
  for (final rel in dirs ?? uiLiteralDirs) {
    final dir = Directory(p.join(root, rel));
    if (!dir.existsSync()) continue;
    final files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final path = p.split(p.relative(file.path, from: root)).join('/');
      if (_skipped(path)) continue;
      final text = file.readAsStringSync();
      for (final re in [_widgetPosition, _namedPosition]) {
        for (final m in re.allMatches(text)) {
          final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
          if (_inComment(text, m.start)) continue;
          found.add((
            (file: path, line: line, literal: m.group(1) ?? m.group(2)!),
            m.start,
          ));
        }
      }
    }
  }
  // Порядок: файл, затем позиция в файле (две позиции бывают на одной строке).
  found.sort((a, b) {
    final c = a.$1.file.compareTo(b.$1.file);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  return [for (final f in found) f.$1];
}

/// Каталоги сообщений и превью — не интерфейс (D10).
///
/// В `features/` проверяется только `presentation/`: `application/` — дело
/// ревью (D10).
bool _skipped(String path) =>
    path.endsWith('_previews.dart') ||
    path.contains('/l10n/') ||
    (path.contains('/lib/features/') && !path.contains('/presentation/'));

bool _inComment(String text, int offset) {
  final start = text.lastIndexOf('\n', offset) + 1;
  return text.substring(start, offset).contains('//');
}

/// Разбор allowlist: строки `путь | литерал | причина`, `#` — комментарий.
/// Возвращает ключи [uiLiteralKey] и строки без причины.
({Set<String> keys, List<String> withoutReason}) parseAllowlist(String source) {
  final keys = <String>{};
  final withoutReason = <String>[];
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    // Разделитель полей — ` | ` с пробелами. Первое поле — путь, последнее —
    // причина; середина — литерал как есть, он сам может содержать `|`.
    final parts = line.split(' | ');
    if (parts.length < 3 || parts.last.trim().isEmpty) {
      withoutReason.add(line);
      continue;
    }
    final literal = parts.sublist(1, parts.length - 1).join(' | ').trim();
    keys.add('${parts.first.trim()}|$literal');
  }
  return (keys: keys, withoutReason: withoutReason);
}
