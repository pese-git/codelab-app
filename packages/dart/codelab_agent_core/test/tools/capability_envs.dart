import 'dart:convert';
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Окружения с другим набором capability поверх [MemoryExecutionEnv]:
/// инструменты ведут себя по-разному в зависимости от того, что умеет env
/// (§4.3), и тестам нужны оба варианта.

/// Только файлы и shell — без `DirectoryListing`, как ACP-клиент без
/// листинга каталога.
final class FilesOnlyEnv implements ExecutionEnv {
  FilesOnlyEnv(this.memory);

  final MemoryExecutionEnv memory;

  @override
  String get cwd => memory.cwd;

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => memory.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      memory.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => memory.stat(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => memory.exec(command, options);
}

/// Память с `BinaryFiles`: так `read` может отдать картинку.
/// [MemoryExecutionEnv] не реализует `BinaryFiles` (§4.8), поэтому байты
/// двоичных файлов хранятся здесь отдельно.
final class BinaryMemoryEnv
    implements ExecutionEnv, DirectoryListing, BinaryFiles {
  BinaryMemoryEnv(this.memory);

  final MemoryExecutionEnv memory;
  final _bytes = <String, Uint8List>{};

  void putBinary(String path, Uint8List bytes) {
    _bytes[path] = bytes;
    memory.putBytes(path, bytes);
  }

  @override
  String get cwd => memory.cwd;

  @override
  Future<Result<Uint8List, FileError>> readBytes(String path) async {
    if (_bytes[path] case final bytes?) {
      return Ok(bytes);
    }
    return switch (await memory.readText(path)) {
      Ok(:final value) => Ok(utf8.encode(value)),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => memory.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      memory.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => memory.stat(path);

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) =>
      memory.listDir(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => memory.exec(command, options);
}
