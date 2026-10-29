import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'host_path.dart';
import 'host_variables.dart';
import 'output_buffer.dart';
import 'process_tree.dart';

const _tailLimit = 64 * 1024;
const _pipeGrace = Duration(seconds: 1);

/// Fixed variables: commands must not wait for interactive input.
const _fixedVariables = {
  'TERM': 'dumb',
  'PAGER': 'cat',
  'GIT_PAGER': 'cat',
  'GIT_TERMINAL_PROMPT': '0',
};

/// Files and processes of the local machine (`agent-core-architecture`
/// §4.3, §4.6). Paths of the core are POSIX; on Windows they are converted
/// to host paths and back (design.md, D3). Expected failures are values
/// (ENV-1); `exec` returns within 5 s after a timeout or a cancel (ENV-5),
/// and the environment of a command is the allowlist of §4.5 plus explicit
/// variables (ENV-6).
final class LocalExecutionEnv
    implements ExecutionEnv, DirectoryListing, BinaryFiles, PathResolver {
  LocalExecutionEnv({
    required String cwd,
    String? shell,
    Map<String, String>? hostEnvironment,
  }) : _windows = io.Platform.isWindows,
       _shell = shell ?? (io.Platform.isWindows ? 'cmd.exe' : '/bin/sh'),
       _hostEnvironment = hostEnvironment ?? io.Platform.environment,
       cwd = toCorePath(cwd, windows: io.Platform.isWindows);

  @override
  final String cwd;
  final bool _windows;
  final String _shell;
  final Map<String, String> _hostEnvironment;

  String _host(String path) {
    final abs = path.startsWith('/') ? path : '$cwd/$path';
    return toHostPath(abs, windows: _windows);
  }

  String _core(String hostPath) => toCorePath(hostPath, windows: _windows);

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) async {
    final bytes = await readBytes(path);
    return switch (bytes) {
      Err(:final error) => Err(error),
      Ok(:final value) => switch (decodeUtf8Strict(value)) {
        null => Err(FileError(FileErrorCode.notText, path)),
        final text => Ok(sliceLines(text, line: line, limit: limit)),
      },
    };
  }

  @override
  Future<Result<Uint8List, FileError>> readBytes(String path) async {
    final host = _host(path);
    final type = await io.FileSystemEntity.type(host);
    if (type == io.FileSystemEntityType.notFound) {
      return Err(FileError(FileErrorCode.notFound, path));
    }
    if (type == io.FileSystemEntityType.directory) {
      return Err(FileError(FileErrorCode.isDirectory, path));
    }
    try {
      return Ok(await io.File(host).readAsBytes());
    } on io.FileSystemException catch (e) {
      return Err(_error(e, path));
    }
  }

  @override
  Future<Result<void, FileError>> writeText(String path, String content) async {
    final host = _host(path);
    if (await io.FileSystemEntity.isDirectory(host)) {
      return Err(FileError(FileErrorCode.isDirectory, path));
    }
    try {
      await io.File(host).parent.create(recursive: true);
      await io.File(host).writeAsBytes(utf8.encode(content), flush: true);
      return const Ok(null);
    } on io.FileSystemException catch (e) {
      return Err(_error(e, path));
    }
  }

  @override
  Future<Result<FileStat, FileError>> stat(String path) async {
    final host = _host(path);
    final type = await io.FileSystemEntity.type(host, followLinks: false);
    if (type == io.FileSystemEntityType.notFound) {
      return Err(FileError(FileErrorCode.notFound, path));
    }
    return Ok(await _stat(host, type));
  }

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) async {
    final host = _host(path);
    final type = await io.FileSystemEntity.type(host);
    if (type == io.FileSystemEntityType.notFound) {
      return Err(FileError(FileErrorCode.notFound, path));
    }
    if (type != io.FileSystemEntityType.directory) {
      return Err(FileError(FileErrorCode.notDirectory, path));
    }
    try {
      final entries = <FileStat>[];
      await for (final entity in io.Directory(host).list(followLinks: false)) {
        final entityType = await io.FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        entries.add(await _stat(entity.path, entityType));
      }
      entries.sort((a, b) => a.path.compareTo(b.path));
      return Ok(entries);
    } on io.FileSystemException catch (e) {
      return Err(_error(e, path));
    }
  }

  @override
  Future<Result<String, FileError>> realpath(String path) async {
    try {
      return Ok(_core(await io.File(_host(path)).resolveSymbolicLinks()));
    } on io.FileSystemException catch (e) {
      return Err(_error(e, path));
    }
  }

  Future<FileStat> _stat(String host, io.FileSystemEntityType type) async {
    final path = _core(host);
    final kind = switch (type) {
      io.FileSystemEntityType.file => FileType.file,
      io.FileSystemEntityType.directory => FileType.directory,
      io.FileSystemEntityType.link => FileType.link,
      _ => FileType.other,
    };
    if (kind == FileType.link) {
      return FileStat(path: path, type: kind);
    }
    final stat = await io.FileStat.stat(host);
    return FileStat(
      path: path,
      type: kind,
      size: kind == FileType.file ? stat.size : null,
      modified: stat.modified.toUtc(),
    );
  }

  static FileError _error(io.FileSystemException e, String path) =>
      switch (e.osError?.errorCode) {
        2 => FileError(FileErrorCode.notFound, path),
        13 || 1 => FileError(FileErrorCode.permissionDenied, path),
        20 => FileError(FileErrorCode.notDirectory, path),
        21 => FileError(FileErrorCode.isDirectory, path),
        _ => FileError(FileErrorCode.io, path, e.message),
      };

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) async {
    final watch = Stopwatch()..start();
    final dir = _host(options.cwd);
    if (!await io.Directory(dir).exists()) {
      return const Err(
        ExecError(
          ExecErrorCode.spawnFailed,
          message: 'working directory does not exist',
        ),
      );
    }
    final io.Process process;
    try {
      process = await io.Process.start(
        _shell,
        _windows ? ['/d', '/s', '/c', command] : ['-c', command],
        workingDirectory: dir,
        environment: _environment(options.env),
        includeParentEnvironment: false,
      );
    } on io.ProcessException catch (e) {
      final missing = !_windows && !await io.File(_shell).exists();
      return Err(
        ExecError(
          missing ? ExecErrorCode.shellUnavailable : ExecErrorCode.spawnFailed,
          message: e.message,
        ),
      );
    }
    unawaited(process.stdin.close().catchError((Object _) {}));
    final buffer = OutputBuffer(options.outputByteLimit);
    void onChunk(String chunk) {
      buffer.add(chunk);
      options.onOutput?.call(chunk);
    }

    final decoder = Utf8Decoder(allowMalformed: true);
    final subscriptions = [
      process.stdout.transform(decoder).listen(onChunk),
      process.stderr.transform(decoder).listen(onChunk),
    ];
    final pipes = [for (final s in subscriptions) s.asFuture<void>()];
    final ended = Completer<_End>();
    process.exitCode.then((code) {
      if (!ended.isCompleted) {
        ended.complete(_Exited(code));
      }
    });
    final timer = options.timeout == null
        ? null
        : Timer(options.timeout!, () {
            if (!ended.isCompleted) {
              ended.complete(const _TimedOut());
            }
          });
    options.cancel.onCancel.then((_) {
      if (!ended.isCompleted) {
        ended.complete(const _Cancelled());
      }
    });
    final end = await ended.future;
    timer?.cancel();
    if (end is! _Exited) {
      await terminateTree(process);
    }
    // A grandchild may inherit a pipe and keep it open: unsubscribe after
    // the grace period (§4.6, step 7).
    await Future.wait(pipes).timeout(_pipeGrace, onTimeout: () => const []);
    for (final s in subscriptions) {
      await s.cancel();
    }
    watch.stop();
    return switch (end) {
      _Exited(:final code) => Ok(
        ExecResult(
          exitCode: code >= 0 ? code : null,
          signal: code < 0 ? 'SIG${-code}' : null,
          output: buffer.text,
          truncated: buffer.truncated,
          duration: watch.elapsed,
        ),
      ),
      _TimedOut() => Err(
        ExecError(
          ExecErrorCode.timeout,
          outputTail: buffer.tail(_tailLimit),
          duration: watch.elapsed,
        ),
      ),
      _Cancelled() => Err(
        ExecError(
          ExecErrorCode.aborted,
          outputTail: buffer.tail(_tailLimit),
          duration: watch.elapsed,
        ),
      ),
    };
  }

  Map<String, String> _environment(Map<String, String> extra) => {
    for (final name in hostEnvironmentAllowlist) name: ?_hostEnvironment[name],
    ..._fixedVariables,
    ...extra,
  };
}

sealed class _End {
  const _End();
}

final class _Exited extends _End {
  const _Exited(this.code);

  final int code;
}

final class _TimedOut extends _End {
  const _TimedOut();
}

final class _Cancelled extends _End {
  const _Cancelled();
}
