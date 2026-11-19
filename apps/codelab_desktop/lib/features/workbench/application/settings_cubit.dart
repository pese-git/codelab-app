import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart'
    show DiagnosticSeverity, Logger;
import 'package:codelab_client_io/codelab_client_io.dart' show DirectoryExists;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, RecentProjectsStore;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabRecentProject;

import '../../../core/platform/project_folder_picker.dart';
import '../../../core/platform/startup_preferences.dart';
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
    StartupPreferences? startupPreferences,
    Logger? appLogger,
    this.projectRestoreTimeout = const Duration(seconds: 2),
  }) : _workspace = workspace,
       _startupPreferences = startupPreferences,
       _appLogger = appLogger,
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
  /// не восстанавливать. Триггер запуска (`startOnLaunch`, D19) ждёт его, чтобы
  /// стартовать агента уже с папкой проекта.
  late final Future<void> projectRestored;

  var _projectRestoreFinished = false;

  /// [projectRestored] уже завершился: действие пользователя ждёт
  /// восстановления, только пока оно идёт ([awaitProject]).
  bool get projectRestoreFinished => _projectRestoreFinished;

  /// Сколько действие пользователя ждёт восстановления проекта (D3). Больше
  /// не ждём: зависшее чтение снимка не должно делать приложение немым.
  /// Параметр конструктора нужен тестам.
  final Duration projectRestoreTimeout;

  /// Проект для действия пользователя (New session, «Restart agent»):
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

  Future<void> Function(String project)? _onProjectSelected;

  /// Связывает выбор проекта со стартом агента (D13 п. 1).
  ///
  /// Почему метод, а не публичное поле: `ConnectionCubit` создаётся после
  /// этого Cubit, поэтому связь ставится сборкой частей один раз
  /// (`CodeLabShellParts.build`); свободно перезаписываемое поле позволяло бы
  /// любому коду подменить триггер. Восстановление проекта прошлого запуска
  /// ([_restoreProject]) триггер не вызывает — его вызывает `startOnLaunch`
  /// (D19), иначе каждая сборка графа в тестах запускала бы агента.
  ///
  /// Как использовать: сборка зовёт `bindProjectStart(connection.startAgent)`;
  /// тест, который стартует агента явно (D20), зовёт `bindProjectStart(null)`.
  void bindProjectStart(Future<void> Function(String project)? start) =>
      _onProjectSelected = start;

  final ClientWorkspace _workspace;
  final ShellDiagnostics _diagnostics;
  final ProjectFolderPicker _projectFolderPicker;
  final RecentProjectsStore _recentProjectsStore;

  /// Порт настройки «Reopen the last project and its tabs» (D9); `null` —
  /// настройка не читается, проект прошлого запуска открывается всегда.
  final StartupPreferences? _startupPreferences;

  /// Логгер компонента `app` для событий `app.reopen_last_project_*` (D9).
  final Logger? _appLogger;

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
    // Ошибки старта не теряются: `ConnectionCubit` публикует их состоянием
    // соединения и диагностикой, наружу старт не бросает.
    unawaited(_onProjectSelected?.call(trimmed) ?? Future<void>.value());

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
    // Настройка читается до восстановления (D9): при выключенной проект и
    // сессии снимка не поднимаются, а снимок этого запуска пишется как обычно
    // (`startWithoutRestore`), поэтому включение настройки откроет проект
    // последнего запуска, а не двухдневной давности.
    if (!await _reopenLastProject()) {
      if (isClosed) {
        return;
      }
      _appLogger?.info('app.reopen_last_project_skipped');
      _workspace.startWithoutRestore();
      return;
    }
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

  /// Включено ли открытие проекта прошлого запуска. Нечитаемое значение —
  /// «включено» с предупреждением без текста ошибки и значения (CFG-10); ключ
  /// не перезаписывается.
  Future<bool> _reopenLastProject() async {
    final port = _startupPreferences;
    if (port == null) {
      return true;
    }
    final StartupLoad load;
    try {
      load = await port.load();
    } on Object catch (error) {
      // Порт обязан не бросать, но адаптер может нарушить контракт: без
      // защиты не вызвались бы ни `restoreProject`, ни `startWithoutRestore`,
      // и снимок этого запуска не писался бы вовсе (приоритет 3: данные).
      _appLogger?.warning(
        'app.reopen_last_project_unreadable',
        context: {'error_class': error.runtimeType.toString()},
      );
      return true;
    }
    if (load.storedValueInvalid || load.readFailure != null) {
      _appLogger?.warning(
        'app.reopen_last_project_unreadable',
        context: {'error_class': ?load.readFailure},
      );
    }
    return load.reopenLastProject;
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
