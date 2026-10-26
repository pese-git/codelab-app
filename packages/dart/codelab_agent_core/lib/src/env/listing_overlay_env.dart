import '../util/result.dart';
import 'execution_env.dart';

/// Env, у которого листинг каталога берётся из другого env
/// (`agent-core-architecture` §4.7, §10.4; design.md change
/// `add-dart-agent-acp-server`, D5).
///
/// Почему: в ACP нет метода листинга, поэтому env через клиента не умеет
/// `listDir`, и без него `ls` и `search` выключены. Когда клиент и агент на
/// одной машине (stdio), каталог можно прочитать локально, а файлы и команды
/// по-прежнему идут через клиента — он показывает правки и терминалы.
///
/// Для чего: [listDir] и [stat] — от [listing], всё остальное
/// (`readText`, `writeText`, `exec`) — от [primary]. `stat` локальный,
/// потому что в ACP нет метода stat: через клиента каталог не проверить, а
/// `search` начинает со stat корня (design.md, D5, D15). Корень сессии —
/// корень [primary].
///
/// Как использовать: ACP-сервер передаёт
/// `ListingOverlayEnv(acpClientEnv, localListing(cwd))` в порты сессии, а
/// сессия оборачивает результат в `BoundedEnv` целиком — граница рабочей
/// папки одна для обоих env, и путь вне корня отклоняется до [listing].
final class ListingOverlayEnv implements ExecutionEnv, DirectoryListing {
  ListingOverlayEnv(this.primary, this.listing);

  final ExecutionEnv primary;

  /// Env с `DirectoryListing`; без него [listDir] — `unsupported`.
  final ExecutionEnv listing;

  @override
  String get cwd => primary.cwd;

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => primary.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      primary.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => listing.stat(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => primary.exec(command, options);

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) async =>
      switch (listing) {
        final DirectoryListing directories => directories.listDir(path),
        _ => Err(FileError(FileErrorCode.unsupported, path)),
      };
}
