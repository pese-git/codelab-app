import 'package:codelab_client_core/codelab_client_core.dart'
    show RecentProject, RecentProjectsStore, mergeRecentProjects;

/// [RecentProjectsStore] в памяти для widget-тестов.
///
/// Почему: настоящий файл в `testWidgets` зависал бы в fake-async зоне, а
/// хранилище на `shared_preferences` без мока канала падало бы
/// `MissingPluginException` (change `share-recent-projects-store`, D7;
/// образец — `InMemoryProfileStore`). Настоящий файл проверяют
/// `app_scope_recent_projects_test.dart` и тесты `codelab_client_io`.
///
/// Как использовать: `FakeRecentProjectsStore([RecentProject(...)])` — список
/// прошлого запуска; `CodeLabTestBinding(recentProjects:)` передаёт его
/// как начальный. Правило слияния то же, что у настоящего хранилища
/// (`mergeRecentProjects`): одна запись на путь, последний первым.
final class FakeRecentProjectsStore implements RecentProjectsStore {
  FakeRecentProjectsStore([Iterable<RecentProject> initial = const []])
    : _entries = [...initial];

  /// Начальный список из путей с фиксированным временем открытия.
  factory FakeRecentProjectsStore.ofPaths(Iterable<String> paths) =>
      FakeRecentProjectsStore([
        for (final path in paths)
          RecentProject(path: path, lastOpenedAt: DateTime.utc(2026, 1, 1)),
      ]);

  List<RecentProject> _entries;

  @override
  Future<List<RecentProject>> load() async => List.unmodifiable(_entries);

  @override
  Future<void> record(String path) async {
    _entries = mergeRecentProjects([
      RecentProject(path: path, lastOpenedAt: DateTime.now()),
    ], _entries);
  }
}
