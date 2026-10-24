import 'dart:convert';

/// Truncation of tool output (`agent-core-architecture` §6.3.5): a result
/// never exceeds the limits and always says so (TOOL-9). `null` means «no
/// limit» — not a big shift, since `1 << 62 == 0` in dart2js.

const defaultMaxLines = 2000;
const defaultMaxBytes = 50 * 1024;
const lineTruncatedSuffix = ' [line truncated]';

final class Truncated {
  const Truncated({
    required this.text,
    required this.truncated,
    required this.keptLines,
    required this.totalLines,
  });

  final String text;
  final bool truncated;
  final int keptLines, totalLines;
}

/// Takes whole lines from the start while neither limit is exceeded; a
/// first line longer than [maxBytes] is cut at a character boundary.
Truncated truncateHead(
  String text, {
  int? maxLines = defaultMaxLines,
  int? maxBytes = defaultMaxBytes,
}) => _truncate(text, maxLines, maxBytes, fromEnd: false);

/// The same from the end: errors are usually at the end of a command
/// output.
Truncated truncateTail(
  String text, {
  int? maxLines = defaultMaxLines,
  int? maxBytes = defaultMaxBytes,
}) => _truncate(text, maxLines, maxBytes, fromEnd: true);

Truncated _truncate(
  String text,
  int? maxLines,
  int? maxBytes, {
  required bool fromEnd,
}) {
  final lines = text.split('\n');
  final total = lines.length;
  final kept = <String>[];
  var bytes = 0;
  var cut = false;
  for (var i = 0; i < total; i++) {
    final line = lines[fromEnd ? total - 1 - i : i];
    if (maxLines != null && kept.length >= maxLines) {
      break;
    }
    final size = utf8.encode(line).length + (kept.isEmpty ? 0 : 1);
    if (maxBytes != null && bytes + size > maxBytes) {
      if (kept.isEmpty) {
        kept.add(_cutLine(line, maxBytes));
        cut = true;
      }
      break;
    }
    kept.add(line);
    bytes += size;
  }
  final ordered = fromEnd ? kept.reversed.toList() : kept;
  return Truncated(
    text: ordered.join('\n'),
    truncated: cut || kept.length < total,
    keptLines: kept.length,
    totalLines: total,
  );
}

/// Cuts [line] so that it with [lineTruncatedSuffix] fits in [maxBytes].
String _cutLine(String line, int maxBytes) {
  final budget = maxBytes - utf8.encode(lineTruncatedSuffix).length;
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in line.runes) {
    final size = utf8.encode(String.fromCharCode(rune)).length;
    if (bytes + size > budget) {
      break;
    }
    out.writeCharCode(rune);
    bytes += size;
  }
  return '$out$lineTruncatedSuffix';
}

/// Notice lines of §6.3.5: they say how to get the rest.
abstract final class TruncationNotices {
  static String read({required int first, required int last, int? total}) =>
      total == null
      ? '[Showing lines $first-$last. More lines may follow: '
            'use offset=${last + 1}.]'
      : '[Showing lines $first-$last of $total. '
            'Use offset=${last + 1} to continue.]';

  static String ls({required int shown, required int total}) =>
      '[Showing $shown of $total entries. Use a more specific path.]';

  static String search({int limit = 100}) =>
      '[Showing first $limit matches. Narrow the pattern or the glob.]';

  static String exec({required int kept, required int total}) =>
      '[Output truncated: showing the last $kept lines of $total.]';

  /// The generic notice of the execution point for a tool that did not
  /// truncate itself.
  static String head({required int kept, required int total}) =>
      '[Output truncated: showing the first $kept lines of $total.]';
}
