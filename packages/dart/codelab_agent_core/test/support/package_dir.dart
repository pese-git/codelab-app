import 'dart:io';

/// [relative] inside the `codelab_agent_core` package, whether the tests
/// run from the package (`melos run test`) or from the repository root
/// (the Definition of Done command of `09-06-stage-1-llm.md`).
String corePath(String relative) => '${_root.path}/$relative';

final Directory _root = () {
  bool isCore(Directory dir) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    return pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: codelab_agent_core');
  }

  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    if (isCore(dir)) {
      return dir;
    }
    final nested = Directory('${dir.path}/packages/dart/codelab_agent_core');
    if (isCore(nested)) {
      return nested;
    }
    if (dir.parent.path == dir.path) {
      throw StateError('codelab_agent_core is not above ${Directory.current}');
    }
  }
}();
