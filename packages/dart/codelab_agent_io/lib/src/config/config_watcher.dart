/// Наблюдатель за файлами конфига (design.md change
/// `add-config-writer-and-reload`, D7; agent-configuration «Наблюдение за
/// файлами конфига»).
///
/// Почему отдельный класс: «что-то изменилось» в файловой системе приходит
/// пачкой событий (редактор пишет tmp, переименовывает, ставит lock), а ядру
/// нужен один сигнал на правку. Сворачивание событий (debounce на `Clock`),
/// сравнение содержимого (sha256) и деградация до опроса — самостоятельная
/// логика со своими тестами на `FakeClock`, поэтому она вынесена из
/// `FileConfigSource`.
///
/// Для чего: [changes] — «прочитанные файлы изменились» после debounce 300 мс
/// и только если sha256 хотя бы одного файла отличается от прежнего
/// состояния. События каталога (`Directory.watch` на родителе каждого файла)
/// ловят и замену через `rename`, и файлы, которых при старте ещё нет. Если
/// каталога нет или поток событий упал, файлы этого каталога переходят на
/// опрос раз в `config.poll_interval` по `(exists, mtime, size)`.
///
/// Как использовать: `FileConfigSource` строит наблюдатель по списку
/// `watchedConfigFiles(...)` (наблюдаемое ⊆ защищаемому, R5-1), вызывает
/// [start], а после `runtime.dispose()` — [close]. После [close] сигналов и
/// таймеров нет. Тесты подают события через [DirectoryEventsFactory] и часы
/// `FakeClock`; сигналы служебных файлов писателя (`config.yaml.lock`,
/// `*.lock.stale-*`, `*.tmp-*`) отбрасываются до debounce — запись
/// `ConfigWriter` даёт один сигнал по итоговому `rename` (шаблоны имён — из
/// `config_write_lock.dart`, а не копии здесь).
library;

import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'config_loader.dart' show maxConfigBytes;
import 'config_write_lock.dart';

/// Debounce событий (D7): новые события перезапускают таймер.
const configWatchDebounce = Duration(milliseconds: 300);

/// Изменение в наблюдаемом каталоге: узкая замена `FileSystemEvent`.
///
/// Почему своя структура: `FileSystemEvent` запечатан и не строится вне SDK,
/// а unit-тесты (D7, «Тестируемость») должны подавать события вручную. Путь
/// и [destination] (цель `rename` там, где платформа её сообщает) — всё, что
/// нужно наблюдателю.
final class DirectoryChange {
  const DirectoryChange({required this.path, this.destination});

  /// Путь изменённой записи (при `rename` — источник).
  final String path;

  /// Цель `rename`, если платформа её называет (inotify).
  final String? destination;
}

/// Шов: поток событий каталога (D7). Исключение при вызове и ошибка потока
/// переводят файлы каталога на опрос.
typedef DirectoryEventsFactory =
    Stream<DirectoryChange> Function(Directory directory);

/// Состояние файла для опроса: существует ли, время изменения и размер.
typedef ConfigFileStamp = ({bool exists, DateTime? modified, int size});

/// Шов: чтение состояния файла при опросе. Исключение — `config.watch.failed`.
typedef ConfigFileProbe = ConfigFileStamp Function(String path);

/// Настоящие события каталога: `Directory.watch` без рекурсии.
///
/// Почему проверка существования: на macOS `watch` по несуществующему
/// каталогу не бросает и не сообщает об ошибке — поток молча ничего не
/// присылает, и правка файла была бы пропущена. Поэтому отсутствие каталога
/// превращается в исключение здесь, и наблюдатель переводит файлы на опрос
/// (`config.watch.fallback`, D7).
Stream<DirectoryChange> defaultDirectoryEvents(Directory directory) {
  if (!directory.existsSync()) {
    throw PathNotFoundException(
      directory.path,
      const OSError('no such directory', 2),
    );
  }
  return directory.watch().map(
    (event) => DirectoryChange(
      path: event.path,
      destination: event is FileSystemMoveEvent ? event.destination : null,
    ),
  );
}

