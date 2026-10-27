import '../connection/connection_profile.dart';

/// Сколько недавних проектов хранится (add-open-project-picker/design.md,
/// Decision 4).
const recentProjectsLimit = 10;

/// Папка, которую пользователь открывал как проект, и когда.
final class RecentProject {
  const RecentProject({required this.path, required this.lastOpenedAt});

  factory RecentProject.fromJson(Map<String, Object?> json) => RecentProject(
    path: json['path']! as String,
    lastOpenedAt: DateTime.parse(json['lastOpenedAt']! as String),
  );

  final String path;
  final DateTime lastOpenedAt;

  Map<String, Object?> toJson() => {
    'path': path,
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is RecentProject &&
      other.path == path &&
      other.lastOpenedAt == lastOpenedAt;

  @override
  int get hashCode => Object.hash(path, lastOpenedAt);
}

/// Порт хранилища недавних проектов, переживающего перезапуск клиента.
///
/// Почему: app хранит список в `shared_preferences`, CLI — в файле; правило
/// «последний открытый — первым, не больше [recentProjectsLimit]» общее
/// (add-open-project-picker/design.md, Decision 4).
///
/// Как использовать: [record] после выбора проекта; [load] не обязан
/// возвращать список по порядку — сортировку по `lastOpenedAt` делает
/// вызывающий.
abstract interface class RecentProjectsStore {
  Future<List<RecentProject>> load();

  /// Отмечает [path] как только что открытый: переносит его в начало и
  /// отбрасывает самые старые записи сверх [recentProjectsLimit].
  Future<void> record(String path);
}

/// Порт хранилища профилей подключения.
///
/// Почему: CLI выбирает агента по сохранённому профилю
/// (`codelab --agent <id>`, этап 6), а секреты в профиль не попадают —
/// только ссылки (design D8).
///
/// Как использовать: [save] заменяет профиль с тем же `id` на месте или
/// добавляет новый в конец; [load] возвращает профили в порядке хранения;
/// [remove] удаляет профиль по `id` (`codelab profiles remove`, design.md
/// change `add-codelab-cli`, D4). App этот порт не использует: форма
/// подключения app — черновик в состоянии Cubit.
abstract interface class ProfileStore {
  Future<List<ConnectionProfile>> load();

  Future<void> save(ConnectionProfile profile);

  /// `true` — профиль с [id] был и удалён; `false` — такого профиля нет.
  Future<bool> remove(String id);
}
