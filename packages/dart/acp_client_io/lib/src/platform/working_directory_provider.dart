import 'dart:io';

/// Источник рабочей папки процесса клиента.
///
/// Почему: без выбранного проекта сессия и процесс агента стартуют в рабочей
/// папке клиента (add-open-project-picker/design.md, Goals), а тестам нужна
/// подмена без `Directory.current`.
abstract interface class WorkingDirectoryProvider {
  String get currentPath;
}

/// [WorkingDirectoryProvider] на `Directory.current`.
final class IoWorkingDirectoryProvider implements WorkingDirectoryProvider {
  const IoWorkingDirectoryProvider();

  @override
  String get currentPath => Directory.current.path;
}
