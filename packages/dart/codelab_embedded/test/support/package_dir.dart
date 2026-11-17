import 'dart:io';

/// Корень пакета `codelab_embedded` для тестов, запускающих процессы из
/// файлов пакета.
///
/// Почему не `Isolate.resolvePackageUri`: под `flutter test` (так тесты
/// гоняет `melos run test` в CI) он бросает `Unsupported operation`. Как в
/// `codelab_agent_core/test/support/package_dir.dart`, корень ищется вверх
/// от текущей папки — тесты работают и из пакета, и из корня репозитория.
///
/// Как использовать: `embeddedRoot` — абсолютный путь к пакету.
String get embeddedRoot => _root.path;

final Directory _root = () {
  bool isEmbedded(Directory dir) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    return pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: codelab_embedded');
  }

  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    if (isEmbedded(dir)) {
      return dir;
    }
    final nested = Directory('${dir.path}/packages/dart/codelab_embedded');
    if (isEmbedded(nested)) {
      return nested;
    }
    if (dir.parent.path == dir.path) {
      throw StateError('codelab_embedded is not above ${Directory.current}');
    }
  }
}();

/// Исполняемый `dart` для дочерних процессов тестов.
///
/// Почему: под `flutter test` `Platform.resolvedExecutable` — это
/// `flutter_tester`, он не запускает скрипты как `dart`, и процессные тесты
/// зависают (CI PR #214). Тот же приём, что в
/// `codelab_agent_io/test/support/dart_executable.dart`: SDK через
/// `FLUTTER_ROOT`, иначе текущий VM, если это `dart`, иначе `dart` из `PATH`.
///
/// Как использовать: `Process.run(dartExecutable(), [...])` или `command`
/// stdio-сервера MCP в конфиге теста.
String dartExecutable() {
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dart = File('$flutterRoot/bin/cache/dart-sdk/bin/$name');
    if (dart.existsSync()) {
      return dart.path;
    }
  }
  final current = File(Platform.resolvedExecutable);
  return current.uri.pathSegments.last == name ? current.path : name;
}
