/// Containment символических ссылок файлов конфигурации (change
/// `add-config-writer-and-reload`, D5 п. 5, D7; задача 8.5; ревью
/// безопасности итерации 3, L2).
///
/// Почему отдельный модуль: репозиторий не должен ссылкой
/// `.codelab/config.yaml -> ../../чужое` ни направить запись агента в чужой
/// файл (`ConfigWriter`), ни втянуть чужой файл в конфигурацию при чтении
/// (`ConfigLoader`, `ConfigWatcher`). Правило одно, поэтому и логика одна:
/// раскрытие ссылок и проверка «цель внутри `<cwd>/.codelab`» живут здесь, а
/// писатель, загрузчик и наблюдатель только вызывают её (приоритет 1,
/// безопасность; без дублирования).
///
/// Как использовать: [resolveConfigLinks] раскрывает путь, [isWithinDirectory]
/// проверяет вхождение, [projectLayerEscape] — готовый вердикт для файла
/// проектного слоя. Слой `user` (раскладки dotfiles) не ограничивается, его
/// вызывающие сюда не отправляют.
library;

import 'dart:io';

import 'config_loader.dart' show isAbsoluteConfigPath;
import 'config_paths.dart' show canonicalDirectory;

/// Путь нельзя безопасно раскрыть: цикл ссылок или `..` в ещё не созданном
/// хвосте. Писатель превращает её в `ConfigException`, загрузчик — в проблему
/// загрузки.
final class ConfigLinkException implements Exception {
  const ConfigLinkException(this.message);

  /// Причина без содержимого файлов.
  final String message;

  @override
  String toString() => 'ConfigLinkException: $message';
}

/// Разделители пути платформы (одна точка решения, §11): на POSIX `\` —
/// обычный символ имени, и резать по нему нельзя — проверка увидела бы `a/b`
/// там, где ссылка `a\b` ведёт наружу (ревью безопасности 8.5).
final _separators = Platform.isWindows ? RegExp(r'[/\\]') : RegExp('/');

bool _isAbsolute(String path) =>
    Platform.isWindows ? isAbsoluteConfigPath(path) : path.startsWith('/');

/// Канонический `<cwd>/.codelab` проектных слоёв. На Windows
/// `resolveSymbolicLinks` даёт `\`, и путь приводится к `/`; на POSIX
/// строка остаётся как есть (`\` в имени каталога — часть имени).
String projectCodelabDirectory(String cwd) {
  final root = canonicalDirectory(cwd);
  return '${Platform.isWindows ? root.replaceAll(r'\', '/') : root}/.codelab';
}

/// Файлы проектных слоёв `project` и `projectLocal`: единственное место,
/// где строятся их пути для загрузчика, наблюдателя и списка наблюдаемых
/// файлов, чтобы признак «это проектный слой» не сравнивал строки разных
/// видов (Windows: `\` против `/`).
List<String> projectLayerFiles(String cwd) {
  final dir = projectCodelabDirectory(cwd);
  return ['$dir/config.yaml', '$dir/config.local.yaml'];
}

/// Лежит ли [path] строго внутри каталога [directory] (оба — с `/`, без
/// косой черты в конце). Сравнение по сегментам: `.codelab-evil/x` не внутри
/// `.codelab`. Эквивалент `p.isWithin`, без новой зависимости пакета.
bool isWithinDirectory(String directory, String path) =>
    path.startsWith('$directory/') && path.length > directory.length + 1;

/// Текст проблемы «цель ссылки вне каталога». Называет только каталог
/// ограничения: ни содержимого файла, ни цели ссылки (она может выдать
/// структуру чужого дерева и не нужна для исправления).
String configEscapeMessage(String codelabDirectory) =>
    'the config file resolves outside $codelabDirectory/; symbolic links of '
    'a project config must stay inside .codelab';

/// Вердикт для файла проектного слоя (agent-configuration «Ссылки проектных
/// слоёв при чтении»; задача 8.5). Типизирован, чтобы «нельзя разрешить»
/// никогда не путалось с «слоя нет».
sealed class ProjectLayerAccess {
  const ProjectLayerAccess();
}

/// Файл существует, его реальный путь [realPath] внутри `<cwd>/.codelab`.
/// Читать нужно именно [realPath]: проверенное и открытое совпадают, окно
/// подмены ссылки между проверкой и чтением сужается.
final class ProjectLayerReadable extends ProjectLayerAccess {
  const ProjectLayerReadable(this.realPath);
  final String realPath;
}

