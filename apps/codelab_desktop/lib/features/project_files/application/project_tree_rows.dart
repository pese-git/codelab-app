import 'package:codelab_client_core/codelab_client_core.dart'
    show DirectoryListing, ProjectEntry, ProjectEntryKind;
import 'package:codelab_ui/codelab_ui.dart'
    show CodeLabFileTreeRowData, CodeLabFileTreeRowKind;

/// Сегменты синтетических строк: `NUL` не бывает в имени POSIX-файла, поэтому
/// ключ строки не совпадёт с настоящей записью `#more` или `#error`.
const _moreSegment = '\u0000more';
const _errorSegment = '\u0000error';

/// Строит плоский список строк дерева из перечислений раскрытых папок.
///
/// Почему отдельная чистая функция: `CodeLabFileTree` виртуализирован и
/// принимает плоский список, а порядок «папка, затем её содержимое» и
/// синтетические строки (`… N more`, ошибка) проще проверить без Cubit и без
/// файловой системы (design.md change `add-file-preview-and-tree`, D1, D6).
///
/// Для чего: единственное место, где перечисления превращаются в строки.
/// Читает только то, что уже есть в [listings] (ключ — папка от корня, `''` —
/// сам корень); новых чтений не вызывает.
///
/// Как использовать: [expanded] — раскрытые папки; [loading] — раскрытые
/// папки, перечисление которых ещё в полёте (строка показывает индикатор);
/// [failed] — папки, чтение которых не удалось (под ними — строка ошибки).
/// Записи [ProjectEntryKind.symlinkOutside] и [ProjectEntryKind.other]
/// остаются строками без раскрытия. Синтетические строки получают пути
/// `<папка>/\u0000more` и `<папка>/\u0000error`: имя с `NUL` невозможно, и ключ
/// не совпадёт с настоящей записью.
List<CodeLabFileTreeRowData> buildProjectTreeRows({
  required Map<String, DirectoryListing> listings,
  required Set<String> expanded,
  Set<String> loading = const {},
  Set<String> failed = const {},
}) {
  final root = listings[''];
  if (root == null) {
    return const [];
  }
  final rows = <CodeLabFileTreeRowData>[];

  void walk(DirectoryListing listing, int depth) {
    for (final entry in listing.entries) {
      final isDirectory = entry.kind == ProjectEntryKind.directory;
      final isOpen = isDirectory && expanded.contains(entry.relativePath);
      rows.add(
        CodeLabFileTreeRowData(
          relativePath: entry.relativePath,
          name: entry.name,
          kind: _kindOf(entry),
          depth: depth,
          expanded: isOpen,
          loading: isOpen && loading.contains(entry.relativePath),
        ),
      );
      if (!isOpen) {
        continue;
      }
      if (failed.contains(entry.relativePath)) {
        rows.add(
          CodeLabFileTreeRowData(
            relativePath: '${entry.relativePath}/$_errorSegment',
            name: 'Cannot read this folder.',
            kind: CodeLabFileTreeRowKind.error,
            depth: depth + 1,
          ),
        );
        continue;
      }
      final children = listings[entry.relativePath];
      if (children != null) {
        walk(children, depth + 1);
      }
    }
    if (listing.omitted > 0) {
      final dir = listing.relativeDir;
      rows.add(
        CodeLabFileTreeRowData(
          relativePath: dir.isEmpty ? _moreSegment : '$dir/$_moreSegment',
          name: '… ${listing.omitted} more',
          kind: CodeLabFileTreeRowKind.more,
          depth: depth,
        ),
      );
    }
  }

  walk(root, 0);
  return rows;
}

CodeLabFileTreeRowKind _kindOf(ProjectEntry entry) => switch (entry.kind) {
  ProjectEntryKind.directory => CodeLabFileTreeRowKind.directory,
  ProjectEntryKind.file => CodeLabFileTreeRowKind.file,
  ProjectEntryKind.symlinkOutside => CodeLabFileTreeRowKind.outsideLink,
  ProjectEntryKind.other => CodeLabFileTreeRowKind.other,
};
