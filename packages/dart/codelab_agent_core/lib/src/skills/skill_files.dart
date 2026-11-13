/// Порт файлов навыков и его данные (design.md change `add-agent-skills`,
/// D1, D16; `agent-core-architecture` §17.2.3).
///
/// Почему отдельный порт, а не поле `ProjectFiles`: у навыков свой таймаут и
/// своя отмена — медленный корень навыков не должен отнимать у сессии
/// `AGENTS.md`; кроме того, чтение идёт до ответа `session/new`, когда у
/// клиента ещё нет `sessionId`, а ядро не имеет `dart:io` (PKG-1).
///
/// Для чего: хост читает файлы и разбирает YAML (CFG-5), ядро проверяет поля
/// и строит каталог чистой функцией `parseSkills`.
///
/// Как использовать: хост кладёт реализацию в `AgentCoreServices.skillFiles`
/// (`ProjectFilesLoader` из `codelab_agent_io` реализует оба порта); `null`
/// значит «навыков нет».
library;

import '../cancel/cancel_token.dart';
import '../config/config_tree.dart';
import '../project/project_files.dart';

/// Запрос порту: всё нужное приходит в нём, а не из состояния сессии.
final class SkillFilesQuery {
  const SkillFilesQuery({
    required this.cwd,
    required this.projectTrusted,
    this.extraRoots = const [],
    required this.cancel,
  });

  /// Канонический корень сессии.
  final String cwd;

  /// Проект доверенный (тот же расчёт, что у `ProjectFilesQuery`; без
  /// раскрытого `realpath` — недоверенный).
  final bool projectTrusted;

  /// `skills.extra_roots` в порядке конфига, как записаны (`~` раскрывает
  /// загрузчик, Q41).
  final List<String> extraRoots;

  /// Закрытие сессии или рантайма: результат после отмены выбрасывается.
  final CancelToken cancel;
}

/// Один найденный `SKILL.md`, ещё не проверенный ядром.
///
/// Почему «сырой»: мягкую проверку полей (D4) делает ядро, хост лишь читает
/// файл, разбирает frontmatter (с одной попыткой починки) и перечисляет
/// сопутствующие файлы.
final class SkillFile {
  const SkillFile({
    required this.dir,
    required this.scope,
    required this.rootIndex,
    this.frontmatter,
    this.parseErrors = const [],
    this.repaired = false,
    required this.body,
    required this.bodyLine,
    this.companions = const [],
    this.companionsTruncated = false,
  });

  /// `realpath` каталога навыка; «имя каталога» — его последний сегмент.
  final String dir;

  /// Путь файла навыка.
  String get path => '$dir/SKILL.md';

  final ExtensionScope scope;

  /// Позиция корня в списке корней загрузчика (D16): ядро сравнивает только
  /// порядок, значение в журнал не пишется.
  final int rootIndex;

  /// Разобранный frontmatter; `null` — его нет или он не разобран и после
  /// починки.
  final ConfigTree? frontmatter;

  /// Ошибки разбора с позициями файла; непусто ⇒ [frontmatter] равен `null`.
  final List<ExtensionDiagnostic> parseErrors;

  /// Разбор удался после починки; диагностику `yaml_repaired` даёт ядро.
  final bool repaired;

  /// Тело как в файле (LF); обрезку делает ядро.
  final String body;

  /// Строка файла, с которой начинается [body] (с 1).
  final int bodyLine;

  /// Пути сопутствующих файлов от [dir] через `/`, байтовый порядок, ≤ 50.
  final List<String> companions;

  /// В каталоге файлов больше, чем в [companions].
  final bool companionsTruncated;
}

/// Результат чтения навыков.
final class SkillFiles {
  const SkillFiles({
    this.skills = const [],
    this.diagnostics = const [],
    this.sessionRoots = const [],
  });

  static const empty = SkillFiles();

  /// По возрастанию `rootIndex`, внутри корня — байтовый порядок имён записей.
  final List<SkillFile> skills;

  /// Диагностики корней и файлов, не ставших [SkillFile] (`too_large`,
  /// `not_utf8`, `outside_root`, `untrusted_project`, `limit_exceeded`).
  final List<ExtensionDiagnostic> diagnostics;

  /// Корни навыков, зависящие от сессии (уровни проекта выше `cwd`,
  /// относительные `skills.extra_roots`) и абсолютные корни `extra_roots`
  /// этой папки: канонические, существующие или нет, независимо от доверия
  /// проекта (design.md change `add-agent-skills`, D9, D17; Q27).
  ///
  /// Почему поле порта: список корней знает только загрузчик, который строит
  /// его той же функцией, что и обход; рантайм добавляет их к защищаемым
  /// путям PERM-11 политики этой сессии (`AgentConfigPaths.withSession`).
  /// По умолчанию пусто — хост без файлов ничего не защищает.
  final List<String> sessionRoots;
}

/// Порт чтения навыков.
abstract interface class SkillFilesSource {
  /// Читает навыки по [query]. НЕ бросает исключений для ошибок файлов: всё
  /// уходит в [SkillFiles.diagnostics]. Непредвиденное исключение ловит
  /// рантайм и создаёт сессию без навыков.
  Future<SkillFiles> loadSkills(SkillFilesQuery query);
}
