import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart'
    show DiagnosticSeverity;
import 'package:codelab_client_io/codelab_client_io.dart'
    show WorkingDirectoryProvider;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, RecentProjectsStore;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabRecentProject;

import '../../../core/platform/project_folder_picker.dart';
import 'shell_part.dart';
import 'ui_mappers.dart';

/// Проект и параметры запуска агента.
final class SettingsState {
  const SettingsState({
    this.selectedProjectPath,
    this.runAgentFromProjectDirectory = true,
    this.recentProjects = const [],
  });

  /// Рабочая папка («проект»), выбранная через «Open Project», — `cwd`
  /// следующей сессии и для stdio, и для WebSocket. `null` — проект не
  /// выбран, тогда берётся `WorkingDirectoryProvider.currentPath`
  /// (add-open-project-picker/design.md, Decision 1).
  final String? selectedProjectPath;

  /// Только stdio: процесс агента запускается в папке проекта. По умолчанию
  /// `true` — прежнее неявное «cwd процесса == проект» (design.md,
  /// Decision 2).
  final bool runAgentFromProjectDirectory;

  /// Недавние проекты, самый свежий первым (design.md, Decision 4).
  final List<CodeLabRecentProject> recentProjects;

  SettingsState _copyWith({
    String? selectedProjectPath,
    bool? runAgentFromProjectDirectory,
    List<CodeLabRecentProject>? recentProjects,
  }) => SettingsState(
    selectedProjectPath: selectedProjectPath ?? this.selectedProjectPath,
    runAgentFromProjectDirectory:
        runAgentFromProjectDirectory ?? this.runAgentFromProjectDirectory,
    recentProjects: recentProjects ?? this.recentProjects,
  );
}

/// Выбор проекта, недавние проекты и запуск агента из папки проекта.
///
/// Почему: выбор папки — плагин `file_selector`, хранение недавних —
/// `shared_preferences`, поэтому эта часть остаётся в app (таблица переноса
/// `09-10`, строка «Проект»; design D10 change `extract-acp-client-kit`).
///
/// Для чего: владелец выбранного проекта; [projectDirectory] — `cwd` для
/// подключения и новых сессий.
///
/// Как использовать: создаётся вместе с остальными частями
/// (`CodeLabShellParts`) и сразу загружает недавние проекты и проект
/// прошлого запуска из снимка рабочего пространства
/// (`ClientWorkspace.restoreProject`, design D6 change
/// `add-session-list-and-reload`); ошибки хранилищ — предупреждение в
/// журнале, не сбой.
final class SettingsCubit extends ShellPartCubit<SettingsState> {
  SettingsCubit({
    required super.changes,
    required ClientWorkspace workspace,
    required ShellDiagnostics diagnostics,
    required WorkingDirectoryProvider workingDirectoryProvider,
    required ProjectFolderPicker projectFolderPicker,
    required RecentProjectsStore recentProjectsStore,
  }) : _workspace = workspace,
       _diagnostics = diagnostics,
       _workingDirectoryProvider = workingDirectoryProvider,
       _projectFolderPicker = projectFolderPicker,
       _recentProjectsStore = recentProjectsStore,
       super(const SettingsState()) {
    // Недавние проекты прошлого запуска видны до первого открытия выбора.
    unawaited(_loadRecentProjects());
    unawaited(_restoreProject());
  }

  final ClientWorkspace _workspace;
  final ShellDiagnostics _diagnostics;
  final WorkingDirectoryProvider _workingDirectoryProvider;
  final ProjectFolderPicker _projectFolderPicker;
  final RecentProjectsStore _recentProjectsStore;

  /// Папка для `cwd` сессии и процесса агента: выбранный проект, иначе
  /// текущая папка процесса CodeLab (add-open-project-picker/design.md,
  /// Goals).
  String get projectDirectory {
    final selected = state.selectedProjectPath?.trim();
    return selected == null || selected.isEmpty
        ? _workingDirectoryProvider.currentPath
        : selected;
  }

  /// Выбирает [path] проектом следующей сессии, записывает его в недавние и
  /// сразу перечитывает их — выбор проекта показывает новую запись, не
  /// дожидаясь следующего запуска.
  Future<void> selectProject(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }

    emit(state._copyWith(selectedProjectPath: trimmed));
    _workspace.selectProject(trimmed);
    _diagnostics.record('Selected project: $trimmed.', source: 'project');

    try {
      await _recentProjectsStore.record(trimmed);
      if (isClosed) return;
      await _loadRecentProjects();
    } on Object catch (error) {
      if (isClosed) return;
      _diagnostics.record(
        'Failed to record recent project: $error',
        severity: DiagnosticSeverity.warning,
        source: 'project',
      );
    }
  }

  /// Открывает системный выбор папки; выбранная папка — как [selectProject],
  /// закрытый без выбора диалог ничего не меняет.
  Future<void> browseForProject() async {
    final path = await _projectFolderPicker.pickFolder(
      initialDirectory: state.selectedProjectPath,
    );
    if (isClosed || path == null) {
      return;
    }
    await selectProject(path);
  }

  void toggleRunAgentFromProjectDirectory(bool value) =>
      emit(state._copyWith(runAgentFromProjectDirectory: value));

  /// Проект прошлого запуска выбирается, только если пользователь ещё не
  /// выбрал свой, пока снимок читался.
  Future<void> _restoreProject() async {
    final project = await _workspace.restoreProject();
    if (isClosed || project == null || state.selectedProjectPath != null) {
      return;
    }
    emit(state._copyWith(selectedProjectPath: project));
    _workspace.selectProject(project);
  }

  /// Сбой хранилища не мешает работать: остаются прежние недавние проекты.
  Future<void> _loadRecentProjects() async {
    try {
      final recents = await _recentProjectsStore.load();
      if (isClosed) return;
      emit(state._copyWith(recentProjects: recentProjectsOf(recents)));
    } on Object catch (error) {
      if (isClosed) return;
      _diagnostics.record(
        'Failed to load recent projects: $error',
        severity: DiagnosticSeverity.warning,
        source: 'project',
      );
    }
  }
}
