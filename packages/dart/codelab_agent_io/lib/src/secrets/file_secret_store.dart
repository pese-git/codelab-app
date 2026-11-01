import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/yaml_reader.dart';
import 'secret_process_runner.dart';
import 'secret_value_checks.dart';
import 'secrets_backend_problem.dart';

/// Предел размера `secrets.yaml`: файл целиком читается в память, а настоящему
/// хранилищу секретов мегабайта хватает с огромным запасом (по образцу
/// CFG-21).
const _maxFileBytes = 1024 * 1024;

/// Биты «группа и остальные» режима файла (`0o077`): любой из них — отказ.
const _groupOtherBits = 0x3f;

/// Биты записи «группа и остальные» (`0o022`): каталог с ними позволяет
/// подменить `secrets.yaml` чужому пользователю.
const _groupOtherWriteBits = 0x12;

/// Все биты прав режима (`0o777`).
const _permissionBits = 0x1ff;

/// Биты прав вместе с setuid/setgid/sticky (`0o7777`): no-op `chmod` проверки
/// владельца возвращает каталогу ровно его текущий режим.
const _allModeBits = 0xfff;

/// Приватный каталог временных файлов внутри `$CODELAB_HOME` (та же файловая
/// система, что у `secrets.yaml`, поэтому `rename` атомарен).
const _tmpDirName = '.secrets-tmp';

/// Префикс имени временного файла: чистятся только такие файлы.
const _tmpPrefix = 'secrets.tmp-';

/// Возраст, после которого временный файл считается брошенным убитым
/// процессом. Свежий файл может принадлежать параллельному процессу.
const _staleTmpAge = Duration(minutes: 10);

/// Бэкенд `file`: секреты открытым текстом в `$CODELAB_HOME/secrets.yaml`
/// (design.md change `add-agent-secret-store`, D14; agent-secrets «Бэкенд
/// file»).
///
/// Почему он есть: в 1.0 хранилищ ОС нет, а `secret set` должен куда-то
/// писать. Файл открытый, поэтому выбирается только явным
/// `secrets.backend: file` (`auto` его не выбирает никогда, CFG-11) и работает
/// по правилам ssh: права шире `0600` и символическая ссылка — отказ, а не
/// «чтение с предупреждением».
///
/// Для чего: `SecretStore` поверх YAML-отображения «имя → строка».
/// Формат строгий: по строке `"<имя>": "<значение>"`, ключи по алфавиту,
/// значения в двойных кавычках с экранированием JSON; читается через
/// [readYamlTree]. Структура не «имя → строка», имя вне `SecretNames` или
/// синтаксическая ошибка дают `SecretStoreUnavailableException` без строк
/// файла (в них секреты). Файл создаёт только [write]; [read], [delete] и
/// [names] отсутствующего файла не создают.
///
/// Запись атомарна и закрыта от других пользователей: временный файл создаётся
/// не рядом с `secrets.yaml`, а в приватном каталоге `$CODELAB_HOME/.secrets-tmp`
/// (`chmod 700` через [SecretProcessRunner], проверка типа и режима). Пока у
/// файла ещё широкие права `0666 & ~umask`, открыть его по пути может только
/// владелец каталога `.secrets-tmp`, а значит, при `$CODELAB_HOME` текущего
/// пользователя дескриптор, открытый посторонним до `chmod 600`, невозможен.
/// Чужой каталог `$CODELAB_HOME` (например, `/tmp/codelab` другого uid) этого
/// не гарантирует: его владелец мог бы подменить `.secrets-tmp` своим `0777`
/// каталогом. Поэтому перед каждой записью владелец проверяется no-op
/// `chmod <текущий режим> $CODELAB_HOME` через порт: не-владельцу ОС отвечает
/// `EPERM`, и запись отклоняется. Остаточный риск (зафиксирован архитектором):
/// root обходит `EPERM`, а проверка владельца при чтении не выполняется.
/// Затем файлу выставляется `chmod 600 <tmp>` (в argv только путь; `/bin/chmod`
/// или, если его нет, `/usr/bin/chmod`), а тип и режим `.secrets-tmp` и самого
/// tmp проверяются сразу после создания, до записи значения и ещё раз перед
/// `rename`; после `rename` проверяется сам `secrets.yaml`: широкие права
/// сначала исправляются `chmod 600`, и файл удаляется только если это не
/// удалось. Имя tmp уникально (pid, счётчик, случайная
/// часть). Сбой до `rename` оставляет прежний файл; брошенные tmp старше
/// 10 минут удаляются следующей записью, свежие чужие — нет. Записи сводятся в
/// одну очередь на ПУТЬ в пределах процесса, поэтому несколько экземпляров
/// ([FileSecretStore] строится заново на каждую команду) не теряют обновления;
/// два разных процесса могут потерять одно (Risks в design.md).
///
/// Каталог `$CODELAB_HOME` с правом записи для группы или остальных
/// (`mode & 0o022`) и символическая ссылка вместо него — отказ с подсказкой
/// `chmod go-w` (как у ssh); каталог пользователя бэкенд не изменяет. Исключение
/// — каталог, который создал сам бэкенд: он получает `700` независимо от umask.
///
/// Ограничения: владельца файла `dart:io` не сообщает, проверка владельца как
/// у ssh не выполняется; между проверкой и чтением остаётся окно TOCTOU того же
/// класса, что у `BoundedEnv`. На Windows бэкенд отказывает: ACL NTFS
/// `dart:io` не проверяет (D14).
///
/// Как использовать: `FileSecretStore(path: '$home/secrets.yaml', logger:
/// logger)`; путь явный, чтобы тестовое хранилище этапа 7
/// (`CODELAB_TEST_SECRET_STORE`) переиспользовало реализацию (D14). Хост
/// получает экземпляр из `openSecretStore`.
final class FileSecretStore implements DescribedSecretStore {
  FileSecretStore({
    required this.path,
    SecretProcessRunner? runner,
    Logger? logger,
    String? platform,
    @visibleForTesting void Function()? onRenamed,
  }) : _onRenamed = onRenamed,
       _runner = runner ?? const IoSecretProcessRunner(),
       _logger = logger,
       _platform = platform ?? Platform.operatingSystem;

