import 'dart:io';
import 'dart:typed_data';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:path/path.dart' as p;

/// Предел переходов по цепочке ссылок в [IoProjectFiles._escapesRoot].
const _maxLinkHops = 40;

/// Реализация порта [ProjectFiles] на `dart:io`.
///
/// Почему: браузер файлов читает произвольные пути проекта, а лексической
/// проверки недостаточно — символическая ссылка внутри корня может вести
/// наружу. Поэтому граница считается по realpath и до открытия файла или
/// перечисления папки (design.md change `add-file-preview-and-tree`, D3,
/// Q2; требование `workspace-file-browser` «Граница рабочей папки браузера»).
/// Лексическую проверку `fs/*` (`resolveWithinWorkingDirectory`) не
/// переиспользуем: она не разрешает ссылок и относится к другому решению (D3).
///
/// Для чего: единственное место `dart:io` для панели Files. Политика
/// (нормализация пути, двоичный/большой файл, сортировка) — чистые функции
/// kit; здесь только перенос на файловую систему (AGENTS.md пакета, §2).
///
/// Как использовать: composition root передаёт экземпляр хосту как
/// [ProjectFiles]. `root` берётся из [canonicalRoot]; каждая операция заново
/// считает realpath корня и цели. Ошибки — [ProjectFilesFailure] без
/// содержимого файла.
///
/// Остаточный риск: между проверкой realpath и открытием ссылку могут
/// подменить (TOCTOU); дескриптор в Dart на realpath не проверить. Окно
/// узкое, чтение только на чтение и с лимитом (design.md, «Risks»).
final class IoProjectFiles implements ProjectFiles {
  /// [openRange] — шов для тестов: как открыть диапазон байт файла. Тест
  /// подменяет его, чтобы проверить, что `read` просит не больше
  /// `maxBytes + 1` байт (D4); в рабочем коде остаётся [openFileRange].
  const IoProjectFiles({this.openRange = openFileRange});

  final Stream<List<int>> Function(File file, int? start, int? end) openRange;

  @override
  Future<String> canonicalRoot(String folder) async {
    final resolved = await _realpath(folder, '');
    if (await FileSystemEntity.type(resolved) !=
        FileSystemEntityType.directory) {
      throw const ProjectFilesFailure(ProjectFilesFailureKind.notFound, '');
    }
    return resolved;
  }

  @override
  Future<DirectoryListing> list(
    String root,
    String relativeDir, {
    int maxEntries = 5000,
  }) async {
    final dir = normalizeRelativePath(relativeDir);
    final target = await _resolveInside(root, dir, relativeDir);
    final targetType = await FileSystemEntity.type(target.resolved);
    if (targetType == FileSystemEntityType.notFound) {
      throw ProjectFilesFailure(ProjectFilesFailureKind.notFound, relativeDir);
    }
    // Файл вместо папки — как папка вместо файла в `read`: unreadable.
    if (targetType != FileSystemEntityType.directory) {
      throw ProjectFilesFailure(
        ProjectFilesFailureKind.unreadable,
        relativeDir,
      );
    }

    final found = <ProjectEntry>[];
    try {
      await for (final entity in Directory(
        target.resolved,
      ).list(followLinks: false)) {
        final name = p.basename(entity.path);
        // `.git` скрыт всегда, в том числе файл `.git` рабочих деревьев (Q4).
        if (name == '.git') continue;
        found.add(
          ProjectEntry(
            relativePath: dir.isEmpty ? name : '$dir/$name',
            name: name,
            kind: await _kindOf(entity, target.realRoot),
          ),
        );
      }
    } on FileSystemException {
      throw ProjectFilesFailure(
        ProjectFilesFailureKind.unreadable,
        relativeDir,
      );
    }

    // Сортировка до усечения: «лишними» становятся последние по порядку.
    final sorted = sortProjectEntries(found);
    final kept = sorted.length > maxEntries
        ? sorted.sublist(0, maxEntries)
        : sorted;
    final withSizes = await Future.wait(
      kept.map((e) async {
        if (e.kind != ProjectEntryKind.file) return e;
        final size = await _sizeOrNull(p.joinAll([target.resolved, e.name]));
        return ProjectEntry(
          relativePath: e.relativePath,
          name: e.name,
          kind: e.kind,
          size: size,
        );
      }),
    );
    return DirectoryListing(
      relativeDir: dir,
      entries: withSizes,
      omitted: sorted.length - kept.length,
    );
  }

