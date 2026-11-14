/// Результат чтения «расширений» папки — файлов проекта и навыков — одним
/// значением (design.md change `add-app-skills-page`, D3).
///
/// Почему в ядре: расчёт делает `codelab_agent_io` (`loadProjectExtensions`),
/// а строит по нему вид страницы web-безопасный основной барель
/// `codelab_setup`, которому `dart:io`-пакет импортировать нельзя. Типы —
/// чистые данные рядом с портами `ProjectFiles` и `SkillFiles` (PKG-1:
/// `dart:io` не нужен).
///
/// Для чего: `codelab config check` и страница app получают один и тот же
/// расчёт канонической папки, доверия, корней и исходов двух фаз, а не две
/// копии правил (`AGENTS.md` §14).
///
/// Как использовать: функция хоста возвращает [ProjectExtensions]; потребитель
/// читает исход каждой фазы через `switch` по [PhaseOutcome].
library;

import '../skills/skill_files.dart';
import 'project_files.dart';

/// Исход одной фазы чтения: значение, а не исключение (D3).
///
/// Почему sealed: потребитель обязан обработать таймаут и сбой явно, иначе
/// «не прочитано» стало бы пустым списком и скрыло бы проблему.
sealed class PhaseOutcome<T> {
  const PhaseOutcome();
}

/// Фаза завершилась; [value] — прочитанное порта.
final class PhaseLoaded<T> extends PhaseOutcome<T> {
  const PhaseLoaded(this.value);

  final T value;

  /// Значение не печатается: в нём тела файлов (SETUP-25).
  @override
  String toString() => 'PhaseLoaded';
}

/// Порт не ответил за предел фазы; чтение отменено.
final class PhaseTimedOut extends PhaseOutcome<Never> {
  const PhaseTimedOut();

  @override
  String toString() => 'PhaseTimedOut';
}

/// Порт бросил исключение; [errorType] — только имя типа, без текста:
/// текст может содержать пути и фрагменты файлов (D14 `add-agent-project-files`).
final class PhaseFailed extends PhaseOutcome<Never> {
  const PhaseFailed(this.errorType);

  final String errorType;

  @override
  String toString() => 'PhaseFailed($errorType)';
}

/// Корень навыков с номером [SkillFile.rootIndex] равным позиции в списке
/// `ProjectExtensions.skillRoots` (D3).
///
/// Почему отдельный тип: загрузчик отдаёт навык с номером корня, а подпись
/// источника и путь для «Open» нужны потребителю без повторного расчёта
/// списка корней.
final class SkillRootInfo {
  const SkillRootInfo({
    required this.scope,
    required this.path,
    this.extraRoot,
  });

  /// Проект, пользователь или явный корень `skills.extra_roots`.
  final ExtensionScope scope;

  /// Корень на диске (форма ядра).
  final String path;

  /// Элемент `skills.extra_roots` как записан в конфиге; `null` — корень не
  /// из `extra_roots`.
  final String? extraRoot;

  @override
  String toString() => 'SkillRootInfo(${scope.name} $path)';
}

/// Файлы проекта и навыки папки так, как их прочитает сессия агента.
///
/// Как использовать: получить из `loadProjectExtensions`; тела файлов внутри
/// [projectFiles] и [skills] наружу (в вид, журнал) не выводятся.
final class ProjectExtensions {
  const ProjectExtensions({
    required this.cwd,
    required this.trusted,
    required this.contextRoot,
    required this.codelabHome,
    required this.projectFiles,
    required this.skills,
    required this.skillRoots,
    this.preparationError,
  });

  /// Канонический корень сессии (или исходный путь при ошибке `realpath`).
  final String cwd;

  /// Папка в `trusted_projects`; fail-closed: без `realpath` — `false`.
  final bool trusted;

  /// Уровень, от которого считаются пути `ContextFile` проекта: корень
  /// репозитория либо `cwd`.
  final String contextRoot;

  /// `$CODELAB_HOME` для пути пользовательского `AGENTS.md` на диске.
  final String? codelabHome;

  /// Исход фазы файлов проекта.
  final PhaseOutcome<ProjectFiles> projectFiles;

  /// Исход фазы навыков; `null` — `skills.enabled: false`, фаза не запускалась.
  final PhaseOutcome<SkillFiles>? skills;

  /// Корни навыков по `rootIndex`.
  final List<SkillRootInfo> skillRoots;

  /// Имя типа исключения, если подготовка чтения (окружение, `CODELAB_HOME`)
  /// не удалась и обе фазы не запускались; `null` — подготовка прошла.
  ///
  /// Почему явное поле: сбой подготовки — не сбой порта. `config check`
  /// печатает про него одну строку, а не по строке на фазу (как до
  /// выделения расчёта), и отличает его от двух независимых сбоев портов.
  final String? preparationError;

  @override
  String toString() => 'ProjectExtensions($cwd)';
}