/// Настоящее состояние файла через `stat`; нет файла — `exists: false`.
ConfigFileStamp defaultConfigFileProbe(String path) {
  final stat = File(path).statSync();
  if (stat.type == FileSystemEntityType.notFound) {
    return (exists: false, modified: null, size: 0);
  }
  return (exists: true, modified: stat.modified, size: stat.size);
}

/// Сворачивает поток событий файловой системы в один сигнал «конфиг изменился».
///
/// Почему: редактор или писатель даёт пачку событий (tmp, rename, lock), а ядру
/// нужен один сигнал на правку; платформенный `watch` ещё и ненадёжен (нет
/// каталога, закрытый поток), поэтому нужна деградация до опроса (D7).
///
/// Для чего: debounce 300 мс на `Clock`, сравнение sha256 (отпечаток по
/// размеру и mtime для файлов больше лимита загрузчика), события каталога
/// родителей файлов и целей ссылок, переход на опрос `config.poll_interval`
/// при отказе. Отладочное событие `config.watch.debounce` с `path` отмечает
/// замеченную правку.
///
/// Как использовать: `FileConfigSource` создаёт наблюдатель по списку
/// `watchedConfigFiles(...)`, вызывает [start], слушает [changes], а после
/// `runtime.dispose()` вызывает [close]. Швы тестов — [DirectoryEventsFactory]
/// и [ConfigFileProbe]; часы — `FakeClock`.
final class ConfigWatcher {
  ConfigWatcher({
    required List<String> files,
    required Clock clock,
    required Logger logger,
    Duration pollInterval = const Duration(seconds: 2),
    DirectoryEventsFactory? directoryEvents,
    ConfigFileProbe? probe,
  }) : _files = List.unmodifiable(files),
       _clock = clock,
       _logger = logger,
       _pollInterval = pollInterval,
       _directoryEvents = directoryEvents ?? defaultDirectoryEvents,
       _probe = probe ?? defaultConfigFileProbe;

  final List<String> _files;
  final Clock _clock;
  final Logger _logger;
  final Duration _pollInterval;
  final DirectoryEventsFactory _directoryEvents;
  final ConfigFileProbe _probe;

  final _controller = StreamController<void>.broadcast();

  /// Наблюдаемые каталоги: лексические родители файлов и родители
  /// канонических целей ссылок (`config.yaml -> ~/dotfiles/…`, PERM-11).
  final _directories = <String, _DirectoryWatch>{};

  /// Файлы, переведённые на опрос, и их последний замер.
  final _polled = <String, ConfigFileStamp?>{};

  /// sha256 файлов при последней загрузке/сигнале; `null` — файла нет.
  Map<String, String?> _baseline = {};
  ClockTimer? _debounce;
  ClockTimer? _pollTimer;
  var _started = false;
  var _closed = false;

  /// Сигнал «прочитанные файлы изменились» (после debounce и сравнения
  /// sha256). Широковещательный: слушатель получает только будущие сигналы.
  Stream<void> get changes => _controller.stream;

  /// Запоминает текущее содержимое файлов как точку сравнения и подписывается
  /// на каталоги. Повторный вызов и вызов после [close] ничего не делают.
  void start() {
    if (_started || _closed) {
      return;
    }
    _started = true;
    _baseline = _digests();
    _syncDirectories();
  }

  /// Принимает текущее содержимое файлов за «последнюю загрузку».
  ///
  /// Для чего: `FileConfigSource.load()` вызывает перед чтением слоёв, чтобы
  /// собственное чтение не порождало повторный сигнал, а правка во время
  /// чтения — порождала (её sha256 отличается от снимка до чтения).
  void rebase() {
    if (!_closed) {
      _baseline = _digests();
      _syncDirectories();
    }
  }