/// Файла нет: слой молча отсутствует. [escapes] — висячая ссылка ведёт
/// наружу `.codelab`; читать такой путь нельзя, если цель позже появится.
final class ProjectLayerAbsent extends ProjectLayerAccess {
  const ProjectLayerAbsent({required this.escapes});
  final bool escapes;
}

/// Слой отклонён: существующая цель вне `.codelab` либо путь нельзя
/// разрешить (цикл, `..` в хвосте). [message] — готовый текст проблемы без
/// содержимого файла и без цели ссылки.
final class ProjectLayerRefused extends ProjectLayerAccess {
  const ProjectLayerRefused(this.message);
  final String message;
}

/// Проверяет файл проектного слоя [layerFile] при чтении.
///
/// Сначала `realpath` самого файла: существует — вердикт по нему. Не
/// существует (или цикл) — свой обход [resolveConfigLinks], отличающий
/// висячую ссылку от цикла и `..` в хвосте.
ProjectLayerAccess checkProjectLayer(String layerFile, String cwd) {
  final root = projectCodelabDirectory(cwd);
  try {
    final real = File(layerFile).resolveSymbolicLinksSync();
    final normalized = Platform.isWindows ? real.replaceAll(r'\', '/') : real;
    return isWithinDirectory(root, normalized)
        ? ProjectLayerReadable(real)
        : ProjectLayerRefused(configEscapeMessage(root));
  } on FileSystemException {
    // Нет файла или цикл: уточняем обходом.
  }
  try {
    return ProjectLayerAbsent(
      escapes: !isWithinDirectory(root, resolveConfigLinks(layerFile)),
    );
  } on ConfigLinkException catch (error) {
    return ProjectLayerRefused(error.message);
  }
}

/// Раскрывает символические ссылки файла и его каталогов (D5, п. 5) и
/// нормализует путь: правится цель, ссылка остаётся ссылкой.
///
/// Идёт по сегментам слева направо, держа канонический путь уже
/// пройденного: `..` берёт родителя канонического пути (а не лексический,
/// который ошибся бы после ссылки), ссылка подставляет свою цель в начало
/// очереди. Первый несуществующий сегмент завершает разбор: хвост дальше
/// только добавляется, а `..` в хвосте — `ConfigLinkException`, иначе
/// относительная ссылка `../../x/y.yaml` на несуществующий каталог обошла
/// бы проверку «внутри `.codelab`» (ревью безопасности итерации 3).
/// Ссылка на несуществующий файл ведёт к будущей цели. Больше 32
/// переходов — `ConfigLinkException` (цикл ссылок).
///
/// Как использовать: [path] абсолютный; результат — канонический путь с `/`.
/// Файлы не читаются и не создаются.
String resolveConfigLinks(String path) {
  ConfigLinkException refuse(String message) => ConfigLinkException(message);

  final windows = Platform.isWindows;
  final pending = path.split(_separators);
  // Буква диска Windows — корень, а не сегмент.
  var resolved = '';
  final unc = windows
      ? RegExp(r'^[/\\]{2}[^/\\]+[/\\][^/\\]+').firstMatch(path)
      : null;
  if (unc != null) {
    // UNC `\\server\share`: ведущие `//` не теряются.
    resolved = unc.group(0)!.replaceAll(r'\', '/');
    pending.removeRange(0, 4);
  } else if (windows &&
      pending.isNotEmpty &&
      RegExp(r'^[A-Za-z]:$').hasMatch(pending.first)) {
    resolved = pending.removeAt(0);
  }
  var hops = 0;
  while (pending.isNotEmpty) {
    final segment = pending.removeAt(0);
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      final cut = resolved.lastIndexOf('/');
      resolved = cut < 0 ? '' : resolved.substring(0, cut);
      continue;
    }
    final candidate = '$resolved/$segment';
    final type = FileSystemEntity.typeSync(candidate, followLinks: false);
    if (type == FileSystemEntityType.link) {
      if (++hops > 32) {
        throw refuse('too many symbolic links: $path');
      }
      final target = Link(candidate).targetSync();
      if (_isAbsolute(target)) {
        resolved = '';
      }
      pending.insertAll(0, target.split(_separators));
    } else if (type == FileSystemEntityType.notFound) {
      final tail = [segment, ...pending];
      if (tail.contains('..')) {
        throw refuse('invalid path: $path');
      }
      return '$resolved/${tail.where((s) => s.isNotEmpty && s != '.').join('/')}';
    } else {
      resolved = candidate;
    }
  }
  return resolved.isEmpty ? '/' : resolved;
}
