/// POSIX paths of the core (`agent-core-architecture` §4.4). The core works
/// only with `/`-separated absolute paths; hosts convert their own paths
/// before handing them over (design.md, D3).
library;

/// Normalizes [path] against the absolute [base]: a relative path is joined
/// to [base], empty segments and `.` are dropped, `..` removes the previous
/// segment (at the root it stays the root). `~` and `~/…` give `null`: the
/// core does not expand the home directory.
String? normalizePath(String base, String path) {
  if (path == '~' || path.startsWith('~/')) {
    return null;
  }
  final full = path.startsWith('/') ? path : '$base/$path';
  final segments = <String>[];
  for (final segment in full.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(segment);
  }
  return '/${segments.join('/')}';
}

/// Whether the normalized absolute [path] is [root] or lies under it,
/// compared by segments: `/proj_evil` is not inside `/proj`.
bool isInside(String root, String path) =>
    root == '/' || path == root || path.startsWith('$root/');

/// [path] relative to [root] for output; `.` for the root itself and the
/// absolute path for anything outside it.
String relativeTo(String root, String path) {
  if (path == root) {
    return '.';
  }
  if (!isInside(root, path)) {
    return path;
  }
  return path.substring(root == '/' ? 1 : root.length + 1);
}

/// The parent of a normalized absolute path; the root is its own parent.
String parentOf(String path) {
  final i = path.lastIndexOf('/');
  return i <= 0 ? '/' : path.substring(0, i);
}
