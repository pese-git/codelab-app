import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../secrets/secret_process_runner.dart';
import 'config_loader.dart';
import 'config_paths.dart';
import 'config_write_lock.dart';
import 'literal_secret_rule.dart';
import 'yaml_document_edit.dart';
import 'yaml_reader.dart';

/// Результат успешной записи [ConfigWriter.apply] (`agent-core-architecture`
/// §17.5.2).
///
/// Почему отдельный тип: вызывающему (подкоманды CLI, экраны настроек) нужны
/// не только новый отпечаток для следующей правки, но и то, что записано с
/// оговорками — незаданная `${VAR}` — и какие ключи вступят в силу только
/// после перезапуска агента.
///
/// Как использовать: [fingerprint] — основа следующего снимка;
/// [warnings] показывают строками `warning:`; [restartRequiredKeys] — пути
/// ключей правки, чей дескриптор `SettingsRegistry` помечен
/// `restartRequired`. Значений ключей в результате нет.
final class ConfigWriteResult {
  const ConfigWriteResult({
    required this.path,
    required this.fingerprint,
    this.warnings = const [],
    this.restartRequiredKeys = const [],
  });

  /// Записанный файл после разрешения символической ссылки.
  final String path;

  /// sha256 записанных байтов ([configFingerprint]).
  final String fingerprint;

  /// Что записано с оговорками: незаданная `${VAR}` в окружении писателя,
  /// предупреждения загрузки о затронутых ключах и проблемы, которые были в
  /// файле до правки (R3-1). Тексты без значений ключей.
  final List<ConfigIssue> warnings;

  /// Пути ключей правки, чей дескриптор реестра требует перезапуска агента.
  final List<String> restartRequiredKeys;

  @override
  String toString() => 'ConfigWriteResult($path)';
}

/// Точки записи, на которых тест может вклиниться (design.md change
/// `add-config-writer-and-reload`, D5, D15).
///
/// Почему шов: «сбой между tmp и переименованием» и гонку снятия устаревшего
/// lock нельзя воспроизвести детерминированно без вмешательства в нужный
/// момент; настоящий сбой процесса тест не устроит.
enum ConfigWriteSeam {
  /// Устаревший lock замечен, `rename` в уникальное имя ещё не выполнен.
  staleLockChecked,

  /// Содержимое tmp записано и сброшено на диск, `rename` ещё не выполнен.
  tmpWritten,
}

/// Атомарная запись конфигурации с сохранением формата (`agent-core-
/// architecture` §17.5.5; design.md change `add-config-writer-and-reload`,
/// D2, D5; CFG-13).
///
/// Почему отдельный класс: правку конфига ведут подкоманды CLI и экраны
/// настроек, и у всех должны быть одни и те же гарантии: комментарии и
/// порядок ключей остаются (правка через `YamlEditor`, а не пересериализация
/// дерева, §17.5.12), файл либо целиком старый, либо целиком новый (tmp +
/// `rename`), чужая ручная правка не затирается (отпечаток под lock), а
/// литеральный секрет и непроверенный итог не доходят до диска.
///
/// Для чего: единственный путь программной записи конфига. Ядро не знает
/// файлов (PKG-1), поэтому писатель живёт здесь; типы правок и исключения
/// ([ConfigEdit], [ConfigConflictException]) — в ядре, их ловят клиенты без
/// зависимости от этого пакета.
///
/// Как использовать: хост создаёт один писатель на процесс —
/// `ConfigWriter(codelabHome: …, environment: …, loader: …, logger: …,
/// processRunner: …, clock: …, random: …)`. Затем `snapshot = await
/// read(target)` и `await apply(snapshot, edits)`. Исключения `apply`:
/// [ConfigConflictException] (файл изменился после `read` или занят lock;
/// вызывающий перечитывает и повторяет), [ConfigInlineSecretException]
/// (подкласс [ConfigException], поэтому ловится раньше него) и
/// [ConfigException] (итог невалиден, правку нельзя выполнить без потери
/// структуры или нет прав/места для записи). При любой ошибке файл не
/// меняется, tmp и lock убираются. Значения правок в тексты исключений и
/// записи лога не попадают.
///
/// Ограничения: без fsync каталога (`dart:io` его не открывает; при отказе
/// питания можно потерять только последнюю правку, повреждённого файла не
/// будет — как у `secrets.yaml`); новый ключ `yaml_edit` вставляет по
/// алфавиту, если ключи отображения уже отсортированы, иначе в конец.
final class ConfigWriter {
  ConfigWriter({
    required String codelabHome,
    required Map<String, String> environment,
    required ConfigLoader loader,
    required Logger logger,
    required SecretProcessRunner processRunner,
    required Clock clock,
    required Random random,
    String? cwd,
    String? platform,
    @visibleForTesting Future<void> Function(ConfigWriteSeam point)? seam,
  }) : // Относительный `codelabHome` привязывается к каталогу процесса сразу:
       // резолвер ссылок идёт от корня и иначе прочёл бы его как абсолютный.
       _codelabHome = isAbsoluteConfigPath(codelabHome)
           ? codelabHome
           : Directory(codelabHome).absolute.path,
       _environment = Map.unmodifiable(environment),
       _loader = loader,
       _logger = logger,
       _runner = processRunner,
       _locks = ConfigWriteLocks(
         clock: clock,
         logger: logger,
         random: random,
         afterStaleCheck: seam == null
             ? null
             : () => seam(ConfigWriteSeam.staleLockChecked),
       ),
       _random = random,
       _cwd = cwd,
       _platform = platform,
       _seam = seam;

