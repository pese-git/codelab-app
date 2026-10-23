import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/import_scanner.dart';
import 'support/repo_root.dart';
import 'support/rules.dart';

void main() {
  final root = repoRoot();

  for (final rule in rules) {
    test('${rule.dir}: no forbidden imports in lib/', () {
      expect(
        Directory(p.join(root, rule.dir)).existsSync(),
        isTrue,
        reason: '${rule.dir} is listed in rules.dart but does not exist',
      );
      final violations = scan(root, rule);
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  }

  test('reports dart:io imported by a core library', () {
    final tmp = Directory.systemTemp.createTempSync('guard_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'x.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync("import 'a.dart' if (dart.library.io) 'dart:io';\n");

    final violations = scan(tmp.path, PackageRule('.', forbidden: webUnsafe));

    expect(violations.single, endsWith('lib/src/x.dart:1 -> dart:io'));
  });
}
