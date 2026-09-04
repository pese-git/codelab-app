import 'package:path/path.dart' as p;

/// Client-side port for reading a text file, backing ACP `fs/read_text_file`.
///
/// Implemented by an infrastructure adapter (`apps/codelab_app/lib/core/
/// platform/`, per `docs/architecture/platform-integration.md`) and injected
/// into [AcpClientApplication] — this package stays free of `dart:io`.
abstract interface class TextFileReader {
  Future<String> readText({required String path, int? line, int? limit});
}

/// Client-side port for writing a text file, backing ACP
/// `fs/write_text_file`. See [TextFileReader] for why this is a port rather
/// than a direct `dart:io` call.
abstract interface class TextFileWriter {
  Future<void> writeText({required String path, required String content});
}

sealed class FsAccessFailure implements Exception {
  const FsAccessFailure();
}

/// The requested `path`, once lexically normalized, does not fall inside the
/// session's working directory — a `..`/relative-style escape attempt, not
/// an IO problem. Rejected before any infrastructure call is made.
final class PathOutsideWorkingDirectoryFailure extends FsAccessFailure {
  const PathOutsideWorkingDirectoryFailure({
    required this.path,
    required this.workingDirectory,
  });

  final String path;
  final String workingDirectory;

  @override
  String toString() =>
      'Path "$path" is outside the session working directory '
      '"$workingDirectory".';
}

/// The underlying filesystem operation failed (missing file, no permission,
/// disk full, ...) — surfaced by a [TextFileReader]/[TextFileWriter]
/// implementation, not by path validation.
final class FsIoFailure extends FsAccessFailure {
  const FsIoFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Lexically resolves [path] against [workingDirectory] and throws
/// [PathOutsideWorkingDirectoryFailure] if it escapes — the working-directory
/// containment that stands in for approval on `fs/*` requests (see
/// `openspec/changes/add-acp-fs-client-support/design.md`, Decision 3).
///
/// This is normalization only (`.`/`..`/separator cleanup via `package:path`,
/// no filesystem access) — it does not resolve symlinks, since doing so
/// would require `dart:io`, which this package must not depend on for file
/// access (`docs/architecture/platform-integration.md` §9-10). Symlink
/// escapes are a known residual risk, accepted in the design's Risks section.
String resolveWithinWorkingDirectory({
  required String path,
  required String workingDirectory,
}) {
  final normalizedRoot = p.normalize(workingDirectory);
  final normalizedPath = p.normalize(path);

  final rootWithSeparator = normalizedRoot.endsWith(p.separator)
      ? normalizedRoot
      : '$normalizedRoot${p.separator}';

  final isWithinRoot =
      normalizedPath == normalizedRoot ||
      normalizedPath.startsWith(rootWithSeparator);

  if (!isWithinRoot) {
    throw PathOutsideWorkingDirectoryFailure(
      path: path,
      workingDirectory: workingDirectory,
    );
  }

  return normalizedPath;
}
