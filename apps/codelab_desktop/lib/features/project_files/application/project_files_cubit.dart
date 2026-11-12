import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        DirectoryListing,
        ProjectEntry,
        ProjectEntryKind,
        ProjectFiles,
        ProjectFilesFailure,
        ProjectFilesFailureKind,
        SessionStatusView,
        WorkspaceState,
        isMaybeSecretFileName;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabFileTreeRowData;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import 'project_tree_rows.dart';
import 'project_tree_state.dart';

/// Папка, которую показывает панель Files: `cwd` сессии в фокусе, а без
/// сессии — папка выбранного проекта.
///
/// Почему: панель «следует за сессией в фокусе» (артборд `Files`, подпись
/// «Panes follow the focused session»), а до первой сессии пользователь уже
/// выбрал проект и ждёт увидеть его файлы (Q13; spec workspace-file-browser
/// «Корень без сессии»).
///
/// Как использовать: чистая функция снимка `WorkspaceState`; `null` — ни
/// сессии, ни проекта. Ничего не проверяет на диске: существование папки
/// решает `ProjectFiles.canonicalRoot`.
String? projectFolderOf(WorkspaceState state) {
  final active = state.activeSessionId;
  if (active != null) {
    for (final session in state.sessions) {
      if (session.id != active) continue;
      // Сессия, не загруженная в текущем соединении (осталась от прежнего
      // подключения или ещё не открыта), показывает папку проекта, как без
      // сессии: её `cwd` ничего не говорит о файлах агента этого соединения
      // (решение пользователя Q17).
      final loaded =
          session.status != SessionStatusView.detached &&
          session.status != SessionStatusView.notLoaded;
      return loaded ? session.cwd : state.projectDirectory;
    }
  }
  return state.projectDirectory;
}

/// Лежит ли [root] внутри [base] (оба — realpath): равен или начинается с
/// `base` и разделителя.
///
/// Почему по realpath, а не по строке: корень сессии объявляет агент, и путь
/// с `..` или ссылка внутри проекта, ведущая наружу, лексически «внутри», а
/// на деле вне; `/tmp/w` и `/private/tmp/w` на macOS — одна папка (Q18).
bool _within(String root, String base) =>
    // Разделитель — платформы (`package:path`, без `dart:io` в feature):
    // на POSIX `\` — обычный символ имени, `/work/app\evil` не внутри
    // `/work/app`.
    p.equals(root, base) || p.isWithin(base, root);

/// Cubit панели Files: корень, ленивое дерево, выбор файла и просмотр.
///
/// Почему в app, а не в kit: раскрытые папки и выбор — UI-состояние окна, а
/// CLI дерево не рисует (design.md change `add-file-preview-and-tree`, D1,
/// Q11). Политика («двоичное», «слишком большое», «секрет», граница корня) —
/// в kit и в `IoProjectFiles`; Cubit только применяет ответы порта.
///
/// Для чего: единственный владелец состояния дерева. Подписывается на
/// `ClientWorkspace.state` и переключает корень при смене сессии в фокусе;
/// раскрытие читает ровно один уровень; «Refresh» перечитывает корень,
/// раскрытые папки и выбранный файл.
///
/// Поздние результаты (AGENTS.md §9, §12; D6): у каждого `list` свой номер на
/// папку, у `read` — номер на панель, у корня — поколение. Результат
/// применяется, только если его номер текущий, поколение не сменилось, а папка
/// всё ещё раскрыта. Подписка на workspace отменяется в [close], после
/// которого результаты ничего не меняют.
///
/// Логи (D5): события `project_files.*` несут только вид сбоя и `session_id`;
/// относительный путь — только на уровне debug; содержимое файла и абсолютные
/// пути не пишутся никогда.
///
/// Как использовать: владелец — окно (`ProjectFilesHolder` в `app_scope.dart`,
/// создаёт лениво, закрывает scope); `ProjectFilesPane` его только читает и не
/// закрывает. [available]/[availability] — доступность панели (Q8): пока её
/// нет, порт не вызывается. Методы вызываются из обработчиков виджета; [toggleDirectory], [selectFile]
/// и [refresh] возвращают `Future`, который удобно ждать в тестах.
final class ProjectFilesCubit extends Cubit<ProjectTreeState> {
  ProjectFilesCubit({
    required ProjectFiles files,
    required ClientWorkspace workspace,
    Logger? logger,
    bool available = true,
    Stream<bool>? availability,
  }) : _files = files,
       _workspace = workspace,
       _logger = logger,
       _available = available,
       super(const ProjectTreeState()) {
    _subscription = workspace.state.listen(_onWorkspace);
    _availabilitySubscription = availability?.listen((value) {
      _available = value;
      _retarget();
    });
    _onWorkspace(workspace.current);
  }

