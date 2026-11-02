import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Суффикс lock-файла писателя конфига: `config.yaml.lock`.
const configLockSuffix = '.lock';

/// Инфикс уникального имени, в которое переименовывается устаревший lock:
/// `config.yaml.lock.stale-<nonce>` (D5, шаг 2).
const configStaleLockInfix = '.lock.stale-';

/// Инфикс временного файла записи: `config.yaml.tmp-<pid>-<rand>` (D5,
/// шаг 7).
const configTmpInfix = '.tmp-';

/// Путь lock-файла для файла конфигурации [path].
String configLockPath(String path) => '$path$configLockSuffix';

/// Служебное ли имя файла писателя конфига (lock, устаревший lock, tmp) для
/// файла с именем [configFileName].
///
/// Почему здесь: наблюдатель за конфигом (итерация 5, D7) не должен считать
/// служебные файлы писателя правкой конфига, и шаблоны имён живут рядом с
/// кодом, который их создаёт.
bool isConfigWriterFileName(String fileName, String configFileName) =>
    fileName == '$configFileName$configLockSuffix' ||
    fileName.startsWith('$configFileName$configStaleLockInfix') ||
    fileName.startsWith('$configFileName$configTmpInfix');

/// Захваченный lock: путь и nonce писателя.
final class ConfigLockHandle {
  const ConfigLockHandle(this.path, this.nonce);

  final String path;
  final String nonce;
}

/// Блокировка файла конфигурации и чистка служебных файлов писателя
/// (design.md change `add-config-writer-and-reload`, D5, шаги 2, 3 и 7).
///
/// Почему отдельный класс: `ConfigWriter` — про правку и проверку документа, а
/// жизненный цикл lock (эксклюзивное создание, снятие устаревшего без гонки,
/// проверка владения) — самостоятельная часть с собственными тестами гонок.
///
/// Как использовать: `acquire(path)` бросает [ConfigConflictException], если
/// lock занят; `isHeldBy` перед `rename` подтверждает, что lock всё ещё свой;
/// `release` снимает только свой lock. [staleAfter] — возраст, после которого
/// lock и брошенный tmp считаются устаревшими; всё, что писатель делает под
/// lock (в том числе ожидание `chmod`), обязано укладываться строго короче
/// [staleAfter], иначе другой писатель вправе снять живой lock.
final class ConfigWriteLocks {
  ConfigWriteLocks({
    required Clock clock,
    required Logger logger,
    required Random random,
    Future<void> Function()? afterStaleCheck,
  }) : _clock = clock,
       _logger = logger,
       _random = random,
       _afterStaleCheck = afterStaleCheck;

  final Clock _clock;
  final Logger _logger;
  final Random _random;

  /// Тестовый шов: устаревший lock замечен, `rename` ещё не выполнен.
  final Future<void> Function()? _afterStaleCheck;

  static const staleAfter = Duration(seconds: 10);

  /// Эксклюзивно создаёт `<path>.lock` с содержимым `<pid> <nonce>`.
  Future<ConfigLockHandle> acquire(String path) async {
    final lockPath = configLockPath(path);
    final nonce = _nonce();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        File(lockPath).createSync(exclusive: true);
      } on FileSystemException {
        if (!File(lockPath).existsSync()) {
          rethrow;
        }
        // Lock занят: свежий — конфликт, устаревший — снимаем и пробуем ещё
        // раз (один раз: второй отказ значит, что нас опередили).
        if (attempt == 1 || !await _removeStale(lockPath, path, nonce)) {
          throw ConfigConflictException(path);
        }
        continue;
      }
      try {
        File(lockPath).writeAsStringSync('$pid $nonce', flush: true);
      } on FileSystemException {
        deleteQuietly(lockPath);
        rethrow;
      }
      return ConfigLockHandle(lockPath, nonce);
    }
    throw ConfigConflictException(path);
  }

  /// Свой ли ещё lock: файл есть и в нём nonce этого писателя. Другой
  /// писатель мог счесть наш lock устаревшим и взять своё.
  bool isHeldBy(ConfigLockHandle lock) =>
      (readQuietly(lock.path) ?? '').endsWith(' ${lock.nonce}');

  /// Свой lock удаляется, только если в нём nonce этого писателя (D5).
  void release(ConfigLockHandle lock) {
    if (isHeldBy(lock)) {
      deleteQuietly(lock.path);
    }
  }

  /// Снимает устаревший lock без гонки (D5, шаг 2): `rename` в уникальное
  /// имя, повторная проверка возраста и содержимого переименованного файла.
  /// `true` — место свободно и можно создавать свой lock.
  Future<bool> _removeStale(String lockPath, String path, String nonce) async {
    final stat = File(lockPath).statSync();
    if (stat.type == FileSystemEntityType.notFound) {
      return true;
    }
    final age = _clock.now().difference(stat.modified);
    if (age <= staleAfter) {
      return false;
    }
    final seen = readQuietly(lockPath);
    await _afterStaleCheck?.call();

    final stalePath = '$path$configStaleLockInfix$nonce';
    try {
      File(lockPath).renameSync(stalePath);
    } on FileSystemException {
      // Lock исчез сам (писатель закончил): место свободно либо занято
      // новым — это выяснит повторное создание.
      return !File(lockPath).existsSync();
    }
    final movedAge = _clock.now().difference(
      File(stalePath).statSync().modified,
    );
    if (readQuietly(stalePath) != seen || movedAge <= staleAfter) {
      // Между проверкой и `rename` другой писатель успел снять устаревший
      // lock и создать свой: переименован чужой свежий файл. Возвращаем его
      // на место; конфликт получает тот, кто ошибся (D5).
      if (File(lockPath).existsSync()) {
        deleteQuietly(stalePath);
      } else {
        try {
          File(stalePath).renameSync(lockPath);
        } on FileSystemException {
          deleteQuietly(stalePath);
        }
      }
      return false;
    }
    deleteQuietly(stalePath);
    _logger.log(
      LogLevel.warning,
      'config.write.stale_lock',
      fields: {'path': path, 'age_ms': age.inMilliseconds},
    );
    return true;
  }

  /// Удаляет брошенные `<имя>.tmp-*` старше [staleAfter] (D5, шаг 7): процесс
  /// мог упасть между записью tmp и `rename`. Свежий tmp — работа другого
  /// писателя — не трогается. Вызывается только под своим lock: без него
  /// чистка могла бы удалить tmp писателя, который ещё держит lock.
  void sweepAbandonedTmp(String path) {
    final file = File(path);
    final prefix = '${file.uri.pathSegments.last}$configTmpInfix';
    try {
      for (final entity in file.parent.listSync(followLinks: false)) {
        if (entity is! File ||
            !entity.uri.pathSegments.last.startsWith(prefix)) {
          continue;
        }
        final age = _clock.now().difference(entity.statSync().modified);
        if (age > staleAfter) {
          deleteQuietly(entity.path);
        }
      }
    } on FileSystemException {
      // Каталог недоступен для чтения — дальше это увидит запись.
    }
  }

  String _nonce() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Читает текстовый файл, не бросая: нет файла или не UTF-8 — `null`.
String? readQuietly(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// Удаляет файл, если он есть; ошибки удаления не пробрасываются.
void deleteQuietly(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  } on FileSystemException {
    // Нечего больше сделать: файл уже убран или недоступен.
  }
}
