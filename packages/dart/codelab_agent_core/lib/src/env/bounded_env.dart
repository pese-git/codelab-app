import 'dart:typed_data';

import '../util/posix_path.dart';
import '../util/result.dart';
import 'execution_env.dart';

/// The workspace boundary (`agent-core-architecture` §4.4): a decorator
/// that rejects every path outside the session root before the inner env
/// sees the operation (ENV-3). No tool gets the base env around it
/// (ENV-2).
///
/// A path is normalized against the root; when the inner env resolves
/// links, the longest existing prefix of the path is resolved, so a link
/// out of the root is caught and a new file behind a link into the root is
/// accepted. The check compares segments: `/proj_evil` is not inside
/// `/proj`. The inner env receives the normalized path, not the resolved
/// one, so messages show the path as the user sees it.
abstract final class BoundedEnv {
  /// Wraps [inner] at [root]. The result implements an optional capability
  /// only when [inner] does (ENV-4).
  static Future<ExecutionEnv> wrap(ExecutionEnv inner, String root) async {
    final normalized = normalizePath('/', root)!;
    final resolver = inner is PathResolver ? inner as PathResolver : null;
    var realRoot = normalized;
    if (resolver != null) {
      if (await resolver.realpath(normalized) case Ok(:final value)) {
        realRoot = normalizePath('/', value)!;
      }
    }
    final guard = _Guard(inner, normalized, realRoot, resolver);
    return switch ((
      inner is DirectoryListing,
      inner is BinaryFiles,
      resolver != null,
    )) {
      (false, false, false) => _Bounded(guard),
      (true, false, false) => _BoundedL(guard),
      (false, true, false) => _BoundedB(guard),
      (false, false, true) => _BoundedR(guard),
      (true, true, false) => _BoundedLB(guard),
      (true, false, true) => _BoundedLR(guard),
      (false, true, true) => _BoundedBR(guard),
      (true, true, true) => _BoundedLBR(guard),
    };
  }
}

final class _Guard {
  _Guard(this.inner, this.root, this.realRoot, this.resolver);

  final ExecutionEnv inner;
  final String root, realRoot;
  final PathResolver? resolver;

  /// The normalized path when it is inside the root, otherwise `null`.
  Future<String?> check(String path) async {
    final abs = normalizePath(root, path);
    if (abs == null) {
      return null;
    }
    final real = await _resolve(abs);
    return isInside(realRoot, real) ? abs : null;
  }

  Future<String> _resolve(String abs) async {
    final resolver = this.resolver;
    if (resolver == null) {
      return abs;
    }
    var prefix = abs;
    final rest = <String>[];
    while (true) {
      if (await inner.stat(prefix) case Ok()) {
        if (await resolver.realpath(prefix) case Ok(:final value)) {
          final resolved = normalizePath('/', value)!;
          return rest.isEmpty
              ? resolved
              : normalizePath(resolved, rest.reversed.join('/'))!;
        }
        return abs;
      }
      if (prefix == '/') {
        return abs;
      }
      rest.add(prefix.substring(prefix.lastIndexOf('/') + 1));
      prefix = parentOf(prefix);
    }
  }
}

Err<T, FileError> _outside<T>(String path) =>
    Err(FileError(FileErrorCode.outsideWorkspace, path));

base class _Bounded implements ExecutionEnv {
  _Bounded(this._guard);

  final _Guard _guard;

  @override
  String get cwd => _guard.root;

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) async {
    final abs = await _guard.check(path);
    return abs == null
        ? _outside(path)
        : _guard.inner.readText(abs, line: line, limit: limit);
  }

  @override
  Future<Result<void, FileError>> writeText(String path, String content) async {
    final abs = await _guard.check(path);
    return abs == null ? _outside(path) : _guard.inner.writeText(abs, content);
  }

  @override
  Future<Result<FileStat, FileError>> stat(String path) async {
    final abs = await _guard.check(path);
    return abs == null ? _outside(path) : _guard.inner.stat(abs);
  }

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) async {
    final abs = await _guard.check(options.cwd);
    if (abs == null) {
      return Err(
        ExecError(
          ExecErrorCode.outsideWorkspace,
          message: 'working directory is outside the workspace: ${options.cwd}',
        ),
      );
    }
    return _guard.inner.exec(command, options.copyWith(cwd: abs));
  }
}

base mixin _Listing on _Bounded implements DirectoryListing {
  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) async {
    final abs = await _guard.check(path);
    return abs == null
        ? _outside(path)
        : (_guard.inner as DirectoryListing).listDir(abs);
  }
}

base mixin _Binary on _Bounded implements BinaryFiles {
  @override
  Future<Result<Uint8List, FileError>> readBytes(String path) async {
    final abs = await _guard.check(path);
    return abs == null
        ? _outside(path)
        : (_guard.inner as BinaryFiles).readBytes(abs);
  }
}

base mixin _Resolver on _Bounded implements PathResolver {
  @override
  Future<Result<String, FileError>> realpath(String path) async {
    final abs = await _guard.check(path);
    if (abs == null) {
      return _outside(path);
    }
    final result = await _guard.resolver!.realpath(abs);
    return switch (result) {
      Ok(:final value) when !isInside(_guard.realRoot, value) => _outside(path),
      _ => result,
    };
  }
}

final class _BoundedL extends _Bounded with _Listing {
  _BoundedL(super.guard);
}

final class _BoundedB extends _Bounded with _Binary {
  _BoundedB(super.guard);
}

final class _BoundedR extends _Bounded with _Resolver {
  _BoundedR(super.guard);
}

final class _BoundedLB extends _Bounded with _Listing, _Binary {
  _BoundedLB(super.guard);
}

final class _BoundedLR extends _Bounded with _Listing, _Resolver {
  _BoundedLR(super.guard);
}

final class _BoundedBR extends _Bounded with _Binary, _Resolver {
  _BoundedBR(super.guard);
}

final class _BoundedLBR extends _Bounded with _Listing, _Binary, _Resolver {
  _BoundedLBR(super.guard);
}
