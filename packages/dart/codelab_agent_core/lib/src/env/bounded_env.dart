import 'dart:typed_data';

import '../util/posix_path.dart';
import '../util/result.dart';
import 'execution_env.dart';

/// Граница рабочей папки (`agent-core-architecture` §4.4).
///
/// Почему: инструменты получают пути от модели, и путь вроде `../../etc` или
/// ссылка наружу не должны выводить агента за корень сессии; обход границы в
/// обход этой обёртки запрещён (ENV-2).
///
/// Для чего: декоратор отклоняет любой путь вне корня сессии до того, как
/// внутренний env увидит операцию (ENV-3).
///
/// Как использовать: хост оборачивает env один раз при открытии сессии.
/// Путь нормализуется от корня; если внутренний env умеет раскрывать ссылки,
/// раскрывается самый длинный существующий префикс, поэтому ссылка наружу
/// ловится, а новый файл за ссылкой внутрь корня принимается. Сравнение
/// идёт по сегментам: `/proj_evil` не лежит в `/proj`. Внутренний env
/// получает нормализованный, а не раскрытый путь, чтобы сообщения показывали
/// путь так, как его видит пользователь.
abstract final class BoundedEnv {
  /// Оборачивает [inner] границей [root]. Результат реализует опциональную
  /// возможность, только если её реализует [inner] (ENV-4).
  ///
  /// Корни только для чтения (design.md change `add-agent-skills`, D5, D17;
  /// SKL-9): [readOnlyRoots] — канонические каталоги загруженных навыков вне
  /// [root]; чтение из них идёт в [readOnlyFs] (файловая система процесса
  /// агента — клиент ACP может не видеть этот каталог), запись — всегда
  /// `outsideWorkspace` до обращения к любому env (ENV-3). [execInReadOnlyRoots]
  /// разрешает `ExecOptions.cwd` в таком корне, только если внутренний env
  /// исполняет команды на той же машине, что [readOnlyFs]. Без [readOnlyFs]
  /// корни игнорируются: поведение прежнее. Корни раскрываются `realpath`
  /// через [readOnlyFs] один раз при создании.
  static Future<ExecutionEnv> wrap(
    ExecutionEnv inner,
    String root, {
    List<String> readOnlyRoots = const [],
    ExecutionEnv? readOnlyFs,
    bool execInReadOnlyRoots = false,
  }) async {
    final normalized = normalizePath('/', root)!;
    final resolver = inner is PathResolver ? inner as PathResolver : null;
    var realRoot = normalized;
    if (resolver != null) {
      if (await resolver.realpath(normalized) case Ok(:final value)) {
        realRoot = normalizePath('/', value)!;
      }
    }
    final roots = <_RoRoot>[];
    if (readOnlyFs != null) {
      for (final raw in readOnlyRoots) {
        final lexical = normalizePath('/', raw);
        if (lexical == null) {
          continue;
        }
        var real = lexical;
        if (readOnlyFs is PathResolver) {
          if (await (readOnlyFs as PathResolver).realpath(lexical) case Ok(
            :final value,
          )) {
            real = normalizePath('/', value)!;
          }
        }
        roots.add(_RoRoot(lexical, real));
      }
    }
    final guard = _Guard(
      inner,
      normalized,
      realRoot,
      resolver,
      roots,
      roots.isEmpty ? null : readOnlyFs,
      execInReadOnlyRoots,
    );
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

/// Корень только для чтения: нормализованная и реальная формы.
final class _RoRoot {
  const _RoRoot(this.lexical, this.real);

  final String lexical, real;
}

/// Путь, прошедший проверку: [abs] и env, которому уходит операция.
/// [readOnly] — путь в корне только для чтения (операция идёт в `readOnlyFs`).
final class _Target {
  const _Target(this.abs, {this.readOnly = false});

  final String abs;
  final bool readOnly;
}

final class _Guard {
  _Guard(
    this.inner,
    this.root,
    this.realRoot,
    this.resolver,
    this.roRoots,
    this.fs,
    this.execInRo,
  );

  final ExecutionEnv inner;
  final String root, realRoot;
  final PathResolver? resolver;
  final List<_RoRoot> roRoots;

  /// `readOnlyFs`; `null`, если корней нет.
  final ExecutionEnv? fs;
  final bool execInRo;

  /// The normalized path when it is inside the root, otherwise `null`.
  Future<String?> check(String path) async {
    final abs = normalizePath(root, path);
    if (abs == null) {
      return null;
    }
    final real = await _resolve(abs, inner, resolver);
    return isInside(realRoot, real) ? abs : null;
  }

  /// Классификация пути (D17): рабочая папка, затем корень только для
  /// чтения, затем прежняя проверка (ссылка извне в рабочую папку принимается).
  /// Внутренний env пути корня только для чтения не видит — ни `stat`, ни
  /// `realpath`.
  Future<_Target?> target(String path) async {
    final abs = normalizePath(root, path);
    if (abs == null) {
      return null;
    }
    if (!isInside(root, abs) && !isInside(realRoot, abs)) {
      for (final ro in roRoots) {
        if (isInside(ro.lexical, abs) || isInside(ro.real, abs)) {
          final fs = this.fs!;
          final real = await _resolve(
            abs,
            fs,
            fs is PathResolver ? fs as PathResolver : null,
          );
          // Реальный путь обязан остаться в том же корне: ссылка наружу — нет.
          return isInside(ro.real, real) || isInside(ro.lexical, real)
              ? _Target(abs, readOnly: true)
              : null;
        }
      }
    }
    return await check(path) == null ? null : _Target(abs);
  }

  /// Путь лексически лежит в корне только для чтения (и вне рабочей папки):
  /// запись туда отклоняется сразу, без `stat` и `realpath` любого env
  /// (ENV-3, D17).
  bool isReadOnlyPath(String path) {
    final abs = normalizePath(root, path);
    if (abs == null || isInside(root, abs) || isInside(realRoot, abs)) {
      return false;
    }
    return roRoots.any(
      (r) => isInside(r.lexical, abs) || isInside(r.real, abs),
    );
  }

  /// Env, которому уходит операция над [target].
  ExecutionEnv envOf(_Target target) => target.readOnly ? fs! : inner;

  Future<String> _resolve(
    String abs,
    ExecutionEnv env,
    PathResolver? resolver,
  ) async {
    if (resolver == null) {
      return abs;
    }
    var prefix = abs;
    final rest = <String>[];
    while (true) {
      if (await env.stat(prefix) case Ok()) {
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

Err<T, FileError> _unsupported<T>(String path) =>
    Err(FileError(FileErrorCode.unsupported, path));

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
    final t = await _guard.target(path);
    return t == null
        ? _outside(path)
        : _guard.envOf(t).readText(t.abs, line: line, limit: limit);
  }

  @override
  Future<Result<void, FileError>> writeText(String path, String content) async {
    // Корень только для чтения: запись не доходит ни до одного env (ENV-3),
    // в том числе до `stat`/`realpath` проверки пути.
    if (_guard.isReadOnlyPath(path)) {
      return _outside(path);
    }
    final t = await _guard.target(path);
    return t == null || t.readOnly
        ? _outside(path)
        : _guard.inner.writeText(t.abs, content);
  }

  @override
  Future<Result<FileStat, FileError>> stat(String path) async {
    final t = await _guard.target(path);
    return t == null ? _outside(path) : _guard.envOf(t).stat(t.abs);
  }

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) async {
    final t = await _guard.target(options.cwd);
    if (t == null || (t.readOnly && !_guard.execInRo)) {
      return Err(
        ExecError(
          ExecErrorCode.outsideWorkspace,
          message: 'working directory is outside the workspace: ${options.cwd}',
        ),
      );
    }
    return _guard.inner.exec(command, options.copyWith(cwd: t.abs));
  }
}

base mixin _Listing on _Bounded implements DirectoryListing {
  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) async {
    final t = await _guard.target(path);
    if (t == null) {
      return _outside(path);
    }
    // ENV-4: возможность корня только для чтения — по `readOnlyFs`.
    return switch (_guard.envOf(t)) {
      final DirectoryListing env => env.listDir(t.abs),
      _ => Future.value(_unsupported(path)),
    };
  }
}

base mixin _Binary on _Bounded implements BinaryFiles {
  @override
  Future<Result<Uint8List, FileError>> readBytes(String path) async {
    final t = await _guard.target(path);
    if (t == null) {
      return _outside(path);
    }
    return switch (_guard.envOf(t)) {
      final BinaryFiles env => env.readBytes(t.abs),
      _ => Future.value(_unsupported(path)),
    };
  }
}

base mixin _Resolver on _Bounded implements PathResolver {
  @override
  Future<Result<String, FileError>> realpath(String path) async {
    final t = await _guard.target(path);
    if (t == null) {
      return _outside(path);
    }
    if (t.readOnly) {
      return switch (_guard.fs) {
        final PathResolver fs => fs.realpath(t.abs),
        _ => _unsupported(path),
      };
    }
    final result = await _guard.resolver!.realpath(t.abs);
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
