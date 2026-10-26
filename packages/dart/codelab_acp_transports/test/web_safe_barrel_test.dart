import 'dart:io';

import 'package:codelab_acp_transports/io.dart';
import 'package:test/test.dart';

/// URIs that pull in `dart:io` and therefore break web compilation.
const _ioUris = ['dart:io', 'package:web_socket_channel/io.dart'];

final _directive = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''');
final _conditional = RegExp(r'''if\s*\([^)]*\)\s*['"]([^'"]+)['"]''');

/// Follows package-local `import`/`export`/`part` directives starting at
/// [entry] and returns every `dart:io`-bound URI reached, as
/// `file -> uri`.
List<String> _ioReachableFrom(String entry) {
  final seen = <String>{};
  final hits = <String>[];
  final pending = [File(entry).absolute.path];
  final libDir = Directory('lib').absolute.path;

  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!seen.add(path)) continue;
    for (final line in File(path).readAsLinesSync()) {
      final uris = [
        for (final m in _directive.allMatches(line)) m.group(1)!,
        for (final m in _conditional.allMatches(line)) m.group(1)!,
      ];
      for (final uri in uris) {
        if (_ioUris.contains(uri)) {
          hits.add('${File(path).uri.pathSegments.last} -> $uri');
        } else if (uri.startsWith('package:codelab_acp_transports/')) {
          pending.add(
            '$libDir/${uri.substring('package:codelab_acp_transports/'.length)}',
          );
        } else if (!uri.contains(':')) {
          pending.add(File(path).parent.uri.resolve(uri).toFilePath());
        }
      }
    }
  }
  return hits;
}

void main() {
  for (final entry in [
    'lib/codelab_acp_transports.dart',
    'lib/src/transport_configs.dart',
  ]) {
    test('$entry does not reach dart:io', () {
      expect(File(entry).existsSync(), isTrue, reason: '$entry is missing');
      final hits = _ioReachableFrom(entry);
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  }

  test('io.dart exposes the dart:io transports', () {
    expect(<Type>[StdioAcpTransport, WebSocketAcpTransport], hasLength(2));
  });
}
