import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_transports/io.dart';
import 'package:test/test.dart';

/// Серверный stdio-транспорт агента (agent-transports «Серверные
/// транспорты ACP»; design.md change `add-codelab-agent-binary`, D2): потоки
/// процесса подменены потоками в памяти.
void main() {
  late StreamController<List<int>> input;
  late _Output output;
  late StdioServerAcpTransport transport;

  setUp(() async {
    input = StreamController<List<int>>();
    output = _Output();
    transport = StdioServerAcpTransport(
      input: input.stream,
      output: output.sink,
    );
    await transport.start();
  });

  tearDown(() async {
    if (!input.isClosed) {
      await input.close();
    }
    await transport.close();
  });

  void writeLine(String line) => input.add(utf8.encode('$line\n'));

  test('a 2 MiB line is read as one message', () async {
    final text = 'x' * (2 * 1024 * 1024);
    final received = transport.inbound.first;

    // Строка приходит кусками, как из настоящего pipe.
    final bytes = utf8.encode(
      '${jsonEncode({
        'jsonrpc': '2.0',
        'method': 'note',
        'params': {'text': text},
      })}\n',
    );
    for (var i = 0; i < bytes.length; i += 65536) {
      input.add(bytes.sublist(i, (i + 65536).clamp(0, bytes.length)));
    }

    final message = await received as JsonRpcNotification;
    expect((message.params! as Map)['text'], hasLength(text.length));
  });

  test('empty lines are skipped without an answer', () async {
    final received = transport.inbound.first;
    writeLine('');
    writeLine('   ');
    writeLine('{"jsonrpc":"2.0","method":"note"}');

    expect(await received, isA<JsonRpcNotification>());
    expect(output.lines, isEmpty);
  });

  test('1 000 messages are written whole and in order', () async {
    final sends = [
      for (var i = 0; i < 1000; i++)
        transport.send(
          JsonRpcMessage.notification(method: 'note', params: {'n': i}),
        ),
    ];
    await Future.wait(sends);
    await output.untilCount(1000);

    expect(output.lines, hasLength(1000));
    for (var i = 0; i < 1000; i++) {
      final frame = jsonDecode(output.lines[i]) as Map<String, Object?>;
      expect((frame['params']! as Map)['n'], i);
    }
  });

  test('EOF closes inbound and the transport', () async {
    final done = transport.inbound.toList();
    writeLine('{"jsonrpc":"2.0","method":"note"}');
    await input.close();

    expect(await done, hasLength(1));
    expect(transport.state, AcpTransportState.closed);
  });

  test('unparsable JSON gets -32700 with id null', () async {
    final diagnostics = transport.events
        .where((e) => e is AcpTransportDiagnostic)
        .cast<AcpTransportDiagnostic>()
        .first;
    writeLine('{"jsonrpc": "2.0", "id": 1,');
    await output.next();

    final answer = jsonDecode(output.lines.single) as Map<String, Object?>;
    expect(answer['id'], isNull);
    expect((answer['error']! as Map)['code'], jsonRpcParseErrorCode);
    expect(
      (await diagnostics).severity,
      AcpTransportDiagnosticSeverity.warning,
    );
  });

  test('a frame without jsonrpc gets -32600 with its id', () async {
    writeLine('{"id": 7, "method": "initialize"}');
    await output.next();

    final answer = jsonDecode(output.lines.single) as Map<String, Object?>;
    expect(answer['id'], 7);
    expect((answer['error']! as Map)['code'], jsonRpcInvalidRequestCode);
  });

  test('a JSON value that is not an object gets -32600 with id null', () async {
    writeLine('[1, 2]');
    await output.next();

    final answer = jsonDecode(output.lines.single) as Map<String, Object?>;
    expect(answer['id'], isNull);
    expect((answer['error']! as Map)['code'], jsonRpcInvalidRequestCode);
  });

  test('the connection lives after a bad frame', () async {
    final received = transport.inbound.first;
    writeLine('not json');
    writeLine('{"jsonrpc":"2.0","id":2,"method":"initialize","params":{}}');

    final message = await received as JsonRpcRequest;
    expect(message.id, const JsonRpcId.integer(2));
    expect(transport.state, AcpTransportState.connected);
  });
}

/// Выход транспорта в памяти: строки, записанные в `IOSink`.
final class _Output {
  _Output() {
    _controller.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          lines.add(line);
          _waiter?.complete();
          _waiter = null;
        });
  }

  final _controller = StreamController<List<int>>();
  late final IOSink sink = IOSink(_controller.sink);
  final lines = <String>[];
  Completer<void>? _waiter;

  /// Ждёт следующей строки.
  Future<void> next() => (_waiter = Completer<void>()).future;

  /// Ждёт, пока декодер разберёт [count] строк (не дольше 5 с).
  Future<void> untilCount(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (lines.length < count && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}
