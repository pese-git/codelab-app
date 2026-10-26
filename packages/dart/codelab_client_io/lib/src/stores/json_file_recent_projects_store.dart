import 'package:codelab_client_core/codelab_client_core.dart';

import 'json_file.dart';

/// [RecentProjectsStore] в JSON-файле.
///
/// Почему: у CLI нет `shared_preferences`, а правило недавних проектов то же,
/// что в app: последний открытый — первым, не больше `recentProjectsLimit`
/// (add-open-project-picker/design.md, Decision 4; `09-10`, задача 5.8).
///
/// Как использовать: `JsonFileRecentProjectsStore(path)`; [clock] — для
/// детерминированных тестов. Нет файла — пустой список; битый файл —
/// `FormatException`.
final class JsonFileRecentProjectsStore implements RecentProjectsStore {
  JsonFileRecentProjectsStore(this.path, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String path;
  final DateTime Function() _clock;

  @override
  Future<List<RecentProject>> load() async {
    final json = await readJsonObject(path);
    final projects = json?['projects'];
    if (json == null) {
      return const [];
    }
    if (projects is! List<Object?>) {
      throw FormatException('Expected a "projects" list in $path.');
    }
    return [
      for (final project in projects)
        RecentProject.fromJson(project as Map<String, Object?>),
    ];
  }

  @override
  Future<void> record(String projectPath) async {
    final current = await load();
    final updated = [
      RecentProject(path: projectPath, lastOpenedAt: _clock()),
      ...current.where((project) => project.path != projectPath),
    ].take(recentProjectsLimit);
    await writeJsonObject(path, {
      'projects': [for (final project in updated) project.toJson()],
    });
  }
}
