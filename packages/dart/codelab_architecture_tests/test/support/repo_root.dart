import 'dart:io';

import 'package:path/path.dart' as p;

/// The repository root: the nearest directory, from the current one up,
/// whose `pubspec.yaml` declares the pub `workspace:`. Works both from the
/// package directory (`melos run test`) and from the root (`melos run guard`).
String repoRoot() {
  for (var d = Directory.current.absolute.path; ; d = p.dirname(d)) {
    final pubspec = File(p.join(d, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        RegExp(
          r'^workspace:',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync())) {
      return d;
    }
    if (p.dirname(d) == d) {
      throw StateError('No pub workspace root above ${Directory.current.path}');
    }
  }
}
