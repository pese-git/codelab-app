import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart'
    show DiagnosticSeverity;
import 'package:codelab_client_io/codelab_client_io.dart' show DirectoryExists;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, RecentProjectsStore;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabRecentProject;

import '../../../core/platform/project_folder_picker.dart';
import 'project_paths.dart';
import 'shell_part.dart';
import 'ui_mappers.dart';

/// Проект и параметры запуска агента.
final class SettingsState {
  const SettingsState({
    this.selectedProjectPath,
    this.recentProjects = const [],
  });

  /// Рабочая папка («проект»), выбранная через «Open Project», — `cwd`
  /// следующей сессии и для stdio, и для WebSocket. `null` — проект не
  /// выбран: папки агента и сессий нет, папка процесса её не заменяет
  /// (require-project-folder/design.md, D1).
  final String? selectedProjectPath;

  /// Недавние проекты, самый свежий первым (design.md, Decision 4).
  final List<CodeLabRecentProject> recentProjects;

  SettingsState _copyWith({
    String? selectedProjectPath,
    List<CodeLabRecentProject>? recentProjects,
  }) => SettingsState(
    selectedProjectPath: selectedProjectPath ?? this.selectedProjectPath,
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
/// подключения и новых сессий, `null` без проекта. Неявной папки нет: ни
/// папка процесса, ни домашняя папка проект не заменяют (D1,
/// `platform-integration.md` §54).
///
/// Как использовать: создаётся вместе с остальными частями
/// (`CodeLabShellParts`) и сразу загружает недавние проекты и проект
/// прошлого запуска из снимка рабочего пространства
/// (`ClientWorkspace.restoreProject`, design D6 change
/// `add-session-list-and-reload`); ошибки хранилищ — предупреждение в
/// журнале, не сбой. С `directoryExists` проект прошлого запуска без папки
/// на диске не восстанавливается, а [missingProjectDirectory] сообщает об
/// исчезнувшей папке до подключения.
final class SettingsCubit extends ShellPartCubit<SettingsState> {
  SettingsCubit({
    required super.changes,
    required ClientWorkspace workspace,
    required ShellDiagnostics diagnostics,
    required ProjectFolderPicker projectFolderPicker,
    required RecentProjectsStore recentProjectsStore,
    DirectoryExists? directoryExists,
    this.projectRestoreTimeout = const Duration(seconds: 2),
  }) : _workspace = workspace,
       _diagnostics = diagnostics,
       _projectFolderPicker = projectFolderPicker,
       _recentProjectsStore = recentProjectsStore,
       _directoryExists = directoryExists,
       super(const SettingsState()) {
    // Недавние проекты прошлого запуска видны до первого открытия выбора.
    unawaited(_loadRecentProjects());
    projectRestored = _restoreProject().whenComplete(
      () => _projectRestoreFinished = true,
    );
    unawaited(projectRestored);
  }

  /// Завершается, когда проект прошлого запуска восстановлен или решено его
  /// не восстанавливать. «Connect on start» ждёт его, чтобы подключиться уже
  /// с папкой проекта (spec app-settings «Блок «Behavior»», D8).
  late final Future<void> projectRestored;

  var _projectRestoreFinished = false;

  /// [projectRestored] уже завершился: действие пользователя ждёт
  /// восстановления, только пока оно идёт ([awaitProject]).
  bool get projectRestoreFinished => _projectRestoreFinished;

  /// Сколько действие пользователя ждёт восстановления проекта (D3). Больше
  /// не ждём: зависшее чтение снимка не должно делать приложение немым.
  /// Параметр конструктора нужен тестам.
  final Duration projectRestoreTimeout;

  /// Проект для действия пользователя (Connect, Reconnect, New session):
  /// выбранный проект, а пока проект прошлого запуска восстанавливается —
  /// после ожидания не дольше [projectRestoreTimeout].
  ///
  /// Почему: действие в первые миллисекунды после старта не должно получать
  /// отказ «нет проекта», когда снимок вот-вот его вернёт (D3). После
  /// таймаута или ошибки восстановления возвращает то, что выбрано к этому
  /// моменту, — возможно `null`. Одна функция для всех действий, чтобы
  /// правило не расходилось. Вызывающий проверяет номер своего намерения
  /// после ожидания (AGENTS.md §9).
  Future<String?> awaitProject() async {
    if (!_projectRestoreFinished) {
      try {
        await projectRestored.timeout(projectRestoreTimeout);
      } on Object {
        // Таймаут или сбой восстановления: берём, что выбрано.
      }
    }
    return projectDirectory;
  }

  final ClientWorkspace _workspace;
  final ShellDiagnostics _diagnostics;
  final ProjectFolderPicker _projectFolderPicker;
  final RecentProjectsStore _recentProjectsStore;

  /// `null` — папка проекта не проверяется (тесты с вымышленными путями).
  final DirectoryExists? _directoryExists;

  /// Папка для `cwd` сессии и процесса агента: выбранный проект без
  /// пробелов по краям; `null` — проект не выбран (пустая строка — не
  /// проект). Запасного варианта нет: `Process.start(workingDirectory: '')`
  /// падает на `chdir`, а домашняя папка — та же неявная папка (D1).
  ///
  /// Вызывающий читает геттер один раз на намерение и передаёт значение
  /// дальше (D3).
  String? get projectDirectory {
    final selected = state.selectedProjectPath?.trim();
    return selected == null || selected.isEmpty ? null : selected;
  }

  /// [path], если его нет на диске; `null` — папка на месте или проверка не
  /// подключена.
  ///
  /// Вызывает `ConnectionCubit` перед запуском локального агента: процесс в
  /// исчезнувшей папке не стартует, а `session/new` с таким `cwd` отклоняет
  /// агент, и обе ошибки не говорят, что дело в папке. Ошибка самой проверки
  /// не блокирует подключение — тогда ответит агент. Папку [path] вызывающий
  /// берёт из [projectDirectory] один раз и передаёт и сюда, и в
  /// `ClientWorkspace` (D3): проект могли сменить, пока шла проверка.
  Future<String?> missingProjectDirectory(String path) async {
    final exists = _directoryExists;
    if (exists == null) {
      return null;
    }
    try {
      return await exists(path) ? null : path;
    } on Object {
      return null;
    }
  }

  /// Выбирает [path] проектом следующей сессии, записывает его в недавние и
  /// сразу перечитывает их — выбор проекта показывает новую запись, не
  /// дожидаясь следующего запуска. Пустой путь и путь из пробелов проектом не
  /// являются и ничего не меняют (D1).
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

  /// Проект прошлого запуска выбирается, только если пользователь ещё не
  /// выбрал свой, пока снимок читался, он не корень файловой системы и его
  /// папка ещё есть на диске.
  /// Исчезнувшая папка не выбирается: иначе первое же подключение упало бы
  /// в ней; пользователь видит предупреждение и выбирает папку заново.
  /// Корень (`/`) оставили версии, подставлявшие папку процесса вместо
  /// проекта; он тоже не выбирается, а сессии такого снимка убирает правило
  /// kit «выбор другого проекта отменяет восстановление» (D10).
  Future<void> _restoreProject() async {
    final project = await _workspace.restoreProject();
    if (isClosed || project == null || state.selectedProjectPath != null) {
      return;
    }
    if (isFilesystemRoot(project)) {
      _diagnostics.record(
        'Project folder from the last run is the filesystem root: $project. '
        'Choose a folder with Open folder….',
        severity: DiagnosticSeverity.warning,
        source: 'project',
      );
      return;
    }
    if (_directoryExists case final exists?) {
      final present = await exists(project).catchError((Object _) => true);
      if (isClosed || state.selectedProjectPath != null) {
        return;
      }
      if (!present) {
        _diagnostics.record(
          'Project folder from the last run no longer exists: $project. '
          'Choose a folder with Open folder….',
          severity: DiagnosticSeverity.warning,
          source: 'project',
        );
        return;
      }
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
