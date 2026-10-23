import 'package:codelab_agent_core/codelab_agent_core.dart';

/// A [MemoryExecutionEnv] with symbolic links: [links] maps a link path to
/// its absolute target. Implements [PathResolver] and records every call
/// except `stat` and `realpath` in [operations].
final class ResolvingEnv
    implements ExecutionEnv, DirectoryListing, PathResolver {
  ResolvingEnv(this.inner, {this.links = const {}});

  final MemoryExecutionEnv inner;
  final Map<String, String> links;
  final operations = <String>[];

  String _resolve(String path) {
    var current = path;
    for (var i = 0; i < 8; i++) {
      String? next;
      for (final MapEntry(key: link, value: target) in links.entries) {
        if (current == link || current.startsWith('$link/')) {
          next = target + current.substring(link.length);
          break;
        }
      }
      if (next == null) {
        return current;
      }
      current = next;
    }
    return current;
  }

  @override
  String get cwd => inner.cwd;

  @override
  Future<Result<String, FileError>> realpath(String path) async {
    final real = _resolve(path);
    return switch (await inner.stat(real)) {
      Ok() => Ok(real),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<Result<FileStat, FileError>> stat(String path) async {
    if (links.containsKey(path)) {
      return Ok(FileStat(path: path, type: FileType.link));
    }
    return inner.stat(_resolve(path));
  }

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) {
    operations.add('readText $path');
    return inner.readText(_resolve(path), line: line, limit: limit);
  }

  @override
  Future<Result<void, FileError>> writeText(String path, String content) {
    operations.add('writeText $path');
    return inner.writeText(_resolve(path), content);
  }

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) {
    operations.add('listDir $path');
    return inner.listDir(_resolve(path));
  }

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) {
    operations.add('exec ${options.cwd}');
    return inner.exec(command, options);
  }
}

/// A recording env without optional capabilities.
final class PlainEnv implements ExecutionEnv {
  PlainEnv(this.inner);

  final MemoryExecutionEnv inner;
  final operations = <String>[];

  @override
  String get cwd => inner.cwd;

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) {
    operations.add('readText $path');
    return inner.readText(path, line: line, limit: limit);
  }

  @override
  Future<Result<void, FileError>> writeText(String path, String content) {
    operations.add('writeText $path');
    return inner.writeText(path, content);
  }

  @override
  Future<Result<FileStat, FileError>> stat(String path) {
    operations.add('stat $path');
    return inner.stat(path);
  }

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) {
    operations.add('exec ${options.cwd}');
    return inner.exec(command, options);
  }
}

FileErrorCode? fileErrorOf(Result<Object?, FileError> result) =>
    switch (result) {
      Ok() => null,
      Err(:final error) => error.code,
    };