  /// Путь к `secrets.yaml`.
  final String path;

  final SecretProcessRunner _runner;
  final Logger? _logger;
  final String _platform;

  /// Тестовая точка сразу после `rename` (проверка прав итогового файла).
  final void Function()? _onRenamed;

  /// Очередь записей на путь, общая для всех экземпляров процесса: одна запись
  /// за раз, ошибка предыдущей следующую не отменяет.
  static final _queues = <String, Future<void>>{};

  /// Пути, для которых `secrets.file.refused` уже записан в этом процессе (D10):
  /// повторы чтения и новые экземпляры лог не засоряют.
  static final _refusedPaths = <String>{};

  static final _random = Random.secure();
  static var _tmpCounter = 0;

  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'file', writable: true);

  @override
  Future<String?> read(String name) async {
    if (!_prepare()) {
      return null;
    }
    return _load()[name];
  }

  @override
  Future<List<String>> names() async {
    if (!_prepare()) {
      return const [];
    }
    return _load().keys.toList()..sort();
  }

  @override
  Future<void> write(String name, String value) => _enqueue(() async {
    // Текст ошибок не называет ни имя, ни значение: в поле имени часто
    // вписывают сам секрет (D2).
    if (SecretNames.problem(name) != null) {
      throw _unavailable('invalid secret name');
    }
    if (secretValueProblem(value) case final problem?) {
      throw _unavailable(problem);
    }
    final values = _prepare() ? _load() : <String, String>{};
    values[name] = value;
    await _replace(_serialize(values));
  });

  @override
  Future<void> delete(String name) => _enqueue(() async {
    if (!_prepare()) {
      return;
    }
    final values = _load();
    if (values.remove(name) == null) {
      return;
    }
    await _replace(_serialize(values));
  });

  // ---- проверка доступа ---------------------------------------------------

  String get _home => File(path).parent.path;

  String get _tmpDir => '$_home/$_tmpDirName';

  /// Проверяет платформу, каталог, тип и права файла перед КАЖДЫМ обращением
  /// (D14). Возвращает `false`, если файла нет (его создаёт только [write]).
  bool _prepare() {
    final problem = secretsBackendProblem(_backendChoice, _platform);
    if (problem != null) {
      throw _unavailable(problem.message);
    }
    final homeType = FileSystemEntity.typeSync(_home, followLinks: false);
    if (homeType == FileSystemEntityType.notFound) {
      return false;
    }
    _checkHome(homeType);
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return false;
      case FileSystemEntityType.link:
        _refuse('$path is a symbolic link; refusing to read secrets', {
          'path': path,
          'reason': 'symlink',
        });
      case FileSystemEntityType.file:
        break;
      default:
        throw _notAMap();
    }
    final mode = File(path).statSync().mode & _permissionBits;
    if (mode & _groupOtherBits != 0) {
      final text = mode.toRadixString(8).padLeft(4, '0');
      _refuse('$path has permissions $text; run: chmod 600 $path', {
        'path': path,
        'mode': text,
      });
    }
    return true;
  }

  /// Платформенная проверка передаёт `file`, чтобы получить тот же текст, что
  /// у `ConfigLoader` и `openSecretStore`.
  static const _backendChoice = 'file';

  /// Каталог секретов не должен быть ссылкой и не должен быть доступен на
  /// запись группе и остальным: иначе чужой пользователь заменит `secrets.yaml`
  /// или каталог tmp. Каталог пользователя не изменяется (как у ssh).
  void _checkHome(FileSystemEntityType type) {
    if (type == FileSystemEntityType.link) {
      _refuse('$_home is a symbolic link; refusing to keep secrets there', {
        'path': path,
        'reason': 'home_symlink',
      });
    }
    if (type != FileSystemEntityType.directory) {
      throw _unavailable('$_home is not a directory');
    }
    final mode = Directory(_home).statSync().mode & _permissionBits;
    if (mode & _groupOtherWriteBits != 0) {
      final text = mode.toRadixString(8).padLeft(4, '0');
      _refuse(
        '$_home is writable by group or others (mode $text); '
        'run: chmod go-w $_home',
        {'path': path, 'reason': 'home_writable', 'mode': text},
      );
    }
  }

  /// Отказ с одним на процесс и путь предупреждением `secrets.file.refused`
  /// (D10): повторы чтения не должны засорять лог.
  Never _refuse(String reason, Map<String, Object?> fields) {
    if (_refusedPaths.add(path)) {
      _logger?.log(LogLevel.warning, 'secrets.file.refused', fields: fields);
    }
    throw _unavailable(reason);
  }

  SecretStoreUnavailableException _unavailable(String reason) =>
      SecretStoreUnavailableException(backend: 'file', reason: reason);

  SecretStoreUnavailableException _notAMap() =>
      _unavailable('$path is not a map of secret names to strings');

  // ---- чтение -------------------------------------------------------------

  Map<String, String> _load() {
    final String text;
    try {
      final file = File(path);
      if (file.statSync().size > _maxFileBytes) {
        throw _unavailable('$path is larger than 1 MiB');
      }
      text = utf8.decode(file.readAsBytesSync());
    } on FormatException {
      throw _notAMap();
    } on FileSystemException catch (error) {
      throw _unavailable(
        'cannot read $path: ${error.osError?.message ?? error.message}',
      );
    }
    // Тексты проблем разбора в ответ не идут: профиль не цитирует файл, но
    // здесь нужна одна причина без строк, поэтому проблемы сворачиваются.
    final tree = readYamlTree(
      text,
      source: path,
      kind: ConfigLayerKind.user,
    ).tree;
    if (tree == null) {
      throw _notAMap();
    }
    final values = <String, String>{};
    for (final entry in tree.values.entries) {
      final value = entry.value;
      if (SecretNames.problem(entry.key) != null || value is! String) {
        throw _notAMap();
      }
      values[entry.key] = value;
    }
    return values;
  }

  // ---- запись -------------------------------------------------------------

  Future<void> _enqueue(Future<void> Function() action) {
    final key = _queueKey();
    final result = (_queues[key] ?? Future<void>.value()).then((_) => action());
    // Следующая запись ждёт завершения этой, но не наследует её ошибку.
    final tail = result.then<void>((_) {}, onError: (_) {});
    _queues[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_queues[key], tail)) {
          _queues.remove(key);
        }
      }),
    );
    return result;
  }

  /// Ключ очереди: абсолютный путь без `.`/`..`, родитель с разрешёнными
  /// символическими ссылками (если он существует), чтобы эквивалентные пути
  /// делили одну очередь, а не писали параллельно.
  String _queueKey() {
    final file = File(path);
    final normalized = file.absolute.uri.normalizePath().toFilePath();
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    final parent = Directory(File(normalized).parent.path);
    try {
      return '${parent.resolveSymbolicLinksSync()}/$name';
    } on FileSystemException {
      return normalized;
    }
  }

  /// Путь утилиты `chmod`: абсолютный (PATH дочернему процессу не передаётся);
  /// на NixOS `/bin/chmod` нет, тогда `/usr/bin/chmod`.
  static String get _chmodExecutable =>
      File('/bin/chmod').existsSync() ? '/bin/chmod' : '/usr/bin/chmod';

  /// `chmod <mode> <target>`; в argv только режим и путь.
  Future<void> _chmod(String mode, String target) async {
    final result = await _runner.run(_chmodExecutable, [
      mode,
      target,
    ], timeout: const Duration(seconds: 10));
    if (result.exitCode != 0 || result.timedOut) {
      throw _unavailable('cannot restrict permissions of $target');
    }
  }

  int _modeOf(String target) => File(target).statSync().mode & _permissionBits;

  /// Создаёт `$CODELAB_HOME`, если его нет, с правами `700` независимо от
  /// umask (на Debian/Ubuntu umask `0002` дал бы группе запись и отказ
  /// следующей же проверки); существующий каталог только проверяется.
  Future<void> _ensureHome() async {
    final type = FileSystemEntity.typeSync(_home, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      Directory(_home).createSync(recursive: true);
      await _chmod('700', _home);
    } else {
      _checkHome(type);
      await _verifyHomeOwner();
    }
    _checkHome(FileSystemEntity.typeSync(_home, followLinks: false));
  }

  /// Владелец `$CODELAB_HOME` — текущий пользователь: no-op `chmod` с текущим
  /// режимом. `dart:io` владельца не сообщает, а `chmod` у не-владельца падает
  /// с `EPERM`. Без этого владелец чужого каталога подменил бы `.secrets-tmp`
  /// между `chmod 700` и созданием tmp. Root обходит проверку (остаточный риск).
  Future<void> _verifyHomeOwner() async {
    final mode = (Directory(_home).statSync().mode & _allModeBits)
        .toRadixString(8)
        .padLeft(4, '0');
    final bool owned;
    try {
      final result = await _runner.run(_chmodExecutable, [
        mode,
        _home,
      ], timeout: const Duration(seconds: 10));
      owned = result.exitCode == 0 && !result.timedOut;
    } on Object {
      throw _unavailable('cannot verify the owner of $_home');
    }
    if (!owned) {
      _refuse(
        '$_home is not owned by the current user; refusing to write secrets',
        {'path': path, 'reason': 'home_owner'},
      );
    }
  }

  /// Приватный каталог tmp: ссылка — отказ без `chmod` (он пошёл бы по ссылке
  /// на чужой каталог), иначе `chmod 700` и проверка типа и режима.
  Future<void> _ensureTmpDir() async {
    final dir = _tmpDir;
    switch (FileSystemEntity.typeSync(dir, followLinks: false)) {
      case FileSystemEntityType.notFound:
        Directory(dir).createSync();
      case FileSystemEntityType.directory:
        break;
      case FileSystemEntityType.link:
        _refuse('$dir is a symbolic link; refusing to write secrets', {
          'path': path,
          'reason': 'tmp_dir_symlink',
        });
      default:
        throw _unavailable('$dir is not a directory');
    }
    await _chmod('700', dir);
    if (FileSystemEntity.typeSync(dir, followLinks: false) !=
            FileSystemEntityType.directory ||
        _modeOf(dir) & _groupOtherBits != 0) {
      _refuse('$dir must be private (mode 0700)', {
        'path': path,
        'reason': 'tmp_dir_mode',
      });
    }
  }

  /// Удаляет только брошенные tmp: обычные файлы с нашим префиксом старше
  /// [_staleTmpAge]. Свежие файлы могут принадлежать параллельному процессу;
  /// ссылки не разыменовываются и не удаляются.
  void _cleanStaleTmp() {
    final cutoff = DateTime.now().subtract(_staleTmpAge);
    for (final entity in Directory(_tmpDir).listSync(followLinks: false)) {
      if (entity is! File ||
          !entity.uri.pathSegments.last.startsWith(_tmpPrefix)) {
        continue;
      }
      try {
        if (entity.statSync().modified.isBefore(cutoff)) {
          entity.deleteSync();
        }
      } on FileSystemException {
        // Файл исчез или занят: это не помеха записи.
      }
    }
  }

  Future<void> _replace(String content) async {
    final bytes = utf8.encode(content);
    // Проверка до замены: прежний файл остаётся нетронутым.
    if (bytes.length > _maxFileBytes) {
      throw _unavailable('$path would be larger than 1 MiB');
    }
    File? tmp;
    try {
      await _ensureHome();
      await _ensureTmpDir();
      _cleanStaleTmp();
      final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
      tmp = File('$_tmpDir/$_tmpPrefix$pid-${_tmpCounter++}-$suffix')
        ..createSync(exclusive: true);
      // Каталог могли подменить между проверкой и созданием файла.
      _verifyTmpDir();
      await _chmod('600', tmp.path);
      _verifyTmp(tmp);
      tmp.writeAsBytesSync(bytes, flush: true);
      // Права могли измениться за время записи: повторная проверка перед
      // rename.
      _verifyTmp(tmp);
      tmp.renameSync(path);
      _onRenamed?.call();
      await _verifyFinal();
    } on SecretStoreUnavailableException {
      rethrow;
    } on FileSystemException catch (error) {
      throw _unavailable(
        'cannot write $path: ${error.osError?.message ?? error.message}',
      );
    } on Object catch (error) {
      // Чужой порт: в причину идёт только тип, текст мог бы цитировать данные.
      throw _unavailable('cannot write $path: ${error.runtimeType}');
    } finally {
      try {
        if (tmp != null && tmp.existsSync()) {
          tmp.deleteSync();
        }
      } on FileSystemException {
        // Остаток уберёт следующая запись, когда достаточно постареет.
      }
    }
  }

  /// Итоговый `secrets.yaml` с широкими правами (например, `rename` на
  /// файловой системе без POSIX-прав): сначала `chmod 600` и повторная
  /// проверка, чтобы не стирать все секреты пользователя; удаление — только
  /// если исправить не удалось, и причина говорит об этом (без значений).
  Future<void> _verifyFinal() async {
    if (_modeOf(path) & _groupOtherBits == 0) {
      return;
    }
    try {
      await _chmod('600', path);
    } on SecretStoreUnavailableException {
      // повторная проверка ниже решает исход
    }
    if (_modeOf(path) & _groupOtherBits == 0) {
      return;
    }
    var removed = true;
    try {
      File(path).deleteSync();
    } on FileSystemException {
      removed = false;
    }
    _refuse(
      '$path has wider permissions than 0600 after write; '
      '${removed ? 'the file was removed' : 'could not remove the file'}',
      {'path': path, 'reason': 'wide_after_write', 'removed': removed},
    );
  }

  /// `.secrets-tmp` — по-прежнему настоящий каталог без прав для группы и
  /// остальных (повторная проверка против подмены, см. [_ensureTmpDir]).
  void _verifyTmpDir() {
    if (FileSystemEntity.typeSync(_tmpDir, followLinks: false) !=
            FileSystemEntityType.directory ||
        _modeOf(_tmpDir) & _groupOtherBits != 0) {
      _refuse('$_tmpDir must be private (mode 0700)', {
        'path': path,
        'reason': 'tmp_dir_mode',
      });
    }
  }

  void _verifyTmp(File tmp) {
    _verifyTmpDir();
    if (FileSystemEntity.typeSync(tmp.path, followLinks: false) !=
            FileSystemEntityType.file ||
        _modeOf(tmp.path) & _groupOtherBits != 0) {
      throw _unavailable('cannot restrict permissions of ${tmp.path}');
    }
  }

  String _serialize(Map<String, String> values) {
    final out = StringBuffer(
      '# CodeLab secrets in plaintext. Managed by: codelab secret '
      'set|delete\n',
    );
    for (final name in values.keys.toList()..sort()) {
      out.writeln('${jsonEncode(name)}: ${_quote(values[name]!)}');
    }
    return out.toString();
  }

  /// Строка в двойных кавычках YAML. `jsonEncode` экранирует `"`, `\` и
  /// управляющие символы ниже U+0020; остальные непечатные символы YAML (DEL,
  /// C1, U+2028/2029 — разрывы строк, BOM) экранируются здесь, иначе разборщик
  /// отверг бы файл или склеил строки.
  String _quote(String value) {
    final out = StringBuffer();
    for (final unit in jsonEncode(value).codeUnits) {
      final special =
          (unit >= 0x7f && unit <= 0x9f) ||
          unit == 0x2028 ||
          unit == 0x2029 ||
          unit == 0xfeff;
      if (special) {
        out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      } else {
        out.writeCharCode(unit);
      }
    }
    return out.toString();
  }
}
