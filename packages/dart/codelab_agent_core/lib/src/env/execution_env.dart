import 'dart:typed_data';

import '../cancel/cancel_token.dart';
import '../util/result.dart';

/// The only point where the core touches files and processes
/// (`agent-core-architecture` §4). Built-in tools are written once over
/// this port and work locally, through the ACP client and in memory.
///
/// Paths on input are absolute or relative to [FileSystem.cwd]; paths on
/// output are absolute and normalized. Expected failures are values
/// ([FileError], [ExecError]), never exceptions (ENV-1).

enum FileErrorCode {
  notFound,
  permissionDenied,
  isDirectory,
  notDirectory,
  outsideWorkspace,
  tooLarge,
  notText,
  unsupported,
  io,
}

final class FileError {
  const FileError(this.code, this.path, [this.message]);

  final FileErrorCode code;
  final String path;
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is FileError &&
      other.code == code &&
      other.path == path &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, path, message);

  @override
  String toString() =>
      'FileError(${code.name}, $path${message == null ? '' : ', $message'})';
}

enum FileType { file, directory, link, other }

final class FileStat {
  const FileStat({
    required this.path,
    required this.type,
    this.size,
    this.modified,
  });

  /// Absolute normalized path.
  final String path;
  final FileType type;

  /// Bytes; `null` — unknown (ACP client).
  final int? size;
  final DateTime? modified;

  @override
  String toString() => 'FileStat($path, ${type.name})';
}

final class ExecOptions {
  ExecOptions({
    required this.cwd,
    this.env = const {},
    this.timeout,
    CancelToken? cancel,
    this.onOutput,
    this.onTerminal,
    this.outputByteLimit = 1 << 20,
  }) : cancel = cancel ?? CancelToken.none;

  /// Absolute, or relative to the cwd of the env.
  final String cwd;

  /// On top of the minimal environment (ENV-6).
  final Map<String, String> env;
  final Duration? timeout;
  final CancelToken cancel;

  /// Output as it arrives.
  final void Function(String chunk)? onOutput;

  /// ACP: the terminal id to embed into the tool call.
  final void Function(String terminalId)? onTerminal;

  /// Only the tail of at most this many bytes is kept.
  final int outputByteLimit;

  ExecOptions copyWith({String? cwd}) => ExecOptions(
    cwd: cwd ?? this.cwd,
    env: env,
    timeout: timeout,
    cancel: cancel,
    onOutput: onOutput,
    onTerminal: onTerminal,
    outputByteLimit: outputByteLimit,
  );
}

final class ExecResult {
  const ExecResult({
    required this.exitCode,
    required this.output,
    required this.truncated,
    required this.duration,
    this.signal,
  });

  final int? exitCode;
  final String? signal;

  /// stdout and stderr in the order of arrival.
  final String output;

  /// The beginning of the output was dropped by the limit.
  final bool truncated;
  final Duration duration;
}

enum ExecErrorCode {
  aborted,
  timeout,
  shellUnavailable,
  spawnFailed,
  outsideWorkspace,
  unknown,
}

final class ExecError {
  const ExecError(
    this.code, {
    this.message,
    this.outputTail = '',
    this.duration,
  });

  final ExecErrorCode code;
  final String? message;

  /// With aborted and timeout: the tail of the output, at most 64 KiB.
  final String outputTail;
  final Duration? duration;

  @override
  String toString() =>
      'ExecError(${code.name}${message == null ? '' : ', $message'})';
}

abstract interface class FileSystem {
  /// The root of the session.
  String get cwd;

  /// Lines from [line] (1-based), at most [limit], each with its line
  /// terminator; without parameters — the whole file. Invalid UTF-8 →
  /// [FileErrorCode.notText]; a directory → [FileErrorCode.isDirectory].
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  });

  /// Writes the whole file, creating missing parents.
  Future<Result<void, FileError>> writeText(String path, String content);

  Future<Result<FileStat, FileError>> stat(String path);
}

abstract interface class Shell {
  /// Runs a command line through the shell of the host. A non-zero exit
  /// code is `Ok(ExecResult(exitCode: N))`: a failed command is data for
  /// the model.
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  );
}

abstract interface class ExecutionEnv implements FileSystem, Shell {}

/// Optional capabilities, checked with `is`.
abstract interface class DirectoryListing {
  Future<Result<List<FileStat>, FileError>> listDir(String path);
}

abstract interface class BinaryFiles {
  Future<Result<Uint8List, FileError>> readBytes(String path);
}

abstract interface class PathResolver {
  Future<Result<String, FileError>> realpath(String path);
}
