/// Общий список корней навыков для загрузчика и PERM-11 (design.md change
/// `add-agent-skills`, D3, D9, D17; задача 2.8; решение Q27).
///
/// Почему отдельный непубличный файл: загрузчик навыков читает корни, а
/// политика разрешений защищает те же корни. Если подъём к корню репозитория,
/// канонизация пути и разбор вида элемента `extra_roots` написаны в двух
/// местах, они расходятся, и защищённый список перестаёт совпадать с
/// читаемым. Здесь всё это в одном месте; наружу (барель) файл не
/// экспортируется, публичны только `hostSkillRoot` и `sessionSkillRootsFor`
/// из `config/agent_config_paths.dart`.
library;

import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        ExtensionScope,
        isAbsoluteSkillRoot,
        isHomeSkillRoot,
        isRelativeSkillRoot;

import '../env/host_path.dart';

// Признаки элемента `extra_roots` живут в ядре (один предикат для загрузчика и
// моста настроек); реэкспорт сохраняет прежний импорт этого файла.
export 'package:codelab_agent_core/codelab_agent_core.dart'
    show isHomeSkillRoot, isRelativeSkillRoot;

/// Подкаталоги навыков каждого уровня проекта в порядке приоритета (D3).
const projectSkillSubdirs = ['.codelab/skills', '.agents/skills'];

/// Предел подъёма к корню репозитория, уровни.
const maxProjectLevels = 64;

/// Тип записи по пути хоста без раскрытия ссылок; подменяется в тестах.
typedef EntryTypeOf = FileSystemEntityType Function(String hostPath);

FileSystemEntityType _typeOf(String hostPath) =>
    FileSystemEntity.typeSync(hostPath, followLinks: false);

/// Уровни проекта от корня репозитория к `cwd` (design.md change
/// `add-agent-project-files`, D6; `add-agent-skills`, D3).
///
/// Пути — в форме ядра (`/c/proj` на Windows, `/`-разделители): подъём идёт
/// по сегментам `/`, а в `dart:io` каждый путь уходит через `toHostPath`.
/// [levels] — каталоги от корня репозитория к `cwd`, если он найден, иначе
/// единственный уровень `cwd`. [found] — найден `.git` (каталог или файл:
/// worktree, submodule). [limitHit] — репозитория нет в пределах
/// [maxProjectLevels] уровней. Ссылка маркером не считается: `.git` -> куда
/// угодно мог бы подложить чужой репозиторий и сдвинуть корень поиска. Сам `/`
/// (на Windows — корень диска) тоже проверяется. [windows] по умолчанию
/// определяется платформой; [typeOf] — только для тестов.
({List<String> levels, bool found, bool limitHit}) projectLevels(
  String cwd, {
  bool? windows,
  EntryTypeOf typeOf = _typeOf,
}) {
  final isWindows = windows ?? Platform.isWindows;
  var start = cwd.startsWith('/')
      ? cwd
      : toCorePath(
          Directory(toHostPath(cwd, windows: isWindows)).absolute.path,
          windows: isWindows,
        );
  if (start.length > 1 && start.endsWith('/')) {
    start = start.substring(0, start.length - 1);
  }
  // Корень дисков Windows (`/c`): выше подниматься некуда.
  final topWindows = RegExp(r'^/[A-Za-z]$');
  final up = <String>[];
  var dir = start;
  while (up.length < maxProjectLevels) {
    up.add(dir);
    final type = typeOf(
      toHostPath('${dir == '/' ? '' : dir}/.git', windows: isWindows),
    );
    if (type == FileSystemEntityType.directory ||
        type == FileSystemEntityType.file) {
      return (levels: up.reversed.toList(), found: true, limitHit: false);
    }
    if (dir == '/' || (isWindows && topWindows.hasMatch(dir))) {
      // Дошли до корня файловой системы без репозитория.
      return (levels: [start], found: false, limitHit: false);
    }
    final slash = dir.lastIndexOf('/');
    dir = slash <= 0 ? '/' : dir.substring(0, slash);
  }
  return (levels: [start], found: false, limitHit: true);
}

/// Путь с раскрытыми ссылками по самому глубокому существующему предку;
/// остаток (ещё не созданные звенья) добавляется как есть.
String canonicalPath(String path) {
  var prefix = File(path).absolute.path;
  final rest = <String>[];
  while (true) {
    try {
      final resolved =
          FileSystemEntity.typeSync(prefix, followLinks: false) ==
              FileSystemEntityType.notFound
          ? null
          : File(prefix).resolveSymbolicLinksSync();
      if (resolved != null) {
        if (rest.isEmpty) {
          return resolved;
        }
        // Корень `/` уже оканчивается разделителем: без этого вышло бы `//x`.
        final head = resolved.endsWith(Platform.pathSeparator)
            ? resolved.substring(0, resolved.length - 1)
            : resolved;
        return [head, ...rest.reversed].join(Platform.pathSeparator);
      }
    } on FileSystemException {
      // Ссылка в никуда или нет доступа: поднимаемся к предку.
    }
    final parent = File(prefix).parent.path;
    if (parent == prefix) {
      return File(path).absolute.path;
    }
    rest.add(
      prefix.substring(parent.length).replaceAll(RegExp(r'^[\\/]+'), ''),
    );
    prefix = parent;
  }
}