  final String _codelabHome;
  final Map<String, String> _environment;
  final ConfigLoader _loader;
  final Logger _logger;
  final SecretProcessRunner _runner;
  final ConfigWriteLocks _locks;
  final Random _random;

  /// Каталог, относительно которого проверяются проектные слои при записи в
  /// слой `user`; `null` — текущий каталог процесса.
  final String? _cwd;

  /// Подмена `Platform.operatingSystem` в тестах: на `windows` права файла
  /// не переносятся.
  final String? _platform;
  final Future<void> Function(ConfigWriteSeam point)? _seam;

  /// Предел ожидания `chmod`. Строго короче [ConfigWriteLocks.staleAfter]
  /// (10 с): пока писатель ждёт `chmod` под lock, другой не должен счесть
  /// lock устаревшим и снять его (D5, шаги 2 и 7). 5 с с запасом покрывают
  /// локальный `chmod`; медленнее — ненормальный отказ.
  static const _chmodTimeout = Duration(seconds: 5);

  /// Читает слой [target]: отпечаток байтов и разобранные значения.
  ///
  /// Файла нет — `fingerprint == null` и пустые значения. Файл с нарушением
  /// профиля YAML или синтаксиса — [ConfigException]: снимок несуществующего
  /// слоя не годится для правки.
  Future<ConfigSnapshot> read(ConfigTarget target) async {
    final path = _targetPath(target);
    final bytes = _readBytes(path);
    if (bytes == null) {
      return ConfigSnapshot(
        target: target,
        path: path,
        fingerprint: null,
        values: const {},
      );
    }
    final tree = _parse(_decode(bytes, path), path, target.layer);
    return ConfigSnapshot(
      target: target,
      path: path,
      fingerprint: configFingerprint(bytes),
      values: tree,
    );
  }

  /// Применяет [edits] к файлу цели [base] и атомарно заменяет его
  /// (алгоритм §17.5.5, шаги 1–8; D5).
  ///
  /// Файл при ошибке не меняется. Если итоговый текст совпал с исходным,
  /// файл не перезаписывается.
  Future<ConfigWriteResult> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    final target = base.target;
    // Ссылка проектного слоя наружу отклоняется до lock и до создания
    // каталогов (ревью безопасности итерации 3).
    final path = _targetPath(target);
    _checkEdits(edits, target);

