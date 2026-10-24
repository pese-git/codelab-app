import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../util/clock.dart';
import '../util/posix_path.dart';
import '../util/result.dart';
import 'execution_env.dart';

/// Files in memory under absolute POSIX paths (`agent-core-architecture`
/// §4.8): the default env of tests and the base of the web env. `/` and
/// [cwd] always exist; there are no links, so [PathResolver] is not
/// implemented; `exec` answers [ExecErrorCode.shellUnavailable].
final class MemoryExecutionEnv implements ExecutionEnv, DirectoryListing {
  MemoryExecutionEnv({String cwd = '/work', Clock? clock})
    : cwd = normalizePath('/', cwd)!,
      _clock = clock ?? const SystemClock() {
    var path = this.cwd;
    while (true) {
      _nodes[path] = _Dir(_clock.now());
      if (path == '/') {
        break;
      }
      path = parentOf(path);
    }
  }

  @override
  final String cwd;
  final Clock _clock;
  final _nodes = SplayTreeMap<String, _Node>();

  /// Puts raw bytes into a file, creating parents — for tests of
  /// non-UTF-8 content.
  void putBytes(String path, Uint8List bytes) {
    final abs = _abs(path);
    _mkdirs(parentOf(abs));
    _nodes[abs] = _File(bytes, _clock.now());
  }

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) async {
    final abs = _abs(path);
    final node = _nodes[abs];
    switch (node) {
      case null:
        return Err(FileError(FileErrorCode.notFound, abs));
      case _Dir():
        return Err(FileError(FileErrorCode.isDirectory, abs));
      case _File(:final bytes):
        final text = decodeUtf8Strict(bytes);
        return text == null
            ? Err(FileError(FileErrorCode.notText, abs))
            : Ok(sliceLines(text, line: line, limit: limit));
    }
  }

  @override
  Future<Result<void, FileError>> writeText(String path, String content) async {
    final abs = _abs(path);
    if (_nodes[abs] is _Dir) {
      return Err(FileError(FileErrorCode.isDirectory, abs));
    }
    var parent = parentOf(abs);
    while (true) {
      if (_nodes[parent] is _File) {
        return Err(FileError(FileErrorCode.notDirectory, abs));
      }
      if (parent == '/') {
        break;
      }
      parent = parentOf(parent);
    }
    _mkdirs(parentOf(abs));
    _nodes[abs] = _File(utf8.encode(content), _clock.now());
    return const Ok(null);
  }

  @override
  Future<Result<FileStat, FileError>> stat(String path) async {
    final abs = _abs(path);
    return switch (_nodes[abs]) {
      null => Err(FileError(FileErrorCode.notFound, abs)),
      _Dir(:final modified) => Ok(
        FileStat(path: abs, type: FileType.directory, modified: modified),
      ),
      _File(:final bytes, :final modified) => Ok(
        FileStat(
          path: abs,
          type: FileType.file,
          size: bytes.length,
          modified: modified,
        ),
      ),
    };
  }

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) async {
    final abs = _abs(path);
    switch (_nodes[abs]) {
      case null:
        return Err(FileError(FileErrorCode.notFound, abs));
      case _File():
        return Err(FileError(FileErrorCode.notDirectory, abs));
      case _Dir():
        final prefix = abs == '/' ? '/' : '$abs/';
        final entries = <FileStat>[];
        for (final key in _nodes.keys) {
          if (key == abs ||
              !key.startsWith(prefix) ||
              key.substring(prefix.length).contains('/')) {
            continue;
          }
          entries.add(((await stat(key)) as Ok<FileStat, FileError>).value);
        }
        return Ok(entries);
    }
  }

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) async => const Err(
    ExecError(
      ExecErrorCode.shellUnavailable,
      message: 'shell is not available on this platform',
    ),
  );

  String _abs(String path) => normalizePath(cwd, path) ?? path;

  void _mkdirs(String path) {
    var current = path;
    while (!_nodes.containsKey(current)) {
      _nodes[current] = _Dir(_clock.now());
      if (current == '/') {
        break;
      }
      current = parentOf(current);
    }
  }
}

/// Strict UTF-8 that keeps a leading byte order mark (`utf8.decode` drops
/// it, and `edit` must write it back); `null` for invalid UTF-8.
String? decodeUtf8Strict(List<int> bytes) {
  final bom =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  try {
    final text = utf8.decode(bom ? bytes.sublist(3) : bytes);
    return bom ? '\uFEFF$text' : text;
  } on FormatException {
    return null;
  }
}

/// Lines from [line] (1-based), at most [limit], each with its terminator:
/// the slicing of `FileSystem.readText` shared by the envs of the core.
String sliceLines(String text, {int? line, int? limit}) {
  if (line == null && limit == null) {
    return text;
  }
  final first = (line ?? 1) < 1 ? 0 : (line ?? 1) - 1;
  var start = 0;
  for (var i = 0; i < first; i++) {
    final next = text.indexOf('\n', start);
    if (next < 0) {
      return '';
    }
    start = next + 1;
  }
  if (limit == null) {
    return text.substring(start);
  }
  var end = start;
  for (var i = 0; i < limit && end < text.length; i++) {
    final next = text.indexOf('\n', end);
    end = next < 0 ? text.length : next + 1;
  }
  return text.substring(start, end);
}

sealed class _Node {
  const _Node(this.modified);

  final DateTime modified;
}

final class _Dir extends _Node {
  const _Dir(super.modified);
}

final class _File extends _Node {
  const _File(this.bytes, super.modified);

  final Uint8List bytes;
}
