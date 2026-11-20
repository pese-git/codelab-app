// Сторож 1 кита: литералов активаторов вне каталога нет (задача 1.3 change
// `add-app-keyboard-page`; design.md D3; spec app-settings «Сочетания app и
// страница «Keyboard» не расходятся», сценарий «Привязка вне списка»).
//
// Читает `lib/src/**.dart` и падает с именем файла и строкой на
// `SingleActivator(`, `CharacterActivator(`, `LogicalKeySet(` и сравнении с
// `LogicalKeyboardKey.` (`==`, `!=`) вне `atomics/codelab_shortcuts.dart`.
// Красный до задачи 1.4: сейчас литералы лежат в пяти файлах кита. Это
// правило пакета, а не `rules.dart` сторожа импортов (D3).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Единственный файл, где литералы активаторов разрешены (D2).
const _catalogPath = 'lib/src/atomics/codelab_shortcuts.dart';

final _forbidden = <RegExp>[
  RegExp(r'\bSingleActivator\('),
  RegExp(r'\bCharacterActivator\('),
  RegExp(r'\bLogicalKeySet\('),
  RegExp(r'(==|!=)\s*LogicalKeyboardKey\.'),
  RegExp(r'LogicalKeyboardKey\.\w+\s*(==|!=)'),
  // Чтение клавиши события в обход каталога: `event.logicalKey`,
  // `event.physicalKey`, `keys.contains(event.logicalKey)` и т. п.
  RegExp(r'\.(logicalKey|physicalKey)\b'),
  RegExp(r'\bPhysicalKeyboardKey\.'),
  // Выбор по клавише через `switch`.
  RegExp(r'\bcase\s+LogicalKeyboardKey\.'),
  RegExp(r'LogicalKeyboardKey\.\w+\s*=>'),
  RegExp(r'\bLogicalKeySet\.fromSet\('),
  RegExp(r'\bisLogicalKeyPressed\('),
];

/// Нарушения в [source]: строки вида `путь:номер: текст`. Строки-комментарии
/// не считаются: в них литералы называют в пояснениях.
List<String> violationsIn(String path, String source) {
  final result = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) {
      continue;
    }
    if (_forbidden.any((pattern) => pattern.hasMatch(line))) {
      result.add('$path:${i + 1}: ${line.trim()}');
    }
  }
  return result;
}

void main() {
  test('сторож различает литералы активаторов и комментарии', () {
    expect(
      violationsIn('x.dart', 'final a = SingleActivator(k);'),
      hasLength(1),
    );
    expect(
      violationsIn('x.dart', 'if (key == LogicalKeyboardKey.enter) {}'),
      hasLength(1),
    );
    expect(
      violationsIn('x.dart', 'bool b = LogicalKeyboardKey.enter == key;'),
      hasLength(1),
    );
    // Обходы без литерала активатора: чтение клавиши события, `switch` по
    // клавише, `LogicalKeySet.fromSet`, `isLogicalKeyPressed`.
    for (final line in const [
      'if (event.physicalKey == PhysicalKeyboardKey.enter) {}',
      'case LogicalKeyboardKey.enter:',
      'LogicalKeyboardKey.enter => open(),',
      'if (keys.contains(event.logicalKey)) {}',
      'final set = LogicalKeySet.fromSet({a});',
      'if (keyboard.isLogicalKeyPressed(k)) {}',
      'final p = PhysicalKeyboardKey.keyK;',
    ]) {
      expect(violationsIn('x.dart', line), hasLength(1), reason: line);
    }
    expect(violationsIn('x.dart', '/// см. SingleActivator(…)'), isEmpty);
    expect(
      violationsIn('x.dart', 'final k = LogicalKeyboardKey.enter;'),
      isEmpty,
    );
  });

  test('вне каталога нет литералов активаторов и сравнений клавиш', () {
    final files = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.path.replaceAll(r'\', '/') != _catalogPath)
        .toList();
    expect(files, isNotEmpty, reason: 'сторож не нашёл исходники кита');

    final violations = [
      for (final file in files)
        ...violationsIn(file.path, file.readAsStringSync()),
    ];

    expect(
      violations,
      isEmpty,
      reason:
          'Привязки клавиш берут активаторы из CodeLabShortcut '
          '($_catalogPath):\n${violations.join('\n')}',
    );
  });
}
