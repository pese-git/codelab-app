/// Paths of the host ↔ POSIX paths of the core (design.md of
/// `add-agent-core-loop-and-tools`, D3): the core works only with
/// `/`-separated paths, so a Windows path `C:\proj` becomes `/c/proj`.
library;

final _drive = RegExp(r'^([A-Za-z]):[\\/]?(.*)$');

String toCorePath(String hostPath, {required bool windows}) {
  if (!windows) {
    return hostPath;
  }
  final match = _drive.firstMatch(hostPath);
  if (match == null) {
    return hostPath.replaceAll(r'\', '/');
  }
  final rest = match.group(2)!.replaceAll(r'\', '/');
  final trimmed = rest.endsWith('/')
      ? rest.substring(0, rest.length - 1)
      : rest;
  return '/${match.group(1)!.toLowerCase()}${trimmed.isEmpty ? '' : '/$trimmed'}';
}

String toHostPath(String corePath, {required bool windows}) {
  if (!windows) {
    return corePath;
  }
  final segments = corePath.split('/')..removeWhere((s) => s.isEmpty);
  if (segments.isEmpty || segments.first.length != 1) {
    return corePath.replaceAll('/', r'\');
  }
  final drive = '${segments.first.toUpperCase()}:';
  return '$drive\\${segments.skip(1).join(r'\')}';
}