  final ProjectFiles _files;
  final ClientWorkspace _workspace;
  final Logger? _logger;
  late final StreamSubscription<WorkspaceState> _subscription;
  late final StreamSubscription<bool>? _availabilitySubscription;

  /// Панель Files доступна (локальная папка сессии, Q8). Пока нет, Cubit не
  /// обращается к порту вовсе: `cwd` удалённой сессии на локальном диске —
  /// чужой путь, а его проверка могла бы пойти в сеть (autofs, SMB).
  bool _available;
  WorkspaceState? _latest;
  String? _project;

  /// Realpath папки проекта по её пути: одно разрешение на проект (Q18).
  final _projectRoots = <String, String>{};

  /// Папка, для которой построено текущее дерево (до `canonicalRoot`).
  String? _folder;

  /// Поколение корня: растёт при каждой смене папки и отбрасывает всё, что
  /// пришло от прежней.
  var _generation = 0;
  String? _root;

  /// Раскрытые папки по корню: переживают смену сессии в фокусе и возврат
  /// (D6), но не перезапуск окна.
  final _expandedByRoot = <String, Set<String>>{};
  var _expanded = <String>{};

  final _listings = <String, DirectoryListing>{};
  final _loading = <String>{};
  final _failed = <String>{};
  final _listSeq = <String, int>{};
  var _readSeq = 0;
  var _refreshing = false;
  var _outsideProject = false;

  /// Выбранный файл по корню: восстанавливается при возврате к корню (D6).
  final _selectedByRoot = <String, String>{};

  void _onWorkspace(WorkspaceState workspaceState) {
    _latest = workspaceState;
    _retarget();
  }

  /// Выбирает папку по рабочему пространству и доступности и переключает
  /// дерево, если она сменилась. Недоступная панель — «нет папки»: поколение
  /// растёт, идущие чтения обесцениваются, порт не вызывается.
  void _retarget() {
    final workspaceState = _latest;
    if (workspaceState == null) return;
    final folder = _available ? projectFolderOf(workspaceState) : null;
    final project = workspaceState.projectDirectory;
    final projectChanged = project != _project;
    _project = project;
    if (folder == _folder && _generation > 0) {
      if (projectChanged && _root != null && folder != null) {
        unawaited(_updateOutside(_generation, folder));
      }
      return;
    }
    unawaited(_switchTo(folder));
  }

  /// Корень [root] вне папки проекта? Сравнение по realpath обоих; проект,
  /// который не разрешается, считается «вне» — подпись показывается.
  Future<bool> _isOutsideProject(String root, String folder) async {
    final project = _project;
    if (project == null) return false;
    if (folder == project) {
      _projectRoots[project] = root;
      return false;
    }
    var base = _projectRoots[project];
    if (base == null) {
      try {
        base = await _files.canonicalRoot(project);
        _projectRoots[project] = base;
      } on Object {
        return true;
      }
    }
    return !_within(root, base);
  }

  Future<void> _updateOutside(int generation, String folder) async {
    final root = _root;
    if (root == null) return;
    final outside = await _isOutsideProject(root, folder);
    if (_stale(generation)) return;
    _outsideProject = outside;
    if (state.status == ProjectTreeStatus.ready) {
      emit(state.copyWith(rootOutsideProject: outside));
    }
  }

