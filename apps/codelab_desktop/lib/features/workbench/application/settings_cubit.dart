import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart'
    show DiagnosticSeverity, Logger;
import 'package:codelab_client_io/codelab_client_io.dart' show DirectoryExists;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, RecentProjectsStore;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabRecentProject;

import '../../../core/platform/local_path_kind.dart';
import '../../../core/platform/project_folder_picker.dart';
import '../../../core/platform/startup_preferences.dart';
import 'project_drop.dart';
import 'project_paths.dart';
import 'shell_part.dart';
import 'ui_mappers.dart';

export 'project_drop.dart';

/// Проект и параметры запуска агента.
final class SettingsState {
  const SettingsState({
    this.selectedProjectPath,
    this.recentProjects = const [],
    this.dropRejection,
  });

  /// Рабочая папка («проект»), выбранная через «Open Project», — `cwd`
  /// следующей сессии и для stdio, и для WebSocket. `null` — проект не
  /// выбран: папки агента и сессий нет, папка процесса её не заменяет
  /// (require-project-folder/design.md, D1).
  final String? selectedProjectPath;

  /// Недавние проекты, самый свежий первым (design.md, Decision 4).
  final List<CodeLabRecentProject> recentProjects;

  /// Отказ последнего броска папки; `null` — отказа нет. Держится до
  /// следующего входа перетаскивания на экран, броска или выбора проекта
  /// (design.md change `add-empty-project-screen`, D4).
  final ProjectDropRejection? dropRejection;

  static const Object _keep = Object();

