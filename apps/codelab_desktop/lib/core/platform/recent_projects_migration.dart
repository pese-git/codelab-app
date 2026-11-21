import 'package:codelab_client_core/codelab_client_core.dart'
    show RecentProject, RecentProjectsStore;

/// Список недавних проектов недоступен: `CODELAB_HOME` недопустим.
///
/// Почему: без дома нет файла `recent_projects.json`, а молча писать в другое
/// место нельзя (change `share-recent-projects-store`, D8).
///
/// Для чего: типизированная ошибка (`error-handling.md`) для `load` и
/// `record` у [UnavailableRecentProjectsStore]; `SettingsCubit` ловит её и
/// выводит в диагностику, список остаётся пустым.
///
/// Как использовать: бросается только хранилищем-заглушкой; [reason] —
/// причина от `ConnectionEnvironment.homeProblem`, текст без перевода.
final class RecentProjectsUnavailableException implements Exception {
  const RecentProjectsUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'RecentProjectsUnavailableException: $reason';
}

/// Хранилище недавних проектов при недопустимом `CODELAB_HOME`.
///
/// Почему: composition root не должен падать из-за окружения; как и
/// `UnavailableProfileStore`, заглушка отдаёт ошибку на каждой операции и не
/// создаёт файлов и каталогов (D8). Ключ `shared_preferences` не трогается.
///
/// Для чего: старт, выбор проекта и восстановление сессии продолжаются, а
/// причина видна в диагностике app.
///
/// Как использовать: привязывается в `CodeLabPlatformModule`, когда
/// `ConnectionEnvironment.codelabHome == null`.
///
/// Файл назван по D8 (рядом с будущей обёрткой переноса, итерация 4).
final class UnavailableRecentProjectsStore implements RecentProjectsStore {
  const UnavailableRecentProjectsStore(this.reason);

  final String reason;

  @override
  Future<List<RecentProject>> load() =>
      Future.error(RecentProjectsUnavailableException(reason));

  @override
  Future<void> record(String path) =>
      Future.error(RecentProjectsUnavailableException(reason));
}
