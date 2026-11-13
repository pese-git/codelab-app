import 'dart:convert';
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Env «машины» с файлами в памяти, ссылками и всеми опциональными
/// возможностями; записывает вызовы (design.md change `add-agent-skills`,
/// D5).
///
/// Почему отдельный класс: тесты корней только для чтения различают два env
/// — внутренний (рабочая папка) и `readOnlyFs` (файловая система процесса
/// агента) — и проверяют, какому из них ушла операция. [calls] — операции
/// с побочным или содержательным действием (`readText`, `writeText`,
/// `readBytes`, `listDir`, `exec`); [resolves] — `stat` и `realpath`,
/// которыми обёртка проверяет путь.
final class MachineEnv
    implements ExecutionEnv, DirectoryListing, BinaryFiles, PathResolver {
  MachineEnv({String cwd = '/', this.links = const {}})
    : inner = MemoryExecutionEnv(cwd: cwd);

  final MemoryExecutionEnv inner;

  /// Ссылка → абсолютная цель.
  final Map<String, String> links;
  final calls = <String>[];
  final resolves = <String>[];

  String _resolve(String path) {
    for (final MapEntry(key: link, value: target) in links.entries) {
      if (path == link || path.startsWith('$link/')) {
        return target + path.substring(link.length);
      }
    }
    return path;
  }

  @override
  String get cwd => inner.cwd;

  @override
  Future<Result<String, FileError>> realpath(String path) async {
    resolves.add('realpath $path');
    final real = _resolve(path);
    return switch (await inner.stat(real)) {
      Ok() => Ok(real),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<Result<FileStat, FileError>> stat(String path) {
    resolves.add('stat $path');
    return inner.stat(_resolve(path));
  }

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) {
    calls.add('readText $path');
    return inner.readText(_resolve(path), line: line, limit: limit);
  }

  @override
  Future<Result<Uint8List, FileError>> readBytes(String path) async {
    calls.add('readBytes $path');
    return switch (await inner.readText(_resolve(path))) {
      Ok(:final value) => Ok(Uint8List.fromList(utf8.encode(value))),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<Result<void, FileError>> writeText(String path, String content) {
    calls.add('writeText $path');
    return inner.writeText(_resolve(path), content);
  }

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) {
    calls.add('listDir $path');
    return inner.listDir(_resolve(path));
  }

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) async {
    calls.add('exec ${options.cwd}');
    return const Ok(
      ExecResult(
        exitCode: 0,
        output: '',
        truncated: false,
        duration: Duration.zero,
      ),
    );
  }
}
