/// Каталог пользовательских тем на `dart:io` (spec `client-themes`).
///
/// ЗАГЛУШКА красного теста 2.1: реализация — задача 2.2.
library;

import 'package:codelab_client_core/codelab_client_core.dart';

final class IoThemeLibrary implements ThemeLibrary {
  /// [home] — `$CODELAB_HOME`; темы лежат в `<home>/themes`.
  IoThemeLibrary({required this.home});

  final String home;

  @override
  Future<List<ThemeEntry>> list() =>
      throw UnimplementedError('io_theme_library: задача 2.2');

  @override
  Future<ThemeImportResult> import(String sourcePath, {bool replace = false}) =>
      throw UnimplementedError('io_theme_library: задача 2.2');
}
