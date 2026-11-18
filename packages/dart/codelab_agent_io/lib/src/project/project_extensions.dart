/// Файлы проекта и навыки папки одним расчётом для `config check` и страницы
/// навыков app (design.md change `add-app-skills-page`, D3).
///
/// Почему отдельная функция: канонизация папки, доверие (fail-closed) и две
/// параллельные фазы чтения раньше были приватным кодом `ConfigCommands`.
/// Страница app должна показывать то же, что прочитает сессия, поэтому
/// правило живёт в одном месте, а не в двух копиях (`AGENTS.md` §14).
library;

import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../config/config_loader.dart' show codelabHomeOf, userHomeOf;
import '../env/local_execution_env.dart';
import 'project_files_loader.dart';
import 'project_trust.dart';
import 'skill_roots.dart';

/// Предел каждой фазы по умолчанию: как `_projectFilesTimeout` рантайма
/// (D14 change `add-agent-project-files`), чтобы `check` и страница показывали
/// то, что увидит сессия.
const _defaultPhaseTimeout = Duration(seconds: 5);

/// Сигнатура [loadProjectExtensions]: шов `ConfigCommands` для тестов пути
/// «сбой подготовки», недостижимого через настоящий `check` (конфиг с тем же
/// окружением уже загружен).
typedef ProjectExtensionsLoader =
    Future<ProjectExtensions> Function({
      required String cwd,
      required CoreConfig config,
      required Map<String, String> environment,
      ProjectFilesSource? projectFiles,
      SkillFilesSource? skillFiles,
      Duration timeout,
      Duration? skillsTimeout,
    });

/// Читает файлы проекта и навыки папки [cwd] так, как это сделает сессия.
///
/// Как использовать: [cwd] — как задал пользователь, функция канонизирует его
/// сама (`realpath`; без него проект недоверенный, fail-closed). [config] —
/// конфигурация сессии этой папки, [environment] — окружение агента
/// (`CODELAB_HOME`, `HOME`). Файлы проекта и навыки читаются параллельно,
/// у каждой фазы свой [timeout] (для навыков — [skillsTimeout], если задан) и
/// своя отмена; навыки не читаются при `skills.enabled: false` (тогда
/// `ProjectExtensions.skills == null`).
///
/// Не пишет журнал и не бросает: таймаут, исключение порта (только имя типа) и
/// непредвиденный сбой подготовки — значения [PhaseOutcome]. [projectFiles],
/// [skillFiles] и [skillsTimeout] — швы тестов (и `ConfigCommands`, который
/// передаёт свои): порты и предел навыков подменяются; по умолчанию —
/// `ProjectFilesLoader` и [timeout].
Future<ProjectExtensions> loadProjectExtensions({
  required String cwd,
  required CoreConfig config,
  required Map<String, String> environment,
  ProjectFilesSource? projectFiles,
  SkillFilesSource? skillFiles,
  Duration timeout = _defaultPhaseTimeout,
  Duration? skillsTimeout,
}) async {
  final shown = Directory(cwd).absolute.path;
  try {
    final local = LocalExecutionEnv(cwd: shown, hostEnvironment: environment);
    // Канонизацию и доверие считает одна функция, общая с мостом страницы
    // настроек (SETUP-8, D20.2 change `add-settings-agents-modes`).
    final (cwd: canonical, :trusted) = await projectTrustAt(
      config: config,
      folder: shown,
      environment: environment,
    );
    final codelabHome = codelabHomeOf(environment);
    final userHome = userHomeOf(environment);
    final loader = ProjectFilesLoader(
      home: codelabHome,
      userHome: userHome,
      local: local,
    );
    final projectSource = projectFiles ?? loader;
    final skillsSource = skillFiles ?? loader;
    final (project, skills) = await (
      _phase<ProjectFiles>(
        timeout,
        (cancel) => projectSource.load(
          ProjectFilesQuery(
            cwd: canonical,
            projectTrusted: trusted,
            contextMaxBytes: config.projectContextMaxBytes,
            cancel: cancel,
          ),
        ),
      ),
      config.skills.enabled
          ? _phase<SkillFiles>(
              skillsTimeout ?? timeout,
              (cancel) => skillsSource.loadSkills(
                SkillFilesQuery(
                  cwd: canonical,
                  projectTrusted: trusted,
                  extraRoots: config.skills.extraRoots,
                  cancel: cancel,
                ),
              ),
            )
          : Future<PhaseOutcome<SkillFiles>?>.value(),
    ).wait;
    return ProjectExtensions(
      cwd: canonical,
      trusted: trusted,
      contextRoot: projectLevels(canonical).levels.first,
      codelabHome: codelabHome,
      projectFiles: project,
      skills: skills,
      skillRoots: _skillRoots(
        cwd: canonical,
        trusted: trusted,
        codelabHome: codelabHome,
        userHome: userHome,
        extraRoots: config.skills.extraRoots,
      ),
    );
  } on Object catch (error) {
    // Сбой подготовки (окружение, `CODELAB_HOME`): обе фазы не прочитаны.
    final failed = PhaseFailed('${error.runtimeType}');
    return ProjectExtensions(
      cwd: shown,
      trusted: false,
      contextRoot: shown,
      codelabHome: null,
      projectFiles: failed,
      skills: config.skills.enabled ? failed : null,
      skillRoots: const [],
      preparationError: failed.errorType,
    );
  }
}

/// Одна фаза: порт с собственной отменой и пределом времени. Загрузчик
/// перестаёт читать по токену (D6 `add-agent-project-files`), результат после
/// таймаута выбрасывается.
Future<PhaseOutcome<T>> _phase<T>(
  Duration timeout,
  Future<T> Function(CancelToken cancel) run,
) async {
  final cancel = CancelTokenSource();
  try {
    final value = await Future<T>.sync(
      () => run(cancel.token),
    ).then<T?>((value) => value).timeout(timeout, onTimeout: () => null);
    if (value == null) {
      cancel.cancel();
      return const PhaseTimedOut();
    }
    return PhaseLoaded<T>(value);
  } on Object catch (error) {
    // Только тип исключения: текст может содержать пути и фрагменты (D14).
    cancel.cancel();
    return PhaseFailed('${error.runtimeType}');
  } finally {
    cancel.dispose();
  }
}

/// Проекция плана корней загрузчика в данные для потребителя (D3): тот же
/// `skillRootPlan`, что обходит `ProjectFilesLoader`, поэтому позиция корня
/// равна `SkillFile.rootIndex`.
List<SkillRootInfo> _skillRoots({
  required String cwd,
  required bool trusted,
  required String? codelabHome,
  required String? userHome,
  required List<String> extraRoots,
}) => [
  for (final r in skillRootPlan(
    levels: projectLevels(cwd).levels,
    cwd: cwd,
    trusted: trusted,
    home: codelabHome,
    userHome: userHome,
    extraRoots: extraRoots,
  ).roots)
    SkillRootInfo(scope: r.scope, path: r.path, extraRoot: r.extraRoot),
];
