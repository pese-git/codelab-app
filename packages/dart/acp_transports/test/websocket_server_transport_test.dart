import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:acp_transports/io.dart';
import 'package:test/test.dart';

/// Серверный WebSocket-транспорт агента (agent-transports «Серверные
/// транспорты ACP»; design.md change `add-codelab-agent-binary`, D2):
/// настоящий `HttpServer` на loopback и клиент `WebSocketAcpTransport`.
void main() {
  late HttpServer http;
  late Future<WebSocketServerAcpTransport> accepted;

  setUp(() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completer = Completer<WebSocketServerAcpTransport>();
    accepted = completer.future;
    http.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      final transport = WebSocketServerAcpTransport(socket);
      await transport.start();
      completer.complete(transport);
    });
  });

  tearDown(() async {
    await http.close(force: true);
  });

  Uri endpoint() => Uri.parse('ws://127.0.0.1:${http.port}/acp');

  test('a text frame is one message in both directions', () async {
    final client = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(uri: endpoint()),
    );
    await client.start();
    final server = await accepted;

    final atServer = server.inbound.first;
    await client.send(
      const JsonRpcMessage.request(
        id: JsonRpcId.integer(1),
        method: 'initialize',
        params: {'protocolVersion': 1},
      ),
    );
    expect(await atServer, isA<JsonRpcRequest>());

    final atClient = client.inbound.first;
    await server.send(
      const JsonRpcMessage.response(id: JsonRpcId.integer(1), result: {}),
    );
    expect(await atClient, isA<JsonRpcResponse>());

    await client.close();
    await server.close();
  });

  test('binary and unparsable frames get errors; the socket lives', () async {
    final socket = await WebSocket.connect(endpoint().toString());
    final server = await accepted;
    final answers = StreamIterator(socket.cast<Object?>());

    socket.add(utf8.encode('{"jsonrpc":"2.0","method":"note"}'));
    expect(await answers.moveNext(), isTrue);
    final binary = jsonDecode(answers.current! as String) as Map;
    expect((binary['error']! as Map)['code'], jsonRpcInvalidRequestCode);

    socket.add('{"jsonrpc": "2.0",');
    expect(await answers.moveNext(), isTrue);
    final parse = jsonDecode(answers.current! as String) as Map;
    expect(parse['id'], isNull);
    expect((parse['error']! as Map)['code'], jsonRpcParseErrorCode);

    final received = server.inbound.first;
    socket.add('{"jsonrpc":"2.0","method":"note"}');
    expect(await received, isA<JsonRpcNotification>());

    await socket.close();
    await answers.cancel();
    await server.close();
  });

  test('closing the client socket closes inbound', () async {
    final socket = await WebSocket.connect(endpoint().toString());
    final server = await accepted;
    final done = server.inbound.toList();

    await socket.close();

    expect(await done, isEmpty);
    expect(server.state, AcpTransportState.closed);
  });
}
