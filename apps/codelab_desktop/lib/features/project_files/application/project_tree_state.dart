import 'package:codelab_client_core/codelab_client_core.dart'
    show FilePreview, ProjectFilesFailureKind;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabFileTreeRowData;

/// Состояние дерева файлов (машина, а не набор флагов; AGENTS.md §8).
///
/// Почему: «нет папки», «папка пропала», «читаем корень» и «готово» —
/// взаимоисключающие состояния, независимые `isLoading`/`hasError` позволили
/// бы показать невозможные сочетания (design.md change
/// `add-file-preview-and-tree`, D6).
enum ProjectTreeStatus {
  /// Нет ни сессии, ни выбранного проекта (Q13).
  noFolder,

  /// Папки нет на диске: «The project folder does not exist.».
  unavailable,

  /// Корень разрешается и читается.
  loading,

  /// Корень прочитан, дерево показывается.
  ready,
}

/// Состояние просмотра выбранного файла (закрытая иерархия, D6).
///
/// Содержимое файла живёт только здесь, в памяти Cubit: в логи, диагностику,
/// события и снимок рабочего места оно НЕ ДОЛЖНО попадать (D5).
sealed class FilePreviewState {
  const FilePreviewState();
}

/// Файл не выбран.
final class PreviewNone extends FilePreviewState {
  const PreviewNone();
}

/// Файл [path] читается.
final class PreviewLoading extends FilePreviewState {
  const PreviewLoading(this.path);

  final String path;
}

/// Файл [path] прочитан. [preview] — ответ порта (текст, двоичный или слишком
/// большой); [maybeSecret] — имя похоже на файл с секретами (правило kit,
/// Q3, Q15); [line] — строка для подсветки (задел итерации 5).
final class PreviewShown extends FilePreviewState {
  const PreviewShown(
    this.path,
    this.preview, {
    required this.maybeSecret,
    this.line,
  });

  final String path;
  final FilePreview preview;
  final bool maybeSecret;
  final int? line;
}

/// Чтение [path] не удалось по причине [kind].
final class PreviewFailed extends FilePreviewState {
  const PreviewFailed(this.path, this.kind);

  final String path;
  final ProjectFilesFailureKind kind;
}

/// Снимок панели Files: корень, раскрытые папки, строки дерева, выбор и
/// просмотр.
///
/// Как использовать: читает `ProjectFilesPane`; меняет только
/// `ProjectFilesCubit`. [root] — realpath папки (`null`, пока корень не
/// разрешён); [expanded] — раскрытые папки от корня; [rows] — готовый плоский
/// список для `CodeLabFileTree`; [selected] — выбранный файл.
final class ProjectTreeState {
  const ProjectTreeState({
    this.status = ProjectTreeStatus.noFolder,
    this.root,
    this.expanded = const {},
    this.rows = const [],
    this.selected,
    this.preview = const PreviewNone(),
    this.rootOutsideProject = false,
    this.failure,
  });

  final ProjectTreeStatus status;
  final String? root;
  final Set<String> expanded;
  final List<CodeLabFileTreeRowData> rows;
  final String? selected;
  final FilePreviewState preview;
  final bool rootOutsideProject;
  final ProjectFilesFailureKind? failure;

  ProjectTreeState copyWith({
    ProjectTreeStatus? status,
    Object? root = _unset,
    Set<String>? expanded,
    List<CodeLabFileTreeRowData>? rows,
    Object? selected = _unset,
    FilePreviewState? preview,
    bool? rootOutsideProject,
  }) => ProjectTreeState(
    status: status ?? this.status,
    root: identical(root, _unset) ? this.root : root as String?,
    expanded: expanded ?? this.expanded,
    rows: rows ?? this.rows,
    selected: identical(selected, _unset) ? this.selected : selected as String?,
    preview: preview ?? this.preview,
    rootOutsideProject: rootOutsideProject ?? this.rootOutsideProject,
    failure: failure,
  );

  static const Object _unset = Object();
}
