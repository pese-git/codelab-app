import 'package:codelab_client_core/codelab_client_core.dart';

import 'json_file.dart';

/// [RecentProjectsStore] в общем JSON-файле `$CODELAB_HOME/recent_projects.json`.
///
/// Почему: список недавних проектов общий у app и CLI и не должен зависеть
/// от идентификатора бандла app (change `share-recent-projects-store`, D1).
/// Формат — `{"version": 1, "projects": [{"path", "lastOpenedAt"}]}` по
/// образцу `profiles.json`.
///
/// Для чего: хранит список; правило «одна запись на путь, последний первым,
/// не больше `recentProjectsLimit`» не содержит, а берёт у kit
/// ([mergeRecentProjects], D5).
///
/// Как использовать: `JsonFileRecentProjectsStore(path)`; [clock] — для
/// детерминированных тестов. Нет файла — пустой список. Файл не JSON-объект,
/// с другой `version`, без списка `projects` или с записью неверного вида —
/// `FormatException` (не `TypeError`); [record] и [merge] при этом файл НЕ
/// меняют, чтобы не затереть данные более нового клиента или правку
/// пользователя (D2). Операции одного экземпляра идут по очереди — две
/// записи без ожидания друг друга не теряются, ошибка одной не отменяет
/// следующие (D3). Между процессами порядок не гарантирован: при столкновении
/// может потеряться одна запись, файл остаётся целым (D3).
final class JsonFileRecentProjectsStore implements RecentProjectsStore {
  JsonFileRecentProjectsStore(this.path, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String path;
  final DateTime Function() _clock;

  static const _version = 1;

  /// Хвост очереди операций; ошибки в нём погашены, их получает вызывающий.
  Future<void> _tail = Future<void>.value();

  @override
  Future<List<RecentProject>> load() => _enqueue(_read);

  /// Отмечает [projectPath] как только что открытый.
  ///
  /// Пустой путь — `ArgumentError` до чтения и записи: инварианты записи те
  /// же, что у строгого чтения (D2), иначе собственная запись сделала бы файл
  /// нечитаемым и, по D2, не перезаписываемым.
  @override
  Future<void> record(String projectPath) => _enqueue(() async {
    _requireNonEmptyPath(projectPath);
    final current = await _read();
    await _write(
      mergeRecentProjects([
        RecentProject(path: projectPath, lastOpenedAt: _clock()),
      ], current),
    );
  });

  /// Сливает [projects] с текущим списком: `mergeRecentProjects(projects,
  /// текущий)` (D5).
  ///
  /// Нужен одному потребителю — одноразовому переносу из прежнего хранилища
  /// (D4), поэтому в порт не входит (§13). Запись с пустым `path` — `ArgumentError`
  /// до чтения и записи, файл не меняется (инварианты записи = инварианты
  /// чтения, D2).
  Future<void> merge(Iterable<RecentProject> projects) => _enqueue(() async {
    for (final project in projects) {
      _requireNonEmptyPath(project.path);
    }
    final current = await _read();
    await _write(mergeRecentProjects(projects, current));
  });

  static void _requireNonEmptyPath(String projectPath) {
    if (projectPath.isEmpty) {
      throw ArgumentError.value(projectPath, 'path', 'Must not be empty.');
    }
  }

  /// Ставит [operation] после предыдущих; результат или ошибка уходят
  /// вызывающему, а очередь продолжается (D3).
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<RecentProject>> _read() async {
    final json = await readJsonObject(path);
    if (json == null) {
      return const [];
    }
    if (json['version'] != _version) {
      throw FormatException('Unsupported recent projects version in $path.');
    }
    final projects = json['projects'];
    if (projects is! List<Object?>) {
      throw FormatException('Expected a "projects" list in $path.');
    }
    return [for (final project in projects) _decode(project)];
  }

  RecentProject _decode(Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatException('Expected a project object in $path.');
    }
    final projectPath = json['path'];
    final openedAt = json['lastOpenedAt'];
    if (projectPath is! String || projectPath.isEmpty) {
      throw FormatException('Expected a non-empty "path" in $path.');
    }
    if (openedAt is! String) {
      throw FormatException('Expected a "lastOpenedAt" string in $path.');
    }
    // `DateTime.parse` сам бросает `FormatException` на неверной дате.
    return RecentProject(
      path: projectPath,
      lastOpenedAt: DateTime.parse(openedAt),
    );
  }

  Future<void> _write(List<RecentProject> projects) => writeJsonObject(path, {
    'version': _version,
    'projects': [for (final project in projects) project.toJson()],
  });
}