    final createdDirs = <Directory>[];
    ConfigLockHandle? lock;
    File? tmp;
    var committed = false;
    try {
      await _createParents(path, createdDirs);
      lock = await _locks.acquire(path);
      // Чистка брошенных tmp — только под своим lock (D5, шаг 7): иначе она
      // шла бы параллельно с записью, которую ведёт держатель lock.
      _locks.sweepAbandonedTmp(path);

      final bytes = _readBytes(path);
      final fingerprint = bytes == null ? null : configFingerprint(bytes);
      if (fingerprint != base.fingerprint) {
        throw ConfigConflictException(path);
      }
      final original = bytes == null ? '' : _decode(bytes, path);

      final text = const ConfigDocumentEditor().apply(
        original,
        edits,
        path,
        target.layer,
      );
      final result = _validate(
        target: target,
        path: path,
        original: original,
        text: text,
        edits: edits,
      );

      if (text == original) {
        return ConfigWriteResult(
          path: path,
          fingerprint: fingerprint ?? configFingerprint(const []),
          warnings: result.warnings,
          restartRequiredKeys: result.restartRequiredKeys,
        );
      }

      final newBytes = utf8.encode(text);
      tmp = await _writeTmp(path, newBytes);
      await _seam?.call(ConfigWriteSeam.tmpWritten);
      // Перед `rename` (D5, шаг 2): lock всё ещё свой (иначе его сочли
      // устаревшим и мог писать другой) и файл не изменился с чтения под
      // lock. Это закрывает гонку трёх писателей; tmp удалит `finally`.
      if (!_locks.isHeldBy(lock)) {
        throw ConfigConflictException(path);
      }
      final current = _readBytes(path);
      if ((current == null ? null : configFingerprint(current)) !=
          fingerprint) {
        throw ConfigConflictException(path);
      }
      tmp.renameSync(path);
      tmp = null;
      committed = true;

      _logger.log(
        LogLevel.info,
        'config.write',
        fields: {'path': path, 'keys': _editKeys(edits)},
      );
      return ConfigWriteResult(
        path: path,
        fingerprint: configFingerprint(newBytes),
        warnings: result.warnings,
        restartRequiredKeys: result.restartRequiredKeys,
      );
    } on FileSystemException catch (error) {
      throw ConfigException([
        configEditIssue(path, 'cannot write $path: ${error.runtimeType}'),
      ]);
    } finally {
      if (tmp != null) {
        deleteQuietly(tmp.path);
      }
      if (lock != null) {
        _locks.release(lock);
      }
      if (!committed) {
        _removeEmptyDirs(createdDirs);
      }
    }
  }

  /// Проверяет [edits] так же, как [apply], но ничего не пишет: ни файла, ни
  /// lock, ни каталогов (design.md change `add-config-writer-and-reload`, D6,
  /// `--api-key-stdin`, шаг 1 «проверка кандидата без записи»).
  ///
  /// Почему отдельный метод: `provider add --api-key-stdin` сохраняет ключ
  /// в хранилище *до* записи конфига. Если итог заведомо невалиден (литеральный
  /// секрет, новая ошибка загрузки, запрещённый слой), ключ не должен
  /// сохраняться и запрашиваться. Метод идёт через те же `_checkEdits`,
  /// `ConfigDocumentEditor` и `_validate`, поэтому проверка не расходится с
  /// записью.
  ///
  /// Как использовать: [base] — снимок после [read]; исключения те же, что у
  /// [apply], кроме [ConfigConflictException] (файл не блокируется, а
  /// конфликт увидит последующий [apply]). Результат несёт путь, предупреждения
  /// и ключи «после перезапуска» без записи.
  Future<ConfigWriteResult> validate(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    final target = base.target;
    final path = _targetPath(target);
    _checkEdits(edits, target);
    try {
      final bytes = _readBytes(path);
      final original = bytes == null ? '' : _decode(bytes, path);
      final text = const ConfigDocumentEditor().apply(
        original,
        edits,
        path,
        target.layer,
      );
      final result = _validate(
        target: target,
        path: path,
        original: original,
        text: text,
        edits: edits,
      );
      return ConfigWriteResult(
        path: path,
        fingerprint: bytes == null
            ? configFingerprint(const [])
            : configFingerprint(bytes),
        warnings: result.warnings,
        restartRequiredKeys: result.restartRequiredKeys,
      );
    } on FileSystemException catch (error) {
      throw ConfigException([
        configEditIssue(path, 'cannot read $path: ${error.runtimeType}'),
      ]);
    }
  }

  // ---- пути ---------------------------------------------------------------

  /// Файл слоя до разрешения ссылок цели — общая с `config path` функция
  /// [configLayerFilePath], чтобы подкоманда называла файл, в который пишет
  /// писатель.
  String _layerPath(ConfigTarget target) =>
      configLayerFilePath(target, _codelabHome);

  /// Файл цели после разрешения ссылок. Для проектных слоёв раскрытая цель
  /// (и сам `.codelab`, если он ссылка) обязана лежать внутри канонического
  /// `<cwd>/.codelab`: репозиторий не должен ссылкой направить запись агента в
  /// чужой файл (приоритет 1; ревью безопасности итерации 3). Слой `user`
  /// может быть ссылкой куда угодно — раскладки dotfiles. Загрузчик ссылки при
  /// чтении следует (`File.readAsBytesSync`), поэтому писатель отказывает, а
  /// не молча пишет в другое место.
  String _targetPath(ConfigTarget target) {
    final path = _resolveTarget(_layerPath(target));
    if (target.layer != ConfigLayer.user) {
      // Корень записывается теми же разделителями, что и путь из
      // `_resolveTarget` (всегда `/`): на Windows `resolveSymbolicLinks`
      // даёт `\`, и сравнение иначе отклоняло бы любую запись. Ветка
      // Windows автотестом не проверяется (нужна настоящая ОС).
      final root =
          '${canonicalDirectory(target.cwd!).replaceAll(r'\', '/')}/.codelab/';
      if (!path.startsWith(root)) {
        throw ConfigException([
          configEditIssue(
            _layerPath(target),
            'the config file resolves outside $root; symbolic links of '
            'a project config must stay inside .codelab',
          ),
        ]);
      }
    }
    return path;
  }

  /// Раскрывает символические ссылки файла и его каталогов (D5, п. 5) и
  /// нормализует путь: правится цель, ссылка остаётся ссылкой.
  ///
  /// Идёт по сегментам слева направо, держа канонический путь уже
  /// пройденного: `..` берёт родителя канонического пути (а не лексический,
  /// который ошибся бы после ссылки), ссылка подставляет свою цель в начало
  /// очереди. Первый несуществующий сегмент завершает разбор: хвост дальше
  /// только добавляется, а `..` в хвосте — `ConfigException`, иначе
  /// относительная ссылка `../../x/y.yaml` на несуществующий каталог обошла
  /// бы проверку «внутри `.codelab`» (ревью безопасности итерации 3).
  /// Ссылка на несуществующий файл ведёт к будущей цели. Больше 32
  /// переходов — `ConfigException` (цикл ссылок).
  String _resolveTarget(String path) {
    ConfigException refuse(String message) =>
        ConfigException([configEditIssue(path, message)]);

    final pending = path.split(RegExp(r'[/\\]'));
    // Буква диска Windows — корень, а не сегмент.
    var resolved = '';
    final unc = RegExp(r'^[/\\]{2}[^/\\]+[/\\][^/\\]+').firstMatch(path);
    if (unc != null) {
      // UNC `\\server\share`: ведущие `//` не теряются.
      resolved = unc.group(0)!.replaceAll(r'\', '/');
      pending.removeRange(0, 4);
    } else if (pending.isNotEmpty &&
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
        if (isAbsoluteConfigPath(target)) {
          resolved = '';
        }
        pending.insertAll(0, target.split(RegExp(r'[/\\]')));
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

  /// Создаёт недостающие каталоги файла и запоминает созданные: при отказе
  /// записи они убираются, и «файл не создан» верно и для каталога `.codelab`.
  /// Созданный `$CODELAB_HOME` получает права `0700`, как у `FileSecretStore`
  /// (там лежат секреты); проектный `.codelab` — по umask.
  Future<void> _createParents(String path, List<Directory> created) async {
    final missing = <Directory>[];
    var dir = File(path).parent;
    while (!dir.existsSync()) {
      missing.add(dir);
      final up = dir.parent;
      if (up.path == dir.path) {
        break;
      }
      dir = up;
    }
    for (final dir in missing.reversed) {
      dir.createSync();
      created.add(dir);
      if (dir.path == _codelabHome) {
        await _chmod('700', dir.path, path);
      }
    }
  }

  void _removeEmptyDirs(List<Directory> created) {
    for (final dir in created.reversed) {
      try {
        dir.deleteSync();
      } on FileSystemException {
        // Каталог не пуст или уже убран — оставляем как есть.
      }
    }
  }

  // ---- чтение -------------------------------------------------------------

  List<int>? _readBytes(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      if (file.statSync().size > maxConfigBytes) {
        throw ConfigException([
          configEditIssue(path, 'the file is larger than 1 MiB'),
        ]);
      }
      return file.readAsBytesSync();
    } on FileSystemException catch (error) {
      throw ConfigException([
        configEditIssue(path, 'cannot read $path: ${error.runtimeType}'),
      ]);
    }
  }

  String _decode(List<int> bytes, String path) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw ConfigException([
        configEditIssue(path, 'the file is not valid UTF-8'),
      ]);
    }
  }

  Map<String, Object?> _parse(String text, String path, ConfigLayer layer) {
    final result = readYamlTree(
      text,
      source: path,
      kind: configLayerKindOf(layer),
    );
    final tree = result.tree;
    if (tree == null) {
      throw ConfigException(result.issues);
    }
    return tree.values;
  }

  // ---- шаг 1: реестр и слои ----------------------------------------------

  void _checkEdits(List<ConfigEdit> edits, ConfigTarget target) {
    final path = _layerPath(target);
    ConfigException refuse(String key, String message) =>
        ConfigException([configEditIssue(path, message, key: key)]);

    void checkLayer(SettingDescriptor d, String key) {
      if (!d.layers.contains(target.layer)) {
        final names = [
          for (final layer in ConfigLayer.values)
            if (d.layers.contains(layer))
              switch (layer) {
                ConfigLayer.user => 'user',
                ConfigLayer.project => 'project',
                ConfigLayer.projectLocal => 'local',
              },
        ];
        throw refuse(key, 'can only be written to: ${names.join(', ')}');
      }
    }

    for (final edit in edits) {
      switch (edit) {
        case SetValue(:final key):
          final segments = splitKeyPath(key);
          if (segments == null) {
            throw refuse(key, 'not a valid key path');
          }
          // Секрет значением отвергается раньше реестра: `api_key` вне
          // реестра, но ответ должен быть «секрет», а не «неизвестный ключ»
          // (D5). Поле `secret` элемента `exec.secrets` хранит имя секрета и
          // проверяется по итоговому дереву.
          final last = segments.last;
          if (!last.isElement &&
              inlineSecretKeys.contains(last.value) &&
              !_isExecSecretsField(segments)) {
            throw ConfigInlineSecretException([
              ConfigIssue(
                kind: ConfigIssueKind.inlineSecret,
                key: key,
                source: path,
                message:
                    'secrets are not stored in the config; run: codelab '
                    'secret set ${SecretNames.suggestFor(key)}, then '
                    'reference it with \${secret:'
                    '${SecretNames.suggestFor(key)}}',
              ),
            ], key);
          }
          final d = SettingsRegistry.lookup(key);
          if (d == null) {
            throw refuse(key, 'unknown key');
          }
          checkLayer(d, key);
        case UnsetValue(:final key):
          if (splitKeyPath(key) == null) {
            throw refuse(key, 'not a valid key path');
          }
        case UpsertMcpServer(:final server):
          final name = server['name'];
          if (name is! String || name.isEmpty) {
            throw refuse(
              'mcp.servers',
              'name is required and must be a non-empty string',
            );
          }
          checkLayer(SettingsRegistry.lookup('mcp.servers')!, 'mcp.servers');
        case RemoveMcpServer():
          break;
        case RemoveTable(:final key):
          if (!_isTableInstance(key)) {
            throw refuse(key, 'not a named table of the config');
          }
      }
    }
  }

  bool _isExecSecretsField(List<KeyPathSegment> s) =>
      s.length == 4 &&
      s[0].value == 'exec' &&
      s[1].value == 'secrets' &&
      s[2].isElement &&
      s[3].value == 'secret';

  /// Экземпляр именованного отображения схемы: `providers.<id>`,
  /// `providers.<id>.models.<m>`, `tools.web.search.backends.<name>` — путь,
  /// чей последний сегмент стоит на месте `*` дескриптора с более длинным
  /// путём.
  bool _isTableInstance(String key) {
    final segments = splitKeyPath(key);
    if (segments == null || segments.any((s) => s.isElement)) {
      return false;
    }
    for (final d in SettingsRegistry.all) {
      final pattern = d.key.split('.');
      if (pattern.length <= segments.length ||
          pattern[segments.length - 1] != '*') {
        continue;
      }
      var matches = true;
      for (var i = 0; i < segments.length && matches; i++) {
        matches = pattern[i] == '*' || pattern[i] == segments[i].value;
      }
      if (matches) {
        return true;
      }
    }
    return false;
  }

  // ---- шаг 7: tmp, права, запись ------------------------------------------

  /// Создаёт пустой tmp эксклюзивно, переносит на него права существующего
  /// файла и только потом пишет содержимое (D5, п. 4): конфиг с правами
  /// `0600` не должен на мгновение стать `0644`.
  Future<File> _writeTmp(String path, List<int> bytes) async {
    final tmp = File(
      '$path$configTmpInfix$pid-'
      '${_random.nextInt(1 << 32).toRadixString(16)}',
    );
    tmp.createSync(exclusive: true);
    try {
      final existing = File(path).statSync();
      final isWindows = (_platform ?? Platform.operatingSystem) == 'windows';
      if (existing.type == FileSystemEntityType.file && !isWindows) {
        await _chmod((existing.mode & 0x1FF).toRadixString(8), tmp.path, path);
      }
      tmp.writeAsBytesSync(bytes, flush: true);
    } on Object {
      deleteQuietly(tmp.path);
      rethrow;
    }
    return tmp;
  }

  /// `chmod <режим> <цель>` через порт; любой сбой — отказ записи (fail
  /// closed), `rename` не выполняется. [path] — файл конфига для текста
  /// проблемы.
  Future<void> _chmod(String mode, String target, String path) async {
    final failure = ConfigException([
      configEditIssue(path, 'cannot set permissions on $path'),
    ]);
    final SecretProcessResult result;
    try {
      result = await _runner.run(chmodExecutablePath(), [
        mode,
        target,
      ], timeout: _chmodTimeout);
    } on Exception {
      throw failure;
    }
    if (result.exitCode != 0 || result.timedOut) {
      throw failure;
    }
  }

  // ---- шаги 5–6: правка и проверка ----------------------------------------

  /// Проверяет итог: доверие проекта, литеральные секреты, полную загрузку.
  ({List<ConfigIssue> warnings, List<String> restartRequiredKeys}) _validate({
    required ConfigTarget target,
    required String path,
    required String original,
    required String text,
    required List<ConfigEdit> edits,
  }) {
    final before = original.trim().isEmpty
        ? const <String, Object?>{}
        : _parse(original, path, target.layer);
    final after = text.trim().isEmpty
        ? const <String, Object?>{}
        : _parse(text, path, target.layer);

    final secrets = literalSecretIssues(
      before: before,
      after: after,
      source: path,
    );
    if (secrets.isNotEmpty) {
      throw ConfigInlineSecretException(secrets, secrets.first.key);
    }

    final cwd = target.cwd ?? _cwd ?? Directory.current.path;
    final environment = {..._environment, 'CODELAB_HOME': _codelabHome};
    final check = _loader.validateCandidate(
      target,
      text,
      cwd: cwd,
      environment: environment,
      platform: _platform,
    );

    // Доверие проверяет `trust.dart` ядра внутри загрузки (§15.3): писатель
    // своего правила не держит. Ключ, который загрузка отбросила
    // предупреждением, — отказ записи до других проблем: подсказка про
    // `--local` полезнее, чем «обязательный ключ».
    final touched = touchedKeys(edits);
    // Правило §15.3 касается только проектных слоёв: для `user` проверки нет.
    for (final warning
        in target.layer == ConfigLayer.user
            ? const <ConfigIssue>[]
            : check.warnings) {
      if (warning.event == 'config.project.untrusted_key' &&
          _related(warning.key, touched)) {
        throw ConfigException([
          configEditIssue(
            path,
            target.layer == ConfigLayer.project
                ? 'ignored in an untrusted project; use --local or add the '
                      'project to trusted_projects in the global config'
                : 'ignored in an untrusted project; add the project to '
                      'trusted_projects in the global config',
            key: warning.key,
          ),
        ]);
      }
    }
    // R3-1 (решение пользователя 2026-11-02): блокируют только ошибки,
    // которых не было до правки. Прежние (по ключу и виду, без значений)
    // идут предупреждениями результата: иначе первая запись в пустой слой
    // упиралась бы в `agent.default_model: required`.
    final baseline = _loader.validateCandidate(
      target,
      original,
      cwd: cwd,
      environment: environment,
      platform: _platform,
    );
    // Сигнатура: вид, ключ и файл-источник, без значений. Строка и столбец
    // не входят: правка сдвигает строки прежних проблем. Проблемы без ключа
    // (синтаксис) различаются текстом, иначе разные ошибки слиплись бы.
    String signature(ConfigIssue i) =>
        '${i.kind.name}|${i.key}|${i.source}|${i.key.isEmpty ? i.message : ''}';
    final existing = {for (final i in baseline.issues) signature(i)};
    final fresh = [
      for (final i in check.issues)
        if (!existing.contains(signature(i))) i,
    ];
    if (fresh.isNotEmpty) {
      throw ConfigException(fresh);
    }
    final carried = [
      for (final i in check.issues)
        if (existing.contains(signature(i))) i,
    ];

    return (
      warnings: [
        ...carried,
        for (final warning in check.warnings)
          // Незаданная `${VAR}` и предупреждения о самих записанных ключах;
          // прочее — состояние окружения, не этой записи.
          if (warning.event == unsetVariableEvent ||
              _related(warning.key, touched))
            warning,
      ],
      restartRequiredKeys: _restartRequired(edits),
    );
  }

  bool _related(String warningKey, List<String> touched) {
    if (warningKey.isEmpty) {
      return false;
    }
    bool under(String key, String parent) =>
        key == parent ||
        key.startsWith('$parent.') ||
        key.startsWith('$parent[');
    return touched.any(
      (key) => under(warningKey, key) || under(key, warningKey),
    );
  }

  /// Ключи для лога `config.write`: пути без значений; сервер MCP — по имени.
  List<String> _editKeys(List<ConfigEdit> edits) => [
    for (final edit in edits)
      switch (edit) {
        SetValue(:final key) => key,
        UnsetValue(:final key) => key,
        RemoveTable(:final key) => key,
        UpsertMcpServer(:final server) => 'mcp.servers[${server['name']}]',
        RemoveMcpServer(:final name) => 'mcp.servers[$name]',
      },
  ];

  /// Ключи правок, чей дескриптор реестра требует перезапуска агента
  /// (`SettingDescriptor.restartRequired` — единственный источник, D4, D8).
  List<String> _restartRequired(List<ConfigEdit> edits) {
    final keys = <String>[];
    for (final key in touchedKeys(edits)) {
      if ((SettingsRegistry.lookup(key)?.restartRequired ?? false) &&
          !keys.contains(key)) {
        keys.add(key);
      }
    }
    return keys;
  }
}
