import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/import_scanner.dart';
import 'support/rules.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('scanner_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String source) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(source);

  List<String> scanPkg(PackageRule rule) => scan(root.path, rule);

  test('reports forbidden import, export and conditional alternatives', () {
    write('pkg/pubspec.yaml', 'name: pkg\n');
    write(
      'pkg/lib/a.dart',
      "import 'dart:io';\nexport 'package:flutter/widgets.dart';\n",
    );
    write(
      'pkg/lib/b.dart',
      "export 'x.dart' if (dart.library.html) 'dart:html';\n",
    );

    expect(scanPkg(const PackageRule('pkg', forbidden: webUnsafe)), [
      'pkg/lib/a.dart:1 -> dart:io',
      'pkg/lib/a.dart:2 -> package:flutter/widgets.dart',
      'pkg/lib/b.dart:1 -> dart:html',
    ]);
  });

  test('scans part files and top-level entry points', () {
    write('pkg/pubspec.yaml', 'name: pkg\n');
    write('pkg/lib/testing.dart', "import 'dart:isolate';\n");
    write(
      'pkg/lib/src/model.g.dart',
      "part of 'model.dart';\nimport 'dart:ffi';\n",
    );

    expect(scanPkg(const PackageRule('pkg', forbidden: webUnsafe)), [
      'pkg/lib/src/model.g.dart:2 -> dart:ffi',
      'pkg/lib/testing.dart:1 -> dart:isolate',
    ]);
  });

  test('excluded files are not checked against forbidden prefixes', () {
    write('pkg/pubspec.yaml', 'name: pkg\n');
    write('pkg/lib/io.dart', "import 'dart:io';\n");
    write('pkg/lib/src/io/stdio.dart', "import 'dart:io';\n");

    final rule = PackageRule(
      'pkg',
      forbidden: webUnsafe,
      exclude: ['lib/io.dart', 'lib/src/io/'],
    );

    expect(scanPkg(rule), isEmpty);
  });

  test('sealExclude reports references into excluded files', () {
    write('pkg/pubspec.yaml', 'name: pkg\n');
    write(
      'pkg/lib/pkg.dart',
      "export 'src/io/stdio.dart';\nimport 'package:pkg/io.dart';\n",
    );
    write('pkg/lib/io.dart', '');
    write('pkg/lib/src/io/stdio.dart', '');

    final rule = PackageRule(
      'pkg',
      forbidden: webUnsafe,
      exclude: ['lib/io.dart', 'lib/src/io/'],
    );

    expect(scanPkg(rule), [
      'pkg/lib/pkg.dart:1 -> src/io/stdio.dart (excluded file)',
      'pkg/lib/pkg.dart:2 -> package:pkg/io.dart (excluded file)',
    ]);
  });

  test('sealExclude: false only lifts prohibitions for a directory in lib', () {
    write('cli/pubspec.yaml', 'name: cli\n');
    write(
      'cli/lib/src/tui/app.dart',
      "import 'package:dart_tui/dart_tui.dart';\n",
    );
    write(
      'cli/lib/src/repl.dart',
      "import 'tui/app.dart';\nimport 'package:cli/src/tui/app.dart';\n",
    );
    write('cli/lib/src/bad.dart', "import 'package:dart_tui/dart_tui.dart';\n");

    final rule = PackageRule(
      'cli/lib/src',
      forbidden: ['package:dart_tui/'],
      exclude: ['tui/'],
      sealExclude: false,
    );

    expect(scanPkg(rule), [
      'cli/lib/src/bad.dart:1 -> package:dart_tui/dart_tui.dart',
    ]);
  });

  test('sealExclude resolves package URIs from a directory rule', () {
    write('cli/pubspec.yaml', 'name: cli\n');
    write('cli/lib/src/tui/app.dart', '');
    write('cli/lib/src/repl.dart', "import 'package:cli/src/tui/app.dart';\n");

    final rule = PackageRule(
      'cli/lib/src',
      forbidden: const [],
      exclude: ['tui/'],
    );

    expect(scanPkg(rule), [
      'cli/lib/src/repl.dart:1 -> package:cli/src/tui/app.dart (excluded file)',
    ]);
  });
}
