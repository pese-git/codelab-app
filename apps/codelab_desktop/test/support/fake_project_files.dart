import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart';

/// Фальшивый порт `ProjectFiles` для тестов панели Files.
///
/// Почему: настоящая файловая система зависает в fake-async зоне
/// `testWidgets` (`apps/codelab_desktop/AGENTS.md`, «Тесты»), а гонки
/// «поздний результат» нужно воспроизводить по порядку, а не по времени
/// (design.md change `add-file-preview-and-tree`, D12).
///
/// Для чего: дерево задаётся картой, вызовы пишутся в журналы, а ответ на
/// выбранный вызов можно придержать ([gateList], [gateRead]) и отпустить
/// позже.
///
/// Как использовать: [listings] — `root → relativeDir → записи`, [files] —
/// `root → relativePath → просмотр`; [roots] переводит папку в «realpath»
/// (по умолчанию — она же), [missingFolders] даёт `notFound`.
final class FakeProjectFiles implements ProjectFiles {
  FakeProjectFiles({
    Map<String, Map<String, DirectoryListing>>? listings,
    Map<String, Map<String, FilePreview>>? files,
    Map<String, String>? roots,
    Set<String>? missingFolders,
  }) : listings = listings ?? {},
       files = files ?? {},
       roots = roots ?? {},
       missingFolders = missingFolders ?? {};

  final Map<String, Map<String, DirectoryListing>> listings;
  final Map<String, Map<String, FilePreview>> files;
  final Map<String, String> roots;
  final Set<String> missingFolders;

  /// Вызовы `canonicalRoot`, `list` и `read` по порядку.
  final canonicalCalls = <String>[];
  final listCalls = <(String root, String dir)>[];
  final readCalls = <(String root, String path)>[];

  /// Папки и файлы, чтение которых должно завершиться ошибкой.
  final failingDirs = <(String root, String dir), ProjectFilesFailureKind>{};
  final failingFiles = <(String root, String path), ProjectFilesFailureKind>{};

  /// Непредвиденные исключения порта (не `ProjectFilesFailure`): панель не
  /// должна зависать в `loading`, если адаптер бросил что-то своё.
  Object? canonicalError;
  final listErrors = <(String root, String dir), Object>{};
  final readErrors = <(String root, String path), Object>{};

  final _listGates = <(String, String), Completer<void>>{};
  final _readGates = <(String, String), Completer<void>>{};

  /// Придерживает ответ на следующие `list(root, dir)` до `complete()`.
  Completer<void> gateList(String root, String dir) =>
      _listGates[(root, dir)] = Completer<void>();

  /// Придерживает ответ на `read(root, path)` до `complete()`.
  Completer<void> gateRead(String root, String path) =>
      _readGates[(root, path)] = Completer<void>();

  @override
  Future<String> canonicalRoot(String folder) async {
    canonicalCalls.add(folder);
    if (canonicalError case final error?) throw error;
    if (missingFolders.contains(folder)) {
      throw ProjectFilesFailure(ProjectFilesFailureKind.notFound, folder);
    }
    return roots[folder] ?? folder;
  }

  @override
  Future<DirectoryListing> list(
    String root,
    String relativeDir, {
    int maxEntries = 5000,
  }) async {
    listCalls.add((root, relativeDir));
    // Содержимое снимается до ожидания: ответ принадлежит моменту запроса,
    // как у настоящего перечисления.
    final snapshot = listings[root]?[relativeDir];
    await _listGates[(root, relativeDir)]?.future;
    if (listErrors[(root, relativeDir)] case final error?) throw error;
    final failure = failingDirs[(root, relativeDir)];
    if (failure != null) {
      throw ProjectFilesFailure(failure, relativeDir);
    }
    return snapshot ??
        (throw ProjectFilesFailure(
          ProjectFilesFailureKind.notFound,
          relativeDir,
        ));
  }

  @override
  Future<FilePreview> read(
    String root,
    String relativePath, {
    int maxBytes = 1 << 20,
  }) async {
    readCalls.add((root, relativePath));
    final snapshot = files[root]?[relativePath];
    await _readGates[(root, relativePath)]?.future;
    if (readErrors[(root, relativePath)] case final error?) throw error;
    final failure = failingFiles[(root, relativePath)];
    if (failure != null) {
      throw ProjectFilesFailure(failure, relativePath);
    }
    return snapshot ??
        (throw ProjectFilesFailure(
          ProjectFilesFailureKind.notFound,
          relativePath,
        ));
  }
}

/// Запись-файл для [FakeProjectFiles.listings].
ProjectEntry fileEntry(String path, {int? size}) => ProjectEntry(
  relativePath: path,
  name: path.split('/').last,
  kind: ProjectEntryKind.file,
  size: size,
);

/// Запись-папка для [FakeProjectFiles.listings].
ProjectEntry dirEntry(String path) => ProjectEntry(
  relativePath: path,
  name: path.split('/').last,
  kind: ProjectEntryKind.directory,
);

/// Ссылка с целью вне корня.
ProjectEntry outsideEntry(String path) => ProjectEntry(
  relativePath: path,
  name: path.split('/').last,
  kind: ProjectEntryKind.symlinkOutside,
);

/// Перечисление папки [dir] из записей [entries].
DirectoryListing listingOf(
  String dir,
  List<ProjectEntry> entries, {
  int omitted = 0,
}) => DirectoryListing(relativeDir: dir, entries: entries, omitted: omitted);