  /// Останавливает наблюдение: подписки, таймеры и поток [changes]. После
  /// вызова сигналов нет; повторный вызов безопасен.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _debounce?.cancel();
    _pollTimer?.cancel();
    _polled.clear();
    final watches = [..._directories.values];
    _directories.clear();
    for (final watch in watches) {
      await watch.subscription?.cancel();
    }
    await _controller.close();
  }

  /// Приводит подписки к нужному составу каталогов.
  ///
  /// Почему и лексический путь, и каноническая цель: `config.yaml` часто
  /// ссылка в dotfiles, и правка цели — событие другого каталога. Ссылку
  /// могли перенаправить, поэтому цели пересчитываются в [rebase] и перед
  /// сравнением в [_fire]. Содержимое всегда читается по лексическому пути —
  /// так же, как читает загрузчик.
  void _syncDirectories() {
    final wanted = <String, ({Set<String> names, Set<String> owners})>{};
    void want(String path, String owner) {
      final entry = wanted.putIfAbsent(
        _dirname(path),
        () => (names: <String>{}, owners: <String>{}),
      );
      entry.names.add(_basename(path));
      entry.owners.add(owner);
    }

    for (final file in _files) {
      want(file, file);
      final target = _canonicalTarget(file);
      if (target != null && target != file) {
        want(target, file);
      }
    }
    for (final dir in _directories.keys.toList()) {
      if (!wanted.containsKey(dir)) {
        unawaited(_directories.remove(dir)!.subscription?.cancel());
      }
    }
    for (final entry in wanted.entries) {
      final existing = _directories[entry.key];
      if (existing != null) {
        existing.names
          ..clear()
          ..addAll(entry.value.names);
        existing.owners
          ..clear()
          ..addAll(entry.value.owners);
        continue;
      }
      final watch = _DirectoryWatch(entry.value.names, entry.value.owners);
      _directories[entry.key] = watch;
      _watchDirectory(entry.key, watch);
    }
  }

  /// Цель ссылки с раскрытыми цепочками; `null` — файла нет или ссылка висит.
  String? _canonicalTarget(String file) {
    try {
      return File(file).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
  }

  void _watchDirectory(String directory, _DirectoryWatch watch) {
    final Stream<DirectoryChange> stream;
    try {
      stream = _directoryEvents(Directory(directory));
    } on Object catch (error) {
      _fallBack(watch.owners.toList(), error);
      return;
    }
    watch.subscription = stream.listen(
      (change) => _onChange(change, watch.names),
      onError: (Object error) {
        _fallBack(watch.owners.toList(), error);
      },
      // Каталог удалён (inotify): поток закрывается без ошибки, и без этой
      // ветки файлы остались бы без наблюдения (D7). Собственная отмена
      // подписки `onDone` не вызывает, поэтому ложных переходов нет.
      onDone: () => _fallBack(watch.owners.toList(), const _StreamClosed()),
      cancelOnError: true,
    );
  }

  /// Событие каталога: перезагрузку запускает только правка наблюдаемого
  /// файла. Служебные файлы писателя отбрасываются здесь, до debounce (D7).
  void _onChange(DirectoryChange change, Set<String> watchedNames) {
    if (_closed) {
      return;
    }
    // При `rename` источник (tmp) служебный, а цель — наблюдаемый файл: это и
    // есть итоговый сигнал записи писателя.
    for (final path in [change.path, ?change.destination]) {
      final name = _basename(path);
      if (!_isWriterFile(name, watchedNames) && watchedNames.contains(name)) {
        _schedule(path);
        return;
      }
    }
  }

  /// Служебное имя писателя рядом с любым наблюдаемым файлом (шаблоны — из
  /// `config_write_lock.dart`, D5/D7).
  bool _isWriterFile(String name, Set<String> watchedNames) =>
      watchedNames.any((watched) => isConfigWriterFileName(name, watched));

  void _schedule(String path) {
    // Событие debug: наблюдаемая точка «правка замечена» для диагностики и для
    // интеграционных тестов, которым нужно дождаться запуска debounce без
    // опроса таймеров часов (§16).
    _logger.log(
      LogLevel.debug,
      'config.watch.debounce',
      fields: {'path': path},
    );
    _debounce?.cancel();
    _debounce = _clock.timer(configWatchDebounce, _fire);
  }

  void _fire() {
    if (_closed) {
      return;
    }
    _syncDirectories();
    final digests = _digests();
    if (_sameDigests(digests, _baseline)) {
      return;
    }
    _baseline = digests;
    _controller.add(null);
  }

  /// Переводит [files] на опрос после ошибки (`config.watch.fallback`, info).
  void _fallBack(List<String> files, Object error) {
    if (_closed) {
      return;
    }
    for (final file in files) {
      _logger.log(
        LogLevel.info,
        'config.watch.fallback',
        fields: {'path': file, 'reason': error.runtimeType.toString()},
      );
      _polled[file] = _safeProbe(file);
    }
    _armPoll();
  }

  ConfigFileStamp? _safeProbe(String file) {
    try {
      return _probe(file);
    } on Object catch (error) {
      _logger.log(
        LogLevel.warning,
        'config.watch.failed',
        fields: {'path': file, 'error_class': error.runtimeType.toString()},
      );
      return null;
    }
  }

  void _armPoll() {
    if (_closed || (_pollTimer?.isActive ?? false) || _polled.isEmpty) {
      return;
    }
    _pollTimer = _clock.timer(_pollInterval, _poll);
  }

  void _poll() {
    if (_closed) {
      return;
    }
    var changed = false;
    String? polledPath;
    for (final file in _polled.keys.toList()) {
      final before = _polled[file];
      final after = _safeProbe(file);
      // Сбой замера не считается правкой; повтор — на следующем тике.
      if (after == null) {
        continue;
      }
      _polled[file] = after;
      if (before == null ||
          before.exists != after.exists ||
          before.modified != after.modified ||
          before.size != after.size) {
        changed = true;
        polledPath ??= file;
      }
    }
    // Исключение опроса не останавливает его (D7): таймер взводится всегда.
    if (changed) {
      _schedule(polledPath!);
    }
    _armPoll();
  }

  Map<String, String?> _digests() => {
    for (final file in _files) file: _digest(file),
  };

  String? _digest(String file) {
    try {
      final entity = File(file);
      final stat = entity.statSync();
      if (stat.type == FileSystemEntityType.notFound) {
        return null;
      }
      // Файл больше лимита загрузчика не читается и здесь: отпечаток по
      // размеру и mtime (D7). Читать произвольный объём на каждый сигнал
      // нельзя — загрузчик всё равно откажется от такого файла.
      if (stat.size > maxConfigBytes) {
        return 'oversized:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
      }
      return configFingerprint(entity.readAsBytesSync());
    } on Object catch (error) {
      // Нечитаемый файл — отдельное состояние, отличное и от «нет файла», и
      // от любого содержимого: загрузчик сам назовёт причину.
      _logger.log(
        LogLevel.warning,
        'config.watch.failed',
        fields: {'path': file, 'error_class': error.runtimeType.toString()},
      );
      return 'unreadable';
    }
  }

  static bool _sameDigests(Map<String, String?> a, Map<String, String?> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// Причина перехода на опрос при закрытии потока без ошибки; в лог уходит
/// только имя типа (`reason`).
final class _StreamClosed {
  const _StreamClosed();
}

/// Имя файла в пути: последний сегмент после `/` или `\`.
String _basename(String path) => path.substring(_lastSeparator(path) + 1);

/// Родительский каталог пути; для имени без каталога — `.`.
String _dirname(String path) {
  final index = _lastSeparator(path);
  if (index < 0) {
    return '.';
  }
  return index == 0 ? path.substring(0, 1) : path.substring(0, index);
}

int _lastSeparator(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = Platform.isWindows ? path.lastIndexOf(r'\') : -1;
  return slash > backslash ? slash : backslash;
}

/// Подписка на один каталог: имена, которые в нём наблюдаются, и файлы
/// конфига (лексические пути), которые уйдут на опрос при отказе `watch`.
final class _DirectoryWatch {
  _DirectoryWatch(Set<String> names, Set<String> owners)
    : names = {...names},
      owners = {...owners};

  final Set<String> names;
  final Set<String> owners;
  StreamSubscription<DirectoryChange>? subscription;
}