  @override
  Future<FilePreview> read(
    String root,
    String relativePath, {
    int maxBytes = 1 << 20,
  }) async {
    final rel = normalizeRelativePath(relativePath);
    final target = await _resolveInside(root, rel, relativePath);
    final type = await FileSystemEntity.type(target.resolved);
    if (type == FileSystemEntityType.notFound) {
      throw ProjectFilesFailure(ProjectFilesFailureKind.notFound, relativePath);
    }
    if (type != FileSystemEntityType.file) {
      throw ProjectFilesFailure(
        ProjectFilesFailureKind.unreadable,
        relativePath,
      );
    }
    try {
      final file = File(target.resolved);
      final size = await file.length();
      // Не больше maxBytes + 1 байта: этого достаточно, чтобы отличить
      // файл ровно в лимит от большего, и не читать гигабайты (D4).
      final builder = BytesBuilder(copy: false);
      await for (final chunk in openRange(file, 0, maxBytes + 1)) {
        builder.add(chunk);
      }
      final head = builder.takeBytes();
      return classifyPreview(
        head,
        size: head.length > size ? head.length : size,
        maxBytes: maxBytes,
      );
    } on PathNotFoundException {
      throw ProjectFilesFailure(ProjectFilesFailureKind.notFound, relativePath);
    } on FileSystemException {
      throw ProjectFilesFailure(
        ProjectFilesFailureKind.unreadable,
        relativePath,
      );
    }
  }

  /// realpath [path]; ошибки — в [ProjectFilesFailure] по типу, не по тексту.
  Future<String> _realpath(String path, String relativePath) async {
    // dart:io на части платформ молча обрезает путь по `\0`, поэтому
    // проверка явная и до обращения к диску.
    if (path.contains('\u0000')) {
      throw ProjectFilesFailure(
        ProjectFilesFailureKind.invalidPath,
        relativePath,
      );
    }
    try {
      return await File(path).resolveSymbolicLinks();
    } on PathNotFoundException {
      throw ProjectFilesFailure(ProjectFilesFailureKind.notFound, relativePath);
    } on FileSystemException {
      throw ProjectFilesFailure(
        ProjectFilesFailureKind.unreadable,
        relativePath,
      );
    }
  }

  /// Разрешает [rel] (уже нормализованный) и проверяет границу до чтения.
  ///
  /// Q16: ответ не должен раскрывать, существует ли что-либо вне корня, ни
  /// при какой ошибке разрешения. Если realpath цели упал (кроме
  /// `invalidPath`), путь проходится от корня без перехода по ссылкам
  /// ([_escapesRoot]): уход за корень даёт `outsideRoot`, иначе остаётся
  /// исходная ошибка (`notFound` / `unreadable`).
  Future<({String realRoot, String resolved})> _resolveInside(
    String root,
    String rel,
    String requested,
  ) async {
    final realRoot = await _realpath(root, '');
    // На POSIX дублирует нормализацию kit; это рубеж для Windows (сегменты с
    // `\` и `:`), и он единственный строит путь цели. Не удалять.
    final joined = resolveLexicallyInsideRoot(p.context, realRoot, rel);
    final String resolved;
    try {
      resolved = await _realpath(joined, requested);
    } on ProjectFilesFailure catch (e) {
      if (e.kind == ProjectFilesFailureKind.invalidPath) rethrow;
      if (await _escapesRoot(realRoot, rel)) {
        throw ProjectFilesFailure(
          ProjectFilesFailureKind.outsideRoot,
          requested,
        );
      }
      rethrow;
    }
    if (!_isWithin(realRoot, resolved)) {
      throw ProjectFilesFailure(ProjectFilesFailureKind.outsideRoot, requested);
    }
    return (realRoot: realRoot, resolved: resolved);
  }

  /// Уводит ли путь [rel] за корень, если идти по сегментам от [realRoot] без
  /// автоматического перехода по ссылкам.
  ///
  /// Ссылка, чей realpath вне корня, — да. Ссылка, которая не разрешается
  /// (битая, цикл), — да, если ближайший разрешимый предок её цели вне корня
  /// (`out -> /outside/missing`); внутри корня — нет, исходная ошибка
  /// остаётся. Ссылку, которую нельзя прочитать, считаем уходом наружу:
  /// безопаснее не различать.
  Future<bool> _escapesRoot(String realRoot, String rel) async {
    var current = realRoot;
    for (final segment in rel.isEmpty ? const <String>[] : rel.split('/')) {
      final next = p.join(current, segment);
      final type = await FileSystemEntity.type(next, followLinks: false);
      if (type == FileSystemEntityType.notFound) return false;
      if (type != FileSystemEntityType.link) {
        current = next;
        continue;
      }
      try {
        final resolved = await Link(next).resolveSymbolicLinks();
        if (!_isWithin(realRoot, resolved)) return true;
        current = resolved;
      } on FileSystemException {
        // Ссылка не разрешилась: идём по цепочке ссылок вручную, чтобы
        // `a -> b -> /outside/missing` вёл себя как `a -> /outside/missing`.
        var hop = next;
        final seen = <String>{hop};
        for (var hops = 0; hops < _maxLinkHops; hops++) {
          final String target;
          try {
            target = await Link(hop).target();
          } on FileSystemException {
            return true;
          }
          hop = p.normalize(p.join(p.dirname(hop), target));
          if (!_isWithin(realRoot, hop)) return true;
          if (await FileSystemEntity.type(hop, followLinks: false) !=
              FileSystemEntityType.link) {
            final ancestor = await _nearestResolvable(hop);
            return ancestor == null || !_isWithin(realRoot, ancestor);
          }
          // Цикл целиком внутри корня: наружу он не ведёт, остаётся
          // исходная ошибка.
          if (!seen.add(hop)) return false;
        }
        return true;
      }
    }
    return false;
  }