  Future<void> _switchTo(String? folder) async {
    final generation = ++_generation;
    _folder = folder;
    _root = null;
    _expanded = <String>{};
    _listings.clear();
    _loading.clear();
    _failed.clear();
    _listSeq.clear();
    _readSeq++;
    _refreshing = false;
    _outsideProject = false;

    if (folder == null) {
      emit(const ProjectTreeState());
      return;
    }
    emit(const ProjectTreeState(status: ProjectTreeStatus.loading));

    final String root;
    try {
      root = await _files.canonicalRoot(folder);
    } on Object catch (error) {
      // Любое исключение порта, не только `ProjectFilesFailure`: панель не
      // должна зависать в `loading` (AGENTS.md §12).
      if (_stale(generation)) return;
      final kind = _kindOf(error);
      _logFailure('project_files.root_unavailable', error);
      emit(
        ProjectTreeState(status: ProjectTreeStatus.unavailable, failure: kind),
      );
      return;
    }
    if (_stale(generation)) return;
    final outside = await _isOutsideProject(root, folder);
    if (_stale(generation)) return;
    _outsideProject = outside;
    _root = root;
    _expanded = _expandedByRoot.putIfAbsent(root, () => <String>{});

    if (!await _loadDirectory('', generation)) {
      return;
    }
    _log('project_files.root_opened');
    // Раскрытые папки, запомненные для этого корня, перечитываются: дерево
    // могло измениться, пока фокус был на другой сессии.
    await Future.wait([
      for (final dir in _expanded.toList()) _loadDirectory(dir, generation),
    ]);
    if (_stale(generation)) return;
    // Выбор по корню (D6): файл читается заново, если он ещё есть.
    final remembered = _selectedByRoot[root];
    if (remembered != null &&
        _entryOf(remembered)?.kind == ProjectEntryKind.file) {
      await selectFile(remembered);
    }
  }

  /// Раскрывает свёрнутую папку (читает один уровень) или сворачивает
  /// раскрытую. Ссылка наружу, «прочее» и файлы игнорируются.
  Future<void> toggleDirectory(String relativeDir) async {
    if (state.status != ProjectTreeStatus.ready) return;
    final entry = _entryOf(relativeDir);
    if (entry == null || entry.kind != ProjectEntryKind.directory) return;

    if (_expanded.contains(relativeDir)) {
      _collapse(relativeDir);
      _emitTree();
      return;
    }
    _expanded.add(relativeDir);
    _loading.add(relativeDir);
    _emitTree();
    await _loadDirectory(relativeDir, _generation);
  }

  /// Выбирает файл и читает его для просмотра. Не-файлы игнорируются: ссылка
  /// наружу не открывается (Q2).
  Future<void> selectFile(String relativePath) async {
    if (state.status != ProjectTreeStatus.ready) return;
    final entry = _entryOf(relativePath);
    if (entry == null || entry.kind != ProjectEntryKind.file) return;

    final root = _root;
    if (root != null) _selectedByRoot[root] = relativePath;
    emit(
      state.copyWith(
        selected: relativePath,
        preview: PreviewLoading(relativePath),
      ),
    );
    await _readSelected(relativePath, entry.name);
  }

  /// Перечитывает корень, раскрытые папки и выбранный файл (Q9). Повторное
  /// нажатие, пока обновление идёт, игнорируется.
  Future<void> refresh() async {
    if (state.status != ProjectTreeStatus.ready || _refreshing) return;
    final generation = _generation;
    _refreshing = true;
    _log('project_files.refresh');
    try {
      final selected = state.selected;
      final selectedEntry = selected == null ? null : _entryOf(selected);
      await Future.wait([
        _loadDirectory('', generation),
        for (final dir in _expanded.toList()) _loadDirectory(dir, generation),
        if (selected != null && selectedEntry != null)
          _readSelected(selected, selectedEntry.name),
      ]);
    } finally {
      if (generation == _generation) {
        _refreshing = false;
      }
    }
  }

  bool _stale(int generation) => isClosed || generation != _generation;

  ProjectEntry? _entryOf(String relativePath) {
    final slash = relativePath.lastIndexOf('/');
    final parent = slash < 0 ? '' : relativePath.substring(0, slash);
    final entries = _listings[parent]?.entries;
    if (entries == null) return null;
    for (final entry in entries) {
      if (entry.relativePath == relativePath) return entry;
    }
    return null;
  }

  /// Сворачивает [relativeDir] вместе с раскрытыми потомками и обесценивает
  /// их идущие чтения номером.
  void _collapse(String relativeDir) {
    bool inside(String path) =>
        path == relativeDir || path.startsWith('$relativeDir/');
    _expanded.removeWhere(inside);
    for (final key in _listings.keys.where(inside).toList()) {
      _listings.remove(key);
    }
    _loading.removeWhere(inside);
    _failed.removeWhere(inside);
    for (final key in _listSeq.keys.where(inside).toList()) {
      _listSeq[key] = (_listSeq[key] ?? 0) + 1;
    }
  }