  SettingsState _copyWith({
    String? selectedProjectPath,
    List<CodeLabRecentProject>? recentProjects,
    Object? dropRejection = _keep,
  }) => SettingsState(
    selectedProjectPath: selectedProjectPath ?? this.selectedProjectPath,
    recentProjects: recentProjects ?? this.recentProjects,
    dropRejection: identical(dropRejection, _keep)
        ? this.dropRejection
        : dropRejection as ProjectDropRejection?,
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
    LocalPathKindOf localPathKind = ioLocalPathKind,
    StartupPreferences? startupPreferences,
    Logger? appLogger,
    this.projectRestoreTimeout = const Duration(seconds: 2),
    bool projectStartHeld = false,
  }) : _projectStartHeld = projectStartHeld,
       _workspace = workspace,
       _startupPreferences = startupPreferences,
       _appLogger = appLogger,
       _diagnostics = diagnostics,
       _projectFolderPicker = projectFolderPicker,
       _recentProjectsStore = recentProjectsStore,
       _directoryExists = directoryExists,
       _localPathKind = localPathKind,
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

  /// Удержание триггера выбора проекта, пока показан onboarding.
  ///
  /// Почему: агент не должен стартовать под onboarding (D5 `add-app-onboarding`:
  /// провайдер, сохранённый на шаге модели, должен действовать при первом
  /// старте), а выбор папки на шаге «Open a project» — единственный триггер,
  /// достижимый до рабочего места (design.md change
  /// `add-onboarding-project-step`, D5). Поэтому пока флаг поднят,
  /// [_selectProject] делает всё, кроме вызова привязанного триггера.
  ///
  /// Как использовать: сборка передаёт `projectStartHeld: true`, если
  /// onboarding показан (`OnboardingStart.show`); снимает удержание
  /// [releaseProjectStart], которое зовёт `CodeLabShellCubit.startOnLaunch()`.
  /// При `CodeLabApp(startOnLaunch: false)` `startOnLaunch()` не зовётся и
  /// удержание не снимается: так бывает только в тестах.
  bool _projectStartHeld;

  /// Снимает удержание триггера выбора проекта (D5).
  ///
  /// Агента сам НЕ стартует: единственный старт после onboarding делает
  /// `ConnectionCubit.startOnLaunch()` в папке, выбранной на шаге или
  /// восстановленной из снимка. Повторный вызов и вызов без удержания —
  /// no-op. Зовёт только `CodeLabShellCubit.startOnLaunch()`; из onboarding
  /// его звать нельзя, иначе старт агента вернётся внутрь onboarding. Если
  /// `startOnLaunch` не вызывается (`CodeLabApp(startOnLaunch: false)`, только
  /// тесты), удержание остаётся.
  void releaseProjectStart() => _projectStartHeld = false;

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

  /// Порт вида брошенного пути (D4).
  final LocalPathKindOf _localPathKind;

  /// Счётчик явных намерений выбора проекта: [selectProject],
  /// [browseForProject] и [openDroppedPaths] его увеличивают. Бросок после
  /// `await` проверки вида применяет результат, только если номер не
  /// изменился: поздний результат не перебивает более новый выбор
  /// (корневой `AGENTS.md` §9, §12; D4). Восстановление проекта прошлого
  /// запуска — не намерение.
  var _projectIntent = 0;

  /// Незавершённый системный диалог выбора папки; единственный источник
  /// истины «диалог открыт» (D7): повторный запрос ждёт его, а не открывает
  /// второй диалог.
  Future<String?>? _picking;

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
  /// являются и ничего не меняют (D1). Любой выбор проекта снимает отказ
  /// последнего броска (D4).
  ///
  /// Возвращает принятую папку (без пробелов по краям) или `null` для пустого
  /// пути и закрытого Cubit: адаптер шага «Open a project» берёт результат
  /// отсюда (`add-onboarding-project-step`, D5).
  Future<String?> selectProject(String path) {
    _projectIntent++;
    return _selectProject(path);
  }

  /// Возвращает принятую папку (без пробелов по краям) или `null` для
  /// пустого пути (D5 `add-onboarding-project-step`).
  Future<String?> _selectProject(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    emit(state._copyWith(selectedProjectPath: trimmed, dropRejection: null));
    _workspace.selectProject(trimmed);
    _diagnostics.record('Selected project: $trimmed.', source: 'project');
    if (_projectStartHeld) {
      // Onboarding ещё показан: старт агента — только `startOnLaunch` после
      // перехода на рабочее место (D5). Путь в событие не пишется (D8).
      _appLogger?.debug('project.start_held');
    } else {
      // Ошибки старта не теряются: `ConnectionCubit` публикует их состоянием
      // соединения и диагностикой, наружу старт не бросает.
      unawaited(_onProjectSelected?.call(trimmed) ?? Future<void>.value());
    }

    try {
      await _recentProjectsStore.record(trimmed);
      if (isClosed) return null;
      await _loadRecentProjects();
    } on Object catch (error) {
      if (isClosed) return null;
      _diagnostics.record(
        'Failed to record recent project: $error',
        severity: DiagnosticSeverity.warning,
        source: 'project',
      );
    }
    return trimmed;
  }

  /// Открывает системный выбор папки; выбранная папка — как [selectProject],
  /// закрытый без выбора диалог ничего не меняет.
  ///
  /// Один диалог за раз (D7): пока диалог открыт, повторный вызов (сайдбар,
  /// «New session» без проекта, Cmd/Ctrl+O) возвращает тот же `Future` и порт
  /// второй раз не вызывает.
  ///
  /// Возвращает путь принятой папки или `null` (отмена, сбой порта, пустой
  /// путь, закрытый Cubit); второй вызывающий получает тот же результат.
  /// Результат нужен шагу «Open a project» onboarding: он завершается только
  /// по принятой папке (design.md change `add-onboarding-project-step`, D5,
  /// D6). Прежние вызывающие через `unawaited` его игнорируют.
  Future<String?> browseForProject() {
    _projectIntent++;
    return _picking ??= _browse().whenComplete(() => _picking = null);
  }

  Future<String?> _browse() async {
    final String? path;
    try {
      path = await _projectFolderPicker.pickFolder(
        initialDirectory: state.selectedProjectPath,
      );
    } on Object catch (error) {
      // Плагин выбора папки может бросить (сбой платформы). Вызывающие
      // запускают выбор через `unawaited` с нескольких триггеров, поэтому
      // ошибка не должна уходить в зону. Текст ошибки может нести путь и в
      // журнал не пишется (корневой `AGENTS.md` §12, §16).
      if (!isClosed) {
        _diagnostics.record(
          'Failed to open the folder picker.',
          severity: DiagnosticSeverity.warning,
          source: 'project',
        );
        // Событие журнала app: только класс ошибки, без текста и пути (D7;
        // по образцу `app.reopen_last_project_unreadable`).
        _appLogger?.warning(
          'project.picker_failed',
          context: {'error_class': error.runtimeType.toString()},
        );
      }
      return null;
    }
    if (isClosed || path == null) {
      return null;
    }
    return selectProject(path);
  }

  /// Принимает пути, брошенные в окно из файлового менеджера ОС (D4).
  ///
  /// Ровно один элемент с локальным путём и видом «папка» — выбор проекта,
  /// как «Open folder…» (недавние, триггер старта агента). Всё остальное —
  /// отказ в [SettingsState.dropRejection] без смены проекта и без старта
  /// агента. Порядок: пустой список — ничего; больше одного — `multiple`
  /// (вид не проверяется); `null` или пустой путь — `unsupported`; иначе вид
  /// пути из порта. Путь не канонизируется. Устаревший или закрытый Cubit
  /// результат отбрасывает ([_projectIntent], `isClosed`).
  ///
  /// Возвращает путь принятой папки или `null` при каждом отказе, пустом
  /// списке и устаревшем результате: шаг onboarding завершается только по
  /// принятой папке, а текст отказа читает из [SettingsState.dropRejection]
  /// (design.md change `add-onboarding-project-step`, D5, D6).
  Future<String?> openDroppedPaths(List<String?> paths) async {
    if (paths.isEmpty) {
      return null;
    }
    final intent = ++_projectIntent;
    if (paths.length > 1) {
      _reject(DropMultiple(paths.length));
      return null;
    }
    final path = paths.single?.trim();
    if (path == null || path.isEmpty || !isLocalAbsolutePath(path)) {
      // Не локальный абсолютный путь: отказ БЕЗ пути (он может нести
      // userinfo URL), вид не запрашивается.
      _reject(const DropUnsupported(null));
      return null;
    }
    LocalPathKind kind;
    try {
      kind = await _localPathKind(path);
    } on Object {
      // Порт обязан не бросать; сбой адаптера — «нельзя открыть».
      kind = LocalPathKind.other;
    }
    if (isClosed || intent != _projectIntent) {
      return null;
    }
    switch (kind) {
      case LocalPathKind.directory:
        final selected = await _selectProject(path);
        if (isClosed) return null;
        _appLogger?.info(
          'project.drop',
          context: {'outcome': 'opened', 'count': 1},
        );
        return selected;
      case LocalPathKind.file:
        _reject(DropNotAFolder(path));
      case LocalPathKind.missing:
        _reject(DropMissing(path));
      case LocalPathKind.other:
        _reject(DropUnsupported(path));
    }
    return null;
  }

  /// Снимает отказ последнего броска: перетаскивание вошло на экран (D4).
  void clearDropRejection() {
    if (state.dropRejection != null) {
      emit(state._copyWith(dropRejection: null));
    }
  }

  /// Отказ: состояние, диагностика `warning` с путём и событие без путей
  /// (корневой `AGENTS.md` §16; D4).
  void _reject(ProjectDropRejection rejection) {
    final (reason, text, count) = switch (rejection) {
      DropNotAFolder(:final path) => (
        'not_a_folder',
        'Dropped item rejected (not_a_folder): $path.',
        1,
      ),
      DropMultiple(:final count) => (
        'multiple',
        'Dropped items rejected (multiple): $count items.',
        count,
      ),
      DropMissing(:final path) => (
        'missing',
        'Dropped item rejected (missing): $path.',
        1,
      ),
      DropUnsupported(:final path) => (
        'unsupported',
        path == null
            ? 'Dropped item rejected (unsupported).'
            : 'Dropped item rejected (unsupported): $path.',
        1,
      ),
    };
    emit(state._copyWith(dropRejection: rejection));
    _diagnostics.record(
      text,
      severity: DiagnosticSeverity.warning,
      source: 'project',
    );
    _appLogger?.info(
      'project.drop',
      context: {'outcome': 'rejected', 'reason': reason, 'count': count},
    );
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
