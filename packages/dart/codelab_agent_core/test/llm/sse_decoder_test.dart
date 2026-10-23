import 'dart:math';

import 'package:codelab_agent_core/src/llm/sse.dart';
import 'package:test/test.dart';

Future<List<ServerSentEvent>> _decode(List<String> chunks) =>
    Stream.fromIterable(chunks).transform(const SseDecoder()).toList();

List<String> _byChar(String text) => [for (final c in text.split('')) c];

List<String> _randomChunks(String text, Random random) {
  final chunks = <String>[];
  var i = 0;
  while (i < text.length) {
    final end = min(text.length, i + 1 + random.nextInt(7));
    chunks.add(text.substring(i, end));
    i = end;
  }
  return chunks;
}

Matcher _event(String data, {String? event, String? id}) =>
    isA<ServerSentEvent>()
        .having((e) => e.data, 'data', data)
        .having((e) => e.event, 'event', event)
        .having((e) => e.id, 'id', id);

const _stream =
    '﻿event: message_start\r\n'
    'data: {"a":1}\r\n'
    '\r\n'
    ': keep-alive\n'
    'id: 7\n'
    'data: line one\n'
    'data: line two\n'
    '\n'
    'data:no-space\r'
    '\r'
    'event: x\n'
    'data:  two spaces\n'
    '\n';

void main() {
  test('chunking does not change the result', () async {
    final whole = await _decode([_stream]);
    final byChar = await _decode(_byChar(_stream));
    final random = Random(42);
    final randomized = [
      for (var i = 0; i < 20; i++)
        await _decode(_randomChunks(_stream, random)),
    ];

    expect(whole, [
      _event('{"a":1}', event: 'message_start'),
      _event('line one\nline two', id: '7'),
      _event('no-space', id: '7'),
      _event(' two spaces', event: 'x', id: '7'),
    ]);
    expect(byChar.map((e) => e.toString()), whole.map((e) => e.toString()));
    for (final events in randomized) {
      expect(events.map((e) => e.toString()), whole.map((e) => e.toString()));
    }
  });

  test('the example of §2.6', () async {
    expect(
      await _decode([
        '﻿data: a\r',
        '\ndata:b\n\n: ping\n',
        'event: x\ndata: c\n\n',
      ]),
      [_event('a\nb'), _event('c', event: 'x')],
    );
  });

  test('CRLF split between chunks is one line break', () async {
    expect(await _decode(['data: a\r', '\n', '\r', '\n']), [_event('a')]);
  });

  test('a lone CR ends a line', () async {
    expect(await _decode(['data: a\rdata: b\r\r']), [_event('a\nb')]);
  });

  test('BOM is dropped only at the very start', () async {
    expect(await _decode(['', '﻿data: a\n\n']), [_event('a')]);
    expect(await _decode(['data: ﻿a\n\n']), [_event('﻿a')]);
  });

  test('comments are ignored', () async {
    expect(await _decode([': ping\n\n: x\ndata: a\n\n']), [_event('a')]);
  });

  test('an id with U+0000 is ignored, the id is kept between events', () async {
    expect(await _decode(['id: 1\ndata: a\n\nid: x\u0000y\ndata: b\n\n']), [
      _event('a', id: '1'),
      _event('b', id: '1'),
    ]);
  });

  test('a field without a colon has an empty value', () async {
    expect(await _decode(['data\n\n']), [_event('')]);
    expect(await _decode(['event\ndata: a\n\n']), [_event('a', event: '')]);
  });

  test('retry and unknown fields are ignored', () async {
    expect(await _decode(['retry: 10\nfoo: bar\ndata: a\n\n']), [_event('a')]);
  });

  test('an empty line without data dispatches nothing', () async {
    expect(await _decode(['event: x\n\n\ndata: a\n\n']), [_event('a')]);
  });

  test('an unfinished event at the end is dropped', () async {
    expect(await _decode(['data: a\n\ndata: b\n']), [_event('a')]);
    expect(await _decode(['data: a\n\ndata: b']), [_event('a')]);
  });
}
