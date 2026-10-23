import 'dart:convert';

/// The ring buffer of a command output (`agent-core-architecture` §4.6,
/// step 4): stdout and stderr in the order of arrival, at most [limit]
/// UTF-8 bytes; on overflow the beginning is dropped at a character
/// boundary and [truncated] is set.
final class OutputBuffer {
  OutputBuffer(this.limit);

  final int limit;
  final _chunks = <String>[];
  var _bytes = 0;
  var truncated = false;

  void add(String chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _chunks.add(chunk);
    _bytes += utf8.encode(chunk).length;
    while (_bytes > limit && _chunks.isNotEmpty) {
      truncated = true;
      final first = _chunks.first;
      final firstBytes = utf8.encode(first).length;
      if (_bytes - firstBytes >= limit) {
        _chunks.removeAt(0);
        _bytes -= firstBytes;
        continue;
      }
      final keep = _dropHead(first, _bytes - limit);
      _bytes -= firstBytes - utf8.encode(keep).length;
      _chunks[0] = keep;
    }
  }

  String get text => _chunks.join();

  /// The last [bytes] UTF-8 bytes of [text], cut at a character boundary.
  String tail(int bytes) {
    final all = text;
    final size = utf8.encode(all).length;
    return size <= bytes ? all : _dropHead(all, size - bytes);
  }

  /// [text] without at least [bytes] leading UTF-8 bytes.
  static String _dropHead(String text, int bytes) {
    var dropped = 0;
    var index = 0;
    final runes = text.runes.toList();
    while (index < runes.length && dropped < bytes) {
      dropped += utf8.encode(String.fromCharCode(runes[index])).length;
      index++;
    }
    return String.fromCharCodes(runes.sublist(index));
  }
}