  /// realpath ближайшего разрешимого предка (или самого [path]); `null`, если
  /// не разрешился даже корень файловой системы.
  Future<String?> _nearestResolvable(String path) async {
    var current = path;
    while (true) {
      try {
        return await File(current).resolveSymbolicLinks();
      } on FileSystemException {
        final parent = p.dirname(current);
        if (parent == current) return null;
        current = parent;
      }
    }
  }

  /// `path == root` или `root + separator` — префикс (не просто строковый:
  /// `/w-evil` не внутри `/w`).
  bool _isWithin(String root, String path) {
    if (path == root) return true;
    final prefix = root.endsWith(p.separator) ? root : '$root${p.separator}';
    return path.startsWith(prefix);
  }

  Future<ProjectEntryKind> _kindOf(
    FileSystemEntity entity,
    String realRoot,
  ) async {
    if (entity is Link) {
      final String resolved;
      try {
        resolved = await entity.resolveSymbolicLinks();
      } on FileSystemException {
        return ProjectEntryKind.other; // битая ссылка
      }
      if (!_isWithin(realRoot, resolved)) {
        return ProjectEntryKind.symlinkOutside;
      }
      return _kindOfType(await FileSystemEntity.type(resolved));
    }
    if (entity is Directory) {
      return ProjectEntryKind.directory;
    }
    if (entity is File) {
      // FIFO, сокет и устройство тоже приходят как File: файл — только
      // обычный файл, остальное `other`, и его не открывают.
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      return type == FileSystemEntityType.file
          ? ProjectEntryKind.file
          : ProjectEntryKind.other;
    }
    return ProjectEntryKind.other;
  }

  ProjectEntryKind _kindOfType(FileSystemEntityType type) {
    if (type == FileSystemEntityType.directory) {
      return ProjectEntryKind.directory;
    }
    if (type == FileSystemEntityType.file) {
      return ProjectEntryKind.file;
    }
    return ProjectEntryKind.other;
  }

  Future<int?> _sizeOrNull(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return null;
    }
  }
}

/// Открывает диапазон `[start, end)` файла; рабочая реализация шва
/// `IoProjectFiles.openRange`.
///
/// Почему отдельная функция: тест подменяет шов и проверяет аргументы, а
/// этой функции отдельный тест проверяет, что `end` реально ограничивает
/// чтение (D4).
Stream<List<int>> openFileRange(File file, int? start, int? end) =>
    file.openRead(start, end);

/// Лексическая проверка и склейка относительного пути [rel] до обращения к
/// диску: единственное место, где строится путь цели.
///
/// Почему: `normalizeRelativePath` kit разбирает только POSIX; на Windows
/// сегмент `a\..\..\b` или `C:` вышел бы за корень уже после склейки
/// (D3). Проверка идёт по правилам [context] платформы.
///
/// Как использовать: [realRoot] — канонический корень. Возвращает склеенный
/// путь, если [rel] относительный, без сегментов с `\` или `:` (только
/// Windows) и после склейки лежит в корне или равен ему; иначе бросает
/// [ProjectFilesFailure] `invalidPath`.
String resolveLexicallyInsideRoot(
  p.Context context,
  String realRoot,
  String rel,
) {
  if (context.isAbsolute(rel)) {
    throw ProjectFilesFailure(ProjectFilesFailureKind.invalidPath, rel);
  }
  final segments = rel.isEmpty ? const <String>[] : rel.split('/');
  if (context.style == p.Style.windows &&
      segments.any((s) => s.contains('\\') || s.contains(':'))) {
    throw ProjectFilesFailure(ProjectFilesFailureKind.invalidPath, rel);
  }
  final joined = context.joinAll([realRoot, ...segments]);
  if (joined != realRoot && !context.isWithin(realRoot, joined)) {
    throw ProjectFilesFailure(ProjectFilesFailureKind.invalidPath, rel);
  }
  return joined;
}
