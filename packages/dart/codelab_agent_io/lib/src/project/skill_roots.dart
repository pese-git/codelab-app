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

import '../env/host_path.dart';

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

bool _isAbsolute(String raw) =>
    raw.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(raw);

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
  return _isAbsolute(raw) ? raw : null;
}

/// Элемент `extra_roots` — `~`/`~/…` (раскрывается в домашний каталог).
bool isHomeSkillRoot(String raw) => raw == '~' || raw.startsWith('~/');

/// Элемент `extra_roots` — относительный путь от `cwd` сессии: не абсолютный,
/// не `~…` и не `<scheme>://…`. Остальное — путь хоста либо не корень.
bool isRelativeSkillRoot(String raw) =>
    !_isAbsolute(raw) && !raw.startsWith('~') && !raw.contains('://');
