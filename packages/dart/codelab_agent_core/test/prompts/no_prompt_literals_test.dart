import 'dart:io';

import 'package:test/test.dart';

import '../support/package_dir.dart';

void main() {
  // PR-2: тексты промптов живут в prompts/**/*.md; в lib/ нет многострочных
  // строковых литералов, кроме сгенерированного prompts.g.dart.
  test('no multi-line string literals in lib/ outside prompts.g.dart', () {
    final offenders = <String>[];
    final lib = Directory(corePath('lib'));
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('prompts.g.dart')) {
        continue;
      }
      final text = file.readAsStringSync();
      for (final quote in ["'''", '"""']) {
        if (text.contains(quote)) {
          offenders.add('${file.path} ($quote)');
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