/// Корень навыков из `skills.extra_roots`, известный без `cwd` (путь хоста):
/// абсолютный либо `~`/`~/…`; иначе `null` (относительный — путь сессии,
/// `~user` и `<scheme>://` не раскрываются, Q41). Без [userHome] `~`-элемент
/// тоже `null`.
///
/// Почему одна функция: загрузчик навыков и PERM-11 читают один и тот же
/// элемент конфигурации, разбор вида корня не должен разойтись.
String? hostSkillRoot(String raw, String? userHome) {
  if (raw == '~' || raw.startsWith('~/')) {
    return userHome == null ? null : '$userHome${raw.substring(1)}';
  }
  if (raw.startsWith('~') || raw.contains('://')) {
    return null;
  }
  return isAbsoluteSkillRoot(raw) ? raw : null;
}

/// Корень навыков плана: порядок в [SkillRootPlan.roots] — номер
/// `SkillFile.rootIndex`.
final class PlannedSkillRoot {
  const PlannedSkillRoot({
    required this.path,
    required this.scope,
    this.area,
    this.extraRoot,
  });

  /// Корень на диске (форма ядра), как его видит пользователь.
  final String path;

  /// Проект, пользователь или явный корень `extra_roots`.
  final ExtensionScope scope;

  /// Каталог, которым ограничено раскрытие корня (`BoundedEnv`, Q42);
  /// `null` — корень назван пользователем явно, граница не применяется.
  final String? area;

  /// Элемент `skills.extra_roots` как записан; `null` — корень не из него.
  final String? extraRoot;
}

/// Почему корень не вошёл в план и номера не получил.
enum SkippedSkillRootReason {
  /// Уровень проекта недоверенного проекта: его навыки не читаются.
  untrustedProject,

  /// Относительный элемент `extra_roots` недоверенного проекта.
  untrustedRelativeExtra,

  /// Элемент с `~`, а домашний каталог неизвестен.
  unresolvedHome,
}

/// Пропущенный корень: загрузчик по нему пишет диагностику, номера у него нет.
final class SkippedSkillRoot {
  const SkippedSkillRoot(this.path, this.reason);

  /// Путь корня; для [SkippedSkillRootReason.unresolvedHome] — элемент
  /// `extra_roots` как записан.
  final String path;
  final SkippedSkillRootReason reason;
}

/// План корней навыков: читаемые корни по приоритету и пропущенные.
final class SkillRootPlan {
  const SkillRootPlan(this.roots, this.skipped);

  final List<PlannedSkillRoot> roots;

  /// В порядке встречи: сначала уровни проекта, затем `extra_roots`.
  final List<SkippedSkillRoot> skipped;
}

/// Список корней навыков в порядке приоритета (design.md change
/// `add-agent-skills`, D3, D16; `add-app-skills-page`, D3): уровни проекта от
/// `cwd` вверх (только доверенный проект), `$CODELAB_HOME/skills`,
/// `~/.agents/skills`, затем `skills.extra_roots`.
///
/// Почему одна чистая функция: загрузчик навыков читает эти корни, а
/// `loadProjectExtensions` показывает их странице навыков с теми же номерами.
/// Два списка разошлись бы тихо: подпись источника указала бы не на тот
/// корень. Загрузчик обходит план и добавляет диагностики и `stat`, функция
/// проекции отображает его в `SkillRootInfo`.
///
/// Как использовать: [levels] — уровни проекта от корня репозитория к [cwd]
/// (`projectLevels` или `_findRoot` загрузчика); [home] и [userHome] — пустая
/// строка то же, что `null` (области нет, `/skills` не читается, приоритет 1).
SkillRootPlan skillRootPlan({
  required List<String> levels,
  required String cwd,
  required bool trusted,
  required String? home,
  required String? userHome,
  required List<String> extraRoots,
}) {
  final homeDir = home == null || home.isEmpty ? null : home;
  final userDir = userHome == null || userHome.isEmpty ? null : userHome;
  final roots = <PlannedSkillRoot>[];
  final skipped = <SkippedSkillRoot>[];
  for (final level in levels.reversed) {
    for (final sub in projectSkillSubdirs) {
      final path = '${level == '/' ? '' : level}/$sub';
      if (trusted) {
        roots.add(
          PlannedSkillRoot(
            path: path,
            scope: ExtensionScope.project,
            area: level,
          ),
        );
      } else {
        skipped.add(
          SkippedSkillRoot(path, SkippedSkillRootReason.untrustedProject),
        );
      }
    }
  }
  if (homeDir != null) {
    roots.add(
      PlannedSkillRoot(
        path: '$homeDir/skills',
        scope: ExtensionScope.user,
        area: homeDir,
      ),
    );
  }
  if (userDir != null) {
    roots.add(
      PlannedSkillRoot(
        path: '$userDir/.agents/skills',
        scope: ExtensionScope.user,
      ),
    );
  }
  for (final raw in extraRoots) {
    if (isHomeSkillRoot(raw) && userDir == null) {
      skipped.add(SkippedSkillRoot(raw, SkippedSkillRootReason.unresolvedHome));
    } else if (hostSkillRoot(raw, userDir) case final path?) {
      roots.add(
        PlannedSkillRoot(
          path: path,
          scope: ExtensionScope.extra,
          extraRoot: raw,
        ),
      );
    } else if (isRelativeSkillRoot(raw)) {
      final path = '${cwd == '/' ? '' : cwd}/$raw';
      if (trusted) {
        roots.add(
          PlannedSkillRoot(
            path: path,
            scope: ExtensionScope.extra,
            extraRoot: raw,
          ),
        );
      } else {
        skipped.add(
          SkippedSkillRoot(path, SkippedSkillRootReason.untrustedRelativeExtra),
        );
      }
    }
    // `~user/…` и `<scheme>://…` не корни (Q41): ни корня, ни диагностики.
  }
  return SkillRootPlan(roots, skipped);
}
