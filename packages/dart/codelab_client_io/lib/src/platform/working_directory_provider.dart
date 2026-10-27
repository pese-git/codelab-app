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

/// Проверяет, что папка существует.
///
/// Почему: папка проекта из снимка прошлого запуска или из недавних может
/// исчезнуть (удалена, временная папка e2e, отключённый диск); агент,
/// запущенный в ней, падает с непонятной ошибкой процесса, а `session/new`
/// с таким `cwd` — с ошибкой агента.
///
/// Для чего: порт клиента для ранней и понятной проверки папки проекта до
/// восстановления и подключения; файловая система остаётся в
/// инфраструктуре (AGENTS.md §11).
///
/// Как использовать: composition root передаёт [ioDirectoryExists]; тесты —
/// свою функцию или ничего, если проверка не нужна.
typedef DirectoryExists = Future<bool> Function(String path);

/// [DirectoryExists] на `dart:io`.
Future<bool> ioDirectoryExists(String path) => Directory(path).exists();
