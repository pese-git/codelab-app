final class RecentProject {
  const RecentProject({required this.path, required this.lastOpenedAt});

  final String path;
  final DateTime lastOpenedAt;

  Map<String, Object?> toJson() => {
    'path': path,
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
  };

  factory RecentProject.fromJson(Map<String, Object?> json) => RecentProject(
    path: json['path']! as String,
    lastOpenedAt: DateTime.parse(json['lastOpenedAt']! as String),
  );

  @override
  bool operator ==(Object other) =>
      other is RecentProject &&
      other.path == path &&
      other.lastOpenedAt == lastOpenedAt;

  @override
  int get hashCode => Object.hash(path, lastOpenedAt);
}

/// Stores the directories the user has opened as a "project", surviving
/// application restarts (see add-open-project-picker/design.md, Decision 4).
/// Implementations do not need to return [load] results in any particular
/// order — recency ordering is the caller's (application-layer) concern.
abstract interface class RecentProjectsStore {
  Future<List<RecentProject>> load();

  /// Records [path] as just-opened, moving it to the front if it was already
  /// present. Implementations SHOULD bound the stored list, dropping the
  /// least recently opened entries once a capacity is exceeded.
  Future<void> record(String path);
}
