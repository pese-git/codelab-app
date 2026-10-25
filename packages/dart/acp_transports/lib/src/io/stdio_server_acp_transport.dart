import 'dart:io';

import 'package:acp_protocol/acp_protocol.dart';

import '../acp_transport.dart';

final class StdioServerAcpTransport implements AcpTransport {
  StdioServerAcpTransport({Stream<List<int>>? input, IOSink? output});

  @override
  Stream<JsonRpcMessage> get inbound => throw UnimplementedError();

  @override
  Stream<AcpTransportEvent> get events => throw UnimplementedError();

  @override
  AcpTransportState get state => throw UnimplementedError();

  @override
  Future<void> start() => throw UnimplementedError();

  @override
  Future<void> send(JsonRpcMessage message) => throw UnimplementedError();

  @override
  Future<void> close({Duration? timeout}) => throw UnimplementedError();
}
