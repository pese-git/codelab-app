import 'dart:io';

/// Исполняемый `dart` для дочерних процессов тестов.
///
/// Почему: под `flutter test` (`melos run check`, CI) `Platform.resolvedExecutable`
/// — это `flutter_tester`: он не запускает скрипты как `dart` и первой строкой
/// печатает в stdout адрес VM service, а тесты stdio-протоколов читают stdout
/// построчно (PR #158: тесты stdio-транспорта MCP падали только в CI).
///
/// Как использовать: `Process.start(dartExecutable(), [script])` или `command`
/// конфига stdio-сервера. SDK ищется через `FLUTTER_ROOT`, как в
/// `acp_transports_test.dart`; без него — текущий VM, если это `dart`, иначе
/// `dart` из `PATH`.
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
