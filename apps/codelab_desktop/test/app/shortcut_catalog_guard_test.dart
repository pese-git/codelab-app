// Сторож 1 app: литералов активаторов вне каталога нет (задача 1.5 change
// `add-app-keyboard-page`; design.md D3; spec app-settings «Сочетания app и
// страница «Keyboard» не расходятся», сценарий «Привязка вне списка»).
//
// Читает `lib/**.dart`, кроме сгенерированного `lib/l10n/app_localizations*.dart`,
// и падает с именем файла и строкой на `SingleActivator(`,
// `CharacterActivator(`, `LogicalKeySet(` и сравнении с `LogicalKeyboardKey.`
// (`==`, `!=`). Esc экрана настроек и диалогов берётся из каталога кита
// (`CodeLabShortcut.leaveSettings`, `CodeLabShortcut.closeOverlay`). Красный до
// задачи 1.6: сейчас литерал стоит в `settings_shell.dart`,
// `add_profile_dialog.dart`, `provider_wizard_dialog.dart` и
// `agents_modes_page.dart`. Это правило пакета, а не `rules.dart` сторожа
// импортов (D3).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
/// не считаются.
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

bool _isGeneratedL10n(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.startsWith('lib/l10n/app_localizations') &&
      normalized.endsWith('.dart');
}

void main() {
  test('сторож различает литералы активаторов и комментарии', () {
    expect(
      violationsIn(
        'x.dart',
        'const SingleActivator(LogicalKeyboardKey.escape)',
      ),
      hasLength(1),
    );
    expect(
      violationsIn(
        'x.dart',
        'if (event.logicalKey == LogicalKeyboardKey.a) {}',
      ),
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
    expect(
      violationsIn('x.dart', '// SingleActivator(…) в комментарии'),
      isEmpty,
    );
    expect(
      violationsIn('x.dart', 'final k = CodeLabShortcut.closeOverlay;'),
      isEmpty,
    );
  });

  test('вне каталога кита нет литералов активаторов и сравнений клавиш', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !_isGeneratedL10n(f.path))
        .toList();
    expect(files, isNotEmpty, reason: 'сторож не нашёл исходники app');

    final violations = [
      for (final file in files)
        ...violationsIn(file.path, file.readAsStringSync()),
    ];

    expect(
      violations,
      isEmpty,
      reason:
          'Привязки клавиш берут активаторы из CodeLabShortcut (кит):\n'
          '${violations.join('\n')}',
    );
  });
}
