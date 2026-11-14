/// The fence of untrusted output (`agent-core-architecture` §6.3.6): text
/// from files, commands and servers the model must not obey enters the
/// transcript only inside `<untrusted-content>` (TOOL-10).
library;

final _marker = RegExp(r'</?untrusted-content', caseSensitive: false);

/// Wraps [text]; markers inside it are escaped (`<` → `&lt;`), quotes of
/// [source] become `'`.
String fenceUntrusted(String text, {required String source}) {
  final escaped = text.replaceAllMapped(
    _marker,
    (m) => '&lt;${m[0]!.substring(1)}',
  );
  return '<untrusted-content source="${source.replaceAll('"', "'")}">\n'
      '$escaped\n</untrusted-content>';
}

/// Directories whose files are third-party data (`tools.untrusted_paths`,
/// §6.3.6); the configuration that changes the list arrives at stage 8.
const defaultUntrustedPaths = ['node_modules', '.dart_tool', 'vendor'];

/// Whether a workspace-relative [path] lies under an untrusted directory.
bool isUntrustedPath(String path) =>
    path.split('/').any(defaultUntrustedPaths.contains);

const _networkPrefixes = [
  'curl',
  'wget',
  'http',
  'nc',
  'ssh',
  'scp',
  'git clone',
  'git fetch',
  'git pull',
  'npm install',
  'pnpm install',
  'yarn install',
  'pip install',
  'dart pub get',
  'dart pub upgrade',
];

final _separators = RegExp(r'&&|\|\||;|\|');
final _assignment = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=\S*$');

/// A network command of §10.6: some segment (between `&&`, `||`, `;`, `|`,
/// without leading `VAR=x`) starts with one of the prefixes, compared by
/// words (`httpie` is not `http`).
bool isNetworkCommand(String command) {
  for (final segment in command.split(_separators)) {
    final words = segment.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    while (words.isNotEmpty && _assignment.hasMatch(words.first)) {
      words.removeAt(0);
    }
    for (final prefix in _networkPrefixes) {
      final parts = prefix.split(' ');
      if (words.length >= parts.length &&
          [
            for (var i = 0; i < parts.length; i++) words[i] == parts[i],
          ].every((e) => e)) {
        return true;
      }
    }
  }
  return false;
}
