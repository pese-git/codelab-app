import 'dart:io';

import 'package:test/test.dart';

import '../support/package_dir.dart';

/// TOOL-1: `AgentTool.execute` is called only by the single execution
/// point `lib/src/tools/executor.dart`.
void main() {
  test('no .execute( call outside tools/executor.dart', () {
    final lib = Directory(corePath('lib'));
    final offenders = <String>[];
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('tools/executor.dart')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        if (line.contains('.execute(')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(offenders, isEmpty);
    expect(
      File(corePath('lib/src/tools/executor.dart')).readAsStringSync(),
      contains('.execute('),
    );
  });
}
