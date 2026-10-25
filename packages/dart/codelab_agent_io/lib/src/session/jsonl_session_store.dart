import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import 'write_queue.dart';

/// Когда хранилище вызывает `fsync` (`agent-core-architecture` §8.5,
/// настройка `sessions.fsync` §15).
///
/// Почему не после каждой записи: `writeString` отдаёт байты ОС без буфера
/// процесса, поэтому падение процесса ничего не теряет ни в одном режиме, а
/// `fsync` защищает только от отключения питания. [checkpoints] делает
/// надёжными точки восстановления SES-9 и не платит за каждую строку
/// потокового ответа модели.
enum FsyncPolicy {
  /// Только записи с `durable` (результат инструмента, `compaction`) и
  /// `flush` в конце хода. По умолчанию.
  checkpoints,

  /// После каждой записи и на `flush`.
  always,

  /// Никогда: сброс решает ОС.
  never,
}

/// Сброс файла на носитель; по умолчанию — `RandomAccessFile.flush`.
typedef FileSync = Future<void> Function(RandomAccessFile file);

/// Журналы сессий в JSONL-файлах на `dart:io` (`agent-core-architecture`
/// §8.5, §8.6, §8.9, §8.10; design.md change
/// `add-agent-core-sessions-and-compaction`, D7).
///
/// Почему хранилище отвечает только за байты: разбор, дерево, ремонт в
/// памяти и сводки живут в ядре (`parseSessionLines`, `summarize`,
/// `pageOf`), поэтому файл ведёт себя так же, как `MemorySessionStore`, и
/// проходит тот же контрактный набор. Здесь — раскладка каталогов, очередь
/// записи, `fsync`, карантин и переписывание файла.
///
/// Для чего: порт `SessionStore` настольных хостов
/// (`sessionPersistence: jsonl-file`).
///
/// Как использовать: хост создаёт одно хранилище на процесс над каталогом
/// `$CODELAB_HOME/sessions` и передаёт его в `AgentCoreServices.sessions`;
/// переменные окружения хранилище не читает. Файл сессии —
/// `<root>/<cwdSlug(cwd)>/<created>_<sessionId>.jsonl`; поиск по id — по
/// суффиксу имени. Ошибка файловой операции уходит вызывающему, а
/// дескриптор закрывается: следующая операция открывает файл заново.
final class JsonlSessionStore implements SessionStore {
  JsonlSessionStore({
    required String root,
    this.fsync = FsyncPolicy.checkpoints,
    required Clock clock,
    Logger? logger,
    @visibleForTesting FileSync? sync,
  }) : root = root.replaceFirst(RegExp(r'[/\\]+$'), ''),
       _clock = clock,
       _logger = logger,
       _sync = sync ?? ((file) => file.flush());

  /// Каталог `sessions/`.
  final String root;
  final FsyncPolicy fsync;
  final Clock _clock;
  final Logger? _logger;
  final FileSync _sync;

  /// Пути созданных и найденных сессий: повторный поиск по каталогам не
  /// нужен.
  final _paths = <SessionId, String>{};

  /// Открытые дескрипторы; живут до [close] или до ошибки операции.
  final _handles = <String, RandomAccessFile>{};

  String get _indexPath => '$root/index.json';

  @override
  Future<void> create(SessionHeader header) async {
    if (await _find(header.id) != null) {
      throw StateError('session ${header.id.value} already exists');
    }
    final stamp = formatJournalTime(
      header.created,
    ).replaceAll(':', '-').replaceAll('.', '-');
    final path =
        '$root/${cwdSlug(header.cwd)}/${stamp}_${header.id.value}.jsonl';
    final line = _encode(header.toJson());
    await writeQueue.run(path, () async {
      final file = File(path);
      await file.parent.create(recursive: true);
      if (await file.exists()) {
        throw StateError('session ${header.id.value} already exists');
      }
      await _write(path, line, durable: true);
    });
    _paths[header.id] = path;
  }