  /// Читает один уровень [dir] (пусто — корень). `true`, если результат
  /// применён.
  Future<bool> _loadDirectory(String dir, int generation) async {
    final root = _root;
    if (root == null) return false;
    final seq = _listSeq[dir] = (_listSeq[dir] ?? 0) + 1;
    bool current() =>
        !_stale(generation) &&
        _listSeq[dir] == seq &&
        (dir.isEmpty || _expanded.contains(dir));

    try {
      final listing = await _files.list(root, dir);
      if (!current()) return false;
      _listings[dir] = listing;
      _loading.remove(dir);
      _failed.remove(dir);
      if (dir.isEmpty) {
        // Корень прочитан: дерево готово (`loading` → `ready`).
        emit(
          state.copyWith(
            status: ProjectTreeStatus.ready,
            root: root,
            expanded: Set.of(_expanded),
            rows: _rows(),
            rootOutsideProject: _outsideProject,
          ),
        );
      } else {
        _emitTree();
      }
      return true;
    } on Object catch (error) {
      if (!current()) return false;
      _logFailure('project_files.list_failed', error, path: dir);
      _loading.remove(dir);
      if (dir.isEmpty) {
        emit(
          ProjectTreeState(
            status: ProjectTreeStatus.unavailable,
            failure: _kindOf(error),
          ),
        );
        return false;
      }
      _listings.remove(dir);
      _failed.add(dir);
      _emitTree();
      return false;
    }
  }

  Future<void> _readSelected(String relativePath, String name) async {
    final root = _root;
    if (root == null) return;
    final generation = _generation;
    final seq = ++_readSeq;
    bool current() =>
        !_stale(generation) &&
        seq == _readSeq &&
        state.selected == relativePath;

    try {
      final preview = await _files.read(root, relativePath);
      if (!current()) return;
      _log('project_files.preview_opened', path: relativePath);
      emit(
        state.copyWith(
          preview: PreviewShown(
            relativePath,
            preview,
            maybeSecret: isMaybeSecretFileName(name),
          ),
        ),
      );
    } on Object catch (error) {
      if (!current()) return;
      _logFailure('project_files.read_failed', error, path: relativePath);
      emit(
        state.copyWith(preview: PreviewFailed(relativePath, _kindOf(error))),
      );
    }
  }

  List<CodeLabFileTreeRowData> _rows() => buildProjectTreeRows(
    listings: _listings,
    expanded: _expanded,
    loading: _loading,
    failed: _failed,
  );

  void _emitTree() =>
      emit(state.copyWith(expanded: Set.of(_expanded), rows: _rows()));

  void _log(String event, {String? path}) {
    final logger = _logger;
    if (logger == null) return;
    final session = _workspace.current.activeSessionId?.value;
    final context = <String, Object?>{'session_id': ?session};
    if (path != null) {
      logger.debug(event, context: {...context, 'path': path});
    } else {
      logger.info(event, context: context);
    }
  }

  /// Вид сбоя для состояния: чужое исключение порта считается нечитаемым.
  static ProjectFilesFailureKind _kindOf(Object error) =>
      error is ProjectFilesFailure
      ? error.kind
      : ProjectFilesFailureKind.unreadable;

  /// Пишет сбой видом, а не текстом исключения (в нём может быть путь или
  /// содержимое): `unexpected` — исключение не из контракта порта. Путь —
  /// только в отдельной записи уровня debug (D5).
  void _logFailure(String event, Object error, {String? path}) {
    final logger = _logger;
    if (logger == null) return;
    final session = _workspace.current.activeSessionId?.value;
    final kind = error is ProjectFilesFailure ? error.kind.name : 'unexpected';
    // Для чужого исключения — только его тип: текст может нести путь или
    // содержимое (D5).
    final type = error is ProjectFilesFailure
        ? null
        : error.runtimeType.toString();
    final base = <String, Object?>{
      'session_id': ?session,
      'kind': kind,
      'error_type': ?type,
    };
    logger.warning(event, context: base);
    if (path != null) {
      logger.debug(event, context: {...base, 'path': path});
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _availabilitySubscription?.cancel();
    return super.close();
  }
}
