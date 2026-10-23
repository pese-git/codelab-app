import 'dart:io';

import 'package:path/path.dart' as p;

import 'rules.dart';

final _directive = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''');
final _conditional = RegExp(r'''if\s*\([^)]*\)\s*['"]([^'"]+)['"]''');
final _packageName = RegExp(r'^name:\s*(\S+)', multiLine: true);

/// Violations of [rule] under [root], as `file:line -> URI`.
///
/// Scans every `lib/**/*.dart` file of the rule's directory, including
/// `part` files and top-level entry points, and checks each URI of
/// `import`/`export`/`part` and every alternative of a conditional import.
List<String> scan(String root, PackageRule rule) {
  final base = p.normalize(p.join(root, rule.dir));
  final scansLib = !p.split(rule.dir).contains('lib');
  final dir = Directory(scansLib ? p.join(base, 'lib') : base);
  final package = _findPackage(base);
  final violations = <String>[];
  if (!dir.existsSync()) return violations;

  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final rel = _rel(file.path, base);
    if (_excluded(rel, rule)) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final uris = [
        for (final m in _directive.allMatches(lines[i])) m.group(1)!,
        for (final m in _conditional.allMatches(lines[i])) m.group(1)!,
      ];
      final where = '${_rel(file.path, root)}:${i + 1}';
      for (final uri in uris) {
        if (rule.forbidden.any(uri.startsWith)) {
          violations.add('$where -> $uri');
        } else if (rule.sealExclude && rule.exclude.isNotEmpty) {
          final target = _localTarget(uri, file.path, base, package);
          if (target != null && _excluded(target, rule)) {
            violations.add('$where -> $uri (excluded file)');
          }
        }
      }
    }
  }
  return violations;
}

bool _excluded(String rel, PackageRule rule) =>
    rule.exclude.any((e) => e.endsWith('/') ? rel.startsWith(e) : rel == e);

String _rel(String path, String from) =>
    p.split(p.relative(path, from: from)).join('/');

/// Path of a package-local URI relative to [base], or `null` for URIs of
/// other packages and `dart:` libraries.
String? _localTarget(String uri, String from, String base, _Package? package) {
  if (package != null && uri.startsWith('package:${package.name}/')) {
    final path = uri.substring('package:${package.name}/'.length);
    return _rel(p.join(package.root, 'lib', path), base);
  }
  if (uri.contains(':')) return null;
  return _rel(p.normalize(p.join(p.dirname(from), uri)), base);
}

typedef _Package = ({String name, String root});

/// The nearest enclosing package of [dir]: its name and root directory.
_Package? _findPackage(String dir) {
  for (var d = dir; ; d = p.dirname(d)) {
    final pubspec = File(p.join(d, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final name = _packageName
          .firstMatch(pubspec.readAsStringSync())
          ?.group(1);
      return name == null ? null : (name: name, root: d);
    }
    if (p.dirname(d) == d) return null;
  }
}