  @override
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  }) async {
    // Строка кодируется один раз и до очереди (§8.5, шаг 1).
    final line = _encode(record.toJson());
    final path = await _pathOf(id);
    await writeQueue.run(path, () => _write(path, line, durable: durable));
  }

  @override
  Future<void> flush(SessionId id) async {
    final path = await _pathOf(id);
    await writeQueue.run(path, () async {
      final handle = _handles[path];
      if (handle == null || fsync == FsyncPolicy.never) {
        return;
      }
      await _guard(path, () => _sync(handle));
    });
  }

  @override
  Future<SessionSnapshot> open(SessionId id) async {
    final path = await _pathOf(id);
    final snapshot = await writeQueue.run(path, () async {
      // Переписывание заменяет файл через rename: дескриптор старого файла
      // писал бы в удалённый inode.
      await _drop(path);
      final file = File(path);
      if (!await file.exists()) {
        throw SessionNotFound(id);
      }
      final parsed = await _parse(file, id);
      await _repair(file, id, parsed);
      return parsed.snapshot;
    });
    _paths[id] = path;
    return snapshot;
  }

  @override
  Future<SessionPage> list({
    String? cwd,
    String? cursor,
    int pageSize = 50,
  }) async {
    final index = await _readIndex();
    final fresh = <String, _IndexEntry>{};
    final summaries = <SessionSummary>[];
    for (final file in await _journals(cwd)) {
      final key = _keyOf(file.path);
      final entry = await writeQueue.run(
        file.path,
        () => _entryOf(file, index[key]),
      );
      if (entry == null) {
        continue;
      }
      fresh[key] = entry;
      if (cwd == null || entry.summary.cwd == cwd) {
        summaries.add(entry.summary);
      }
    }
    // Записи других каталогов при фильтре по cwd остаются в кеше.
    final merged = {
      if (cwd != null)
        for (final MapEntry(:key, :value) in index.entries)
          if (!key.startsWith('${cwdSlug(cwd)}/')) key: value,
      ...fresh,
    };
    if (!_sameIndex(index, merged)) {
      await _writeIndex(merged);
    }
    return pageOf(summaries, cursor: cursor, pageSize: pageSize);
  }

  @override
  Future<void> close(SessionId id) async {
    final path = _paths[id] ?? await _find(id);
    if (path == null) {
      return;
    }
    await writeQueue.run(path, () => _drop(path));
  }

  /// Одна строка JSON без переводов строк внутри (§8.5, шаг 1).
  String _encode(Map<String, Object?> json) {
    final line = jsonEncode(json);
    if (line.contains('\n') || line.contains('\r')) {
      throw StateError('a journal line must not contain line breaks');
    }
    return line;
  }

  /// Одна строка — один вызов `write` (§8.5, шаг 3).
  Future<void> _write(String path, String line, {required bool durable}) =>
      _guard(path, () async {
        final handle = _handles[path] ??= await File(
          path,
        ).open(mode: FileMode.append);
        await handle.writeString('$line\n');
        final sync = switch (fsync) {
          FsyncPolicy.always => true,
          FsyncPolicy.checkpoints => durable,
          FsyncPolicy.never => false,
        };
        if (sync) {
          await _sync(handle);
        }
      });

  /// Ошибка операции закрывает дескриптор (§8.5, шаг 4).
  Future<void> _guard(String path, Future<void> Function() operation) async {
    try {
      await operation();
    } on Object {
      await _drop(path);
      rethrow;
    }
  }

  Future<void> _drop(String path) async {
    final handle = _handles.remove(path);
    try {
      await handle?.close();
    } on FileSystemException {
      // Дескриптор уже сломан; закрыть его нечем, ошибку операции получил
      // её вызывающий.
    }
  }

  Future<ParsedJournal> _parse(File file, SessionId id) async {
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    final cached = (await _readIndex())[_keyOf(file.path)];
    // Синтез отсутствующего заголовка (§8.6, шаг 3b): cwd — из кеша
    // сводок по имени файла, created — mtime.
    return parseSessionLines(
      text,
      id: id,
      cwd: cached?.summary.cwd ?? '',
      created: (await file.lastModified()).toUtc(),
      logger: _logger,
    );
  }

  /// Шаги 5a–5b §8.6: карантин и единственное переписывание файла (SES-1).
  Future<void> _repair(File file, SessionId id, ParsedJournal parsed) async {
    if (parsed.quarantine.isEmpty) {
      if (parsed.missingFinalNewline) {
        // Иначе следующая запись склеилась бы с последней строкой.
        await file.writeAsString('\n', mode: FileMode.append, flush: true);
      }
      return;
    }
    final at = formatJournalTime(_clock.now());
    await File('${file.path}.corrupt').writeAsString(
      [
        for (final q in parsed.quarantine)
          '${jsonEncode({'line': q.line, 'text': q.text, 'reason': q.reason, 'at': at})}\n',
      ].join(),
      mode: FileMode.append,
      flush: true,
    );
    if (parsed.onlyTailBroken) {
      final bytes = await file.readAsBytes();
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.truncate(bytes.lastIndexOf(0x0a) + 1);
        await handle.flush();
      } finally {
        await handle.close();
      }
    } else {
      final tmp = File('${file.path}.tmp');
      final kept = parsed.keptLines;
      await tmp.writeAsString(
        kept.isEmpty ? '' : '${kept.join('\n')}\n',
        flush: true,
      );
      await tmp.rename(file.path);
    }
    _logger?.log(
      LogLevel.warning,
      'session.quarantined',
      fields: {
        'session_id': id.value,
        'lines': parsed.quarantine.length,
        'truncated': parsed.onlyTailBroken,
      },
    );
  }

  Future<String> _pathOf(SessionId id) async =>
      _paths[id] ?? await _find(id) ?? (throw SessionNotFound(id));

  /// Поиск файла по суффиксу `_<id>.jsonl` в каталогах слагов (D7).
  Future<String?> _find(SessionId id) async {
    final known = _paths[id];
    if (known != null) {
      return known;
    }
    final suffix = '_${id.value}.jsonl';
    for (final file in await _journals(null)) {
      if (file.path.endsWith(suffix)) {
        return _paths[id] = file.path;
      }
    }
    return null;
  }

  /// Файлы `sessions/*/*.jsonl` без рекурсии (§8.10, шаг 1); с [cwd] —
  /// только каталог его слага.
  Future<List<File>> _journals(String? cwd) async {
    final dirs = cwd == null
        ? await _list(
            Directory(root),
          ).where((e) => e is Directory).cast<Directory>().toList()
        : [Directory('$root/${cwdSlug(cwd)}')];
    return [
      for (final dir in dirs)
        ...await _list(dir)
            .where((e) => e is File && e.path.endsWith('.jsonl'))
            .cast<File>()
            .toList(),
    ];
  }

  Stream<FileSystemEntity> _list(Directory dir) async* {
    if (await dir.exists()) {
      yield* dir.list(followLinks: false);
    }
  }

  /// Сводка из кеша по `(size, mtime)` или из разбора без ремонта на
  /// диске (§8.10, шаг 2); `null` — журнал нельзя открыть.
  Future<_IndexEntry?> _entryOf(File file, _IndexEntry? cached) async {
    final stat = await file.stat();
    final mtime = stat.modified.millisecondsSinceEpoch;
    if (cached != null && cached.size == stat.size && cached.mtime == mtime) {
      return cached;
    }
    final id = _idOf(file.path);
    if (id == null) {
      return null;
    }
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    try {
      final parsed = parseSessionLines(
        text,
        id: id,
        cwd: cached?.summary.cwd ?? '',
        created: stat.modified.toUtc(),
        logger: _logger,
      );
      return _IndexEntry(
        size: stat.size,
        mtime: mtime,
        summary: summarize(parsed.snapshot, logger: _logger),
      );
    } on SessionOpenException {
      return null;
    }
  }

  SessionId? _idOf(String path) {
    final match = RegExp(r'_([0-9A-Z]{26})\.jsonl$').firstMatch(path);
    return match == null ? null : SessionId(match.group(1)!);
  }

  /// Ключ кеша — путь относительно [root] через `/`.
  String _keyOf(String path) =>
      path.substring(root.length + 1).replaceAll(r'\', '/');

  /// Кеш — производный файл: нечитаемый игнорируется (D7).
  Future<Map<String, _IndexEntry>> _readIndex() async {
    try {
      final json = jsonDecode(await File(_indexPath).readAsString());
      final sessions = (json as Map<String, Object?>)['sessions']! as Map;
      return {
        for (final MapEntry(:key, :value) in sessions.entries)
          key as String: _IndexEntry.fromJson(value as Map<String, Object?>),
      };
    } on PathNotFoundException {
      return {};
    } on Object catch (error) {
      _logger?.log(
        LogLevel.debug,
        'session.index.ignored',
        fields: {'path': _indexPath},
        error: error,
      );
      return {};
    }
  }

  Future<void> _writeIndex(Map<String, _IndexEntry> entries) =>
      writeQueue.run(_indexPath, () async {
        await Directory(root).create(recursive: true);
        final tmp = File('$_indexPath.tmp');
        await tmp.writeAsString(
          jsonEncode({
            'v': 1,
            'sessions': {
              for (final MapEntry(:key, :value) in entries.entries)
                key: value.toJson(),
            },
          }),
        );
        await tmp.rename(_indexPath);
      });

  bool _sameIndex(Map<String, _IndexEntry> a, Map<String, _IndexEntry> b) =>
      a.length == b.length &&
      a.entries.every((e) => identical(b[e.key], e.value));
}

/// Строка кеша `index.json`: сводка журнала и ключ свежести.
final class _IndexEntry {
  const _IndexEntry({
    required this.size,
    required this.mtime,
    required this.summary,
  });

  factory _IndexEntry.fromJson(Map<String, Object?> json) => _IndexEntry(
    size: json['size']! as int,
    mtime: json['mtime']! as int,
    summary: SessionSummary(
      id: SessionId(json['id']! as String),
      cwd: json['cwd']! as String,
      title: json['title'] as String?,
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      messageCount: json['messageCount']! as int,
      lastTurnFailed: json['lastTurnFailed']! as bool,
    ),
  );

  final int size;

  /// `mtime` файла в миллисекундах.
  final int mtime;
  final SessionSummary summary;

  Map<String, Object?> toJson() => {
    'size': size,
    'mtime': mtime,
    'id': summary.id.value,
    'cwd': summary.cwd,
    'title': ?summary.title,
    'updatedAt': formatJournalTime(summary.updatedAt),
    'messageCount': summary.messageCount,
    'lastTurnFailed': summary.lastTurnFailed,
  };
}
