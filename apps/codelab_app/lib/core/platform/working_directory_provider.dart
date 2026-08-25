import 'dart:io';

abstract interface class WorkingDirectoryProvider {
  String get currentPath;
}

final class IoWorkingDirectoryProvider implements WorkingDirectoryProvider {
  const IoWorkingDirectoryProvider();

  @override
  String get currentPath => Directory.current.path;
}
