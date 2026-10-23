import 'dart:async';

/// One server-sent event (`agent-core-architecture` §2.6).
final class ServerSentEvent {
  const ServerSentEvent({this.event, required this.data, this.id});

  /// The `event:` field; `null` means `message`.
  final String? event;

  /// `data:` lines joined with `\n`.
  final String data;
  final String? id;

  @override
  String toString() => 'ServerSentEvent(event: $event, id: $id, data: $data)';
}

/// Decodes a stream of text chunks into [ServerSentEvent]s by the rules of
/// §2.6. The UTF-8 decoding happens upstream
/// (`Utf8Decoder(allowMalformed: true)`), which also joins multi-byte
/// characters split between chunks.
///
/// * Lines end with `\n`, `\r` or `\r\n`; a `\r\n` split between chunks is
///   one line break.
/// * `U+FEFF` is dropped only as the very first character of the stream.
/// * Lines starting with `:` are comments (provider keep-alive).
/// * A line splits at its first `:`; without one the whole line is the field
///   name with an empty value; exactly one leading space of the value is
///   dropped.
/// * `event` sets the type, `data` adds a line, `id` is kept unless it
///   contains `U+0000`; `retry` and other fields are ignored.
/// * An empty line dispatches the event if it has data and resets `event`
///   and the data; `id` persists.
/// * An unfinished line or event at the end of the stream is dropped.
final class SseDecoder extends StreamTransformerBase<String, ServerSentEvent> {
  const SseDecoder();

  @override
  Stream<ServerSentEvent> bind(Stream<String> source) async* {
    final line = StringBuffer();
    final data = <String>[];
    String? event;
    String? id;
    var skipLf = false;
    var atStart = true;

    ServerSentEvent? feed(String text) {
      if (text.isEmpty) {
        if (data.isEmpty) {
          event = null;
          return null;
        }
        final dispatched = ServerSentEvent(
          event: event,
          data: data.join('\n'),
          id: id,
        );
        data.clear();
        event = null;
        return dispatched;
      }
      if (text.startsWith(':')) {
        return null;
      }
      final colon = text.indexOf(':');
      final field = colon < 0 ? text : text.substring(0, colon);
      var value = colon < 0 ? '' : text.substring(colon + 1);
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
      switch (field) {
        case 'event':
          event = value;
        case 'data':
          data.add(value);
        case 'id':
          if (!value.contains('\u0000')) {
            id = value;
          }
      }
      return null;
    }

    await for (final chunk in source) {
      var start = 0;
      if (atStart && chunk.isNotEmpty) {
        atStart = false;
        if (chunk.codeUnitAt(0) == 0xFEFF) {
          start = 1;
        }
      }
      var segment = start;
      for (var i = start; i < chunk.length; i++) {
        final c = chunk.codeUnitAt(i);
        if (skipLf) {
          skipLf = false;
          if (c == 0x0A) {
            segment = i + 1;
            continue;
          }
        }
        if (c == 0x0A || c == 0x0D) {
          skipLf = c == 0x0D;
          line.write(chunk.substring(segment, i));
          segment = i + 1;
          final dispatched = feed(line.toString());
          line.clear();
          if (dispatched != null) {
            yield dispatched;
          }
        }
      }
      if (segment < chunk.length) {
        line.write(chunk.substring(segment));
      }
    }
  }
}
